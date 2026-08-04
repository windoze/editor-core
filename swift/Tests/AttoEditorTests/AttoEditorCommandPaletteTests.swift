import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testCommandPaletteOrdersRecentCommandsFirst() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("recent.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.workspaceEditRequestRetryOwnersByTransactionSequence.removeAll()
            ctx.editorAreaController.workspaceEditHistoryPanelController?.hide()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_right"))
        XCTAssertTrue(delegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertEqual(Array(delegate._recentCommandIDsForTesting().prefix(2)), [
            "editor.duplicate_lines",
            "cursor.move_right",
        ])

        let ordered = delegate._defaultCommandsForTesting().prefix(2).map(\.id)
        XCTAssertEqual(ordered, ["editor.duplicate_lines", "cursor.move_right"])

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_right"))
        XCTAssertEqual(Array(delegate._recentCommandIDsForTesting().prefix(2)), [
            "cursor.move_right",
            "editor.duplicate_lines",
        ])
        XCTAssertEqual(
            delegate._defaultCommandsForTesting().prefix(2).map(\.id),
            ["cursor.move_right", "editor.duplicate_lines"]
        )

        let recentBeforeInvalidArguments = delegate._recentCommandIDsForTesting()
        XCTAssertFalse(delegate.executeCommand(id: "go.line", arguments: [:]))
        XCTAssertEqual(delegate._recentCommandIDsForTesting(), recentBeforeInvalidArguments)
    }

    func testCommandPalettePersistsRecentCommandsAcrossDelegates() throws {
        let suiteName = "AttoEditorCommandTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AttoRecentCommandStore(userDefaults: defaults)
        let firstDelegate = AttoAppDelegate(keyBindings: [:], recentCommandStore: store)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("recent-persist.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = firstDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(firstDelegate.executeCommand(id: "cursor.move_right"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertEqual(Array(firstDelegate._recentCommandIDsForTesting().prefix(2)), [
            "editor.duplicate_lines",
            "cursor.move_right",
        ])

        let secondDelegate = AttoAppDelegate(keyBindings: [:], recentCommandStore: store)
        XCTAssertEqual(Array(secondDelegate._recentCommandIDsForTesting().prefix(2)), [
            "editor.duplicate_lines",
            "cursor.move_right",
        ])
        XCTAssertEqual(
            secondDelegate._defaultCommandsForTesting().prefix(2).map(\.id),
            ["editor.duplicate_lines", "cursor.move_right"]
        )
    }

    func testCommandPalettePersistsRecentCommandArgumentsAcrossDelegates() throws {
        let suiteName = "AttoEditorCommandTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AttoRecentCommandStore(userDefaults: defaults)
        let firstDelegate = AttoAppDelegate(keyBindings: [:], recentCommandStore: store)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("recent-args.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = firstDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let arguments: AttoCommandArguments = ["line": .integer(2), "column": .integer(3)]
        XCTAssertTrue(firstDelegate.executeCommand(id: "go.line", arguments: arguments))
        XCTAssertEqual(firstDelegate._recentCommandIDsForTesting().first, "go.line")
        XCTAssertEqual(firstDelegate._recentCommandArgumentsForTesting(commandID: "go.line"), arguments)

        let secondDelegate = AttoAppDelegate(keyBindings: [:], recentCommandStore: store)
        XCTAssertEqual(secondDelegate._recentCommandIDsForTesting().first, "go.line")
        XCTAssertEqual(secondDelegate._recentCommandArgumentsForTesting(commandID: "go.line"), arguments)
    }

    func testCommandPaletteReplaysRecentCommandArguments() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("recent-replay.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.workspaceEditHistoryPanelController?.hide()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertTrue(delegate.executeCommand(
            id: "go.line",
            arguments: ["line": .integer(2), "column": .integer(3)]
        ))
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 6)

        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 0)

        let recentCommand = try XCTUnwrap(delegate._defaultCommandsForTesting().first)
        XCTAssertEqual(recentCommand.id, "go.line")
        recentCommand.run()
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 6)
    }
}
