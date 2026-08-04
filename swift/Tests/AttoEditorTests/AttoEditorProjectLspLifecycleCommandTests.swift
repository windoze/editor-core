import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceRootChangeNotifiesOpenTabLspWorkspaceFolders() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        let firstCaptureURL = tempDir.appendingPathComponent("first-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: firstScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        try secondTab.editCore.editor.lspEnable(
            command: secondScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            firstTab.editCore.editor.lspDisable()
            secondTab.editCore.editor.lspDisable()
        }

        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: "workspace/didChangeWorkspaceFolders"
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: "workspace/didChangeWorkspaceFolders"
        )
        for captured in [firstCaptured, secondCaptured] {
            XCTAssertTrue(captured.contains(#""method":"workspace/didChangeWorkspaceFolders""#), captured)
            XCTAssertTrue(captured.contains(alternateRoot.standardizedFileURL.absoluteString), captured)
            XCTAssertTrue(captured.contains(tempDir.standardizedFileURL.absoluteString), captured)
        }
    }

    func testWorkspaceRootChangeAutoStartsConfiguredOpenTabLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_start.rs")
        try "fn main() {}".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-start-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-start-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc._setLspEnvironmentProviderForTesting {
            [
                "ATTO_EDITOR_DISABLE_LSP": "1",
                "ATTO_EDITOR_LSP_CMD": scriptURL.path,
            ]
        }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        XCTAssertFalse(try tab.editCore.editor.lspIsEnabled())
        XCTAssertNil(tab.lspServerConfig)

        vc._setLspEnvironmentProviderForTesting {
            [
                "ATTO_EDITOR_LSP_CMD": scriptURL.path,
            ]
        }
        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)
        defer { tab.editCore.editor.lspDisable() }
        let alternateRootURI = alternateRoot.standardizedFileURL.absoluteString

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        XCTAssertTrue(try tab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(tab.lspServerConfig?.command, scriptURL.path)
        XCTAssertEqual(tab.lspServerConfig?.languageId, "rust")
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(alternateRootURI), captured)
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["start", "start"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["auto_start", "auto_start"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "started"])
        XCTAssertEqual(lifecycle.events.map(\.workspaceRoots), [[alternateRootURI], [alternateRootURI]])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
        XCTAssertEqual(lifecycle.events[1].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[1].languageId, "rust")
        XCTAssertEqual(lifecycle.events[1].command, scriptURL.path)

        vc._drainProjectLspPanelLifecycleEventsForTesting()
        let drainedLifecycle = vc._projectLspLifecycleEventsForTesting(after: 0)
        XCTAssertEqual(drainedLifecycle.count, 2)
        XCTAssertEqual(drainedLifecycle.map(\.status), ["requested", "started"])

        XCTAssertTrue(vc.showProjectLspStatusEventsPanel())
        let statusPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectStatusEvents")
        })
        let statusRoot = try XCTUnwrap(statusPanel.contentView)
        let statusTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectStatusEvents"),
                in: statusRoot
            ) as? NSTableView
        )
        XCTAssertEqual(statusTable.numberOfRows, 2)
        let statusTitles = (0..<statusTable.numberOfRows).compactMap { row -> String? in
            (statusTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue
        }
        XCTAssertTrue(
            statusTitles.contains(where: {
                $0.contains("Lifecycle") && $0.contains("started") && $0.contains("rust")
                    && $0.contains("attempt #\(attemptId)")
            }),
            statusTitles.joined(separator: "\n")
        )

        XCTAssertTrue(vc.showProjectLspDashboardPanel())
        let dashboardPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectDashboard")
        })
        let dashboardRoot = try XCTUnwrap(dashboardPanel.contentView)
        let dashboardTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectDashboard"),
                in: dashboardRoot
            ) as? NSTableView
        )
        let dashboardTitles = (0..<dashboardTable.numberOfRows).compactMap { row -> String? in
            (dashboardTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue
        }
        XCTAssertTrue(
            dashboardTitles.contains(where: { $0.contains("Summary -") && $0.contains("lifecycle events 2") }),
            dashboardTitles.joined(separator: "\n")
        )
        XCTAssertTrue(
            dashboardTitles.contains(where: { $0.contains("Summary -") && $0.contains("lifecycle attempts 1") }),
            dashboardTitles.joined(separator: "\n")
        )
        XCTAssertTrue(
            dashboardTitles.contains(where: {
                $0.contains("Lifecycle -") && $0.contains("started") && $0.contains("attempt #\(attemptId)")
            }),
            dashboardTitles.joined(separator: "\n")
        )
    }

    func testProjectLspAutoStartUsesCoreStartPlanLanguageFilter() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("mismatch.rs")
        try "fn main() {}".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("mismatch-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("mismatch-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc._setLspEnvironmentProviderForTesting { ["ATTO_EDITOR_DISABLE_LSP": "1"] }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.first?.languageId, "rust")

        tab.lspServerConfig = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "python"
        )
        vc.syncProjectLspServerConfigsToCore()
        XCTAssertEqual(try vc._coreProjectLspStartPlanForTesting(), [])

        vc._setLspEnvironmentProviderForTesting { [:] }
        XCTAssertEqual(vc.startProjectLspServersForOpenTabs(), 0)
        XCTAssertFalse(try tab.editCore.editor.lspIsEnabled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: captureURL.path))
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 0)
        XCTAssertTrue(lifecycle.events.isEmpty)
    }

    func testProjectLspLaunchConfigsSyncToCoreProjectStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rustURL = tempDir.appendingPathComponent("main.rs")
        let swiftURL = tempDir.appendingPathComponent("App.swift")
        try "fn main() {}".write(to: rustURL, atomically: true, encoding: .utf8)
        try "print(\"hello\")".write(to: swiftURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc._setLspEnvironmentProviderForTesting { ["ATTO_EDITOR_DISABLE_LSP": "1"] }
        vc.openFile(url: rustURL, mode: .pinned)
        let rustTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.first?.languageId, "rust")
        let rustConfig = AttoLspServerLaunchConfig(
            command: "/usr/bin/rust-analyzer",
            args: "--stdio --log-file",
            languageId: "rust"
        )
        rustTab.lspServerConfig = rustConfig
        vc.syncProjectLspServerConfigsToCore()

        var configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        let rustKey = "rust:/usr/bin/rust-analyzer:--stdio:--log-file"
        let rootURI = tempDir.standardizedFileURL.absoluteString
        let projectedRust = try XCTUnwrap(configsByKey[rustKey])
        XCTAssertEqual(projectedRust.command, "/usr/bin/rust-analyzer")
        XCTAssertEqual(projectedRust.args, ["--stdio", "--log-file"])
        XCTAssertEqual(projectedRust.languageId, "rust")
        XCTAssertEqual(projectedRust.workspaceRoots, [rootURI])
        XCTAssertTrue(projectedRust.autoStart)

        vc.openFile(url: swiftURL, mode: .pinned)
        let swiftTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.last?.languageId, "swift")
        let swiftConfig = AttoLspServerLaunchConfig(
            command: "/usr/bin/sourcekit-lsp",
            args: nil,
            languageId: "swift"
        )
        swiftTab.lspServerConfig = swiftConfig
        swiftTab.suppressesAutomaticLspStart = true
        vc.syncProjectLspServerConfigsToCore()

        configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        let swiftKey = "swift:/usr/bin/sourcekit-lsp"
        XCTAssertEqual(Set(configsByKey.keys), [rustKey, swiftKey])
        XCTAssertFalse(try XCTUnwrap(configsByKey[swiftKey]).autoStart)

        vc.closeTab(id: rustTab.id)
        configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        XCTAssertEqual(Set(configsByKey.keys), [swiftKey])

        swiftTab.lspServerConfig = nil
        vc.syncProjectLspServerConfigsToCore()
        XCTAssertEqual(try vc._coreProjectLspServerConfigsForTesting(), [])
    }

    func testProjectLspLaunchConfigsUseCoreWorkspaceRoots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        let extraRoot = tempDir.appendingPathComponent("extra-root", isDirectory: true)
        try FileManager.default.createDirectory(at: extraRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("main.rs")
        try "fn main() {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc._setLspEnvironmentProviderForTesting { ["ATTO_EDITOR_DISABLE_LSP": "1"] }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        tab.lspServerConfig = AttoLspServerLaunchConfig(
            command: "/usr/bin/rust-analyzer",
            args: nil,
            languageId: "rust"
        )

        let rootURI = tempDir.standardizedFileURL.absoluteString
        let extraRootURI = extraRoot.standardizedFileURL.absoluteString
        _ = try XCTUnwrap(vc.coreDocuments).setWorkspaceRootsReturningChange([rootURI, extraRootURI])

        vc.syncProjectLspServerConfigsToCore()

        let config = try XCTUnwrap(try vc._coreProjectLspServerConfigsForTesting().first)
        XCTAssertEqual(config.workspaceRoots, [rootURI, extraRootURI])
    }

    func testClosingConfiguredProjectLspTabRecordsStopOutcome() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("close_project_lsp.txt")
        let plannedRoot = tempDir.appendingPathComponent("close-project-lsp-planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        try "close".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("close-project-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("close-project-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: "--stdio",
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            args: config.args,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        vc.closeTab(id: tab.id)

        XCTAssertFalse(vc.tabs.contains { $0.id == tab.id })
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["stop", "stop"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["tab_close", "tab_close"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "stopped"])
        XCTAssertEqual(lifecycle.events.map(\.workspaceRoots), [[plannedRootURI], [plannedRootURI]])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
        XCTAssertEqual(lifecycle.events[1].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[1].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[1].command, scriptURL.path)
        XCTAssertEqual(lifecycle.events[1].args, ["--stdio"])
    }

    func testPlainTextSyntaxSwitchRecordsProjectLspStopOutcome() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("plain_stop.txt")
        let plannedRoot = tempDir.appendingPathComponent("plain-stop-planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("plain-stop-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("plain-stop-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        vc.setSyntaxLanguageForActiveTab(languageId: nil)

        XCTAssertFalse(try tab.editCore.editor.lspIsEnabled())
        XCTAssertNil(tab.lspServerConfig)
        XCTAssertTrue(tab.suppressesAutomaticLspStart)
        XCTAssertNil(tab.syntaxLanguageId)
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["stop", "stop"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["language_change", "language_change"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "stopped"])
        XCTAssertEqual(lifecycle.events.map(\.workspaceRoots), [[plannedRootURI], [plannedRootURI]])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
        XCTAssertEqual(lifecycle.events[1].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[1].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[1].command, scriptURL.path)
    }

    func testShutdownLspServerRequiresRunningSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("shutdown_unavailable.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.shutdownLspServerInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server shutdown: unavailable")
    }

    func testShutdownLspServerInActiveTabRequiresCoreStopPlanMatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("shutdown_plan_gate.txt")
        try "shutdown".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("shutdown-plan-gate-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("shutdown-plan-gate-fake-lsp.py")
        try writeInlayHintResolveFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(try XCTUnwrap(vc.coreDocuments).closeTab(coreTabID))

        XCTAssertFalse(vc.shutdownLspServerInActiveTab())
        XCTAssertTrue(try tab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server shutdown: unavailable")

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertFalse(captured.contains(#""method":"shutdown""#), captured)
        XCTAssertFalse(captured.contains(#""method":"exit""#), captured)
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 1)
        XCTAssertEqual(lifecycle.events.count, 1)
        XCTAssertEqual(lifecycle.events[0].operation, "stop")
        XCTAssertEqual(lifecycle.events[0].trigger, "manual_shutdown")
        XCTAssertEqual(lifecycle.events[0].status, "skipped")
        XCTAssertEqual(lifecycle.events[0].tabId, coreTabID)
        XCTAssertNil(lifecycle.events[0].attemptId)
        XCTAssertEqual(lifecycle.events[0].errorMessage, "No project LSP stop plan matches this document.")
    }

    func testShutdownLspServerStopsActiveSessionAndRecordsOutcome() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("shutdown_project_lsp.txt")
        try "shutdown".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("shutdown-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("shutdown-fake-lsp.py")
        try writeInlayHintResolveFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        tab.syntaxLanguageId = "plaintext"
        tab.languageSupportSource = .lspServices
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.shutdownLspServerInActiveTab())

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"exit""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
        XCTAssertTrue(captured.contains(#""method":"shutdown""#), captured)
        XCTAssertTrue(captured.contains(#""method":"exit""#), captured)
        XCTAssertFalse(try tab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertTrue(tab.suppressesAutomaticLspStart)
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server shut down")

        let projectedConfig = try XCTUnwrap(try vc._coreProjectLspServerConfigsForTesting().first)
        XCTAssertEqual(projectedConfig.command, scriptURL.path)
        XCTAssertFalse(projectedConfig.autoStart)

        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["stop", "stop"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["manual_shutdown", "manual_shutdown"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "stopped"])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        XCTAssertEqual(lifecycle.events[0].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[1].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[0].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[1].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[0].command, scriptURL.path)
        XCTAssertEqual(lifecycle.events[1].command, scriptURL.path)
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
    }

    func testShutdownProjectLspServersRequiresRunningConfiguredTabs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("shutdown_project_unavailable.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.shutdownProjectLspServers())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server shutdown: unavailable")
    }

    func testShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("shutdown_project_first.txt")
        let secondURL = tempDir.appendingPathComponent("shutdown_project_second.txt")
        let plannedRoot = tempDir.appendingPathComponent("shutdown-project-planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let firstCaptureURL = tempDir.appendingPathComponent("first-shutdown-project-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-shutdown-project-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-shutdown-project-fake-lsp.py")
        let secondScriptURL = tempDir.appendingPathComponent("second-shutdown-project-fake-lsp.py")
        try writeInlayHintResolveFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeInlayHintResolveFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        let firstCoreTabID = try XCTUnwrap(firstTab.coreTabID)
        let firstConfig = AttoLspServerLaunchConfig(
            command: firstScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try firstTab.editCore.editor.lspEnable(
            command: firstConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: firstConfig.languageId
        )
        firstTab.lspServerConfig = firstConfig
        firstTab.syntaxLanguageId = "plaintext"
        firstTab.languageSupportSource = .lspServices

        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        let secondConfig = AttoLspServerLaunchConfig(
            command: secondScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try secondTab.editCore.editor.lspEnable(
            command: secondConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: secondConfig.languageId
        )
        secondTab.lspServerConfig = secondConfig
        secondTab.syntaxLanguageId = "plaintext"
        secondTab.languageSupportSource = .lspServices
        defer {
            firstTab.editCore.editor.lspDisable()
            secondTab.editCore.editor.lspDisable()
        }

        _ = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        _ = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.shutdownProjectLspServers())

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"exit""#
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"exit""#
        )
        for captured in [firstCaptured, secondCaptured] {
            XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
            XCTAssertTrue(captured.contains(#""method":"shutdown""#), captured)
            XCTAssertTrue(captured.contains(#""method":"exit""#), captured)
        }

        XCTAssertFalse(try firstTab.editCore.editor.lspIsEnabled())
        XCTAssertFalse(try secondTab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(firstTab.lspServerConfig, firstConfig)
        XCTAssertEqual(secondTab.lspServerConfig, secondConfig)
        XCTAssertTrue(firstTab.suppressesAutomaticLspStart)
        XCTAssertTrue(secondTab.suppressesAutomaticLspStart)
        XCTAssertEqual(firstTab.languageSupportSource, .plainText)
        XCTAssertEqual(secondTab.languageSupportSource, .plainText)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP servers shut down: 2")

        let projectedConfigs = try vc._coreProjectLspServerConfigsForTesting()
        XCTAssertEqual(projectedConfigs.count, 2)
        XCTAssertTrue(projectedConfigs.allSatisfy { $0.autoStart == false })

        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 4)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["stop", "stop", "stop", "stop"])
        XCTAssertEqual(
            lifecycle.events.map(\.workspaceRoots),
            Array(repeating: [plannedRootURI], count: 4)
        )
        XCTAssertEqual(
            lifecycle.events.map(\.trigger),
            ["project_shutdown", "project_shutdown", "project_shutdown", "project_shutdown"]
        )
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "stopped", "requested", "stopped"])
        let firstAttemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(firstAttemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, firstAttemptId)
        XCTAssertEqual(lifecycle.events[1].tabId, lifecycle.events[0].tabId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
        let secondAttemptId = try XCTUnwrap(lifecycle.events[2].attemptId)
        XCTAssertEqual(secondAttemptId, lifecycle.events[2].sequence)
        XCTAssertEqual(lifecycle.events[3].attemptId, secondAttemptId)
        XCTAssertEqual(lifecycle.events[3].tabId, lifecycle.events[2].tabId)
        XCTAssertEqual(lifecycle.events[3].documentURI, lifecycle.events[2].documentURI)
        XCTAssertEqual(
            Set(lifecycle.events.map(\.tabId)),
            Set([firstCoreTabID, secondCoreTabID])
        )
        XCTAssertEqual(
            Set(lifecycle.events.map(\.documentURI)),
            Set([
                firstURL.standardizedFileURL.absoluteString,
                secondURL.standardizedFileURL.absoluteString,
            ])
        )
        XCTAssertEqual(
            Set(lifecycle.events.map(\.command)),
            Set([firstScriptURL.path, secondScriptURL.path])
        )
    }

    func testRestartLspServerRequiresSavedLaunchConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("plain.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.restartLspServerInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restart: unavailable")
    }

    func testRestartLspServerRestartsActiveTabSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("restart.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("restart-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("restart-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.restartLspServerInActiveTab())

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured),
            2,
            captured
        )
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(#""languageId":"plaintext""#), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(tab.syntaxLanguageId, "plaintext")
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restarted")
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["restart", "restart"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["manual_restart", "manual_restart"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "started"])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        XCTAssertEqual(lifecycle.events[0].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[1].documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(lifecycle.events[0].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[1].languageId, "plaintext")
        XCTAssertEqual(lifecycle.events[0].command, scriptURL.path)
        XCTAssertEqual(lifecycle.events[1].command, scriptURL.path)
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
    }

    func testRestartLspServerInActiveTabUsesCoreRestartPlanRoot() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        let plannedRoot = tempDir.appendingPathComponent("active-planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("restart_plan_root.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("restart-plan-root-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("restart-plan-root-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])

        XCTAssertTrue(vc.restartLspServerInActiveTab())

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: plannedRootURI,
            minimumOccurrences: 1
        )
        XCTAssertGreaterThanOrEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)
        XCTAssertTrue(captured.contains(plannedRootURI), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restarted")
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.events.map(\.workspaceRoots), [[plannedRootURI], [plannedRootURI]])
    }

    func testRestartLspServerInActiveTabRecordsSkippedWhenCorePlanDoesNotMatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("restart_plan_gate.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("restart-plan-gate-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("restart-plan-gate-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(try XCTUnwrap(vc.coreDocuments).closeTab(coreTabID))

        XCTAssertFalse(vc.restartLspServerInActiveTab())
        XCTAssertTrue(try tab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restart: unavailable")

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 1, captured)

        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 1)
        XCTAssertEqual(lifecycle.events.count, 1)
        XCTAssertEqual(lifecycle.events[0].operation, "restart")
        XCTAssertEqual(lifecycle.events[0].trigger, "manual_restart")
        XCTAssertEqual(lifecycle.events[0].status, "skipped")
        XCTAssertEqual(lifecycle.events[0].tabId, coreTabID)
        XCTAssertNil(lifecycle.events[0].attemptId)
        XCTAssertEqual(lifecycle.events[0].errorMessage, "No project LSP restart plan matches this document.")
    }

    func testProjectLspProcessHealthAutoRestartsExitedConfiguredTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured),
            2,
            captured
        )
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server auto-restarted")
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 2)
        XCTAssertEqual(lifecycle.events.count, 2)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["restart", "restart"])
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["auto_restart", "auto_restart"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "started"])
        XCTAssertEqual(lifecycle.events.map(\.tabId), [coreTabID, coreTabID])
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
    }

    func testProjectLspAutoRestartUsesCoreRestartPlanRoot() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        let plannedRoot = tempDir.appendingPathComponent("planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart_plan_root.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-plan-root-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-plan-root-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: plannedRootURI,
            minimumOccurrences: 1
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured),
            2,
            captured
        )
        XCTAssertTrue(captured.contains(plannedRootURI), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.events.map(\.trigger), ["auto_restart", "auto_restart"])
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "started"])
        XCTAssertEqual(lifecycle.events.map(\.workspaceRoots), [[plannedRootURI], [plannedRootURI]])
        let attemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(attemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, attemptId)
    }

    func testProjectLspAutoRestartCanBeDisabledByPreferences() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_lsp_auto_restart_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)

        let fileURL = tempDir.appendingPathComponent("auto_restart_disabled.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-disabled-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
        XCTAssertEqual(occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured), 1, captured)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 1, captured)
    }

    func testProjectLspAutoRestartCanBeDisabledForServerByPreferences() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_lsp_auto_restart_server_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartDisabled(true, forServerName: "fake-lsp", serverCommand: nil)
        XCTAssertTrue(preferences.effectiveLspAutoRestartEnabled)

        let fileURL = tempDir.appendingPathComponent("auto_restart_server_disabled.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-server-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-server-disabled-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
        XCTAssertEqual(occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured), 1, captured)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 1, captured)
    }

    func testProjectLspAutoRestartUsesServerSpecificBackoffPolicy() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart_server_policy.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-server-policy-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-server-policy-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_command_lsp_auto_restart_server_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartMaxAttempts(0)
        preferences.setLspAutoRestartBaseDelaySeconds(30)
        preferences.setLspAutoRestartMaxAttempts(2, forServerName: "fake-lsp", serverCommand: nil)
        preferences.setLspAutoRestartBaseDelaySeconds(1, forServerName: "fake-lsp", serverCommand: nil)

        var now = Date(timeIntervalSince1970: 10_000)
        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        vc._setProjectLspAutoRestartNowProviderForTesting { now }
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let failedStatus = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 321, state: .exited, exitCode: 9, stderrTail: "crash"),
            workspaceFolders: []
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        var captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_000.5)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_001)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 3
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        now = Date(timeIntervalSince1970: 10_002)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)
    }

    func testProjectLspAutoRestartUsesBackoffAndResetsAfterHealthyStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart_backoff.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-backoff-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-backoff-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_command_lsp_auto_restart_backoff_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartMaxAttempts(2)
        preferences.setLspAutoRestartBaseDelaySeconds(2)

        var now = Date(timeIntervalSince1970: 10_000)
        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        vc._setProjectLspAutoRestartNowProviderForTesting { now }
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let failedStatus = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 321, state: .exited, exitCode: 9, stderrTail: "crash"),
            workspaceFolders: []
        )
        let healthyStatus = EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: nil,
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 322, state: .running),
            workspaceFolders: []
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        var captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_001)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_002)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 3
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        now = Date(timeIntervalSince1970: 10_006)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: healthyStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
    }

    func testRestartProjectLspServersRequiresConfiguredTabs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("plain.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.restartProjectLspServers())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restart: unavailable")
    }

    func testRestartProjectLspServersRestartsConfiguredOpenTabs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        let plannedRoot = tempDir.appendingPathComponent("project-restart-planned-root", isDirectory: true)
        try FileManager.default.createDirectory(at: plannedRoot, withIntermediateDirectories: true)
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let firstCaptureURL = tempDir.appendingPathComponent("first-project-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-project-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-project-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-project-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeAppendingFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let plannedRootURI = plannedRoot.standardizedFileURL.absoluteString
        try vc.coreDocuments?.setWorkspaceRoots([plannedRootURI])
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        let firstConfig = AttoLspServerLaunchConfig(
            command: firstScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try firstTab.editCore.editor.lspEnable(
            command: firstConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: firstConfig.languageId
        )
        firstTab.lspServerConfig = firstConfig

        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        let secondConfig = AttoLspServerLaunchConfig(
            command: secondScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try secondTab.editCore.editor.lspEnable(
            command: secondConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: secondConfig.languageId
        )
        secondTab.lspServerConfig = secondConfig
        defer {
            firstTab.editCore.editor.lspDisable()
            secondTab.editCore.editor.lspDisable()
        }

        _ = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        _ = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.restartProjectLspServers())

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: "--session--", in: firstCaptured),
            2,
            firstCaptured
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: "--session--", in: secondCaptured),
            2,
            secondCaptured
        )
        XCTAssertTrue(firstCaptured.contains(firstURL.standardizedFileURL.absoluteString), firstCaptured)
        XCTAssertTrue(secondCaptured.contains(secondURL.standardizedFileURL.absoluteString), secondCaptured)
        XCTAssertTrue(firstCaptured.contains(plannedRootURI), firstCaptured)
        XCTAssertTrue(secondCaptured.contains(plannedRootURI), secondCaptured)
        XCTAssertEqual(firstTab.lspServerConfig, firstConfig)
        XCTAssertEqual(secondTab.lspServerConfig, secondConfig)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP servers restarted: 2")
        let lifecycle = try XCTUnwrap(try vc._coreProjectLspLifecycleEventsForTesting())
        XCTAssertEqual(lifecycle.latestSequence, 4)
        XCTAssertEqual(lifecycle.events.map(\.operation), ["restart", "restart", "restart", "restart"])
        XCTAssertEqual(
            lifecycle.events.map(\.workspaceRoots),
            Array(repeating: [plannedRootURI], count: 4)
        )
        XCTAssertEqual(
            lifecycle.events.map(\.trigger),
            ["project_restart", "project_restart", "project_restart", "project_restart"]
        )
        XCTAssertEqual(lifecycle.events.map(\.status), ["requested", "started", "requested", "started"])
        let firstAttemptId = try XCTUnwrap(lifecycle.events[0].attemptId)
        XCTAssertEqual(firstAttemptId, lifecycle.events[0].sequence)
        XCTAssertEqual(lifecycle.events[1].attemptId, firstAttemptId)
        XCTAssertEqual(lifecycle.events[1].documentURI, lifecycle.events[0].documentURI)
        let secondAttemptId = try XCTUnwrap(lifecycle.events[2].attemptId)
        XCTAssertEqual(secondAttemptId, lifecycle.events[2].sequence)
        XCTAssertEqual(lifecycle.events[3].attemptId, secondAttemptId)
        XCTAssertEqual(lifecycle.events[3].documentURI, lifecycle.events[2].documentURI)
        XCTAssertEqual(
            Set(lifecycle.events.map(\.documentURI)),
            Set([
                firstURL.standardizedFileURL.absoluteString,
                secondURL.standardizedFileURL.absoluteString,
            ])
        )
    }
}
