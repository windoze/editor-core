@testable import AttoEditor
import XCTest

@MainActor
final class AttoEditorSettingsCommandTests: XCTestCase {
    func testSettingsValidationPanelProjectsIssuesAndMetadata() {
        let report = AttoConfigurationSettingsFileValidationReport(
            url: URL(fileURLWithPath: "/tmp/settings.json"),
            scope: .workspace,
            settings: AttoConfigurationSettings(),
            result: AttoConfigurationSettingsValidationResult(issues: [
                AttoConfigurationSettingsValidationIssue(
                    keyPath: "editor.wrap_mode",
                    message: "Value 'paragraph' is not one of: none, char, word.",
                    severity: .error,
                    scope: .workspace
                ),
                AttoConfigurationSettingsValidationIssue(
                    keyPath: "scoped_settings[0].selectors",
                    message: "Scoped settings selectors cannot be empty.",
                    severity: .warning,
                    scope: .workspaceScoped
                ),
            ])
        )

        let items = AttoSettingsValidationPanelController.items(
            for: report,
            displayName: "Workspace Settings"
        )

        XCTAssertEqual(items.map(\.keyPath), [
            "editor.wrap_mode",
            "scoped_settings[0].selectors",
        ])
        XCTAssertEqual(items.map(\.sourceURL), [
            URL(fileURLWithPath: "/tmp/settings.json"),
            URL(fileURLWithPath: "/tmp/settings.json"),
        ])
        XCTAssertEqual(items.map(\.status), [
            "error | workspace",
            "warning | workspace_scoped",
        ])
        XCTAssertEqual(
            AttoSettingsValidationPanelController.metadataSummary(for: items),
            "2 issues | 1 error | 1 warning"
        )
    }

    func testSettingsValidationCommandsUseSettingsMetadata() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let commands = delegate._defaultCommandsForTesting()

        let validateUser = try XCTUnwrap(commands.first { $0.id == "settings.validate_user_settings" })
        XCTAssertEqual(validateUser.group, "Settings")
        XCTAssertFalse(validateUser.requiresEditor)
        XCTAssertTrue(validateUser.isEnabled)

        let validateWorkspace = try XCTUnwrap(commands.first { $0.id == "settings.validate_workspace_settings" })
        XCTAssertEqual(validateWorkspace.group, "Settings")
        XCTAssertFalse(validateWorkspace.requiresEditor)
        XCTAssertTrue(validateWorkspace.isEnabled)

        let schema = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "settings.validate_user_settings"))
        XCTAssertEqual(schema.macroPolicy, .notRecordable)
        XCTAssertFalse(schema.isParameterized)
    }

    func testSettingsValidationPanelOpensSelectedIssueWithLocation() {
        let sourceURL = URL(fileURLWithPath: "/tmp/settings.json")
        let first = AttoSettingsValidationPanelController.Item(
            id: "first",
            sourceURL: sourceURL,
            keyPath: "editor.wrap_mode",
            message: "Invalid wrap mode.",
            severity: .error,
            scope: .workspace,
            sourceLocation: AttoConfigurationSettingsJSONSourceLocation(line: 4, column: 18, characterOffset: 42)
        )
        let second = AttoSettingsValidationPanelController.Item(
            id: "second",
            sourceURL: sourceURL,
            keyPath: "editor.font_size_points",
            message: "Invalid font size.",
            severity: .error,
            scope: .workspace,
            sourceLocation: nil
        )
        var opened: [AttoSettingsValidationPanelController.Item] = []
        let controller = AttoSettingsValidationPanelController { item in
            opened.append(item)
        }

        controller.update(title: "Workspace Settings Validation", items: [first, second])

        XCTAssertEqual(controller.selectedItem, first)
        XCTAssertTrue(controller.openSelectedItem())
        XCTAssertEqual(opened, [first])

        XCTAssertTrue(controller.selectItem(id: "second"))
        XCTAssertFalse(controller.openSelectedItem())
        XCTAssertEqual(opened, [first])
    }
}
