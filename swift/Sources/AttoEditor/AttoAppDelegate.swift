import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation
import UniformTypeIdentifiers

struct AttoRecentCommandRecord: Equatable {
    let commandID: String
    let arguments: AttoCommandArguments
}

struct AttoRecordedCommand: Equatable {
    let commandID: String
    let arguments: AttoCommandArguments
}

@MainActor
struct AttoRecentCommandStore {
    private static let defaultRecordsKey = "AttoEditor.RecentCommandRecords"
    private static let legacyCommandIDsKey = "AttoEditor.RecentCommandIDs"

    private let userDefaults: UserDefaults
    private let recordsKey: String
    private let legacyCommandIDsKey: String

    static let appDefault = AttoRecentCommandStore(userDefaults: .standard)

    init(
        userDefaults: UserDefaults,
        recordsKey: String = AttoRecentCommandStore.defaultRecordsKey,
        legacyCommandIDsKey: String = AttoRecentCommandStore.legacyCommandIDsKey
    ) {
        self.userDefaults = userDefaults
        self.recordsKey = recordsKey
        self.legacyCommandIDsKey = legacyCommandIDsKey
    }

    func load(maxCount: Int) -> [AttoRecentCommandRecord] {
        if let data = userDefaults.data(forKey: recordsKey),
           let stored = try? JSONDecoder().decode([StoredRecord].self, from: data)
        {
            return sanitize(stored.map(\.record), maxCount: maxCount)
        }

        return sanitize(
            (userDefaults.stringArray(forKey: legacyCommandIDsKey) ?? []).map {
                AttoRecentCommandRecord(commandID: $0, arguments: [:])
            },
            maxCount: maxCount
        )
    }

    func save(_ records: [AttoRecentCommandRecord], maxCount: Int) {
        let sanitized = sanitize(records, maxCount: maxCount)
        let stored = sanitized.map(StoredRecord.init(record:))
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: recordsKey)
        }
        userDefaults.set(sanitized.map(\.commandID), forKey: legacyCommandIDsKey)
    }

    private func sanitize(_ records: [AttoRecentCommandRecord], maxCount: Int) -> [AttoRecentCommandRecord] {
        var out: [AttoRecentCommandRecord] = []
        var seen: Set<String> = []
        for record in records {
            let trimmed = record.commandID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.contains(trimmed) == false else { continue }
            seen.insert(trimmed)
            out.append(AttoRecentCommandRecord(commandID: trimmed, arguments: record.arguments))
            if out.count >= maxCount { break }
        }
        return out
    }

    private struct StoredRecord: Codable {
        let commandID: String
        let arguments: [String: StoredArgument]

        init(record: AttoRecentCommandRecord) {
            commandID = record.commandID
            arguments = record.arguments.mapValues { StoredArgument(value: $0) }
        }

        var record: AttoRecentCommandRecord {
            AttoRecentCommandRecord(
                commandID: commandID,
                arguments: arguments.compactMapValues { $0.value }
            )
        }
    }

    private struct StoredArgument: Codable {
        let type: String
        let stringValue: String?
        let integerValue: Int?
        let numberValue: Double?
        let booleanValue: Bool?

        init(value: AttoCommandArgumentValue) {
            switch value {
            case .string(let value):
                type = "string"
                stringValue = value
                integerValue = nil
                numberValue = nil
                booleanValue = nil
            case .integer(let value):
                type = "integer"
                stringValue = nil
                integerValue = value
                numberValue = nil
                booleanValue = nil
            case .number(let value):
                type = "number"
                stringValue = nil
                integerValue = nil
                numberValue = value
                booleanValue = nil
            case .boolean(let value):
                type = "boolean"
                stringValue = nil
                integerValue = nil
                numberValue = nil
                booleanValue = value
            case .json(let value):
                type = "json"
                stringValue = value
                integerValue = nil
                numberValue = nil
                booleanValue = nil
            }
        }

        var value: AttoCommandArgumentValue? {
            switch type {
            case "string":
                return stringValue.map(AttoCommandArgumentValue.string)
            case "integer":
                return integerValue.map(AttoCommandArgumentValue.integer)
            case "number":
                return numberValue.map(AttoCommandArgumentValue.number)
            case "boolean":
                return booleanValue.map(AttoCommandArgumentValue.boolean)
            case "json":
                return stringValue.map(AttoCommandArgumentValue.json)
            default:
                return nil
            }
        }
    }
}

@MainActor
final class AttoAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var commandPaletteController: AttoCommandPaletteController?
    private var quickOpenController: AttoCommandPaletteController?
    private var preferencesWindowController: AttoPreferencesWindowController?

    private let library = EditorCoreUIFFILibrary()
    private let sessionManager = AttoSessionManager()
    private var runtimeCompatibilityReport: AttoRuntimeCompatibility.Report?

    private var windows: [AttoWindowContext] = []
    private var activeWindowID: UUID?
    private var keyBindings: [String: AttoKeyBinding]
    private var keySequences: [String: AttoKeySequence]
    private var keyBindingArguments: [String: AttoCommandArguments]
    private let keymapResolver: ((AttoKeymapContext) -> AttoKeymapResolution)?
    private var pendingKeySequence: [AttoKeyBinding] = []
    private var keySequenceTimeoutTimer: Timer?
    private let keySequencePrefixTimeoutSeconds: TimeInterval
    private var keySequenceStatusHandler: ((String?) -> Void)?
    private var keyEventMonitor: Any?
    private var recentCommandRecords: [AttoRecentCommandRecord] = []
    private let recentCommandStore: AttoRecentCommandStore?
    private let macroStore: AttoMacroStore?
    private var macroImportSelectionProvider: (() -> (url: URL, name: String)?)?
    private var macroExportSelectionProvider: (([String]) -> (name: String, url: URL)?)?
    private var macroDeleteConfirmationProvider: (([String]) -> Bool)?
    private var isRecordingMacro = false
    private var isReplayingMacro = false
    private var currentMacroCommands: [AttoRecordedCommand] = []
    private var lastMacroCommands: [AttoRecordedCommand] = []

    private static let maxRecentCommandCount = 12
    private static let maxRecordedMacroCommandCount = 512
    private static let sublimeMacroFileType = UTType(filenameExtension: "sublime-macro") ?? .json

    var ipcServer: AttoIpcServer?
    var createDefaultWindowOnLaunch: Bool = true

    override init() {
        let keymapResolver: (AttoKeymapContext) -> AttoKeymapResolution = { context in
            AttoKeymap.resolvedKeymap(context: context)
        }
        let keymap = keymapResolver(AttoKeymapContext())
        self.keyBindings = keymap.bindings
        self.keySequences = keymap.sequences
        self.keyBindingArguments = keymap.arguments
        self.keymapResolver = keymapResolver
        self.keySequencePrefixTimeoutSeconds = 1.0
        self.recentCommandStore = .appDefault
        self.recentCommandRecords = recentCommandStore?.load(maxCount: Self.maxRecentCommandCount) ?? []
        self.macroStore = .appDefault
        self.lastMacroCommands = self.macroStore?.load(maxCount: Self.maxRecordedMacroCommandCount) ?? []
        super.init()
    }

    init(
        keyBindings: [String: AttoKeyBinding],
        keyBindingArguments: [String: AttoCommandArguments] = [:],
        keySequences: [String: AttoKeySequence] = [:],
        keySequencePrefixTimeoutSeconds: TimeInterval = 1.0,
        keySequenceStatusHandler: ((String?) -> Void)? = nil,
        keymapResolver: ((AttoKeymapContext) -> AttoKeymapResolution)? = nil,
        recentCommandStore: AttoRecentCommandStore? = nil,
        macroStore: AttoMacroStore? = nil
    ) {
        self.keyBindings = keyBindings
        self.keySequences = keySequences
        self.keyBindingArguments = keyBindingArguments
        self.keymapResolver = keymapResolver
        self.keySequencePrefixTimeoutSeconds = keySequencePrefixTimeoutSeconds
        self.keySequenceStatusHandler = keySequenceStatusHandler
        self.recentCommandStore = recentCommandStore
        self.recentCommandRecords = recentCommandStore?.load(maxCount: Self.maxRecentCommandCount) ?? []
        self.macroStore = macroStore
        self.lastMacroCommands = self.macroStore?.load(maxCount: Self.maxRecordedMacroCommandCount) ?? []
        super.init()
    }

    private struct StaticEditorJSONCommand {
        let id: String
        let title: String
        let commandJSON: String
        let schema: AttoCommandSchema

        init(id: String, title: String, commandJSON: String) {
            self.id = id
            self.title = title
            self.commandJSON = commandJSON
            self.schema = AttoCommandSchema(
                macroPolicy: .recordable,
                defaultPayloadJSON: commandJSON,
                requiredRuntimeFeatures: .jsonCommandDispatch
            )
        }
    }

    private enum CommandAvailabilityRequirement {
        case none
        case activeWindow
        case activeEditor
        case multiplePanes
        case multipleTabs

        var requiresEditor: Bool {
            switch self {
            case .activeEditor, .multiplePanes, .multipleTabs:
                return true
            case .none, .activeWindow:
                return false
            }
        }
    }

    private struct CommandMetadata {
        let group: String
        let requirement: CommandAvailabilityRequirement
        let schema: AttoCommandSchema
    }

    private static let staticEditorJSONCommands: [StaticEditorJSONCommand] = [
        .init(id: "editor.duplicate_lines", title: "Edit: Duplicate Line", commandJSON: #"{"kind":"edit","op":"duplicate_lines"}"#),
        .init(id: "editor.delete_lines", title: "Edit: Delete Line", commandJSON: #"{"kind":"edit","op":"delete_lines"}"#),
        .init(id: "editor.move_lines_up", title: "Edit: Move Line Up", commandJSON: #"{"kind":"edit","op":"move_lines_up"}"#),
        .init(id: "editor.move_lines_down", title: "Edit: Move Line Down", commandJSON: #"{"kind":"edit","op":"move_lines_down"}"#),
        .init(id: "editor.join_lines", title: "Edit: Join Lines", commandJSON: #"{"kind":"edit","op":"join_lines"}"#),
        .init(id: "editor.split_line", title: "Edit: Split Line", commandJSON: #"{"kind":"edit","op":"split_line"}"#),
        .init(id: "editor.indent", title: "Edit: Indent", commandJSON: #"{"kind":"edit","op":"indent"}"#),
        .init(id: "editor.outdent", title: "Edit: Outdent", commandJSON: #"{"kind":"edit","op":"outdent"}"#),
        .init(id: "editor.delete_to_prev_tab_stop", title: "Edit: Delete to Previous Tab Stop", commandJSON: #"{"kind":"edit","op":"delete_to_prev_tab_stop"}"#),
        .init(id: "editor.snippet_next_placeholder", title: "Edit: Snippet Next Placeholder", commandJSON: #"{"kind":"cursor","op":"snippet_next_placeholder"}"#),
        .init(id: "editor.snippet_prev_placeholder", title: "Edit: Snippet Previous Placeholder", commandJSON: #"{"kind":"cursor","op":"snippet_prev_placeholder"}"#),
        .init(id: "editor.select_word", title: "Edit: Select Word", commandJSON: #"{"kind":"cursor","op":"select_word"}"#),
        .init(id: "editor.select_line", title: "Edit: Select Line", commandJSON: #"{"kind":"cursor","op":"select_line"}"#),
        .init(id: "editor.expand_selection", title: "Edit: Expand Selection", commandJSON: #"{"kind":"cursor","op":"expand_selection"}"#),
        .init(id: "editor.add_cursor_above", title: "Edit: Add Cursor Above", commandJSON: #"{"kind":"cursor","op":"add_cursor_above"}"#),
        .init(id: "editor.add_cursor_below", title: "Edit: Add Cursor Below", commandJSON: #"{"kind":"cursor","op":"add_cursor_below"}"#),
        .init(id: "view.wrap.none", title: "View: Word Wrap Off", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"none"}"#),
        .init(id: "view.wrap.char", title: "View: Word Wrap by Character", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#),
        .init(id: "view.wrap.word", title: "View: Word Wrap by Word", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"word"}"#),
    ]

    private static let snippetCommandSchema = AttoCommandSchema(
        parameters: [
            AttoCommandParameterSchema(
                name: "snippet",
                title: "Snippet",
                kind: .string,
                isRequired: true,
                allowsEmptyString: false,
                help: "editor-core snippet string using $0 and ${1:name} placeholders."
            ),
        ],
        macroPolicy: .recordableWithArguments
    )

    private static let goToLineCommandSchema = AttoCommandSchema(
        parameters: [
            AttoCommandParameterSchema(
                name: "line",
                title: "Line",
                kind: .integer,
                isRequired: true,
                minimumInteger: 1,
                help: "1-based logical line number."
            ),
            AttoCommandParameterSchema(
                name: "column",
                title: "Column",
                kind: .integer,
                defaultValue: .integer(1),
                minimumInteger: 1,
                help: "1-based logical column number."
            ),
        ],
        macroPolicy: .recordableWithArguments
    )

    private static let workspaceSymbolsCommandSchema = AttoCommandSchema(
        parameters: [
            AttoCommandParameterSchema(
                name: "query",
                title: "Query",
                kind: .string,
                defaultValue: .string(""),
                help: "Workspace symbol search query sent to the LSP server."
            ),
        ],
        macroPolicy: .recordableWithArguments,
        requiredRuntimeFeatures: .lspInteractiveCommandRequirements
    )

    private static let renameCommandSchema = AttoCommandSchema(
        parameters: [
            AttoCommandParameterSchema(
                name: "newName",
                title: "New Name",
                kind: .string,
                isRequired: true,
                allowsEmptyString: false,
                help: "Replacement symbol name passed to textDocument/rename."
            ),
        ],
        macroPolicy: .recordableWithArguments,
        requiredRuntimeFeatures: .lspWorkspaceEditCommandRequirements
    )

    private static func macroNameCommandSchema(choices: [String] = []) -> AttoCommandSchema {
        AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "name",
                    title: "Macro Name",
                    kind: .string,
                    isRequired: true,
                    choices: choices.map { AttoCommandArgumentChoice(title: $0, value: .string($0)) },
                    allowsEmptyString: false,
                    help: "Name of a .sublime-macro file in AttoEditor's macro directory."
                ),
            ],
            macroPolicy: .notRecordable
        )
    }

    private static func macroRenameCommandSchema(choices: [String] = []) -> AttoCommandSchema {
        AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "oldName",
                    title: "Existing Macro",
                    kind: .string,
                    isRequired: true,
                    choices: choices.map { AttoCommandArgumentChoice(title: $0, value: .string($0)) },
                    allowsEmptyString: false,
                    help: "Existing .sublime-macro name in AttoEditor's macro directory."
                ),
                AttoCommandParameterSchema(
                    name: "newName",
                    title: "New Macro Name",
                    kind: .string,
                    isRequired: true,
                    allowsEmptyString: false,
                    help: "New .sublime-macro file name."
                ),
            ],
            macroPolicy: .notRecordable
        )
    }

    private static func macroDeleteBatchCommandSchema() -> AttoCommandSchema {
        AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "names",
                    title: "Macro Names",
                    kind: .json,
                    isRequired: true,
                    help: "JSON array of named macros to delete, for example [\"Build\", \"Format\"]."
                ),
            ],
            macroPolicy: .notRecordable
        )
    }

    private static func macroImportCommandSchema() -> AttoCommandSchema {
        AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "path",
                    title: "Macro File Path",
                    kind: .string,
                    isRequired: true,
                    allowsEmptyString: false,
                    help: "Path to an existing .sublime-macro file."
                ),
                AttoCommandParameterSchema(
                    name: "name",
                    title: "Imported Macro Name",
                    kind: .string,
                    isRequired: true,
                    allowsEmptyString: false,
                    help: "Name to store in AttoEditor's macro directory."
                ),
            ],
            macroPolicy: .notRecordable
        )
    }

    private static func macroExportCommandSchema(choices: [String] = []) -> AttoCommandSchema {
        AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "name",
                    title: "Macro Name",
                    kind: .string,
                    isRequired: true,
                    choices: choices.map { AttoCommandArgumentChoice(title: $0, value: .string($0)) },
                    allowsEmptyString: false,
                    help: "Existing .sublime-macro name in AttoEditor's macro directory."
                ),
                AttoCommandParameterSchema(
                    name: "path",
                    title: "Export File Path",
                    kind: .string,
                    isRequired: true,
                    allowsEmptyString: false,
                    help: "Destination .sublime-macro file path."
                ),
            ],
            macroPolicy: .notRecordable
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .attoPreferencesDidChange,
            object: nil
        )

        guard validateRuntimeCompatibilityBeforeLaunch() else {
            return
        }
        installKeyEventMonitorIfNeeded()

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        let windowsWereEmptyAtLaunch = windows.isEmpty
        var didRestoreSession = false

        if createDefaultWindowOnLaunch {
            if windowsWereEmptyAtLaunch {
                didRestoreSession = restoreSessionIfEligible(contentSize: contentSize)
                if didRestoreSession == false {
                    _ = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
                }
            }

            if windows.isEmpty == false {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

        commandPaletteController = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.CommandPalette",
            showsCommandGroups: true,
            argumentProvider: { command in
                AttoCommandArgumentPrompt.promptArguments(for: command)
            },
            commandsProvider: { [weak self] in
                self?.defaultCommands() ?? []
            }
        )

        quickOpenController = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.QuickOpen",
            commandsProvider: { [weak self] in
                self?.quickOpenCommands() ?? []
            }
        )

        // Demo: 仅在开发态启动 GUI 时打开一个真实 Rust 文件，确保 LSP/theme 可见。
        //
        // 规则：
        // - `.app` bundle 启动：不做 demo 行为（避免对最终用户造成困扰）
        // - session restore 成功：不做 demo 行为
        // - IPC spool 已经创建了窗口：不做 demo 行为
        let isBundledApp = (Bundle.main.bundleURL.pathExtension == "app")
        if createDefaultWindowOnLaunch,
           isBundledApp == false,
           windowsWereEmptyAtLaunch,
           didRestoreSession == false,
           let first = windows.first
        {
            let initial = first.workspaceRootURL.appendingPathComponent("crates/tui-editor/src/main.rs")
            if FileManager.default.fileExists(atPath: initial.path) {
                first.rememberRecentFile(initial)
                first.editorAreaController.openFile(url: initial)
                first.fileExplorerController.revealFile(initial)
            }
        }

        if windows.isEmpty == false {
            scheduleSessionSave(reason: "did_finish_launching")
        }

        // Remove system window-tabbing menu items (e.g. "Show Tab Bar") from standard menus.
        removeSystemWindowTabbingMenuItems()

        // Ensure preferences are applied (also covers env-var fallbacks).
        applyEditorPreferencesToAllWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if windows.isEmpty == false {
            sessionManager.saveNow(reason: "will_terminate", capture: { [weak self] in
                self?.makeSessionSnapshot()
            })
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        clearPendingKeySequence()
        ipcServer?.stop()
    }

    private func installKeyEventMonitorIfNeeded() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated {
                self.handleKeyDownEvent(event)
            }
            return handled ? nil : event
        }
    }

    private func validateRuntimeCompatibilityBeforeLaunch(logSuccess: Bool = true) -> Bool {
        let report = AttoRuntimeCompatibility.evaluate(library: library)
        runtimeCompatibilityReport = report
        guard report.isCompatible else {
            presentRuntimeCompatibilityFailure(report)
            NSApplication.shared.terminate(nil)
            return false
        }
        if logSuccess {
            NSLog("AttoEditor: %@", report.diagnosticMessage)
        }
        return true
    }

    private func presentRuntimeCompatibilityFailure(_ report: AttoRuntimeCompatibility.Report) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "AttoEditor cannot start"
        alert.informativeText = report.diagnosticMessage
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }

    // MARK: - Menu actions

    @objc func openFolderMenuClicked(_ sender: Any?) {
        let defaultDir = activeWindow()?.workspaceRootURL ?? AttoAppDelegate.defaultRepoRootURL()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open."
        panel.directoryURL = defaultDir

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)
        let ctx = createWindow(workspaceRootURL: url.standardizedFileURL, contentSize: contentSize)
        focusWindow(ctx)
    }

    @objc func openFileMenuClicked(_ sender: Any?) {
        guard let ctx = ensureActiveWindowForMenuActions() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a file to open."
        panel.directoryURL = ctx.workspaceRootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        ctx.rememberRecentFile(url)
        ctx.editorAreaController.openFile(url: url)
        ctx.fileExplorerController.revealFile(url)
    }

    @objc func newFileMenuClicked(_ sender: Any?) {
        guard let ctx = ensureActiveWindowForMenuActions() else { return }

        let fm = FileManager.default
        let dir = ctx.workspaceRootURL.standardizedFileURL

        var n = 1
        var url: URL
        while true {
            url = dir.appendingPathComponent("untitled-\(n).txt", isDirectory: false)
            // “New File” should not touch disk; it only creates a new in-memory buffer.
            // Still, we want a stable, human-friendly display name, so we generate a file URL
            // under the workspace root and keep it unique across BOTH:
            // 1) existing files on disk, and
            // 2) currently opened (possibly unsaved) tabs.
            if fm.fileExists(atPath: url.path) == false, ctx.editorAreaController.containsFile(url: url) == false {
                break
            }
            n += 1
            if n > 9_999 {
                NSSound.beep()
                NSLog("AttoEditor: new file name search exhausted under %@", dir.path)
                return
            }
        }

        _ = ctx.editorAreaController.openFile(url: url, mode: .pinned, isUntitled: true)
    }

    private func ensureActiveWindowForMenuActions() -> AttoWindowContext? {
        if let ctx = activeWindow() { return ctx }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        let ctx = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
        focusWindow(ctx)
        return ctx
    }

    @objc func closeTabMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.closeActiveTab()
    }

    @objc func saveMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.saveActiveTab()
    }

    @objc func toggleSidebarMenuClicked(_ sender: Any?) {
        activeWindow()?.toggleSidebar()
    }

    @objc func toggleMinimapMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.toggleMinimapForActiveTab()
    }

    @objc func commandPaletteMenuClicked(_ sender: Any?) {
        showCommandPalette()
    }

    @objc func goToFileMenuClicked(_ sender: Any?) {
        showQuickOpen()
    }

    @objc func findMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.showFindBar()
    }

    @objc func replaceMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.showReplaceBar()
    }

    @objc func findInFilesMenuClicked(_ sender: Any?) {
        activeWindow()?.showFindInFilesSidebar()
    }

    @objc func preferencesMenuClicked(_ sender: Any?) {
        showPreferencesWindow()
    }

    @objc func commandMenuItemClicked(_ sender: Any?) {
        let commandID: String?
        if let item = sender as? NSMenuItem {
            commandID = item.representedObject as? String
        } else {
            commandID = sender as? String
        }

        guard let commandID else {
            NSSound.beep()
            return
        }
        executeCommandUsingKeymapArguments(commandID: commandID)
    }

    @discardableResult
    private func executeCommandUsingKeymapArguments(commandID: String) -> Bool {
        executeCommandUsingKeymapArguments(commandID: commandID, keymap: keymapResolutionForCurrentContext())
    }

    @discardableResult
    private func executeCommandUsingKeymapArguments(commandID: String, keymap: AttoKeymapResolution) -> Bool {
        if let arguments = keymap.arguments[commandID] {
            executeCommand(id: commandID, arguments: arguments)
        } else {
            executeCommand(id: commandID)
        }
    }

    @discardableResult
    func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard let binding = AttoKeymap.binding(for: event) else {
            clearPendingKeySequence()
            return false
        }
        return handleKeyBinding(binding)
    }

    @discardableResult
    private func handleKeyBinding(_ binding: AttoKeyBinding) -> Bool {
        let keymap = keymapResolutionForCurrentContext()

        if pendingKeySequence.isEmpty == false, binding == AttoKeymap.parseBinding("escape") {
            clearPendingKeySequence()
            return true
        }

        let candidate = pendingKeySequence + [binding]
        if let commandID = commandID(forKeySequence: candidate, keymap: keymap) {
            clearPendingKeySequence()
            return executeCommandUsingKeymapArguments(commandID: commandID, keymap: keymap)
        }

        if hasKeySequencePrefix(candidate, keymap: keymap) {
            setPendingKeySequence(candidate)
            return true
        }

        if pendingKeySequence.isEmpty, let commandID = commandID(forKeyBinding: binding, keymap: keymap) {
            return executeCommandUsingKeymapArguments(commandID: commandID, keymap: keymap)
        }

        let hadPending = pendingKeySequence.isEmpty == false
        clearPendingKeySequence()

        if hadPending, hasKeySequencePrefix([binding], keymap: keymap) {
            setPendingKeySequence([binding])
            return true
        }

        if hadPending, let commandID = commandID(forKeyBinding: binding, keymap: keymap) {
            return executeCommandUsingKeymapArguments(commandID: commandID, keymap: keymap)
        }

        return false
    }

    private func setPendingKeySequence(_ sequence: [AttoKeyBinding]) {
        pendingKeySequence = sequence
        publishPendingKeySequenceStatus()
        restartKeySequenceTimeout()
    }

    private func clearPendingKeySequence() {
        let hadPending = pendingKeySequence.isEmpty == false
        pendingKeySequence = []
        keySequenceTimeoutTimer?.invalidate()
        keySequenceTimeoutTimer = nil
        if hadPending {
            publishPendingKeySequenceStatus()
        }
    }

    private func restartKeySequenceTimeout() {
        keySequenceTimeoutTimer?.invalidate()
        keySequenceTimeoutTimer = nil

        guard keySequencePrefixTimeoutSeconds > 0 else { return }
        keySequenceTimeoutTimer = Timer.scheduledTimer(
            timeInterval: keySequencePrefixTimeoutSeconds,
            target: self,
            selector: #selector(keySequenceTimeoutTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        keySequenceTimeoutTimer?.tolerance = 0.05
    }

    @objc private func keySequenceTimeoutTimerFired(_ timer: Timer) {
        _ = timer
        clearPendingKeySequence()
    }

    private func publishPendingKeySequenceStatus() {
        let text: String? = if pendingKeySequence.isEmpty {
            nil
        } else {
            "Keys: \(pendingKeySequence.map(\.displayText).joined(separator: " "))"
        }

        if let keySequenceStatusHandler {
            keySequenceStatusHandler(text)
        } else {
            activeWindow()?.editorAreaController.setTransientStatusText(text)
        }
    }

    private func keymapResolutionForCurrentContext() -> AttoKeymapResolution {
        guard let keymapResolver else {
            return AttoKeymapResolution(
                bindings: keyBindings,
                sequences: keySequences,
                arguments: keyBindingArguments,
                conflicts: [],
                sequenceConflicts: []
            )
        }
        return keymapResolver(currentKeymapContext())
    }

    private func currentKeymapContext() -> AttoKeymapContext {
        activeWindow()?.editorAreaController.keymapContextForActiveState() ?? AttoKeymapContext()
    }

    private func commandID(forKeySequence bindings: [AttoKeyBinding], keymap: AttoKeymapResolution) -> String? {
        keymap.sequences.first { _, sequence in
            sequence.bindings == bindings
        }?.key
    }

    private func commandID(forKeyBinding binding: AttoKeyBinding, keymap: AttoKeymapResolution) -> String? {
        keymap.bindings.first { _, candidate in
            candidate == binding
        }?.key
    }

    private func hasKeySequencePrefix(_ bindings: [AttoKeyBinding], keymap: AttoKeymapResolution) -> Bool {
        keymap.sequences.values.contains { sequence in
            guard sequence.bindings.count > bindings.count else { return false }
            return Array(sequence.bindings.prefix(bindings.count)) == bindings
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let commandID = menuItem.representedObject as? String else { return true }
        return commandIsEnabled(commandID: commandID)
    }

    // MARK: - Command palette integration

    private func showCommandPalette() {
        guard let win = activeWindow()?.window else { return }
        commandPaletteController?.show(relativeTo: win)
    }

    private func showQuickOpen() {
        guard let win = activeWindow()?.window else { return }
        quickOpenController?.show(relativeTo: win, placeholder: "Type a file name to open…")
    }

    private func defaultCommands(orderForCommandPalette: Bool = true) -> [AttoCommandPaletteCommand] {
        var commands: [AttoCommandPaletteCommand] = [
            .init(id: "file.new", title: "File: New File") { [weak self] in
                self?.newFileMenuClicked(nil)
            },
            .init(id: "file.open_folder", title: "File: Open Folder…") { [weak self] in
                self?.openFolderMenuClicked(nil)
            },
            .init(id: "file.open_file", title: "File: Open File…") { [weak self] in
                self?.openFileMenuClicked(nil)
            },
            .init(id: "file.save", title: "File: Save") { [weak self] in
                self?.saveMenuClicked(nil)
            },
            .init(id: "file.close_tab", title: "File: Close Tab") { [weak self] in
                self?.closeTabMenuClicked(nil)
            },
            .init(id: "file.close_all_tabs", title: "File: Close All Tabs") { [weak self] in
                self?.activeWindow()?.editorAreaController.closeAllTabsForWindow()
            },
            .init(id: "file.close_other_tabs", title: "File: Close Other Tabs") { [weak self] in
                self?.activeWindow()?.editorAreaController.closeOtherTabsForActiveTab()
            },
            .init(id: "file.close_tabs_to_right", title: "File: Close Tabs to Right") { [weak self] in
                self?.activeWindow()?.editorAreaController.closeTabsToRightOfActiveTab()
            },
            .init(id: "file.move_tab_left", title: "File: Move Tab Left") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveActiveTabLeft()
            },
            .init(id: "file.move_tab_right", title: "File: Move Tab Right") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveActiveTabRight()
            },
            .init(id: "editor.format_document", title: "Edit: Format Document") { [weak self] in
                self?.activeWindow()?.editorAreaController.formatDocumentWithLspInActiveTab()
            },
            .init(id: "editor.format_selection", title: "Edit: Format Selection") { [weak self] in
                self?.activeWindow()?.editorAreaController.formatSelectionWithLspInActiveTab()
            },
            .init(id: "editor.find", title: "Edit: Find") { [weak self] in
                self?.activeWindow()?.editorAreaController.showFindBar()
            },
            .init(id: "editor.replace", title: "Edit: Replace") { [weak self] in
                self?.activeWindow()?.editorAreaController.showReplaceBar()
            },
            .init(id: "workspace.undo_last_workspace_edit", title: "Workspace: Undo Last Workspace Edit") { [weak self] in
                self?.activeWindow()?.editorAreaController.undoLastCoreWorkspaceEditTransaction()
            },
            .init(id: "view.toggle_sidebar", title: "View: Toggle Sidebar") { [weak self] in
                self?.activeWindow()?.toggleSidebar()
            },
            .init(id: "view.toggle_minimap", title: "View: Toggle Minimap") { [weak self] in
                self?.activeWindow()?.editorAreaController.toggleMinimapForActiveTab()
            },
            .init(id: "view.split_right", title: "View: Split Right") { [weak self] in
                self?.activeWindow()?.editorAreaController.splitActiveTabRight()
            },
            .init(id: "view.focus_next_pane", title: "View: Focus Next Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.focusNextPaneInActiveTab()
            },
            .init(id: "view.focus_previous_pane", title: "View: Focus Previous Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.focusPreviousPaneInActiveTab()
            },
            .init(id: "view.move_pane_left", title: "View: Move Pane Left") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveActivePaneLeft()
            },
            .init(id: "view.move_pane_right", title: "View: Move Pane Right") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveActivePaneRight()
            },
            .init(id: "view.close_pane", title: "View: Close Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.closeActivePane()
            },
            .init(id: "workbench.command_palette", title: "AttoEditor: Command Palette") { [weak self] in
                self?.showCommandPalette()
            },
            .init(id: "macro.toggle_recording", title: "Macro: Toggle Recording") { [weak self] in
                self?.toggleMacroRecording()
            },
            .init(id: "macro.replay_last", title: "Macro: Replay Last Macro") { [weak self] in
                self?.replayLastMacro()
            },
            .init(
                id: "macro.save_named",
                title: "Macro: Save Last Macro As…",
                schema: Self.macroNameCommandSchema()
            ) { [weak self] arguments in
                self?.saveNamedMacro(arguments: arguments)
            },
            .init(
                id: "macro.replay_named",
                title: "Macro: Replay Named Macro…",
                schema: Self.macroNameCommandSchema()
            ) { [weak self] arguments in
                self?.replayNamedMacro(arguments: arguments)
            },
            .init(
                id: "macro.rename_named",
                title: "Macro: Rename Named Macro…",
                schema: Self.macroRenameCommandSchema()
            ) { [weak self] arguments in
                self?.renameNamedMacro(arguments: arguments)
            },
            .init(
                id: "macro.delete_named",
                title: "Macro: Delete Named Macro…",
                schema: Self.macroNameCommandSchema()
            ) { [weak self] arguments in
                self?.deleteNamedMacro(arguments: arguments)
            },
            .init(
                id: "macro.delete_named_batch",
                title: "Macro: Delete Named Macros…",
                schema: Self.macroDeleteBatchCommandSchema()
            ) { [weak self] arguments in
                self?.deleteNamedMacros(arguments: arguments)
            },
            .init(
                id: "macro.import_file",
                title: "Macro: Import Macro File…",
                schema: Self.macroImportCommandSchema()
            ) { [weak self] arguments in
                self?.importNamedMacro(arguments: arguments)
            },
            .init(
                id: "macro.export_named",
                title: "Macro: Export Named Macro…",
                schema: Self.macroExportCommandSchema()
            ) { [weak self] arguments in
                self?.exportNamedMacro(arguments: arguments)
            },
            .init(id: "go.file", title: "Go: Go to File…") { [weak self] in
                self?.showQuickOpen()
            },
            .init(
                id: "go.line",
                title: "Go: Go to Line…",
                schema: Self.goToLineCommandSchema
            ) { [weak self] arguments in
                guard let line = arguments.integer("line") else {
                    self?.activeWindow()?.editorAreaController.promptGoToLineInActiveTab()
                    return
                }
                let column = arguments.integer("column") ?? 1
                self?.activeWindow()?.editorAreaController.goToLineInActiveTab(line1: line, column1: column)
            },
            .init(id: "search.find_in_files", title: "Search: Find in Files") { [weak self] in
                self?.activeWindow()?.showFindInFilesSidebar()
            },
            .init(id: "workbench.preferences", title: "AttoEditor: Preferences…") { [weak self] in
                self?.showPreferencesWindow()
            },
            .init(id: "go.back", title: "Go: Back") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpBackInActiveTab()
            },
            .init(id: "go.forward", title: "Go: Forward") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpForwardInActiveTab()
            },
            .init(id: "go.matching_bracket", title: "Go: Go to Matching Bracket") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveToMatchingBracketInActiveTab()
            },
            .init(id: "lsp.go_to_definition", title: "LSP: Go to Definition") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToDefinitionInActiveTab()
            },
            .init(id: "lsp.go_to_declaration", title: "LSP: Go to Declaration") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToDeclarationInActiveTab()
            },
            .init(id: "lsp.go_to_type_definition", title: "LSP: Go to Type Definition") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToTypeDefinitionInActiveTab()
            },
            .init(id: "lsp.go_to_implementation", title: "LSP: Go to Implementation") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToImplementationInActiveTab()
            },
            .init(id: "lsp.find_references", title: "LSP: Find References") { [weak self] in
                self?.activeWindow()?.editorAreaController.findReferencesInActiveTab()
            },
            .init(id: "lsp.show_last_locations", title: "LSP: Show Last Locations") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLastLspLocationResults()
            },
            .init(id: "lsp.show_location_history", title: "LSP: Show Location History") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLspLocationHistory()
            },
            .init(id: "lsp.show_locations_panel", title: "LSP: Show Locations Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLspLocationPanel()
            },
            .init(id: "lsp.show_workbench_panel", title: "LSP: Show Workbench Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLspWorkbenchPanel()
            },
            .init(id: "lsp.call_hierarchy_incoming", title: "LSP: Incoming Calls") { [weak self] in
                self?.activeWindow()?.editorAreaController.showIncomingCallsInActiveTab()
            },
            .init(id: "lsp.call_hierarchy_outgoing", title: "LSP: Outgoing Calls") { [weak self] in
                self?.activeWindow()?.editorAreaController.showOutgoingCallsInActiveTab()
            },
            .init(id: "lsp.type_hierarchy_supertypes", title: "LSP: Supertypes") { [weak self] in
                self?.activeWindow()?.editorAreaController.showTypeSupertypesInActiveTab()
            },
            .init(id: "lsp.type_hierarchy_subtypes", title: "LSP: Subtypes") { [weak self] in
                self?.activeWindow()?.editorAreaController.showTypeSubtypesInActiveTab()
            },
            .init(id: "lsp.show_hierarchy_panel", title: "LSP: Show Hierarchy Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showHierarchyPanelInActiveTab()
            },
            .init(
                id: "lsp.rename",
                title: "LSP: Rename Symbol",
                schema: Self.renameCommandSchema
            ) { [weak self] arguments in
                guard let newName = arguments.string("newName") else {
                    self?.activeWindow()?.editorAreaController.promptRenameSymbolInActiveTab()
                    return
                }
                self?.activeWindow()?.editorAreaController.renameSymbolInActiveTab(to: newName)
            },
            .init(id: "lsp.code_actions", title: "LSP: Code Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCodeActionsInActiveTab()
            },
            .init(id: "lsp.code_lens_actions", title: "LSP: Code Lens Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCodeLensActionsInActiveTab()
            },
            .init(id: "lsp.code_lens_at_cursor", title: "LSP: Code Lens at Cursor") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCodeLensActionsAtCursorInActiveTab()
            },
            .init(id: "lsp.show_code_lens_panel", title: "LSP: Show Code Lens Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCodeLensPanelInActiveTab()
            },
            .init(id: "lsp.refresh_code_lens", title: "LSP: Refresh Code Lens") { [weak self] in
                self?.activeWindow()?.editorAreaController.refreshCodeLensInActiveTab()
            },
            .init(id: "lsp.refresh_inlay_hints", title: "LSP: Refresh Inlay Hints") { [weak self] in
                self?.activeWindow()?.editorAreaController.refreshInlayHintsInActiveTab()
            },
            .init(id: "lsp.show_inlay_hints_panel", title: "LSP: Show Inlay Hints Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showInlayHintsPanelInActiveTab()
            },
            .init(id: "lsp.refresh_document_links", title: "LSP: Refresh Document Links") { [weak self] in
                self?.activeWindow()?.editorAreaController.refreshDocumentLinksInActiveTab()
            },
            .init(id: "lsp.show_document_links_panel", title: "LSP: Show Document Links Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showDocumentLinksPanelInActiveTab()
            },
            .init(id: "lsp.quick_fix", title: "LSP: Quick Fixes") { [weak self] in
                self?.activeWindow()?.editorAreaController.showQuickFixesInActiveTab()
            },
            .init(id: "lsp.refactor", title: "LSP: Refactor Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showRefactorActionsInActiveTab()
            },
            .init(id: "lsp.source_actions", title: "LSP: Source Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showSourceActionsInActiveTab()
            },
            .init(id: "lsp.organize_imports", title: "LSP: Organize Imports") { [weak self] in
                self?.activeWindow()?.editorAreaController.organizeImportsInActiveTab()
            },
            .init(id: "lsp.fix_all", title: "LSP: Fix All") { [weak self] in
                self?.activeWindow()?.editorAreaController.fixAllInActiveTab()
            },
            .init(id: "lsp.problems", title: "LSP: Problems") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProblemsInActiveTab()
            },
            .init(id: "lsp.show_problems_panel", title: "LSP: Show Problems Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProblemsPanelInActiveTab()
            },
            .init(id: "lsp.workspace_diagnostics", title: "LSP: Workspace Diagnostics") { [weak self] in
                self?.activeWindow()?.editorAreaController.showWorkspaceDiagnosticsInActiveTab()
            },
            .init(id: "lsp.show_workspace_problems_panel", title: "LSP: Show Workspace Problems Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showWorkspaceProblemsPanelInActiveTab()
            },
            .init(id: "lsp.show_project_lsp_status", title: "LSP: Show Project Status Events") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProjectLspStatusEventsPanel()
            },
            .init(id: "lsp.show_project_lsp_health", title: "LSP: Show Project Process Health") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProjectLspProcessHealthPanel()
            },
            .init(id: "lsp.show_project_lsp_health_log", title: "LSP: Show Project Process Health Log") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProjectLspProcessHealthLogPanel()
            },
            .init(id: "lsp.show_project_lsp_dashboard", title: "LSP: Show Project Health Dashboard") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProjectLspDashboardPanel()
            },
            .init(id: "lsp.clear_project_lsp_health_log", title: "LSP: Clear Project Process Health Log") { [weak self] in
                self?.activeWindow()?.editorAreaController.clearProjectLspProcessHealthLog()
            },
            .init(id: "lsp.export_project_lsp_health_log", title: "LSP: Export Project Process Health Log") { [weak self] in
                self?.activeWindow()?.editorAreaController.exportProjectLspProcessHealthLog()
            },
            .init(id: "lsp.restart_server", title: "LSP: Restart Server") { [weak self] in
                self?.activeWindow()?.editorAreaController.restartLspServerInActiveTab()
            },
            .init(id: "lsp.restart_project_servers", title: "LSP: Restart Project Servers") { [weak self] in
                self?.activeWindow()?.editorAreaController.restartProjectLspServers()
            },
            .init(id: "lsp.document_colors", title: "LSP: Document Colors") { [weak self] in
                self?.activeWindow()?.editorAreaController.showDocumentColorsInActiveTab()
            },
            .init(id: "lsp.pick_document_color", title: "LSP: Pick Document Color") { [weak self] in
                self?.activeWindow()?.editorAreaController.pickDocumentColorInActiveTab()
            },
            .init(id: "lsp.show_document_colors_panel", title: "LSP: Show Document Colors Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showDocumentColorsPanelInActiveTab()
            },
            .init(id: "lsp.refresh_folding_ranges", title: "LSP: Refresh Folding Ranges") { [weak self] in
                self?.activeWindow()?.editorAreaController.refreshFoldingRangesInActiveTab()
            },
            .init(id: "lsp.selection_range", title: "LSP: Expand Selection") { [weak self] in
                self?.activeWindow()?.editorAreaController.expandSelectionWithLspInActiveTab()
            },
            .init(id: "lsp.linked_editing", title: "LSP: Linked Editing") { [weak self] in
                self?.activeWindow()?.editorAreaController.startLinkedEditingInActiveTab()
            },
            .init(id: "lsp.document_symbols", title: "LSP: Document Symbols") { [weak self] in
                self?.activeWindow()?.editorAreaController.showDocumentSymbolsInActiveTab()
            },
            .init(
                id: "lsp.workspace_symbols",
                title: "LSP: Workspace Symbols",
                schema: Self.workspaceSymbolsCommandSchema
            ) { [weak self] arguments in
                guard let query = arguments.string("query") else {
                    self?.activeWindow()?.editorAreaController.promptWorkspaceSymbolsInActiveTab()
                    return
                }
                self?.activeWindow()?.editorAreaController.showWorkspaceSymbolsInActiveTab(query: query)
            },
            .init(id: "lsp.show_last_symbols", title: "LSP: Show Last Symbols") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLastLspSymbolResults()
            },
            .init(id: "lsp.show_symbol_history", title: "LSP: Show Symbol History") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLspSymbolHistory()
            },
            .init(id: "lsp.show_symbols_panel", title: "LSP: Show Symbols Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showLspSymbolPanel()
            },
            .init(id: "lsp.show_workspace_outline_panel", title: "LSP: Show Workspace Outline Panel") { [weak self] in
                self?.activeWindow()?.editorAreaController.showWorkspaceOutlinePanel()
            },
            .init(id: "lsp.completion", title: "LSP: Completion") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCompletionsInActiveTab()
            },
            .init(id: "lsp.signature_help", title: "LSP: Signature Help") { [weak self] in
                self?.activeWindow()?.editorAreaController.showSignatureHelpInActiveTab()
            },
        ]

        commands.append(contentsOf: cursorMovementCommands())
        commands.append(contentsOf: editorCommandPaletteCommands())
        let contextualCommands = commands.map(commandWithCurrentContext(_:))
        guard orderForCommandPalette else { return contextualCommands }
        return commandsOrderedForCommandPalette(contextualCommands)
    }

    func _defaultCommandsForTesting() -> [AttoCommandPaletteCommand] {
        defaultCommands()
    }

    func _keyBindingForTesting(commandID: String) -> AttoKeyBinding? {
        keyBinding(forCommandID: commandID)
    }

    func _keyBindingArgumentsForTesting(commandID: String) -> AttoCommandArguments? {
        keymapResolutionForCurrentContext().arguments[commandID]
    }

    func _keySequenceForTesting(commandID: String) -> AttoKeySequence? {
        keymapResolutionForCurrentContext().sequences[commandID]
    }

    func _keymapContextForTesting() -> AttoKeymapContext {
        currentKeymapContext()
    }

    func _pendingKeySequenceForTesting() -> [AttoKeyBinding] {
        pendingKeySequence
    }

    func _expirePendingKeySequenceForTesting() {
        clearPendingKeySequence()
    }

    @discardableResult
    func _handleKeyBindingForTesting(_ binding: AttoKeyBinding) -> Bool {
        handleKeyBinding(binding)
    }

    func _commandIsEnabledForTesting(commandID: String) -> Bool {
        commandIsEnabled(commandID: commandID)
    }

    func _commandSchemaForTesting(commandID: String) -> AttoCommandSchema? {
        defaultCommands(orderForCommandPalette: false).first(where: { $0.id == commandID })?.schema
    }

    func _commandConflictsForTesting() -> [String] {
        Self.duplicateCommandIDs(in: defaultCommands(orderForCommandPalette: false))
    }

    func _recentCommandIDsForTesting() -> [String] {
        recentCommandRecords.map(\.commandID)
    }

    func _recentCommandArgumentsForTesting(commandID: String) -> AttoCommandArguments? {
        recentCommandRecords.first { $0.commandID == commandID }?.arguments
    }

    func _isRecordingMacroForTesting() -> Bool {
        isRecordingMacro
    }

    func _lastMacroCommandsForTesting() -> [AttoRecordedCommand] {
        lastMacroCommands
    }

    func _setMacroImportSelectionProviderForTesting(_ provider: (() -> (url: URL, name: String)?)?) {
        macroImportSelectionProvider = provider
    }

    func _setMacroExportSelectionProviderForTesting(_ provider: (([String]) -> (name: String, url: URL)?)?) {
        macroExportSelectionProvider = provider
    }

    func _setMacroDeleteConfirmationProviderForTesting(_ provider: ((String) -> Bool)?) {
        macroDeleteConfirmationProvider = provider.map { stringProvider in
            { names in stringProvider(names.joined(separator: "\n")) }
        }
    }

    func _setMacroDeleteBatchConfirmationProviderForTesting(_ provider: (([String]) -> Bool)?) {
        macroDeleteConfirmationProvider = provider
    }

    func _validateRuntimeCompatibilityForTesting() -> Bool {
        validateRuntimeCompatibilityBeforeLaunch(logSuccess: false)
    }

    func _runtimeCompatibilityReportForTesting() -> AttoRuntimeCompatibility.Report? {
        runtimeCompatibilityReport
    }

    func _setRuntimeInfoForTesting(_ runtimeInfo: EditorCoreUIFFIRuntimeInfo) {
        runtimeCompatibilityReport = AttoRuntimeCompatibility.evaluate(runtimeInfo: runtimeInfo)
    }

    func _createWindowForTesting(workspaceRootURL: URL) -> AttoWindowContext {
        createWindow(
            workspaceRootURL: workspaceRootURL,
            contentSize: AttoWindowSizing.preferredContentSize,
            centerOnShow: false
        )
    }

    @discardableResult
    func executeCommand(id commandID: String) -> Bool {
        executeCommand(id: commandID, explicitArguments: nil)
    }

    @discardableResult
    func executeCommand(id commandID: String, arguments: AttoCommandArguments) -> Bool {
        executeCommand(id: commandID, explicitArguments: arguments)
    }

    @discardableResult
    private func executeCommand(id commandID: String, explicitArguments arguments: AttoCommandArguments?) -> Bool {
        guard let command = defaultCommands(orderForCommandPalette: false).first(where: { $0.id == commandID }) else {
            NSSound.beep()
            NSLog("AttoEditor: unknown command id %@", commandID)
            return false
        }
        guard command.isEnabled else {
            NSSound.beep()
            return false
        }
        guard let arguments else {
            command.run()
            return true
        }
        do {
            let normalized = try command.schema.normalizedArguments(arguments)
            command.runWithArguments(normalized)
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: invalid arguments for command %@: %@", commandID, String(describing: error))
            return false
        }
        return true
    }

    func keyBinding(forCommandID commandID: String) -> AttoKeyBinding? {
        keymapResolutionForCurrentContext().bindings[commandID]
    }

    private func editorCommandPaletteCommands() -> [AttoCommandPaletteCommand] {
        var commands = Self.staticEditorJSONCommands.map { spec in
            AttoCommandPaletteCommand(id: spec.id, title: spec.title) { [weak self] in
                self?.activeWindow()?.editorAreaController.executeActiveEditorCommandJSON(spec.commandJSON)
            }
        }

        commands.append(contentsOf: [
            .init(
                id: "editor.apply_snippet",
                title: "Edit: Apply Snippet",
                schema: Self.snippetCommandSchema
            ) { [weak self] arguments in
                guard let snippet = arguments.string("snippet") else {
                    self?.activeWindow()?.editorAreaController.promptApplySnippetInActiveTab()
                    return
                }
                self?.activeWindow()?.editorAreaController.applySnippetInActiveTab(snippet)
            },
            .init(id: "editor.add_next_occurrence", title: "Edit: Add Next Occurrence") { [weak self] in
                self?.activeWindow()?.editorAreaController.addNextOccurrenceInActiveTab()
            },
            .init(id: "editor.add_all_occurrences", title: "Edit: Add All Occurrences") { [weak self] in
                self?.activeWindow()?.editorAreaController.addAllOccurrencesInActiveTab()
            },
            .init(id: "editor.toggle_line_comment", title: "Edit: Toggle Line Comment") { [weak self] in
                self?.activeWindow()?.editorAreaController.toggleLineCommentInActiveTab()
            },
            .init(id: "editor.fold_selection", title: "Edit: Fold Selection") { [weak self] in
                self?.activeWindow()?.editorAreaController.foldSelectionInActiveTab()
            },
            .init(id: "editor.unfold", title: "Edit: Unfold at Cursor") { [weak self] in
                self?.activeWindow()?.editorAreaController.unfoldAtCursorInActiveTab()
            },
            .init(id: "editor.unfold_all", title: "Edit: Unfold All") { [weak self] in
                self?.activeWindow()?.editorAreaController.unfoldAllInActiveTab()
            },
        ])

        return commands
    }

    private func cursorMovementCommands() -> [AttoCommandPaletteCommand] {
        AttoEditorAreaViewController.CursorMovementCommand.allCases.map { command in
            AttoCommandPaletteCommand(id: command.id, title: command.title) { [weak self] in
                self?.activeWindow()?.editorAreaController.performCursorMovementCommand(command)
            }
        }
    }

    private func commandWithCurrentContext(_ command: AttoCommandPaletteCommand) -> AttoCommandPaletteCommand {
        let metadata = commandMetadata(commandID: command.id, title: command.title)
        let schema = metadata.schema
        return AttoCommandPaletteCommand(
            id: command.id,
            title: command.title,
            group: metadata.group,
            swatchColor: command.swatchColor,
            isEnabled: commandIsEnabled(commandID: command.id),
            requiresEditor: metadata.requirement.requiresEditor,
            schema: schema,
            promptsForArguments: schema.isParameterized,
            initialArguments: command.initialArguments,
            runWithArguments: { [weak self] arguments in
                command.runWithArguments(arguments)
                self?.recordMacroCommandIfNeeded(commandID: command.id, schema: schema, arguments: arguments)
                self?.rememberRecentCommand(command.id, arguments: arguments)
            }
        )
    }

    private func commandsOrderedForCommandPalette(
        _ commands: [AttoCommandPaletteCommand]
    ) -> [AttoCommandPaletteCommand] {
        guard recentCommandRecords.isEmpty == false else { return commands }

        var commandsByID: [String: AttoCommandPaletteCommand] = [:]
        for command in commands where commandsByID[command.id] == nil {
            commandsByID[command.id] = command
        }
        let recentCommands = recentCommandRecords.compactMap { record -> AttoCommandPaletteCommand? in
            guard let command = commandsByID[record.commandID] else { return nil }
            return commandReplayingRecentArguments(command, arguments: record.arguments)
        }
        let recentSet = Set(recentCommands.map(\.id))
        let remainingCommands = commands.filter { recentSet.contains($0.id) == false }
        return recentCommands + remainingCommands
    }

    private func commandReplayingRecentArguments(
        _ command: AttoCommandPaletteCommand,
        arguments: AttoCommandArguments
    ) -> AttoCommandPaletteCommand {
        guard arguments.isEmpty == false,
              let replayArguments = try? command.schema.normalizedArguments(arguments)
        else {
            return command
        }

        return AttoCommandPaletteCommand(
            id: command.id,
            title: command.title,
            group: command.group,
            swatchColor: command.swatchColor,
            isEnabled: command.isEnabled,
            requiresEditor: command.requiresEditor,
            schema: command.schema,
            promptsForArguments: command.promptsForArguments,
            initialArguments: replayArguments,
            runWithArguments: { providedArguments in
                let effectiveArguments = providedArguments.isEmpty ? replayArguments : providedArguments
                command.runWithArguments(effectiveArguments)
            }
        )
    }

    private func rememberRecentCommand(_ commandID: String, arguments: AttoCommandArguments) {
        guard commandID != "workbench.command_palette" else { return }

        recentCommandRecords.removeAll { $0.commandID == commandID }
        recentCommandRecords.insert(AttoRecentCommandRecord(commandID: commandID, arguments: arguments), at: 0)
        if recentCommandRecords.count > Self.maxRecentCommandCount {
            recentCommandRecords.removeLast(recentCommandRecords.count - Self.maxRecentCommandCount)
        }
        recentCommandStore?.save(recentCommandRecords, maxCount: Self.maxRecentCommandCount)
    }

    private func toggleMacroRecording() {
        if isRecordingMacro {
            stopMacroRecording()
        } else {
            startMacroRecording()
        }
    }

    private func startMacroRecording() {
        currentMacroCommands = []
        isRecordingMacro = true
    }

    private func stopMacroRecording() {
        guard isRecordingMacro else { return }
        lastMacroCommands = currentMacroCommands
        currentMacroCommands = []
        isRecordingMacro = false
        try? macroStore?.save(lastMacroCommands, maxCount: Self.maxRecordedMacroCommandCount)
    }

    private func replayLastMacro() {
        guard isRecordingMacro == false, lastMacroCommands.isEmpty == false else {
            NSSound.beep()
            return
        }

        replayMacroCommands(lastMacroCommands)
    }

    private func saveNamedMacro(arguments: AttoCommandArguments) {
        guard let name = arguments.string("name") ?? promptMacroName(commandID: "macro.save_named", title: "Macro: Save Last Macro As…") else {
            return
        }
        _ = saveLastMacro(named: name)
    }

    private func replayNamedMacro(arguments: AttoCommandArguments) {
        guard let name = arguments.string("name") ?? promptMacroName(commandID: "macro.replay_named", title: "Macro: Replay Named Macro…") else {
            return
        }
        _ = replayNamedMacro(named: name)
    }

    private func renameNamedMacro(arguments: AttoCommandArguments) {
        let effectiveArguments = arguments.isEmpty
            ? (promptMacroArguments(commandID: "macro.rename_named", title: "Macro: Rename Named Macro…") ?? [:])
            : arguments
        guard let oldName = effectiveArguments.string("oldName"),
              let newName = effectiveArguments.string("newName")
        else {
            return
        }
        _ = renameNamedMacro(from: oldName, to: newName)
    }

    private func deleteNamedMacro(arguments: AttoCommandArguments) {
        guard let name = arguments.string("name") ?? promptMacroName(commandID: "macro.delete_named", title: "Macro: Delete Named Macro…") else {
            return
        }
        _ = deleteNamedMacro(named: name)
    }

    private func deleteNamedMacros(arguments: AttoCommandArguments) {
        let effectiveArguments = arguments.isEmpty
            ? (promptMacroArguments(commandID: "macro.delete_named_batch", title: "Macro: Delete Named Macros…") ?? [:])
            : arguments
        guard let names = macroNamesArgument(effectiveArguments, parameter: "names") else {
            return
        }
        _ = deleteNamedMacros(named: names)
    }

    private func importNamedMacro(arguments: AttoCommandArguments) {
        if arguments.isEmpty {
            guard let selection = macroImportSelectionProvider?() ?? promptImportMacroFile() else {
                return
            }
            _ = importNamedMacro(from: selection.url, named: selection.name)
            return
        }

        let effectiveArguments = arguments.isEmpty
            ? (promptMacroArguments(commandID: "macro.import_file", title: "Macro: Import Macro File…") ?? [:])
            : arguments
        guard let path = effectiveArguments.string("path"),
              let name = effectiveArguments.string("name")
        else {
            return
        }
        _ = importNamedMacro(fromPath: path, named: name)
    }

    private func exportNamedMacro(arguments: AttoCommandArguments) {
        if arguments.isEmpty {
            let names = macroStore?.namedMacroNames() ?? []
            guard let selection = macroExportSelectionProvider?(names) ?? promptExportNamedMacro(names: names) else {
                return
            }
            _ = exportNamedMacro(named: selection.name, to: selection.url)
            return
        }

        let effectiveArguments = arguments.isEmpty
            ? (promptMacroArguments(commandID: "macro.export_named", title: "Macro: Export Named Macro…") ?? [:])
            : arguments
        guard let name = effectiveArguments.string("name"),
              let path = effectiveArguments.string("path")
        else {
            return
        }
        _ = exportNamedMacro(named: name, toPath: path)
    }

    private func saveLastMacro(named name: String) -> Bool {
        guard isRecordingMacro == false, lastMacroCommands.isEmpty == false, let macroStore else {
            NSSound.beep()
            return false
        }

        do {
            try macroStore.save(lastMacroCommands, named: name, maxCount: Self.maxRecordedMacroCommandCount)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save macro %@: %@", name, String(describing: error))
            return false
        }
    }

    private func replayNamedMacro(named name: String) -> Bool {
        guard isRecordingMacro == false,
              let commands = macroStore?.loadNamedMacro(name, maxCount: Self.maxRecordedMacroCommandCount),
              commands.isEmpty == false
        else {
            NSSound.beep()
            return false
        }

        replayMacroCommands(commands)
        return true
    }

    private func renameNamedMacro(from oldName: String, to newName: String) -> Bool {
        guard isRecordingMacro == false, let macroStore else {
            NSSound.beep()
            return false
        }

        do {
            try macroStore.renameNamedMacro(oldName, to: newName)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to rename macro %@ to %@: %@", oldName, newName, String(describing: error))
            return false
        }
    }

    private func deleteNamedMacro(named name: String) -> Bool {
        guard isRecordingMacro == false, let macroStore else {
            NSSound.beep()
            return false
        }
        guard confirmDeleteNamedMacro(name) else {
            return false
        }

        do {
            try macroStore.deleteNamedMacro(name)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to delete macro %@: %@", name, String(describing: error))
            return false
        }
    }

    private func deleteNamedMacros(named rawNames: [String]) -> Bool {
        guard isRecordingMacro == false, let macroStore else {
            NSSound.beep()
            return false
        }

        let names: [String]
        do {
            names = try macroStore.normalizedNamedMacroNames(rawNames)
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: invalid macro names for batch delete: %@", String(describing: error))
            return false
        }
        let existingNames = Set(macroStore.namedMacroNames())
        if let missingName = names.first(where: { existingNames.contains($0) == false }) {
            NSSound.beep()
            NSLog("AttoEditor: failed to delete macros, missing macro %@", missingName)
            return false
        }
        guard confirmDeleteNamedMacros(names) else {
            return false
        }

        do {
            try macroStore.deleteNamedMacros(names)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to delete macros %@: %@", names.joined(separator: ", "), String(describing: error))
            return false
        }
    }

    private func confirmDeleteNamedMacro(_ name: String) -> Bool {
        confirmDeleteNamedMacros([name])
    }

    private func confirmDeleteNamedMacros(_ names: [String]) -> Bool {
        if let macroDeleteConfirmationProvider {
            return macroDeleteConfirmationProvider(names)
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = names.count == 1 ? "Delete Macro?" : "Delete Macros?"
        if names.count == 1, let name = names.first {
            alert.informativeText = "Delete the named macro \"\(name)\" from AttoEditor's macro directory. This cannot be undone."
        } else {
            let preview = names.prefix(8).map { "- \($0)" }.joined(separator: "\n")
            let overflow = names.count > 8 ? "\n...and \(names.count - 8) more." : ""
            alert.informativeText = "Delete \(names.count) named macros from AttoEditor's macro directory?\n\n\(preview)\(overflow)\n\nThis cannot be undone."
        }
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func macroNamesArgument(_ arguments: AttoCommandArguments, parameter: String) -> [String]? {
        guard case .json(let rawJSON)? = arguments[parameter],
              let data = rawJSON.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            NSSound.beep()
            NSLog("AttoEditor: macro batch delete expects '%@' to be a JSON string array", parameter)
            return nil
        }
        guard names.isEmpty == false else {
            NSSound.beep()
            return nil
        }
        return names
    }

    private func importNamedMacro(fromPath path: String, named name: String) -> Bool {
        guard isRecordingMacro == false, let sourceURL = macroFileURL(fromPath: path) else {
            NSSound.beep()
            return false
        }

        return importNamedMacro(from: sourceURL, named: name)
    }

    private func importNamedMacro(from sourceURL: URL, named name: String) -> Bool {
        guard isRecordingMacro == false, let macroStore else {
            NSSound.beep()
            return false
        }

        do {
            try macroStore.importNamedMacro(from: sourceURL, named: name, maxCount: Self.maxRecordedMacroCommandCount)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to import macro %@ from %@: %@", name, sourceURL.path, String(describing: error))
            return false
        }
    }

    private func exportNamedMacro(named name: String, toPath path: String) -> Bool {
        guard isRecordingMacro == false, let destinationURL = macroFileURL(fromPath: path) else {
            NSSound.beep()
            return false
        }

        return exportNamedMacro(named: name, to: destinationURL)
    }

    private func exportNamedMacro(named name: String, to destinationURL: URL) -> Bool {
        guard isRecordingMacro == false, let macroStore else {
            NSSound.beep()
            return false
        }

        do {
            try macroStore.exportNamedMacro(name, to: destinationURL, maxCount: Self.maxRecordedMacroCommandCount)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to export macro %@ to %@: %@", name, destinationURL.path, String(describing: error))
            return false
        }
    }

    private func macroFileURL(fromPath rawPath: String) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false else { return nil }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(path, isDirectory: false)
            .standardizedFileURL
    }

    private func promptImportMacroFile() -> (url: URL, name: String)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a .sublime-macro file to import."
        panel.allowedContentTypes = [Self.sublimeMacroFileType]

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return nil
        }

        let derivedName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (url, derivedName.isEmpty ? "Imported Macro" : derivedName)
    }

    private func promptExportNamedMacro(names: [String]) -> (name: String, url: URL)? {
        guard names.isEmpty == false else { return nil }
        let name: String
        if names.count == 1 {
            name = names[0]
        } else {
            guard let selected = promptMacroName(
                title: "Macro: Export Named Macro…",
                choices: names
            ) else {
                return nil
            }
            name = selected
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Export the selected macro as a .sublime-macro file."
        panel.nameFieldStringValue = "\(name).sublime-macro"
        panel.allowedContentTypes = [Self.sublimeMacroFileType]

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return nil
        }
        return (name, url)
    }

    private func promptMacroName(commandID: String, title: String) -> String? {
        promptMacroArguments(commandID: commandID, title: title)?.string("name")
    }

    private func promptMacroName(title: String, choices: [String]) -> String? {
        let promptCommand = AttoCommandPaletteCommand(
            id: "macro.select_named",
            title: title,
            schema: Self.macroNameCommandSchema(choices: choices),
            promptsForArguments: true
        ) { _ in }
        return AttoCommandArgumentPrompt.promptArguments(for: promptCommand)?.string("name")
    }

    private func promptMacroArguments(commandID: String, title: String) -> AttoCommandArguments? {
        let schema = commandSchema(commandID: commandID)
        let promptCommand = AttoCommandPaletteCommand(
            id: commandID,
            title: title,
            schema: schema,
            promptsForArguments: true
        ) { _ in }
        return AttoCommandArgumentPrompt.promptArguments(for: promptCommand)
    }

    private func replayMacroCommands(_ commands: [AttoRecordedCommand]) {
        isReplayingMacro = true
        defer { isReplayingMacro = false }

        for command in lastMacroCommands {
            if command.arguments.isEmpty {
                _ = executeCommand(id: command.commandID)
            } else {
                _ = executeCommand(id: command.commandID, arguments: command.arguments)
            }
        }
    }

    private func recordMacroCommandIfNeeded(commandID: String, schema: AttoCommandSchema, arguments: AttoCommandArguments) {
        guard isRecordingMacro, isReplayingMacro == false else { return }

        let recordedArguments: AttoCommandArguments
        switch schema.macroPolicy {
        case .recordable:
            recordedArguments = [:]
        case .recordableWithArguments:
            guard arguments.isEmpty == false else { return }
            recordedArguments = arguments
        case .promptRequired, .notRecordable:
            return
        }

        currentMacroCommands.append(AttoRecordedCommand(commandID: commandID, arguments: recordedArguments))
        if currentMacroCommands.count > Self.maxRecordedMacroCommandCount {
            currentMacroCommands.removeFirst(currentMacroCommands.count - Self.maxRecordedMacroCommandCount)
        }
    }

    private func commandIsEnabled(commandID: String) -> Bool {
        switch commandID {
        case "macro.replay_last":
            return isRecordingMacro == false && lastMacroCommands.isEmpty == false
        case "macro.save_named":
            return isRecordingMacro == false && lastMacroCommands.isEmpty == false && macroStore != nil
        case "macro.replay_named", "macro.rename_named", "macro.delete_named", "macro.delete_named_batch":
            return isRecordingMacro == false && (macroStore?.namedMacroNames().isEmpty == false)
        case "macro.import_file":
            return isRecordingMacro == false && macroStore != nil
        case "macro.export_named":
            return isRecordingMacro == false && (macroStore?.namedMacroNames().isEmpty == false)
        default:
            break
        }

        let metadata = commandMetadata(commandID: commandID, title: commandID)
        return commandIsEnabled(requirement: metadata.requirement, schema: metadata.schema)
    }

    private func commandIsEnabled(requirement: CommandAvailabilityRequirement, schema: AttoCommandSchema) -> Bool {
        guard runtimeSupports(schema.requiredRuntimeFeatures) else {
            return false
        }

        switch requirement {
        case .none:
            return true
        case .activeWindow:
            return activeWindow() != nil
        case .activeEditor:
            return activeWindow()?.editorAreaController.hasActiveEditorForCommands == true
        case .multiplePanes:
            return activeWindow()?.editorAreaController.hasMultiplePanesForCommands == true
        case .multipleTabs:
            return activeWindow()?.editorAreaController.hasMultipleTabsForCommands == true
        }
    }

    private func runtimeSupports(_ features: EditorCoreUIFFIFeatures) -> Bool {
        guard features.isEmpty == false else { return true }
        let supported = runtimeCompatibilityReport?.runtimeInfo?.features ?? library.featureFlags
        return supported.contains(features)
    }

    private func commandMetadata(commandID: String, title: String) -> CommandMetadata {
        let group: String = {
            if let prefix = title.split(separator: ":", maxSplits: 1).first,
               prefix.isEmpty == false,
               prefix.count < title.count
            {
                return String(prefix)
            }

            if commandID.hasPrefix("file.") { return "File" }
            if commandID.hasPrefix("editor.") { return "Edit" }
            if commandID.hasPrefix("cursor.") { return "Cursor" }
            if commandID.hasPrefix("view.") { return "View" }
            if commandID.hasPrefix("go.") { return "Go" }
            if commandID.hasPrefix("search.") { return "Search" }
            if commandID.hasPrefix("lsp.") { return "LSP" }
            if commandID.hasPrefix("workspace.") { return "Workspace" }
            if commandID.hasPrefix("workbench.") { return "AttoEditor" }
            return "General"
        }()

        let requirement: CommandAvailabilityRequirement = {
            switch commandID {
            case "file.open_folder", "file.open_file", "file.new", "workbench.command_palette", "workbench.preferences":
                return .none
            case "go.file", "search.find_in_files", "view.toggle_sidebar", "workspace.undo_last_workspace_edit":
                return .activeWindow
            case "view.focus_next_pane", "view.focus_previous_pane", "view.move_pane_left", "view.move_pane_right", "view.close_pane":
                return .multiplePanes
            case "file.close_other_tabs", "file.close_tabs_to_right",
                 "file.move_tab_left", "file.move_tab_right":
                return .multipleTabs
            default:
                if commandID == "file.save" || commandID == "file.close_tab" || commandID == "file.close_all_tabs" {
                    return .activeEditor
                }
                if commandID.hasPrefix("editor.")
                    || commandID.hasPrefix("cursor.")
                    || commandID.hasPrefix("lsp.")
                    || commandID.hasPrefix("view.wrap.")
                    || commandID == "view.toggle_minimap"
                    || commandID == "view.split_right"
                    || commandID == "go.line"
                    || commandID == "go.back"
                    || commandID == "go.forward"
                    || commandID == "go.matching_bracket"
                {
                    return .activeEditor
                }
                return .none
            }
        }()

        return CommandMetadata(
            group: group,
            requirement: requirement,
            schema: commandSchema(commandID: commandID)
        )
    }

    private func commandSchema(commandID: String) -> AttoCommandSchema {
        if let staticCommand = Self.staticEditorJSONCommands.first(where: { $0.id == commandID }) {
            return staticCommand.schema
        }

        switch commandID {
        case "editor.apply_snippet":
            return Self.snippetCommandSchema
        case "go.line":
            return Self.goToLineCommandSchema
        case "lsp.workspace_symbols":
            return Self.workspaceSymbolsCommandSchema
        case "lsp.rename":
            return Self.renameCommandSchema
        case "editor.format_document", "editor.format_selection":
            return AttoCommandSchema(
                macroPolicy: .notRecordable,
                requiredRuntimeFeatures: .lspInteractiveCommandRequirements
            )
        case "lsp.code_actions", "lsp.quick_fix", "lsp.refactor", "lsp.source_actions",
             "lsp.organize_imports", "lsp.fix_all":
            return AttoCommandSchema(
                macroPolicy: .notRecordable,
                requiredRuntimeFeatures: .lspWorkspaceEditCommandRequirements
            )
        case "workspace.undo_last_workspace_edit":
            return AttoCommandSchema(
                macroPolicy: .notRecordable,
                requiredRuntimeFeatures: .workspaceEditTransactionUndoCommandRequirements
            )
        case "file.open_folder", "file.open_file", "workbench.preferences", "go.file",
             "editor.find", "editor.replace", "workbench.command_palette":
            return AttoCommandSchema(macroPolicy: .promptRequired)
        case "macro.save_named":
            return Self.macroNameCommandSchema()
        case "macro.replay_named":
            return Self.macroNameCommandSchema(choices: macroStore?.namedMacroNames() ?? [])
        case "macro.rename_named":
            return Self.macroRenameCommandSchema(choices: macroStore?.namedMacroNames() ?? [])
        case "macro.delete_named":
            return Self.macroNameCommandSchema(choices: macroStore?.namedMacroNames() ?? [])
        case "macro.delete_named_batch":
            return Self.macroDeleteBatchCommandSchema()
        case "macro.import_file":
            return Self.macroImportCommandSchema()
        case "macro.export_named":
            return Self.macroExportCommandSchema(choices: macroStore?.namedMacroNames() ?? [])
        case "macro.toggle_recording", "macro.replay_last":
            return AttoCommandSchema(macroPolicy: .notRecordable)
        case "file.new", "file.save", "file.close_tab", "file.close_all_tabs",
             "file.close_other_tabs", "file.close_tabs_to_right",
             "file.move_tab_left", "file.move_tab_right",
             "view.toggle_sidebar", "view.toggle_minimap", "view.split_right",
             "view.focus_next_pane", "view.focus_previous_pane",
             "view.move_pane_left", "view.move_pane_right", "view.close_pane",
             "go.back", "go.forward", "go.matching_bracket":
            return AttoCommandSchema(macroPolicy: .recordable)
        default:
            if commandID.hasPrefix("cursor.") {
                return AttoCommandSchema(macroPolicy: .recordable)
            }
            if commandID.hasPrefix("lsp.") {
                return AttoCommandSchema(
                    macroPolicy: .notRecordable,
                    requiredRuntimeFeatures: .lspInteractiveCommandRequirements
                )
            }
            if commandID == "editor.add_next_occurrence"
                || commandID == "editor.add_all_occurrences"
                || commandID == "editor.toggle_line_comment"
                || commandID == "editor.fold_selection"
                || commandID == "editor.unfold"
                || commandID == "editor.unfold_all"
            {
                return AttoCommandSchema(macroPolicy: .recordable)
            }
            return AttoCommandSchema(macroPolicy: .notRecordable)
        }
    }

    private static func duplicateCommandIDs(in commands: [AttoCommandPaletteCommand]) -> [String] {
        var counts: [String: Int] = [:]
        for command in commands {
            counts[command.id, default: 0] += 1
        }
        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    // MARK: - Preferences

    @objc private func preferencesDidChange(_ notification: Notification) {
        applyEditorPreferencesToAllWindows()
    }

    private func showPreferencesWindow() {
        if preferencesWindowController == nil {
            preferencesWindowController = AttoPreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func applyEditorPreferencesToAllWindows() {
        let registry = AttoThemeManager.loadRegistry()
        let effectiveThemeName = AttoPreferences.shared.effectiveThemeName
        let resolved = AttoThemeManager.resolveSkiaTheme(themeName: effectiveThemeName, registry: registry)

        for ctx in windows {
            ctx.editorAreaController.applyTheme(resolved.theme)
            ctx.editorAreaController.applyEditorPreferences()
        }
    }

    private func quickOpenCommands() -> [AttoCommandPaletteCommand] {
        guard let ctx = activeWindow() else { return [] }
        let editorAreaController = ctx.editorAreaController
        let fileExplorerController = ctx.fileExplorerController
        let all = ctx.fileIndex.entries()

        var out: [AttoCommandPaletteCommand] = []
        var seen: Set<URL> = Set()

        for url in ctx.recentFiles {
            let u = url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            let title = ctx.relativePathForDisplay(u)
            out.append(.init(title: title) { [weak self] in
                self?.activeWindow()?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        for entry in all {
            let u = entry.url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            out.append(.init(title: entry.relativePath) { [weak self] in
                self?.activeWindow()?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        return out
    }

    // MARK: - macOS window tabbing (disable + hide menu items)

    private func removeSystemWindowTabbingMenuItems() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }

        let actionNamesToRemove: Set<String> = [
            "toggleTabBar:",
            "showTabBar:",
            "showAllTabs:",
            "selectNextTab:",
            "selectPreviousTab:",
            "moveTabToNewWindow:",
            "mergeAllWindows:",
        ]

        let titlesToRemove: Set<String> = [
            "Show Tab Bar",
            "Hide Tab Bar",
            "Show All Tabs",
        ]

        func strip(menu: NSMenu) {
            // Iterate backwards so removal doesn't invalidate indices.
            for item in menu.items.reversed() {
                if titlesToRemove.contains(item.title) {
                    menu.removeItem(item)
                    continue
                }
                if let action = item.action {
                    let name = NSStringFromSelector(action)
                    if actionNamesToRemove.contains(name) {
                        menu.removeItem(item)
                        continue
                    }
                }
                if let sub = item.submenu {
                    strip(menu: sub)
                }
            }
        }

        strip(menu: mainMenu)
    }

    // MARK: - Helpers

    private static func defaultRepoRootURL() -> URL {
        // Finder 双击启动 `.app` 时，进程 cwd 往往是 `/`，用它作为默认 workspace root 很奇怪。
        // 这里把 bundle 启动的默认目录设为用户 Home。
        if Bundle.main.bundleURL.pathExtension == "app" {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        // 开发态：尝试从源码路径推导 repo root（只在本仓库内构建/运行时成立）。
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AttoEditor
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // swift
            .deletingLastPathComponent() // repo root
            .standardizedFileURL

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
        }

        // 兜底：如果 binary 被移动（例如打包后的裸可执行文件），则用 cwd；若 cwd 不存在则用 Home。
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
        if FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDir), isDir.boolValue {
            return cwd
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Session (restore/save)

    private func makeSessionSnapshot() -> AttoSessionSnapshot? {
        guard windows.isEmpty == false else { return nil }

        let activeIndex: Int? = {
            guard let id = activeWindowID else { return nil }
            return windows.firstIndex(where: { $0.id == id })
        }()

        let windowSnaps = windows.map { $0.makeSessionSnapshot() }
        return AttoSessionSnapshot(
            schemaVersion: AttoSessionSnapshot.currentSchemaVersion,
            savedAt: Date(),
            activeWindowIndex: activeIndex,
            windows: windowSnaps
        )
    }

    private func scheduleSessionSave(reason: String) {
        sessionManager.scheduleSave(reason: reason, capture: { [weak self] in
            self?.makeSessionSnapshot()
        })
    }

    private func restoreSessionIfEligible(contentSize: CGSize) -> Bool {
        // 仅 `.app` bundle 启动时恢复；CLI 冷启动不恢复。
        let args = ProcessInfo.processInfo.arguments
        guard let snapshot = sessionManager.loadSnapshotForRestore(arguments: args) else { return false }
        guard snapshot.windows.isEmpty == false else { return false }

        sessionManager.beginRestoring()
        defer {
            sessionManager.endRestoring(capture: { [weak self] in
                self?.makeSessionSnapshot()
            })
        }

        let fm = FileManager.default

        func validatedWorkspaceRoot(_ path: String) -> URL? {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url
        }

        func rectIfVisible(_ frame: AttoWindowFrameSnapshot?) -> CGRect? {
            guard let frame else { return nil }
            let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            guard rect.width >= 200, rect.height >= 200 else { return nil }
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
            return visible ? rect : nil
        }

        for win in snapshot.windows {
            let root = validatedWorkspaceRoot(win.workspaceRootPath) ?? fm.homeDirectoryForCurrentUser
            let frameRect = rectIfVisible(win.frame)
            let ctx = createWindow(
                workspaceRootURL: root,
                contentSize: contentSize,
                initialFrame: frameRect,
                centerOnShow: (frameRect == nil)
            )

            ctx.sidebarSplitItem.isCollapsed = win.sidebarCollapsed
            ctx.restoreRecentFiles(filePaths: win.recentFilePaths)
            ctx.editorAreaController.restoreSession(
                tabs: win.tabs,
                selectedTabIndex: win.selectedTabIndex
            )
        }

        if windows.isEmpty {
            return false
        }

        if let idx = snapshot.activeWindowIndex, (0..<windows.count).contains(idx) {
            focusWindow(windows[idx])
        } else if let first = windows.first {
            focusWindow(first)
        }

        // restore 结束后写回一次“清理后的快照”（比如跳过了不存在的文件）。
        scheduleSessionSave(reason: "restore_completed")

        return true
    }

    // MARK: - Windows

    private func createWindow(
        workspaceRootURL: URL,
        contentSize: CGSize,
        initialFrame: CGRect? = nil,
        centerOnShow: Bool = true
    ) -> AttoWindowContext {
        let referenceWindow: NSWindow? = activeWindow()?.window ?? windows.last?.window

        let registry = AttoThemeManager.loadRegistry()
        let effectiveThemeName = AttoPreferences.shared.effectiveThemeName
        let resolved = AttoThemeManager.resolveSkiaTheme(themeName: effectiveThemeName, registry: registry)

        let ctx = AttoWindowContext(
            library: library,
            theme: resolved.theme,
            workspaceRootURL: workspaceRootURL,
            contentSize: contentSize
        )

        let windowID = ctx.id
        ctx.editorAreaController.onDidCloseFile = { [weak self] url in
            self?.ipcServer?.notifyFileInstanceClosed(windowID: windowID, url: url)
        }

        ctx.onWindowBecameKey = { [weak self] ctx in
            guard let self else { return }
            self.activeWindowID = ctx.id
            self.scheduleSessionSave(reason: "window_became_key")
        }
        ctx.onWindowWillClose = { [weak self] ctx in
            guard let self else { return }

            // 先保存一次“仍包含该窗口”的 session，避免关闭最后一个窗口导致 session 变空而丢失状态。
            self.sessionManager.saveNow(reason: "window_will_close", capture: { [weak self] in
                self?.makeSessionSnapshot()
            })

            self.windows.removeAll { $0.id == ctx.id }
            if self.activeWindowID == ctx.id {
                self.activeWindowID = self.windows.first?.id
            }
            self.handleWindowWillCloseForWait(ctx)

            // 再保存一次“移除该窗口后的 session”（如果没有窗口则跳过写盘）。
            self.scheduleSessionSave(reason: "window_closed")
        }

        ctx.onSessionStateChanged = { [weak self] in
            self?.scheduleSessionSave(reason: "window_state_changed")
        }
        ctx.editorAreaController.onSessionStateChanged = { [weak self] in
            self?.scheduleSessionSave(reason: "tabs_changed")
        }

        windows.append(ctx)
        if activeWindowID == nil {
            activeWindowID = ctx.id
        }

        var resolvedInitialFrame = initialFrame
        var resolvedCenterOnShow = centerOnShow

        // 默认行为（center）会导致新窗口与现有窗口完全重叠。
        // 这里做一个“级联/cascade”定位：
        // - 若已有窗口且未最大化：新窗口在现有窗口的基础上偏移一小段距离；
        // - 若现有窗口是最大化：允许新窗口与其相同位置（甚至相同大小）。
        if resolvedInitialFrame == nil, resolvedCenterOnShow, let referenceWindow, windows.count >= 2 {
            if let autoFrame = Self.autoPlacedFrameForNewWindow(referenceWindow: referenceWindow) {
                resolvedInitialFrame = autoFrame
                resolvedCenterOnShow = false
            }
        }

        if let resolvedInitialFrame {
            ctx.window.setFrame(resolvedInitialFrame, display: false)
        }

        ctx.show(center: resolvedCenterOnShow)
        return ctx
    }

    private static func autoPlacedFrameForNewWindow(referenceWindow: NSWindow) -> CGRect? {
        let refFrame = referenceWindow.frame
        guard let screen = referenceWindow.screen ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame

        if isWindowEffectivelyMaximized(referenceWindow) {
            return refFrame
        }

        let delta: CGFloat = 24

        // 新窗口默认继承参考窗口的大小（比“总是默认 size”更符合直觉）。
        var size = refFrame.size
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height)

        func clamp(_ origin: CGPoint) -> CGPoint {
            let maxX = visible.maxX - size.width
            let maxY = visible.maxY - size.height

            var x = origin.x
            var y = origin.y

            if maxX < visible.minX {
                x = visible.minX
            } else {
                x = min(max(x, visible.minX), maxX)
            }

            if maxY < visible.minY {
                y = visible.minY
            } else {
                y = min(max(y, visible.minY), maxY)
            }

            return CGPoint(x: x, y: y)
        }

        func approxEqual(_ a: CGFloat, _ b: CGFloat) -> Bool {
            abs(a - b) <= 0.5
        }

        var origin = clamp(CGPoint(x: refFrame.origin.x + delta, y: refFrame.origin.y - delta))
        var out = CGRect(origin: origin, size: size)

        // 尽量避免“偏移后又被 clamp 回原地”导致仍然重叠。
        if approxEqual(out.origin.x, refFrame.origin.x), approxEqual(out.origin.y, refFrame.origin.y) {
            origin = clamp(CGPoint(x: refFrame.origin.x - delta, y: refFrame.origin.y + delta))
            out = CGRect(origin: origin, size: size)
        }
        if approxEqual(out.origin.x, refFrame.origin.x), approxEqual(out.origin.y, refFrame.origin.y) {
            origin = clamp(CGPoint(x: refFrame.origin.x + 1, y: refFrame.origin.y - 1))
            out = CGRect(origin: origin, size: size)
        }

        return out
    }

    private static func isWindowEffectivelyMaximized(_ window: NSWindow) -> Bool {
        if window.styleMask.contains(.fullScreen) {
            return true
        }
        if window.isZoomed {
            return true
        }
        guard let screen = window.screen else { return false }

        let f = window.frame
        let v = screen.visibleFrame
        let eps: CGFloat = 2.0

        return abs(f.origin.x - v.origin.x) <= eps
            && abs(f.origin.y - v.origin.y) <= eps
            && abs(f.size.width - v.size.width) <= eps
            && abs(f.size.height - v.size.height) <= eps
    }

    private func activeWindow() -> AttoWindowContext? {
        if let id = activeWindowID, let ctx = windows.first(where: { $0.id == id }) {
            return ctx
        }
        return windows.first
    }

    private func findWindow(containingFile url: URL) -> AttoWindowContext? {
        windows.first { $0.editorAreaController.containsFile(url: url) }
    }

    private func focusWindow(_ ctx: AttoWindowContext) {
        activeWindowID = ctx.id
        ctx.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - IPC open handling

    func handleOpenRequest(_ req: AttoIpcOpenRequest) -> AttoIpcOpenResult {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        // 仅激活：用于 `atto`（无参数）或将现有实例置前。
        if req.directories.isEmpty, req.files.isEmpty {
            if windows.isEmpty {
                _ = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
            }
            if let win = activeWindow() {
                focusWindow(win)
            }
            return .empty
        }

        var errors: [String] = []
        var pendingTokens: [AttoIpcWaitToken] = []

        // 目录：总是新窗口（支持多个目录 => 多个窗口）。并记录这次请求创建的“first window”。
        var dirWindows: [AttoWindowContext] = []
        for dirPath in req.directories {
            let url = URL(fileURLWithPath: dirPath).standardizedFileURL
            let ctx = createWindow(workspaceRootURL: url, contentSize: contentSize)
            dirWindows.append(ctx)
        }
        let firstDirWindow: AttoWindowContext? = dirWindows.first

        func locFrom(_ f: AttoIpcFileRequest) -> AttoCommandLine.FileLocation? {
            guard let line1 = f.line1 else { return nil }
            return .init(line1: max(1, line1), column1: f.column1)
        }

        func openFileInWindow(_ url: URL, loc: AttoCommandLine.FileLocation?, window: AttoWindowContext) {
            focusWindow(window)
            window.rememberRecentFile(url)
            let ok = window.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
            if ok {
                pendingTokens.append(.init(windowID: window.id, fileURL: url))
                window.fileExplorerController.revealFile(url)
            } else {
                errors.append("failed to open file: \(url.path)")
            }
        }

        func openFileInNewWindow(_ url: URL, loc: AttoCommandLine.FileLocation?) {
            let root = url.deletingLastPathComponent()
            let ctx = createWindow(workspaceRootURL: root, contentSize: contentSize)
            openFileInWindow(url, loc: loc, window: ctx)
        }

        // 仅目录：打开完窗口后，把第一个目录窗口置前。
        if req.files.isEmpty, let firstDirWindow {
            focusWindow(firstDirWindow)
            return .init(pendingTokens: [], errors: [])
        }

        // `-n/--new-window`：文件总是新窗口打开（每个 file arg 一次）。
        if req.newWindow {
            for f in req.files {
                let url = URL(fileURLWithPath: f.path).standardizedFileURL
                openFileInNewWindow(url, loc: locFrom(f))
            }
            return .init(pendingTokens: pendingTokens, errors: errors)
        }

        // Special-case：同时指定了目录和文件。
        //
        // 规则：
        // - 目录：每个目录一个新窗口（已在上面创建）
        // - 文件：如果“first window”里已经打开该文件，则复用 first window；否则每个文件新窗口
        if req.directories.isEmpty == false, req.files.isEmpty == false {
            for f in req.files {
                let url = URL(fileURLWithPath: f.path).standardizedFileURL
                let loc = locFrom(f)
                if let firstDirWindow, firstDirWindow.editorAreaController.containsFile(url: url) {
                    openFileInWindow(url, loc: loc, window: firstDirWindow)
                } else {
                    openFileInNewWindow(url, loc: loc)
                }
            }
            return .init(pendingTokens: pendingTokens, errors: errors)
        }

        // 常规：只有文件参数（或只有目录参数已被上面提前 return）。
        // 文件：若已在某个窗口打开，则复用该窗口；否则新开窗口。
        for f in req.files {
            let url = URL(fileURLWithPath: f.path).standardizedFileURL
            let loc = locFrom(f)
            if let existing = findWindow(containingFile: url) {
                openFileInWindow(url, loc: loc, window: existing)
            } else {
                openFileInNewWindow(url, loc: loc)
            }
        }

        return .init(pendingTokens: pendingTokens, errors: errors)
    }

    // MARK: - Wait notifications (IPC)

    private func handleWindowWillCloseForWait(_ ctx: AttoWindowContext) {
        let windowID = ctx.id
        for url in ctx.editorAreaController.openFileURLs() {
            ipcServer?.notifyFileInstanceClosed(windowID: windowID, url: url)
        }
    }
}
