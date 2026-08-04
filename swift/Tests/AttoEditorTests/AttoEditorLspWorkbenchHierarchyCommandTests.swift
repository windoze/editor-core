import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testHierarchyResultEntriesRetainExpansionRequestJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy-expand.swift")
        let entries = AttoLspHierarchyParser.incomingCalls(fromResultJSON: """
        [
          {
            "from": {
              "name": "render",
              "kind": 12,
              "detail": "View.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 3, "character": 9 },
                "end": { "line": 3, "character": 15 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 4, "character": 12 },
                "end": { "line": 4, "character": 18 }
              }
            ]
          }
        ]
        """)
        let entry = try XCTUnwrap(entries.first)
        let vc = makeEditorArea(workspaceRootURL: tempDir)

        XCTAssertEqual(entry.name, "render")
        XCTAssertEqual(entry.target.line, 4)
        XCTAssertEqual(entry.target.utf16Character, 12)
        let item = try XCTUnwrap(vc.hierarchyExpansionItem(from: entry))
        XCTAssertEqual(item.name, "render")
        XCTAssertEqual(item.target.line, 4)
        XCTAssertEqual(item.target.utf16Character, 12)
        XCTAssertTrue(item.requestJSON.contains(#""name":"render""#))
        XCTAssertTrue(item.requestJSON.contains(#""selectionRange""#))
    }

    func testHierarchyRefreshModeUpdatesWorkbenchWithoutOpeningQuickPanel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy-refresh.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()
        let target = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 2,
            utf16Character: 8
        )
        let rootItem = AttoLspHierarchyParser.Item(
            name: "caller",
            detail: "Root.swift",
            kindLabel: "function",
            target: target,
            requestJSON: #"{"name":"caller","uri":"file:///hierarchy-refresh.swift"}"#
        )
        let refreshRequest = AttoEditorAreaViewController.HierarchyPanelRefreshRequest(
            tabID: UUID(),
            kind: .callIncoming,
            item: rootItem
        )
        let entry = AttoLspHierarchyParser.Entry(
            name: "render",
            detail: "View.swift",
            kindLabel: "function",
            target: target,
            relatedRangeCount: 1
        )

        XCTAssertTrue(vc.finishHierarchyRefresh(
            [entry],
            kind: .callIncoming,
            refreshRequest: refreshRequest,
            showFeedback: false,
            editorView: nil
        ))

        let snapshot = try XCTUnwrap(vc._hierarchyPanelSnapshotForTesting())
        XCTAssertEqual(snapshot.title, "Incoming Calls")
        XCTAssertEqual(snapshot.entries.map(\.name), ["render"])
        XCTAssertEqual(vc._hierarchyPanelRefreshRequestForTesting(), refreshRequest)
        XCTAssertFalse(vc._hierarchyPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "hierarchy" }
        XCTAssertEqual(events.map(\.payload), [.hierarchy(title: "Incoming Calls", itemCount: 1)])

        let workbenchItem = try XCTUnwrap(vc.lspWorkbenchItems().first { $0.title == "Hierarchy" })
        XCTAssertTrue(workbenchItem.status.hasPrefix("1 result | Fresh | Result #"))
        XCTAssertTrue(workbenchItem.status.contains(" | hierarchy | Incoming Calls"))
        XCTAssertEqual(workbenchItem.historyCount, 1)
        XCTAssertEqual(workbenchItem.jumpTargetCount, 1)
    }

    func testHierarchyPanelUsesLastHierarchyResults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy.swift")
        try "func caller() { render() }\nfunc layout() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showHierarchyResultJSONForTesting("""
        [
          {
            "from": {
              "name": "render",
              "kind": 12,
              "detail": "View.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 0, "character": 16 },
                "end": { "line": 0, "character": 22 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 0, "character": 16 },
                "end": { "line": 0, "character": 22 }
              }
            ]
          },
          {
            "from": {
              "name": "layout",
              "kind": 6,
              "detail": "Layout.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 1, "character": 5 },
                "end": { "line": 1, "character": 11 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 1, "character": 5 },
                "end": { "line": 1, "character": 11 }
              }
            ]
          }
        ]
        """, kind: "callIncoming"))

        XCTAssertTrue(vc.showHierarchyPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.hierarchyPanel
        })
        XCTAssertEqual(panel.title, "Hierarchy (2)")

        let root = try XCTUnwrap(panel.contentView)
        let metadata = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelTable, in: root) as? NSTableView
        )
        XCTAssertTrue(metadata.stringValue.hasPrefix("2 results | Fresh | Result #"))
        XCTAssertTrue(metadata.stringValue.contains(" | hierarchy | Incoming Calls"))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._hierarchyPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._hierarchyPanelEntriesForTesting().map(\.name), ["render", "layout"])
        XCTAssertTrue(vc._hierarchyPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "hierarchy" }
        XCTAssertEqual(events.map(\.payload), [.hierarchy(title: "Incoming Calls", itemCount: 2)])

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Hierarchy"]?.hasPrefix("2 results | Fresh | Result #") == true)
        XCTAssertTrue(statuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Hierarchy"]?.hasPrefix("2 results | Stale: document edited | Result #") == true)
        XCTAssertTrue(staleStatuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)

        XCTAssertFalse(vc.requestLspHierarchyAtPrimaryCaret(kind: .callIncoming, showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(errorStatuses["Hierarchy"]?.hasPrefix("2 results | Error: Call hierarchy: unavailable | Result #") == true)
        XCTAssertTrue(errorStatuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)
    }}
