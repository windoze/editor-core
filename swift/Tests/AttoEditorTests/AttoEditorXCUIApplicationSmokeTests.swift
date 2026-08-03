import AttoEditorSupport
@testable import AttoEditor
import Foundation
import XCTest

@MainActor
final class AttoEditorXCUIApplicationSmokeTests: XCTestCase {
    private static let enabledEnvKey = "ATTO_XCUI_SMOKE_TESTS"
    private static let appPathEnvKey = "ATTO_XCUI_APP_PATH"
    private static let timeout: TimeInterval = 12
    private static let pollInterval: TimeInterval = 0.05

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

    private func launchAttoEditor() throws -> LaunchedAttoApp {
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
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        let app = XCUIApplication(url: appURL)
        app.launchArguments = [AttoIPC.internalServerFlag]
        app.launchEnvironment[AttoIPC.socketPathEnvKey] = runtimeRoot
            .appendingPathComponent("atto.sock", isDirectory: false)
            .path
        app.launchEnvironment[AttoIPC.spoolDirPathEnvKey] = runtimeRoot
            .appendingPathComponent("spool", isDirectory: true)
            .path
        app.launchEnvironment["HOME"] = homeURL.path
        app.launchEnvironment["ATTO_EDITOR_THEME"] = "Atto Dark"
        app.launch()

        return LaunchedAttoApp(app: app, runtimeRoot: runtimeRoot)
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

    private func assertElementExists(_ identifier: String, in app: XCUIApplication) {
        let element = element(identifier: identifier, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "missing AX element: \(identifier)")
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func requiredElement(identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = element(identifier: identifier, in: app)
        guard element.waitForExistence(timeout: Self.timeout) else {
            XCTFail("missing AX element: \(identifier)")
            throw AttoXCUISmokeConfigurationError.missingElement(identifier)
        }
        return element
    }

    private func runCommandPaletteCommand(_ query: String, in app: XCUIApplication) throws {
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

    private func waitForElementText(
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

    private func text(from element: XCUIElement) -> String {
        if let value = element.value as? String, value.isEmpty == false {
            return value
        }
        return element.label
    }

    private func assertElementCount(
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

    private func firstElement(
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

    private func waitForElementCount(
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

    private func elements(identifierPrefix: String, in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).allElementsBoundByIndex.filter {
            $0.identifier.hasPrefix(identifierPrefix)
        }
    }

    private func dynamicIdentifierPrefix(_ makeIdentifier: (UUID) -> String) -> String {
        let id = UUID()
        return makeIdentifier(id).replacingOccurrences(of: id.uuidString, with: "")
    }

    private struct LaunchedAttoApp {
        let app: XCUIApplication
        let runtimeRoot: URL

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
