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

    let library: EditorCoreUIFFILibrary
    var theme: EditorCoreSkiaTheme
    var workspaceRootURL: URL
    let preferences: AttoPreferences
    static let maxLspResultHistoryEntries = 20
    static let maxLspResultEventHistoryEntries = 80

    var tabs: [AttoEditorTab] = []
    var selectedTabID: UUID?
    let coreDocuments: MultiDocumentEditorUI?

    let tabBarView = AttoTabBarView()
    let findReplaceBarView = AttoFindReplaceBarView()
    var findReplaceBarHeightConstraint: NSLayoutConstraint?
    let contentHostView = NSView(frame: .zero)
    let statusBarView = AttoStatusBarView()
    let derivedStateStore = AttoDerivedStateStore()
    let emptyStateLabel = NSTextField(labelWithString: "Open a file to start editing")
    var lastPresentedLspFailureDetail: String?
    var transientStatusText: String?

    var activeViewportObserver: EditorCoreSkiaView.ViewportStateObserverToken?

    var didAttemptLoadTreeSitterRegistry: Bool = false
    var treeSitterRegistryJSON: String?
    var treeSitterLanguageIDs: [String] = []
    var treeSitterExtensionMap: [String: String] = [:]

    var onDidCloseFile: ((URL) -> Void)?
    /// (url, createdOnDisk)
    var onDidSaveFile: ((URL, Bool) -> Void)?
    var onOpenFilesChanged: (([OpenFileItem], UUID?) -> Void)?
    var onSessionStateChanged: (() -> Void)?

    var isRestoringSession: Bool = false

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

        let documentURL = projectedFileURL(for: tab)
        let language = AttoLanguageConfiguration.languageKey(
            fileURL: documentURL,
            syntaxLanguageId: tab.syntaxLanguageId
        )
        if language.isEmpty == false {
            values["syntax"] = .string(language)
            values["selector"] = .string(Self.keymapSelector(forLanguage: language))
        }
        values["file_name"] = .string(documentURL.lastPathComponent)
        values["file_extension"] = .string(documentURL.pathExtension.lowercased())
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

    static func keymapSelector(forLanguage language: String) -> String {
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

    func _activeDerivedStateIsStaleForTesting() -> Bool {
        derivedStateStore.activeIsStale
    }

    func _activeLspStatusForTesting() -> EcuLspStatusSnapshot? {
        derivedStateStore.activeLspStatus
    }

    func _derivedStateEventKindsForTesting() -> [EcuEditorUIStateEventKind] {
        derivedStateStore.lastStateEventKinds
    }

    func _derivedStateEventSequenceForTesting() -> UInt64 {
        derivedStateStore.lastStateEventSequence
    }

    func _derivedStateSnapshotRefreshCountForTesting() -> Int {
        derivedStateStore.snapshotRefreshCount
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

    func _lspLocationPanelEntryForTesting() -> AttoLspResultLifecycleEntry<LspLocationResultSnapshot>? {
        lspLocationPanelController?.currentEntry
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

    func _lspSymbolPanelEntryForTesting() -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        lspSymbolPanelController?.currentEntry
    }

    func _lspSymbolPanelRowCountForTesting() -> Int {
        lspSymbolPanelController?.rowCount ?? 0
    }

    func _lspSymbolPanelIsVisibleForTesting() -> Bool {
        lspSymbolPanelController?.isVisible == true
    }

    func _workspaceOutlineSnapshotForTesting() -> AttoWorkspaceOutlineSnapshot {
        workspaceOutlineStore.snapshot
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

    func _projectLspPanelErrorEventsForTesting(after sequence: UInt64) -> [AttoProjectLspPanelErrorEvent] {
        projectLspPanelErrorEventStore.entries(after: sequence)
    }

    func _latestProjectLspPanelErrorEventSequenceForTesting() -> UInt64 {
        projectLspPanelErrorEventStore.latestSequence
    }

    func _projectLspProcessHealthEventsForTesting(after sequence: UInt64) -> [AttoProjectLspProcessHealthEvent] {
        projectLspProcessHealthEventStore.entries(after: sequence)
    }

    func _latestProjectLspProcessHealthEventSequenceForTesting() -> UInt64 {
        projectLspProcessHealthEventStore.latestSequence
    }

    @discardableResult
    func _recordProjectLspPanelErrorForTesting(
        family: String,
        title: String,
        slot: String,
        status: String,
        message: String
    ) -> Bool {
        recordProjectLspPanelError(
            source: .request,
            sourceSequence: 0,
            tabId: activeTab?.coreTabID,
            viewIndex: activeTab?.activePaneIndex,
            viewId: nil,
            family: family,
            title: title,
            slot: slot,
            method: "",
            requestId: 0,
            status: status,
            errorMessage: message
        ) != nil
    }

    @discardableResult
    func _recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot) -> Bool {
        recordProjectLspStatusFailure(
            sourceSequence: 0,
            tabId: activeTab?.coreTabID,
            viewIndex: activeTab?.activePaneIndex,
            viewId: nil,
            status: status
        ) != nil
    }

    @discardableResult
    func _recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot) -> Bool {
        recordProjectLspProcessHealth(
            sourceSequence: 0,
            tabId: activeTab?.coreTabID,
            viewIndex: activeTab?.activePaneIndex,
            viewId: nil,
            status: status
        ) != nil
    }

    func _setProjectLspAutoRestartNowProviderForTesting(_ provider: @escaping () -> Date) {
        projectLspAutoRestartNowProvider = provider
    }

    func _projectLspAutoRestartAttemptsForTesting(tabId: UInt64) -> Int {
        projectLspAutoRestartStatesByTabID[tabId]?.attempts ?? 0
    }

    func _showCodeActionResultJSONForTesting(
        _ json: String,
        onlyKinds: [String] = [],
        showFeedback: Bool = true
    ) -> Bool {
        let items = AttoLspCodeActionParser.filteredItems(
            AttoLspCodeActionParser.items(fromCodeActionResultJSON: json),
            onlyKinds: onlyKinds
        )
        return showCodeActionResults(items, onlyKinds: onlyKinds, showFeedback: showFeedback)
    }

    func _showCompletionResultJSONForTesting(_ json: String) -> Bool {
        _showCompletionResultJSONForTesting(json, showFeedback: true)
    }

    func _showCompletionResultJSONForTesting(_ json: String, showFeedback: Bool) -> Bool {
        guard let tab = activeTab else { return false }
        guard let context = try? completionRequestContextForCurrentSelection(tab, showFeedback: showFeedback) else {
            return false
        }
        let items = AttoLspCompletionParser.items(fromCompletionResultJSON: json)
        return showCompletionList(items: items, context: context, editorView: tab.editCore.editorView)
    }

    func _applyRenameResultJSONForTesting(_ json: String, newName: String, showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else { return false }
        let context = RenameRequestContext(
            tabID: tab.id,
            documentURI: projectedFileURL(for: tab).absoluteString,
            newName: newName,
            showFeedback: showFeedback
        )
        return applyRenameResultJSON(json, context: context)
    }

    func _showHierarchyResultJSONForTesting(
        _ json: String,
        kind: String = "callIncoming",
        showFeedback: Bool = true
    ) -> Bool {
        let requestKind: LspHierarchyRequestKind
        switch kind {
        case "callOutgoing":
            requestKind = .callOutgoing
        case "typeSupertypes":
            requestKind = .typeSupertypes
        case "typeSubtypes":
            requestKind = .typeSubtypes
        default:
            requestKind = .callIncoming
        }

        let entries: [AttoLspHierarchyParser.Entry]
        switch requestKind {
        case .callIncoming:
            entries = AttoLspHierarchyParser.incomingCalls(fromResultJSON: json)
        case .callOutgoing:
            entries = AttoLspHierarchyParser.outgoingCalls(fromResultJSON: json)
        case .typeSupertypes, .typeSubtypes:
            entries = AttoLspHierarchyParser.typeHierarchyEntries(fromResultJSON: json)
        }

        return showHierarchyResults(
            entries,
            placeholder: requestKind.resultPlaceholder,
            feedbackFeature: requestKind.feedbackFeature,
            showFeedback: showFeedback
        )
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

    func _coreProjectLspServerConfigsForTesting() throws -> [EcuProjectLspServerConfig] {
        try coreDocuments?.projectLspServers() ?? []
    }

    func _coreWorkspaceEditTransactionLatestSequenceForTesting() throws -> UInt64? {
        try coreDocuments?.workspaceEditTransactionEventsLatestSequence()
    }

    func _undoLastCoreWorkspaceEditTransactionForTesting() -> Bool {
        undoLastCoreWorkspaceEditTransaction()
    }

    func _setWorkspaceEditPreviewDecisionProviderForTesting(
        _ provider: ((AttoWorkspaceEditPreview) -> AttoWorkspaceEditPreviewDecision)?
    ) {
        workspaceEditPreviewDecisionProviderForTesting = provider
    }

    func _coreMultiDocumentSearchForTesting(query: String) throws -> [EcuTabSearchResult]? {
        try coreDocuments?.searchAllTabs(query: query)
    }

    func _linkedEditingSessionIsActiveForTesting() -> Bool {
        linkedEditingSession != nil
    }

    func _codeLensResultSummaryForTesting(_ result: EcuLspCodeLensResult) -> (errorMessage: String?, count: Int) {
        (Self.codeLensResultErrorMessage(result), Self.codeLensResultCount(result))
    }

    func _inlayHintResultSummaryForTesting(_ result: EcuLspInlayHintResult) -> (errorMessage: String?, count: Int) {
        (Self.inlayHintResultErrorMessage(result), Self.inlayHintResultCount(result))
    }

    func _documentLinkResultSummaryForTesting(_ result: EcuLspDocumentLinkResult) -> (errorMessage: String?, count: Int) {
        (Self.documentLinkResultErrorMessage(result), Self.documentLinkResultCount(result))
    }

    func _activeSemanticTokensBaselineForTesting() -> (resultId: String?, data: [UInt32])? {
        guard let tab = activeTab else { return nil }
        return (tab.semanticTokensResultId, tab.semanticTokensData)
    }

    func _setDocumentColorPickerForTesting(_ picker: ((NSColor) -> NSColor?)?) {
        documentColorPickerForTesting = picker
    }

    func _setLspEnvironmentProviderForTesting(_ provider: @escaping () -> [String: String]) {
        lspEnvironmentProvider = provider
    }

    func _setActiveTabDirtyCacheForTesting(_ isDirty: Bool) {
        activeTab?.isDirty = isDirty
    }

    func _activeTabDirtyForDataLossDecisionForTesting() -> Bool {
        guard let tab = activeTab else { return false }
        return isTabDirtyForDataLossDecision(tab)
    }

    struct HoverRequestContext {
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

        var feedbackFeature: AttoLspResultFeedback.Feature {
            switch self {
            case .definition:
                return .definition
            case .declaration:
                return .declaration
            case .typeDefinition:
                return .typeDefinition
            case .implementation:
                return .implementation
            case .references:
                return .references
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

    enum LspSymbolRequestKind {
        case document
        case workspace(query: String)

        var feedbackFeature: AttoLspResultFeedback.Feature {
            switch self {
            case .document: return .documentSymbols
            case .workspace: return .workspaceSymbols
            }
        }

        var emptyFeedbackDetailText: String {
            switch self {
            case .document:
                return AttoLspResultFeedback.Feature.documentSymbols.emptyText
            case .workspace(let query):
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return AttoLspResultFeedback.Feature.workspaceSymbols.emptyText
                }
                return "No workspace symbols match \"\(trimmed)\"."
            }
        }
    }

    enum ProjectLspPanelFamily {
        case locations
        case symbols
    }

    struct LspSymbolResultSnapshot: Equatable {
        let title: String
        let symbols: [AttoLspSymbolParser.Symbol]
        let placeholder: String
    }

    enum LspHierarchyRequestKind {
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

        var feedbackFeature: AttoLspResultFeedback.Feature {
            switch self {
            case .callIncoming, .callOutgoing:
                return .callHierarchy
            case .typeSupertypes, .typeSubtypes:
                return .typeHierarchy
            }
        }
    }

    struct DefinitionRequestContext {
        let tabID: UUID
        let logicalLine: UInt32
        let logicalColumn: UInt32
        let kind: LspLocationRequestKind
        let showFeedback: Bool
    }

    struct SymbolRequestContext {
        let tabID: UUID
        let kind: LspSymbolRequestKind
    }

    struct WorkspaceSymbolSearchContext {
        let tabID: UUID
        let requestID: Int
        let query: String
    }

    struct HierarchyPrepareContext {
        let tabID: UUID
        let kind: LspHierarchyRequestKind
        let showFeedback: Bool
    }

    struct HierarchyChildrenContext {
        let tabID: UUID
        let kind: LspHierarchyRequestKind
        let showFeedback: Bool
    }

    struct SignatureHelpRequestContext {
        let tabID: UUID
        let showEmptyResults: Bool
    }

    struct CompletionRequestContext {
        let tabID: UUID
        let fallbackStart: UInt32
        let fallbackEnd: UInt32
        let beepOnFailure: Bool
        let showFeedback: Bool
    }

    struct CompletionResolveContext {
        let request: CompletionRequestContext
        let item: AttoLspCompletionParser.Item
        let commitCharacter: String?
    }

    struct RenameRequestContext {
        let tabID: UUID
        let documentURI: String
        let newName: String
        let showFeedback: Bool
    }

    struct RenamePrepareContext {
        let tabID: UUID
        let fallbackSeed: AttoLspRenameSupport.DialogSeed
        let showFeedback: Bool
    }

    struct CodeActionRequestContext {
        let tabID: UUID
        let onlyKinds: [String]
        let showFeedback: Bool
    }

    struct CodeActionResolveContext {
        let tabID: UUID
        let item: AttoLspCodeActionParser.Item
        let showFeedback: Bool
    }

    struct CodeLensResolveContext {
        let tabID: UUID
        let item: AttoLspCodeLensParser.Item
    }

    struct CodeLensRefreshContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    enum AuxiliaryRefreshKind {
        case inlayHints
        case documentLinks

        var feedbackFeature: AttoLspResultFeedback.Feature {
            switch self {
            case .inlayHints:
                return .inlayHints
            case .documentLinks:
                return .documentLinks
            }
        }

        var singularNoun: String {
            switch self {
            case .inlayHints:
                return "hint"
            case .documentLinks:
                return "link"
            }
        }

        var pluralNoun: String {
            switch self {
            case .inlayHints:
                return "hints"
            case .documentLinks:
                return "links"
            }
        }
    }

    struct AuxiliaryRefreshContext {
        let tabID: UUID
        let kind: AuxiliaryRefreshKind
        let showFeedback: Bool
    }

    struct InlayHintResolveContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    struct DocumentLinkResolveContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    struct ExecuteCommandRequestContext {
        let tabID: UUID
        let commandTitle: String
    }

    struct FoldingRangesRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    struct SelectionRangeRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    struct LinkedEditingRequestContext {
        let tabID: UUID
        let caretOffset: UInt32
        let showFeedback: Bool
    }

    struct LinkedEditingSession {
        let tabID: UUID
        let selectionCount: Int
    }

    enum DocumentColorResultMode {
        case presentations
        case picker

        var lifecycleMode: String {
            switch self {
            case .presentations:
                return "presentations"
            case .picker:
                return "picker"
            }
        }
    }

    struct DocumentColorRequestContext {
        let tabID: UUID
        let showFeedback: Bool
        let mode: DocumentColorResultMode
    }

    struct ColorPresentationRequestContext {
        let tabID: UUID
        let item: AttoLspDocumentColorParser.Item
        let showFeedback: Bool
    }

    struct DocumentColorPanelContext {
        let tabID: UUID
        let item: AttoLspDocumentColorParser.Item
    }

    struct WorkspaceDiagnosticsRequestContext {
        let tabID: UUID
        let showFeedback: Bool
    }

    struct DiagnosticsTextFingerprint: Equatable {
        let count: Int
        let hashValue: Int

        init(_ text: String) {
            self.count = text.count
            self.hashValue = text.hashValue
        }
    }

    var hoverContext: HoverRequestContext?
    var hoverDebounceWorkItem: DispatchWorkItem?
    var hoverPollTimer: DispatchSourceTimer?
    var hoverPopover: NSPopover?
    var hoverPopoverLabel: NSTextField?
    var workspaceEditPopover: NSPopover?
    var workspaceEditPopoverLabel: NSTextField?
    var workspaceEditPreviewPanelController: AttoWorkspaceEditPreviewPanelController?
    var workspaceEditPreviewDecisionProviderForTesting: ((AttoWorkspaceEditPreview) -> AttoWorkspaceEditPreviewDecision)?

    var definitionContext: DefinitionRequestContext?
    var definitionPollTimer: DispatchSourceTimer?
    var lspLocationResultsController: AttoCommandPaletteController?
    var lspLocationPanelController: AttoLspLocationPanelController?
    let lspLocationResultStore = AttoLspResultLifecycleStore<LspLocationResultSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )

    var symbolContext: SymbolRequestContext?
    var symbolPollTimer: DispatchSourceTimer?
    var lspSymbolResultsController: AttoCommandPaletteController?
    var lspSymbolPanelController: AttoLspSymbolPanelController?
    let lspSymbolResultStore = AttoLspResultLifecycleStore<LspSymbolResultSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )
    let workspaceOutlineStore: AttoWorkspaceOutlineStore
    var workspaceSymbolSearchContext: WorkspaceSymbolSearchContext?
    var workspaceSymbolSearchDebounceTimer: DispatchSourceTimer?
    var workspaceSymbolSearchPollTimer: DispatchSourceTimer?
    var workspaceSymbolSearchRequestID: Int = 0
    var workspaceSymbolSearchQuery: String = ""
    var workspaceSymbolSearchResults: [AttoLspSymbolParser.Symbol] = []
    var hierarchyPrepareContext: HierarchyPrepareContext?
    var hierarchyPreparePollTimer: DispatchSourceTimer?
    var hierarchyChildrenContext: HierarchyChildrenContext?
    var hierarchyChildrenPollTimer: DispatchSourceTimer?
    var hierarchyResultsController: AttoCommandPaletteController?
    var problemsResultsController: AttoCommandPaletteController?
    var problemsPanelController: AttoProblemsPanelController?
    let diagnosticsLifecycleStore = AttoLspResultLifecycleStore<AttoDiagnosticsLifecycleSnapshot>(
        maxHistoryEntries: maxLspResultHistoryEntries
    )
    let lspResultEventStream = AttoLspResultEventStream(
        maxHistoryEntries: maxLspResultEventHistoryEntries
    )
    let projectLspPanelErrorEventStore = AttoProjectLspPanelErrorEventStore(
        maxHistoryEntries: maxLspResultEventHistoryEntries
    )
    let projectLspProcessHealthEventStore = AttoProjectLspProcessHealthEventStore(
        maxHistoryEntries: maxLspResultEventHistoryEntries
    )
    let projectLspProcessHealthLogStore: AttoProjectLspProcessHealthLogStore
    var projectLspStatusEventsController: AttoCommandPaletteController?
    var projectLspProcessHealthController: AttoCommandPaletteController?
    var projectLspProcessHealthLogController: AttoCommandPaletteController?
    var projectLspDashboardController: AttoCommandPaletteController?
    var projectLspAutoRestartStatesByTabID: [UInt64: ProjectLspAutoRestartState] = [:]
    var projectLspAutoRestartNowProvider: () -> Date = Date.init
    var coreLspRequestEventCursor: UInt64 = 0
    var coreLspResultEventCursor: UInt64 = 0
    var coreLspStateEventCursor: UInt64 = 0
    var activeDiagnosticsTextFingerprintsByTabID: [UUID: DiagnosticsTextFingerprint] = [:]
    var activeDiagnosticsBaselinesByTabID: [UUID: [EcuDiagnostic]] = [:]
    var activeDiagnosticsStaleReasonsByTabID: [UUID: AttoDiagnosticsStaleReason] = [:]
    let workspaceProblemsStore: AttoWorkspaceProblemsStore
    var workspaceProblemsPanelController: AttoProblemsPanelController?
    var workspaceDiagnosticsContext: WorkspaceDiagnosticsRequestContext?
    var workspaceDiagnosticsPollTimer: DispatchSourceTimer?
    var workspaceDiagnosticsResultsController: AttoCommandPaletteController?
    var workspaceDiagnosticsStaleReason: AttoDiagnosticsStaleReason?
    var documentColorResultsController: AttoCommandPaletteController?
    var colorPresentationResultsController: AttoCommandPaletteController?

    var signatureHelpContext: SignatureHelpRequestContext?
    var signatureHelpPollTimer: DispatchSourceTimer?
    var signatureHelpPopover: NSPopover?
    var signatureHelpPopoverLabel: NSTextField?

    var completionContext: CompletionRequestContext?
    var completionPollTimer: DispatchSourceTimer?
    var completionResolveContext: CompletionResolveContext?
    var completionResolvePollTimer: DispatchSourceTimer?
    var completionListController: AttoCompletionListController?
    var completionListContext: CompletionRequestContext?
    var shouldPreserveCompletionUIForCurrentTextMutation = false

    var renameContext: RenameRequestContext?
    var renamePollTimer: DispatchSourceTimer?
    var renamePrepareContext: RenamePrepareContext?
    var renamePreparePollTimer: DispatchSourceTimer?

    var codeActionContext: CodeActionRequestContext?
    var codeActionPollTimer: DispatchSourceTimer?
    var codeActionResolveContext: CodeActionResolveContext?
    var codeActionResolvePollTimer: DispatchSourceTimer?
    var codeActionResultsController: AttoCommandPaletteController?
    var codeLensResolveContext: CodeLensResolveContext?
    var codeLensResolvePollTimer: DispatchSourceTimer?
    var codeLensRefreshContext: CodeLensRefreshContext?
    var codeLensRefreshPollTimer: DispatchSourceTimer?
    var codeLensResultsController: AttoCommandPaletteController?
    var auxiliaryRefreshContext: AuxiliaryRefreshContext?
    var auxiliaryRefreshPollTimer: DispatchSourceTimer?
    var inlayHintResolveContext: InlayHintResolveContext?
    var inlayHintResolvePollTimer: DispatchSourceTimer?
    var documentLinkResolveContext: DocumentLinkResolveContext?
    var documentLinkResolvePollTimer: DispatchSourceTimer?
    var executeCommandContext: ExecuteCommandRequestContext?
    var executeCommandPollTimer: DispatchSourceTimer?

    var foldingRangesContext: FoldingRangesRequestContext?
    var foldingRangesPollTimer: DispatchSourceTimer?
    var selectionRangeContext: SelectionRangeRequestContext?
    var selectionRangePollTimer: DispatchSourceTimer?
    var linkedEditingContext: LinkedEditingRequestContext?
    var linkedEditingPollTimer: DispatchSourceTimer?
    var linkedEditingSession: LinkedEditingSession?
    var documentColorContext: DocumentColorRequestContext?
    var documentColorPollTimer: DispatchSourceTimer?
    var colorPresentationContext: ColorPresentationRequestContext?
    var colorPresentationPollTimer: DispatchSourceTimer?
    var documentColorPanelContext: DocumentColorPanelContext?
    var documentColorPickerForTesting: ((NSColor) -> NSColor?)?
    var lspEnvironmentProvider: () -> [String: String] = {
        ProcessInfo.processInfo.environment
    }

    init(
        library: EditorCoreUIFFILibrary,
        theme: EditorCoreSkiaTheme,
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared,
        projectLspProcessHealthLogStore: AttoProjectLspProcessHealthLogStore = AttoProjectLspProcessHealthLogStore()
    ) {
        self.library = library
        self.theme = theme
        self.workspaceRootURL = workspaceRootURL
        self.preferences = preferences
        self.projectLspProcessHealthLogStore = projectLspProcessHealthLogStore
        do {
            let coreDocuments = try MultiDocumentEditorUI(library: library)
            self.coreDocuments = coreDocuments
            self.workspaceProblemsStore = AttoWorkspaceProblemsStore(coreDocuments: coreDocuments)
            self.workspaceOutlineStore = AttoWorkspaceOutlineStore(coreDocuments: coreDocuments)
        } catch {
            self.coreDocuments = nil
            self.workspaceProblemsStore = AttoWorkspaceProblemsStore()
            self.workspaceOutlineStore = AttoWorkspaceOutlineStore()
            NSLog("AttoEditor: failed to initialize core multi-document model: %@", String(describing: error))
        }
        super.init(nibName: nil, bundle: nil)
        syncCoreWorkspaceRoots()
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

    func loadTreeSitterRegistryCacheIfNeeded() {
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

    func refreshStatusBarLanguageOptions() {
        loadTreeSitterRegistryCacheIfNeeded()
        var opts: [AttoStatusBarView.LanguageOption] = [
            .init(id: nil, title: "Plain Tex"),
        ]
        for id in treeSitterLanguageIDs {
            opts.append(.init(id: id, title: id))
        }
        statusBarView.setLanguageOptions(opts)
    }

    func inferredTreeSitterLanguageId(for url: URL) -> String? {
        loadTreeSitterRegistryCacheIfNeeded()
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ext.isEmpty == false else { return nil }
        return treeSitterExtensionMap[ext]
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
        syncCoreWorkspaceRoots()
        syncProjectLspServerConfigsToCore()
        startProjectLspServersForOpenTabs()
    }

    func syncCoreWorkspaceRoots() {
        guard let coreDocuments else { return }
        do {
            let change = try coreDocuments.setWorkspaceRootsReturningChange([
                workspaceRootURL.standardizedFileURL.absoluteString
            ])
            notifyOpenTabLspWorkspaceFoldersChanged(change)
        } catch {
            NSLog("AttoEditor: failed to sync core workspace roots: %@", String(describing: error))
        }
    }

    func notifyOpenTabLspWorkspaceFoldersChanged(_ change: EcuWorkspaceRootsChange) {
        guard change.isEmpty == false else { return }

        for tab in tabs {
            guard (try? tab.editCore.editor.lspIsEnabled()) == true else { continue }
            do {
                try tab.editCore.editor.lspDidChangeWorkspaceFolders(
                    added: change.added,
                    removed: change.removed
                )
            } catch {
                NSLog("AttoEditor: failed to notify LSP workspace folder change: %@", String(describing: error))
            }
        }
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

        if let prepareRenameResultJSON,
           let data = prepareRenameResultJSON.data(using: .utf8),
           let result = try? JSONDecoder().decode(EcuLspPrepareRenameResult.self, from: data)
        {
            return dialogSeed(
                documentText: documentText,
                selectedText: selectedText,
                caretOffset: caretOffset,
                prepareRenameResult: result,
                fallback: fallback
            )
        }

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

    static func dialogSeed(
        documentText: String,
        selectedText: String,
        caretOffset: UInt32,
        prepareRenameResult: EcuLspPrepareRenameResult?,
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

        guard let prepareRenameResult else {
            return fallback
        }

        if prepareRenameResult.shape == .none {
            return fallback
        }

        if prepareRenameResult.defaultBehavior == true {
            return fallback
        }

        guard let range = prepareRenameResult.range else {
            return fallback
        }

        let placeholder = prepareRenameResult.placeholder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rangeName = text(inLspRange: range, documentText: documentText)
        let initial = nonEmpty(placeholder) ?? nonEmpty(rangeName) ?? fallback.initialName
        let outputPlaceholder = prepareRenameResult.shape == .range ? fallback.placeholder : nonEmpty(placeholder)
        return DialogSeed(initialName: initial, placeholder: outputPlaceholder)
    }

    static func isIdentifierCharacter(_ ch: Character) -> Bool {
        if ch == "_" { return true }
        return ch.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isLspRangeObject(_ obj: [String: Any]) -> Bool {
        obj["start"] is [String: Any] && obj["end"] is [String: Any]
    }

    static func text(inLspRange range: [String: Any], documentText: String) -> String? {
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

    static func text(inLspRange range: EcuLspRange, documentText: String) -> String? {
        let lines = documentText.split(separator: "\n", omittingEmptySubsequences: false)
        guard let startOffset = scalarOffset(forLspPosition: range.start, lines: lines),
              let endOffset = scalarOffset(forLspPosition: range.end, lines: lines),
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

    static func scalarOffset(
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

    static func scalarOffset(
        forLspPosition position: EcuLspPosition,
        lines: [String.SubSequence]
    ) -> Int? {
        let lineNumber = Int(position.line)
        let utf16Column = Int(position.utf16Character)
        guard lineNumber >= 0,
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

    static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in line: String.SubSequence) -> Int {
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

enum AttoLspLanguageId {
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

enum AttoLanguageConfiguration {
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

    static func normalizeLanguageAlias(_ raw: String) -> String {
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

    static func indentStyle(for language: String) -> EcuIndentStyle {
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

    static func indentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml":
            return [":"]
        case "toml", "markdown", "makefile":
            return []
        default:
            return ["{", "[", "(", ":"]
        }
    }

    static func outdentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml", "toml", "markdown", "makefile":
            return []
        default:
            return ["}", "]", ")"]
        }
    }
}

@MainActor
struct AttoLspServerLaunchConfig: Equatable {
    let command: String
    let args: String?
    let languageId: String
}

@MainActor
struct ProjectLspAutoRestartState: Equatable {
    var attempts: Int
    var nextAllowedAt: Date
}

@MainActor
final class AttoEditorTab {
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
    var lspServerConfig: AttoLspServerLaunchConfig?
    var suppressesAutomaticLspStart: Bool
    var semanticTokensResultId: String?
    var semanticTokensData: [UInt32]

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
        self.lspServerConfig = nil
        self.suppressesAutomaticLspStart = false
        self.semanticTokensResultId = nil
        self.semanticTokensData = []
    }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension NSColor {
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
