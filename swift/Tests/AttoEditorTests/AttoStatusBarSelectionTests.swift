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

        vc._updateStatusBarForTesting()

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.diagnostics.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].message, "first warning")
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].severity, .warning)
        XCTAssertEqual(
            vc._activeMinimapDiagnosticMarkersForTesting(),
            [EditorCoreSkiaMinimapMarker(logicalLine: 0, kind: .warning)]
        )

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue == "Problems: 1" })
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
