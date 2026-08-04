import AttoEditorSupport
@testable import AttoEditor
import Foundation
import XCTest

@MainActor
final class AttoEditorXCUIApplicationSmokeTests: XCTestCase {
    static let enabledEnvKey = "ATTO_XCUI_SMOKE_TESTS"
    static let appPathEnvKey = "ATTO_XCUI_APP_PATH"
    static let timeout: TimeInterval = 12
    static let pollInterval: TimeInterval = 0.05

    func testLaunchShowsMainChromeAccessibilityNodes() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))
        assertElementExists(AttoAccessibilityID.sidebar, in: launched.app)
        assertElementExists(AttoAccessibilityID.fileExplorer, in: launched.app)
        assertElementExists(AttoAccessibilityID.editorArea, in: launched.app)
        assertElementExists(AttoAccessibilityID.editorContentHost, in: launched.app)
        assertElementExists(AttoAccessibilityID.tabBar, in: launched.app)
        assertElementExists(AttoAccessibilityID.statusBar, in: launched.app)
    }

    func testCommandPaletteOpensFromDefaultKeyboardShortcut() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        launched.app.typeKey("p", modifierFlags: [.command, .shift])
        assertElementExists(
            AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.CommandPalette"),
            in: launched.app
        )
        assertElementExists(
            AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.CommandPalette"),
            in: launched.app
        )
        assertElementExists(
            AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.CommandPalette"),
            in: launched.app
        )
    }

    func testEditingFindAndSplitKeyboardSmokeFlow() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        launched.app.typeKey("n", modifierFlags: [.command])
        let editorViewPrefix = dynamicIdentifierPrefix(AttoAccessibilityID.editorView)
        let editorView = try firstElement(identifierPrefix: editorViewPrefix, in: launched.app)
        editorView.click()
        launched.app.typeText("alpha\nbeta\nalpha\n")
        launched.app.typeKey("z", modifierFlags: [.command])

        launched.app.typeKey("f", modifierFlags: [.command])
        assertElementExists(AttoAccessibilityID.findReplaceBar, in: launched.app)
        assertElementExists(AttoAccessibilityID.findSearchField, in: launched.app)
        launched.app.typeText("alpha")

        launched.app.typeKey("2", modifierFlags: [.command, .option])
        assertElementCount(
            atLeast: 1,
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.tabChip),
            in: launched.app
        )
        assertElementCount(
            atLeast: 2,
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorPane),
            in: launched.app
        )
        assertElementCount(atLeast: 2, identifierPrefix: editorViewPrefix, in: launched.app)
    }

    func testSidebarSearchAndQuickOpenPanelSmokeFlow() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        launched.app.typeKey("f", modifierFlags: [.command, .shift])
        let findQuery = try requiredElement(identifier: AttoAccessibilityID.findInFilesQueryField, in: launched.app)
        findQuery.click()
        launched.app.typeText("alpha")
        assertElementExists(AttoAccessibilityID.findInFilesScopeControl, in: launched.app)
        assertElementExists(AttoAccessibilityID.findInFilesStatusLabel, in: launched.app)
        assertElementExists(AttoAccessibilityID.findInFilesTable, in: launched.app)

        launched.app.typeKey("p", modifierFlags: [.command])
        let quickOpenPrefix = "AttoEditor.QuickOpen"
        assertElementExists(
            AttoAccessibilityID.commandPalettePanel(prefix: quickOpenPrefix),
            in: launched.app
        )
        let quickOpenSearch = try requiredElement(
            identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: quickOpenPrefix),
            in: launched.app
        )
        quickOpenSearch.click()
        launched.app.typeText("main")
        assertElementExists(
            AttoAccessibilityID.commandPaletteTable(prefix: quickOpenPrefix),
            in: launched.app
        )
    }

    func testLspResultPanelsOpenFromCommandPaletteSmokeFlow() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        launched.app.typeKey("n", modifierFlags: [.command])
        _ = try firstElement(identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorView), in: launched.app)

        try runCommandPaletteCommand("lsp.show_workbench_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspWorkbenchPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspWorkbenchPanelRoot, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspWorkbenchPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspWorkbenchPanelMetadataLabel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspWorkbenchPanelTable, in: launched.app)

        try runCommandPaletteCommand("lsp.show_problems_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.problemsPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.problemsPanelRoot, in: launched.app)
        assertElementExists(AttoAccessibilityID.problemsPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.problemsPanelTable, in: launched.app)

        try runCommandPaletteCommand("lsp.show_workspace_problems_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.workspaceProblemsPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.workspaceProblemsPanelRoot, in: launched.app)
        assertElementExists(AttoAccessibilityID.workspaceProblemsPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.workspaceProblemsPanelTable, in: launched.app)
    }

    func testSelectionAndMulticursorCommandPaletteSmokeFlow() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        launched.app.typeKey("n", modifierFlags: [.command])
        let editorView = try firstElement(
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorView),
            in: launched.app
        )
        editorView.click()
        launched.app.typeText("alpha beta alpha\nalpha beta\n")

        try runCommandPaletteCommand("cursor.document_start", in: launched.app)
        try runCommandPaletteCommand("editor.select_word", in: launched.app)
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarSelectionLabel,
                contains: "Sel ",
                in: launched.app
            ),
            "expected selecting a word to update the status bar selection label"
        )

        try runCommandPaletteCommand("editor.add_next_occurrence", in: launched.app)
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarSelectionLabel,
                contains: "cursors",
                in: launched.app
            ),
            "expected adding the next occurrence to create a multi-cursor selection"
        )

        try runCommandPaletteCommand("editor.add_all_occurrences", in: launched.app)
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarSelectionLabel,
                contains: "cursors",
                in: launched.app
            ),
            "expected selecting all occurrences to keep a multi-cursor selection"
        )
    }

    func testOpenFileThroughIPCAndSaveKeyboardSmokeFlow() throws {
        let launched = try launchAttoEditor()
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        let workspaceURL = launched.runtimeRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("open-save-smoke.txt", isDirectory: false)
        try "initial\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try enqueueOpenFileRequest(fileURL, launched: launched)
        assertElementCount(
            atLeast: 1,
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.tabChip),
            in: launched.app
        )
        let editorView = try firstElement(
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorView),
            in: launched.app
        )
        editorView.click()
        launched.app.typeText("saved via xcui\n")
        launched.app.typeKey("s", modifierFlags: [.command])

        XCTAssertNotNil(
            waitForFileText(at: fileURL, contains: "saved via xcui"),
            "expected cmd+s to persist editor text to \(fileURL.path)"
        )
    }

    func testInjectedLocationSymbolAndWorkspaceOutlinePanelsSmokeFlow() throws {
        let launched = try launchAttoEditor(resultFixtures: true)
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        let workspaceURL = launched.runtimeRoot.appendingPathComponent("result-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("ResultFixtures.swift", isDirectory: false)
        try """
        struct XCUISmokeDocument {
            func smokeChild() {}
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        try enqueueOpenFileRequest(fileURL, launched: launched)
        _ = try firstElement(identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorView), in: launched.app)

        try runCommandPaletteCommand("lsp.show_locations_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanelRoot, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanelMetadataLabel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanelTable, in: launched.app)
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.lspLocationPanelRowTitle,
                contains: "ResultFixtures.swift",
                in: launched.app
            ),
            "expected injected Locations panel rows to render"
        )
        launched.app.typeKey(.downArrow, modifierFlags: [])
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 2, Col 3",
                in: launched.app
            ),
            "expected opening the second Locations row to navigate to line 2 column 3"
        )

        try runCommandPaletteCommand("lsp.show_symbols_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelRoot, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelMetadataLabel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelTable, in: launched.app)
        let symbolSearch = try requiredElement(identifier: AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        symbolSearch.click()
        launched.app.typeText("smokeChild")
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "smokeChild",
                in: launched.app
            ),
            "expected injected Document Symbols panel rows to filter"
        )
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 2, Col 1",
                in: launched.app
            ),
            "expected opening the filtered Document Symbols row to navigate to line 2 column 1"
        )

        try runCommandPaletteCommand("lsp.show_workspace_outline_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelMetadataLabel, in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanelTable, in: launched.app)
        let outlineSearch = try requiredElement(identifier: AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        outlineSearch.click()
        launched.app.typeText("smokeChild")
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "smokeChild",
                in: launched.app
            ),
            "expected injected Workspace Outline rows to filter"
        )
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 2, Col 1",
                in: launched.app
            ),
            "expected opening the filtered Workspace Outline row to navigate to line 2 column 1"
        )
    }

    func testRealLspServerLocationSymbolAndWorkspaceOutlineSmokeFlow() throws {
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("atto-xcui-real-lsp-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = runtimeRoot.appendingPathComponent("fixture-lsp.py", isDirectory: false)
        let captureURL = runtimeRoot.appendingPathComponent("fixture-lsp-capture.jsonl", isDirectory: false)
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        try writeRealLspFixtureServerScript(scriptURL: scriptURL, captureURL: captureURL)

        let launched = try launchAttoEditor(environment: [
            "ATTO_EDITOR_LSP_CMD": scriptURL.path,
        ])
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        let workspaceURL = launched.runtimeRoot.appendingPathComponent("real-lsp", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let fileURL = workspaceURL.appendingPathComponent("fixture_real_lsp.rs", isDirectory: false)
        try """
        fn fixture_main() {
            fixture_child();
        }

        fn fixture_child() {}
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        try enqueueOpenFileRequest(fileURL, launched: launched)
        let editorView = try firstElement(
            identifierPrefix: dynamicIdentifierPrefix(AttoAccessibilityID.editorView),
            in: launched.app
        )
        editorView.click()
        XCTAssertNotNil(
            waitForFileText(at: captureURL, contains: "textDocument/didOpen"),
            "expected fixture LSP server to receive a real didOpen notification"
        )

        try runCommandPaletteCommand("lsp.go_to_definition", in: launched.app)
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 5, Col 4",
                in: launched.app
            ),
            "expected real fixture LSP definition response to navigate to fixture_child"
        )

        try runCommandPaletteCommand("lsp.show_locations_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspLocationPanel, in: launched.app)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.lspLocationPanelRowTitle,
                contains: "fixture_real_lsp.rs",
                in: launched.app
            ),
            "expected real fixture LSP definition response to populate Locations panel"
        )
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 5, Col 4",
                in: launched.app
            ),
            "expected opening the real LSP Locations panel row to keep the fixture_child target"
        )

        try runCommandPaletteCommand("lsp.document_symbols", in: launched.app)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: "AttoEditor.LSP.SymbolResults"),
                contains: "fixture_child",
                in: launched.app
            ),
            "expected real fixture LSP documentSymbol response to populate Symbol Results"
        )
        launched.app.typeKey(.escape, modifierFlags: [])

        try runCommandPaletteCommand("lsp.show_symbols_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanel, in: launched.app)
        let symbolSearch = try requiredElement(identifier: AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        symbolSearch.click()
        launched.app.typeText("fixture_child")
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "fixture_child",
                in: launched.app
            ),
            "expected real fixture LSP symbols to populate Symbols panel"
        )
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 5, Col 4",
                in: launched.app
            ),
            "expected opening the real LSP Symbols panel row to navigate to fixture_child"
        )

        try runCommandPaletteCommand("lsp.show_workspace_outline_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanel, in: launched.app)
        let outlineSearch = try requiredElement(identifier: AttoAccessibilityID.lspSymbolPanelSearchField, in: launched.app)
        outlineSearch.click()
        launched.app.typeText("fixture_child")
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "fixture_child",
                in: launched.app
            ),
            "expected real fixture LSP document symbols to feed Workspace Outline"
        )
        launched.app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarPositionLabel,
                contains: "Ln 5, Col 4",
                in: launched.app
            ),
            "expected opening the real LSP Workspace Outline row to navigate to fixture_child"
        )

        XCTAssertNotNil(
            waitForFileText(at: captureURL, contains: "textDocument/definition"),
            "expected fixture LSP server to receive a real definition request"
        )
        XCTAssertNotNil(
            waitForFileText(at: captureURL, contains: "textDocument/documentSymbol"),
            "expected fixture LSP server to receive a real documentSymbol request"
        )
    }

    func launchAttoEditor(
        resultFixtures: Bool = false,
        environment: [String: String] = [:]
    ) throws -> LaunchedAttoApp {
        guard Self.isEnabled else {
            throw XCTSkip(
                """
                XCUIApplication smoke tests are opt-in. Set \(Self.enabledEnvKey)=1 and \
                \(Self.appPathEnvKey)=/path/to/AttoEditor.app after running \
                `swift/scripts/build-attoeditor-app.sh --debug`.
                """
            )
        }

        let appURL = try Self.resolveApplicationURL()
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("atto-xcui-smoke-\(UUID().uuidString)", isDirectory: true)
        let homeURL = runtimeRoot.appendingPathComponent("home", isDirectory: true)
        let spoolDir = runtimeRoot.appendingPathComponent("spool", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        let app = XCUIApplication(url: appURL)
        app.launchArguments = [AttoIPC.internalServerFlag]
        app.launchEnvironment[AttoIPC.socketPathEnvKey] = runtimeRoot
            .appendingPathComponent("atto.sock", isDirectory: false)
            .path
        app.launchEnvironment[AttoIPC.spoolDirPathEnvKey] = spoolDir.path
        app.launchEnvironment["HOME"] = homeURL.path
        app.launchEnvironment["ATTO_EDITOR_THEME"] = "Atto Dark"
        if resultFixtures {
            app.launchEnvironment[AttoEditorAreaViewController.xcuiResultFixturesEnvKey] = "1"
        }
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()

        return LaunchedAttoApp(app: app, runtimeRoot: runtimeRoot, spoolDir: spoolDir)
    }

    private static var isEnabled: Bool {
        guard let value = ProcessInfo.processInfo.environment[enabledEnvKey] else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func resolveApplicationURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard let configuredPath = env[appPathEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              configuredPath.isEmpty == false
        else {
            throw XCTSkip(
                "\(appPathEnvKey) is required for XCUIApplication smoke tests; build the app bundle first."
            )
        }

        let url = URL(fileURLWithPath: configuredPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AttoXCUISmokeConfigurationError.missingAppPath(url.path)
        }
        if isDirectory.boolValue {
            guard url.pathExtension == "app" else {
                throw AttoXCUISmokeConfigurationError.invalidAppBundle(url.path)
            }
        } else if FileManager.default.isExecutableFile(atPath: url.path) == false {
            throw AttoXCUISmokeConfigurationError.nonExecutablePath(url.path)
        }
        return url
    }

    func assertElementExists(_ identifier: String, in app: XCUIApplication) {
        let element = element(identifier: identifier, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "missing AX element: \(identifier)")
    }

    func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func requiredElement(identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = element(identifier: identifier, in: app)
        guard element.waitForExistence(timeout: Self.timeout) else {
            XCTFail("missing AX element: \(identifier)")
            throw AttoXCUISmokeConfigurationError.missingElement(identifier)
        }
        return element
    }

    func runCommandPaletteCommand(_ query: String, in app: XCUIApplication) throws {
        let prefix = "AttoEditor.CommandPalette"
        app.typeKey("p", modifierFlags: [.command, .shift])
        let searchField = try requiredElement(
            identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix),
            in: app
        )
        searchField.click()
        app.typeText(query)
        assertElementExists(AttoAccessibilityID.commandPaletteTable(prefix: prefix), in: app)
        app.typeKey(.return, modifierFlags: [])
    }

    func enqueueOpenFileRequest(_ fileURL: URL, launched: LaunchedAttoApp) throws {
        try FileManager.default.createDirectory(at: launched.spoolDir, withIntermediateDirectories: true)
        let requestID = UUID().uuidString
        let request = AttoIpcOpenRequest(
            requestID: requestID,
            newWindow: false,
            wait: false,
            directories: [],
            files: [
                AttoIpcFileRequest(path: fileURL.path, line1: nil, column1: nil),
            ]
        )
        let requestURL = launched.spoolDir.appendingPathComponent("req-\(requestID).json", isDirectory: false)
        let data = try JSONEncoder().encode(request)
        try data.write(to: requestURL, options: [.atomic])
    }

    func waitForFileText(at url: URL, contains expected: String) -> String? {
        let deadline = Date().addingTimeInterval(Self.timeout)
        repeat {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains(expected)
            {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline
        return nil
    }

    func waitForElementText(
        identifier: String,
        contains expected: String,
        in app: XCUIApplication
    ) -> String? {
        let deadline = Date().addingTimeInterval(Self.timeout)
        repeat {
            let candidate = element(identifier: identifier, in: app)
            if candidate.exists {
                let text = text(from: candidate)
                if text.contains(expected) {
                    return text
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline
        return nil
    }

    func waitForAnyElementText(
        identifier: String,
        contains expected: String,
        in app: XCUIApplication
    ) -> String? {
        let deadline = Date().addingTimeInterval(Self.timeout)
        repeat {
            let candidates = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .allElementsBoundByIndex
            for candidate in candidates where candidate.exists {
                let text = text(from: candidate)
                if text.contains(expected) {
                    return text
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline
        return nil
    }

    func text(from element: XCUIElement) -> String {
        if let value = element.value as? String, value.isEmpty == false {
            return value
        }
        return element.label
    }

    private func writeRealLspFixtureServerScript(scriptURL: URL, captureURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys
        import traceback

        capture_path = '\(capturePath)'

        def log_event(method):
            with open(capture_path, 'a', encoding='utf-8') as fh:
                fh.write(json.dumps({'method': method}) + '\\n')

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()
            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None
            body = sys.stdin.buffer.read(length)
            return json.loads(body.decode('utf-8'))

        def send_response(request_id, result):
            body = json.dumps(
                {'jsonrpc': '2.0', 'id': request_id, 'result': result},
                separators=(',', ':')
            ).encode('utf-8')
            sys.stdout.buffer.write(b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n')
            sys.stdout.buffer.write(body)
            sys.stdout.buffer.flush()

        def location(uri, line, character):
            return {
                'uri': uri,
                'range': {
                    'start': {'line': line, 'character': character},
                    'end': {'line': line, 'character': character + 13},
                },
            }

        def document_symbols():
            return [
                {
                    'name': 'fixture_main',
                    'kind': 12,
                    'range': {
                        'start': {'line': 0, 'character': 0},
                        'end': {'line': 2, 'character': 1},
                    },
                    'selectionRange': {
                        'start': {'line': 0, 'character': 3},
                        'end': {'line': 0, 'character': 15},
                    },
                },
                {
                    'name': 'fixture_child',
                    'kind': 12,
                    'range': {
                        'start': {'line': 4, 'character': 0},
                        'end': {'line': 4, 'character': 21},
                    },
                    'selectionRange': {
                        'start': {'line': 4, 'character': 3},
                        'end': {'line': 4, 'character': 16},
                    },
                },
            ]

        try:
            while True:
                message = read_message()
                if message is None:
                    break
                method = message.get('method')
                if method:
                    log_event(method)
                if 'id' not in message:
                    continue
                request_id = message['id']
                if method == 'initialize':
                    send_response(request_id, {
                        'capabilities': {
                            'definitionProvider': True,
                            'documentSymbolProvider': True,
                            'workspaceSymbolProvider': True,
                        },
                        'serverInfo': {'name': 'atto-xcui-fixture-lsp'},
                    })
                elif method == 'textDocument/definition':
                    uri = message.get('params', {}).get('textDocument', {}).get('uri', '')
                    send_response(request_id, [location(uri, 4, 3)])
                elif method == 'textDocument/documentSymbol':
                    send_response(request_id, document_symbols())
                elif method == 'workspace/symbol':
                    uri = message.get('params', {}).get('textDocument', {}).get('uri', '')
                    send_response(request_id, [
                        {
                            'name': 'fixture_child',
                            'kind': 12,
                            'location': location(uri, 4, 3),
                        },
                    ])
                elif method == 'shutdown':
                    send_response(request_id, None)
                else:
                    send_response(request_id, None)
        except Exception:
            with open(capture_path, 'a', encoding='utf-8') as fh:
                fh.write(traceback.format_exc())
            raise
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func assertElementCount(
        atLeast expected: Int,
        identifierPrefix: String,
        in app: XCUIApplication
    ) {
        let actual = waitForElementCount(atLeast: expected, identifierPrefix: identifierPrefix, in: app)
        XCTAssertGreaterThanOrEqual(
            actual,
            expected,
            "expected at least \(expected) AX elements with prefix \(identifierPrefix), got \(actual)"
        )
    }

    func firstElement(
        identifierPrefix: String,
        in app: XCUIApplication
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(Self.timeout)
        repeat {
            if let element = elements(identifierPrefix: identifierPrefix, in: app).first {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline

        XCTFail("missing AX element prefix: \(identifierPrefix)")
        throw AttoXCUISmokeConfigurationError.missingElementPrefix(identifierPrefix)
    }

    func waitForElementCount(
        atLeast expected: Int,
        identifierPrefix: String,
        in app: XCUIApplication
    ) -> Int {
        let deadline = Date().addingTimeInterval(Self.timeout)
        var lastCount = 0
        repeat {
            lastCount = elements(identifierPrefix: identifierPrefix, in: app).count
            if lastCount >= expected {
                return lastCount
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline
        return lastCount
    }

    func elements(identifierPrefix: String, in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).allElementsBoundByIndex.filter {
            $0.identifier.hasPrefix(identifierPrefix)
        }
    }

    func dynamicIdentifierPrefix(_ makeIdentifier: (UUID) -> String) -> String {
        let id = UUID()
        return makeIdentifier(id).replacingOccurrences(of: id.uuidString, with: "")
    }

    struct LaunchedAttoApp {
        let app: XCUIApplication
        let runtimeRoot: URL
        let spoolDir: URL

        @MainActor
        func cleanUp() {
            app.terminate()
            try? FileManager.default.removeItem(at: runtimeRoot)
        }
    }
}

private enum AttoXCUISmokeConfigurationError: Error, CustomStringConvertible {
    case missingAppPath(String)
    case invalidAppBundle(String)
    case nonExecutablePath(String)
    case missingElement(String)
    case missingElementPrefix(String)

    var description: String {
        switch self {
        case let .missingAppPath(path):
            return "ATTO_XCUI_APP_PATH does not exist: \(path)"
        case let .invalidAppBundle(path):
            return "ATTO_XCUI_APP_PATH should point at AttoEditor.app or an executable: \(path)"
        case let .nonExecutablePath(path):
            return "ATTO_XCUI_APP_PATH is not executable: \(path)"
        case let .missingElement(identifier):
            return "missing AX element: \(identifier)"
        case let .missingElementPrefix(prefix):
            return "missing AX element prefix: \(prefix)"
        }
    }
}
