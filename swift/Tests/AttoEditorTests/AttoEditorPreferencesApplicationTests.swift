import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorPreferencesApplicationTests: XCTestCase {
    func testScopedConfigurationSettingsLoadForAppWindowsAndPreferenceReapply() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorScopedConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = workspaceRootURL.appendingPathComponent("wrap.txt")
        try "foo-bar bar abcdefghijklmnop\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let sourcesURL = workspaceRootURL.appendingPathComponent("Sources", isDirectory: true)
        let vendorURL = workspaceRootURL.appendingPathComponent("Vendor", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vendorURL, withIntermediateDirectories: true)
        let sourceURL = sourcesURL.appendingPathComponent("App.swift")
        let generatedURL = sourcesURL.appendingPathComponent("Model.generated.swift")
        let readmeURL = workspaceRootURL.appendingPathComponent("README.md")
        let vendoredURL = vendorURL.appendingPathComponent("Vendored.swift")
        try "needle\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "needle\n".write(to: generatedURL, atomically: true, encoding: .utf8)
        try "needle\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "needle\n".write(to: vendoredURL, atomically: true, encoding: .utf8)

        let settingsStore = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try settingsStore.saveUserSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontFamilies: ["User Mono"],
                fontSizePoints: 19,
                wrapMode: "char"
            ),
            rendering: AttoRenderingPreferenceSettings(
                themeName: "Atto Light",
                fontLigaturesEnabled: true
            )
        ))
        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                autoPairsEnabled: false,
                wrapMode: "none",
                wrapIndent: "fixed_cells:2",
                findCaseSensitive: false,
                findWholeWord: true,
                findRegex: true,
                wordBoundaryAsciiBoundaryChars: "."
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Dark"),
            workspace: AttoWorkspacePreferenceSettings(
                findInFilesDefaultScope: "workspace",
                workspaceSearchIncludeGlobs: ["Sources/**/*.swift", "README.md"],
                workspaceSearchExcludeGlobs: ["**/*.generated.swift", "Vendor/**"]
            )
        ), workspaceRootURL: workspaceRootURL)

        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: settingsStore
        )
        let ctx = delegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            ctx.window.close()
        }

        var snapshot = ctx.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontFamilies, ["User Mono"])
        XCTAssertEqual(snapshot.editor.fontSizePoints, 19)
        XCTAssertFalse(snapshot.editor.autoPairsEnabled)
        XCTAssertEqual(snapshot.editor.wrapMode, "none")
        XCTAssertEqual(snapshot.editor.wrapIndent, "fixed_cells:2")
        XCTAssertFalse(snapshot.editor.findCaseSensitive)
        XCTAssertTrue(snapshot.editor.findWholeWord)
        XCTAssertTrue(snapshot.editor.findRegex)
        XCTAssertEqual(snapshot.editor.wordBoundaryAsciiBoundaryChars, ".")
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Dark")
        XCTAssertTrue(snapshot.rendering.fontLigaturesEnabled)
        XCTAssertEqual(snapshot.workspace.rootPath, workspaceRootURL.path)
        XCTAssertEqual(snapshot.workspace.findInFilesDefaultScope, "workspace")
        XCTAssertEqual(snapshot.workspace.workspaceSearchIncludeGlobs, ["Sources/**/*.swift", "README.md"])
        XCTAssertEqual(snapshot.workspace.workspaceSearchExcludeGlobs, ["**/*.generated.swift", "Vendor/**"])
        ctx.editorAreaController.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.caseSensitiveButton.state, .off)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.wholeWordButton.state, .on)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.regexButton.state, .on)
        ctx.findInFilesController.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(ctx.findInFilesController._selectedScopeForTesting(), .workspace)
        XCTAssertEqual(
            ctx.findInFilesController._searchOptionsForTesting(),
            AttoFindInFilesViewController.SearchOptions(caseSensitive: false, wholeWord: true, regex: true)
        )
        let workspaceSearchFiles = [sourceURL, generatedURL, readmeURL, vendoredURL, fileURL]
        XCTAssertEqual(
            ctx.findInFilesController._filteredWorkspaceFileURLsForTesting(workspaceSearchFiles).map(\.standardizedFileURL),
            [sourceURL, readmeURL].map(\.standardizedFileURL)
        )

        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try editorView.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(editorView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(editorView.fontSizePoints, CGFloat(19))
        XCTAssertEqual(
            try editorView.editor.setSearchQuery(
                "bar",
                options: EcuSearchOptions(caseSensitive: true, wholeWord: true)
            ),
            1
        )

        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(wrapMode: "char"),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light")
        ), workspaceRootURL: workspaceRootURL)
        delegate._applyEditorPreferencesForTesting()

        snapshot = ctx.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.wrapMode, "char")
        XCTAssertTrue(snapshot.editor.findCaseSensitive)
        XCTAssertFalse(snapshot.editor.findWholeWord)
        XCTAssertFalse(snapshot.editor.findRegex)
        XCTAssertNil(snapshot.editor.wordBoundaryAsciiBoundaryChars)
        XCTAssertEqual(snapshot.workspace.findInFilesDefaultScope, "opened_files")
        XCTAssertEqual(snapshot.workspace.workspaceSearchIncludeGlobs, [])
        XCTAssertEqual(snapshot.workspace.workspaceSearchExcludeGlobs, [])
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Light")
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.caseSensitiveButton.state, .on)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.wholeWordButton.state, .off)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.regexButton.state, .off)
        XCTAssertEqual(ctx.findInFilesController._selectedScopeForTesting(), .openedFiles)
        XCTAssertEqual(
            ctx.findInFilesController._searchOptionsForTesting(),
            AttoFindInFilesViewController.SearchOptions(caseSensitive: true, wholeWord: false, regex: false)
        )
        XCTAssertEqual(
            ctx.findInFilesController._filteredWorkspaceFileURLsForTesting(workspaceSearchFiles).map(\.standardizedFileURL),
            workspaceSearchFiles.map(\.standardizedFileURL)
        )

        try editorView.editor.setViewportWidthCells(4)
        XCTAssertTrue(try viewportLines(editorView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(
            try editorView.editor.setSearchQuery(
                "bar",
                options: EcuSearchOptions(caseSensitive: true, wholeWord: true)
            ),
            2
        )
    }

    func testDocumentScopedConfigurationSettingsApplyPerOpenTabAndReapply() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorDocumentScopedConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let textURL = workspaceRootURL.appendingPathComponent("plain.txt")
        let swiftURL = workspaceRootURL.appendingPathComponent("App.swift")
        try "abcdefghijklmnop\n".write(to: textURL, atomically: true, encoding: .utf8)
        try "abcdefghijklmnop\n".write(to: swiftURL, atomically: true, encoding: .utf8)

        let settingsStore = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontSizePoints: 14,
                wrapMode: "none",
                findCaseSensitive: true,
                findWholeWord: false,
                findRegex: false
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light"),
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["*.swift"],
                    editor: AttoEditorPreferenceSettings(
                        fontSizePoints: 23,
                        wrapMode: "char",
                        findCaseSensitive: false,
                        findWholeWord: true,
                        findRegex: true
                    ),
                    rendering: AttoRenderingPreferenceSettings(themeName: "Atto Dark")
                ),
            ]
        ), workspaceRootURL: workspaceRootURL)

        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: settingsStore
        )
        let ctx = delegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            ctx.window.close()
        }

        ctx.editorAreaController.openFile(url: textURL, mode: .pinned)
        ctx.editorAreaController.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try textView.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(textView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(textView.fontSizePoints, CGFloat(14))
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.caseSensitiveButton.state, .on)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.wholeWordButton.state, .off)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.regexButton.state, .off)
        try assertEditorBackground(ctx.editorAreaController, matchesThemeNamed: "Atto Light")

        ctx.editorAreaController.openFile(url: swiftURL, mode: .pinned)
        ctx.editorAreaController.view.layoutSubtreeIfNeeded()
        let swiftView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try swiftView.editor.setViewportWidthCells(4)
        XCTAssertTrue(try viewportLines(swiftView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(swiftView.fontSizePoints, CGFloat(23))
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.caseSensitiveButton.state, .off)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.wholeWordButton.state, .on)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.regexButton.state, .on)
        try assertEditorBackground(ctx.editorAreaController, matchesThemeNamed: "Atto Dark")

        let textTabID = try XCTUnwrap(ctx.editorAreaController.tabs.first { $0.fileURL.standardizedFileURL == textURL.standardizedFileURL }?.id)
        let swiftTabID = try XCTUnwrap(ctx.editorAreaController.tabs.first { $0.fileURL.standardizedFileURL == swiftURL.standardizedFileURL }?.id)
        ctx.editorAreaController.selectTab(id: textTabID)
        ctx.editorAreaController.view.layoutSubtreeIfNeeded()
        try assertEditorBackground(ctx.editorAreaController, matchesThemeNamed: "Atto Light")
        ctx.editorAreaController.selectTab(id: swiftTabID)
        ctx.editorAreaController.view.layoutSubtreeIfNeeded()
        try assertEditorBackground(ctx.editorAreaController, matchesThemeNamed: "Atto Dark")

        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontSizePoints: 14,
                wrapMode: "none",
                findCaseSensitive: true,
                findWholeWord: false,
                findRegex: false
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light"),
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["*.swift"],
                    editor: AttoEditorPreferenceSettings(
                        fontSizePoints: 24,
                        wrapMode: "none",
                        findCaseSensitive: true,
                        findWholeWord: false,
                        findRegex: false
                    ),
                    rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light")
                ),
            ]
        ), workspaceRootURL: workspaceRootURL)
        delegate._applyEditorPreferencesForTesting()

        try swiftView.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(swiftView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(swiftView.fontSizePoints, CGFloat(24))
        XCTAssertEqual(textView.fontSizePoints, CGFloat(14))
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.caseSensitiveButton.state, .on)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.wholeWordButton.state, .off)
        XCTAssertEqual(ctx.editorAreaController.findReplaceBarView.regexButton.state, .off)
        try assertEditorBackground(ctx.editorAreaController, matchesThemeNamed: "Atto Light")
    }

    func testRuntimeConfigurationSettingsOverrideUserAndWorkspaceSettings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorRuntimeConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = workspaceRootURL.appendingPathComponent("wrap.txt")
        try "abcdefghijklmnop\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let settingsStore = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try settingsStore.saveUserSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 17, wrapMode: "char"),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light")
        ))
        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(wrapMode: "none"),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Dark")
        ), workspaceRootURL: workspaceRootURL)

        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: settingsStore
        )
        delegate._setRuntimeConfigurationSettingsForTesting(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 22, wrapMode: "char"),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Light")
        ))

        let ctx = delegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            ctx.window.close()
        }

        var snapshot = ctx.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontSizePoints, 22)
        XCTAssertEqual(snapshot.editor.wrapMode, "char")
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Light")

        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try editorView.editor.setViewportWidthCells(4)
        XCTAssertTrue(try viewportLines(editorView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(editorView.fontSizePoints, CGFloat(22))

        delegate._setRuntimeConfigurationSettingsForTesting(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(wrapMode: "none"),
            rendering: AttoRenderingPreferenceSettings(themeName: "Atto Dark")
        ))

        snapshot = ctx.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontSizePoints, 17)
        XCTAssertEqual(snapshot.editor.wrapMode, "none")
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Dark")

        try editorView.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(editorView.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
        XCTAssertEqual(editorView.fontSizePoints, CGFloat(17))
    }

    func testWrapModePreferenceAppliesToNewEditor() throws {
        let noWrap = try openEditor(wrapMode: .none)
        try noWrap.editor.setViewportWidthCells(4)
        XCTAssertFalse(try viewportLines(noWrap.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })

        let charWrap = try openEditor(wrapMode: .char)
        try charWrap.editor.setViewportWidthCells(4)
        XCTAssertTrue(try viewportLines(charWrap.editor).contains { ($0["is_wrapped_part"] as? Bool) == true })
    }

    func testWrapIndentPreferenceAppliesToNewEditor() throws {
        let fixedIndent = try openEditor(wrapMode: .char, wrapIndent: .fixedCells(2))
        try fixedIndent.editor.setViewportWidthCells(4)

        let wrappedLines = try viewportLines(fixedIndent.editor).filter {
            ($0["is_wrapped_part"] as? Bool) == true
        }
        XCTAssertTrue(wrappedLines.contains { ($0["segment_x_start_cells"] as? Int) == 2 })
    }

    private func openEditor(
        wrapMode: EcuWrapMode,
        wrapIndent: EcuWrapIndent? = nil
    ) throws -> EditorCoreSkiaView {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorPreferencesApplicationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = tempDir.appendingPathComponent("wrap.txt")
        try "abcdefghijklmnop\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let prefs = makeIsolatedPreferences(wrapMode: wrapMode, wrapIndent: wrapIndent)
        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            preferences: prefs
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        vc.openFile(url: fileURL, mode: .pinned)

        return try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
    }

    private func makeIsolatedPreferences(
        wrapMode: EcuWrapMode,
        wrapIndent: EcuWrapIndent?
    ) -> AttoPreferences {
        let suiteName = "atto_editor_preferences_application_tests_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults(suiteName:)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        prefs.setWrapMode(wrapMode)
        if let wrapIndent {
            prefs.setWrapIndent(wrapIndent)
        }
        return prefs
    }

    private func viewportLines(_ editor: EditorUI) throws -> [[String: Any]] {
        let json = try editor.viewportJSON(startRow: 0, count: 20)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
        return try XCTUnwrap(viewport["lines"] as? [[String: Any]])
    }

    private func assertEditorBackground(
        _ vc: AttoEditorAreaViewController,
        matchesThemeNamed themeName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let registry = AttoThemeManager.loadRegistry()
        let theme = AttoThemeManager.resolveSkiaTheme(themeName: themeName, registry: registry).theme
        let actualCGColor = try XCTUnwrap(vc.contentHostView.layer?.backgroundColor, file: file, line: line)
        let actual = try XCTUnwrap(
            NSColor(cgColor: actualCGColor)?.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        let expected = try XCTUnwrap(
            NSColor(ecuRgba8: theme.editorBackground).usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
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
