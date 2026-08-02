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
