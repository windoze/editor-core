import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoLanguageCrossLanguageExperienceTests: XCTestCase {
    func testDerivedStateAndStatusBarAcrossLanguageSources() throws {
        let cases: [LanguageCase] = [
            LanguageCase(
                fileName: "main.rs",
                languageId: "rust",
                source: .lspSemantic,
                symbolName: "RustEntry",
                expectedStatusText: "LSP semantic",
                expectedTooltipSnippets: [
                    "Language source: LSP semantic tokens (rust)",
                    "Highlighting: LSP semantic tokens",
                    "Semantic tokens: LSP semantic tokens",
                    "Diagnostics: LSP diagnostics",
                    "Symbols: LSP symbols",
                ],
                semanticTokenData: [0, 4, 5, 7, 0]
            ),
            LanguageCase(
                fileName: "App.swift",
                languageId: "swift",
                source: .lspTreeSitter,
                symbolName: "SwiftEntry",
                expectedStatusText: "LSP + Tree-sitter",
                expectedTooltipSnippets: [
                    "Language source: LSP language services plus Tree-sitter syntax (swift)",
                    "Highlighting: Tree-sitter",
                    "Diagnostics: LSP diagnostics",
                    "Symbols: LSP symbols",
                    "Folding: Tree-sitter folds",
                    "Fallback: LSP semantic tokens are unavailable. Tree-sitter syntax fallback is active.",
                ],
                fallbackReasons: [
                    "LSP semantic tokens are unavailable. Tree-sitter syntax fallback is active.",
                ]
            ),
            LanguageCase(
                fileName: "notes.md",
                languageId: "markdown",
                source: .sublimeSyntax,
                symbolName: "MarkdownEntry",
                expectedStatusText: "Sublime baseline",
                expectedTooltipSnippets: [
                    "Language source: Sublime syntax baseline (markdown)",
                    "Highlighting: Sublime syntax",
                    "Semantic tokens: unavailable",
                    "Diagnostics: unavailable",
                    "Symbols: unavailable",
                    "Folding: Sublime folds",
                ]
            ),
        ]

        for testCase in cases {
            try runLanguageCase(testCase)
        }
    }

    private func runLanguageCase(_ testCase: LanguageCase) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoLanguageCrossLanguageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent(testCase.fileName)
        try """
        let value = 1
        let other = value
        """.write(to: file, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: root)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertTrue(vc.openFile(url: file, mode: .pinned), testCase.fileName)
        let tab = try XCTUnwrap(vc.tabs.first, testCase.fileName)
        tab.syntaxLanguageId = testCase.languageId
        tab.languageSupportSource = testCase.source
        tab.languageFallbackReasons = testCase.fallbackReasons
        vc.applyLanguageConfiguration(for: tab)

        try applyDiagnostics(to: tab, file: file, message: "\(testCase.languageId) diagnostic")
        XCTAssertTrue(applyFoldingRange(to: vc, tab: tab), testCase.fileName)
        XCTAssertTrue(applyDocumentSymbol(to: vc, symbolName: testCase.symbolName), testCase.fileName)
        try applySemanticTokensIfNeeded(to: vc, testCase: testCase)

        vc._updateStatusBarForTesting()

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.diagnostics.diagnostics.map(\.message), ["\(testCase.languageId) diagnostic"])
        XCTAssertEqual(snapshot.foldingRegions.regions.filter(\.isCollapsed).count, 1)
        XCTAssertEqual(vc._workspaceOutlineSnapshotForTesting().symbols.map(\.name), [testCase.symbolName])

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view), testCase.fileName)
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let statusText = labels.map(\.stringValue).joined(separator: "\n")
        XCTAssertTrue(statusText.contains("Problems: 1"), "\(testCase.fileName): \(statusText)")
        XCTAssertTrue(statusText.contains("Folded: 1"), "\(testCase.fileName): \(statusText)")

        let sourceLabel = try XCTUnwrap(labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarLanguageSourceLabel
        }, testCase.fileName)
        XCTAssertEqual(sourceLabel.stringValue, testCase.expectedStatusText, testCase.fileName)
        let tooltip = try XCTUnwrap(sourceLabel.toolTip, testCase.fileName)
        for snippet in testCase.expectedTooltipSnippets {
            XCTAssertTrue(tooltip.contains(snippet), "\(testCase.fileName): \(tooltip)")
        }
    }

    private func applyDiagnostics(to tab: AttoEditorTab, file: URL, message: String) throws {
        try tab.editCore.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(file.standardizedFileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "severity": 2,
              "message": "\(message)"
            }
          ],
          "version": 1
        }
        """)
    }

    private func applyFoldingRange(to vc: AttoEditorAreaViewController, tab: AttoEditorTab) -> Bool {
        guard vc.applyFoldingRangesResultJSONToActiveTab(
            #"[{"startLine":0,"endLine":1,"kind":"region"}]"#
        ) else {
            return false
        }
        do {
            try tab.editCore.editor.fold(startLine: 0, endLine: 1)
            return true
        } catch {
            return false
        }
    }

    private func applyDocumentSymbol(to vc: AttoEditorAreaViewController, symbolName: String) -> Bool {
        vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "\(symbolName)",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 1, "character": 17 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 4 },
              "end": { "line": 0, "character": 9 }
            }
          }
        ]
        """)
    }

    private func applySemanticTokensIfNeeded(
        to vc: AttoEditorAreaViewController,
        testCase: LanguageCase
    ) throws {
        guard let semanticTokenData = testCase.semanticTokenData else { return }
        let data = semanticTokenData.map(String.init).joined(separator: ", ")
        let result = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "\(testCase.languageId)-semantic-1",
          "data": [\(data)]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(result), testCase.fileName)
        let semanticLayer = try XCTUnwrap(
            vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 },
            testCase.fileName
        )
        let interval = try XCTUnwrap(semanticLayer.intervals.first, testCase.fileName)
        XCTAssertEqual(interval.start, 4, testCase.fileName)
        XCTAssertEqual(interval.end, 9, testCase.fileName)
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        var out: [NSView] = []
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            out.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return out
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }

    private struct LanguageCase {
        let fileName: String
        let languageId: String
        let source: AttoLanguageSupportSource
        let symbolName: String
        let expectedStatusText: String
        let expectedTooltipSnippets: [String]
        var fallbackReasons: [String] = []
        var semanticTokenData: [UInt32]? = nil
    }
}
