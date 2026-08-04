import AppKit
@testable import AttoEditor
import EditorCoreUI
import XCTest

@MainActor
final class AttoEditorCommandMacroTests: XCTestCase {
    func testCommandMacroRecordsAndReplaysCommandSequence() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let delegate = makeDelegate(sessionRootURL: tempDir)
        let fileURL = tempDir.appendingPathComponent("macro.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.workspaceEditHistoryPanelController?.hide()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.replay_last"))

        XCTAssertTrue(delegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(delegate._isRecordingMacroForTesting())
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.replay_last"))

        XCTAssertTrue(delegate.executeCommand(id: "go.line", arguments: ["line": .integer(2), "column": .integer(2)]))
        XCTAssertTrue(delegate.executeCommand(id: "editor.find"))
        XCTAssertTrue(delegate.executeCommand(id: "editor.duplicate_lines"))

        XCTAssertTrue(delegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertFalse(delegate._isRecordingMacroForTesting())

        let recorded = delegate._lastMacroCommandsForTesting()
        XCTAssertEqual(recorded.map(\.commandID), ["go.line", "editor.duplicate_lines"])
        XCTAssertEqual(recorded.first?.arguments, ["line": .integer(2), "column": .integer(2)])
        XCTAssertEqual(recorded.last?.arguments, [:])
        XCTAssertEqual(try editorView.editor.text(), "abc\ndef\ndef\n")
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.replay_last"))

        XCTAssertTrue(delegate.executeCommand(id: "macro.replay_last"))
        XCTAssertEqual(try editorView.editor.text(), "abc\ndef\ndef\ndef\n")
        XCTAssertEqual(delegate._lastMacroCommandsForTesting(), recorded)
    }

    func testCommandMacroPersistsSublimeMacroFileAcrossDelegates() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroURL = tempDir.appendingPathComponent("Last Macro.sublime-macro")
        let macroStore = AttoMacroStore(macroFileURL: macroURL)
        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)

        let firstFileURL = tempDir.appendingPathComponent("macro-record.txt")
        try "abc\ndef\n".write(to: firstFileURL, atomically: true, encoding: .utf8)

        let firstContext = firstDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { firstContext.window.close() }
        firstContext.editorAreaController.openFile(url: firstFileURL, mode: .pinned)

        XCTAssertTrue(firstDelegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "go.line", arguments: ["line": .integer(2), "column": .integer(2)]))
        XCTAssertTrue(firstDelegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "macro.toggle_recording"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: macroURL.path))
        let rawJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: macroURL)) as? [[String: Any]]
        let stored = try XCTUnwrap(rawJSON)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored[0]["command"] as? String, "go.line")
        let goLineArgs = try XCTUnwrap(stored[0]["args"] as? [String: Any])
        XCTAssertEqual((goLineArgs["line"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((goLineArgs["column"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(stored[1]["command"] as? String, "editor.duplicate_lines")
        XCTAssertNil(stored[1]["args"])

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let loaded = secondDelegate._lastMacroCommandsForTesting()
        XCTAssertEqual(loaded.map(\.commandID), ["go.line", "editor.duplicate_lines"])
        XCTAssertEqual(loaded.first?.arguments, ["line": .integer(2), "column": .integer(2)])

        let replayFileURL = tempDir.appendingPathComponent("macro-replay.txt")
        try "abc\ndef\n".write(to: replayFileURL, atomically: true, encoding: .utf8)
        let secondContext = secondDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { secondContext.window.close() }
        secondContext.editorAreaController.openFile(url: replayFileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: secondContext.editorAreaController.view))
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.replay_last"))
        XCTAssertTrue(secondDelegate.executeCommand(id: "macro.replay_last"))
        XCTAssertEqual(try editorView.editor.text(), "abc\ndef\ndef\n")
    }

    func testCommandMacroSavesAndReplaysNamedSublimeMacroFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroURL = tempDir.appendingPathComponent("Last Macro.sublime-macro")
        let macroStore = AttoMacroStore(macroFileURL: macroURL)
        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)

        let firstFileURL = tempDir.appendingPathComponent("macro-named-record.txt")
        try "abc\ndef\n".write(to: firstFileURL, atomically: true, encoding: .utf8)

        let firstContext = firstDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { firstContext.window.close() }
        firstContext.editorAreaController.openFile(url: firstFileURL, mode: .pinned)

        XCTAssertFalse(firstDelegate._commandIsEnabledForTesting(commandID: "macro.save_named"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "go.line", arguments: ["line": .integer(2), "column": .integer(2)]))
        XCTAssertTrue(firstDelegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertTrue(firstDelegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.save_named"))

        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.save_named",
            arguments: ["name": .string("Duplicate Current Line")]
        ))
        let namedMacroURL = tempDir.appendingPathComponent("Duplicate Current Line.sublime-macro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: namedMacroURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Duplicate Current Line"])

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.replay_named"))
        let replayNamedSchema = try XCTUnwrap(secondDelegate._commandSchemaForTesting(commandID: "macro.replay_named"))
        XCTAssertEqual(replayNamedSchema.parameters.first?.choices.map(\.title), ["Duplicate Current Line"])
        XCTAssertThrowsError(try replayNamedSchema.normalizedArguments(["name": .string("Missing Macro")]))

        let replayFileURL = tempDir.appendingPathComponent("macro-named-replay.txt")
        try "abc\ndef\n".write(to: replayFileURL, atomically: true, encoding: .utf8)
        let secondContext = secondDelegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { secondContext.window.close() }
        secondContext.editorAreaController.openFile(url: replayFileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: secondContext.editorAreaController.view))
        XCTAssertTrue(secondDelegate.executeCommand(
            id: "macro.replay_named",
            arguments: ["name": .string("Duplicate Current Line")]
        ))
        XCTAssertEqual(try editorView.editor.text(), "abc\ndef\ndef\n")
    }

    func testCommandMacroRenamesAndDeletesNamedSublimeMacroFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroURL = tempDir.appendingPathComponent("Last Macro.sublime-macro")
        let macroStore = AttoMacroStore(macroFileURL: macroURL)
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)

        let recordFileURL = tempDir.appendingPathComponent("macro-rename-record.txt")
        try "abc\ndef\n".write(to: recordFileURL, atomically: true, encoding: .utf8)

        let context = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { context.window.close() }
        context.editorAreaController.openFile(url: recordFileURL, mode: .pinned)

        XCTAssertTrue(delegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(delegate.executeCommand(id: "go.line", arguments: ["line": .integer(2), "column": .integer(2)]))
        XCTAssertTrue(delegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.toggle_recording"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.save_named", arguments: ["name": .string("Old Macro")]))

        let oldURL = tempDir.appendingPathComponent("Old Macro.sublime-macro")
        let newURL = tempDir.appendingPathComponent("Renamed Macro.sublime-macro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Old Macro"])

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.rename_named"))
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.rename_named",
            arguments: ["oldName": .string("Old Macro"), "newName": .string("Renamed Macro")]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Renamed Macro"])

        let renameSchema = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.rename_named"))
        XCTAssertEqual(renameSchema.parameters.first?.choices.map(\.title), ["Renamed Macro"])
        XCTAssertThrowsError(try renameSchema.normalizedArguments([
            "oldName": .string("Old Macro"),
            "newName": .string("Another Macro"),
        ]))

        let replayFileURL = tempDir.appendingPathComponent("macro-rename-replay.txt")
        try "abc\ndef\n".write(to: replayFileURL, atomically: true, encoding: .utf8)
        context.editorAreaController.openFile(url: replayFileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: context.editorAreaController.view))
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.replay_named",
            arguments: ["name": .string("Renamed Macro")]
        ))
        XCTAssertEqual(try editorView.editor.text(), "abc\ndef\ndef\n")

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.delete_named"))
        delegate._setMacroDeleteConfirmationProviderForTesting { name in
            XCTAssertEqual(name, "Renamed Macro")
            return false
        }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Renamed Macro")]
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Renamed Macro"])

        delegate._setMacroDeleteConfirmationProviderForTesting { name in
            XCTAssertEqual(name, "Renamed Macro")
            return true
        }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Renamed Macro")]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.replay_named"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.rename_named"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.delete_named"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Renamed Macro"])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
    }

    func testCommandMacroBatchDeletesNamedSublimeMacroFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroURL = tempDir.appendingPathComponent("Last Macro.sublime-macro")
        let macroStore = AttoMacroStore(macroFileURL: macroURL)
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "One", maxCount: 20)
        try macroStore.save(commands, named: "Two", maxCount: 20)
        try macroStore.save(commands, named: "Three", maxCount: 20)

        let oneURL = tempDir.appendingPathComponent("One.sublime-macro")
        let twoURL = tempDir.appendingPathComponent("Two.sublime-macro")
        let threeURL = tempDir.appendingPathComponent("Three.sublime-macro")
        XCTAssertEqual(macroStore.namedMacroNames(), ["One", "Three", "Two"])
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.delete_named_batch"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        delegate._setMacroDeleteBatchConfirmationProviderForTesting { names in
            XCTAssertEqual(names, ["One", "Two"])
            return false
        }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"One\", \"Two\", \"One.sublime-macro\"]")]
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oneURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: twoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threeURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["One", "Three", "Two"])

        delegate._setMacroDeleteBatchConfirmationProviderForTesting { names in
            XCTAssertEqual(names, ["One", "Two"])
            return true
        }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"One\", \"Two\"]")]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oneURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: twoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threeURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Three"])
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oneURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: twoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: threeURL.path))
        XCTAssertEqual(macroStore.namedMacroNames(), ["One", "Three", "Two"])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Missing\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), ["One", "Three", "Two"])
    }

    func testCommandMacroUndoDeleteUsesMultiLevelHistory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)

        delegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }

        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta", "Gamma"])

        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Beta\", \"Gamma\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta", "Gamma"])

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Alpha", "Beta", "Gamma"])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
    }

    func testCommandMacroUndoDeleteHistoryPersistsAcrossDelegates() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)

        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        firstDelegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Beta\", \"Gamma\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), [])

        XCTAssertTrue(secondDelegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta", "Gamma"])
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let thirdDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(thirdDelegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Alpha", "Beta", "Gamma"])
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let fourthDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertFalse(fourthDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
    }

    func testCommandMacroDeleteHistoryPanelRestoresSelectedEntry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let context = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { context.window.close() }

        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)

        delegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Beta\", \"Gamma\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.show_delete_history"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.show_delete_history"))

        let historyPanel = try XCTUnwrap(context.window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.Macro.DeleteHistory")
        })
        let root = try XCTUnwrap(historyPanel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.Macro.DeleteHistory"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter deleted macros...")

        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.Macro.DeleteHistory"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)
        let firstCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(firstCell.textField?.stringValue, "1. Beta, Gamma (2 macros)")
        let secondCell = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(secondCell.textField?.stringValue, "2. Alpha")

        XCTAssertTrue(delegate._restoreDeletedMacroHistoryEntryForTesting(displayIndex: 1))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Alpha"])
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.show_delete_history"))

        XCTAssertTrue(delegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Alpha", "Beta", "Gamma"])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.show_delete_history"))
    }

    func testCommandMacroDeleteHistoryPanelSupportsVisualBatchRemovalAndRestore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let context = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { context.window.close() }

        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)
        try macroStore.save(commands, named: "Delta", maxCount: 20)

        delegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Beta")]
        ))
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Gamma\", \"Delta\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.manage_delete_history"))
        XCTAssertTrue(delegate.executeCommand(id: "macro.manage_delete_history"))

        let historyPanel = try XCTUnwrap(context.window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.deletedMacroHistoryPanel
        })
        let root = try XCTUnwrap(historyPanel.contentView)
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.deletedMacroHistoryPanelTable, in: root) as? NSTableView
        )
        let restoreButton = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.deletedMacroHistoryPanelRestoreButton, in: root) as? NSButton
        )
        let removeButton = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.deletedMacroHistoryPanelRemoveButton, in: root) as? NSButton
        )
        let clearButton = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.deletedMacroHistoryPanelClearButton, in: root) as? NSButton
        )

        func title(at row: Int) throws -> String {
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
            return try XCTUnwrap(cell.textField?.stringValue)
        }

        XCTAssertTrue(table.allowsMultipleSelection)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(try title(at: 0), "1. Gamma, Delta (2 macros)")
        XCTAssertEqual(try title(at: 1), "2. Beta")
        XCTAssertEqual(try title(at: 2), "3. Alpha")
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(removeButton.isEnabled)
        XCTAssertTrue(clearButton.isEnabled)

        table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        table.delegate?.tableViewSelectionDidChange?(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )
        XCTAssertFalse(restoreButton.isEnabled)
        XCTAssertTrue(removeButton.isEnabled)

        var removalAttempts: [[(displayIndex: Int, title: String)]] = []
        delegate._setMacroDeleteHistoryEntriesRemovalConfirmationProviderForTesting { items in
            removalAttempts.append(items)
            return true
        }
        removeButton.performClick(nil)
        XCTAssertEqual(removalAttempts.count, 1)
        XCTAssertEqual(removalAttempts.first?.map(\.displayIndex), [1, 3])
        XCTAssertEqual(removalAttempts.first?.map(\.title), ["Gamma, Delta (2 macros)", "Alpha"])
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(try title(at: 0), "1. Beta")
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(removeButton.isEnabled)
        XCTAssertTrue(clearButton.isEnabled)

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.delegate?.tableViewSelectionDidChange?(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )
        restoreButton.performClick(nil)
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta"])
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "macro.manage_delete_history"))
        XCTAssertFalse(historyPanel.isVisible)
    }

    func testCommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)

        delegate._setMacroDeleteConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(delegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.show_delete_history"))

        XCTAssertTrue(delegate.executeCommand(id: "macro.show_delete_history"))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
    }

    func testCommandMacroClearDeleteHistoryClearsPersistentUndoStack() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)

        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        firstDelegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Beta\", \"Gamma\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.clear_delete_history"))

        var clearAttempts: [(records: Int, macros: Int)] = []
        firstDelegate._setMacroDeleteHistoryClearConfirmationProviderForTesting { records, macros in
            clearAttempts.append((records, macros))
            return false
        }
        XCTAssertTrue(firstDelegate.executeCommand(id: "macro.clear_delete_history"))
        XCTAssertEqual(clearAttempts.count, 1)
        XCTAssertEqual(clearAttempts.first?.records, 2)
        XCTAssertEqual(clearAttempts.first?.macros, 3)
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.clear_delete_history"))

        secondDelegate._setMacroDeleteHistoryClearConfirmationProviderForTesting { records, macros in
            XCTAssertEqual(records, 2)
            XCTAssertEqual(macros, 3)
            return true
        }
        XCTAssertTrue(secondDelegate.executeCommand(id: "macro.clear_delete_history"))
        XCTAssertFalse(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertFalse(secondDelegate._commandIsEnabledForTesting(commandID: "macro.show_delete_history"))
        XCTAssertFalse(secondDelegate._commandIsEnabledForTesting(commandID: "macro.clear_delete_history"))

        let thirdDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.clear_delete_history"))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
    }

    func testCommandMacroRemoveDeleteHistoryEntryRemovesPersistentSelectedRecord() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)

        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        firstDelegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Beta\", \"Gamma\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.remove_delete_history_entry"))

        let schema = try XCTUnwrap(firstDelegate._commandSchemaForTesting(commandID: "macro.remove_delete_history_entry"))
        XCTAssertEqual(schema.parameters.first?.choices.map(\.title), ["1. Beta, Gamma (2 macros)", "2. Alpha"])
        XCTAssertThrowsError(try schema.normalizedArguments(["index": .integer(3)]))

        var removalAttempts: [(index: Int, title: String)] = []
        firstDelegate._setMacroDeleteHistoryEntryRemovalConfirmationProviderForTesting { index, title in
            removalAttempts.append((index, title))
            return false
        }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.remove_delete_history_entry",
            arguments: ["index": .integer(2)]
        ))
        XCTAssertEqual(removalAttempts.count, 1)
        XCTAssertEqual(removalAttempts.first?.index, 2)
        XCTAssertEqual(removalAttempts.first?.title, "Alpha")
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        secondDelegate._setMacroDeleteHistoryEntryRemovalConfirmationProviderForTesting { index, title in
            XCTAssertEqual(index, 2)
            XCTAssertEqual(title, "Alpha")
            return true
        }
        XCTAssertTrue(secondDelegate.executeCommand(
            id: "macro.remove_delete_history_entry",
            arguments: ["index": .integer(2)]
        ))
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let thirdDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(thirdDelegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta", "Gamma"])
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.remove_delete_history_entry"))
    }

    func testCommandMacroRemoveDeleteHistoryEntriesRemovesPersistentSelectedRecords() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macroStore = AttoMacroStore(macroFileURL: tempDir.appendingPathComponent("Last Macro.sublime-macro"))
        let commands = [AttoRecordedCommand(commandID: "editor.duplicate_lines", arguments: [:])]
        try macroStore.save(commands, named: "Alpha", maxCount: 20)
        try macroStore.save(commands, named: "Beta", maxCount: 20)
        try macroStore.save(commands, named: "Gamma", maxCount: 20)
        try macroStore.save(commands, named: "Delta", maxCount: 20)

        let firstDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        firstDelegate._setMacroDeleteBatchConfirmationProviderForTesting { _ in true }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Alpha")]
        ))
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named",
            arguments: ["name": .string("Beta")]
        ))
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.delete_named_batch",
            arguments: ["names": .json("[\"Gamma\", \"Delta\"]")]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), [])
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.remove_delete_history_entries"))

        var removalAttempts: [[(displayIndex: Int, title: String)]] = []
        firstDelegate._setMacroDeleteHistoryEntriesRemovalConfirmationProviderForTesting { items in
            removalAttempts.append(items)
            return false
        }
        XCTAssertTrue(firstDelegate.executeCommand(
            id: "macro.remove_delete_history_entries",
            arguments: ["indices": .json("[1, 3, 1]")]
        ))
        XCTAssertEqual(removalAttempts.count, 1)
        XCTAssertEqual(removalAttempts.first?.map(\.displayIndex), [1, 3])
        XCTAssertEqual(removalAttempts.first?.map(\.title), ["Gamma, Delta (2 macros)", "Alpha"])
        XCTAssertTrue(firstDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let secondDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        secondDelegate._setMacroDeleteHistoryEntriesRemovalConfirmationProviderForTesting { items in
            XCTAssertEqual(items.map(\.displayIndex), [1, 3])
            XCTAssertEqual(items.map(\.title), ["Gamma, Delta (2 macros)", "Alpha"])
            return true
        }
        XCTAssertTrue(secondDelegate.executeCommand(
            id: "macro.remove_delete_history_entries",
            arguments: ["indices": .json("[1, 3]")]
        ))
        XCTAssertTrue(secondDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))

        let thirdDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(thirdDelegate.executeCommand(id: "macro.undo_delete"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Beta"])
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.undo_delete"))
        XCTAssertFalse(thirdDelegate._commandIsEnabledForTesting(commandID: "macro.remove_delete_history_entries"))
    }

    func testCommandMacroImportsAndExportsSublimeMacroFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let externalDir = tempDir.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        let sourceMacroURL = externalDir.appendingPathComponent("External Macro.sublime-macro")
        try """
        [
          {
            "command": "go.line",
            "args": {
              "line": 2,
              "column": 2
            }
          },
          {
            "command": "editor.duplicate_lines"
          }
        ]
        """.write(to: sourceMacroURL, atomically: true, encoding: .utf8)

        let internalDir = tempDir.appendingPathComponent("Internal", isDirectory: true)
        let macroURL = internalDir.appendingPathComponent("Last Macro.sublime-macro")
        let macroStore = AttoMacroStore(macroFileURL: macroURL)
        let importDelegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        XCTAssertTrue(importDelegate._commandIsEnabledForTesting(commandID: "macro.import_file"))
        XCTAssertFalse(importDelegate._commandIsEnabledForTesting(commandID: "macro.export_named"))

        XCTAssertTrue(importDelegate.executeCommand(
            id: "macro.import_file",
            arguments: [
                "path": .string(sourceMacroURL.path),
                "name": .string("Imported Macro"),
            ]
        ))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Imported Macro"])
        let importedURL = internalDir.appendingPathComponent("Imported Macro.sublime-macro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        let importedCommands = try XCTUnwrap(macroStore.loadNamedMacro("Imported Macro", maxCount: 512))
        XCTAssertEqual(importedCommands.map(\.commandID), ["go.line", "editor.duplicate_lines"])
        XCTAssertEqual(importedCommands.first?.arguments, ["line": .integer(2), "column": .integer(2)])
        XCTAssertTrue(importDelegate._commandIsEnabledForTesting(commandID: "macro.export_named"))

        let exportSchema = try XCTUnwrap(importDelegate._commandSchemaForTesting(commandID: "macro.export_named"))
        XCTAssertEqual(exportSchema.parameters.first?.choices.map(\.title), ["Imported Macro"])

        let exportURL = externalDir.appendingPathComponent("Round Trip.sublime-macro")
        XCTAssertTrue(importDelegate.executeCommand(
            id: "macro.export_named",
            arguments: [
                "name": .string("Imported Macro"),
                "path": .string(exportURL.path),
            ]
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        let exportedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [[String: Any]]
        let exported = try XCTUnwrap(exportedJSON)
        XCTAssertEqual(exported.count, 2)
        XCTAssertEqual(exported[0]["command"] as? String, "go.line")
        let exportedArgs = try XCTUnwrap(exported[0]["args"] as? [String: Any])
        XCTAssertEqual((exportedArgs["line"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((exportedArgs["column"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(exported[1]["command"] as? String, "editor.duplicate_lines")

        XCTAssertEqual(
            try XCTUnwrap(macroStore.loadNamedMacro("Imported Macro", maxCount: 512)),
            importedCommands
        )
    }

    func testCommandMacroImportExportUsesNativeFileSelectionProviders() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandMacroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let externalDir = tempDir.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let sourceMacroURL = externalDir.appendingPathComponent("Panel Source.sublime-macro")
        try """
        [
          {
            "command": "editor.duplicate_lines"
          }
        ]
        """.write(to: sourceMacroURL, atomically: true, encoding: .utf8)

        let internalDir = tempDir.appendingPathComponent("Internal", isDirectory: true)
        let macroStore = AttoMacroStore(macroFileURL: internalDir.appendingPathComponent("Last Macro.sublime-macro"))
        let delegate = makeDelegate(macroStore: macroStore, sessionRootURL: tempDir)
        delegate._setMacroImportSelectionProviderForTesting {
            (url: sourceMacroURL, name: "Panel Imported")
        }

        XCTAssertTrue(delegate.executeCommand(id: "macro.import_file"))
        XCTAssertEqual(macroStore.namedMacroNames(), ["Panel Imported"])

        let exportURL = externalDir.appendingPathComponent("Panel Export.sublime-macro")
        delegate._setMacroExportSelectionProviderForTesting { names in
            XCTAssertEqual(names, ["Panel Imported"])
            return (name: "Panel Imported", url: exportURL)
        }

        XCTAssertTrue(delegate.executeCommand(id: "macro.export_named"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        let exportedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [[String: Any]]
        let exported = try XCTUnwrap(exportedJSON)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported[0]["command"] as? String, "editor.duplicate_lines")
    }

    private func makeDelegate(
        macroStore: AttoMacroStore? = nil,
        sessionRootURL: URL
    ) -> AttoAppDelegate {
        let sessionURL = sessionRootURL.appendingPathComponent(
            "AttoEditorCommandMacroTests.session.json",
            isDirectory: false
        )
        let sessionStore = AttoSessionStore(sessionFileURL: sessionURL)
        let sessionManager = AttoSessionManager(store: sessionStore, debounceSeconds: 0)
        return AttoAppDelegate(
            keyBindings: [:],
            macroStore: macroStore,
            sessionManager: sessionManager
        )
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let found = findView(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }
}
