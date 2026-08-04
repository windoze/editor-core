import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoStatusBarSelectionTests: XCTestCase {
    func testStatusBarShowsSelectionRangeAndSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.txt")
        try "ab\ncde\nf".write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        editorView.doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        editorView.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let selection = labels.first(where: { $0.stringValue.hasPrefix("Sel ") })?.stringValue

        let text = try XCTUnwrap(selection)
        XCTAssertTrue(text.contains("Sel 1"), "expected selection size to be shown")
        XCTAssertTrue(text.contains("(1:1-1:2)"), "expected selection range (Ln:Col) to be shown")
    }

    func testStatusBarMetadataUsesCoreDocumentURIProjection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("status-local.txt")
        let projected = root.appendingPathComponent("status-projected.rs")
        let projectedText = "0123456789\n"
        try "local".write(to: file, atomically: true, encoding: .utf8)
        try projectedText.write(to: projected, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)
        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projected.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, file.standardizedFileURL)

        vc._updateStatusBarForTesting()

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let fileSizeLabel = try XCTUnwrap(labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarFileSizeLabel
        })
        XCTAssertEqual(fileSizeLabel.stringValue, AttoFormat.byteCount(Int64(projectedText.utf8.count)))

        let lspLabel = try XCTUnwrap(labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarLspLabel
        })
        XCTAssertFalse(lspLabel.stringValue.isEmpty)
    }

    func testStatusBarShowsLanguageSourceIndicator() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarLanguageSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("plain.noattofallback")
        try "plain".write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)
        let tab = try XCTUnwrap(vc.tabs.first)
        tab.languageSupportSource = .treeSitter
        tab.syntaxLanguageId = "rust"
        tab.languageFallbackReasons = ["No LSP server is configured for .rs."]
        vc._updateStatusBarForTesting()

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let sourceLabel = try XCTUnwrap(labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarLanguageSourceLabel
        })
        XCTAssertEqual(sourceLabel.stringValue, "Tree-sitter")
        let tooltip = try XCTUnwrap(sourceLabel.toolTip)
        XCTAssertTrue(tooltip.contains("Language source: Tree-sitter syntax (rust)"), tooltip)
        XCTAssertTrue(tooltip.contains("Highlighting: Tree-sitter"), tooltip)
        XCTAssertTrue(tooltip.contains("Folding: Tree-sitter folds"), tooltip)
        XCTAssertTrue(tooltip.contains("Fallback: No LSP server is configured for .rs."), tooltip)
    }

    func testStatusBarConsumesActiveDerivedDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarDerivedStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.txt")
        try "abc\n".write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let diagnostics = """
        {
          "uri": "\(file.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 1 }
              },
              "severity": 2,
              "message": "first warning"
            }
          ],
          "version": 1
        }
        """
        try editorView.editor.lspApplyDiagnosticsJSON(diagnostics)

        let refreshCountBeforeDrain = vc._derivedStateSnapshotRefreshCountForTesting()
        let sequenceBeforeDrain = vc._derivedStateEventSequenceForTesting()
        vc._updateStatusBarForTesting()

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.diagnostics.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].message, "first warning")
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].severity, .warning)
        XCTAssertTrue(vc._derivedStateEventSequenceForTesting() > sequenceBeforeDrain)
        XCTAssertTrue(vc._derivedStateEventKindsForTesting().contains(.derivedStateChanged))
        XCTAssertEqual(vc._derivedStateSnapshotRefreshCountForTesting(), refreshCountBeforeDrain + 1)
        XCTAssertFalse(vc._activeDerivedStateIsStaleForTesting())
        XCTAssertEqual(
            vc._activeMinimapDiagnosticMarkersForTesting(),
            [EditorCoreSkiaMinimapMarker(logicalLine: 0, kind: .warning)]
        )
        XCTAssertEqual(
            vc._activeGutterDiagnosticMarkersForTesting(),
            [EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 0, charOffset: 0, kind: .warning)]
        )

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue == "Problems: 1" })

        let refreshCountAfterDrain = vc._derivedStateSnapshotRefreshCountForTesting()
        vc._updateStatusBarForTesting()
        XCTAssertTrue(vc._derivedStateEventKindsForTesting().isEmpty)
        XCTAssertEqual(vc._derivedStateSnapshotRefreshCountForTesting(), refreshCountAfterDrain)

        try editorView.editor.insertText("z")
        vc._updateStatusBarForTesting()
        XCTAssertTrue(vc._derivedStateEventKindsForTesting().contains(.derivedStateStale))
        XCTAssertTrue(vc._activeDerivedStateIsStaleForTesting())
    }

    func testStatusBarConsumesLspStatusStateEvent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarLspStatusStateEventTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("main.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let captureURL = root.appendingPathComponent("lsp-stdin.txt")
        let scriptURL = root.appendingPathComponent("fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: root.standardizedFileURL.absoluteString,
            documentURI: file.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        vc._updateStatusBarForTesting()

        let status = try XCTUnwrap(vc._activeLspStatusForTesting())
        XCTAssertEqual(status.availability, .enabled)
        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(
            status.workspaceFolders.first?.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            root.standardizedFileURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
        XCTAssertTrue(vc._derivedStateEventKindsForTesting().contains(.lspStatusChanged))

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let lspText = labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarLspLabel
        }?.stringValue
        let text = try XCTUnwrap(lspText)
        XCTAssertTrue(text.contains("LSP"), text)
        XCTAssertTrue(text.contains("Ready"), text)
        XCTAssertTrue(text.contains("@ \(root.lastPathComponent)"), text)
    }

    func testStatusBarConsumesFoldedDerivedState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarFoldingStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("folds.txt")
        try """
        import A
        import B
        let value = 1
        """.write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertTrue(
            vc.applyFoldingRangesResultJSONToActiveTab(
                #"[{"startLine":0,"endLine":1,"kind":"imports"}]"#
            )
        )
        try editorView.editor.fold(startLine: 0, endLine: 1)

        vc._updateStatusBarForTesting()

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.foldingRegions.regions.filter { $0.isCollapsed }.count, 1)

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue == "Folded: 1" })
    }

    func testStatusBarConsumesCodeLensDerivedState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarCodeLensStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("lens.swift")
        try """
        func one() {}
        func two() {}
        """.write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyCodeLensJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": { "title": "Run One", "command": "test.runOne" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """)

        vc._updateStatusBarForTesting()

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(AttoLspCodeLensParser.items(fromDecorationsSnapshot: snapshot.decorations).count, 2)

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue == "Code Lens: 2" })
    }

    private func writeFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        body='{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}'
        printf 'Content-Length: %s\\r\\n\\r\\n%s' "${#body}" "$body"
        cat > '\(capturePath)'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
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
}
