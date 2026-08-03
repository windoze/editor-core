import AttoEditorSupport
@testable import AttoEditor
import Foundation
import XCTest

@MainActor
final class AttoEditorXCUIApplicationSmokeTests: XCTestCase {
    private static let enabledEnvKey = "ATTO_XCUI_SMOKE_TESTS"
    private static let appPathEnvKey = "ATTO_XCUI_APP_PATH"
    private static let timeout: TimeInterval = 12

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
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "missing AX element: \(identifier)")
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

    var description: String {
        switch self {
        case let .missingAppPath(path):
            return "ATTO_XCUI_APP_PATH does not exist: \(path)"
        case let .invalidAppBundle(path):
            return "ATTO_XCUI_APP_PATH should point at AttoEditor.app or an executable: \(path)"
        case let .nonExecutablePath(path):
            return "ATTO_XCUI_APP_PATH is not executable: \(path)"
        }
    }
}
