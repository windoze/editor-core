@testable import AttoEditor
import EditorCoreUIFFI
import Foundation
import XCTest

final class AttoLspResultLifecycleStoreTests: XCTestCase {
    func testRecordKeepsCurrentAndBoundsHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 3)
        let firstDate = Date(timeIntervalSince1970: 100)

        let first = store.record(1, family: "numbers", title: "One", recordedAt: firstDate)
        store.record(2)
        store.record(3)
        let fourth = store.record(4, family: "numbers", title: "Four")

        XCTAssertEqual(store.current, 4)
        XCTAssertEqual(store.history, [2, 3, 4])
        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(first.family, "numbers")
        XCTAssertEqual(first.title, "One")
        XCTAssertEqual(first.recordedAt, firstDate)
        XCTAssertEqual(first.state, .fresh)
        XCTAssertEqual(fourth.sequence, 4)
        XCTAssertEqual(fourth.state, .fresh)
        XCTAssertEqual(store.latestSequence, 4)
        XCTAssertEqual(store.currentEntry?.sequence, 4)
        XCTAssertEqual(store.historyEntries.map(\.sequence), [2, 3, 4])
        XCTAssertEqual(store.entries(after: 2).map(\.snapshot), [3, 4])
        XCTAssertEqual(store.entries(after: 4).map(\.snapshot), [])
    }

    func testMakeCurrentDoesNotDuplicateHistory() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.record("first", family: "symbols", title: "First")
        store.record("second")
        store.makeCurrent(first)

        XCTAssertEqual(store.current, "first")
        XCTAssertEqual(store.history, ["first", "second"])
        XCTAssertEqual(store.currentEntry, first)
        XCTAssertEqual(store.historyEntries.map(\.title), ["First", ""])
    }

    func testMakeCurrentSnapshotCreatesEntryWithoutAddingHistory() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first")
        let current = store.makeCurrent("manual", family: "locations", title: "Manual")

        XCTAssertEqual(store.current, "manual")
        XCTAssertEqual(store.history, ["first"])
        XCTAssertEqual(current.sequence, 2)
        XCTAssertEqual(current.family, "locations")
        XCTAssertEqual(current.title, "Manual")
        XCTAssertEqual(current.state, .fresh)
    }

    func testRecordIfChangedSkipsDuplicateCurrentSnapshot() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.recordIfChanged("same", family: "diagnostics", title: "Initial")
        let duplicate = store.recordIfChanged("same", family: "diagnostics", title: "Duplicate")
        let changed = store.recordIfChanged("changed", family: "diagnostics", title: "Changed")

        XCTAssertNotNil(first)
        XCTAssertNil(duplicate)
        XCTAssertNotNil(changed)
        XCTAssertEqual(store.history, ["same", "changed"])
        XCTAssertEqual(store.historyEntries.map(\.title), ["Initial", "Changed"])
        XCTAssertEqual(store.current, "changed")
    }

    func testRecordIfChangedRecordsSameSnapshotWhenStateChanges() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.recordIfChanged("same", family: "symbols", title: "Initial")
        let stale = store.recordIfChanged(
            "same",
            family: "symbols",
            title: "Stale",
            state: .stale(reason: "document edited")
        )

        XCTAssertNotNil(first)
        XCTAssertNotNil(stale)
        XCTAssertEqual(store.history, ["same", "same"])
        XCTAssertEqual(store.historyEntries.map(\.state), [.fresh, .stale(reason: "document edited")])
        XCTAssertEqual(store.currentEntry?.title, "Stale")
    }

    func testUpdateCurrentStateKeepsSequenceAndUpdatesHistoryEntry() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.record("first", family: "locations", title: "First")
        store.record("second", family: "locations", title: "Second")
        store.makeCurrent(first)

        let updated = store.updateCurrentState(.stale(reason: "document edited"))

        XCTAssertEqual(updated?.sequence, first.sequence)
        XCTAssertEqual(updated?.family, first.family)
        XCTAssertEqual(updated?.title, first.title)
        XCTAssertEqual(updated?.recordedAt, first.recordedAt)
        XCTAssertEqual(updated?.snapshot, first.snapshot)
        XCTAssertEqual(updated?.state, .stale(reason: "document edited"))
        XCTAssertEqual(store.currentEntry?.state, .stale(reason: "document edited"))
        XCTAssertEqual(store.historyEntries.map(\.state), [.stale(reason: "document edited"), .fresh])

        let duplicate = store.updateCurrentState(.stale(reason: "document edited"))
        XCTAssertEqual(duplicate, updated)
        XCTAssertEqual(store.historyEntries.map(\.sequence), [1, 2])
    }

    func testNewRecordAfterStaleStateIsFreshByDefault() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first")
        store.updateCurrentState(.stale(reason: "document edited"))
        let second = store.record("second")

        XCTAssertEqual(second.state, .fresh)
        XCTAssertEqual(store.currentEntry?.state, .fresh)
        XCTAssertEqual(store.historyEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
    }

    func testClearDropsCurrentAndHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 0)

        store.record(1)
        store.record(2)
        store.clear()

        XCTAssertNil(store.current)
        XCTAssertEqual(store.history, [])
        XCTAssertNil(store.currentEntry)
        XCTAssertEqual(store.historyEntries, [])

        let next = store.record(3)
        XCTAssertEqual(next.sequence, 1)
    }

    func testResultEventStreamBoundsAndFiltersBySequence() {
        let stream = AttoLspResultEventStream(maxHistoryEntries: 2)
        let firstDate = Date(timeIntervalSince1970: 200)

        let first = stream.record(
            family: "locations",
            title: "Definitions: 1 result",
            recordedAt: firstDate,
            sourceSequence: 10,
            payload: .locations(kind: "definition", itemCount: 1)
        )
        let second = stream.record(
            family: "symbols",
            title: "Workspace Symbols: 2 results",
            sourceSequence: 11,
            payload: .symbols(title: "Workspace Symbols", itemCount: 2)
        )
        let third = stream.record(
            family: "diagnostics.active",
            title: "main.swift",
            sourceSequence: 12,
            payload: .diagnostics(
                scope: .workspace,
                problemCount: 3,
                markerCount: 0,
                isStale: true,
                staleReason: .workspaceRefreshRequested
            )
        )

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(first.recordedAt, firstDate)
        XCTAssertEqual(first.sourceSequence, Optional<UInt64>(10))
        XCTAssertEqual(stream.latestSequence, 3)
        XCTAssertEqual(stream.events.map(\.sequence), [2, 3])
        XCTAssertEqual(stream.entries(after: 2), [third])
        XCTAssertEqual(stream.entries(after: 3), [])
        XCTAssertEqual(second.payload, .symbols(title: "Workspace Symbols", itemCount: 2))
        XCTAssertEqual(
            third.payload,
            .diagnostics(
                scope: .workspace,
                problemCount: 3,
                markerCount: 0,
                isStale: true,
                staleReason: .workspaceRefreshRequested
            )
        )
        XCTAssertEqual(stream.events.map(\.state), [.fresh, .fresh])

        let staleState = AttoLspResultLifecycleState.stale(reason: "document edited")
        let updated = stream.updateLatestStates(
            families: ["symbols", "diagnostics.active", "missing"],
            state: staleState
        )
        XCTAssertEqual(updated.map(\.family), ["symbols", "diagnostics.active"])
        XCTAssertEqual(updated.map(\.state), [staleState, staleState])
        XCTAssertEqual(stream.events.map(\.state), [staleState, staleState])
        XCTAssertEqual(stream.entries(after: 2).map(\.state), [staleState])

        let cleared = stream.clearLatestStaleStates(families: ["symbols", "missing"])
        XCTAssertEqual(cleared.map(\.family), ["symbols"])
        XCTAssertEqual(cleared.map(\.state), [.fresh])
        XCTAssertEqual(stream.events.map(\.state), [.fresh, staleState])

        stream.clear()
        XCTAssertEqual(stream.events, [])
        XCTAssertEqual(stream.latestSequence, 0)
        XCTAssertEqual(
            stream.record(
                family: "locations",
                title: "References: 1 result",
                sourceSequence: 1,
                payload: .locations(kind: "references", itemCount: 1)
            ).sequence,
            1
        )
    }

    func testClearCurrentStaleStateRestoresFreshMetadataOnlyWhenStale() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first", family: "locations", title: "Definitions")
        XCTAssertNil(store.clearCurrentStaleState())

        store.updateCurrentState(.stale(reason: "document edited"))
        let cleared = store.clearCurrentStaleState()

        XCTAssertEqual(cleared?.state, .fresh)
        XCTAssertEqual(store.currentEntry?.state, .fresh)
        XCTAssertEqual(store.historyEntries.map(\.state), [.fresh])
    }

    func testClearStaleStateForHistoryEntryLeavesCurrentEntryUntouched() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)
        let stale = AttoLspResultLifecycleState.stale(reason: "document edited")
        let first = store.record("first", family: "locations", title: "Definitions", state: stale)
        let second = store.record("second", family: "symbols", title: "Document Symbols")

        store.pin(first, key: "locations")

        let cleared = store.clearStaleState(for: first)

        XCTAssertEqual(cleared?.state, .fresh)
        XCTAssertEqual(store.currentEntry, second)
        XCTAssertEqual(store.historyEntries.map(\.state), [.fresh, .fresh])
        XCTAssertEqual(store.pinnedEntriesByKey["locations"]?.state, .fresh)
    }

    func testPinCurrentResultRetainsEntryAfterHistoryBounds() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 2)
        let staleState = AttoLspResultLifecycleState.stale(reason: "document edited")

        store.record("first", family: "locations", title: "Definitions")
        let second = store.record("second", family: "locations", title: "References", state: staleState)

        XCTAssertEqual(store.pinCurrent(), second)
        XCTAssertEqual(store.pinnedEntry, second)
        XCTAssertEqual(store.pinnedEntriesByKey["locations"], second)

        let cleared = store.clearCurrentStaleState()
        XCTAssertEqual(cleared?.state, .fresh)
        XCTAssertEqual(store.pinnedEntry?.state, .fresh)
        XCTAssertEqual(store.pinnedEntriesByKey["locations"]?.state, .fresh)

        store.record("third")
        store.record("fourth")

        XCTAssertEqual(store.history, ["third", "fourth"])
        XCTAssertEqual(store.pinnedEntriesByKey["locations"]?.snapshot, "second")

        store.clear()
        XCTAssertNil(store.pinnedEntry)
        XCTAssertEqual(store.pinnedEntriesByKey, [:])
    }

    func testPinResultCanUseWorkbenchKeySeparateFromFamily() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let symbols = store.record("document symbols", family: "symbols", title: "Document Symbols")
        let outline = store.record("workspace outline", family: "symbols", title: "Workspace Outline")

        store.pin(symbols, key: "symbols")
        store.pin(outline, key: "workspace_outline")

        XCTAssertEqual(store.pinnedEntriesByKey["symbols"], symbols)
        XCTAssertEqual(store.pinnedEntriesByKey["workspace_outline"], outline)
        XCTAssertEqual(store.pinnedEntry, outline)

        XCTAssertEqual(store.unpin(key: "symbols"), symbols)
        XCTAssertNil(store.pinnedEntriesByKey["symbols"])
        XCTAssertEqual(store.pinnedEntriesByKey["workspace_outline"], outline)
        XCTAssertEqual(store.pinnedEntry, outline)

        XCTAssertEqual(store.unpin(key: "workspace_outline"), outline)
        XCTAssertEqual(store.pinnedEntriesByKey, [:])
        XCTAssertNil(store.pinnedEntry)
        XCTAssertNil(store.unpin(key: "workspace_outline"))
    }

    func testPinLatestResultEventRetainsEventAfterHistoryBounds() {
        let stream = AttoLspResultEventStream(maxHistoryEntries: 2)
        let staleState = AttoLspResultLifecycleState.stale(reason: "document edited")

        stream.record(
            family: "code_lens",
            title: "Code Lens: 1 action",
            payload: .codeLens(itemCount: 1)
        )
        let links = stream.record(
            family: "document_links",
            title: "Document Links: 2 links",
            state: staleState,
            payload: .documentLinks(itemCount: 2)
        )

        XCTAssertEqual(stream.pinLatest(family: "document_links"), links)
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"], links)
        XCTAssertNil(stream.pinLatest(family: "missing"))

        let cleared = stream.clearLatestStaleStates(families: ["document_links"])
        XCTAssertEqual(cleared.map(\.family), ["document_links"])
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"]?.state, .fresh)

        stream.record(
            family: "hierarchy",
            title: "Hierarchy: 1 result",
            payload: .hierarchy(title: "Hierarchy", itemCount: 1)
        )
        stream.record(
            family: "document_colors",
            title: "Document Colors: 1 color",
            payload: .documentColors(mode: "document_colors", itemCount: 1)
        )

        XCTAssertFalse(stream.events.contains { $0.sequence == links.sequence })
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"]?.sequence, links.sequence)

        XCTAssertEqual(stream.unpin(family: "document_links")?.sequence, links.sequence)
        XCTAssertNil(stream.pinnedEventsByFamily["document_links"])
        XCTAssertNil(stream.unpin(family: "document_links"))

        stream.clear()
        XCTAssertEqual(stream.pinnedEventsByFamily, [:])
    }

    func testProjectLspPanelErrorEventStoreBoundsAndFiltersBySequence() {
        let store = AttoProjectLspPanelErrorEventStore(maxHistoryEntries: 2)

        let first = store.record(
            source: .request,
            sourceSequence: 10,
            tabId: 1,
            viewIndex: 0,
            viewId: 100,
            family: "locations",
            title: "LSP References",
            slot: "references",
            method: "textDocument/references",
            requestId: 31,
            status: "error",
            message: "LSP References: server busy"
        )
        let second = store.record(
            source: .result,
            sourceSequence: 11,
            tabId: 2,
            viewIndex: 1,
            viewId: 200,
            family: "symbols",
            title: "LSP Workspace Symbols",
            slot: "workspace_symbols",
            method: "workspace/symbol",
            requestId: 32,
            status: "timeout",
            message: "LSP Workspace Symbols: timeout"
        )
        let third = store.record(
            source: .request,
            sourceSequence: 12,
            tabId: nil,
            viewIndex: nil,
            viewId: nil,
            family: "locations",
            title: "LSP Definition",
            slot: "definition",
            method: "textDocument/definition",
            requestId: 33,
            status: "error",
            message: "LSP Definition: failed"
        )

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(second.sequence, 2)
        XCTAssertEqual(third.sequence, 3)
        XCTAssertEqual(store.latestSequence, 3)
        XCTAssertEqual(store.events.map(\.sequence), [2, 3])
        XCTAssertEqual(store.entries(after: 2), [third])
        XCTAssertEqual(store.entries(after: 3), [])

        store.clear()
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(store.latestSequence, 0)
        XCTAssertEqual(
            store.record(
                source: .result,
                sourceSequence: 1,
                tabId: nil,
                viewIndex: nil,
                viewId: nil,
                family: "symbols",
                title: "LSP Document Symbols",
                slot: "document_symbols",
                method: "textDocument/documentSymbol",
                requestId: 1,
                status: "error",
                message: "LSP Document Symbols: failed"
            ).sequence,
            1
        )
    }

    func testProjectLspProcessHealthEventStoreBoundsAndFiltersBySequence() {
        let store = AttoProjectLspProcessHealthEventStore(maxHistoryEntries: 2)

        let first = store.record(
            sourceSequence: 10,
            tabId: 1,
            viewIndex: 0,
            viewId: 100,
            serverName: "rust-analyzer",
            serverCommand: "rust-analyzer",
            availability: "enabled",
            state: "ready",
            detail: nil,
            process: EcuLspProcessStatus(pid: 101, state: .running)
        )
        let second = store.record(
            sourceSequence: 11,
            tabId: 2,
            viewIndex: 1,
            viewId: 200,
            serverName: nil,
            serverCommand: "fake-lsp",
            availability: "failed",
            state: "failed",
            detail: "server exited",
            process: EcuLspProcessStatus(pid: 102, state: .exited, exitCode: 7)
        )
        let third = store.record(
            sourceSequence: 12,
            tabId: nil,
            viewIndex: nil,
            viewId: nil,
            serverName: "pylsp",
            serverCommand: "pylsp",
            availability: "enabled",
            state: "busy",
            detail: "stderr:\nindexing",
            process: EcuLspProcessStatus(pid: 103, state: .running, stderrTail: "indexing")
        )

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(second.sequence, 2)
        XCTAssertEqual(third.sequence, 3)
        XCTAssertEqual(store.latestSequence, 3)
        XCTAssertEqual(store.events.map(\.sequence), [2, 3])
        XCTAssertEqual(store.entries(after: 2), [third])
        XCTAssertEqual(store.entries(after: 3), [])
        XCTAssertEqual(store.events[0].process.exitCode, 7)
        XCTAssertEqual(store.events[1].process.stderrTail, "indexing")

        store.clear()
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(store.latestSequence, 0)
        XCTAssertEqual(
            store.record(
                sourceSequence: 1,
                tabId: nil,
                viewIndex: nil,
                viewId: nil,
                serverName: nil,
                serverCommand: "fake-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 200, state: .running)
            ).sequence,
            1
        )
    }

    func testProjectLspLifecycleEventStoreBoundsAndFiltersBySequence() throws {
        let store = AttoProjectLspLifecycleEventStore(maxHistoryEntries: 2)
        let decoder = JSONDecoder()

        let first = try decoder.decode(EcuProjectLspLifecycleEvent.self, from: Data("""
        {
          "sequence": 1,
          "operation": "start",
          "trigger": "auto_start",
          "status": "started",
          "tab_id": 10,
          "active_view_index": 0,
          "document_uri": "file:///tmp/a.rs",
          "language_id": "rust",
          "server_key": "rust-analyzer",
          "command": "rust-analyzer",
          "args": [],
          "workspace_roots": ["file:///tmp"]
        }
        """.utf8))
        let second = try decoder.decode(EcuProjectLspLifecycleEvent.self, from: Data("""
        {
          "sequence": 2,
          "operation": "start",
          "trigger": "auto_start",
          "status": "failed",
          "tab_id": 11,
          "active_view_index": 1,
          "document_uri": "file:///tmp/b.py",
          "language_id": "python",
          "server_key": "pylsp",
          "command": "pylsp",
          "args": ["--stdio"],
          "workspace_roots": ["file:///tmp"],
          "error_message": "server missing"
        }
        """.utf8))
        let third = try decoder.decode(EcuProjectLspLifecycleEvent.self, from: Data("""
        {
          "sequence": 3,
          "operation": "start",
          "trigger": "manual_restart",
          "status": "started",
          "tab_id": 12,
          "active_view_index": 0,
          "document_uri": "file:///tmp/c.swift",
          "language_id": "swift",
          "server_key": "sourcekit-lsp",
          "command": "sourcekit-lsp",
          "args": [],
          "workspace_roots": ["file:///tmp"]
        }
        """.utf8))

        store.record(first)
        store.record(contentsOf: [second, third])

        XCTAssertEqual(store.latestSequence, 3)
        XCTAssertEqual(store.events.map(\.sequence), [2, 3])
        XCTAssertEqual(store.entries(after: 2), [third])
        XCTAssertEqual(store.entries(after: 3), [])

        store.clear()
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(store.latestSequence, 0)
    }

    func testProjectLspProcessHealthLogStoreAppendsAndLoadsRecentWorkspaceEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("workspace-a", isDirectory: true)
        let rootB = tempDir.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL)
        let first = AttoProjectLspProcessHealthEvent(
            sequence: 1,
            sourceSequence: 10,
            tabId: 100,
            viewIndex: 0,
            viewId: 1000,
            serverName: "rust-analyzer",
            serverCommand: "rust-analyzer",
            availability: "enabled",
            state: "ready",
            detail: nil,
            process: EcuLspProcessStatus(pid: 101, state: .running)
        )
        let second = AttoProjectLspProcessHealthEvent(
            sequence: 2,
            sourceSequence: 11,
            tabId: 101,
            viewIndex: 1,
            viewId: 1001,
            serverName: "pylsp",
            serverCommand: "pylsp",
            availability: "failed",
            state: "failed",
            detail: "server exited",
            process: EcuLspProcessStatus(pid: 102, state: .exited, exitCode: 7, stderrTail: "stderr b")
        )
        let third = AttoProjectLspProcessHealthEvent(
            sequence: 3,
            sourceSequence: 12,
            tabId: 102,
            viewIndex: 0,
            viewId: 1002,
            serverName: "rust-analyzer",
            serverCommand: "rust-analyzer",
            availability: "failed",
            state: "failed",
            detail: "server exited",
            process: EcuLspProcessStatus(pid: 103, state: .exited, exitCode: 9, stderrTail: "stderr a")
        )

        let recordedAt = Date(timeIntervalSince1970: 1_785_715_200)
        try logStore.append(event: first, workspaceRootURL: rootA, recordedAt: recordedAt)
        try logStore.append(event: second, workspaceRootURL: rootB, recordedAt: recordedAt)
        try logStore.append(event: third, workspaceRootURL: rootA, recordedAt: recordedAt)

        let allA = logStore.loadRecent(workspaceRootURL: rootA, limit: 10)
        XCTAssertEqual(allA.map(\.sequence), [1, 3])
        XCTAssertEqual(allA[0].workspaceRootURI, rootA.standardizedFileURL.absoluteString)
        XCTAssertEqual(allA[1].process.exitCode, 9)
        XCTAssertEqual(allA[1].process.stderrTail, "stderr a")

        let latestA = logStore.loadRecent(workspaceRootURL: rootA, limit: 1)
        XCTAssertEqual(latestA.map(\.sequence), [3])

        let rawLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(rawLog.split(whereSeparator: \.isNewline).count, 3)
    }

    func testProjectLspProcessHealthLogStoreRetainsLatestEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogRetentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = tempDir.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL, maxPersistedEntries: 2)
        for sequence in UInt64(1)...UInt64(3) {
            try logStore.append(
                event: AttoProjectLspProcessHealthEvent(
                    sequence: sequence,
                    sourceSequence: sequence + 100,
                    tabId: sequence,
                    viewIndex: 0,
                    viewId: sequence + 1_000,
                    serverName: "fake-lsp-\(sequence)",
                    serverCommand: "fake-lsp",
                    availability: "enabled",
                    state: "ready",
                    detail: nil,
                    process: EcuLspProcessStatus(pid: UInt32(sequence), state: .running)
                ),
                workspaceRootURL: root,
                recordedAt: Date(timeIntervalSince1970: TimeInterval(1_785_715_200 + sequence))
            )
        }

        let entries = logStore.loadRecent(workspaceRootURL: root, limit: 10)
        XCTAssertEqual(entries.map(\.sequence), [2, 3])
        XCTAssertEqual(entries.map(\.serverName), ["fake-lsp-2", "fake-lsp-3"])

        let rawLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(rawLog.split(whereSeparator: \.isNewline).count, 2)
        XCTAssertFalse(rawLog.contains("fake-lsp-1"))
    }

    func testProjectLspProcessHealthLogStoreRetainsLatestEntriesPerWorkspace() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogPerWorkspaceRetentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("workspace-a", isDirectory: true)
        let rootB = tempDir.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL, maxPersistedEntries: 2)
        for (sequence, root) in [
            (UInt64(1), rootA),
            (UInt64(2), rootA),
            (UInt64(3), rootB),
            (UInt64(4), rootA),
            (UInt64(5), rootB),
            (UInt64(6), rootB)
        ] {
            try logStore.append(
                event: AttoProjectLspProcessHealthEvent(
                    sequence: sequence,
                    sourceSequence: sequence + 100,
                    tabId: sequence,
                    viewIndex: 0,
                    viewId: sequence + 1_000,
                    serverName: "fake-lsp-\(sequence)",
                    serverCommand: "fake-lsp",
                    availability: "enabled",
                    state: "ready",
                    detail: nil,
                    process: EcuLspProcessStatus(pid: UInt32(sequence), state: .running)
                ),
                workspaceRootURL: root,
                recordedAt: Date(timeIntervalSince1970: TimeInterval(1_785_715_200 + sequence))
            )
        }

        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: rootA, limit: 10).map(\.sequence), [2, 4])
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: rootB, limit: 10).map(\.sequence), [5, 6])

        let rawLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(rawLog.split(whereSeparator: \.isNewline).count, 4)
        XCTAssertFalse(rawLog.contains("fake-lsp-1"))
        XCTAssertFalse(rawLog.contains("fake-lsp-3"))
    }

    func testProjectLspProcessHealthLogStorePrunesEntriesOlderThanMaxAge() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogAgeRotationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = tempDir.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: logURL,
            maxPersistedEntries: 10,
            maxLogFileBytes: 100_000,
            maxEntryAge: 60
        )
        for (sequence, recordedAt) in [
            (UInt64(1), TimeInterval(1_000)),
            (UInt64(2), TimeInterval(1_060)),
            (UInt64(3), TimeInterval(1_110))
        ] {
            try logStore.append(
                event: AttoProjectLspProcessHealthEvent(
                    sequence: sequence,
                    sourceSequence: sequence + 100,
                    tabId: sequence,
                    viewIndex: 0,
                    viewId: sequence + 1_000,
                    serverName: "fake-lsp-\(sequence)",
                    serverCommand: "fake-lsp",
                    availability: "enabled",
                    state: "ready",
                    detail: nil,
                    process: EcuLspProcessStatus(pid: UInt32(sequence), state: .running)
                ),
                workspaceRootURL: root,
                recordedAt: Date(timeIntervalSince1970: recordedAt)
            )
        }

        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: root, limit: 10).map(\.sequence), [2, 3])
        let rawLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(rawLog.contains("fake-lsp-1"))
        XCTAssertTrue(rawLog.contains("fake-lsp-2"))
        XCTAssertTrue(rawLog.contains("fake-lsp-3"))
    }

    func testProjectLspProcessHealthLogStorePrunesOldestLinesBySizeBudget() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogSizeRotationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = tempDir.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: logURL,
            maxPersistedEntries: 100,
            maxLogFileBytes: 2_000,
            maxEntryAge: nil
        )
        for sequence in UInt64(1)...UInt64(6) {
            try logStore.append(
                event: AttoProjectLspProcessHealthEvent(
                    sequence: sequence,
                    sourceSequence: sequence + 100,
                    tabId: sequence,
                    viewIndex: 0,
                    viewId: sequence + 1_000,
                    serverName: "fake-lsp-\(sequence)",
                    serverCommand: "fake-lsp",
                    availability: "failed",
                    state: "failed",
                    detail: String(repeating: "x", count: 1_000),
                    process: EcuLspProcessStatus(pid: UInt32(sequence), state: .exited, exitCode: Int32(sequence))
                ),
                workspaceRootURL: root,
                recordedAt: Date(timeIntervalSince1970: TimeInterval(1_785_715_200 + sequence))
            )
        }

        let rawData = try Data(contentsOf: logURL)
        XCTAssertLessThanOrEqual(rawData.count, 2_000)
        let entries = logStore.loadRecent(workspaceRootURL: root, limit: 10)
        XCTAssertTrue(entries.contains { $0.sequence == 6 })
        XCTAssertLessThan(entries.count, 6)

        let rawLog = String(decoding: rawData, as: UTF8.self)
        XCTAssertFalse(rawLog.contains("fake-lsp-1"))
        XCTAssertTrue(rawLog.contains("fake-lsp-6"))
    }

    func testProjectLspProcessHealthLogStoreQueriesWorkspaceEntriesWithFieldFilters() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogQueryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("workspace-a", isDirectory: true)
        let rootB = tempDir.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL)
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 101,
                tabId: 10,
                viewIndex: 0,
                viewId: 1001,
                serverName: "rust-analyzer",
                serverCommand: "rust-analyzer",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 11, state: .running)
            ),
            workspaceRootURL: rootA,
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 102,
                tabId: 20,
                viewIndex: 1,
                viewId: 1002,
                serverName: "pylsp",
                serverCommand: "pylsp",
                availability: "failed",
                state: "failed",
                detail: "server exited",
                process: EcuLspProcessStatus(pid: 22, state: .exited, exitCode: 7, stderrTail: "boom stack")
            ),
            workspaceRootURL: rootA,
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 3,
                sourceSequence: 103,
                tabId: 30,
                viewIndex: 0,
                viewId: 1003,
                serverName: "rust-analyzer",
                serverCommand: "rust-analyzer",
                availability: "failed",
                state: "failed",
                detail: "late exit",
                process: EcuLspProcessStatus(pid: 33, state: .exited, exitCode: 9, stderrTail: "late stderr")
            ),
            workspaceRootURL: rootA,
            recordedAt: Date(timeIntervalSince1970: 3_000)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 4,
                sourceSequence: 104,
                tabId: 40,
                viewIndex: 0,
                viewId: 1004,
                serverName: "pylsp",
                serverCommand: "pylsp",
                availability: "failed",
                state: "failed",
                detail: "other workspace",
                process: EcuLspProcessStatus(pid: 44, state: .exited, exitCode: 7, stderrTail: "boom other")
            ),
            workspaceRootURL: rootB,
            recordedAt: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(
            logStore.queryRecent(workspaceRootURL: rootA, query: "server:rust state:failed process:exited exit:9", limit: 10).map(\.sequence),
            [3]
        )
        XCTAssertEqual(
            logStore.queryRecent(workspaceRootURL: rootA, query: "pylsp boom", limit: 10).map(\.sequence),
            [2]
        )
        XCTAssertEqual(
            logStore.queryRecent(workspaceRootURL: rootA, query: "stderr:late since:2500", limit: 10).map(\.sequence),
            [3]
        )
        XCTAssertEqual(
            logStore.queryRecent(workspaceRootURL: rootA, query: "until:2500", limit: 10).map(\.sequence),
            [1, 2]
        )
        XCTAssertEqual(
            logStore.queryRecent(workspaceRootURL: rootA, query: "server:rust", limit: 1).map(\.sequence),
            [3]
        )
    }

    func testProjectLspProcessHealthLogStoreExportsWorkspaceEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("workspace-a", isDirectory: true)
        let rootB = tempDir.appendingPathComponent("workspace-b", isDirectory: true)
        let rootC = tempDir.appendingPathComponent("workspace-c", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootC, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL)
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 101,
                tabId: 1,
                viewIndex: 0,
                viewId: 1001,
                serverName: "root-a-lsp",
                serverCommand: "root-a-lsp",
                availability: "failed",
                state: "failed",
                detail: "root a",
                process: EcuLspProcessStatus(pid: 11, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: rootA,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 102,
                tabId: 2,
                viewIndex: 0,
                viewId: 1002,
                serverName: "root-b-lsp",
                serverCommand: "root-b-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 12, state: .running)
            ),
            workspaceRootURL: rootB,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let exportedText = try logStore.exportJSONL(workspaceRootURL: rootA)
        XCTAssertTrue(exportedText.contains("root-a-lsp"))
        XCTAssertFalse(exportedText.contains("root-b-lsp"))
        XCTAssertEqual(exportedText.split(whereSeparator: \.isNewline).count, 1)

        let exportURL = tempDir.appendingPathComponent("exports/root-a-health.jsonl")
        XCTAssertEqual(try logStore.exportJSONL(workspaceRootURL: rootA, to: exportURL), 1)
        let writtenText = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertEqual(writtenText, exportedText)

        let emptyExportURL = tempDir.appendingPathComponent("exports/root-c-health.jsonl")
        XCTAssertEqual(try logStore.exportJSONL(workspaceRootURL: rootC, to: emptyExportURL), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyExportURL.path))
    }

    func testProjectLspProcessHealthLogStoreClearsWorkspaceEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoProjectLspProcessHealthLogClearTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("workspace-a", isDirectory: true)
        let rootB = tempDir.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let logURL = tempDir.appendingPathComponent("lsp-process-health.jsonl")
        let logStore = AttoProjectLspProcessHealthLogStore(logFileURL: logURL)
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 101,
                tabId: 1,
                viewIndex: 0,
                viewId: 1001,
                serverName: "root-a-lsp",
                serverCommand: "root-a-lsp",
                availability: "failed",
                state: "failed",
                detail: "root a",
                process: EcuLspProcessStatus(pid: 11, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: rootA,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 102,
                tabId: 2,
                viewIndex: 0,
                viewId: 1002,
                serverName: "root-b-lsp",
                serverCommand: "root-b-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 12, state: .running)
            ),
            workspaceRootURL: rootB,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        XCTAssertEqual(try logStore.clear(workspaceRootURL: rootA), 1)
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: rootA, limit: 10), [])
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: rootB, limit: 10).map(\.serverName), ["root-b-lsp"])
        XCTAssertEqual(try logStore.clear(workspaceRootURL: rootA), 0)

        let rawLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(rawLog.contains("root-a-lsp"))
        XCTAssertTrue(rawLog.contains("root-b-lsp"))
    }
}
