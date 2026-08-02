import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoEditorAreaViewController: NSViewController {
    struct OpenFileItem: Hashable {
        let id: UUID
        let url: URL
        let title: String
        let isDirty: Bool
        let isPreview: Bool
    }

    enum OpenMode {
        case preview
        case pinned
    }

    private let library: EditorCoreUIFFILibrary
    private var theme: EditorCoreSkiaTheme
    private var workspaceRootURL: URL
    private let preferences: AttoPreferences
    private static let maxLspResultHistoryEntries = 20
    private static let maxLspResultEventHistoryEntries = 80

    private var tabs: [AttoEditorTab] = []
    private var selectedTabID: UUID?
    private let coreDocuments: MultiDocumentEditorUI?

    private let tabBarView = AttoTabBarView()
    private let findReplaceBarView = AttoFindReplaceBarView()
    private var findReplaceBarHeightConstraint: NSLayoutConstraint?
    private let contentHostView = NSView(frame: .zero)
    private let statusBarView = AttoStatusBarView()
    private let derivedStateStore = AttoDerivedStateStore()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a file to start editing")
    private var lastPresentedLspFailureDetail: String?
    private var transientStatusText: String?

    private var activeViewportObserver: EditorCoreSkiaView.ViewportStateObserverToken?

    private var didAttemptLoadTreeSitterRegistry: Bool = false
    private var treeSitterRegistryJSON: String?
    private var treeSitterLanguageIDs: [String] = []
    private var treeSitterExtensionMap: [String: String] = [:]

    var onDidCloseFile: ((URL) -> Void)?
    /// (url, createdOnDisk)
    var onDidSaveFile: ((URL, Bool) -> Void)?
    var onOpenFilesChanged: (([OpenFileItem], UUID?) -> Void)?
    var onSessionStateChanged: (() -> Void)?

    private var isRestoringSession: Bool = false

    var hasActiveEditorForCommands: Bool {
        activeTab != nil
    }

    var hasMultiplePanesForCommands: Bool {
        (activeTab?.panes.count ?? 0) > 1
    }

    var hasMultipleTabsForCommands: Bool {
        tabs.count > 1
    }

    func keymapContextForActiveState() -> AttoKeymapContext {
        var values: [String: AttoKeymapContextValue] = [
            "has_active_editor": .bool(activeTab != nil),
            "has_multiple_tabs": .bool(hasMultipleTabsForCommands),
            "has_multiple_panes": .bool(hasMultiplePanesForCommands),
        ]

        guard let tab = activeTab else {
            return AttoKeymapContext(values: values)
        }

        let language = AttoLanguageConfiguration.languageKey(
            fileURL: tab.fileURL,
            syntaxLanguageId: tab.syntaxLanguageId
        )
        if language.isEmpty == false {
            values["syntax"] = .string(language)
            values["selector"] = .string(Self.keymapSelector(forLanguage: language))
        }
        values["file_name"] = .string(tab.fileURL.lastPathComponent)
        values["file_extension"] = .string(tab.fileURL.pathExtension.lowercased())
        values["is_dirty"] = .bool(refreshTabDirtyState(tab))

        do {
            let selections = try tab.editCore.editor.selections()
            let selectionEmptyValues = selections.ranges.map { range in
                AttoKeymapContextValue.bool(range.start == range.end)
            }
            if selectionEmptyValues.count == 1, let only = selectionEmptyValues.first {
                values["selection_empty"] = only
            } else {
                values["selection_empty"] = .list(selectionEmptyValues)
            }
            values["num_selections"] = .number(Double(selections.ranges.count))
            values["has_multiple_selections"] = .bool(selections.ranges.count > 1)
        } catch {
            values["selection_empty"] = .bool(true)
            values["num_selections"] = .number(1)
            values["has_multiple_selections"] = .bool(false)
        }

        return AttoKeymapContext(values: values)
    }

    private static func keymapSelector(forLanguage language: String) -> String {
        switch language {
        case "markdown":
            return "text.html.markdown"
        case "text", "txt", "plain", "plaintext":
            return "text.plain"
        default:
            return "source.\(language)"
        }
    }

    func _activeDerivedStateForTesting() -> AttoDerivedStateSnapshot {
        derivedStateStore.active
    }

    func _transientStatusTextForTesting() -> String? {
        transientStatusText
    }

    func _updateStatusBarForTesting() {
        updateStatusBar()
    }

    func _lastLspLocationResultForTesting() -> LspLocationResultSnapshot? {
        lspLocationResultStore.current
    }

    func _lspLocationResultHistoryForTesting() -> [LspLocationResultSnapshot] {
        lspLocationResultStore.history
    }

    func _lspLocationResultLifecycleHistoryForTesting() -> [AttoLspResultLifecycleEntry<LspLocationResultSnapshot>] {
        lspLocationResultStore.historyEntries
    }

    func _lspLocationPanelSnapshotForTesting() -> LspLocationResultSnapshot? {
        lspLocationPanelController?.currentSnapshot
    }

    func _lspLocationPanelRowCountForTesting() -> Int {
        lspLocationPanelController?.rowCount ?? 0
    }

    func _lspLocationPanelIsVisibleForTesting() -> Bool {
        lspLocationPanelController?.isVisible == true
    }

    func _lastLspSymbolResultForTesting() -> LspSymbolResultSnapshot? {
        lspSymbolResultStore.current
    }

    func _lspSymbolPanelSnapshotForTesting() -> LspSymbolResultSnapshot? {
        lspSymbolPanelController?.currentSnapshot
    }

    func _lspSymbolPanelRowCountForTesting() -> Int {
        lspSymbolPanelController?.rowCount ?? 0
    }

    func _lspSymbolPanelIsVisibleForTesting() -> Bool {
        lspSymbolPanelController?.isVisible == true
    }

    func _lspSymbolResultHistoryForTesting() -> [LspSymbolResultSnapshot] {
        lspSymbolResultStore.history
    }

    func _lspSymbolResultLifecycleHistoryForTesting() -> [AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>] {
        lspSymbolResultStore.historyEntries
    }

    func _diagnosticsLifecycleHistoryForTesting() -> [AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>] {
        diagnosticsLifecycleStore.historyEntries
    }

    func _currentDiagnosticsLifecycleEntryForTesting() -> AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>? {
        diagnosticsLifecycleStore.currentEntry
    }

    func _diagnosticsLifecycleEventsForTesting(
        after sequence: UInt64
    ) -> [AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>] {
        diagnosticsLifecycleEvents(after: sequence)
    }

    func _latestDiagnosticsLifecycleSequenceForTesting() -> UInt64 {
        diagnosticsLifecycleStore.latestSequence
    }

    func _lspResultLifecycleEventsForTesting(after sequence: UInt64) -> [AttoLspResultLifecycleEvent] {
        lspResultEventStream.entries(after: sequence)
    }

    func _latestLspResultLifecycleEventSequenceForTesting() -> UInt64 {
        lspResultEventStream.latestSequence
    }

    func _showCodeActionResultJSONForTesting(_ json: String, onlyKinds: [String] = []) -> Bool {
        let items = AttoLspCodeActionParser.filteredItems(
            AttoLspCodeActionParser.items(fromCodeActionResultJSON: json),
            onlyKinds: onlyKinds
        )
        return showCodeActionResults(items, onlyKinds: onlyKinds)
    }

    func _showCompletionResultJSONForTesting(_ json: String) -> Bool {
        guard let tab = activeTab else { return false }
        guard let context = try? completionRequestContextForCurrentSelection(tab) else { return false }
        let items = AttoLspCompletionParser.items(fromCompletionResultJSON: json)
        return showCompletionList(items: items, context: context, editorView: tab.editCore.editorView)
    }

    func _problemsPanelDiagnosticsForTesting() -> [EcuDiagnostic] {
        problemsPanelController?.currentDiagnostics ?? []
    }

    func _problemsPanelUnifiedProblemsForTesting() -> [AttoUnifiedDiagnosticProblem] {
        problemsPanelController?.currentProblems ?? []
    }

    func _problemsPanelRowCountForTesting() -> Int {
        problemsPanelController?.rowCount ?? 0
    }

    func _problemsPanelIsVisibleForTesting() -> Bool {
        problemsPanelController?.isVisible == true
    }

    func _workspaceProblemsSnapshotForTesting() -> AttoWorkspaceProblemsSnapshot {
        workspaceProblemsStore.snapshot
    }

    func _workspaceProblemsPanelDiagnosticsForTesting() -> [AttoLspWorkspaceDiagnosticsParser.Diagnostic] {
        workspaceProblemsPanelController?.currentWorkspaceDiagnostics ?? []
    }

    func _workspaceProblemsPanelUnifiedProblemsForTesting() -> [AttoUnifiedDiagnosticProblem] {
        workspaceProblemsPanelController?.currentProblems ?? []
    }

    func _workspaceProblemsPanelRowCountForTesting() -> Int {
        workspaceProblemsPanelController?.rowCount ?? 0
    }

    func _workspaceProblemsPanelIsVisibleForTesting() -> Bool {
        workspaceProblemsPanelController?.isVisible == true
    }

    func _activeMinimapDiagnosticMarkersForTesting() -> [EditorCoreSkiaMinimapMarker] {
        activeTab?.editCore.minimapDiagnosticMarkers ?? []
    }

    func _activeGutterDiagnosticMarkersForTesting() -> [EditorCoreSkiaGutterDiagnosticMarker] {
        activeTab?.editCore.gutterDiagnosticMarkers ?? []
    }

    func _coreMultiDocumentSnapshotForTesting() throws -> EcuMultiDocumentSnapshot? {
        try coreDocuments?.snapshot()
    }

    func _coreMultiDocumentSearchForTesting(query: String) throws -> [EcuTabSearchResult]? {
        try coreDocuments?.searchAllTabs(query: query)
    }

    func _linkedEditingSessionIsActiveForTesting() -> Bool {
        linkedEditingSession != nil
    }

    func _setDocumentColorPickerForTesting(_ picker: ((NSColor) -> NSColor?)?) {
        documentColorPickerForTesting = picker
    }

    func _setActiveTabDirtyCacheForTesting(_ isDirty: Bool) {
        activeTab?.isDirty = isDirty
    }

    func _activeTabDirtyForDataLossDecisionForTesting() -> Bool {
        guard let tab = activeTab else { return false }
        return isTabDirtyForDataLossDecision(tab)
    }

    private struct HoverRequestContext {
        let tabID: UUID
        let info: EditorCoreSkiaHoverInfo
    }

    enum LspLocationRequestKind: Equatable {
        case definition
        case declaration
        case typeDefinition
        case implementation
        case references

        var resultPlaceholder: String {
            switch self {
            case .definition:
                return "Filter definitions..."
            case .declaration:
                return "Filter declarations..."
            case .typeDefinition:
                return "Filter type definitions..."
            case .implementation:
                return "Filter implementations..."
            case .references:
                return "Filter references..."
            }
        }

        var historyTitle: String {
            switch self {
            case .definition:
                return "Definitions"
            case .declaration:
                return "Declarations"
            case .typeDefinition:
                return "Type Definitions"
            case .implementation:
                return "Implementations"
            case .references:
                return "References"
            }
        }

        var lifecycleKind: String {
            switch self {
            case .definition:
                return "definition"
            case .declaration:
                return "declaration"
            case .typeDefinition:
                return "type_definition"
            case .implementation:
                return "implementation"
            case .references:
                return "references"
            }
        }
    }

    struct LspLocationResultSnapshot: Equatable {
        let kind: LspLocationRequestKind
        let items: [AttoLspDefinitionParser.LocationItem]
    }

    struct GoToLineTarget: Equatable {
        let line1: Int
        let column1: Int
    }

    enum CursorMovementCommand: String, CaseIterable {
        case moveLeft = "cursor.move_left"
        case moveRight = "cursor.move_right"
        case moveWordLeft = "cursor.move_word_left"
        case moveWordRight = "cursor.move_word_right"
        case moveUp = "cursor.move_up"
        case moveDown = "cursor.move_down"
        case pageUp = "cursor.page_up"
        case pageDown = "cursor.page_down"
        case lineStart = "cursor.line_start"
        case lineEnd = "cursor.line_end"
        case documentStart = "cursor.document_start"
        case documentEnd = "cursor.document_end"
        case selectLeft = "cursor.select_left"
        case selectRight = "cursor.select_right"
        case selectWordLeft = "cursor.select_word_left"
        case selectWordRight = "cursor.select_word_right"
        case selectUp = "cursor.select_up"
        case selectDown = "cursor.select_down"
        case selectPageUp = "cursor.select_page_up"
        case selectPageDown = "cursor.select_page_down"
        case selectLineStart = "cursor.select_line_start"
        case selectLineEnd = "cursor.select_line_end"
        case selectDocumentStart = "cursor.select_document_start"
        case selectDocumentEnd = "cursor.select_document_end"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .moveLeft: return "Cursor: Move Left"
            case .moveRight: return "Cursor: Move Right"
            case .moveWordLeft: return "Cursor: Move Word Left"
            case .moveWordRight: return "Cursor: Move Word Right"
            case .moveUp: return "Cursor: Move Up"
            case .moveDown: return "Cursor: Move Down"
            case .pageUp: return "Cursor: Page Up"
            case .pageDown: return "Cursor: Page Down"
            case .lineStart: return "Cursor: Move to Line Start"
            case .lineEnd: return "Cursor: Move to Line End"
            case .documentStart: return "Cursor: Move to Document Start"
            case .documentEnd: return "Cursor: Move to Document End"
            case .selectLeft: return "Cursor: Select Left"
            case .selectRight: return "Cursor: Select Right"
            case .selectWordLeft: return "Cursor: Select Word Left"
            case .selectWordRight: return "Cursor: Select Word Right"
            case .selectUp: return "Cursor: Select Up"
            case .selectDown: return "Cursor: Select Down"
            case .selectPageUp: return "Cursor: Select Page Up"
            case .selectPageDown: return "Cursor: Select Page Down"
            case .selectLineStart: return "Cursor: Select to Line Start"
            case .selectLineEnd: return "Cursor: Select to Line End"
            case .selectDocumentStart: return "Cursor: Select to Document Start"
            case .selectDocumentEnd: return "Cursor: Select to Document End"
            }
        }
    }

    private enum LspSymbolRequestKind {
        case document
        case workspace(query: String)

        var feedbackKind: AttoLspSymbolRequestFeedback.Kind {
            switch self {
            case .document: return .document
            case .workspace: return .workspace
            }
        }

        var query: String? {
            switch self {
            case .document: return nil
            case .workspace(let query): return query
            }
        }
    }

    struct LspSymbolResultSnapshot: Equatable {
        let title: String
        let symbols: [AttoLspSymbolParser.Symbol]
        let placeholder: String
    }

    private enum LspHierarchyRequestKind {
        case callIncoming
        case callOutgoing
        case typeSupertypes
        case typeSubtypes

        var isCallHierarchy: Bool {
            switch self {
            case .callIncoming, .callOutgoing:
                return true
            case .typeSupertypes, .typeSubtypes:
                return false
            }
        }

        var resultPlaceholder: String {
            switch self {
            case .callIncoming:
                return "Filter incoming calls..."
            case .callOutgoing:
                return "Filter outgoing calls..."
            case .typeSupertypes:
                return "Filter supertypes..."
            case .typeSubtypes:
                return "Filter subtypes..."
            }
        }
    }

    private struct DefinitionRequestContext {
        let tabID: UUID
        let logicalLine: UInt32
        let logicalColumn: UInt32
        let kind: LspLocationRequestKind
    }

    private struct SymbolRequestContext {
        let tabID: UUID
        let kind: LspSymbolRequestKind
    }

    private struct WorkspaceSymbolSearchContext {
        let tabID: UUID
        let requestID: Int
        let query: String
    }

    private struct HierarchyPrepareContext {
        let tabID: UUID
        let kind: LspHierarchyRequestKind
    }

    private struct HierarchyChildrenContext {
        let tabID: UUID
        let kind: LspHierarchyRequestKind
    }

    private struct SignatureHelpRequestContext {
        let tabID: UUID
        let showEmptyResults: Bool
    }

    private struct CompletionRequestContext {
        let tabID: UUID
        let fallbackStart: UInt32
        let fallbackEnd: UInt32
        let beepOnFailure: Bool
    }

    private struct CompletionResolveContext {
        let request: CompletionRequestContext
        let item: AttoLspCompletionParser.Item
        let commitCharacter: String?
    }

    private struct RenameRequestContext {
        let tabID: UUID
        let documentURI: String
    }

    private struct RenamePrepareContext {
        let tabID: UUID
        let fallbackSeed: AttoLspRenameSupport.DialogSeed
    }

    private struct CodeActionRequestContext {
        let tabID: UUID
        let onlyKinds: [String]
    }

    private struct CodeActionResolveContext {
        let tabID: UUID
        let item: AttoLspCodeActionParser.Item
    }

    private struct CodeLensResolveContext {
        let tabID: UUID
        let item: AttoLspCodeLensParser.Item
    }

    private struct CodeLensRefreshContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    private struct ExecuteCommandRequestContext {
        let tabID: UUID
        let commandTitle: String
    }

    private struct FoldingRangesRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    private struct SelectionRangeRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    private struct LinkedEditingRequestContext {
        let tabID: UUID
        let caretOffset: UInt32
        let showFeedback: Bool
    }

    private struct LinkedEditingSession {
        let tabID: UUID
        let selectionCount: Int
    }

    private enum DocumentColorResultMode {
        case presentations
        case picker
    }

    private struct DocumentColorRequestContext {
        let tabID: UUID
        let showFeedback: Bool
        let mode: DocumentColorResultMode
    }

    private struct ColorPresentationRequestContext {
        let tabID: UUID
        let item: AttoLspDocumentColorParser.Item
        let showFeedback: Bool
    }

    private struct DocumentColorPanelContext {
        let tabID: UUID
        let item: AttoLspDocumentColorParser.Item
    }

    private struct WorkspaceDiagnosticsRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    private struct DiagnosticsTextFingerprint: Equatable {
        let count: Int
        let hashValue: Int

        init(_ text: String) {
            self.count = text.count
            self.hashValue = text.hashValue
        }
    }

    private var hoverContext: HoverRequestContext?
    private var hoverDebounceWorkItem: DispatchWorkItem?
    private var hoverPollTimer: DispatchSourceTimer?
    private var hoverPopover: NSPopover?
    private var hoverPopoverLabel: NSTextField?
    private var workspaceEditPopover: NSPopover?
    private var workspaceEditPopoverLabel: NSTextField?

    private var definitionContext: DefinitionRequestContext?
    private var definitionPollTimer: DispatchSourceTimer?
    private var lspLocationResultsController: AttoCommandPaletteController?
    private var lspLocationPanelController: AttoLspLocationPanelController?
    private let lspLocationResultStore = AttoLspResultLifecycleStore<LspLocationResultSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )

    private var symbolContext: SymbolRequestContext?
    private var symbolPollTimer: DispatchSourceTimer?
    private var lspSymbolResultsController: AttoCommandPaletteController?
    private var lspSymbolPanelController: AttoLspSymbolPanelController?
    private let lspSymbolResultStore = AttoLspResultLifecycleStore<LspSymbolResultSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )
    private var workspaceSymbolSearchContext: WorkspaceSymbolSearchContext?
    private var workspaceSymbolSearchDebounceTimer: DispatchSourceTimer?
    private var workspaceSymbolSearchPollTimer: DispatchSourceTimer?
    private var workspaceSymbolSearchRequestID: Int = 0
    private var workspaceSymbolSearchQuery: String = ""
    private var workspaceSymbolSearchResults: [AttoLspSymbolParser.Symbol] = []
    private var hierarchyPrepareContext: HierarchyPrepareContext?
    private var hierarchyPreparePollTimer: DispatchSourceTimer?
    private var hierarchyChildrenContext: HierarchyChildrenContext?
    private var hierarchyChildrenPollTimer: DispatchSourceTimer?
    private var hierarchyResultsController: AttoCommandPaletteController?
    private var problemsResultsController: AttoCommandPaletteController?
    private var problemsPanelController: AttoProblemsPanelController?
    private let diagnosticsLifecycleStore = AttoLspResultLifecycleStore<AttoDiagnosticsLifecycleSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )
    private let lspResultEventStream = AttoLspResultEventStream(
        maxHistoryEntries: maxLspResultEventHistoryEntries
    )
    private var activeDiagnosticsTextFingerprintsByTabID: [UUID: DiagnosticsTextFingerprint] = [:]
    private var activeDiagnosticsBaselinesByTabID: [UUID: [EcuDiagnostic]] = [:]
    private var activeDiagnosticsStaleReasonsByTabID: [UUID: AttoDiagnosticsStaleReason] = [:]
    private let workspaceProblemsStore: AttoWorkspaceProblemsStore
    private var workspaceProblemsPanelController: AttoProblemsPanelController?
    private var workspaceDiagnosticsContext: WorkspaceDiagnosticsRequestContext?
    private var workspaceDiagnosticsPollTimer: DispatchSourceTimer?
    private var workspaceDiagnosticsResultsController: AttoCommandPaletteController?
    private var workspaceDiagnosticsStaleReason: AttoDiagnosticsStaleReason?
    private var documentColorResultsController: AttoCommandPaletteController?
    private var colorPresentationResultsController: AttoCommandPaletteController?

    private var signatureHelpContext: SignatureHelpRequestContext?
    private var signatureHelpPollTimer: DispatchSourceTimer?
    private var signatureHelpPopover: NSPopover?
    private var signatureHelpPopoverLabel: NSTextField?

    private var completionContext: CompletionRequestContext?
    private var completionPollTimer: DispatchSourceTimer?
    private var completionResolveContext: CompletionResolveContext?
    private var completionResolvePollTimer: DispatchSourceTimer?
    private var completionListController: AttoCompletionListController?
    private var completionListContext: CompletionRequestContext?
    private var shouldPreserveCompletionUIForCurrentTextMutation = false

    private var renameContext: RenameRequestContext?
    private var renamePollTimer: DispatchSourceTimer?
    private var renamePrepareContext: RenamePrepareContext?
    private var renamePreparePollTimer: DispatchSourceTimer?

    private var codeActionContext: CodeActionRequestContext?
    private var codeActionPollTimer: DispatchSourceTimer?
    private var codeActionResolveContext: CodeActionResolveContext?
    private var codeActionResolvePollTimer: DispatchSourceTimer?
    private var codeActionResultsController: AttoCommandPaletteController?
    private var codeLensResolveContext: CodeLensResolveContext?
    private var codeLensResolvePollTimer: DispatchSourceTimer?
    private var codeLensRefreshContext: CodeLensRefreshContext?
    private var codeLensRefreshPollTimer: DispatchSourceTimer?
    private var codeLensResultsController: AttoCommandPaletteController?
    private var executeCommandContext: ExecuteCommandRequestContext?
    private var executeCommandPollTimer: DispatchSourceTimer?

    private var foldingRangesContext: FoldingRangesRequestContext?
    private var foldingRangesPollTimer: DispatchSourceTimer?
    private var selectionRangeContext: SelectionRangeRequestContext?
    private var selectionRangePollTimer: DispatchSourceTimer?
    private var linkedEditingContext: LinkedEditingRequestContext?
    private var linkedEditingPollTimer: DispatchSourceTimer?
    private var linkedEditingSession: LinkedEditingSession?
    private var documentColorContext: DocumentColorRequestContext?
    private var documentColorPollTimer: DispatchSourceTimer?
    private var colorPresentationContext: ColorPresentationRequestContext?
    private var colorPresentationPollTimer: DispatchSourceTimer?
    private var documentColorPanelContext: DocumentColorPanelContext?
    private var documentColorPickerForTesting: ((NSColor) -> NSColor?)?

    init(
        library: EditorCoreUIFFILibrary,
        theme: EditorCoreSkiaTheme,
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared
    ) {
        self.library = library
        self.theme = theme
        self.workspaceRootURL = workspaceRootURL
        self.preferences = preferences
        do {
            let coreDocuments = try MultiDocumentEditorUI(library: library)
            self.coreDocuments = coreDocuments
            self.workspaceProblemsStore = AttoWorkspaceProblemsStore(coreDocuments: coreDocuments)
        } catch {
            self.coreDocuments = nil
            self.workspaceProblemsStore = AttoWorkspaceProblemsStore()
            NSLog("AttoEditor: failed to initialize core multi-document model: %@", String(describing: error))
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        view.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorArea)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(ecuRgba8: theme.editorBackground).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tabBarView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        tabBarView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id)
        }
        tabBarView.onDoubleClickTab = { [weak self] id in
            self?.pinTabIfPreview(id: id)
        }
        tabBarView.translatesAutoresizingMaskIntoConstraints = false

        findReplaceBarView.translatesAutoresizingMaskIntoConstraints = false
        findReplaceBarView.isHidden = true
        findReplaceBarView.searchField.delegate = self
        findReplaceBarView.searchField.target = self
        findReplaceBarView.searchField.action = #selector(findNextClicked(_:))
        findReplaceBarView.replaceField.delegate = self

        for b in [findReplaceBarView.caseSensitiveButton, findReplaceBarView.wholeWordButton, findReplaceBarView.regexButton] {
            b.target = self
            b.action = #selector(findOptionsChanged(_:))
        }
        findReplaceBarView.findPrevButton.target = self
        findReplaceBarView.findPrevButton.action = #selector(findPrevClicked(_:))
        findReplaceBarView.findNextButton.target = self
        findReplaceBarView.findNextButton.action = #selector(findNextClicked(_:))
        findReplaceBarView.clearButton.target = self
        findReplaceBarView.clearButton.action = #selector(clearFindClicked(_:))
        findReplaceBarView.replaceCurrentButton.target = self
        findReplaceBarView.replaceCurrentButton.action = #selector(replaceCurrentClicked(_:))
        findReplaceBarView.replaceAllButton.target = self
        findReplaceBarView.replaceAllButton.action = #selector(replaceAllClicked(_:))
        findReplaceBarView.closeButton.target = self
        findReplaceBarView.closeButton.action = #selector(closeFindBarClicked(_:))

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorContentHost)
        contentHostView.wantsLayer = true
        contentHostView.layer?.backgroundColor = NSColor(ecuRgba8: theme.editorBackground).cgColor

        emptyStateLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyStateLabel.textColor = NSColor(attoHex: 0x8A8A8A)
        emptyStateLabel.alignment = .center
        emptyStateLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorEmptyState)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.onSelectLanguage = { [weak self] languageId in
            self?.setSyntaxLanguageForActiveTab(languageId: languageId)
        }
        refreshStatusBarLanguageOptions()

        view.addSubview(tabBarView)
        view.addSubview(findReplaceBarView)
        view.addSubview(contentHostView)
        view.addSubview(statusBarView)

        findReplaceBarHeightConstraint = findReplaceBarView.heightAnchor.constraint(equalToConstant: 0)
        findReplaceBarHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 30),

            findReplaceBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            findReplaceBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            findReplaceBarView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),

            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 20),

            contentHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHostView.topAnchor.constraint(equalTo: findReplaceBarView.bottomAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
        ])

        showEmptyState()
        refreshTabBar()
        updateStatusBar()
    }

    private func loadTreeSitterRegistryCacheIfNeeded() {
        guard didAttemptLoadTreeSitterRegistry == false else { return }
        didAttemptLoadTreeSitterRegistry = true

        do {
            let paths = try AttoTreeSitterRegistry.defaultPaths()
            let registryJSON = try AttoTreeSitterRegistry.buildRegistryJSON(treesitterRoot: paths.treesitterRoot)
            treeSitterRegistryJSON = registryJSON

            guard let data = registryJSON.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            else {
                return
            }

            if let extMap = obj["extension_map"] as? [String: String] {
                treeSitterExtensionMap = extMap
            }

            if let languages = obj["languages"] as? [String: Any] {
                treeSitterLanguageIDs = languages.keys.sorted { a, b in
                    a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
            }
        } catch {
            NSLog("AttoEditor: failed to load Tree-sitter registry: %@", String(describing: error))
        }
    }

    private func refreshStatusBarLanguageOptions() {
        loadTreeSitterRegistryCacheIfNeeded()
        var opts: [AttoStatusBarView.LanguageOption] = [
            .init(id: nil, title: "Plain Tex"),
        ]
        for id in treeSitterLanguageIDs {
            opts.append(.init(id: id, title: id))
        }
        statusBarView.setLanguageOptions(opts)
    }

    private func inferredTreeSitterLanguageId(for url: URL) -> String? {
        loadTreeSitterRegistryCacheIfNeeded()
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ext.isEmpty == false else { return nil }
        return treeSitterExtensionMap[ext]
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
    }

    // MARK: - Preferences (editor rendering)

    func applyEditorPreferences() {
        let fontFamiliesCSV = preferences.fontFamiliesCSVForApplying()
        let ligaturesEnabled = preferences.effectiveLigaturesEnabled
        let autoPairsEnabled = preferences.effectiveAutoPairsEnabled
        let wrapMode = preferences.effectiveWrapMode
        let wrapIndent = preferences.effectiveWrapIndent
        let fontSizePoints = preferences.effectiveFontSizePoints

        for tab in tabs {
            for editCore in tab.panes {
                // Font families: empty CSV means "reset to default" (Skia renderer falls back).
                do {
                    try editCore.editor.setFontFamiliesCSV(fontFamiliesCSV)
                } catch {
                    NSLog("AttoEditor: setFontFamiliesCSV failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setFontLigaturesEnabled(ligaturesEnabled)
                } catch {
                    NSLog("AttoEditor: setFontLigaturesEnabled failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setAutoPairsEnabled(autoPairsEnabled)
                } catch {
                    NSLog("AttoEditor: setAutoPairsEnabled failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapMode(wrapMode)
                } catch {
                    NSLog("AttoEditor: setWrapMode failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapIndent(wrapIndent)
                } catch {
                    NSLog("AttoEditor: setWrapIndent failed: %@", String(describing: error))
                }

                editCore.editorView.fontSizePoints = CGFloat(fontSizePoints)
                editCore.editorView.needsDisplay = true
            }
        }
    }

    func applyTheme(_ theme: EditorCoreSkiaTheme) {
        self.theme = theme

        if isViewLoaded {
            let bg = NSColor(ecuRgba8: theme.editorBackground).cgColor
            view.layer?.backgroundColor = bg
            contentHostView.layer?.backgroundColor = bg
        }

        for tab in tabs {
            for editCore in tab.panes {
                do {
                    try editCore.applyTheme(theme)
                } catch {
                    NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
                }
            }
        }
    }

    // MARK: - Tabs

    func makeSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?) {
        let selectedIndex: Int? = {
            guard let selectedTabID else { return nil }
            return tabs.firstIndex(where: { $0.id == selectedTabID })
        }()

        let tabSnaps: [AttoTabSnapshot] = tabs.map { tab in
            AttoTabSnapshot(
                filePath: tab.fileURL.standardizedFileURL.path,
                isPreview: tab.isPreview,
                showsMinimap: tab.editCore.showsMinimap,
                paneCount: tab.panes.count,
                activePaneIndex: max(0, min(tab.activePaneIndex, tab.panes.count - 1))
            )
        }

        return (tabs: tabSnaps, selectedTabIndex: selectedIndex)
    }

    func restoreSession(tabs tabSnapshots: [AttoTabSnapshot], selectedTabIndex: Int?) {
        isRestoringSession = true
        defer { isRestoringSession = false }

        cancelHoverUI()
        cancelRenameUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        closeAllCoreDocumentTabs()
        tabs = []
        selectedTabID = nil

        var didUsePreview = false
        var newTabs: [AttoEditorTab] = []
        newTabs.reserveCapacity(tabSnapshots.count)

        for snap in tabSnapshots {
            let url = URL(fileURLWithPath: snap.filePath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let wantsPreview = snap.isPreview && (didUsePreview == false)
            if wantsPreview { didUsePreview = true }

            do {
                let tab = try makeTab(
                    for: url,
                    isPreview: wantsPreview,
                    showsMinimap: snap.showsMinimap ?? true
                )

                let paneCount = max(1, min(snap.paneCount ?? 1, 8))
                if paneCount > 1 {
                    for _ in 1..<paneCount {
                        _ = try appendSplitPane(to: tab)
                    }
                    tab.activePaneIndex = max(0, min(snap.activePaneIndex ?? 0, tab.panes.count - 1))
                    setCoreActiveView(tab)
                }

                newTabs.append(tab)
            } catch {
                NSLog("AttoEditor: session restore failed to open file %@: %@", url.path, String(describing: error))
            }
        }

        tabs = newTabs

        if newTabs.isEmpty {
            showEmptyState()
            refreshTabBar()
            updateStatusBar()
            updateWindowTitle()
            onOpenFilesChanged?(openFileItems(), selectedTabID)
            return
        }

        let idx = selectedTabIndex ?? 0
        let safeIdx = (0..<newTabs.count).contains(idx) ? idx : 0
        selectTab(id: newTabs[safeIdx].id)
    }

    private func notifySessionStateChanged() {
        guard isRestoringSession == false else { return }
        onSessionStateChanged?()
    }

    private func openCoreDocumentTab(for url: URL, initialText: String, isPreview: Bool) -> UInt64? {
        guard let coreDocuments else { return nil }
        do {
            let tabID: UInt64
            if isPreview {
                tabID = try coreDocuments.openPreviewTab(text: initialText, viewportWidthCells: 120)
            } else {
                tabID = try coreDocuments.openTab(text: initialText, viewportWidthCells: 120)
            }
            try coreDocuments.setTabTitle(url.lastPathComponent, tabId: tabID)
            return tabID
        } catch {
            NSLog("AttoEditor: core multi-document open failed for %@: %@", url.path, String(describing: error))
            return nil
        }
    }

    private func closeAllCoreDocumentTabs() {
        guard let coreDocuments else { return }
        do {
            try coreDocuments.closeAllTabs()
        } catch {
            NSLog("AttoEditor: core multi-document closeAllTabs failed: %@", String(describing: error))
        }
    }

    private func setCoreActiveTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setActiveTab(coreTabID)
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document setActive failed: %@", String(describing: error))
        }
    }

    private func updateCoreTabTitle(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setTabTitle(tab.fileURL.lastPathComponent, tabId: coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document setTabTitle failed: %@", String(describing: error))
        }
    }

    private func syncCoreTabText(_ tab: AttoEditorTab, markSaved: Bool) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            let text = try tab.editCore.editor.text()
            try coreDocuments.replaceTabText(tabId: coreTabID, text: text, markSaved: markSaved)
        } catch {
            NSLog("AttoEditor: core multi-document text sync failed: %@", String(describing: error))
        }
    }

    private func coreTabDirtyState(_ tab: AttoEditorTab) -> Bool? {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return nil }
        do {
            return try coreDocuments.isTabModified(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document dirty query failed: %@", String(describing: error))
            return nil
        }
    }

    private func localTabDirtyState(_ tab: AttoEditorTab) -> Bool {
        (try? tab.editCore.editor.isModified()) ?? tab.isDirty
    }

    @discardableResult
    private func refreshTabDirtyState(_ tab: AttoEditorTab) -> Bool {
        let localDirty = localTabDirtyState(tab)
        guard let coreDirty = coreTabDirtyState(tab) else {
            tab.isDirty = localDirty
            return localDirty
        }

        let isDirty = coreDirty || localDirty
        tab.isDirty = isDirty
        return isDirty
    }

    private func refreshAllTabDirtyStates() {
        for tab in tabs {
            refreshTabDirtyState(tab)
        }
    }

    private func isTabDirtyForDataLossDecision(_ tab: AttoEditorTab) -> Bool {
        refreshTabDirtyState(tab)
    }

    private func pinCoreTabIfPreview(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.pinTab(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document pinTab failed: %@", String(describing: error))
        }
    }

    private func closeCoreTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.closeTab(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document closeTab failed: %@", String(describing: error))
        }
    }

    private func splitCoreTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.splitTab(coreTabID, viewportWidthCells: 120)
        } catch {
            NSLog("AttoEditor: core multi-document splitTab failed: %@", String(describing: error))
        }
    }

    private func closeCoreView(tab: AttoEditorTab, viewIndex: Int) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.closeView(tabId: coreTabID, viewIndex: UInt32(clamping: viewIndex))
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document closeView failed: %@", String(describing: error))
        }
    }

    private func moveCoreView(tab: AttoEditorTab, fromIndex: Int, toIndex: Int) -> Bool {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return false }
        do {
            return try coreDocuments.moveView(
                tabId: coreTabID,
                fromIndex: UInt32(clamping: fromIndex),
                toIndex: UInt32(clamping: toIndex)
            )
        } catch {
            NSLog("AttoEditor: core multi-document moveView failed: %@", String(describing: error))
            return false
        }
    }

    private func moveCoreTab(fromIndex: Int, toIndex: Int) -> Bool {
        guard let coreDocuments else { return false }
        do {
            return try coreDocuments.moveTab(
                fromIndex: UInt32(clamping: fromIndex),
                toIndex: UInt32(clamping: toIndex)
            )
        } catch {
            NSLog("AttoEditor: core multi-document moveTab failed: %@", String(describing: error))
            return false
        }
    }

    private func setCoreActiveView(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document setActiveViewIndex failed: %@", String(describing: error))
        }
    }

    func openFile(url: URL) {
        openFile(url: url, mode: .pinned)
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, isUntitled: Bool = false) -> Bool {
        if let existing = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            if mode == .pinned, existing.isPreview {
                existing.isPreview = false
                pinCoreTabIfPreview(existing)
            }
            selectTab(id: existing.id)
            refreshTabBar()
            updateWindowTitle()
            notifySessionStateChanged()
            return true
        }

        do {
            switch mode {
            case .preview:
                if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
                    // Safety: never discard dirty state; pin the preview tab if it got edited.
                    if isTabDirtyForDataLossDecision(tabs[previewIdx]) {
                        tabs[previewIdx].isPreview = false
                        pinCoreTabIfPreview(tabs[previewIdx])
                    } else {
                        let oldURL = tabs[previewIdx].fileURL
                        let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                        tabs[previewIdx] = tab
                        selectTab(id: tab.id)
                        onDidCloseFile?(oldURL)
                        notifySessionStateChanged()
                        return true
                    }
                }

                let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()

            case .pinned:
                let tab = try makeTab(for: url, isPreview: false, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()
            }
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to open file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, location: AttoCommandLine.FileLocation?) -> Bool {
        let ok = openFile(url: url, mode: mode)
        guard ok else { return false }
        guard let location else { return true }
        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else { return true }
        navigate(tab: tab, to: location)
        return true
    }

    func containsFile(url: URL) -> Bool {
        tabs.contains { $0.fileURL.standardizedFileURL == url.standardizedFileURL }
    }

    func openFileURLs() -> [URL] {
        tabs.map(\.fileURL)
    }

    func openFileItems() -> [OpenFileItem] {
        tabs.map { tab in
            let isDirty = refreshTabDirtyState(tab)
            return OpenFileItem(
                id: tab.id,
                url: tab.fileURL,
                title: tab.displayTitle,
                isDirty: isDirty,
                isPreview: tab.isPreview
            )
        }
    }

    func findInOpenTabs(query: String) -> [AttoFindInFilesViewController.SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false, let coreDocuments else { return [] }

        do {
            let coreResults = try coreDocuments.searchAllTabs(
                query: q,
                options: EcuSearchOptions(caseSensitive: false)
            )

            var out: [AttoFindInFilesViewController.SearchResult] = []
            out.reserveCapacity(coreResults.reduce(0) { $0 + $1.matches.count })

            let maxResults = 2000
            for result in coreResults {
                guard out.count < maxResults else { break }
                guard let tab = tabs.first(where: { $0.coreTabID == result.tabId }) else { continue }
                let text = (try? tab.editCore.editor.text()) ?? ""

                for match in result.matches {
                    guard out.count < maxResults else { break }
                    let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: match.start)
                    out.append(
                        AttoFindInFilesViewController.SearchResult(
                            url: tab.fileURL.standardizedFileURL,
                            line1: Int(position.line) + 1,
                            column1: Int(position.column) + 1,
                            lineText: Self.findResultLinePreview(in: text, zeroBasedLine: Int(position.line))
                        )
                    )
                }
            }

            out.sort { a, b in
                if a.url.path != b.url.path { return a.url.path < b.url.path }
                if a.line1 != b.line1 { return a.line1 < b.line1 }
                return a.column1 < b.column1
            }
            return out
        } catch {
            NSLog("AttoEditor: core multi-document open-tab search failed: %@", String(describing: error))
            return []
        }
    }

    private static func findResultLinePreview(in text: String, zeroBasedLine: Int) -> String {
        guard zeroBasedLine >= 0 else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard zeroBasedLine < lines.count else { return "" }
        let line = String(lines[zeroBasedLine]).trimmingCharacters(in: .whitespaces)
        return line.count > 240 ? String(line.prefix(240)) + "…" : line
    }

    func selectFile(url: URL) {
        guard let tab = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) else { return }
        selectTab(id: tab.id)
    }

    func closeActiveTab() {
        guard let selectedTabID else { return }
        closeTab(id: selectedTabID)
    }

    func saveActiveTab() {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }
        _ = saveTabWithSavePanelIfNeeded(tab)
    }

    func confirmClosingDirtyTabsIfNeeded() -> Bool {
        let dirtyTabs = tabs.filter { isTabDirtyForDataLossDecision($0) }
        guard dirtyTabs.isEmpty == false else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save your changes before closing?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAllDirtyTabs()
        case .alertSecondButtonReturn:
            return false
        default:
            return true
        }
    }

    private enum DirtyCloseDecision {
        case save
        case dontSave
        case cancel
    }

    private func confirmCloseDirtyTab(_ tab: AttoEditorTab) -> DirtyCloseDecision {
        let name = tab.fileURL.lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \"\(name)\" before closing?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .cancel
        default:
            return .dontSave
        }
    }

    @discardableResult
    private func saveTab(_ tab: AttoEditorTab) -> Bool {
        let fm = FileManager.default
        let existedOnDiskBeforeSave = fm.fileExists(atPath: tab.fileURL.path)
        do {
            let text = try tab.editCore.editor.text()
            try text.write(to: tab.fileURL, atomically: true, encoding: .utf8)
            try tab.editCore.editor.markSaved()
            tab.isUntitled = false
            tab.isDirty = false
            tab.isPreview = false
            syncCoreTabText(tab, markSaved: true)
            pinCoreTabIfPreview(tab)
            updateCoreTabTitle(tab)
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
            notifySessionStateChanged()
            onDidSaveFile?(tab.fileURL, existedOnDiskBeforeSave == false)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save file %@: %@", tab.fileURL.path, String(describing: error))
            return false
        }
    }

    private func saveAllDirtyTabs() -> Bool {
        for tab in tabs {
            if isTabDirtyForDataLossDecision(tab) {
                if saveTabWithSavePanelIfNeeded(tab) == false {
                    return false
                }
            }
        }
        return true
    }

    private func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        if isTabDirtyForDataLossDecision(tab) {
            switch confirmCloseDirtyTab(tab) {
            case .cancel:
                return
            case .save:
                guard saveTabWithSavePanelIfNeeded(tab) else { return }
            case .dontSave:
                break
            }
        }

        let url = tab.fileURL
        let wasSelected = (selectedTabID == id)
        closeCoreTab(tab)
        clearDiagnosticsLifecycleState(forTabID: tab.id)
        tabs.remove(at: idx)
        onDidCloseFile?(url)
        notifySessionStateChanged()

        if wasSelected {
            if let next = tabs.indices.last {
                selectTab(id: tabs[next].id)
            } else {
                selectedTabID = nil
                showEmptyState()
                refreshTabBar()
                updateStatusBar()
            }
        } else {
            refreshTabBar()
        }
    }

    private func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        setCoreActiveTab(tab)

        updateAlwaysPollProcessingForSelectedTab()
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        showTabContent(tab)
        refreshTabBar()
        attachStatusObserver(to: tab.editCore.editorView)
        updateStatusBar()
        updateWindowTitle()
        tab.editCore.focusEditor()

        applyFindStateToActiveTab()
        notifySessionStateChanged()
    }

    private func refreshTabBar() {
        refreshAllTabDirtyStates()
        tabBarView.updateTabs(
            tabs: tabs.map { .init(id: $0.id, title: $0.displayTitle, toolTip: $0.fileURL.path, isPreview: $0.isPreview) },
            selectedID: selectedTabID
        )
        onOpenFilesChanged?(openFileItems(), selectedTabID)
    }

    private func pinTabIfPreview(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.isPreview else { return }
        tab.isPreview = false
        pinCoreTabIfPreview(tab)
        refreshTabBar()
        notifySessionStateChanged()
    }

    @discardableResult
    func moveActiveTabLeft() -> Bool {
        moveActiveTab(delta: -1)
    }

    @discardableResult
    func moveActiveTabRight() -> Bool {
        moveActiveTab(delta: 1)
    }

    @discardableResult
    private func moveActiveTab(delta: Int) -> Bool {
        guard let selectedTabID,
              let from = tabs.firstIndex(where: { $0.id == selectedTabID }),
              tabs.count > 1
        else {
            NSSound.beep()
            return false
        }

        let to = from + delta
        guard to >= 0, to < tabs.count else {
            NSSound.beep()
            return false
        }

        guard moveCoreTab(fromIndex: from, toIndex: to) else {
            NSSound.beep()
            return false
        }

        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        refreshTabBar()
        updateWindowTitle()
        notifySessionStateChanged()
        return true
    }

    // MARK: - Minimap

    func toggleMinimapForActiveTab() {
        guard let tab = activeTab else { return }
        let nextValue = tab.editCore.showsMinimap == false
        for editCore in tab.panes {
            editCore.showsMinimap = nextValue
            editCore.needsLayout = true
            editCore.needsDisplay = true
        }
        notifySessionStateChanged()
    }

    // MARK: - Split panes

    @discardableResult
    func splitActiveTabRight() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let pane = try appendSplitPane(to: tab)
            showTabContent(tab)
            attachStatusObserver(to: pane.editorView)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            pane.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: split active tab failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    private func appendSplitPane(to tab: AttoEditorTab) throws -> EditCoreUI {
        let editor = try tab.editCore.editor.cloneView(viewportWidthCells: 120)
        let pane = try EditCoreUI(
            editor: editor,
            fontFamiliesCSV: AttoPreferences.shared.fontFamiliesCSVForNewViews(),
            showsMinimap: tab.editCore.showsMinimap,
            minimapPlacement: .rightOfScrollbar
        )

        try configureEditorChrome(pane)
        applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        configureEditCoreHooks(pane, tabID: tab.id)

        tab.panes.append(pane)
        tab.activePaneIndex = tab.panes.count - 1
        splitCoreTab(tab)
        return pane
    }

    @discardableResult
    func focusNextPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: 1)
    }

    @discardableResult
    func focusPreviousPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: -1)
    }

    @discardableResult
    func closeActivePane() -> Bool {
        guard let tab = activeTab, tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let idx = max(0, min(tab.activePaneIndex, tab.panes.count - 1))
        let pane = tab.panes.remove(at: idx)
        pane.removeFromSuperview()
        tab.activePaneIndex = min(idx, tab.panes.count - 1)
        closeCoreView(tab: tab, viewIndex: idx)

        let activePane = tab.editCore
        showTabContent(tab)
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    @discardableResult
    func moveActivePaneLeft() -> Bool {
        moveActivePaneInActiveTab(delta: -1)
    }

    @discardableResult
    func moveActivePaneRight() -> Bool {
        moveActivePaneInActiveTab(delta: 1)
    }

    @discardableResult
    private func focusPaneInActiveTab(delta: Int) -> Bool {
        guard let tab = activeTab, tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let count = tab.panes.count
        let current = max(0, min(tab.activePaneIndex, count - 1))
        let next = (current + delta + count) % count
        tab.activePaneIndex = next
        setCoreActiveView(tab)

        let activePane = tab.editCore
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    @discardableResult
    private func moveActivePaneInActiveTab(delta: Int) -> Bool {
        guard let tab = activeTab, tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let count = tab.panes.count
        let from = max(0, min(tab.activePaneIndex, count - 1))
        let to = from + delta
        guard to >= 0, to < count else {
            NSSound.beep()
            return false
        }

        guard moveCoreView(tab: tab, fromIndex: from, toIndex: to) else {
            NSSound.beep()
            return false
        }

        let pane = tab.panes.remove(at: from)
        tab.panes.insert(pane, at: to)
        tab.activePaneIndex = to

        showTabContent(tab)
        attachStatusObserver(to: pane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        pane.focusEditor()
        return true
    }

    // MARK: - Editor commands

    @discardableResult
    func executeActiveEditorCommandJSON(_ commandJSON: String, treatsAsTextMutation: Bool? = nil) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let isTextMutation = treatsAsTextMutation ?? Self.commandJSONIsTextMutation(commandJSON)
        let mayChangeSelection = Self.commandJSONMayChangeSelection(commandJSON)

        do {
            _ = try tab.editCore.editor.executeCommandJSON(commandJSON)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true

            if isTextMutation {
                handleTabDidMutateDocumentText(tabID: tab.id)
            } else if mayChangeSelection {
                handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            }

            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applySnippetInActiveTab(_ snippet: String) -> Bool {
        guard snippet.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let selections = try tab.editCore.editor.selections()
            guard selections.ranges.isEmpty == false else {
                NSSound.beep()
                return false
            }

            let requestedPrimaryIndex = Int(selections.primaryIndex)
            let primaryIndex = min(requestedPrimaryIndex, selections.ranges.count - 1)
            let range = selections.ranges[primaryIndex]
            _ = try tab.editCore.editor.applySnippet(start: range.start, end: range.end, snippet: snippet)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func promptApplySnippetInActiveTab(initialSnippet: String = "") -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = initialSnippet
        field.placeholderString = "println!(${1:msg})$0"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Apply Snippet"
        alert.informativeText = "Enter an editor-core snippet string using $0 and ${1:name} placeholders."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return applySnippetInActiveTab(field.stringValue)
    }

    @discardableResult
    func addNextOccurrenceInActiveTab() -> Bool {
        addOccurrenceInActiveTab(selectAll: false)
    }

    @discardableResult
    func addAllOccurrencesInActiveTab() -> Bool {
        addOccurrenceInActiveTab(selectAll: true)
    }

    @discardableResult
    private func addOccurrenceInActiveTab(selectAll: Bool) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            if selectAll {
                try tab.editCore.editor.addAllOccurrences(options: currentSearchOptions())
            } else {
                try tab.editCore.editor.addNextOccurrence(options: currentSearchOptions())
            }
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func performCursorMovementCommand(_ command: CursorMovementCommand) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            tab.editCore.layoutSubtreeIfNeeded()
            try Self.applyCursorMovementCommand(command, editor: tab.editCore.editor)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            tab.editCore.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: cursor movement command failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func performCursorMovementCommand(id commandID: String) -> Bool {
        guard let command = CursorMovementCommand(rawValue: commandID) else {
            NSSound.beep()
            return false
        }
        return performCursorMovementCommand(command)
    }

    private static func applyCursorMovementCommand(_ command: CursorMovementCommand, editor: EditorUI) throws {
        switch command {
        case .moveLeft:
            if try collapseSelection(editor, to: .start) == false {
                try editor.moveGraphemeLeft()
            }
        case .moveRight:
            if try collapseSelection(editor, to: .end) == false {
                try editor.moveGraphemeRight()
            }
        case .moveWordLeft:
            _ = try collapseSelection(editor, to: .start)
            try editor.moveWordLeft()
        case .moveWordRight:
            _ = try collapseSelection(editor, to: .end)
            try editor.moveWordRight()
        case .moveUp:
            try editor.moveVisualByRows(-1)
        case .moveDown:
            try editor.moveVisualByRows(1)
        case .pageUp:
            try editor.moveVisualByPages(-1)
        case .pageDown:
            try editor.moveVisualByPages(1)
        case .lineStart:
            try editor.moveToVisualLineStart()
        case .lineEnd:
            try editor.moveToVisualLineEnd()
        case .documentStart:
            try editor.moveToDocumentStart()
        case .documentEnd:
            try editor.moveToDocumentEnd()
        case .selectLeft:
            try editor.moveGraphemeLeftAndModifySelection()
        case .selectRight:
            try editor.moveGraphemeRightAndModifySelection()
        case .selectWordLeft:
            try editor.moveWordLeftAndModifySelection()
        case .selectWordRight:
            try editor.moveWordRightAndModifySelection()
        case .selectUp:
            try editor.moveVisualByRowsAndModifySelection(-1)
        case .selectDown:
            try editor.moveVisualByRowsAndModifySelection(1)
        case .selectPageUp:
            try editor.moveVisualByPagesAndModifySelection(-1)
        case .selectPageDown:
            try editor.moveVisualByPagesAndModifySelection(1)
        case .selectLineStart:
            try editor.moveToVisualLineStartAndModifySelection()
        case .selectLineEnd:
            try editor.moveToVisualLineEndAndModifySelection()
        case .selectDocumentStart:
            try editor.moveToDocumentStartAndModifySelection()
        case .selectDocumentEnd:
            try editor.moveToDocumentEndAndModifySelection()
        }
    }

    private enum SelectionCollapseEdge {
        case start
        case end
    }

    private static func collapseSelection(_ editor: EditorUI, to edge: SelectionCollapseEdge) throws -> Bool {
        let offsets = try editor.selectionOffsets()
        guard offsets.start != offsets.end else { return false }

        let target = edge == .start ? offsets.start : offsets.end
        try editor.setSelections([EcuSelectionRange(start: target, end: target)], primaryIndex: 0)
        return true
    }

    @discardableResult
    func toggleLineCommentInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return executeActiveEditorCommandObject([
            "kind": "edit",
            "op": "toggle_comment",
            "config": AttoLanguageConfiguration.commentConfig(
                fileURL: tab.fileURL,
                syntaxLanguageId: tab.syntaxLanguageId,
                preferences: preferences
            ).jsonObject,
        ])
    }

    @discardableResult
    func foldSelectionInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            let effectiveEndOffset = endOffset > startOffset ? endOffset - 1 : endOffset
            let start = try tab.editCore.editor.charOffsetToLogicalPosition(offset: startOffset)
            let end = try tab.editCore.editor.charOffsetToLogicalPosition(offset: effectiveEndOffset)

            guard end.line > start.line else {
                NSSound.beep()
                return false
            }

            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"fold","start_line":\#(start.line),"end_line":\#(end.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAtCursorInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"unfold","start_line":\#(pos.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAllInActiveTab() -> Bool {
        executeActiveEditorCommandJSON(
            #"{"kind":"style","op":"unfold_all"}"#,
            treatsAsTextMutation: false
        )
    }

    @discardableResult
    func refreshFoldingRangesInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Folding ranges are unavailable.\nLSP is not enabled for this document.",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        if let status = try? tab.editCore.editor.lspStatusSnapshot(),
           AttoLspFoldingRangesSupport.availability(status: status) == .unsupported {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: AttoLspFoldingRangesSupport.unsupportedMessage,
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestFoldingRanges()
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Folding ranges request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        foldingRangesContext = FoldingRangesRequestContext(tabID: tab.id, showFeedback: showFeedback)
        startFoldingRangesPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applyFoldingRangesResultJSONToActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            try tab.editCore.editor.lspApplyFoldingRangesJSON(json)
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            updateStatusBar()

            if showFeedback, Self.foldingRangesResultCount(json) == 0 {
                showWorkspaceEditPopover(
                    text: "No folding ranges are available for this document.",
                    in: tab.editCore.editorView
                )
            }
            return true
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Folding ranges could not be applied.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    private func startFoldingRangesPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        foldingRangesPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.foldingRangesContext, ctx.tabID == tabID else {
                self.cancelFoldingRangesUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelFoldingRangesUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Folding ranges request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelFoldingRangesUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastFoldingRangesResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelFoldingRangesUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Folding ranges failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let showFeedback = ctx.showFeedback
            self.cancelFoldingRangesUI()
            _ = self.applyFoldingRangesResultJSONToActiveTab(json, showFeedback: showFeedback)
        }

        foldingRangesPollTimer = timer
        timer.resume()
    }

    private static func foldingRangesResultCount(_ json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        if root is NSNull {
            return 0
        }
        return (root as? [Any])?.count
    }

    @discardableResult
    func expandSelectionWithLspInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Selection range is unavailable.\nLSP is not enabled for this document.",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        let positionsJSON: String
        do {
            let selections = try tab.editCore.editor.selections().ranges
            let positions = try selections.map { range in
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: range.end)
                return ["line": Int(pos.line), "column": Int(pos.column)]
            }
            let data = try JSONSerialization.data(
                withJSONObject: positions,
                options: []
            )
            guard let json = String(data: data, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            positionsJSON = json
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Selection range position could not be computed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()

        do {
            _ = try tab.editCore.editor.lspRequestSelectionRange(positionsJSON: positionsJSON)
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Selection range request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        selectionRangeContext = SelectionRangeRequestContext(tabID: tab.id, showFeedback: showFeedback)
        startSelectionRangePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applySelectionRangeResultJSONToActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let selections = try tab.editCore.editor.selections()
            let candidateChains = AttoLspSelectionRangeParser.candidateChains(
                fromResultJSON: json,
                documentText: text
            )

            var nextRanges: [EcuSelectionRange] = []
            nextRanges.reserveCapacity(selections.ranges.count)
            var didExpand = false

            for (idx, range) in selections.ranges.enumerated() {
                let candidates = idx < candidateChains.count ? candidateChains[idx] : []
                if let candidate = AttoLspSelectionRangeParser.nextCandidate(
                    from: candidates,
                    currentStart: range.start,
                    currentEnd: range.end
                ) {
                    nextRanges.append(EcuSelectionRange(start: candidate.start, end: candidate.end))
                    didExpand = true
                } else {
                    nextRanges.append(range)
                }
            }

            guard didExpand else {
                if showFeedback {
                    showWorkspaceEditPopover(
                        text: "No larger selection range is available.",
                        in: tab.editCore.editorView
                    )
                }
                NSSound.beep()
                return false
            }

            try tab.editCore.editor.setSelections(
                nextRanges,
                primaryIndex: min(selections.primaryIndex, UInt32(max(0, nextRanges.count - 1)))
            )
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            tab.editCore.editorView.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Selection range could not be applied.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    private func startSelectionRangePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        selectionRangePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.selectionRangeContext, ctx.tabID == tabID else {
                self.cancelSelectionRangeUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelSelectionRangeUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Selection range request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSelectionRangeUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastSelectionRangeResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelSelectionRangeUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Selection range failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let showFeedback = ctx.showFeedback
            self.cancelSelectionRangeUI()
            _ = self.applySelectionRangeResultJSONToActiveTab(json, showFeedback: showFeedback)
        }

        selectionRangePollTimer = timer
        timer.resume()
    }

    @discardableResult
    func startLinkedEditingInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Linked editing is unavailable.\nLSP is not enabled for this document.",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        let caretOffset: UInt32
        let position: (line: UInt32, column: UInt32)
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            caretOffset = offsets.end
            position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Linked editing position could not be computed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            _ = try tab.editCore.editor.lspRequestLinkedEditingRange(
                logicalLine: position.line,
                logicalColumn: position.column
            )
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Linked editing request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        linkedEditingContext = LinkedEditingRequestContext(
            tabID: tab.id,
            caretOffset: caretOffset,
            showFeedback: showFeedback
        )
        startLinkedEditingPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applyLinkedEditingRangeResultJSONToActiveTab(
        _ json: String,
        caretOffset: UInt32? = nil,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let effectiveCaretOffset = caretOffset ?? offsets.end
            guard let result = AttoLspLinkedEditingParser.result(
                fromLinkedEditingRangeResultJSON: json,
                documentText: text
            ), result.ranges.count > 1 else {
                if showFeedback {
                    showWorkspaceEditPopover(
                        text: "No linked editing ranges are available here.",
                        in: tab.editCore.editorView
                    )
                }
                NSSound.beep()
                return false
            }

            try tab.editCore.editor.setSelections(
                result.ranges,
                primaryIndex: result.primaryIndex(containing: effectiveCaretOffset)
            )
            linkedEditingSession = LinkedEditingSession(tabID: tab.id, selectionCount: result.ranges.count)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Linked editing ranges could not be applied.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    private func startLinkedEditingPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        linkedEditingPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.linkedEditingContext, ctx.tabID == tabID else {
                self.cancelLinkedEditingUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelLinkedEditingUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Linked editing request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelLinkedEditingUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastLinkedEditingRangeResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelLinkedEditingUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Linked editing failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let caretOffset = ctx.caretOffset
            let showFeedback = ctx.showFeedback
            self.cancelLinkedEditingUI()
            _ = self.applyLinkedEditingRangeResultJSONToActiveTab(
                json,
                caretOffset: caretOffset,
                showFeedback: showFeedback
            )
        }

        linkedEditingPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showDocumentColorsInActiveTab(showFeedback: Bool = true) -> Bool {
        requestDocumentColorsInActiveTab(mode: .presentations, showFeedback: showFeedback)
    }

    @discardableResult
    func pickDocumentColorInActiveTab(showFeedback: Bool = true) -> Bool {
        requestDocumentColorsInActiveTab(mode: .picker, showFeedback: showFeedback)
    }

    @discardableResult
    private func requestDocumentColorsInActiveTab(
        mode: DocumentColorResultMode,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Document colors are unavailable.\nLSP is not enabled for this document.",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            _ = try tab.editCore.editor.lspRequestDocumentColor()
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Document color request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        documentColorContext = DocumentColorRequestContext(
            tabID: tab.id,
            showFeedback: showFeedback,
            mode: mode
        )
        startDocumentColorPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showDocumentColorResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        handleDocumentColorResultJSON(json, mode: .presentations, showFeedback: showFeedback)
    }

    @discardableResult
    func pickDocumentColorResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        handleDocumentColorResultJSON(json, mode: .picker, showFeedback: showFeedback)
    }

    @discardableResult
    private func handleDocumentColorResultJSON(
        _ json: String,
        mode: DocumentColorResultMode,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let items = AttoLspDocumentColorParser.items(
            fromDocumentColorResultJSON: json,
            documentText: text
        )
        guard items.isEmpty == false else {
            if showFeedback {
                showWorkspaceEditPopover(text: "No document colors are available.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        switch mode {
        case .presentations:
            showDocumentColorResults(items, tabID: tab.id)
        case .picker:
            showDocumentColorPickerResults(items, tabID: tab.id)
        }
        return true
    }

    private func showDocumentColorResults(_ items: [AttoLspDocumentColorParser.Item], tabID: UUID) {
        guard let window = view.window else {
            if let first = items.first {
                _ = selectDocumentColor(first, tabID: tabID, requestPresentations: false)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.document_color.\(idx)",
                title: AttoLspDocumentColorParser.displayTitle(for: item),
                swatchColor: nsColor(for: item.color)
            ) { [weak self] in
                _ = self?.selectDocumentColor(item, tabID: tabID, requestPresentations: true)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.DocumentColors",
            commandsProvider: { commands }
        )
        documentColorResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter document colors...")
    }

    private func showDocumentColorPickerResults(_ items: [AttoLspDocumentColorParser.Item], tabID: UUID) {
        guard items.count > 1, let window = view.window else {
            if let first = items.first {
                _ = openDocumentColorPicker(for: first, tabID: tabID)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.pick_document_color.\(idx)",
                title: "Pick \(AttoLspDocumentColorParser.displayTitle(for: item))",
                swatchColor: nsColor(for: item.color)
            ) { [weak self] in
                _ = self?.openDocumentColorPicker(for: item, tabID: tabID)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.DocumentColorPicker",
            commandsProvider: { commands }
        )
        documentColorResultsController = controller
        controller.show(relativeTo: window, placeholder: "Pick document color...")
    }

    @discardableResult
    private func selectDocumentColor(
        _ item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        requestPresentations: Bool
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        do {
            try tab.editCore.editor.setSelections([item.range], primaryIndex: 0)
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
        } catch {
            NSSound.beep()
            return false
        }

        if requestPresentations {
            return requestColorPresentations(for: item, tabID: tabID, showFeedback: true)
        }
        return true
    }

    @discardableResult
    private func openDocumentColorPicker(
        for item: AttoLspDocumentColorParser.Item,
        tabID: UUID
    ) -> Bool {
        guard selectDocumentColor(item, tabID: tabID, requestPresentations: false) else {
            return false
        }

        let initialColor = nsColor(for: item.color)
        if let documentColorPickerForTesting {
            guard let pickedColor = documentColorPickerForTesting(initialColor) else {
                return true
            }
            return handlePickedDocumentColor(pickedColor, item: item, tabID: tabID, showFeedback: true)
        }

        documentColorPanelContext = DocumentColorPanelContext(tabID: tabID, item: item)
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = initialColor
        panel.setTarget(self)
        panel.setAction(#selector(documentColorPanelDidChange(_:)))
        panel.orderFront(nil)
        return true
    }

    @objc private func documentColorPanelDidChange(_ sender: NSColorPanel) {
        guard let ctx = documentColorPanelContext else { return }
        _ = handlePickedDocumentColor(sender.color, item: ctx.item, tabID: ctx.tabID, showFeedback: false)
    }

    @discardableResult
    private func handlePickedDocumentColor(
        _ pickedColor: NSColor,
        item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool
    ) -> Bool {
        guard let color = lspColor(for: pickedColor) else {
            guard let tab = activeTab, tab.id == tabID else { return false }
            if showFeedback {
                showWorkspaceEditPopover(text: "Selected color could not be converted to RGB.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let pickedItem = AttoLspDocumentColorParser.Item(
            range: item.range,
            startLine: item.startLine,
            startUTF16Character: item.startUTF16Character,
            color: color
        )
        return requestColorPresentations(for: pickedItem, tabID: tabID, showFeedback: showFeedback)
    }

    @discardableResult
    private func requestColorPresentations(
        for item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }
        guard let colorJSON = AttoLspDocumentColorParser.colorJSON(for: item) else {
            if showFeedback {
                showWorkspaceEditPopover(text: "Color presentation request could not encode the color.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelColorPresentationUI()
        do {
            _ = try tab.editCore.editor.lspRequestColorPresentation(
                startOffset: item.range.start,
                endOffset: item.range.end,
                colorJSON: colorJSON
            )
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Color presentation request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        colorPresentationContext = ColorPresentationRequestContext(
            tabID: tabID,
            item: item,
            showFeedback: showFeedback
        )
        startColorPresentationPollTimer(tabID: tabID, editorView: tab.editCore.editorView)
        return true
    }

    private func startDocumentColorPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        documentColorPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.documentColorContext, ctx.tabID == tabID else {
                self.cancelDocumentColorUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentColorUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Document color request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelDocumentColorUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastDocumentColorResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentColorUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Document colors failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let showFeedback = ctx.showFeedback
            let mode = ctx.mode
            self.cancelDocumentColorRequestOnly()
            _ = self.handleDocumentColorResultJSON(json, mode: mode, showFeedback: showFeedback)
        }

        documentColorPollTimer = timer
        timer.resume()
    }

    private func startColorPresentationPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        colorPresentationPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.colorPresentationContext, ctx.tabID == tabID else {
                self.cancelColorPresentationUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelColorPresentationUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Color presentation request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelColorPresentationUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastColorPresentationResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelColorPresentationUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Color presentations failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let item = ctx.item
            let showFeedback = ctx.showFeedback
            self.cancelColorPresentationRequestOnly()
            _ = self.showColorPresentationResultJSONInActiveTab(
                json,
                item: item,
                tabID: tabID,
                showFeedback: showFeedback
            )
        }

        colorPresentationPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showColorPresentationResultJSONInActiveTab(
        _ json: String,
        item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let presentations = AttoLspDocumentColorParser.presentations(
            fromColorPresentationResultJSON: json,
            documentText: text
        )
        guard presentations.isEmpty == false else {
            if showFeedback {
                showWorkspaceEditPopover(text: "No color presentations are available.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            return applyColorPresentationToActiveTab(presentations[0], showFeedback: showFeedback)
        }

        let commands = presentations.enumerated().map { idx, presentation in
            AttoCommandPaletteCommand(
                id: "lsp.color_presentation.\(idx)",
                title: AttoLspDocumentColorParser.displayTitle(for: presentation),
                swatchColor: nsColor(for: item.color),
                isEnabled: presentation.isApplicable
            ) { [weak self] in
                _ = self?.applyColorPresentationToActiveTab(presentation, showFeedback: true)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ColorPresentations",
            commandsProvider: { commands }
        )
        colorPresentationResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter color presentations...")
        return true
    }

    @discardableResult
    func applyColorPresentationToActiveTab(
        _ presentation: AttoLspDocumentColorParser.Presentation,
        showFeedback: Bool = true
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard presentation.isApplicable else {
            if showFeedback {
                showWorkspaceEditPopover(text: "This color presentation has no text edit to apply.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.applyTextEdits(presentation.edits)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Color presentation could not be applied.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    private func nsColor(for color: AttoLspDocumentColorParser.Color) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(max(0, min(1, color.red))),
            green: CGFloat(max(0, min(1, color.green))),
            blue: CGFloat(max(0, min(1, color.blue))),
            alpha: CGFloat(max(0, min(1, color.alpha)))
        )
    }

    private func lspColor(for color: NSColor) -> AttoLspDocumentColorParser.Color? {
        guard let rgb = color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB) else {
            return nil
        }

        return AttoLspDocumentColorParser.Color(
            red: Double(max(0, min(1, rgb.redComponent))),
            green: Double(max(0, min(1, rgb.greenComponent))),
            blue: Double(max(0, min(1, rgb.blueComponent))),
            alpha: Double(max(0, min(1, rgb.alphaComponent)))
        )
    }

    func moveToMatchingBracketInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.moveToMatchingBracket()
    }

    func jumpBackInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpBack()
    }

    func jumpForwardInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpForward()
    }

    @discardableResult
    func formatDocumentWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        let result = tab.editCore.editorView.formatDocumentWithLSPResult()
        if result.didApply {
            updateStatusBar()
        }
        return handleFormattingResult(result, title: "Format Document", editorView: tab.editCore.editorView)
    }

    @discardableResult
    func formatSelectionWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            guard startOffset < endOffset else {
                showWorkspaceEditPopover(text: "Format Selection requires a non-empty selection.", in: tab.editCore.editorView)
                NSSound.beep()
                return false
            }

            let result = tab.editCore.editorView.formatRangeWithLSPResult(
                startOffset: startOffset,
                endOffset: endOffset
            )
            if result.didApply {
                updateStatusBar()
            }
            return handleFormattingResult(result, title: "Format Selection", editorView: tab.editCore.editorView)
        } catch {
            showWorkspaceEditPopover(
                text: "Format Selection failed.\n\(error.localizedDescription)",
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    private func handleFormattingResult(
        _ result: EditorCoreLSPFormattingResult,
        title: String,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        switch result {
        case .applied:
            return true
        case .noEdits:
            showWorkspaceEditPopover(text: "\(title) completed with no edits.", in: editorView)
            return false
        case .unavailable(let reason):
            showWorkspaceEditPopover(text: "\(title) is unavailable.\n\(reason)", in: editorView)
            NSSound.beep()
            return false
        case .failed(let message):
            showWorkspaceEditPopover(text: "\(title) failed.\n\(message)", in: editorView)
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    private func executeActiveEditorCommandObject(_ object: [String: Any], treatsAsTextMutation: Bool? = nil) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [])
            guard let json = String(data: data, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            return executeActiveEditorCommandJSON(json, treatsAsTextMutation: treatsAsTextMutation)
        } catch {
            NSSound.beep()
            return false
        }
    }

    private static func commandJSONIsTextMutation(_ commandJSON: String) -> Bool {
        guard let data = commandJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (obj["kind"] as? String) == "edit"
        else {
            return false
        }
        return (obj["op"] as? String) != "end_undo_group"
    }

    private static func commandJSONMayChangeSelection(_ commandJSON: String) -> Bool {
        guard let data = commandJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return false
        }
        return (obj["kind"] as? String) == "cursor"
    }

    // MARK: - Find / Replace

    func showFindBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .find)
            return
        }

        if findReplaceBarView.currentMode() == .find {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .find)
    }

    func showReplaceBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .replace)
            return
        }

        if findReplaceBarView.currentMode() == .replace {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .replace)
    }

    private func ensureFindReplaceBar(mode: AttoFindReplaceBarView.Mode) {
        let wasHidden = findReplaceBarView.isHidden
        let oldMode = findReplaceBarView.currentMode()

        findReplaceBarView.setMode(mode)
        findReplaceBarView.isHidden = false
        findReplaceBarHeightConstraint?.constant = (mode == .find) ? 42 : 76

        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
        findReplaceBarView.searchField.selectText(nil)

        // Always re-apply highlights on show/switch; `activeTab == nil` is fine (no-op).
        if wasHidden || oldMode != mode {
            applyFindStateToActiveTab()
        } else {
            refreshSearchHighlights()
        }
    }

    func hideFindBar() {
        guard findReplaceBarView.isHidden == false else { return }
        clearSearchHighlightsForAllTabs()
        findReplaceBarView.isHidden = true
        findReplaceBarHeightConstraint?.constant = 0
        activeTab?.editCore.focusEditor()
    }

    private func currentSearchOptions() -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: findReplaceBarView.caseSensitiveButton.state == .on,
            wholeWord: findReplaceBarView.wholeWordButton.state == .on,
            regex: findReplaceBarView.regexButton.state == .on
        )
    }

    private func setMatchCountLabel(_ count: UInt32) {
        findReplaceBarView.matchCountLabel.stringValue = "\(count) matches"
    }

    private func applyFindStateToActiveTab() {
        guard findReplaceBarView.isHidden == false else { return }
        refreshSearchHighlights()
    }

    private func clearSearchHighlightsForAllTabs() {
        for tab in tabs {
            do {
                try tab.editCore.editor.clearSearchQuery()
                tab.editCore.editorView.needsDisplay = true
            } catch {
                // Ignore best-effort cleanup errors.
            }
        }
        setMatchCountLabel(0)
    }

    private func refreshSearchHighlights() {
        guard let tab = activeTab else {
            setMatchCountLabel(0)
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            if query.isEmpty {
                try tab.editCore.editor.clearSearchQuery()
                setMatchCountLabel(0)
            } else {
                let count = try tab.editCore.editor.setSearchQuery(query, options: currentSearchOptions())
                setMatchCountLabel(count)
            }
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    @objc private func findOptionsChanged(_ sender: Any?) {
        refreshSearchHighlights()
    }

    @objc private func clearFindClicked(_ sender: Any?) {
        findReplaceBarView.searchField.stringValue = ""
        refreshSearchHighlights()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
    }

    @objc private func findNextClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findNext(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func findPrevClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findPrev(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func replaceCurrentClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceCurrent(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func replaceAllClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceAll(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func closeFindBarClicked(_ sender: Any?) {
        hideFindBar()
    }

    // MARK: - Status bar

    private var activeTab: AttoEditorTab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    private func updateWindowTitle() {
        guard let win = view.window else { return }
        guard let tab = activeTab else {
            win.title = "AttoEditor"
            return
        }

        let name = tab.fileURL.lastPathComponent
        if refreshTabDirtyState(tab) {
            win.title = "AttoEditor — ● \(name)"
        } else {
            win.title = "AttoEditor — \(name)"
        }
    }

    private func handleTabDidMutateDocumentText(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        let preserveCompletionUI = shouldPreserveCompletionUIForCurrentTextMutation
        if selectedTabID == tabID {
            cancelSignatureHelpUI()
            if preserveCompletionUI == false {
                cancelCompletionUI()
            }
        }

        let didUnpreview = tab.isPreview
        if tab.isPreview {
            tab.isPreview = false
        }

        tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true
        syncCoreTabText(tab, markSaved: tab.isDirty == false)
        if didUnpreview {
            pinCoreTabIfPreview(tab)
        }

        refreshTabBar()
        updateWindowTitle()
        if didUnpreview {
            notifySessionStateChanged()
        }

        handleTabDidChangeSelection(tabID: tabID, causedByTextMutation: true)
    }

    private func handleTabDidChangeSelection(tabID: UUID, causedByTextMutation: Bool) {
        guard let session = linkedEditingSession, session.tabID == tabID else { return }
        guard selectedTabID == tabID,
              let tab = tabs.first(where: { $0.id == tabID })
        else {
            linkedEditingSession = nil
            return
        }

        if causedByTextMutation {
            guard let selections = try? tab.editCore.editor.selections(),
                  selections.ranges.count == session.selectionCount,
                  selections.ranges.count > 1
            else {
                linkedEditingSession = nil
                return
            }
            linkedEditingSession = LinkedEditingSession(tabID: tabID, selectionCount: selections.ranges.count)
        } else {
            linkedEditingSession = nil
        }
    }

    private func attachStatusObserver(to editorView: EditorCoreSkiaView) {
        activeViewportObserver = editorView.addViewportStateObserver { [weak self] in
            self?.updateStatusBar()
        }
    }

    private func updateAlwaysPollProcessingForSelectedTab() {
        for tab in tabs {
            for editCore in tab.panes {
                editCore.alwaysPollProcessing = false
            }
        }

        guard let tab = activeTab else { return }
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            tab.editCore.alwaysPollProcessing = true
        }
    }

    private func updateStatusBar() {
        guard let tab = activeTab else {
            derivedStateStore.clearActive()
            problemsPanelController?.update(problems: [])
            clearDiagnosticMarkers()
            statusBarView.update(
                leftText: transientStatusText,
                languageId: nil,
                languageIsEnabled: false,
                lspText: nil,
                positionText: "Ln -, Col -",
                selectionText: nil,
                fileSizeText: nil
            )
            return
        }

        let editor = tab.editCore.editor
        let editorText = try? editor.text()
        if let editorText {
            markActiveDiagnosticsStaleIfNeeded(for: tab, text: editorText)
        }
        derivedStateStore.refreshActive(editor: editor)
        clearActiveDiagnosticsStaleIfDiagnosticsChanged(
            for: tab,
            diagnostics: derivedStateStore.active.diagnostics.diagnostics
        )
        let diagnosticsSnapshot = unifiedDiagnosticsSnapshot(
            for: tab,
            text: editorText,
            includeActiveDiagnostics: true
        )
        recordActiveDiagnosticsLifecycle(diagnosticsSnapshot, for: tab)
        updateProblemsPanelIfVisible(snapshot: diagnosticsSnapshot)
        updateDiagnosticMarkers(for: tab, projections: diagnosticsSnapshot.markerProjections)

        let (line1, col1): (UInt32, UInt32) = {
            do {
                let offsets = try editor.selectionOffsets()
                let pos = try editor.charOffsetToLogicalPosition(offset: offsets.end)
                return (pos.line + 1, pos.column + 1)
            } catch {
                return (0, 0)
            }
        }()

        let selectionText: String? = {
            do {
                let sel = try editor.selections()
                let totalSelected: UInt64 = sel.ranges.reduce(0) { acc, r in
                    let a = UInt64(r.start)
                    let b = UInt64(r.end)
                    let len = a <= b ? (b - a) : (a - b)
                    return acc + len
                }
                let cursors = sel.ranges.count
                if cursors <= 1, let primary = sel.ranges.first {
                    let a = primary.start
                    let b = primary.end
                    let start = min(a, b)
                    let end = max(a, b)
                    let len = UInt64(end - start)
                    if len == 0 {
                        return nil
                    }
                    let startPos = try editor.charOffsetToLogicalPosition(offset: start)
                    let endPos = try editor.charOffsetToLogicalPosition(offset: end)
                    return "Sel \(len) (\(startPos.line + 1):\(startPos.column + 1)-\(endPos.line + 1):\(endPos.column + 1))"
                }
                if totalSelected == 0 {
                    return "\(cursors) cursors"
                }
                return "Sel \(totalSelected) (\(cursors) cursors)"
            } catch {
                return nil
            }
        }()

        let fileSizeText: String? = {
            do {
                let values = try tab.fileURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize else { return nil }
                return AttoFormat.byteCount(Int64(size))
            } catch {
                return nil
            }
        }()

        let lspText: String? = {
            // Keep the status bar clean unless LSP is likely relevant.
            //
            // - Historically, AttoEditor only auto-enabled LSP for Rust.
            // - With configurable LSPs, show LSP status when it is enabled (any language), or for Rust files.
            let isRustFile = (tab.fileURL.pathExtension.lowercased() == "rs")
            let isEnabled = (try? editor.lspIsEnabled()) == true
            guard isRustFile || isEnabled else { return nil }

            do {
                let status = try editor.lspStatusSnapshot()
                let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: isEnabled)
                if let detail = display.failureDetail {
                    presentLspFailureDetailIfNeeded(detail, editorView: tab.editCore.editorView)
                } else {
                    lastPresentedLspFailureDetail = nil
                }
                return display.text
            } catch {
                // Best-effort: never break status bar rendering because of FFI errors.
                return (try? editor.lspIsEnabled()) == true ? "LSP: on" : "LSP: off"
            }
        }()

        statusBarView.update(
            leftText: transientStatusText ?? statusBarLeftText(for: tab, diagnostics: diagnosticsSnapshot),
            languageId: tab.syntaxLanguageId,
            languageIsEnabled: true,
            lspText: lspText,
            positionText: "Ln \(line1), Col \(col1)",
            selectionText: selectionText,
            fileSizeText: fileSizeText
        )
    }

    private func clearDiagnosticMarkers() {
        for tab in tabs {
            for pane in tab.panes {
                pane.minimapDiagnosticMarkers = []
                pane.gutterDiagnosticMarkers = []
            }
        }
    }

    private func updateDiagnosticMarkers(for tab: AttoEditorTab, includeActiveDiagnostics: Bool) {
        let projections = unifiedDiagnosticsSnapshot(
            for: tab,
            includeActiveDiagnostics: includeActiveDiagnostics
        ).markerProjections
        updateDiagnosticMarkers(for: tab, projections: projections)
    }

    private func updateDiagnosticMarkers(
        for tab: AttoEditorTab,
        projections: [AttoDiagnosticMarkerProjection]
    ) {
        let minimapMarkers = projections.map {
            EditorCoreSkiaMinimapMarker(
                logicalLine: $0.logicalLine,
                kind: minimapMarkerKind(for: $0.severity)
            )
        }
        let gutterMarkers = projections.map {
            EditorCoreSkiaGutterDiagnosticMarker(
                logicalLine: $0.logicalLine,
                charOffset: $0.charOffset,
                kind: gutterMarkerKind(for: $0.severity)
            )
        }

        for pane in tab.panes {
            pane.minimapDiagnosticMarkers = minimapMarkers
            pane.gutterDiagnosticMarkers = gutterMarkers
        }
    }

    private func updateProblemsPanelIfVisible(snapshot: AttoUnifiedDiagnosticsSnapshot) {
        guard problemsPanelController?.isVisible == true else { return }
        problemsPanelController?.update(problems: snapshot.problems)
    }

    private func unifiedDiagnosticsSnapshot(
        for tab: AttoEditorTab,
        text: String? = nil,
        includeActiveDiagnostics: Bool
    ) -> AttoUnifiedDiagnosticsSnapshot {
        guard let text = text ?? (try? tab.editCore.editor.text()) else { return .empty }
        return AttoDiagnosticsModel.snapshot(
            activeDiagnostics: derivedStateStore.active.diagnostics.diagnostics,
            includeActiveDiagnostics: includeActiveDiagnostics,
            workspaceDiagnostics: workspaceProblemsStore.diagnostics,
            workspaceMarkers: workspaceProblemsStore.diagnosticMarkerProjections(),
            tabURL: tab.fileURL,
            text: text,
            logicalPositionForOffset: { offset in
                try? tab.editCore.editor.charOffsetToLogicalPosition(offset: offset)
            }
        )
    }

    private func statusBarLeftText(
        for tab: AttoEditorTab,
        diagnostics: AttoUnifiedDiagnosticsSnapshot
    ) -> String? {
        let parts = [
            diagnostics.problemsStatusText,
            derivedStateStore.active.foldedStatusText,
            derivedStateStore.active.codeLensStatusText,
        ].compactMap { $0 }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " | ")
    }

    private func markActiveDiagnosticsStaleIfNeeded(for tab: AttoEditorTab, text: String) {
        let fingerprint = DiagnosticsTextFingerprint(text)
        if let previous = activeDiagnosticsTextFingerprintsByTabID[tab.id], previous != fingerprint {
            activeDiagnosticsStaleReasonsByTabID[tab.id] = .documentEdited
        }
        activeDiagnosticsTextFingerprintsByTabID[tab.id] = fingerprint
    }

    private func clearActiveDiagnosticsStaleIfDiagnosticsChanged(
        for tab: AttoEditorTab,
        diagnostics: [EcuDiagnostic]
    ) {
        if let previous = activeDiagnosticsBaselinesByTabID[tab.id], previous != diagnostics {
            activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tab.id)
        }
        activeDiagnosticsBaselinesByTabID[tab.id] = diagnostics
    }

    private func clearDiagnosticsLifecycleState(forTabID tabID: UUID) {
        activeDiagnosticsTextFingerprintsByTabID.removeValue(forKey: tabID)
        activeDiagnosticsBaselinesByTabID.removeValue(forKey: tabID)
        activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tabID)
    }

    private func recordLspResultLifecycleEvent<Snapshot>(
        _ entry: AttoLspResultLifecycleEntry<Snapshot>,
        payload: AttoLspResultLifecycleEvent.Payload
    ) {
        lspResultEventStream.record(
            family: entry.family,
            title: entry.title,
            recordedAt: entry.recordedAt,
            sourceSequence: entry.sequence,
            payload: payload
        )
    }

    private func recordActiveDiagnosticsLifecycle(
        _ snapshot: AttoUnifiedDiagnosticsSnapshot,
        for tab: AttoEditorTab
    ) {
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .activeTab(tabID: tab.id, fileURL: tab.fileURL.standardizedFileURL),
            problems: snapshot.problems,
            markerProjections: snapshot.markerProjections,
            statusText: snapshot.problemsStatusText,
            staleReason: activeDiagnosticsStaleReasonsByTabID[tab.id]
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.active",
            title: tab.fileURL.lastPathComponent
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    private func recordWorkspaceDiagnosticsLifecycle(
        problems: [AttoUnifiedDiagnosticProblem]
    ) {
        let statusText: String? = {
            let count = problems.count
            guard count > 0 else { return nil }
            return count == 1 ? "Problems: 1" : "Problems: \(count)"
        }()
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .workspace,
            problems: problems,
            markerProjections: [],
            statusText: statusText,
            staleReason: workspaceDiagnosticsStaleReason
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.workspace",
            title: "Workspace Problems"
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    private func diagnosticsLifecycleEvents(
        after sequence: UInt64
    ) -> [AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>] {
        diagnosticsLifecycleStore.entries(after: sequence)
    }

    private func updateWorkspaceDiagnosticMarkersForOpenTabs() {
        for tab in tabs {
            updateDiagnosticMarkers(for: tab, includeActiveDiagnostics: tab.id == activeTab?.id)
        }
    }

    private func minimapMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaMinimapMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    private func gutterMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaGutterDiagnosticMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    func setTransientStatusText(_ text: String?) {
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = normalized?.isEmpty == false ? normalized : nil
        guard transientStatusText != next else { return }
        transientStatusText = next
        updateStatusBar()
    }

    private func setSyntaxLanguageForActiveTab(languageId: String?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        // "Plain Tex" => disable all syntax engines.
        if languageId == nil {
            tab.editCore.editor.lspDisable()
            tab.editCore.editor.treeSitterDisable()
            tab.editCore.editor.sublimeDisable()
            tab.syntaxLanguageId = nil
            applyLanguageConfiguration(for: tab)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
            return
        }

        let lang = (languageId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if lang.isEmpty {
            NSSound.beep()
            return
        }

        // Force Tree-sitter with an explicit language id.
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            // Best-effort (each editor view owns its own registry state).
            try? tab.editCore.editor.treeSitterSetRegistryJSON(registryJSON)
        }

        tab.editCore.editor.lspDisable()
        tab.editCore.editor.sublimeDisable()

        do {
            try tab.editCore.editor.treeSitterEnableLanguage(lang)
            tab.syntaxLanguageId = lang
            applyLanguageConfiguration(for: tab)
            tab.editCore.editorView.kickProcessingPoll()
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
            NSLog(
                "AttoEditor: failed to set Tree-sitter language %@ for %@: %@",
                lang,
                tab.fileURL.path,
                String(describing: error)
            )
            updateStatusBar()
        }
    }

    // MARK: - Navigation

    private func navigate(tab: AttoEditorTab, to location: AttoCommandLine.FileLocation) {
        let line1 = max(1, location.line1)
        let column1 = max(1, location.column1 ?? 1)

        do {
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = Self.charOffsetForLineColumn1(text: text, line1: line1, column1: column1)
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    static func parseGoToLineTarget(_ raw: String) -> GoToLineTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let parts = trimmed
            .split(omittingEmptySubsequences: false) { ch in ch == ":" || ch == "," }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let line1 = Int(parts[0]), line1 > 0 else { return nil }

        let column1: Int
        if parts.count == 2 {
            guard let parsedColumn = Int(parts[1]), parsedColumn > 0 else { return nil }
            column1 = parsedColumn
        } else {
            column1 = 1
        }

        return GoToLineTarget(line1: line1, column1: column1)
    }

    @discardableResult
    func goToLineInActiveTab(input: String) -> Bool {
        guard let target = Self.parseGoToLineTarget(input) else {
            NSSound.beep()
            return false
        }
        return goToLineInActiveTab(line1: target.line1, column1: target.column1)
    }

    @discardableResult
    func goToLineInActiveTab(line1: Int, column1: Int = 1) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let line0 = UInt32(clamping: max(1, line1) - 1)
        let column0 = UInt32(clamping: max(1, column1) - 1)
        do {
            _ = try tab.editCore.editor.moveTo(line: line0, column: column0)
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            tab.editCore.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: go to line failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func promptGoToLineInActiveTab(initialInput: String = "") -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initialInput
        field.placeholderString = "Line or line:column"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a 1-based line number, optionally followed by :column."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return goToLineInActiveTab(input: field.stringValue)
    }

    private static func charOffsetForLineColumn1(text: String, line1: Int, column1: Int) -> UInt32 {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let targetLineIdx = max(0, line1 - 1)
        if targetLineIdx >= lines.count {
            return UInt32(text.count)
        }

        var offset: Int = 0
        if targetLineIdx > 0 {
            for i in 0..<targetLineIdx {
                offset += lines[i].count
                offset += 1 // '\n'
            }
        }

        let lineText = lines[targetLineIdx]
        let col0 = max(0, min(lineText.count, column1 - 1))
        offset += col0
        return UInt32(max(0, offset))
    }

    // MARK: - Content

    private func showEmptyState() {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        contentHostView.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentHostView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentHostView.centerYAnchor),
        ])
    }

    private func showTabContent(_ tab: AttoEditorTab) {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        let container: NSView
        if tab.panes.count == 1 {
            container = tab.editCore
        } else {
            let splitView = NSSplitView(frame: .zero)
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            for pane in tab.panes {
                pane.translatesAutoresizingMaskIntoConstraints = false
                splitView.addArrangedSubview(pane)
            }
            container = splitView
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
        ])
    }

    private func configureEditorChrome(_ editCore: EditCoreUI) throws {
        // 保持至少 6 个 cell 的 gutter（折叠标记 + 行号），但仍允许在超大文件时自动扩展。
        editCore.editorView.minimumGutterWidthCells = 6
        try editCore.editor.setWhitespaceRenderMode(.selection)
        try editCore.editor.setIndentGuidesEnabled(true)
        try editCore.editor.setFontLigaturesEnabled(preferences.effectiveLigaturesEnabled)
        editCore.editorView.fontSizePoints = CGFloat(preferences.effectiveFontSizePoints)
        try editCore.applyTheme(theme)
        _ = try editCore.editor.setWrapMode(preferences.effectiveWrapMode)
        _ = try editCore.editor.setWrapIndent(preferences.effectiveWrapIndent)
        try editCore.editor.setAutoPairsEnabled(preferences.effectiveAutoPairsEnabled)
        try editCore.editor.setBracketMatchHighlightsEnabled(true)
    }

    private func applyLanguageConfiguration(for tab: AttoEditorTab) {
        for editCore in tab.panes {
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: editCore)
        }
    }

    private func applyLanguageConfiguration(fileURL: URL, syntaxLanguageId: String?, to editCore: EditCoreUI) {
        let config = AttoLanguageConfiguration.indentationConfig(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        do {
            _ = try editCore.editor.setIndentationConfig(config)
        } catch {
            NSLog("AttoEditor: setIndentationConfig failed for %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func configureEditCoreHooks(_ editCore: EditCoreUI, tabID: UUID) {
        editCore.onDidMutateDocumentText = { [weak self] in
            self?.handleTabDidMutateDocumentText(tabID: tabID)
        }
        editCore.onDidCommitText = { [weak self] text in
            self?.handleCommittedTextForLspTriggers(text, tabID: tabID)
        }
        editCore.onDidChangeSelection = { [weak self] causedByTextMutation in
            self?.handleTabDidChangeSelection(tabID: tabID, causedByTextMutation: causedByTextMutation)
        }
        editCore.onDidApplyAsyncProcessing = { [weak self] in
            guard let self else { return }
            // Async processing updates (LSP diagnostics/semantic tokens, etc.) can change status
            // bar info even without any user input.
            guard self.activeTab?.id == tabID else { return }
            self.updateStatusBar()
        }
        editCore.onHover = { [weak self] info in
            self?.handleHover(info: info, tabID: tabID)
        }
        editCore.onHoverExit = { [weak self] in
            self?.handleHoverExit(tabID: tabID)
        }
        editCore.editorView.onDidBecomeFirstResponder = { [weak self, weak editCore] in
            guard let self, let editCore else { return }
            self.setActivePane(editCore, tabID: tabID)
        }
        editCore.editorView.onCommandClick = { [weak self] ctx in
            self?.handleCommandClick(ctx: ctx, tabID: tabID) ?? false
        }
        editCore.editorView.onCodeLensClick = { [weak self] json in
            self?.handleCodeLensClick(json: json, tabID: tabID) ?? false
        }
        editCore.editorView.onCommandHover = { [weak self] _ in
            guard let self else { return false }
            guard activeTab?.id == tabID else { return false }
            guard let tab = activeTab else { return false }
            // Only show Cmd-hover "clickable" affordance when Cmd-click is expected to resolve via LSP.
            return (try? tab.editCore.editor.lspIsEnabled()) == true
        }
    }

    private func setActivePane(_ editCore: EditCoreUI, tabID: UUID) {
        guard selectedTabID == tabID else { return }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        guard let idx = tab.panes.firstIndex(where: { $0 === editCore }) else { return }

        tab.activePaneIndex = idx
        setCoreActiveView(tab)
        attachStatusObserver(to: editCore.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
    }

    // MARK: - Tab creation

    private func makeTab(
        for url: URL,
        isPreview: Bool,
        showsMinimap: Bool = true,
        isUntitled: Bool = false
    ) throws -> AttoEditorTab {
        let initialText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let prefs = AttoPreferences.shared
        let fontFamiliesCSV = prefs.fontFamiliesCSVForNewViews()

        let editCore = try EditCoreUI(
            library: library,
            initialText: initialText,
            viewportWidthCells: 120,
            fontFamiliesCSV: fontFamiliesCSV,
            showsMinimap: showsMinimap,
            minimapPlacement: .rightOfScrollbar
        )

        try configureEditorChrome(editCore)

        // Tree-sitter registry (best-effort).
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            do {
                try editCore.editor.treeSitterSetRegistryJSON(registryJSON)
            } catch {
                NSLog("AttoEditor: Tree-sitter registry init failed: %@", String(describing: error))
            }
        }

        // Syntax support (best-effort): LSP -> Tree-sitter -> Sublime `.sublime-syntax`.
        let syntaxLanguageId = configureSyntaxSupport(for: url, editCore: editCore)
        applyLanguageConfiguration(fileURL: url, syntaxLanguageId: syntaxLanguageId, to: editCore)

        let tabId = UUID()
        editCore.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorPane(tabId))
        editCore.editorView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorView(tabId))
        let coreTabID = openCoreDocumentTab(for: url, initialText: initialText, isPreview: isPreview)
        let tab = AttoEditorTab(
            id: tabId,
            coreTabID: coreTabID,
            fileURL: url,
            isUntitled: isUntitled,
            isPreview: isPreview,
            isDirty: false,
            syntaxLanguageId: syntaxLanguageId,
            editCore: editCore
        )
        configureEditCoreHooks(editCore, tabID: tabId)
        return tab
    }

    // MARK: - Saving helpers

    @discardableResult
    private func saveTabWithSavePanelIfNeeded(_ tab: AttoEditorTab) -> Bool {
        guard tab.isUntitled else {
            return saveTab(tab)
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = "Choose where to save this file."
        panel.directoryURL = workspaceRootURL

        let defaultName = tab.fileURL.lastPathComponent.isEmpty ? "untitled.txt" : tab.fileURL.lastPathComponent
        panel.nameFieldStringValue = defaultName

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return false
        }

        if tabs.contains(where: { $0.id != tab.id && $0.fileURL.standardizedFileURL == url }) {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "This file is already open."
            alert.informativeText = "Please choose a different name or close the other tab first."
            alert.runModal()
            return false
        }

        let oldURL = tab.fileURL
        tab.fileURL = url
        if saveTab(tab) {
            return true
        }

        // Best-effort rollback if the actual write failed.
        tab.fileURL = oldURL
        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
        return false
    }

    private func configureSyntaxSupport(for url: URL, editCore: EditCoreUI) -> String? {
        // Start from a clean slate (best-effort). This avoids stacking style layers when a host
        // switches engines (e.g. LSP becomes available later).
        editCore.editor.lspDisable()
        editCore.editor.treeSitterDisable()
        editCore.editor.sublimeDisable()

        // 1) LSP (configurable by extension).
        let env = ProcessInfo.processInfo.environment
        let disableLSP = env["ATTO_EDITOR_DISABLE_LSP"] == "1"
            || env["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"

        if disableLSP == false {
            let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let configured = AttoLspRegistry.loadServerMap()[ext]

            let cmd: String? = {
                if let configured { return configured.command }

                // Backwards-compat: preserve Rust env override + default behavior when no config exists.
                if ext == "rs" {
                    return env["ATTO_EDITOR_LSP_CMD"]
                        ?? env["EDITOR_CORE_APPKIT_LSP_CMD"]
                        ?? "rust-analyzer"
                }

                return nil
            }()

            let args: String? = {
                if let configured { return configured.args }

                // Backwards-compat for Rust-only env args.
                if ext == "rs" {
                    return env["ATTO_EDITOR_LSP_ARGS"]
                        ?? env["EDITOR_CORE_APPKIT_LSP_ARGS"]
                }

                return nil
            }()

            let languageId: String? = {
                if let configured, let lang = configured.languageId { return lang }
                if let inferred = inferredTreeSitterLanguageId(for: url) { return inferred }
                return AttoLspLanguageId.guess(forExtension: ext)
            }()

            if let cmd, let languageId, languageId.isEmpty == false {
                do {
                    try editCore.editor.lspEnable(
                        command: cmd,
                        args: args,
                        rootURI: workspaceRootURL.absoluteString,
                        documentURI: url.absoluteString,
                        languageId: languageId
                    )

                    let supportsSemanticTokens: Bool = {
                        guard let status = try? editCore.editor.lspStatusSnapshot() else { return false }
                        return status.capabilities?.semanticTokens == true
                    }()

                    if supportsSemanticTokens {
                        // Prefer LSP semantic tokens; keep other engines off.
                        editCore.editor.treeSitterDisable()
                        editCore.editor.sublimeDisable()
                    } else {
                        // LSP without semantic tokens: keep Tree-sitter for baseline highlighting.
                        do {
                            try editCore.editor.treeSitterEnableForPath(url.path)
                            // Kick a short poll window so the initial Tree-sitter parse applies even without edits.
                            editCore.editorView.kickProcessingPoll()
                        } catch {
                            NSLog(
                                "AttoEditor: Tree-sitter enable failed for %@ (fallback after LSP without semantic tokens): %@",
                                url.path,
                                String(describing: error)
                            )
                        }
                        editCore.editor.sublimeDisable()
                    }
                    return languageId
                } catch {
                    NSLog("AttoEditor: LSP enable failed for %@: %@", url.path, String(describing: error))
                }
            }
        }

        // 2) Tree-sitter.
        do {
            try editCore.editor.treeSitterEnableForPath(url.path)
            editCore.editor.sublimeDisable()
            // Kick a short poll window so the initial Tree-sitter parse applies even without edits.
            editCore.editorView.kickProcessingPoll()
            return inferredTreeSitterLanguageId(for: url)
        } catch {
            NSLog("AttoEditor: Tree-sitter enable failed for %@: %@", url.path, String(describing: error))
        }

        // 3) Sublime `.sublime-syntax` (optional fallback).
        guard let syntaxPath = AttoSublimeSyntax.findSyntaxPath(
            for: url,
            workspaceRootURL: workspaceRootURL
        ) else {
            NSLog("AttoEditor: no Sublime syntax found for %@ (ext=%@)", url.path, url.pathExtension)
            return nil
        }

        do {
            try editCore.editor.sublimeSetSyntaxPath(syntaxPath)
            editCore.editor.treeSitterDisable()
            editCore.editorView.needsDisplay = true
            return nil
        } catch {
            NSLog(
                "AttoEditor: Sublime syntax enable failed (path=%@) for %@: %@",
                syntaxPath,
                url.path,
                String(describing: error)
            )
            return nil
        }
    }

    // MARK: - LSP location requests

    private func handleCommandClick(ctx: EditorCoreSkiaContextMenuContext, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        return requestLspLocation(tabID: tabID, logicalLine: ctx.logicalLine, logicalColumn: ctx.logicalColumn, kind: .definition)
    }

    @discardableResult
    func goToDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .definition)
    }

    @discardableResult
    func goToDeclarationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .declaration)
    }

    @discardableResult
    func goToTypeDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .typeDefinition)
    }

    @discardableResult
    func goToImplementationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .implementation)
    }

    @discardableResult
    func findReferencesInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .references)
    }

    private func requestLspLocationAtPrimaryCaret(kind: LspLocationRequestKind) -> Bool {
        guard let tab = activeTab else { return false }
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return requestLspLocation(
                tabID: tab.id,
                logicalLine: pos.line,
                logicalColumn: pos.column,
                kind: kind
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func requestLspLocation(
        tabID: UUID,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        kind: LspLocationRequestKind
    ) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let tab = activeTab else { return false }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        definitionContext = DefinitionRequestContext(
            tabID: tabID,
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            kind: kind
        )
        definitionPollTimer?.cancel()

        do {
            try requestLspLocation(kind: kind, editor: tab.editCore.editor, line: logicalLine, column: logicalColumn)
        } catch {
            cancelDefinitionUI()
            NSSound.beep()
            return false
        }

        startDefinitionPollTimer(tabID: tabID)
        return true
    }

    private func requestLspLocation(kind: LspLocationRequestKind, editor: EditorUI, line: UInt32, column: UInt32) throws {
        switch kind {
        case .definition:
            _ = try editor.lspRequestDefinition(logicalLine: line, logicalColumn: column)
        case .declaration:
            _ = try editor.lspRequestDeclaration(logicalLine: line, logicalColumn: column)
        case .typeDefinition:
            _ = try editor.lspRequestTypeDefinition(logicalLine: line, logicalColumn: column)
        case .implementation:
            _ = try editor.lspRequestImplementation(logicalLine: line, logicalColumn: column)
        case .references:
            _ = try editor.lspRequestReferences(logicalLine: line, logicalColumn: column, includeDeclaration: true)
        }
    }

    private func startDefinitionPollTimer(tabID: UUID) {
        definitionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.definitionContext, ctx.tabID == tabID else {
                self.cancelDefinitionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelDefinitionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelDefinitionUI()
                return
            }

            let json: String?
            do {
                json = try self.takeLspLocationResult(kind: ctx.kind, editor: tab.editCore.editor)
            } catch {
                return
            }
            guard let json else { return }

            self.cancelDefinitionUI()
            _ = self.showLspLocationResultJSONInActiveTab(json, kind: ctx.kind)
            timer.cancel()
        }

        definitionPollTimer = timer
        timer.resume()
    }

    private func takeLspLocationResult(kind: LspLocationRequestKind, editor: EditorUI) throws -> String? {
        switch kind {
        case .definition:
            try editor.lspTakeLastDefinitionResultJSON()
        case .declaration:
            try editor.lspTakeLastDeclarationResultJSON()
        case .typeDefinition:
            try editor.lspTakeLastTypeDefinitionResultJSON()
        case .implementation:
            try editor.lspTakeLastImplementationResultJSON()
        case .references:
            try editor.lspTakeLastReferencesResultJSON()
        }
    }

    @discardableResult
    func showLspLocationResultJSONInActiveTab(_ json: String, kind: LspLocationRequestKind) -> Bool {
        let targets = AttoLspDefinitionParser.targets(fromLocationResultJSON: json)
        guard targets.isEmpty == false else {
            NSSound.beep()
            return false
        }

        let items = AttoLspDefinitionParser.locationItems(for: targets, workspaceRootURL: workspaceRootURL)
        let snapshot = LspLocationResultSnapshot(kind: kind, items: items)
        recordLspLocationResultSnapshot(snapshot)

        if items.count > 1 {
            showLspLocationResults(snapshot)
            return true
        }

        navigateToLspTarget(items[0].target)
        return true
    }

    @discardableResult
    func showLastLspLocationResults() -> Bool {
        guard let entry = lspLocationResultStore.currentEntry, entry.snapshot.items.isEmpty == false else {
            NSSound.beep()
            return false
        }
        let snapshot = entry.snapshot

        if snapshot.items.count > 1 {
            showLspLocationResults(snapshot)
        } else {
            navigateToLspTarget(snapshot.items[0].target)
        }
        return true
    }

    @discardableResult
    func showLspLocationHistory() -> Bool {
        guard lspLocationResultStore.historyEntries.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            guard let entry = lspLocationResultStore.historyEntries.last else { return false }
            return openLspLocationEntry(entry)
        }

        let entries = Array(lspLocationResultStore.historyEntries.reversed())
        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.location_history.\(idx)",
                title: entry.title
            ) { [weak self] in
                _ = self?.openLspLocationEntry(entry)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.LocationHistory",
            commandsProvider: { commands }
        )
        lspLocationResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter location history...")
        return true
    }

    @discardableResult
    func showLspLocationPanel() -> Bool {
        guard let entry = lspLocationResultStore.currentEntry, entry.snapshot.items.isEmpty == false else {
            NSSound.beep()
            return false
        }
        let snapshot = entry.snapshot
        guard let window = view.window else {
            return openLspLocationEntry(entry)
        }
        let controller = lspLocationPanelController ?? AttoLspLocationPanelController { [weak self] target in
            self?.navigateToLspTarget(target)
        }
        lspLocationPanelController = controller
        return controller.show(relativeTo: window, snapshot: snapshot)
    }

    private func recordLspLocationResultSnapshot(_ snapshot: LspLocationResultSnapshot) {
        let entry = lspLocationResultStore.record(
            snapshot,
            family: "locations",
            title: locationHistoryTitle(for: snapshot)
        )
        recordLspResultLifecycleEvent(
            entry,
            payload: .locations(kind: snapshot.kind.lifecycleKind, itemCount: snapshot.items.count)
        )
        lspLocationPanelController?.update(snapshot: snapshot)
    }

    @discardableResult
    private func openLspLocationSnapshot(_ snapshot: LspLocationResultSnapshot) -> Bool {
        lspLocationResultStore.makeCurrent(
            snapshot,
            family: "locations",
            title: locationHistoryTitle(for: snapshot)
        )
        return presentLspLocationSnapshot(snapshot)
    }

    @discardableResult
    private func openLspLocationEntry(_ entry: AttoLspResultLifecycleEntry<LspLocationResultSnapshot>) -> Bool {
        lspLocationResultStore.makeCurrent(entry)
        return presentLspLocationSnapshot(entry.snapshot)
    }

    @discardableResult
    private func presentLspLocationSnapshot(_ snapshot: LspLocationResultSnapshot) -> Bool {
        if snapshot.items.count > 1 {
            showLspLocationResults(snapshot)
        } else if let first = snapshot.items.first {
            navigateToLspTarget(first.target)
        } else {
            NSSound.beep()
            return false
        }
        return true
    }

    private func locationHistoryTitle(for snapshot: LspLocationResultSnapshot) -> String {
        if snapshot.items.count == 1, let first = snapshot.items.first {
            return "\(snapshot.kind.historyTitle): \(first.displayTitle)"
        }
        return "\(snapshot.kind.historyTitle): \(snapshot.items.count) results"
    }

    private func showLspLocationResults(_ snapshot: LspLocationResultSnapshot) {
        guard let window = view.window else {
            navigateToLspTarget(snapshot.items[0].target)
            return
        }

        let commands = snapshot.items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.location.\(idx)",
                title: item.displayTitle
            ) { [weak self] in
                self?.navigateToLspTarget(item.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.LocationResults",
            commandsProvider: { commands }
        )
        lspLocationResultsController = controller
        controller.show(relativeTo: window, placeholder: snapshot.kind.resultPlaceholder)
    }

    private func displayTitle(for target: AttoLspDefinitionParser.Target) -> String {
        AttoLspDefinitionParser.locationItems(for: [target], workspaceRootURL: workspaceRootURL)
            .first?
            .displayTitle ?? "\(target.uri):\(target.line + 1):\(target.utf16Character + 1)"
    }

    private func navigateToLspTarget(_ target: AttoLspDefinitionParser.Target) {
        guard let url = URL(string: target.uri), url.isFileURL else {
            NSSound.beep()
            return
        }

        openFile(url: url, mode: .preview)

        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else {
            return
        }

        do {
            // Ensure the new editor view has a real viewport height before calling `revealPrimaryCaret`.
            // `EditorUI.revealPrimaryCaret()` is a no-op when viewport height is unknown.
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = AttoLspDefinitionParser.charOffsetForLspPosition(
                inText: text,
                line: target.line,
                utf16Character: target.utf16Character
            )
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - LSP symbols quick panels

    @discardableResult
    func showDocumentSymbolsInActiveTab() -> Bool {
        requestLspSymbols(kind: .document)
    }

    @discardableResult
    func showWorkspaceSymbolsInActiveTab(query: String = "") -> Bool {
        requestLspSymbols(kind: .workspace(query: query))
    }

    @discardableResult
    func promptWorkspaceSymbolsInActiveTab(initialQuery: String = "") -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            showWorkspaceEditPopover(
                text: AttoLspSymbolRequestFeedback.unavailableMessage(kind: .workspace),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return showWorkspaceSymbolsInActiveTab(query: initialQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        workspaceSymbolSearchQuery = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceSymbolSearchResults = []

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.WorkspaceSymbolSearch",
            filtersCommands: false,
            searchTextDidChange: { [weak self] query in
                self?.scheduleWorkspaceSymbolSearch(query: query)
            },
            commandsProvider: { [weak self] in
                self?.workspaceSymbolSearchCommands() ?? []
            }
        )
        lspSymbolResultsController = controller
        controller.show(
            relativeTo: window,
            placeholder: "Search workspace symbols...",
            initialQuery: workspaceSymbolSearchQuery
        )
        requestWorkspaceSymbolSearch(query: workspaceSymbolSearchQuery)
        return true
    }

    private func workspaceSymbolSearchCommands() -> [AttoCommandPaletteCommand] {
        let query = workspaceSymbolSearchQuery
        let symbols = workspaceSymbolSearchResults
        return symbols.enumerated().map { idx, symbol in
            AttoCommandPaletteCommand(
                id: "lsp.workspace_symbol_search.\(idx)",
                title: displayTitle(for: symbol),
                group: AttoLspSymbolParser.kindGroupLabel(for: symbol)
            ) { [weak self] in
                self?.openWorkspaceSymbolSearchResult(symbol, symbols: symbols, query: query)
            }
        }
    }

    private func scheduleWorkspaceSymbolSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceSymbolSearchQuery = trimmedQuery
        workspaceSymbolSearchResults = []
        lspSymbolResultsController?.reloadCommands()

        workspaceSymbolSearchDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.18)
        timer.setEventHandler { [weak self] in
            self?.requestWorkspaceSymbolSearch(query: trimmedQuery)
        }
        workspaceSymbolSearchDebounceTimer = timer
        timer.resume()
    }

    private func requestWorkspaceSymbolSearch(query: String) {
        guard let tab = activeTab else {
            cancelSymbolUI()
            return
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            workspaceSymbolSearchResults = []
            lspSymbolResultsController?.reloadCommands()
            return
        }

        workspaceSymbolSearchDebounceTimer?.cancel()
        workspaceSymbolSearchDebounceTimer = nil
        workspaceSymbolSearchPollTimer?.cancel()

        workspaceSymbolSearchRequestID += 1
        let requestID = workspaceSymbolSearchRequestID
        workspaceSymbolSearchContext = WorkspaceSymbolSearchContext(
            tabID: tab.id,
            requestID: requestID,
            query: query
        )

        do {
            _ = try tab.editCore.editor.lspRequestWorkspaceSymbols(query: query)
        } catch {
            workspaceSymbolSearchContext = nil
            workspaceSymbolSearchResults = []
            lspSymbolResultsController?.reloadCommands()
            return
        }

        startWorkspaceSymbolSearchPollTimer(tabID: tab.id, requestID: requestID)
    }

    private func startWorkspaceSymbolSearchPollTimer(tabID: UUID, requestID: Int) {
        workspaceSymbolSearchPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.workspaceSymbolSearchContext,
                  ctx.tabID == tabID,
                  ctx.requestID == requestID
            else {
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.workspaceSymbolSearchPollTimer?.cancel()
                self.workspaceSymbolSearchPollTimer = nil
                self.workspaceSymbolSearchContext = nil
                timer.cancel()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSymbolUI()
                timer.cancel()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastWorkspaceSymbolsResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.workspaceSymbolSearchPollTimer?.cancel()
            self.workspaceSymbolSearchPollTimer = nil
            self.workspaceSymbolSearchContext = nil
            if ctx.query == self.workspaceSymbolSearchQuery {
                self.workspaceSymbolSearchResults = AttoLspSymbolParser.workspaceSymbols(fromResultJSON: json)
                self.lspSymbolResultsController?.reloadCommands()
            }
            timer.cancel()
        }

        workspaceSymbolSearchPollTimer = timer
        timer.resume()
    }

    private func openWorkspaceSymbolSearchResult(
        _ symbol: AttoLspSymbolParser.Symbol,
        symbols: [AttoLspSymbolParser.Symbol],
        query: String
    ) {
        let snapshot = LspSymbolResultSnapshot(
            title: workspaceSymbolTitle(query: query),
            symbols: symbols,
            placeholder: "Search workspace symbols..."
        )
        recordLspSymbolResultSnapshot(snapshot)
        navigateToLspTarget(symbol.target)
    }

    private func requestLspSymbols(kind: LspSymbolRequestKind) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            showWorkspaceEditPopover(
                text: AttoLspSymbolRequestFeedback.unavailableMessage(kind: kind.feedbackKind),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        symbolContext = SymbolRequestContext(tabID: tab.id, kind: kind)

        do {
            switch kind {
            case .document:
                _ = try tab.editCore.editor.lspRequestDocumentSymbols()
            case .workspace(let query):
                _ = try tab.editCore.editor.lspRequestWorkspaceSymbols(query: query)
            }
        } catch {
            cancelSymbolUI()
            showWorkspaceEditPopover(
                text: AttoLspSymbolRequestFeedback.requestFailedMessage(
                    kind: kind.feedbackKind,
                    errorDescription: error.localizedDescription
                ),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }

        startSymbolPollTimer(tabID: tab.id)
        return true
    }

    private func startSymbolPollTimer(tabID: UUID) {
        symbolPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.symbolContext, ctx.tabID == tabID else {
                self.cancelSymbolUI()
                return
            }

            if remainingTicks <= 0 {
                let tab = self.activeTab
                let message = AttoLspSymbolRequestFeedback.timeoutMessage(kind: ctx.kind.feedbackKind)
                self.cancelSymbolUI()
                if let tab, tab.id == tabID {
                    self.showWorkspaceEditPopover(text: message, in: tab.editCore.editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSymbolUI()
                return
            }

            let json: String?
            do {
                switch ctx.kind {
                case .document:
                    json = try tab.editCore.editor.lspTakeLastDocumentSymbolsResultJSON()
                case .workspace:
                    json = try tab.editCore.editor.lspTakeLastWorkspaceSymbolsResultJSON()
                }
            } catch {
                let message = AttoLspSymbolRequestFeedback.failedMessage(
                    kind: ctx.kind.feedbackKind,
                    errorDescription: error.localizedDescription
                )
                self.cancelSymbolUI()
                self.showWorkspaceEditPopover(text: message, in: tab.editCore.editorView)
                NSSound.beep()
                return
            }
            guard let json else { return }

            self.cancelSymbolUI()
            _ = self.handleLspSymbolResultJSON(json, kind: ctx.kind, tab: tab)
            timer.cancel()
        }

        symbolPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showDocumentSymbolResultJSONInActiveTab(_ json: String) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return handleLspSymbolResultJSON(json, kind: .document, tab: tab)
    }

    @discardableResult
    func showWorkspaceSymbolResultJSONInActiveTab(_ json: String, query: String = "") -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return handleLspSymbolResultJSON(json, kind: .workspace(query: query), tab: tab)
    }

    @discardableResult
    func showLastLspSymbolResults() -> Bool {
        guard let entry = lspSymbolResultStore.currentEntry, entry.snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        return openLspSymbolEntry(entry)
    }

    @discardableResult
    func showLspSymbolHistory() -> Bool {
        guard lspSymbolResultStore.historyEntries.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            guard let entry = lspSymbolResultStore.historyEntries.last else { return false }
            return openLspSymbolEntry(entry)
        }

        let entries = Array(lspSymbolResultStore.historyEntries.reversed())
        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.symbol_history.\(idx)",
                title: entry.title
            ) { [weak self] in
                _ = self?.openLspSymbolEntry(entry)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.SymbolHistory",
            commandsProvider: { commands }
        )
        lspSymbolResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter symbol history...")
        return true
    }

    @discardableResult
    func showLspSymbolPanel() -> Bool {
        guard let entry = lspSymbolResultStore.currentEntry, entry.snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        let snapshot = entry.snapshot
        guard let window = view.window else {
            return openLspSymbolEntry(entry)
        }
        let controller = lspSymbolPanelController ?? AttoLspSymbolPanelController(
            titleForSymbol: { [weak self] symbol in
                self?.displayTitle(for: symbol) ?? symbol.name
            },
            onOpen: { [weak self] target in
                self?.navigateToLspTarget(target)
            }
        )
        lspSymbolPanelController = controller
        return controller.show(relativeTo: window, snapshot: snapshot)
    }

    private func handleLspSymbolResultJSON(_ json: String, kind: LspSymbolRequestKind, tab: AttoEditorTab) -> Bool {
        let symbols: [AttoLspSymbolParser.Symbol]
        let placeholder: String
        let title: String

        switch kind {
        case .document:
            try? tab.editCore.editor.lspApplyDocumentSymbolsJSON(json)
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            let text = (try? tab.editCore.editor.text()) ?? ""
            let typedSymbols = AttoLspSymbolParser.documentSymbols(
                snapshot: derivedStateStore.active.documentSymbols,
                documentURI: tab.fileURL.absoluteString,
                documentText: text
            )
            if typedSymbols.isEmpty {
                symbols = AttoLspSymbolParser.documentSymbols(
                    fromResultJSON: json,
                    documentURI: tab.fileURL.absoluteString
                )
            } else {
                symbols = typedSymbols
            }
            placeholder = "Filter document symbols..."
            title = "Document Symbols"

        case .workspace(let query):
            symbols = AttoLspSymbolParser.workspaceSymbols(fromResultJSON: json)
            placeholder = "Filter workspace symbols..."
            title = workspaceSymbolTitle(query: query)
        }

        if symbols.isEmpty {
            showWorkspaceEditPopover(
                text: AttoLspSymbolRequestFeedback.emptyMessage(kind: kind.feedbackKind, query: kind.query),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }

        let snapshot = LspSymbolResultSnapshot(title: title, symbols: symbols, placeholder: placeholder)
        recordLspSymbolResultSnapshot(snapshot)
        showLspSymbolResults(symbols, placeholder: placeholder)
        return true
    }

    private func recordLspSymbolResultSnapshot(_ snapshot: LspSymbolResultSnapshot) {
        let entry = lspSymbolResultStore.record(
            snapshot,
            family: "symbols",
            title: symbolHistoryTitle(for: snapshot)
        )
        recordLspResultLifecycleEvent(
            entry,
            payload: .symbols(title: snapshot.title, itemCount: snapshot.symbols.count)
        )
        lspSymbolPanelController?.update(snapshot: snapshot)
    }

    @discardableResult
    private func openLspSymbolSnapshot(_ snapshot: LspSymbolResultSnapshot) -> Bool {
        guard snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        lspSymbolResultStore.makeCurrent(
            snapshot,
            family: "symbols",
            title: symbolHistoryTitle(for: snapshot)
        )
        showLspSymbolResults(snapshot.symbols, placeholder: snapshot.placeholder)
        return true
    }

    @discardableResult
    private func openLspSymbolEntry(_ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>) -> Bool {
        let snapshot = entry.snapshot
        guard snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        lspSymbolResultStore.makeCurrent(entry)
        showLspSymbolResults(snapshot.symbols, placeholder: snapshot.placeholder)
        return true
    }

    private func symbolHistoryTitle(for snapshot: LspSymbolResultSnapshot) -> String {
        "\(snapshot.title): \(snapshot.symbols.count) results"
    }

    private func workspaceSymbolTitle(query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? "Workspace Symbols" : "Workspace Symbols: \(trimmedQuery)"
    }

    private func showLspSymbolResults(_ symbols: [AttoLspSymbolParser.Symbol], placeholder: String) {
        guard symbols.isEmpty == false else {
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            navigateToLspTarget(symbols[0].target)
            return
        }

        let commands = symbols.enumerated().map { idx, symbol in
            AttoCommandPaletteCommand(
                id: "lsp.symbol.\(idx)",
                title: displayTitle(for: symbol),
                group: AttoLspSymbolParser.kindGroupLabel(for: symbol)
            ) { [weak self] in
                self?.navigateToLspTarget(symbol.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.SymbolResults",
            commandsProvider: { commands }
        )
        lspSymbolResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
    }

    private func displayTitle(for symbol: AttoLspSymbolParser.Symbol) -> String {
        let indent = String(repeating: "  ", count: symbol.depth)
        let detail = symbol.detail.map { " \($0)" } ?? ""
        let kind = symbol.kindLabel.map { " [\($0)]" } ?? ""
        let container = symbol.containerName.map { " — \($0)" } ?? ""
        let location = displayTitle(for: symbol.target)
        return "\(indent)\(symbol.name)\(detail)\(kind)\(container) — \(location)"
    }

    // MARK: - LSP hierarchy quick panels

    @discardableResult
    func showIncomingCallsInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .callIncoming)
    }

    @discardableResult
    func showOutgoingCallsInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .callOutgoing)
    }

    @discardableResult
    func showTypeSupertypesInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .typeSupertypes)
    }

    @discardableResult
    func showTypeSubtypesInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .typeSubtypes)
    }

    private func requestLspHierarchyAtPrimaryCaret(kind: LspHierarchyRequestKind) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        let position: (line: UInt32, column: UInt32)
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        } catch {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            if kind.isCallHierarchy {
                _ = try tab.editCore.editor.lspRequestPrepareCallHierarchy(
                    logicalLine: position.line,
                    logicalColumn: position.column
                )
            } else {
                _ = try tab.editCore.editor.lspRequestPrepareTypeHierarchy(
                    logicalLine: position.line,
                    logicalColumn: position.column
                )
            }
        } catch {
            cancelHierarchyUI()
            NSSound.beep()
            return false
        }

        hierarchyPrepareContext = HierarchyPrepareContext(tabID: tab.id, kind: kind)
        startHierarchyPreparePollTimer(tabID: tab.id)
        return true
    }

    private func startHierarchyPreparePollTimer(tabID: UUID) {
        hierarchyPreparePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.hierarchyPrepareContext, ctx.tabID == tabID else {
                self.cancelHierarchyUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelHierarchyUI()
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHierarchyUI()
                return
            }

            let json: String?
            do {
                if ctx.kind.isCallHierarchy {
                    json = try tab.editCore.editor.lspTakeLastPrepareCallHierarchyResultJSON()
                } else {
                    json = try tab.editCore.editor.lspTakeLastPrepareTypeHierarchyResultJSON()
                }
            } catch {
                return
            }
            guard let json else { return }

            self.hierarchyPreparePollTimer?.cancel()
            self.hierarchyPreparePollTimer = nil
            self.hierarchyPrepareContext = nil
            self.handleHierarchyPrepareResultJSON(json, kind: ctx.kind, tab: tab)
            timer.cancel()
        }

        hierarchyPreparePollTimer = timer
        timer.resume()
    }

    private func handleHierarchyPrepareResultJSON(
        _ json: String,
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab
    ) {
        let items = kind.isCallHierarchy
            ? AttoLspHierarchyParser.prepareCallItems(fromResultJSON: json)
            : AttoLspHierarchyParser.prepareTypeItems(fromResultJSON: json)
        guard items.isEmpty == false else {
            cancelHierarchyUI()
            NSSound.beep()
            return
        }

        if items.count == 1 {
            _ = requestHierarchyChildren(for: items[0], kind: kind, tab: tab)
            return
        }

        showHierarchyRootResults(items, kind: kind, tab: tab)
    }

    private func showHierarchyRootResults(
        _ items: [AttoLspHierarchyParser.Item],
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab
    ) {
        guard let window = view.window else {
            if let first = items.first {
                _ = requestHierarchyChildren(for: first, kind: kind, tab: tab)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.hierarchy.root.\(idx)",
                title: displayTitle(for: item)
            ) { [weak self, weak tab] in
                guard let self, let tab, self.activeTab?.id == tab.id else { return }
                _ = self.requestHierarchyChildren(for: item, kind: kind, tab: tab)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.HierarchyRoots",
            commandsProvider: { commands }
        )
        hierarchyResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter hierarchy roots...")
    }

    @discardableResult
    private func requestHierarchyChildren(
        for item: AttoLspHierarchyParser.Item,
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab
    ) -> Bool {
        hierarchyResultsController?.hide()
        hierarchyResultsController = nil

        do {
            switch kind {
            case .callIncoming:
                _ = try tab.editCore.editor.lspRequestCallHierarchyIncomingCalls(itemJSON: item.requestJSON)
            case .callOutgoing:
                _ = try tab.editCore.editor.lspRequestCallHierarchyOutgoingCalls(itemJSON: item.requestJSON)
            case .typeSupertypes:
                _ = try tab.editCore.editor.lspRequestTypeHierarchySupertypes(itemJSON: item.requestJSON)
            case .typeSubtypes:
                _ = try tab.editCore.editor.lspRequestTypeHierarchySubtypes(itemJSON: item.requestJSON)
            }
        } catch {
            cancelHierarchyUI()
            NSSound.beep()
            return false
        }

        hierarchyChildrenContext = HierarchyChildrenContext(tabID: tab.id, kind: kind)
        startHierarchyChildrenPollTimer(tabID: tab.id)
        return true
    }

    private func startHierarchyChildrenPollTimer(tabID: UUID) {
        hierarchyChildrenPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.hierarchyChildrenContext, ctx.tabID == tabID else {
                self.cancelHierarchyUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelHierarchyUI()
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHierarchyUI()
                return
            }

            let json: String?
            do {
                switch ctx.kind {
                case .callIncoming:
                    json = try tab.editCore.editor.lspTakeLastCallHierarchyIncomingCallsResultJSON()
                case .callOutgoing:
                    json = try tab.editCore.editor.lspTakeLastCallHierarchyOutgoingCallsResultJSON()
                case .typeSupertypes:
                    json = try tab.editCore.editor.lspTakeLastTypeHierarchySupertypesResultJSON()
                case .typeSubtypes:
                    json = try tab.editCore.editor.lspTakeLastTypeHierarchySubtypesResultJSON()
                }
            } catch {
                return
            }
            guard let json else { return }

            self.hierarchyChildrenPollTimer?.cancel()
            self.hierarchyChildrenPollTimer = nil
            self.hierarchyChildrenContext = nil
            _ = self.showHierarchyResultJSONInActiveTab(json, kind: ctx.kind)
            timer.cancel()
        }

        hierarchyChildrenPollTimer = timer
        timer.resume()
    }

    @discardableResult
    private func showHierarchyResultJSONInActiveTab(_ json: String, kind: LspHierarchyRequestKind) -> Bool {
        let entries: [AttoLspHierarchyParser.Entry]
        switch kind {
        case .callIncoming:
            entries = AttoLspHierarchyParser.incomingCalls(fromResultJSON: json)
        case .callOutgoing:
            entries = AttoLspHierarchyParser.outgoingCalls(fromResultJSON: json)
        case .typeSupertypes, .typeSubtypes:
            entries = AttoLspHierarchyParser.typeHierarchyEntries(fromResultJSON: json)
        }

        return showHierarchyResults(entries, placeholder: kind.resultPlaceholder)
    }

    @discardableResult
    private func showHierarchyResults(
        _ entries: [AttoLspHierarchyParser.Entry],
        placeholder: String
    ) -> Bool {
        guard entries.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            navigateToLspTarget(entries[0].target)
            return true
        }

        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.hierarchy.\(idx)",
                title: displayTitle(for: entry)
            ) { [weak self] in
                self?.navigateToLspTarget(entry.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.HierarchyResults",
            commandsProvider: { commands }
        )
        hierarchyResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
        return true
    }

    private func displayTitle(for item: AttoLspHierarchyParser.Item) -> String {
        let detail = item.detail.map { " \($0)" } ?? ""
        let kind = item.kindLabel.map { " [\($0)]" } ?? ""
        let location = displayTitle(for: item.target)
        return "\(item.name)\(detail)\(kind) — \(location)"
    }

    private func displayTitle(for entry: AttoLspHierarchyParser.Entry) -> String {
        let detail = entry.detail.map { " \($0)" } ?? ""
        let kind = entry.kindLabel.map { " [\($0)]" } ?? ""
        let ranges = entry.relatedRangeCount.map { count in
            count == 1 ? " (1 range)" : " (\(count) ranges)"
        } ?? ""
        let location = displayTitle(for: entry.target)
        return "\(entry.name)\(detail)\(kind)\(ranges) — \(location)"
    }

    // MARK: - Problems quick panel

    @discardableResult
    func showProblemsInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let problems = unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true).problems
        guard problems.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            navigateToDiagnosticProblem(problems[0], in: tab)
            return true
        }

        let commands = problems.enumerated().map { idx, problem in
            AttoCommandPaletteCommand(
                id: "lsp.problem.\(idx)",
                title: displayTitle(for: problem, in: tab)
            ) { [weak self] in
                guard let self, let current = self.activeTab, current.id == tab.id else { return }
                self.navigateToDiagnosticProblem(problem, in: current)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.Problems",
            commandsProvider: { commands }
        )
        problemsResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter problems...")
        return true
    }

    @discardableResult
    func showProblemsPanelInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        problemsResultsController?.hide()
        problemsResultsController = nil

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let problems = unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true).problems

        guard let window = view.window else {
            if let first = problems.first {
                navigateToDiagnosticProblem(first, in: tab)
                return true
            }
            NSSound.beep()
            return false
        }

        let controller = problemsPanelController ?? AttoProblemsPanelController(
            titleForProblem: { [weak self] problem in
                guard let self, let tab = self.activeTab else { return problem.message }
                return self.displayTitle(for: problem, in: tab)
            },
            onOpen: { [weak self] problem in
                guard let self, let tab = self.activeTab else { return }
                self.navigateToDiagnosticProblem(problem, in: tab)
            }
        )
        problemsPanelController = controller
        return controller.show(relativeTo: window, problems: problems)
    }

    private func displayTitle(for diagnostic: EcuDiagnostic, in tab: AttoEditorTab) -> String {
        let location: String = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: diagnostic.range.start)
                return "\(tab.fileURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return tab.fileURL.lastPathComponent
            }
        }()

        let severity = diagnostic.severity.map { "[\($0.rawValue)] " } ?? ""
        let source = diagnostic.source.map { " (\($0))" } ?? ""
        return "\(severity)\(diagnostic.message)\(source) — \(location)"
    }

    private func displayTitle(for problem: AttoUnifiedDiagnosticProblem, in tab: AttoEditorTab) -> String {
        switch problem.target {
        case let .active(diagnostic):
            return displayTitle(for: diagnostic, in: tab)
        case let .workspace(diagnostic):
            return displayTitle(for: diagnostic)
        }
    }

    private func navigateToDiagnosticProblem(_ problem: AttoUnifiedDiagnosticProblem, in tab: AttoEditorTab) {
        switch problem.target {
        case let .active(diagnostic):
            navigateToDiagnostic(diagnostic, in: tab)
        case let .workspace(diagnostic):
            navigateToLspTarget(diagnostic.target)
        }
    }

    private func navigateToDiagnosticProblem(_ problem: AttoUnifiedDiagnosticProblem) {
        switch problem.target {
        case let .active(diagnostic):
            guard let tab = activeTab else {
                NSSound.beep()
                return
            }
            navigateToDiagnostic(diagnostic, in: tab)
        case let .workspace(diagnostic):
            navigateToLspTarget(diagnostic.target)
        }
    }

    private func navigateToDiagnostic(_ diagnostic: EcuDiagnostic, in tab: AttoEditorTab) {
        do {
            tab.editCore.layoutSubtreeIfNeeded()
            let start = min(diagnostic.range.start, diagnostic.range.end)
            let end = max(diagnostic.range.start, diagnostic.range.end)
            let selectionEnd = start == end ? start : end
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: start, end: selectionEnd)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Workspace diagnostics quick panel

    @discardableResult
    func showWorkspaceDiagnosticsInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(text: "Workspace diagnostics require an active LSP server.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelWorkspaceDiagnosticsUI()

        do {
            _ = try tab.editCore.editor.lspRequestWorkspaceDiagnostic(
                previousResultIdsJSON: workspaceProblemsStore.previousResultIdsJSON()
            )
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Workspace diagnostics request failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        workspaceDiagnosticsContext = WorkspaceDiagnosticsRequestContext(tabID: tab.id, showFeedback: showFeedback)
        workspaceDiagnosticsStaleReason = .workspaceRefreshRequested
        recordWorkspaceDiagnosticsLifecycle(problems: workspaceDiagnosticProblems())
        startWorkspaceDiagnosticsPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showWorkspaceDiagnosticsResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let snapshot = workspaceProblemsStore.apply(resultJSON: json)
        workspaceDiagnosticsStaleReason = nil
        recordWorkspaceDiagnosticsLifecycle(
            problems: AttoDiagnosticsModel.workspaceProblems(snapshot.diagnostics)
        )
        updateWorkspaceDiagnosticMarkersForOpenTabs()
        updateWorkspaceProblemsPanelIfVisible()
        updateStatusBar()
        guard snapshot.diagnostics.isEmpty == false else {
            if showFeedback {
                showWorkspaceEditPopover(text: "No workspace diagnostics are available.", in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        showWorkspaceDiagnosticResults(snapshot.diagnostics)
        return true
    }

    private func startWorkspaceDiagnosticsPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        workspaceDiagnosticsPollTimer?.cancel()

        var remainingTicks = 80 // ~4s at 50ms; workspace diagnostics can fan out across files.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.workspaceDiagnosticsContext, ctx.tabID == tabID else {
                self.cancelWorkspaceDiagnosticsUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelWorkspaceDiagnosticsUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Workspace diagnostics request timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelWorkspaceDiagnosticsUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastWorkspaceDiagnosticResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let showFeedback = ctx.showFeedback
            self.workspaceDiagnosticsPollTimer?.cancel()
            self.workspaceDiagnosticsPollTimer = nil
            self.workspaceDiagnosticsContext = nil
            _ = self.showWorkspaceDiagnosticsResultJSONInActiveTab(json, showFeedback: showFeedback)
            timer.cancel()
        }

        workspaceDiagnosticsPollTimer = timer
        timer.resume()
    }

    private func showWorkspaceDiagnosticResults(_ diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic]) {
        guard diagnostics.isEmpty == false else {
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            navigateToLspTarget(diagnostics[0].target)
            return
        }

        let commands = diagnostics.enumerated().map { idx, diagnostic in
            AttoCommandPaletteCommand(
                id: "lsp.workspace_diagnostic.\(idx)",
                title: displayTitle(for: diagnostic)
            ) { [weak self] in
                self?.navigateToLspTarget(diagnostic.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.WorkspaceDiagnostics",
            commandsProvider: { commands }
        )
        workspaceDiagnosticsResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter workspace diagnostics...")
    }

    @discardableResult
    func showWorkspaceProblemsPanelInActiveTab() -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        workspaceDiagnosticsResultsController?.hide()
        workspaceDiagnosticsResultsController = nil

        let problems = workspaceDiagnosticProblems()
        guard let window = view.window else {
            if let first = problems.first {
                navigateToDiagnosticProblem(first)
                return true
            }
            NSSound.beep()
            return false
        }

        let controller = workspaceProblemsPanelController ?? AttoProblemsPanelController(
            titleForProblem: { [weak self] problem in
                guard let self else { return problem.message }
                return self.displayTitle(for: problem)
            },
            onOpen: { [weak self] problem in
                self?.navigateToDiagnosticProblem(problem)
            },
            accessibilityIDs: .workspaceProblems
        )
        workspaceProblemsPanelController = controller
        return controller.show(
            relativeTo: window,
            problems: problems,
            title: "Workspace Problems",
            placeholder: "Filter workspace problems..."
        )
    }

    private func updateWorkspaceProblemsPanelIfVisible() {
        guard workspaceProblemsPanelController?.isVisible == true else { return }
        workspaceProblemsPanelController?.update(
            problems: workspaceDiagnosticProblems(),
            title: "Workspace Problems",
            placeholder: "Filter workspace problems..."
        )
    }

    private func workspaceDiagnosticProblems() -> [AttoUnifiedDiagnosticProblem] {
        AttoDiagnosticsModel.workspaceProblems(workspaceProblemsStore.diagnostics)
    }

    private func displayTitle(for diagnostic: AttoLspWorkspaceDiagnosticsParser.Diagnostic) -> String {
        let severity = diagnostic.severityLabel.map { "[\($0)] " } ?? ""
        let code = diagnostic.code.map { " [\($0)]" } ?? ""
        let source = diagnostic.source.map { " (\($0))" } ?? ""
        let location = displayTitle(for: diagnostic.target)
        return "\(severity)\(diagnostic.message)\(code)\(source) — \(location)"
    }

    private func displayTitle(for problem: AttoUnifiedDiagnosticProblem) -> String {
        switch problem.target {
        case let .active(diagnostic):
            guard let tab = activeTab else { return diagnostic.message }
            return displayTitle(for: diagnostic, in: tab)
        case let .workspace(diagnostic):
            return displayTitle(for: diagnostic)
        }
    }

    // MARK: - LSP completion

    @discardableResult
    func showCompletionsInActiveTab() -> Bool {
        showCompletionsInActiveTab(beepOnFailure: true)
    }

    @discardableResult
    private func showCompletionsInActiveTab(beepOnFailure: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let context = try completionRequestContextForCurrentSelection(tab, beepOnFailure: beepOnFailure)
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestCompletion(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )

            completionContext = context
            startCompletionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            if beepOnFailure { NSSound.beep() }
            return false
        }
    }

    private func completionRequestContextForCurrentSelection(
        _ tab: AttoEditorTab,
        beepOnFailure: Bool = false
    ) throws -> CompletionRequestContext {
        let offsets = try tab.editCore.editor.selectionOffsets()
        let text = try tab.editCore.editor.text()
        let fallback: (start: UInt32, end: UInt32) = {
            let start = min(offsets.start, offsets.end)
            let end = max(offsets.start, offsets.end)
            if start != end {
                return (start, end)
            }
            return AttoLspCompletionParser.identifierFallbackRange(in: text, caretOffset: offsets.end)
        }()
        return CompletionRequestContext(
            tabID: tab.id,
            fallbackStart: fallback.start,
            fallbackEnd: fallback.end,
            beepOnFailure: beepOnFailure
        )
    }

    private func startCompletionPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        completionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.completionContext, ctx.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCompletionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCompletionResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let items = AttoLspCompletionParser.items(fromCompletionResultJSON: json)
            self.completionPollTimer?.cancel()
            self.completionPollTimer = nil
            self.completionContext = nil
            _ = self.showCompletionList(items: items, context: ctx, editorView: editorView)
            timer.cancel()
        }

        completionPollTimer = timer
        timer.resume()
    }

    @discardableResult
    private func showCompletionList(
        items: [AttoLspCompletionParser.Item],
        context: CompletionRequestContext,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        guard items.isEmpty == false else {
            cancelCompletionUI()
            if context.beepOnFailure { NSSound.beep() }
            return false
        }
        recordCompletionResultLifecycle(items: items)
        guard editorView.window != nil else { return false }

        let controller = AttoCompletionListController()
        completionListController = controller
        completionListContext = context
        controller.onTextInput = { [weak self, weak controller] text in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterTextInput(text, tabID: context.tabID)
        }
        controller.onDeleteBackward = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterDeleteBackward(tabID: context.tabID)
        }
        controller.onDismiss = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return }
            self.completionListController = nil
            self.completionListContext = nil
        }
        controller.show(
            items: items,
            relativeTo: editorView,
            anchorRect: caretAnchorRect(in: editorView)
        ) { [weak self] item, commitCharacter in
            self?.applyCompletion(item, context: context, commitCharacter: commitCharacter)
        }
        return true
    }

    private func recordCompletionResultLifecycle(items: [AttoLspCompletionParser.Item]) {
        lspResultEventStream.record(
            family: "completion",
            title: items.count == 1 ? "Completion: 1 item" : "Completion: \(items.count) items",
            payload: .completion(itemCount: items.count)
        )
    }

    @discardableResult
    private func handleCompletionFilterTextInput(_ text: String, tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    @discardableResult
    private func handleCompletionFilterDeleteBackward(tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    private func refreshCompletionFilter(tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID,
              let context = completionListContext,
              let controller = completionListController
        else {
            return
        }

        guard let prefix = completionFilterPrefix(context: context, editor: tab.editCore.editor) else {
            cancelCompletionUI()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return
        }

        if controller.updateFilter(
            prefix: prefix,
            relativeTo: tab.editCore.editorView,
            anchorRect: caretAnchorRect(in: tab.editCore.editorView)
        ) == false {
            view.window?.makeFirstResponder(tab.editCore.editorView)
        }
    }

    private func completionFilterPrefix(context: CompletionRequestContext, editor: EditorUI) -> String? {
        guard let offsets = try? editor.selectionOffsets() else { return nil }
        guard offsets.start == offsets.end else { return nil }
        guard offsets.end >= context.fallbackStart else { return nil }
        guard let text = try? editor.text() else { return nil }
        return AttoLspCompletionParser.completionPrefix(
            in: text,
            start: context.fallbackStart,
            caretOffset: offsets.end
        )
    }

    private func applyCompletion(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil
    ) {
        guard let tab = activeTab, tab.id == context.tabID else { return }

        guard completionItemResolveSupported(for: tab.editCore.editor) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        guard let itemJSON = AttoLspCompletionParser.rawJSON(for: item) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        do {
            _ = try tab.editCore.editor.lspRequestCompletionItemResolve(itemJSON: itemJSON)
            completionResolveContext = CompletionResolveContext(
                request: context,
                item: item,
                commitCharacter: commitCharacter
            )
            completionListController?.hide()
            completionListController = nil
            startCompletionResolvePollTimer(tabID: tab.id)
        } catch {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
        }
    }

    private func completionItemResolveSupported(for editor: EditorUI) -> Bool {
        guard let status = try? editor.lspStatusSnapshot() else { return true }
        return status.capabilities?.completionItemResolve ?? true
    }

    private func startCompletionResolvePollTimer(tabID: UUID) {
        completionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.completionResolveContext, ctx.request.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                self.finishCompletionResolve(
                    with: ctx.item,
                    fallback: ctx.item,
                    context: ctx.request,
                    commitCharacter: ctx.commitCharacter,
                    timer: timer
                )
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCompletionItemResolveResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let resolved = AttoLspCompletionParser.item(fromCompletionItemJSON: json) ?? ctx.item
            self.finishCompletionResolve(
                with: resolved,
                fallback: ctx.item,
                context: ctx.request,
                commitCharacter: ctx.commitCharacter,
                timer: timer
            )
        }

        completionResolvePollTimer = timer
        timer.resume()
    }

    private func finishCompletionResolve(
        with item: AttoLspCompletionParser.Item,
        fallback: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String?,
        timer: DispatchSourceTimer
    ) {
        completionResolvePollTimer = nil
        completionResolveContext = nil
        timer.cancel()

        if applyCompletionItem(
            item,
            context: context,
            commitCharacter: commitCharacter,
            beepOnFailure: false
        ) == false {
            _ = applyCompletionItem(
                fallback,
                context: context,
                commitCharacter: commitCharacter,
                beepOnFailure: true
            )
        }
    }

    @discardableResult
    private func applyCompletionItem(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard let tab = activeTab, tab.id == context.tabID else { return false }

        do {
            let text = try tab.editCore.editor.text()
            guard let plan = AttoLspCompletionParser.applicationPlan(
                for: item,
                documentText: text,
                fallbackStart: context.fallbackStart,
                fallbackEnd: context.fallbackEnd
            ) else {
                if beepOnFailure {
                    NSSound.beep()
                }
                return false
            }

            if plan.isSnippet {
                _ = try tab.editCore.editor.applySnippet(
                    start: plan.start,
                    end: plan.end,
                    snippet: plan.text,
                    additionalEdits: plan.additionalEdits
                )
            } else {
                let edits = [EcuTextEdit(start: plan.start, end: plan.end, text: plan.text)] + plan.additionalEdits
                _ = try tab.editCore.editor.applyTextEdits(edits)
            }
            var didCommitCharacter = false
            if let commitCharacter {
                do {
                    try tab.editCore.editor.commitText(commitCharacter)
                    didCommitCharacter = true
                } catch {
                    if beepOnFailure {
                        NSSound.beep()
                    }
                }
            }

            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            if let commitCharacter, didCommitCharacter {
                handleCommittedTextForLspTriggers(commitCharacter, tabID: tab.id)
            }
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
    }

    // MARK: - LSP code lens

    @discardableResult
    func refreshCodeLensInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Code lens is unavailable.\nLSP is not enabled for this document.",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            _ = try tab.editCore.editor.lspRequestCodeLens()
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Code lens refresh failed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        codeLensRefreshContext = CodeLensRefreshContext(tabID: tab.id, showFeedback: showFeedback)
        tab.editCore.editorView.kickProcessingPoll()
        updateStatusBar()
        startCodeLensRefreshPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showCodeLensActionsInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelCodeLensUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let items = AttoLspCodeLensParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
        guard items.isEmpty == false else {
            NSSound.beep()
            return false
        }

        showCodeLensResults(items, tab: tab)
        return true
    }

    @discardableResult
    func showCodeLensActionsAtCursorInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelCodeLensUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let items = AttoLspCodeLensParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
        let currentLineItems = codeLensItemsOnPrimaryCaretLine(items, in: tab)
        guard currentLineItems.isEmpty == false else {
            NSSound.beep()
            return false
        }

        showCodeLensResults(
            currentLineItems,
            tab: tab,
            placeholder: "Filter current-line code lens actions..."
        )
        return true
    }

    private func codeLensItemsOnPrimaryCaretLine(
        _ items: [AttoLspCodeLensParser.Item],
        in tab: AttoEditorTab
    ) -> [AttoLspCodeLensParser.Item] {
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let caret = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return items.filter { item in
                guard let pos = try? tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start) else {
                    return false
                }
                return pos.line == caret.line
            }
        } catch {
            return []
        }
    }

    private func showCodeLensResults(
        _ items: [AttoLspCodeLensParser.Item],
        tab: AttoEditorTab,
        placeholder: String = "Filter code lens actions..."
    ) {
        guard let window = view.window else {
            if let first = items.first {
                _ = applyCodeLens(first)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_lens.\(idx)",
                title: displayTitle(for: item, in: tab)
            ) { [weak self] in
                _ = self?.applyCodeLens(item)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.CodeLens",
            commandsProvider: { commands }
        )
        codeLensResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
    }

    @discardableResult
    private func handleCodeLensClick(json: String, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let item = AttoLspCodeLensParser.item(fromCodeLensJSON: json) else {
            NSSound.beep()
            return false
        }
        cancelHoverUI()
        return applyCodeLens(item)
    }

    @discardableResult
    private func applyCodeLens(_ item: AttoLspCodeLensParser.Item, allowResolve: Bool = true) -> Bool {
        if let command = item.command {
            return requestExecuteCommandJSON(command.commandJSON, commandTitle: command.title)
        }

        guard allowResolve else {
            NSSound.beep()
            return false
        }
        return requestCodeLensResolve(item)
    }

    private func requestCodeLensResolve(_ item: AttoLspCodeLensParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestCodeLensResolve(lensJSON: item.lensJSON)
            codeLensResolveContext = CodeLensResolveContext(tabID: tab.id, item: item)
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            startCodeLensResolvePollTimer(tabID: tab.id)
            return true
        } catch {
            cancelCodeLensUI()
            NSSound.beep()
            return false
        }
    }

    private func startCodeLensResolvePollTimer(tabID: UUID) {
        codeLensResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeLensResolveContext, ctx.tabID == tabID else {
                self.cancelCodeLensUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeLensUI()
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeLensUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeLensResolveResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.codeLensResolvePollTimer?.cancel()
            self.codeLensResolvePollTimer = nil
            self.codeLensResolveContext = nil

            let resolved = AttoLspCodeLensParser.item(
                fromCodeLensJSON: json,
                fallbackTitle: ctx.item.title,
                fallbackRange: ctx.item.range
            ) ?? ctx.item
            _ = self.applyCodeLens(resolved, allowResolve: false)
            timer.cancel()
        }

        codeLensResolvePollTimer = timer
        timer.resume()
    }

    private func startCodeLensRefreshPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        codeLensRefreshPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.codeLensRefreshContext, ctx.tabID == tabID else {
                self.cancelCodeLensUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelCodeLensUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(text: "Code lens refresh timed out.", in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeLensUI()
                return
            }

            do {
                _ = try tab.editCore.editor.pollProcessing()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelCodeLensUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Code lens refresh failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeLensResultJSON()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelCodeLensUI()
                if showFeedback {
                    self.showWorkspaceEditPopover(
                        text: "Code lens refresh failed.\n\(error.localizedDescription)",
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let json else { return }

            let showFeedback = ctx.showFeedback
            self.cancelCodeLensUI()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            self.derivedStateStore.refreshActive(editor: tab.editCore.editor)
            self.updateStatusBar()

            guard showFeedback else { return }
            if let errorMessage = Self.codeLensResultErrorMessage(json) {
                self.showWorkspaceEditPopover(
                    text: "Code lens refresh failed.\n\(errorMessage)",
                    in: editorView
                )
                NSSound.beep()
                return
            }
            let count = Self.codeLensResultCount(json) ?? 0
            let text: String
            if count == 0 {
                text = "No code lens actions are available."
            } else if count == 1 {
                text = "Code lens refreshed.\n1 action is available."
            } else {
                text = "Code lens refreshed.\n\(count) actions are available."
            }
            self.showWorkspaceEditPopover(text: text, in: editorView)
        }

        codeLensRefreshPollTimer = timer
        timer.resume()
    }

    private static func codeLensResultCount(_ json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        if root is NSNull {
            return 0
        }
        return (root as? [Any])?.count
    }

    private static func codeLensResultErrorMessage(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else {
            return nil
        }
        if let message = error["message"] as? String, message.isEmpty == false {
            return message
        }
        return "Unknown LSP error."
    }

    private func displayTitle(for item: AttoLspCodeLensParser.Item, in tab: AttoEditorTab) -> String {
        let location: String? = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start)
                return "\(tab.fileURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return tab.fileURL.lastPathComponent
            }
        }()
        return AttoLspCodeLensParser.displayTitle(for: item, location: location)
    }

    // MARK: - LSP code actions

    @discardableResult
    func showCodeActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: [])
    }

    @discardableResult
    func showQuickFixesInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["quickfix"])
    }

    @discardableResult
    func showRefactorActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["refactor"])
    }

    @discardableResult
    func showSourceActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source"])
    }

    @discardableResult
    func organizeImportsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.organizeImports"])
    }

    @discardableResult
    func fixAllInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.fixAll"])
    }

    @discardableResult
    private func showCodeActionsInActiveTab(onlyKinds: [String]) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let start = min(offsets.start, offsets.end)
            let end = max(offsets.start, offsets.end)
            let contextJSON = codeActionContextJSON(
                editor: tab.editCore.editor,
                startOffset: start,
                endOffset: end,
                onlyKinds: onlyKinds
            )
            _ = try tab.editCore.editor.lspRequestCodeAction(
                startOffset: start,
                endOffset: end,
                contextJSON: contextJSON
            )
            codeActionContext = CodeActionRequestContext(tabID: tab.id, onlyKinds: onlyKinds)
            startCodeActionPollTimer(tabID: tab.id)
            return true
        } catch {
            cancelCodeActionUI()
            NSSound.beep()
            return false
        }
    }

    private func codeActionContextJSON(
        editor: EditorUI,
        startOffset: UInt32,
        endOffset: UInt32,
        onlyKinds: [String]
    ) -> String {
        derivedStateStore.refreshActive(editor: editor)
        let text = (try? editor.text()) ?? ""
        return AttoLspCodeActionContext.contextJSON(
            diagnostics: derivedStateStore.active.diagnostics,
            documentText: text,
            selectionStart: startOffset,
            selectionEnd: endOffset,
            onlyKinds: onlyKinds
        )
    }

    private func startCodeActionPollTimer(tabID: UUID) {
        codeActionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeActionContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeActionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeActionResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let items = AttoLspCodeActionParser.filteredItems(
                AttoLspCodeActionParser.items(fromCodeActionResultJSON: json),
                onlyKinds: ctx.onlyKinds
            )
            self.codeActionPollTimer?.cancel()
            self.codeActionPollTimer = nil
            self.codeActionContext = nil
            _ = self.showCodeActionResults(items, onlyKinds: ctx.onlyKinds)
            timer.cancel()
        }

        codeActionPollTimer = timer
        timer.resume()
    }

    @discardableResult
    private func showCodeActionResults(
        _ items: [AttoLspCodeActionParser.Item],
        onlyKinds: [String]
    ) -> Bool {
        guard items.isEmpty == false else {
            cancelCodeActionUI()
            NSSound.beep()
            return false
        }

        recordCodeActionResultLifecycle(items: items, onlyKinds: onlyKinds)
        guard let window = view.window else {
            _ = applyCodeAction(items[0])
            return true
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_action.\(idx)",
                title: AttoLspCodeActionParser.displayTitle(for: item)
            ) { [weak self] in
                _ = self?.applyCodeAction(item)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.CodeActions",
            commandsProvider: { commands }
        )
        codeActionResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter code actions...")
        return true
    }

    private func recordCodeActionResultLifecycle(
        items: [AttoLspCodeActionParser.Item],
        onlyKinds: [String]
    ) {
        lspResultEventStream.record(
            family: "code_actions",
            title: codeActionResultTitle(itemCount: items.count, onlyKinds: onlyKinds),
            payload: .codeActions(onlyKinds: onlyKinds, itemCount: items.count)
        )
    }

    private func codeActionResultTitle(itemCount: Int, onlyKinds: [String]) -> String {
        let scope: String
        if onlyKinds.isEmpty {
            scope = "Code Actions"
        } else {
            scope = "Code Actions: \(onlyKinds.joined(separator: ", "))"
        }
        return itemCount == 1 ? "\(scope): 1 result" : "\(scope): \(itemCount) results"
    }

    @discardableResult
    private func applyCodeAction(_ item: AttoLspCodeActionParser.Item, allowResolve: Bool = true) -> Bool {
        guard item.disabledReason == nil else {
            NSSound.beep()
            return false
        }

        var didApply = false
        if let editJSON = AttoLspCodeActionParser.editJSON(for: item) {
            didApply = applyWorkspaceEditJSONToActiveTab(editJSON) || didApply
        }

        if let command = item.command {
            didApply = requestExecuteCodeActionCommand(command) || didApply
        }

        if didApply {
            return true
        }

        guard allowResolve, item.isLegacyCommand == false else {
            NSSound.beep()
            return false
        }
        return requestCodeActionResolve(item)
    }

    private func requestCodeActionResolve(_ item: AttoLspCodeActionParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let actionJSON = AttoLspCodeActionParser.rawJSON(for: item) else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestCodeActionResolve(actionJSON: actionJSON)
            codeActionResolveContext = CodeActionResolveContext(tabID: tab.id, item: item)
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            startCodeActionResolvePollTimer(tabID: tab.id)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func startCodeActionResolvePollTimer(tabID: UUID) {
        codeActionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeActionResolveContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeActionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeActionResolveResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.codeActionResolvePollTimer?.cancel()
            self.codeActionResolvePollTimer = nil
            self.codeActionResolveContext = nil
            let resolved = AttoLspCodeActionParser.item(fromCodeActionJSON: json) ?? ctx.item
            _ = self.applyCodeAction(resolved, allowResolve: false)
            timer.cancel()
        }

        codeActionResolvePollTimer = timer
        timer.resume()
    }

    private func requestExecuteCodeActionCommand(_ command: AttoLspCodeActionParser.Command) -> Bool {
        guard let commandJSON = AttoLspCodeActionParser.commandJSON(for: command) else {
            NSSound.beep()
            return false
        }
        return requestExecuteCommandJSON(commandJSON, commandTitle: command.title)
    }

    private func requestExecuteCommandJSON(_ commandJSON: String, commandTitle: String) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestExecuteCommand(commandJSON: commandJSON)
            executeCommandContext = ExecuteCommandRequestContext(tabID: tab.id, commandTitle: commandTitle)
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            startExecuteCommandPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func startExecuteCommandPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        executeCommandPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.executeCommandContext, ctx.tabID == tabID else {
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.showWorkspaceEditPopover(
                    text: AttoLspExecuteCommandFormatter.timeoutText(commandTitle: ctx.commandTitle),
                    in: editorView
                )
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastExecuteCommandResultJSON()
            } catch {
                self.showWorkspaceEditPopover(
                    text: "Command result could not be read.",
                    in: editorView
                )
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }
            guard let json else { return }

            self.showWorkspaceEditPopover(
                text: AttoLspExecuteCommandFormatter.displayText(
                    forResultJSON: json,
                    commandTitle: ctx.commandTitle
                ),
                in: editorView
            )
            self.cancelExecuteCommandUI()
            timer.cancel()
        }

        executeCommandPollTimer = timer
        timer.resume()
    }

    // MARK: - LSP rename

    @discardableResult
    func promptRenameSymbolInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        let fallbackSeed = renameDialogSeedInActiveTab()
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestPrepareRename(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
            renamePrepareContext = RenamePrepareContext(tabID: tab.id, fallbackSeed: fallbackSeed)
            startRenamePreparePollTimer(tabID: tab.id)
            return true
        } catch {
            return showRenameDialog(seed: fallbackSeed)
        }
    }

    @discardableResult
    private func showRenameDialog(seed: AttoLspRenameSupport.DialogSeed) -> Bool {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = seed.initialName
        field.placeholderString = seed.placeholder ?? "New symbol name"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Symbol"
        alert.informativeText = "Enter the new name for the symbol."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return renameSymbolInActiveTab(to: newName)
    }

    @discardableResult
    func renameSymbolInActiveTab(to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestRename(
                logicalLine: pos.line,
                logicalColumn: pos.column,
                newName: trimmed
            )
            renameContext = RenameRequestContext(tabID: tab.id, documentURI: tab.fileURL.absoluteString)
            startRenamePollTimer(tabID: tab.id)
            return true
        } catch {
            cancelRenameUI()
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyWorkspaceEditJSONToActiveTab(_ workspaceEditJSON: String, documentURI: String? = nil) -> Bool {
        guard let initialActiveTab = activeTab else {
            NSSound.beep()
            return false
        }

        guard let workspaceEdit = AttoWorkspaceEditParser.parse(workspaceEditJSON) else {
            NSSound.beep()
            return false
        }

        var documents = workspaceEdit.documents.map { document in
            AttoWorkspaceEditApplyResult.Document(
                uri: document.uri,
                editCount: document.edits.count,
                hasOverlappingEdits: document.hasOverlappingEdits
            )
        }
        for uri in workspaceEdit.unsupportedURIs where documents.contains(where: { $0.uri == uri }) == false {
            documents.append(
                AttoWorkspaceEditApplyResult.Document(
                    uri: uri,
                    editCount: 0,
                    hasOverlappingEdits: false
                )
            )
        }
        for operation in workspaceEdit.resourceOperations {
            for uri in operation.affectedURIs where documents.contains(where: { $0.uri == uri }) == false {
                documents.append(
                    AttoWorkspaceEditApplyResult.Document(
                        uri: uri,
                        editCount: 0,
                        hasOverlappingEdits: false
                    )
                )
            }
        }

        var appliedURIs: [String] = []
        var appliedEditCount = 0
        var appliedResourceOperationCount = 0
        var skippedURIs = Set(workspaceEdit.unsupportedURIs)

        for operation in workspaceEdit.resourceOperations {
            guard applyWorkspaceResourceOperation(operation) else {
                skippedURIs.formUnion(operation.affectedURIs)
                continue
            }

            appliedURIs.append(contentsOf: operation.affectedURIs)
            appliedResourceOperationCount += 1
        }

        for document in workspaceEdit.documents {
            guard document.edits.isEmpty == false else { continue }

            if document.hasOverlappingEdits {
                skippedURIs.insert(document.uri)
                continue
            }

            if let tab = tabForDocumentURI(document.uri) {
                do {
                    let resultJSON = try tab.editCore.editor.lspApplyWorkspaceEditJSON(
                        workspaceEditJSON,
                        documentURI: document.uri
                    )
                    let result = AttoWorkspaceEditApplyResult(json: resultJSON)
                    guard result.applied else {
                        skippedURIs.insert(document.uri)
                        continue
                    }

                    appliedURIs.append(document.uri)
                    appliedEditCount += result.appliedEditCount
                    refreshTabAfterWorkspaceEdit(tab)
                } catch {
                    skippedURIs.insert(document.uri)
                    NSLog(
                        "AttoEditor: failed to apply WorkspaceEdit to open document %@: %@",
                        document.uri,
                        String(describing: error)
                    )
                }
                continue
            }

            guard let url = Self.fileURL(fromDocumentURI: document.uri) else {
                skippedURIs.insert(document.uri)
                continue
            }

            guard applyWorkspaceEdit(document, toFileAt: url) else {
                skippedURIs.insert(document.uri)
                continue
            }

            appliedURIs.append(document.uri)
            appliedEditCount += document.edits.count
        }

        let result = AttoWorkspaceEditApplyResult(
            applied: (appliedEditCount + appliedResourceOperationCount) > 0,
            appliedURI: appliedURIs.first ?? documentURI ?? initialActiveTab.fileURL.absoluteString,
            appliedEditCount: appliedEditCount + appliedResourceOperationCount,
            skippedURIs: Array(skippedURIs).sorted(),
            documents: documents
        )

        let feedbackEditorView = activeTab?.editCore.editorView ?? initialActiveTab.editCore.editorView
        guard result.applied else {
            showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
            if result.skippedURIs.isEmpty == false {
                NSLog(
                    "AttoEditor: WorkspaceEdit was not applied; skipped URIs: %@",
                    result.skippedURIs.joined(separator: ", ")
                )
            }
            NSSound.beep()
            return false
        }

        if result.skippedURIs.isEmpty == false {
            NSLog(
                "AttoEditor: WorkspaceEdit partially applied; skipped URIs: %@",
                result.skippedURIs.joined(separator: ", ")
            )
        }

        updateStatusBar()
        showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
        if let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        }
        return true
    }

    private func showWorkspaceEditSummaryIfNeeded(
        _ result: AttoWorkspaceEditApplyResult,
        editorView: EditorCoreSkiaView
    ) {
        guard let text = AttoWorkspaceEditApplyResult.displayText(for: result) else { return }
        showWorkspaceEditPopover(text: text, in: editorView)
    }

    private func tabForDocumentURI(_ uri: String) -> AttoEditorTab? {
        guard let url = Self.fileURL(fromDocumentURI: uri) else { return nil }
        return tabForFileURL(url)
    }

    private func tabForFileURL(_ url: URL) -> AttoEditorTab? {
        return tabs.first { tab in
            tab.fileURL.standardizedFileURL == url.standardizedFileURL
        }
    }

    private func refreshTabAfterWorkspaceEdit(_ tab: AttoEditorTab) {
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
        }
        try? tab.editCore.editor.revealPrimaryCaret()
        handleTabDidMutateDocumentText(tabID: tab.id)
    }

    private func applyWorkspaceEdit(
        _ document: AttoWorkspaceEditParser.DocumentEdit,
        toFileAt url: URL
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            return false
        }

        do {
            let oldText = try String(contentsOf: url, encoding: .utf8)
            guard let result = AttoWorkspaceEditParser.apply(document, to: oldText),
                  result.hasOverlappingEdits == false,
                  result.editCount > 0
            else {
                return false
            }
            try result.text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to apply WorkspaceEdit to file %@: %@",
                url.path,
                String(describing: error)
            )
            return false
        }
    }

    private func applyWorkspaceResourceOperation(_ operation: AttoWorkspaceEditParser.ResourceOperation) -> Bool {
        switch operation {
        case .create(let op):
            guard let url = workspaceFileURL(fromDocumentURI: op.uri) else { return false }
            if let tab = tabForFileURL(url) {
                if op.ignoreIfExists { return true }
                guard op.overwrite, isTabDirtyForDataLossDecision(tab) == false else { return false }
                guard createWorkspaceFile(at: url, overwrite: true, ignoreIfExists: false) else { return false }
                return replaceOpenTabText(tab, with: "", markSaved: true)
            }
            return createWorkspaceFile(at: url, overwrite: op.overwrite, ignoreIfExists: op.ignoreIfExists)

        case .rename(let op):
            guard let oldURL = workspaceFileURL(fromDocumentURI: op.oldURI),
                  let newURL = workspaceFileURL(fromDocumentURI: op.newURI)
            else { return false }

            if oldURL.standardizedFileURL == newURL.standardizedFileURL {
                return true
            }

            let oldTab = tabForFileURL(oldURL)
            let targetTab = tabForFileURL(newURL)
            let targetExists = FileManager.default.fileExists(atPath: newURL.path)
            if targetExists, op.ignoreIfExists {
                return true
            }

            if let targetTab, targetTab.id != oldTab?.id {
                guard op.overwrite, isTabDirtyForDataLossDecision(targetTab) == false else { return false }
                closeTab(id: targetTab.id)
            }

            guard renameWorkspaceFile(
                from: oldURL,
                to: newURL,
                overwrite: op.overwrite,
                ignoreIfExists: op.ignoreIfExists
            ) else {
                return false
            }

            if let oldTab {
                oldTab.fileURL = newURL
                oldTab.isUntitled = false
                refreshTabAfterWorkspaceResourceOperation(oldTab)
                return true
            }

            return true

        case .delete(let op):
            guard let url = workspaceFileURL(fromDocumentURI: op.uri) else { return false }
            if let tab = tabForFileURL(url) {
                guard isTabDirtyForDataLossDecision(tab) == false else { return false }
                guard deleteWorkspaceFile(
                    at: url,
                    recursive: op.recursive,
                    ignoreIfNotExists: op.ignoreIfNotExists
                ) else {
                    return false
                }
                closeTab(id: tab.id)
                return true
            }
            return deleteWorkspaceFile(
                at: url,
                recursive: op.recursive,
                ignoreIfNotExists: op.ignoreIfNotExists
            )
        }
    }

    private func workspaceFileURL(fromDocumentURI uri: String) -> URL? {
        guard let url = Self.fileURL(fromDocumentURI: uri) else { return nil }
        let path = url.standardizedFileURL.path
        let root = workspaceRootURL.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        return url
    }

    private func createWorkspaceFile(at url: URL, overwrite: Bool, ignoreIfExists: Bool) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists {
            if ignoreIfExists { return true }
            guard overwrite, isDirectory.boolValue == false else { return false }
        }

        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("AttoEditor: failed to create WorkspaceEdit file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    private func renameWorkspaceFile(
        from oldURL: URL,
        to newURL: URL,
        overwrite: Bool,
        ignoreIfExists: Bool
    ) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldURL.path) else { return false }

        let targetExists = fm.fileExists(atPath: newURL.path)
        if targetExists {
            if ignoreIfExists { return true }
            guard overwrite else { return false }
        }

        do {
            try fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if targetExists {
                try fm.removeItem(at: newURL)
            }
            try fm.moveItem(at: oldURL, to: newURL)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to rename WorkspaceEdit file %@ -> %@: %@",
                oldURL.path,
                newURL.path,
                String(describing: error)
            )
            return false
        }
    }

    private func deleteWorkspaceFile(at url: URL, recursive: Bool, ignoreIfNotExists: Bool) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { return ignoreIfNotExists }
        guard recursive || isDirectory.boolValue == false else { return false }

        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            NSLog("AttoEditor: failed to delete WorkspaceEdit file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    private func replaceOpenTabText(_ tab: AttoEditorTab, with text: String, markSaved: Bool) -> Bool {
        do {
            let oldText = try tab.editCore.editor.text()
            let fullRange = UInt32(clamping: oldText.unicodeScalars.count)
            _ = try tab.editCore.editor.applyTextEdits([
                EcuTextEdit(start: 0, end: fullRange, text: text),
            ])
            if markSaved {
                try tab.editCore.editor.markSaved()
                tab.isDirty = false
                tab.isUntitled = false
            } else {
                tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true
            }
            syncCoreTabText(tab, markSaved: markSaved || tab.isDirty == false)
            refreshTabAfterWorkspaceResourceOperation(tab)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to replace open WorkspaceEdit tab %@: %@",
                tab.fileURL.path,
                String(describing: error)
            )
            return false
        }
    }

    private func refreshTabAfterWorkspaceResourceOperation(_ tab: AttoEditorTab) {
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        }
        updateCoreTabTitle(tab)
        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
    }

    private static func fileURL(fromDocumentURI uri: String) -> URL? {
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    private func startRenamePreparePollTimer(tabID: UUID) {
        renamePreparePollTimer?.cancel()

        var remainingTicks = 20 // ~1s at 50ms; fall back to local identifier if no prepare result arrives.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.renamePrepareContext, ctx.tabID == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastPrepareRenameResultJSON()
            } catch {
                return
            }

            if let json {
                self.cancelRenamePrepareUI()
                let seed = self.renameDialogSeedInActiveTab(
                    prepareRenameResultJSON: json,
                    fallback: ctx.fallbackSeed
                )
                _ = self.showRenameDialog(seed: seed)
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.cancelRenamePrepareUI()
                _ = self.showRenameDialog(seed: ctx.fallbackSeed)
                timer.cancel()
                return
            }
            remainingTicks -= 1
        }

        renamePreparePollTimer = timer
        timer.resume()
    }

    private func startRenamePollTimer(tabID: UUID) {
        renamePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.renameContext, ctx.tabID == tabID else {
                self.cancelRenameUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelRenameUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenameUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastRenameResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.renamePollTimer?.cancel()
            self.renamePollTimer = nil
            self.renameContext = nil
            _ = self.applyWorkspaceEditJSONToActiveTab(json, documentURI: ctx.documentURI)
            timer.cancel()
        }

        renamePollTimer = timer
        timer.resume()
    }

    private func renameDialogSeedInActiveTab(
        prepareRenameResultJSON: String? = nil,
        fallback fallbackSeed: AttoLspRenameSupport.DialogSeed? = nil
    ) -> AttoLspRenameSupport.DialogSeed {
        guard let tab = activeTab else {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
        do {
            let selected = try tab.editCore.editor.selectedText()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let text = try tab.editCore.editor.text()
            let fallback = fallbackSeed ?? AttoLspRenameSupport.DialogSeed(
                initialName: AttoLspRenameSupport.candidateName(
                    documentText: text,
                    selectedText: selected,
                    caretOffset: offsets.end
                ),
                placeholder: nil
            )
            return AttoLspRenameSupport.dialogSeed(
                documentText: text,
                selectedText: selected,
                caretOffset: offsets.end,
                prepareRenameResultJSON: prepareRenameResultJSON,
                fallback: fallback
            )
        } catch {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
    }

    // MARK: - LSP signature help

    private func handleCommittedTextForLspTriggers(_ text: String, tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID else { return }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        guard let status = try? tab.editCore.editor.lspStatusSnapshot() else { return }
        let shouldShowSignatureHelp = AttoLspSignatureHelpTrigger.shouldTrigger(
            committedText: text,
            lspStatus: status
        )

        if AttoLspCompletionTrigger.shouldTrigger(
            committedText: text,
            lspStatus: status
        ), shouldShowSignatureHelp == false {
            _ = showCompletionsInActiveTab(beepOnFailure: false)
        }

        if shouldShowSignatureHelp {
            _ = showSignatureHelpInActiveTab(beepOnFailure: false, showEmptyResults: false)
        }
    }

    @discardableResult
    func showSignatureHelpInActiveTab() -> Bool {
        showSignatureHelpInActiveTab(beepOnFailure: true, showEmptyResults: true)
    }

    @discardableResult
    private func showSignatureHelpInActiveTab(beepOnFailure: Bool, showEmptyResults: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showEmptyResults {
                showSignatureHelpPopover(
                    display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help is unavailable.\nLSP is not enabled for this document."),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestSignatureHelp(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
        } catch {
            if showEmptyResults {
                showSignatureHelpPopover(
                    display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help request failed.\n\(error.localizedDescription)"),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        signatureHelpContext = SignatureHelpRequestContext(
            tabID: tab.id,
            showEmptyResults: showEmptyResults
        )
        startSignatureHelpPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    private func startSignatureHelpPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        signatureHelpPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.signatureHelpContext, ctx.tabID == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            if remainingTicks <= 0 {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpPopover(
                        display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help timed out."),
                        in: editorView
                    )
                }
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastSignatureHelpResultJSON()
            } catch {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpPopover(
                        display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help failed.\n\(error.localizedDescription)"),
                        in: editorView
                    )
                }
                timer.cancel()
                return
            }
            guard let json else { return }

            let display = AttoLspSignatureHelpFormatter.display(fromSignatureHelpResultJSON: json)
                ?? (ctx.showEmptyResults ? AttoLspSignatureHelpFormatter.messageDisplay("No signature help is available here.") : nil)
            self.cancelSignatureHelpUI()
            self.showSignatureHelpPopover(display: display, in: editorView)
            timer.cancel()
        }

        signatureHelpPollTimer = timer
        timer.resume()
    }

    private func showSignatureHelpPopover(display: AttoLspSignatureHelpFormatter.Display?, in editorView: EditorCoreSkiaView) {
        guard let display else {
            cancelSignatureHelpUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = signatureHelpPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            signatureHelpPopover = p
            signatureHelpPopoverLabel = label
            popover = p
        }

        signatureHelpPopoverLabel?.attributedStringValue = attributedSignatureHelp(display)
        popover.contentSize = preferredHoverPopoverSize(text: display.text, font: signatureHelpPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    private func attributedSignatureHelp(_ display: AttoLspSignatureHelpFormatter.Display) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let activeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attributed = NSMutableAttributedString(
            string: display.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let fullRange = NSRange(location: 0, length: (display.text as NSString).length)
        let highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.24)

        for range in display.activeParameterRanges where NSIntersectionRange(range, fullRange).length == range.length {
            attributed.addAttributes(
                [
                    .font: activeFont,
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: highlightColor,
                ],
                range: range
            )
        }
        return attributed
    }

    private func caretAnchorRect(in editorView: EditorCoreSkiaView) -> NSRect {
        do {
            let offsets = try editorView.editor.selectionOffsets()
            let pt = try editorView.editor.charOffsetToViewPoint(offset: offsets.end)

            let boundsSize = editorView.bounds.size
            let backingSize = editorView.convertToBacking(boundsSize)
            let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 1
            let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 1

            let xPt = CGFloat(pt.xPx) / max(1e-6, sx)
            let yPt = CGFloat(pt.yPx) / max(1e-6, sy)
            let hPt = max(1, CGFloat(pt.lineHeightPx) / max(1e-6, sy))
            return NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        } catch {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    // MARK: - LSP hover tooltip (AttoEditor UX)

    private func handleHover(info: EditorCoreSkiaHoverInfo, tabID: UUID) {
        guard activeTab?.id == tabID else { return }
        guard let tab = activeTab else { return }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            cancelHoverUI()
            return
        }

        hoverContext = HoverRequestContext(tabID: tabID, info: info)
        hoverDebounceWorkItem?.cancel()
        hoverPollTimer?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.requestHoverForCurrentContext()
        }
        hoverDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func handleHoverExit(tabID: UUID) {
        guard hoverContext?.tabID == tabID else { return }
        cancelHoverUI()
    }

    private func requestHoverForCurrentContext() {
        guard let ctx = hoverContext else { return }
        guard activeTab?.id == ctx.tabID else { return }
        guard let tab = activeTab else { return }

        do {
            _ = try tab.editCore.editor.lspRequestHover(
                logicalLine: ctx.info.logicalLine,
                logicalColumn: ctx.info.logicalColumn
            )
        } catch {
            return
        }

        startHoverPollTimer(tabID: ctx.tabID, editorView: tab.editCore.editorView)
    }

    private func startHoverPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        hoverPollTimer?.cancel()

        var remainingTicks = 30 // ~1.5s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.hoverContext, ctx.tabID == tabID else {
                self.cancelHoverUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelHoverUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHoverUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastHoverResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let text = AttoLspHoverFormatter.displayText(fromHoverResultJSON: json)
            self.showHoverPopover(text: text, at: ctx.info, in: editorView)
            timer.cancel()
        }

        hoverPollTimer = timer
        timer.resume()
    }

    private func showHoverPopover(text: String?, at info: EditorCoreSkiaHoverInfo, in editorView: EditorCoreSkiaView) {
        guard let text else {
            cancelHoverUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = hoverPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            hoverPopover = p
            hoverPopoverLabel = label
            popover = p
        }

        hoverPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: hoverPopoverLabel?.font)

        let rect = NSRect(x: info.viewPoint.x, y: info.viewPoint.y, width: 1, height: 1)
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: rect, of: editorView, preferredEdge: .maxY)
    }

    private func presentLspFailureDetailIfNeeded(_ detail: String, editorView: EditorCoreSkiaView) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard editorView.window != nil else { return }
        guard lastPresentedLspFailureDetail != trimmed else { return }
        lastPresentedLspFailureDetail = trimmed
        NSLog("AttoEditor: LSP status failed: %@", trimmed)
        showWorkspaceEditPopover(text: "LSP failed.\n\(trimmed)", in: editorView)
    }

    private func showWorkspaceEditPopover(text: String, in editorView: EditorCoreSkiaView) {
        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = workspaceEditPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            workspaceEditPopover = p
            workspaceEditPopoverLabel = label
            popover = p
        }

        workspaceEditPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: workspaceEditPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    private func preferredHoverPopoverSize(text: String, font: NSFont?) -> NSSize {
        let maxWidth: CGFloat = 420
        let maxHeight: CGFloat = 260
        let padW: CGFloat = 20
        let padH: CGFloat = 16

        let f = font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: max(1, maxWidth - padW), height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let h = min(maxHeight, ceil(bounds.height) + padH)
        return NSSize(width: maxWidth, height: max(44, h))
    }

    private func cancelHoverUI() {
        hoverDebounceWorkItem?.cancel()
        hoverDebounceWorkItem = nil

        hoverPollTimer?.cancel()
        hoverPollTimer = nil

        hoverContext = nil

        hoverPopover?.performClose(nil)
    }

    private func cancelDefinitionUI() {
        definitionPollTimer?.cancel()
        definitionPollTimer = nil
        definitionContext = nil
        lspLocationResultsController?.hide()
        lspLocationResultsController = nil
    }

    private func cancelSymbolUI() {
        symbolPollTimer?.cancel()
        symbolPollTimer = nil
        symbolContext = nil
        cancelWorkspaceSymbolSearchRequestOnly()
        lspSymbolResultsController?.hide()
        lspSymbolResultsController = nil
        cancelProblemsUI()
        cancelWorkspaceDiagnosticsUI()
    }

    private func cancelWorkspaceSymbolSearchRequestOnly() {
        workspaceSymbolSearchDebounceTimer?.cancel()
        workspaceSymbolSearchDebounceTimer = nil

        workspaceSymbolSearchPollTimer?.cancel()
        workspaceSymbolSearchPollTimer = nil

        workspaceSymbolSearchContext = nil
        workspaceSymbolSearchResults = []
    }

    private func cancelHierarchyUI() {
        hierarchyPreparePollTimer?.cancel()
        hierarchyPreparePollTimer = nil
        hierarchyPrepareContext = nil

        hierarchyChildrenPollTimer?.cancel()
        hierarchyChildrenPollTimer = nil
        hierarchyChildrenContext = nil

        hierarchyResultsController?.hide()
        hierarchyResultsController = nil
    }

    private func cancelProblemsUI() {
        problemsResultsController?.hide()
        problemsResultsController = nil
    }

    private func cancelWorkspaceDiagnosticsUI() {
        workspaceDiagnosticsPollTimer?.cancel()
        workspaceDiagnosticsPollTimer = nil
        workspaceDiagnosticsContext = nil
        workspaceDiagnosticsResultsController?.hide()
        workspaceDiagnosticsResultsController = nil
    }

    private func cancelSignatureHelpUI() {
        signatureHelpPollTimer?.cancel()
        signatureHelpPollTimer = nil
        signatureHelpContext = nil
        signatureHelpPopover?.performClose(nil)
    }

    private func cancelCompletionUI() {
        completionPollTimer?.cancel()
        completionPollTimer = nil
        completionContext = nil

        completionResolvePollTimer?.cancel()
        completionResolvePollTimer = nil
        completionResolveContext = nil

        completionListController?.hide()
        completionListController = nil
        completionListContext = nil
    }

    private func cancelRenameUI() {
        cancelRenamePrepareUI()
        renamePollTimer?.cancel()
        renamePollTimer = nil
        renameContext = nil
    }

    private func cancelRenamePrepareUI() {
        renamePreparePollTimer?.cancel()
        renamePreparePollTimer = nil
        renamePrepareContext = nil
    }

    private func cancelCodeActionUI() {
        codeActionPollTimer?.cancel()
        codeActionPollTimer = nil
        codeActionContext = nil

        codeActionResolvePollTimer?.cancel()
        codeActionResolvePollTimer = nil
        codeActionResolveContext = nil

        codeActionResultsController?.hide()
        codeActionResultsController = nil

        cancelCodeLensUI()
        cancelExecuteCommandUI()
    }

    private func cancelCodeLensUI() {
        codeLensResolvePollTimer?.cancel()
        codeLensResolvePollTimer = nil
        codeLensResolveContext = nil

        codeLensRefreshPollTimer?.cancel()
        codeLensRefreshPollTimer = nil
        codeLensRefreshContext = nil

        codeLensResultsController?.hide()
        codeLensResultsController = nil
    }

    private func cancelExecuteCommandUI() {
        executeCommandPollTimer?.cancel()
        executeCommandPollTimer = nil
        executeCommandContext = nil
    }

    private func cancelFoldingRangesUI() {
        foldingRangesPollTimer?.cancel()
        foldingRangesPollTimer = nil
        foldingRangesContext = nil
    }

    private func cancelSelectionRangeUI() {
        selectionRangePollTimer?.cancel()
        selectionRangePollTimer = nil
        selectionRangeContext = nil
    }

    private func cancelLinkedEditingUI() {
        linkedEditingPollTimer?.cancel()
        linkedEditingPollTimer = nil
        linkedEditingContext = nil
        linkedEditingSession = nil
    }

    private func cancelDocumentColorUI() {
        cancelDocumentColorRequestOnly()
        documentColorPanelContext = nil
        documentColorResultsController?.hide()
        documentColorResultsController = nil
        cancelColorPresentationUI()
    }

    private func cancelDocumentColorRequestOnly() {
        documentColorPollTimer?.cancel()
        documentColorPollTimer = nil
        documentColorContext = nil
    }

    private func cancelColorPresentationUI() {
        cancelColorPresentationRequestOnly()
        colorPresentationResultsController?.hide()
        colorPresentationResultsController = nil
    }

    private func cancelColorPresentationRequestOnly() {
        colorPresentationPollTimer?.cancel()
        colorPresentationPollTimer = nil
        colorPresentationContext = nil
    }
}

enum AttoLspRenameSupport {
    struct DialogSeed: Equatable {
        let initialName: String
        let placeholder: String?
    }

    static func candidateName(documentText: String, selectedText: String, caretOffset: UInt32) -> String {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selected.isEmpty == false, selected.rangeOfCharacter(from: .newlines) == nil {
            return selected
        }

        let chars = Array(documentText)
        guard chars.isEmpty == false else { return "" }

        let rawIndex = max(0, min(Int(caretOffset), chars.count))
        var probe = rawIndex
        if probe >= chars.count || isIdentifierCharacter(chars[probe]) == false {
            probe = max(0, probe - 1)
        }
        guard probe < chars.count, isIdentifierCharacter(chars[probe]) else {
            return ""
        }

        var start = probe
        while start > 0, isIdentifierCharacter(chars[start - 1]) {
            start -= 1
        }

        var end = probe + 1
        while end < chars.count, isIdentifierCharacter(chars[end]) {
            end += 1
        }

        return String(chars[start..<end])
    }

    static func dialogSeed(
        documentText: String,
        selectedText: String,
        caretOffset: UInt32,
        prepareRenameResultJSON: String?,
        fallback: DialogSeed? = nil
    ) -> DialogSeed {
        let fallback = fallback ?? DialogSeed(
            initialName: candidateName(
                documentText: documentText,
                selectedText: selectedText,
                caretOffset: caretOffset
            ),
            placeholder: nil
        )

        guard let prepareRenameResultJSON,
              let data = prepareRenameResultJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return fallback
        }

        if value is NSNull {
            return fallback
        }

        guard let obj = value as? [String: Any] else {
            return fallback
        }

        if boolValue(obj["defaultBehavior"]) == true {
            return fallback
        }

        if let range = obj["range"] as? [String: Any] {
            let placeholder = stringValue(obj["placeholder"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rangeName = text(inLspRange: range, documentText: documentText)
            let initial = nonEmpty(placeholder) ?? nonEmpty(rangeName) ?? fallback.initialName
            return DialogSeed(initialName: initial, placeholder: nonEmpty(placeholder))
        }

        if isLspRangeObject(obj) {
            let initial = nonEmpty(text(inLspRange: obj, documentText: documentText)) ?? fallback.initialName
            return DialogSeed(initialName: initial, placeholder: fallback.placeholder)
        }

        return fallback
    }

    private static func isIdentifierCharacter(_ ch: Character) -> Bool {
        if ch == "_" { return true }
        return ch.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isLspRangeObject(_ obj: [String: Any]) -> Bool {
        obj["start"] is [String: Any] && obj["end"] is [String: Any]
    }

    private static func text(inLspRange range: [String: Any], documentText: String) -> String? {
        guard let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any]
        else {
            return nil
        }

        let lines = documentText.split(separator: "\n", omittingEmptySubsequences: false)
        guard let startOffset = scalarOffset(forLspPosition: start, lines: lines),
              let endOffset = scalarOffset(forLspPosition: end, lines: lines),
              startOffset <= endOffset,
              endOffset <= documentText.unicodeScalars.count
        else {
            return nil
        }

        let scalars = documentText.unicodeScalars
        let startIndex = scalars.index(scalars.startIndex, offsetBy: startOffset)
        let endIndex = scalars.index(scalars.startIndex, offsetBy: endOffset)
        return String(scalars[startIndex..<endIndex])
    }

    private static func scalarOffset(
        forLspPosition position: [String: Any],
        lines: [String.SubSequence]
    ) -> Int? {
        guard let lineNumber = intValue(position["line"]),
              let utf16Column = intValue(position["character"]),
              lineNumber >= 0,
              utf16Column >= 0,
              lineNumber < lines.count
        else {
            return nil
        }

        let preceding = lines.prefix(lineNumber).reduce(0) { total, line in
            total + line.unicodeScalars.count + 1
        }
        return preceding + scalarOffset(fromUTF16Offset: utf16Column, in: lines[lineNumber])
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in line: String.SubSequence) -> Int {
        let target = max(0, min(targetUtf16Offset, line.utf16.count))
        var scalarCursor = 0
        var utf16Cursor = 0

        for scalar in line.unicodeScalars {
            let unitCount = scalar.value <= 0xFFFF ? 1 : 2
            if utf16Cursor + unitCount > target {
                return scalarCursor
            }
            utf16Cursor += unitCount
            scalarCursor += 1
        }

        return scalarCursor
    }
}

private enum AttoLspLanguageId {
    static func guess(forExtension ext: String) -> String? {
        let k = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard k.isEmpty == false else { return nil }

        switch k {
        case "rs": return "rust"
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "jsx": return "javascriptreact"
        case "ts": return "typescript"
        case "tsx": return "typescriptreact"
        case "go": return "go"
        case "c": return "c"
        case "h": return "c"
        case "cpp", "cxx", "cc", "hpp", "hxx", "hh": return "cpp"
        case "m": return "objective-c"
        case "mm": return "objective-cpp"
        case "json": return "json"
        case "toml": return "toml"
        case "yaml", "yml": return "yaml"
        case "md", "markdown": return "markdown"
        default:
            return nil
        }
    }
}

private enum AttoLanguageConfiguration {
    static func indentationConfig(fileURL: URL, syntaxLanguageId: String?) -> EcuIndentationConfig {
        let language = languageKey(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        return EcuIndentationConfig(
            style: indentStyle(for: language),
            indentTriggers: indentTriggers(for: language),
            outdentTriggers: outdentTriggers(for: language)
        )
    }

    @MainActor
    static func commentConfig(
        fileURL: URL,
        syntaxLanguageId: String?,
        preferences: AttoPreferences
    ) -> AttoCommentConfiguration {
        let language = languageKey(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        if let override = preferences.commentConfigurationOverride(forLanguageKey: language) {
            return override
        }

        switch language {
        case "python", "ruby", "shell", "bash", "sh", "zsh", "toml", "yaml", "makefile", "make":
            return .line("#")
        case "lua", "sql", "haskell":
            return .line("--")
        case "lisp", "clojure", "scheme":
            return .line(";")
        case "html", "xml", "markdown":
            return .block("<!--", "-->")
        case "css":
            return .block("/*", "*/")
        case "scss", "sass":
            return .lineAndBlock("//", "/*", "*/")
        default:
            return .lineAndBlock("//", "/*", "*/")
        }
    }

    static func languageKey(fileURL: URL, syntaxLanguageId: String?) -> String {
        if let syntaxLanguageId {
            let language = syntaxLanguageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if language.isEmpty == false {
                return normalizeLanguageAlias(language)
            }
        }

        let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let guessed = AttoLspLanguageId.guess(forExtension: ext) {
            return normalizeLanguageAlias(guessed.lowercased())
        }
        return normalizeLanguageAlias(ext)
    }

    private static func normalizeLanguageAlias(_ raw: String) -> String {
        switch raw {
        case "py":
            return "python"
        case "rb":
            return "ruby"
        case "js":
            return "javascript"
        case "jsx":
            return "javascriptreact"
        case "ts":
            return "typescript"
        case "tsx":
            return "typescriptreact"
        case "yml":
            return "yaml"
        case "sh":
            return "shell"
        case "zsh":
            return "shell"
        case "bash":
            return "shell"
        case "clj":
            return "clojure"
        case "scm":
            return "scheme"
        case "mk", "make":
            return "makefile"
        default:
            return raw
        }
    }

    private static func indentStyle(for language: String) -> EcuIndentStyle {
        switch language {
        case "go", "makefile":
            return .tabs
        case "javascript", "javascriptreact", "typescript", "typescriptreact",
             "json", "jsonc", "yaml", "html", "css", "scss", "sass", "vue":
            return .spaces(width: 2)
        default:
            return .spaces(width: 4)
        }
    }

    private static func indentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml":
            return [":"]
        case "toml", "markdown", "makefile":
            return []
        default:
            return ["{", "[", "(", ":"]
        }
    }

    private static func outdentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml", "toml", "markdown", "makefile":
            return []
        default:
            return ["}", "]", ")"]
        }
    }
}

@MainActor
private final class AttoEditorTab {
    let id: UUID
    /// Projection handle into Rust `MultiDocumentEditorUi`; Swift keeps this only to route
    /// command/query sync while the AppKit tab views are being migrated.
    let coreTabID: UInt64?
    var fileURL: URL
    var isUntitled: Bool
    var isPreview: Bool
    var isDirty: Bool
    var syntaxLanguageId: String?
    var panes: [EditCoreUI]
    var activePaneIndex: Int

    var editCore: EditCoreUI {
        panes[max(0, min(activePaneIndex, panes.count - 1))]
    }

    var displayTitle: String {
        let name = fileURL.lastPathComponent
        if isDirty {
            return "● \(name)"
        }
        return name
    }

    init(
        id: UUID,
        coreTabID: UInt64?,
        fileURL: URL,
        isUntitled: Bool,
        isPreview: Bool,
        isDirty: Bool,
        syntaxLanguageId: String?,
        editCore: EditCoreUI
    ) {
        self.id = id
        self.coreTabID = coreTabID
        self.fileURL = fileURL
        self.isUntitled = isUntitled
        self.isPreview = isPreview
        self.isDirty = isDirty
        self.syntaxLanguageId = syntaxLanguageId
        self.panes = [editCore]
        self.activePaneIndex = 0
    }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    convenience init(ecuRgba8 c: EcuRgba8) {
        let r = CGFloat(c.r) / 255.0
        let g = CGFloat(c.g) / 255.0
        let b = CGFloat(c.b) / 255.0
        let a = CGFloat(c.a) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension AttoEditorAreaViewController: NSSearchFieldDelegate, NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideFindBar()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field == findReplaceBarView.searchField {
            refreshSearchHighlights()
        }
    }
}
