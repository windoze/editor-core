import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorChromePolishLayoutTests: XCTestCase {
    func testNarrowChromeControlsClampLongContentWithoutHorizontalOverflow() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let longName = "very-long-project-path-component-with-symbols-and-status-overflow-fixture.rs"
        let fileURL = tempDir.appendingPathComponent(longName)
        try "fn narrow_chrome_fixture() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc, size: NSSize(width: 520, height: 360))
        defer { window.close() }

        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned, location: nil))
        vc.showReplaceBar()
        vc.statusBarView.update(
            leftText: "Indexing \(longName) with a deliberately long transient status message",
            languageSourceText: "LSP semantic tokens with fallback details",
            languageSourceTooltip: "Long language source tooltip",
            languageId: nil,
            languageIsEnabled: true,
            lspText: "LSP running: rust-analyzer with workspace folders and delayed diagnostics",
            positionText: "Ln 1200, Col 200",
            selectionText: "12 cursors",
            fileSizeText: "128 KB"
        )
        vc.view.layoutSubtreeIfNeeded()

        let opened = try XCTUnwrap(vc.openFileItems().first)
        let tabChip = try XCTUnwrap(findView(identifier: AttoAccessibilityID.tabChip(opened.id), in: vc.view))
        XCTAssertLessThanOrEqual(tabChip.frame.width, 221)
        assertStatusBarLabelsStayInsideStatusBar(vc.statusBarView)

        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findSearchField, in: vc.findReplaceBarView) as? NSSearchField
        )
        let replaceField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findReplaceField, in: vc.findReplaceBarView) as? NSTextField
        )
        assertFrameInside(searchField, vc.findReplaceBarView)
        assertFrameInside(replaceField, vc.findReplaceBarView)
        XCTAssertGreaterThanOrEqual(searchField.frame.width, 140)
        XCTAssertLessThanOrEqual(searchField.frame.width, 360)
        XCTAssertGreaterThanOrEqual(replaceField.frame.width, 120)
        XCTAssertLessThanOrEqual(replaceField.frame.width, 320)
    }

    func testFloatingPanelsClampToNarrowWindowWidth() throws {
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        let window = NSWindow(
            contentRect: hostView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }
        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)

        let palette = AttoCommandPaletteController(accessibilityPrefix: "AttoEditor.NarrowPalette") {
            [
                AttoCommandPaletteCommand(id: "test.long", title: "A very long command title that should truncate") {},
            ]
        }
        defer { palette.hide() }
        palette.show(relativeTo: window)

        let palettePanel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertLessThanOrEqual(palettePanel.frame.width, window.frame.width)
        XCTAssertGreaterThanOrEqual(palettePanel.frame.width, 340)

        palette.hide()

        let completionItems = AttoLspCompletionParser.items(
            fromCompletionResultJSON: #"{"items":[{"label":"veryLongCompletionCandidateName","kind":3,"detail":"fn","documentation":"Detailed completion preview"}]}"#
        )
        XCTAssertFalse(completionItems.isEmpty)

        let completion = AttoCompletionListController()
        defer { completion.hide() }
        completion.show(
            items: completionItems,
            relativeTo: hostView,
            anchorRect: NSRect(x: 18, y: 240, width: 12, height: 18)
        ) { _, _ in }

        let completionPanel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertLessThanOrEqual(completionPanel.frame.width, window.frame.width)
        XCTAssertGreaterThanOrEqual(completionPanel.frame.width, 360)
        let completionRoot = try XCTUnwrap(completionPanel.contentView)
        let tableScroll = try XCTUnwrap(findView(identifier: AttoAccessibilityID.completionScrollView, in: completionRoot))
        let preview = try XCTUnwrap(findView(identifier: AttoAccessibilityID.completionPreviewScrollView, in: completionRoot))
        assertFrameInside(tableScroll, completionRoot)
        assertFrameInside(preview, completionRoot)
        let tableFrame = tableScroll.convert(tableScroll.bounds, to: completionRoot)
        let previewFrame = preview.convert(preview.bounds, to: completionRoot)
        XCTAssertLessThanOrEqual(tableFrame.maxX, previewFrame.minX + 1)
    }

    func testSidebarMinimapAndGutterMarkersStayInsideMinimumWindowChrome() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("sidebar-minimap-gutter.txt")
        let lines = (0..<80)
            .map { "line \($0) with enough content to exercise minimap density and gutter markers" }
        let text = lines.joined(separator: "\n")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let context = AttoWindowContext(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            configurationSnapshot: makeConfigurationSnapshot(workspaceRootURL: tempDir),
            contentSize: AttoWindowSizing.minimumContentSize
        )
        defer { context.window.close() }

        context.show(center: false)
        XCTAssertTrue(context.editorAreaController.openFile(url: fileURL, mode: .pinned, location: nil))
        context.window.contentView?.layoutSubtreeIfNeeded()

        let splitView = context.splitViewController.splitView
        splitView.layoutSubtreeIfNeeded()
        let sidebar = context.sidebarController.view
        let editorArea = context.editorAreaController.view
        assertFrameInside(sidebar, splitView)
        assertFrameInside(editorArea, splitView)

        let sidebarFrame = sidebar.convert(sidebar.bounds, to: splitView)
        let editorFrame = editorArea.convert(editorArea.bounds, to: splitView)
        XCTAssertGreaterThanOrEqual(sidebarFrame.width, 180)
        XCTAssertGreaterThanOrEqual(editorFrame.width, 320)
        XCTAssertLessThanOrEqual(sidebarFrame.maxX, editorFrame.minX + 1)

        let sidebarTabBar = try XCTUnwrap(findView(identifier: AttoAccessibilityID.sidebarTabBar, in: sidebar))
        let sidebarContent = try XCTUnwrap(findView(identifier: AttoAccessibilityID.sidebarContentHost, in: sidebar))
        assertFrameInside(sidebarTabBar, sidebar)
        assertFrameInside(sidebarContent, sidebar)
        XCTAssertLessThanOrEqual(sidebarContent.frame.maxY, sidebarTabBar.frame.minY + 1)

        let opened = try XCTUnwrap(context.editorAreaController.openFileItems().first)
        let pane = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.editorPane(opened.id), in: editorArea) as? EditCoreUI
        )
        pane.showsMinimap = true
        pane.minimapWidth = 72
        pane.minimapDiagnosticMarkers = [
            EditorCoreSkiaMinimapMarker(logicalLine: 3, kind: .warning),
            EditorCoreSkiaMinimapMarker(logicalLine: 45, kind: .error),
        ]
        pane.layoutSubtreeIfNeeded()
        context.window.makeFirstResponder(pane.editorView)
        pane.editorView.needsDisplay = true
        pane.editorView.displayIfNeeded()
        let gutterMarkers = visibleGutterMarkers(lineStartOffsets: lineStartOffsets(for: lines))
        pane.gutterDiagnosticMarkers = gutterMarkers

        let minimapContainer = try XCTUnwrap(findSubview(of: EditorCoreSkiaMinimapContainer.self, in: pane))
        let minimap = try XCTUnwrap(findSubview(of: EditorCoreSkiaMinimapView.self, in: pane))
        assertFrameInside(minimapContainer, pane)
        assertFrameInside(minimap, pane)
        XCTAssertFalse(minimap.isHidden)
        XCTAssertEqual(minimap.frame.width, 72, accuracy: 1)
        XCTAssertGreaterThan(pane.editorView.bounds.width, 0)
        XCTAssertGreaterThan(pane.editorView.bounds.height, 0)
        XCTAssertEqual(pane.editorView._gutterDiagnosticMarkersForTesting, gutterMarkers)
    }

    private func lineStartOffsets(for lines: [String]) -> [UInt32] {
        var offsets: [UInt32] = []
        var current: UInt32 = 0
        for line in lines {
            offsets.append(current)
            current += UInt32(line.count + 1)
        }
        return offsets
    }

    private func visibleGutterMarkers(
        lineStartOffsets: [UInt32]
    ) -> [EditorCoreSkiaGutterDiagnosticMarker] {
        [
            EditorCoreSkiaGutterDiagnosticMarker(
                logicalLine: 0,
                charOffset: lineStartOffsets[0],
                kind: .warning
            ),
            EditorCoreSkiaGutterDiagnosticMarker(
                logicalLine: 3,
                charOffset: lineStartOffsets[3],
                kind: .error
            ),
        ]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorChromePolishLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            configurationSnapshot: makeConfigurationSnapshot(workspaceRootURL: workspaceRootURL)
        )
    }

    private func attachToWindow(
        _ vc: AttoEditorAreaViewController,
        size: NSSize
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.setContentSize(size)
        vc.view.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func makeConfigurationSnapshot(workspaceRootURL: URL) -> AttoConfigurationSnapshot {
        AttoConfigurationSnapshot(
            editor: AttoEditorPreferenceSnapshot(
                fontFamilies: [],
                fontSizePoints: 13,
                autoPairsEnabled: true,
                wrapMode: "char",
                wrapIndent: "none",
                findCaseSensitive: true,
                findWholeWord: false,
                findRegex: false
            ),
            rendering: AttoRenderingPreferenceSnapshot(
                themeName: "Atto Light",
                fontLigaturesEnabled: false
            ),
            language: AttoLanguagePreferenceSnapshot(
                commentConfigurations: [:],
                lspAutoRestart: AttoLspAutoRestartPolicySnapshot(
                    enabled: true,
                    maxAttempts: 3,
                    baseDelaySeconds: 5,
                    disabledServerKeys: [],
                    serverMaxAttempts: [:],
                    serverBaseDelaySeconds: [:]
                )
            ),
            workspace: AttoWorkspacePreferenceSnapshot(
                rootURL: workspaceRootURL.absoluteString,
                rootPath: workspaceRootURL.path,
                findInFilesDefaultScope: "opened_files",
                workspaceSearchIncludeGlobs: [],
                workspaceSearchExcludeGlobs: []
            )
        )
    }

    private func assertFrameInside(
        _ view: NSView,
        _ ancestor: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = view.convert(view.bounds, to: ancestor)
        XCTAssertGreaterThanOrEqual(frame.minX, ancestor.bounds.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, ancestor.bounds.maxX + 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, ancestor.bounds.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, ancestor.bounds.maxY + 1, file: file, line: line)
    }

    private func assertStatusBarLabelsStayInsideStatusBar(
        _ statusBar: AttoStatusBarView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labelFrames = allSubviews(in: statusBar)
            .compactMap { $0 as? NSTextField }
            .filter { $0.isHidden == false }
            .map { $0.convert($0.bounds, to: statusBar) }
            .filter { $0.width > 0 && $0.height > 0 }

        XCTAssertFalse(labelFrames.isEmpty, file: file, line: line)
        for frame in labelFrames {
            XCTAssertGreaterThanOrEqual(frame.minX, statusBar.bounds.minX - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, statusBar.bounds.maxX + 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, statusBar.bounds.minY - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, statusBar.bounds.maxY + 1, file: file, line: line)
        }
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let found = findView(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T {
            return v
        }
        for subview in root.subviews {
            if let found = findSubview(of: type, in: subview) {
                return found
            }
        }
        return nil
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        root.subviews + root.subviews.flatMap { allSubviews(in: $0) }
    }
}
