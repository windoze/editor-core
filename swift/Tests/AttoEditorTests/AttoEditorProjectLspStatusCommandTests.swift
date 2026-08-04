import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testProjectLspPanelRecordsStatusFailures() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let cursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()

        XCTAssertFalse(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: nil,
            capabilities: nil,
            workspaceFolders: []
        )))

        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: nil, version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 123,
                state: .exited,
                exitCode: 7,
                stderrTail: "fatal: missing workspace\nlast line"
            ),
            workspaceFolders: [
                EcuLspWorkspaceFolder(uri: tempDir.absoluteString, name: tempDir.lastPathComponent),
            ]
        )))

        let events = vc._projectLspPanelErrorEventsForTesting(after: cursor)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].source, .status)
        XCTAssertEqual(events[0].family, "lsp")
        XCTAssertEqual(events[0].slot, "lsp_status")
        XCTAssertEqual(events[0].method, "lsp/status")
        XCTAssertEqual(events[0].requestId, 0)
        XCTAssertEqual(events[0].status, "failed")
        XCTAssertTrue(events[0].title.contains("LSP fake-lsp"))
        XCTAssertTrue(events[0].title.contains("Failed"))
        XCTAssertTrue(events[0].message.contains("server exited"))
        XCTAssertTrue(events[0].message.contains("stderr:"))
        XCTAssertTrue(events[0].message.contains("fatal: missing workspace"))
        XCTAssertTrue(events[0].message.contains("last line"))
    }

    func testProjectLspProcessHealthRecordsStatusSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let cursor = vc._latestProjectLspProcessHealthEventSequenceForTesting()

        XCTAssertFalse(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .disabled,
            state: .disabled,
            server: nil,
            activity: nil,
            detail: nil,
            capabilities: nil,
            workspaceFolders: []
        )))

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: nil,
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 456, state: .running),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: nil, version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 456,
                state: .exited,
                exitCode: 7,
                stderrTail: "health stderr"
            ),
            workspaceFolders: []
        )))

        let events = vc._projectLspProcessHealthEventsForTesting(after: cursor)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].availability, "enabled")
        XCTAssertEqual(events[0].state, "ready")
        XCTAssertEqual(events[0].process.pid, 456)
        XCTAssertEqual(events[0].process.state, .running)
        XCTAssertEqual(events[1].availability, "failed")
        XCTAssertEqual(events[1].state, "failed")
        XCTAssertEqual(events[1].detail, "server exited\nstderr:\nhealth stderr")
        XCTAssertEqual(events[1].process.state, .exited)
        XCTAssertEqual(events[1].process.exitCode, 7)
        XCTAssertEqual(events[1].process.stderrTail, "health stderr")
    }

    func testProjectLspStatusEventsPanelShowsRecordedFailures() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspStatusEventsPanel())
        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "panel stderr tail"
            ),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc.showProjectLspStatusEventsPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectStatusEvents")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectStatusEvents"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP status events...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectStatusEvents"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Status") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("server exited") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("panel stderr tail") == true)
    }

    func testProjectLspProcessHealthPanelShowsRecordedStatusSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let suiteName = "atto_command_lsp_dashboard_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)
        preferences.setLspAutoRestartMaxAttempts(7)
        preferences.setLspAutoRestartBaseDelaySeconds(2.5)

        let vc = makeEditorArea(
            workspaceRootURL: tempDir,
            preferences: preferences,
            projectLspProcessHealthLogStore: logStore
        )
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspProcessHealthPanel())
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "health panel stderr"
            ),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc.showProjectLspProcessHealthPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealth")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP process health...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Health") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("fake-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("failed/failed") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 321 exit 9") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("health panel stderr") == true)
    }

    func testProjectLspDashboardPanelShowsStatusAndHealthSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let suiteName = "atto_command_lsp_dashboard_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)
        preferences.setLspAutoRestartMaxAttempts(7)
        preferences.setLspAutoRestartBaseDelaySeconds(2.5)

        let vc = makeEditorArea(
            workspaceRootURL: tempDir,
            preferences: preferences,
            projectLspProcessHealthLogStore: logStore
        )
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspDashboardPanel())
        let status = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "dashboard stderr"
            ),
            workspaceFolders: []
        )
        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: status))
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: status))
        XCTAssertTrue(vc.showProjectLspDashboardPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectDashboard")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectDashboard"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP project health...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectDashboard"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 17)

        let summaryCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("Summary -") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("status failures 1") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("lifecycle attempts 0") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("health events 1") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("persisted logs 1") == true)

        let policyCell = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)
        let policyTitle = policyCell.textField?.stringValue ?? ""
        XCTAssertTrue(policyTitle.contains("Recovery Policy -"), policyTitle)
        XCTAssertTrue(policyTitle.contains("auto-restart off"), policyTitle)
        XCTAssertTrue(policyTitle.contains("max attempts 7"), policyTitle)
        XCTAssertTrue(policyTitle.contains("base delay 2.5s"), policyTitle)

        let actionCell = try XCTUnwrap(table.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSTableCellView)
        let actionTitle = actionCell.textField?.stringValue ?? ""
        XCTAssertTrue(actionTitle.contains("Recovery Action - Enable auto-restart"), actionTitle)

        let increaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (increaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Increase max attempts to 8")
        )
        let decreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 4, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (decreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease max attempts to 6")
        )
        let increaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 5, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (increaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Increase base delay to 3.5s")
        )
        let decreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 6, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (decreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease base delay to 1.5s")
        )

        let trendCell = try XCTUnwrap(table.view(atColumn: 0, row: 7, makeIfNecessary: true) as? NSTableCellView)
        let trendTitle = trendCell.textField?.stringValue ?? ""
        XCTAssertTrue(trendTitle.contains("Trend - persisted logs"), trendTitle)
        XCTAssertTrue(trendTitle.contains("last 1h 1 failed 1"), trendTitle)
        XCTAssertTrue(trendTitle.contains("last 24h 1 failed 1"), trendTitle)

        let serverCell = try XCTUnwrap(table.view(atColumn: 0, row: 8, makeIfNecessary: true) as? NSTableCellView)
        let serverTitle = serverCell.textField?.stringValue ?? ""
        XCTAssertTrue(serverTitle.contains("Server - fake-lsp"), serverTitle)
        XCTAssertTrue(serverTitle.contains("health events 1 failed 1"), serverTitle)
        XCTAssertTrue(serverTitle.contains("persisted logs 1 failed 1"), serverTitle)
        XCTAssertTrue(serverTitle.contains("recovery enabled"), serverTitle)
        XCTAssertTrue(serverTitle.contains("max attempts 7"), serverTitle)
        XCTAssertTrue(serverTitle.contains("base delay 2.5s"), serverTitle)
        XCTAssertTrue(serverTitle.contains("global policy"), serverTitle)
        XCTAssertTrue(serverTitle.contains("latest process exited"), serverTitle)

        let serverActionCell = try XCTUnwrap(table.view(atColumn: 0, row: 9, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverActionCell.textField?.stringValue ?? "").contains("Recovery Action - Disable auto-restart for fake-lsp")
        )

        let serverResetPolicyCell = try XCTUnwrap(table.view(atColumn: 0, row: 10, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverResetPolicyCell.textField?.stringValue ?? "").contains("Recovery Action - Reset recovery policy for fake-lsp to global")
        )

        let serverIncreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 11, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverIncreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Increase max attempts for fake-lsp to 8")
        )
        let serverDecreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 12, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverDecreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease max attempts for fake-lsp to 6")
        )
        let serverIncreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 13, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverIncreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Increase base delay for fake-lsp to 3.5s")
        )
        let serverDecreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 14, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverDecreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease base delay for fake-lsp to 1.5s")
        )

        let statusCell = try XCTUnwrap(table.view(atColumn: 0, row: 15, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(statusCell.textField?.stringValue.contains("Status -") == true)
        XCTAssertTrue(statusCell.textField?.stringValue.contains("server exited") == true)

        let healthCell = try XCTUnwrap(table.view(atColumn: 0, row: 16, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("Health -") == true)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("fake-lsp") == true)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("dashboard stderr") == true)

        XCTAssertFalse(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(id: "lsp.project_dashboard.server_recovery.0"))
        XCTAssertTrue(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart disabled for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 7)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.increase_max_attempts.0"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 8)
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 7)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart max attempts 8 for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 2.5)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.increase_base_delay.0"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 3.5)
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 2.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart base delay 3.5s for fake-lsp")

        XCTAssertTrue(preferences.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.reset_policy.0"
        ))
        XCTAssertFalse(preferences.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertFalse(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 7)
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 2.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart policy reset for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 7)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.increase_auto_restart_max_attempts"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 8)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart max attempts 8")

        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 2.5)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.increase_auto_restart_base_delay"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 3.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart base delay 3.5s")

        XCTAssertFalse(preferences.effectiveLspAutoRestartEnabled)
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let controller = try XCTUnwrap(searchField.delegate as? AttoCommandPaletteController)
        XCTAssertTrue(controller.control(
            searchField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertTrue(preferences.effectiveLspAutoRestartEnabled)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart enabled")
    }

    func testProjectLspProcessHealthPanelFallsBackToPersistedLog() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 3,
                sourceSequence: 30,
                tabId: 77,
                viewIndex: 0,
                viewId: 700,
                serverName: "persisted-lsp",
                serverCommand: "persisted-lsp",
                availability: "failed",
                state: "failed",
                detail: "persisted exit",
                process: EcuLspProcessStatus(
                    pid: 999,
                    state: .exited,
                    exitCode: 12,
                    stderrTail: "persisted stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertEqual(vc._projectLspProcessHealthEventsForTesting(after: 0), [])
        XCTAssertTrue(vc.showProjectLspProcessHealthPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealth")
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 999 exit 12") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted stderr") == true)
    }

    func testProjectLspProcessHealthLogPanelShowsPersistedLog() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "failed",
                state: "failed",
                detail: "other exit",
                process: EcuLspProcessStatus(pid: 100, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 1,
                viewId: 200,
                serverName: "persisted-lsp",
                serverCommand: "persisted-lsp",
                availability: "failed",
                state: "failed",
                detail: "persisted exit",
                process: EcuLspProcessStatus(
                    pid: 999,
                    state: .exited,
                    exitCode: 12,
                    stderrTail: "persisted stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertTrue(vc.showProjectLspProcessHealthLogPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealthLog")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP process health log...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 999 exit 12") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted stderr") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("other-lsp") == true)
    }

    func testProjectLspProcessHealthLogPanelUsesFieldFilterQuery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "rust-analyzer",
                serverCommand: "rust-analyzer",
                availability: "failed",
                state: "failed",
                detail: "rust exit",
                process: EcuLspProcessStatus(
                    pid: 101,
                    state: .exited,
                    exitCode: 1,
                    stderrTail: "rust stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 1,
                viewId: 200,
                serverName: "pyright",
                serverCommand: "pyright-langserver",
                availability: "failed",
                state: "failed",
                detail: "pyright exit",
                process: EcuLspProcessStatus(
                    pid: 202,
                    state: .exited,
                    exitCode: 2,
                    stderrTail: "pyright stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertTrue(vc.showProjectLspProcessHealthLogPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealthLog")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "server:pyright process:exited"
        vc.projectLspProcessHealthLogController?.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )

        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("pyright") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("rust-analyzer") == true)
    }

    func testClearProjectLspProcessHealthLogClearsCurrentWorkspaceOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 0,
                viewId: 200,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 202, state: .running)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertTrue(vc.clearProjectLspProcessHealthLog(confirmBeforeClearing: false))
        XCTAssertFalse(vc.showProjectLspProcessHealthLogPanel())
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10), [])
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: otherRoot, limit: 10).map(\.serverName), ["other-lsp"])
        XCTAssertFalse(vc.clearProjectLspProcessHealthLog(confirmBeforeClearing: false))
    }

    func testClearProjectLspProcessHealthLogCanBeCancelledByConfirmation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertFalse(vc.clearProjectLspProcessHealthLog(confirmationProvider: { false }))
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10).map(\.serverName), ["current-lsp"])

        XCTAssertTrue(vc.clearProjectLspProcessHealthLog(confirmationProvider: { true }))
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10), [])
    }

    func testExportProjectLspProcessHealthLogExportsCurrentWorkspaceOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        let emptyRoot = tempDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 0,
                viewId: 200,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 202, state: .running)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let exportURL = tempDir.appendingPathComponent("exports/current.jsonl")
        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertTrue(vc.exportProjectLspProcessHealthLog(to: exportURL))
        let exported = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exported.contains("current-lsp"))
        XCTAssertFalse(exported.contains("other-lsp"))
        XCTAssertEqual(exported.split(whereSeparator: \.isNewline).count, 1)

        let emptyExportURL = tempDir.appendingPathComponent("exports/empty.jsonl")
        let emptyVC = makeEditorArea(workspaceRootURL: emptyRoot, projectLspProcessHealthLogStore: logStore)
        XCTAssertFalse(emptyVC.exportProjectLspProcessHealthLog(to: emptyExportURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyExportURL.path))
    }
}
