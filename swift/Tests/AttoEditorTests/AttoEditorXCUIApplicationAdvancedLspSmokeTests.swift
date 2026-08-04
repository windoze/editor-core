@testable import AttoEditor
import Foundation
import XCTest

@MainActor
extension AttoEditorXCUIApplicationSmokeTests {
    func testRealLspServerMultiFileWorkspacePanelsSmokeFlow() throws {
        let fixture = try makeAdvancedLspFixture()
        defer { fixture.cleanUp() }

        let launched = try launchAttoEditor(environment: [
            "ATTO_EDITOR_LSP_CMD": fixture.scriptURL.path,
        ])
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        let workspaceURL = launched.runtimeRoot.appendingPathComponent("multi-file-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let mainURL = workspaceURL.appendingPathComponent("multi_main.rs", isDirectory: false)
        let libURL = workspaceURL.appendingPathComponent("multi_lib.rs", isDirectory: false)
        try """
        fn multi_main_symbol() {
            multi_lib_symbol();
        }
        """.write(to: mainURL, atomically: true, encoding: .utf8)
        try "pub fn multi_lib_symbol() {}\n".write(to: libURL, atomically: true, encoding: .utf8)

        try enqueueOpenRequest(directories: [workspaceURL], launched: launched)
        assertElementExists(AttoAccessibilityID.fileExplorer, in: launched.app)

        try openWorkspaceFileThroughQuickOpen("multi_main", expectingTitle: "multi_main.rs", in: launched.app)
        XCTAssertNotNil(
            waitForFileText(at: fixture.captureURL, contains: "multi_main.rs"),
            "expected fixture LSP server to receive didOpen for multi_main.rs"
        )
        try requestDocumentSymbolsAndWaitForSymbol("multi_main_symbol", in: launched.app)

        try openWorkspaceFileThroughQuickOpen("multi_lib", expectingTitle: "multi_lib.rs", in: launched.app)
        XCTAssertNotNil(
            waitForFileText(at: fixture.captureURL, contains: "multi_lib.rs"),
            "expected fixture LSP server to receive didOpen for multi_lib.rs"
        )
        try requestDocumentSymbolsAndWaitForSymbol("multi_lib_symbol", in: launched.app)

        try runCommandPaletteCommand("lsp.show_workspace_outline_panel", in: launched.app)
        assertElementExists(AttoAccessibilityID.lspSymbolPanel, in: launched.app)
        let outlineSearch = try requiredElement(
            identifier: AttoAccessibilityID.lspSymbolPanelSearchField,
            in: launched.app
        )
        outlineSearch.click()
        launched.app.typeText("multi_")
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "multi_main_symbol",
                in: launched.app
            ),
            "expected Workspace Outline to include symbols from the first workspace file"
        )
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.lspSymbolPanelRowTitle,
                contains: "multi_lib_symbol",
                in: launched.app
            ),
            "expected Workspace Outline to include symbols from the second workspace file"
        )
        launched.app.typeKey(.escape, modifierFlags: [])

        try runWorkspaceSymbolSearch("multi", expecting: "multi_lib_symbol", in: launched.app)
        XCTAssertNotNil(
            waitForFileText(at: fixture.captureURL, contains: "\"method\":\"workspace/symbol\""),
            "expected fixture LSP server to receive a real workspace/symbol request"
        )
    }

    func testRealLspServerMultiRootErrorDelayAndRestartPanelsSmokeFlow() throws {
        let fixture = try makeAdvancedLspFixture()
        defer { fixture.cleanUp() }

        let launched = try launchAttoEditor(environment: [
            "ATTO_EDITOR_LSP_CMD": fixture.scriptURL.path,
            "ATTO_EDITOR_LSP_AUTO_RESTART_BASE_DELAY_SECONDS": "0",
        ])
        defer { launched.cleanUp() }

        XCTAssertTrue(launched.app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(launched.app.windows.firstMatch.waitForExistence(timeout: Self.timeout))

        let rootAlpha = launched.runtimeRoot.appendingPathComponent("root-alpha", isDirectory: true)
        let rootBeta = launched.runtimeRoot.appendingPathComponent("root-beta", isDirectory: true)
        try FileManager.default.createDirectory(at: rootAlpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootBeta, withIntermediateDirectories: true)

        let alphaURL = rootAlpha.appendingPathComponent("root_alpha.rs", isDirectory: false)
        let betaURL = rootBeta.appendingPathComponent("root_beta.rs", isDirectory: false)
        let errorURL = rootBeta.appendingPathComponent("error_symbols.rs", isDirectory: false)
        try "fn root_alpha_symbol() {}\n".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "fn root_beta_symbol() {}\n".write(to: betaURL, atomically: true, encoding: .utf8)
        try "fn error_symbol_fixture() {}\n".write(to: errorURL, atomically: true, encoding: .utf8)

        try enqueueOpenRequest(directories: [rootAlpha], launched: launched)
        try openWorkspaceFileThroughQuickOpen("root_alpha", expectingTitle: "root_alpha.rs", in: launched.app)
        try requestDocumentSymbolsAndWaitForSymbol("root_alpha_symbol", in: launched.app)

        try enqueueOpenRequest(directories: [rootBeta], launched: launched)
        try openWorkspaceFileThroughQuickOpen("root_beta", expectingTitle: "root_beta.rs", in: launched.app)
        try requestDocumentSymbolsAndWaitForSymbol("root_beta_symbol", in: launched.app)

        XCTAssertGreaterThanOrEqual(
            waitForCapturedLineCount(at: fixture.captureURL, containing: "\"method\":\"initialize\"", atLeast: 2),
            2,
            "expected separate real LSP sessions for the two project roots"
        )
        XCTAssertNotNil(waitForFileText(at: fixture.captureURL, contains: rootAlpha.path))
        XCTAssertNotNil(waitForFileText(at: fixture.captureURL, contains: rootBeta.path))

        try runWorkspaceSymbolSearch("delayed_symbol", expecting: "delayed_symbol", in: launched.app)
        XCTAssertNotNil(
            waitForFileText(at: fixture.captureURL, contains: "\"query\":\"delayed_symbol\""),
            "expected delayed workspace/symbol request to reach the fixture server"
        )

        try openWorkspaceFileThroughQuickOpen("error_symbols", expectingTitle: "error_symbols.rs", in: launched.app)
        try runCommandPaletteCommand("lsp.document_symbols", in: launched.app)
        XCTAssertNotNil(
            waitForFileText(at: fixture.captureURL, contains: "fixture documentSymbol failure"),
            "expected fixture server to return a real JSON-RPC documentSymbol error"
        )

        try runCommandPaletteCommand("lsp.show_project_lsp_status", in: launched.app)
        let statusPrefix = "AttoEditor.LSP.ProjectStatusEvents"
        assertElementExists(AttoAccessibilityID.commandPalettePanel(prefix: statusPrefix), in: launched.app)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: statusPrefix),
                contains: "fixture documentSymbol failure",
                in: launched.app
            ),
            "expected Project Status Events panel to retain the real server error"
        )
        launched.app.typeKey(.escape, modifierFlags: [])

        try runCommandPaletteCommand("lsp.restart_server", in: launched.app)
        XCTAssertGreaterThanOrEqual(
            waitForCapturedLineCount(at: fixture.captureURL, containing: "\"event\":\"process_start\"", atLeast: 3),
            3,
            "expected manual LSP restart to launch a replacement fixture process"
        )
        XCTAssertNotNil(
            waitForElementText(
                identifier: AttoAccessibilityID.statusBarLeftLabel,
                contains: "LSP server restarted",
                in: launched.app
            ),
            "expected restart command to surface status feedback"
        )

        try runCommandPaletteCommand("lsp.show_project_lsp_status", in: launched.app)
        assertElementExists(AttoAccessibilityID.commandPalettePanel(prefix: statusPrefix), in: launched.app)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: statusPrefix),
                contains: "restart started",
                in: launched.app
            ),
            "expected Project Status Events panel to retain the restart lifecycle event"
        )
    }
}
