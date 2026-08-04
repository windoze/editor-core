import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        XCTAssertEqual(try multi.stateEventsLatestSequence(), 0)
        let stateEvents = try multi.stateEvents()
        XCTAssertEqual(stateEvents.latestSequence, 0)
        XCTAssertTrue(stateEvents.events.isEmpty)

        let alpha = try multi.openTab(text: "alpha world", viewportWidthCells: 80)
        let beta = try multi.openTab(text: "beta world", viewportWidthCells: 80)
        XCTAssertNotEqual(alpha, beta)

        try multi.setTabDocumentURI("file:///project/main.rs", tabId: alpha)
        try multi.setTabLanguageId("rust", tabId: alpha)
        try multi.setTabTitle("Beta", tabId: beta)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: beta)
        XCTAssertEqual(try multi.tabDocumentURI(tabId: beta), "file:///project/Beta.swift")
        try multi.setTabLanguageId(" swift ", tabId: beta)
        XCTAssertEqual(try multi.tabLanguageId(tabId: beta), "swift")
        try multi.setWorkspaceRoots([
            "file:///project",
            "file:///project",
            "file:///other",
        ])
        XCTAssertEqual(try multi.snapshot().workspaceRoots, ["file:///project", "file:///other"])
        let rootsChange = try multi.setWorkspaceRootsReturningChange([
            "file:///other",
            "file:///new",
            "file:///new",
        ])
        XCTAssertEqual(
            rootsChange.added,
            [EcuLspWorkspaceFolder(uri: "file:///new", name: "new")]
        )
        XCTAssertEqual(
            rootsChange.removed,
            [EcuLspWorkspaceFolder(uri: "file:///project", name: "project")]
        )
        XCTAssertEqual(try multi.snapshot().workspaceRoots, ["file:///other", "file:///new"])

        try multi.rememberRecentFileURI(" file:///new/main.rs ")
        try multi.rememberRecentFileURI("file:///new/App.swift")
        try multi.rememberRecentFileURI("file:///new/main.rs")
        XCTAssertEqual(
            try multi.recentFiles(),
            [
                EcuRecentFileEntry(uri: "file:///new/main.rs"),
                EcuRecentFileEntry(uri: "file:///new/App.swift"),
            ]
        )
        XCTAssertEqual(try multi.snapshot().recentFiles.map(\.uri), [
            "file:///new/main.rs",
            "file:///new/App.swift",
        ])
        try multi.restoreRecentFileURIs(["file:///new/restored.rs", "file:///new/main.rs"])
        XCTAssertEqual(try multi.recentFiles().map(\.uri), [
            "file:///new/restored.rs",
            "file:///new/main.rs",
        ])
        try multi.clearRecentFiles()
        XCTAssertTrue(try multi.recentFiles().isEmpty)

        try multi.rememberRecentProjectURI(" file:///new ")
        try multi.rememberRecentProjectURI("file:///other")
        try multi.rememberRecentProjectURI("file:///new")
        XCTAssertEqual(
            try multi.recentProjects(),
            [
                EcuRecentProjectEntry(uri: "file:///new"),
                EcuRecentProjectEntry(uri: "file:///other"),
            ]
        )
        XCTAssertEqual(try multi.snapshot().recentProjects.map(\.uri), [
            "file:///new",
            "file:///other",
        ])
        try multi.restoreRecentProjectURIs(["file:///restored", "file:///new"])
        XCTAssertEqual(try multi.recentProjects().map(\.uri), [
            "file:///restored",
            "file:///new",
        ])
        try multi.clearRecentProjects()
        XCTAssertTrue(try multi.recentProjects().isEmpty)

        try multi.setProjectLspServers([
            EcuProjectLspServerConfig(
                key: " Rust ",
                command: " /bin/rust-analyzer ",
                args: [" ", "--stdio "],
                languageId: " rust ",
                languageName: " Rust Language ",
                serverCapabilities: .object([
                    "semantic_tokens": .bool(true),
                    "completion": .object(["supported": .bool(true)]),
                ]),
                sharedSession: true,
                workspaceRoots: ["file:///new", "file:///new", " file:///other "],
                workspaceFolders: [
                    EcuProjectLspWorkspaceFolder(
                        uri: " file:///new ",
                        name: " New Root ",
                        rootAlias: " primary "
                    ),
                ]
            ),
            EcuProjectLspServerConfig(
                key: "",
                command: "/bin/sourcekit-lsp",
                languageId: "swift",
                sharedSession: false,
                autoStart: false
            ),
        ])
        let lspServers = try multi.projectLspServers()
        XCTAssertEqual(lspServers.map(\.key), ["rust", "swift"])
        XCTAssertEqual(lspServers[0].command, "/bin/rust-analyzer")
        XCTAssertEqual(lspServers[0].args, ["--stdio"])
        XCTAssertEqual(lspServers[0].languageId, "rust")
        XCTAssertEqual(lspServers[0].languageName, "Rust Language")
        XCTAssertEqual(lspServers[0].serverCapabilities, .object([
            "completion": .object(["supported": .bool(true)]),
            "semantic_tokens": .bool(true),
        ]))
        XCTAssertTrue(lspServers[0].sharedSession)
        XCTAssertEqual(lspServers[0].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(lspServers[0].workspaceFolders, [
            EcuProjectLspWorkspaceFolder(
                uri: "file:///new",
                name: "New Root",
                rootAlias: "primary"
            ),
            EcuProjectLspWorkspaceFolder(
                uri: "file:///other",
                name: "other"
            ),
        ])
        XCTAssertEqual(lspServers[1].languageName, "swift")
        XCTAssertEqual(lspServers[1].serverCapabilities, .object([:]))
        XCTAssertFalse(lspServers[1].sharedSession)
        XCTAssertFalse(lspServers[1].autoStart)
        XCTAssertEqual(try multi.snapshot().projectLspServers, lspServers)
        let startPlan = try multi.projectLspStartPlan()
        XCTAssertEqual(startPlan.count, 1)
        XCTAssertEqual(startPlan[0].operation, "start")
        XCTAssertEqual(startPlan[0].tabId, alpha)
        XCTAssertEqual(startPlan[0].activeViewIndex, 0)
        XCTAssertEqual(startPlan[0].documentURI, "file:///project/main.rs")
        XCTAssertEqual(startPlan[0].languageId, "rust")
        XCTAssertEqual(startPlan[0].languageName, "Rust Language")
        XCTAssertEqual(startPlan[0].serverCapabilities, lspServers[0].serverCapabilities)
        XCTAssertTrue(startPlan[0].sharedSession)
        XCTAssertEqual(startPlan[0].serverKey, "rust")
        XCTAssertEqual(startPlan[0].command, "/bin/rust-analyzer")
        XCTAssertEqual(startPlan[0].args, ["--stdio"])
        XCTAssertEqual(startPlan[0].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(startPlan[0].workspaceFolders, lspServers[0].workspaceFolders)
        let stopPlan = try multi.projectLspStopPlan()
        XCTAssertEqual(stopPlan.count, 2)
        XCTAssertEqual(stopPlan.map(\.operation), ["stop", "stop"])
        XCTAssertEqual(stopPlan[0].tabId, alpha)
        XCTAssertEqual(stopPlan[0].documentURI, "file:///project/main.rs")
        XCTAssertEqual(stopPlan[0].serverKey, "rust")
        XCTAssertEqual(stopPlan[0].languageName, "Rust Language")
        XCTAssertEqual(stopPlan[0].serverCapabilities, lspServers[0].serverCapabilities)
        XCTAssertTrue(stopPlan[0].sharedSession)
        XCTAssertEqual(stopPlan[0].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(stopPlan[0].workspaceFolders, lspServers[0].workspaceFolders)
        XCTAssertEqual(stopPlan[1].tabId, beta)
        XCTAssertEqual(stopPlan[1].documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(stopPlan[1].serverKey, "swift")
        XCTAssertEqual(stopPlan[1].command, "/bin/sourcekit-lsp")
        XCTAssertEqual(stopPlan[1].languageName, "swift")
        XCTAssertEqual(stopPlan[1].serverCapabilities, .object([:]))
        XCTAssertFalse(stopPlan[1].sharedSession)
        XCTAssertEqual(stopPlan[1].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(stopPlan[1].workspaceFolders.map(\.name), ["new", "other"])
        let restartPlan = try multi.projectLspRestartPlan()
        XCTAssertEqual(restartPlan.count, 2)
        XCTAssertEqual(restartPlan.map(\.operation), ["restart", "restart"])
        XCTAssertEqual(restartPlan[0].tabId, alpha)
        XCTAssertEqual(restartPlan[0].documentURI, "file:///project/main.rs")
        XCTAssertEqual(restartPlan[0].serverKey, "rust")
        XCTAssertEqual(restartPlan[0].languageName, "Rust Language")
        XCTAssertEqual(restartPlan[0].serverCapabilities, lspServers[0].serverCapabilities)
        XCTAssertTrue(restartPlan[0].sharedSession)
        XCTAssertEqual(restartPlan[0].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(restartPlan[0].workspaceFolders, lspServers[0].workspaceFolders)
        XCTAssertEqual(restartPlan[1].tabId, beta)
        XCTAssertEqual(restartPlan[1].documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(restartPlan[1].serverKey, "swift")
        XCTAssertEqual(restartPlan[1].command, "/bin/sourcekit-lsp")
        XCTAssertEqual(restartPlan[1].languageName, "swift")
        XCTAssertEqual(restartPlan[1].serverCapabilities, .object([:]))
        XCTAssertFalse(restartPlan[1].sharedSession)
        XCTAssertEqual(restartPlan[1].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertEqual(restartPlan[1].workspaceFolders.map(\.name), ["new", "other"])

        try multi.recordProjectLspStartOutcome(EcuProjectLspStartOutcome(
            tabId: alpha,
            activeViewIndex: 0,
            documentURI: "file:///project/main.rs",
            languageId: "rust",
            languageName: "Rust Language",
            serverCapabilities: .object(["hover": .bool(true)]),
            sharedSession: false,
            serverKey: "rust",
            command: "/bin/rust-analyzer",
            args: ["--stdio"],
            workspaceRoots: ["file:///new", "file:///other"],
            status: "started"
        ))
        try multi.recordProjectLspStartOutcome(EcuProjectLspStartOutcome(
            tabId: alpha,
            activeViewIndex: 0,
            operation: "restart",
            documentURI: "file:///project/main.rs",
            languageId: "rust",
            serverKey: "rust",
            command: "/bin/rust-analyzer",
            args: ["--stdio"],
            workspaceRoots: ["file:///new", "file:///other"],
            trigger: "manual_restart",
            status: "started"
        ))
        try multi.recordProjectLspStartOutcome(EcuProjectLspStartOutcome(
            tabId: alpha,
            activeViewIndex: 0,
            operation: "stop",
            documentURI: "file:///project/main.rs",
            languageId: "rust",
            serverKey: "rust",
            command: "/bin/rust-analyzer",
            args: ["--stdio"],
            workspaceRoots: ["file:///new", "file:///other"],
            trigger: "tab_close",
            status: "stopped"
        ))
        XCTAssertEqual(try multi.projectLspLifecycleEventsLatestSequence(), 3)
        let lifecycleEvents = try multi.projectLspLifecycleEvents()
        XCTAssertEqual(lifecycleEvents.latestSequence, 3)
        XCTAssertEqual(lifecycleEvents.events.count, 3)
        XCTAssertEqual(lifecycleEvents.events[0].workspaceFolders.map(\.name), ["new", "other"])
        XCTAssertEqual(lifecycleEvents.events[0].operation, "start")
        XCTAssertEqual(lifecycleEvents.events[0].status, "started")
        XCTAssertEqual(lifecycleEvents.events[0].tabId, alpha)
        XCTAssertEqual(lifecycleEvents.events[0].documentURI, "file:///project/main.rs")
        XCTAssertEqual(lifecycleEvents.events[0].languageName, "Rust Language")
        XCTAssertEqual(lifecycleEvents.events[0].serverCapabilities, .object(["hover": .bool(true)]))
        XCTAssertFalse(lifecycleEvents.events[0].sharedSession)
        XCTAssertEqual(lifecycleEvents.events[1].operation, "restart")
        XCTAssertEqual(lifecycleEvents.events[1].trigger, "manual_restart")
        XCTAssertEqual(lifecycleEvents.events[2].operation, "stop")
        XCTAssertEqual(lifecycleEvents.events[2].trigger, "tab_close")
        XCTAssertEqual(lifecycleEvents.events[2].status, "stopped")
        XCTAssertEqual(try multi.projectLspLifecycleEvents(after: 3).events, [])

        try multi.setActiveTab(beta)
        XCTAssertEqual(try multi.activeTabId(), beta)

        XCTAssertTrue(try multi.moveTab(fromIndex: 1, toIndex: 0))
        let movedSnapshot = try multi.snapshot()
        XCTAssertEqual(movedSnapshot.tabs.map(\.id), [beta, alpha])
        XCTAssertEqual(movedSnapshot.tabs.first?.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(movedSnapshot.tabs.first?.languageId, "swift")
        XCTAssertTrue(try multi.moveTab(fromIndex: 0, toIndex: 1))
        XCTAssertEqual(try multi.snapshot().tabs.map(\.id), [alpha, beta])

        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 1)
        XCTAssertEqual(try multi.viewCount(tabId: beta), 2)
        XCTAssertTrue(try multi.closeView(tabId: beta, viewIndex: 1))
        XCTAssertEqual(try multi.viewCount(tabId: beta), 1)
        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 1)
        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 2)
        XCTAssertTrue(try multi.moveView(tabId: beta, fromIndex: 2, toIndex: 0))
        XCTAssertFalse(try multi.moveView(tabId: beta, fromIndex: 0, toIndex: 0))

        try multi.replaceTabText(tabId: beta, text: "beta mirror", markSaved: false)
        XCTAssertEqual(try multi.tabText(tabId: beta), "beta mirror")
        XCTAssertTrue(try multi.isTabModified(beta))
        try multi.markTabSaved(beta)
        XCTAssertFalse(try multi.isTabModified(beta))
        try multi.replaceTabText(tabId: beta, text: "beta saved mirror", markSaved: true)
        XCTAssertFalse(try multi.isTabModified(beta))

        let preview = try multi.openPreviewTab(text: "preview one", viewportWidthCells: 80)
        let reusedPreview = try multi.openPreviewTab(text: "preview two", viewportWidthCells: 80)
        XCTAssertEqual(reusedPreview, preview)
        XCTAssertTrue(try multi.isPreviewTab(preview))

        try multi.pinTab(preview)
        XCTAssertFalse(try multi.isPreviewTab(preview))

        let results = try multi.searchAllTabs(query: "mirror")
        XCTAssertEqual(results.map(\.tabId), [beta])
        XCTAssertEqual(results.flatMap(\.matches).count, 1)

        let workspaceEdit = """
        {
          "changes": {
            "file:///project/Beta.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 4 }
                },
                "newText": "BETA"
              }
            ],
            "file:///project/Missing.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "missing"
              }
            ]
          }
        }
        """
        let transactionPreview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(transactionPreview.mode, "preview")
        XCTAssertFalse(transactionPreview.applied)
        XCTAssertEqual(transactionPreview.skippedURIs, ["file:///project/Missing.swift"])
        XCTAssertTrue(transactionPreview.skippedDetails.contains {
            $0.uri == "file:///project/Missing.swift"
                && $0.operation == "text_edit"
                && $0.reason == "file_not_found"
        })
        let betaTransactionDocument = try XCTUnwrap(
            transactionPreview.documents.first { $0.uri == "file:///project/Beta.swift" }
        )
        XCTAssertTrue(betaTransactionDocument.isOpen)
        XCTAssertEqual(betaTransactionDocument.tabId, beta)

        let transactionApply = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(transactionApply.mode, "apply")
        XCTAssertTrue(transactionApply.applied)
        XCTAssertEqual(transactionApply.appliedURIs, ["file:///project/Beta.swift"])
        XCTAssertEqual(transactionApply.appliedEditCount, 1)
        XCTAssertEqual(transactionApply.appliedResourceOperationCount, 0)

        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let transactionEvents = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(transactionEvents.latestSequence, 1)
        XCTAssertEqual(transactionEvents.events.map(\.operation), ["apply"])
        XCTAssertEqual(transactionEvents.events.first?.result.appliedURIs, ["file:///project/Beta.swift"])

        XCTAssertEqual(try multi.tabText(tabId: beta), "BETA saved mirror")
        try multi.markTabSaved(beta)

        try multi.applyTabDocumentSymbolsJSON(tabId: beta, resultJSON: """
        [
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 16 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 9 }
            }
          }
        ]
        """)
        let outline = try multi.workspaceOutlineSnapshot()
        XCTAssertEqual(outline.documents.count, 3)
        let betaOutline = try XCTUnwrap(outline.documents.first { $0.tabId == beta })
        XCTAssertEqual(betaOutline.title, "Beta")
        XCTAssertEqual(betaOutline.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(betaOutline.viewIndex, 0)
        XCTAssertEqual(betaOutline.symbolCount, 1)
        XCTAssertEqual(betaOutline.symbols.map(\.name), ["Beta"])

        let diagnostics = try multi.applyWorkspaceDiagnosticsJSON("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                  },
                  "severity": 1,
                  "message": "first problem"
                }
              ]
            }
          ]
        }
        """)
        XCTAssertEqual(diagnostics.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(diagnostics.diagnostics.first?.severityLabel, "error")
        XCTAssertEqual(
            try multi.workspaceDiagnosticMarkersSnapshot().markers,
            [
                EcuWorkspaceDiagnosticMarker(
                    uri: "file:///project/a.swift",
                    line: 0,
                    utf16Character: 1,
                    severity: 1,
                    severityLabel: "error"
                ),
            ]
        )

        let previousResultIds = try JSONSerialization.jsonObject(
            with: Data(try multi.workspaceDiagnosticsPreviousResultIdsJSON().utf8),
            options: []
        ) as? [[String: String]]
        XCTAssertEqual(previousResultIds, [["uri": "file:///project/a.swift", "value": "a-1"]])
        XCTAssertEqual(try multi.workspaceDiagnosticsLatestEventSequence(), 1)
        let diagnosticEvents = try multi.workspaceDiagnosticsEvents()
        XCTAssertEqual(diagnosticEvents.latestSequence, 1)
        XCTAssertEqual(diagnosticEvents.events.count, 1)
        XCTAssertEqual(diagnosticEvents.events[0].family, "workspace_diagnostics")
        XCTAssertEqual(diagnosticEvents.events[0].operation, "apply")
        XCTAssertEqual(diagnosticEvents.events[0].documentCount, 1)
        XCTAssertEqual(diagnosticEvents.events[0].diagnosticCount, 1)
        XCTAssertEqual(diagnosticEvents.events[0].markerCount, 1)

        try multi.clearWorkspaceDiagnostics()
        XCTAssertTrue(try multi.workspaceDiagnosticsSnapshot().diagnostics.isEmpty)
        let clearEvents = try multi.workspaceDiagnosticsEvents(after: 1)
        XCTAssertEqual(clearEvents.latestSequence, 2)
        XCTAssertEqual(clearEvents.events.map(\.operation), ["clear"])
        XCTAssertEqual(clearEvents.events[0].diagnosticCount, 0)

        XCTAssertEqual(try multi.lspResultEventsLatestSequence(), 0)
        let lspEvents = try multi.lspResultEvents()
        XCTAssertEqual(lspEvents.latestSequence, 0)
        XCTAssertTrue(lspEvents.events.isEmpty)

        XCTAssertEqual(try multi.lspRequestEventsLatestSequence(), 0)
        let lspRequestEvents = try multi.lspRequestEvents()
        XCTAssertEqual(lspRequestEvents.latestSequence, 0)
        XCTAssertTrue(lspRequestEvents.events.isEmpty)

        let finalSnapshot = try multi.snapshot()
        XCTAssertEqual(finalSnapshot.activeTabId, beta)
        XCTAssertEqual(finalSnapshot.tabs.count, 3)
        let finalBetaTab = try XCTUnwrap(finalSnapshot.tabs.first { $0.id == beta })
        XCTAssertEqual(finalBetaTab.title, "Beta")
        XCTAssertEqual(finalBetaTab.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(finalBetaTab.viewCount, 3)
        XCTAssertEqual(finalBetaTab.activeViewIndex, 0)
        XCTAssertFalse(finalBetaTab.isModified)
        XCTAssertTrue(finalSnapshot.tabs.contains { $0.id == preview && $0.isPreview == false })

        XCTAssertEqual(try multi.closeTabsToRight(of: beta), 1)
        XCTAssertEqual(try multi.closeOtherTabs(keeping: beta), 1)
        XCTAssertEqual(try multi.snapshot().tabs.map(\.id), [beta])

        XCTAssertTrue(try multi.closeTab(beta))
        XCTAssertNil(try multi.activeTabId())
    }
}
