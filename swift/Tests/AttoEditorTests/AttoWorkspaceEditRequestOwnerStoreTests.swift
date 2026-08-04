@testable import AttoEditor
import Foundation
import XCTest

final class AttoWorkspaceEditRequestOwnerStoreTests: XCTestCase {
    func testLoadRecentCanonicalizesWorkspaceRootURI() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = tempDir.appendingPathComponent("Root With Space", isDirectory: true).standardizedFileURL
        let otherRoot = tempDir.appendingPathComponent("Other Root", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)

        let store = makeStore(in: tempDir)
        let rootURIWithoutTrailingSlash = root.absoluteString.hasSuffix("/")
            ? String(root.absoluteString.dropLast())
            : root.absoluteString

        try appendRecord(
            to: store,
            rootURI: rootURIWithoutTrailingSlash,
            sequence: 1,
            workspaceEditJSON: #"{"changes":{"a":[]}}"#,
            label: "Root URI"
        )
        try appendRecord(
            to: store,
            rootURI: root.path,
            sequence: 2,
            workspaceEditJSON: #"{"changes":{"b":[]}}"#,
            label: "Root Path"
        )
        try appendRecord(
            to: store,
            rootURI: otherRoot.absoluteString,
            sequence: 3,
            workspaceEditJSON: #"{"changes":{"c":[]}}"#,
            label: "Other Root"
        )

        let records = store.loadRecent(workspaceRootURL: root, limit: 10)
        XCTAssertEqual(records.map(\.transactionSequence), [1, 2])
        XCTAssertEqual(records.map(\.descriptor.label), ["Root URI", "Root Path"])
    }

    func testLoadReconciledKeepsCurrentHistoryMatchesAndLatestOwner() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalRoot = tempDir.appendingPathComponent("Original", isDirectory: true).standardizedFileURL
        let migratedRoot = tempDir.appendingPathComponent("Migrated", isDirectory: true).standardizedFileURL
        let otherRoot = tempDir.appendingPathComponent("Other", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: originalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: migratedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)

        let store = makeStore(in: tempDir)
        let originalRootURIWithoutTrailingSlash = originalRoot.absoluteString.hasSuffix("/")
            ? String(originalRoot.absoluteString.dropLast())
            : originalRoot.absoluteString

        try appendRecord(
            to: store,
            rootURI: originalRoot.absoluteString,
            sequence: 1,
            workspaceEditJSON: #"{"changes":{"retained":[]}}"#,
            label: "Pruned History"
        )
        try appendRecord(
            to: store,
            rootURI: originalRoot.absoluteString,
            sequence: 2,
            workspaceEditJSON: #"{"changes":{"wrong":[]}}"#,
            label: "Wrong Workspace Edit"
        )
        try appendRecord(
            to: store,
            rootURI: originalRoot.absoluteString,
            sequence: 3,
            workspaceEditJSON: #"{"changes":{"current":[]}}"#,
            label: "Older Owner"
        )
        try appendRecord(
            to: store,
            rootURI: originalRoot.absoluteString,
            sequence: 3,
            workspaceEditJSON: #"{"changes":{"current":[]}}"#,
            label: "Current Owner"
        )
        try appendRecord(
            to: store,
            rootURI: originalRootURIWithoutTrailingSlash,
            sequence: 4,
            workspaceEditJSON: #"{"changes":{"slash":[]}}"#,
            label: "No Slash Root"
        )
        try appendRecord(
            to: store,
            rootURI: otherRoot.absoluteString,
            sequence: 5,
            workspaceEditJSON: #"{"changes":{"other":[]}}"#,
            label: "Other Root"
        )
        try appendRecord(
            to: store,
            rootURI: originalRoot.absoluteString,
            sequence: 6,
            workspaceEditJSON: nil,
            label: "Legacy Owner"
        )

        let events = [
            AttoWorkspaceEditRequestOwnerStore.ReconciliationEvent(
                transactionSequence: 2,
                workspaceEditJSON: #"{"changes":{"expected":[]}}"#
            ),
            AttoWorkspaceEditRequestOwnerStore.ReconciliationEvent(
                transactionSequence: 3,
                workspaceEditJSON: #"{"changes":{"current":[]}}"#
            ),
            AttoWorkspaceEditRequestOwnerStore.ReconciliationEvent(
                transactionSequence: 4,
                workspaceEditJSON: #"{"changes":{"slash":[]}}"#
            ),
            AttoWorkspaceEditRequestOwnerStore.ReconciliationEvent(
                transactionSequence: 5,
                workspaceEditJSON: #"{"changes":{"other":[]}}"#
            ),
            AttoWorkspaceEditRequestOwnerStore.ReconciliationEvent(
                transactionSequence: 6,
                workspaceEditJSON: #"{"changes":{"legacy":[]}}"#
            ),
        ]

        let reconciled = store.loadReconciled(
            workspaceRootURL: migratedRoot,
            workspaceRootURIs: [originalRoot.absoluteString],
            events: events,
            limit: 10
        )

        XCTAssertEqual(reconciled.map(\.transactionSequence), [3, 4, 6])
        XCTAssertEqual(reconciled.map(\.descriptor.label), ["Current Owner", "No Slash Root", "Legacy Owner"])

        let limited = store.loadReconciled(
            workspaceRootURL: migratedRoot,
            workspaceRootURIs: [originalRoot.absoluteString],
            events: events,
            limit: 2
        )
        XCTAssertEqual(limited.map(\.transactionSequence), [4, 6])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRequestOwnerStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore(in directory: URL) -> AttoWorkspaceEditRequestOwnerStore {
        AttoWorkspaceEditRequestOwnerStore(
            logFileURL: directory.appendingPathComponent("workspace-edit-request-owners.jsonl"),
            maxPersistedEntries: 20
        )
    }

    private func appendRecord(
        to store: AttoWorkspaceEditRequestOwnerStore,
        rootURI: String,
        sequence: UInt64,
        workspaceEditJSON: String?,
        label: String
    ) throws {
        try store.append(record: AttoWorkspaceEditRequestOwnerRecord(
            recordedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
            workspaceRootURI: rootURI,
            transactionSequence: sequence,
            workspaceEditJSON: workspaceEditJSON,
            descriptor: .unknown(label: label)
        ))
    }
}
