import Foundation

public enum EcuLspEventFamily: Hashable, Sendable {
    case hover
    case locations
    case completion
    case rename
    case actions
    case codeLens
    case inlayHints
    case documentLinks
    case semanticTokens
    case symbols
    case ranges
    case diagnostics
    case workspaceDiagnostics
    case colors
    case callHierarchy
    case typeHierarchy
    case formatting
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "hover":
            self = .hover
        case "locations":
            self = .locations
        case "completion":
            self = .completion
        case "rename":
            self = .rename
        case "actions":
            self = .actions
        case "code_lens":
            self = .codeLens
        case "inlay_hints":
            self = .inlayHints
        case "document_links":
            self = .documentLinks
        case "semantic_tokens":
            self = .semanticTokens
        case "symbols":
            self = .symbols
        case "ranges":
            self = .ranges
        case "diagnostics":
            self = .diagnostics
        case "workspace_diagnostics":
            self = .workspaceDiagnostics
        case "colors":
            self = .colors
        case "call_hierarchy":
            self = .callHierarchy
        case "type_hierarchy":
            self = .typeHierarchy
        case "formatting":
            self = .formatting
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .hover:
            return "hover"
        case .locations:
            return "locations"
        case .completion:
            return "completion"
        case .rename:
            return "rename"
        case .actions:
            return "actions"
        case .codeLens:
            return "code_lens"
        case .inlayHints:
            return "inlay_hints"
        case .documentLinks:
            return "document_links"
        case .semanticTokens:
            return "semantic_tokens"
        case .symbols:
            return "symbols"
        case .ranges:
            return "ranges"
        case .diagnostics:
            return "diagnostics"
        case .workspaceDiagnostics:
            return "workspace_diagnostics"
        case .colors:
            return "colors"
        case .callHierarchy:
            return "call_hierarchy"
        case .typeHierarchy:
            return "type_hierarchy"
        case .formatting:
            return "formatting"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuEditorUIStateEventKind: Hashable, Sendable {
    case lspRequest
    case lspResult
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "lsp_request":
            self = .lspRequest
        case "lsp_result":
            self = .lspResult
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .lspRequest:
            return "lsp_request"
        case .lspResult:
            return "lsp_result"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspResultSlot: Hashable, Sendable {
    case hover
    case definition
    case declaration
    case typeDefinition
    case implementation
    case references
    case completion
    case completionResolve
    case signatureHelp
    case prepareRename
    case rename
    case codeAction
    case codeActionResolve
    case executeCommand
    case codeLens
    case codeLensResolve
    case inlayHints
    case inlayHintResolve
    case documentLinks
    case documentLinkResolve
    case semanticTokensFull
    case semanticTokensDelta
    case semanticTokensRange
    case documentSymbols
    case workspaceSymbols
    case foldingRanges
    case selectionRange
    case linkedEditingRange
    case documentDiagnostic
    case workspaceDiagnostic
    case publishDiagnostics
    case documentColor
    case colorPresentation
    case prepareCallHierarchy
    case callHierarchyIncoming
    case callHierarchyOutgoing
    case prepareTypeHierarchy
    case typeHierarchySupertypes
    case typeHierarchySubtypes
    case onTypeFormatting
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "hover":
            self = .hover
        case "definition":
            self = .definition
        case "declaration":
            self = .declaration
        case "type_definition":
            self = .typeDefinition
        case "implementation":
            self = .implementation
        case "references":
            self = .references
        case "completion":
            self = .completion
        case "completion_resolve":
            self = .completionResolve
        case "signature_help":
            self = .signatureHelp
        case "prepare_rename":
            self = .prepareRename
        case "rename":
            self = .rename
        case "code_action":
            self = .codeAction
        case "code_action_resolve":
            self = .codeActionResolve
        case "execute_command":
            self = .executeCommand
        case "code_lens":
            self = .codeLens
        case "code_lens_resolve":
            self = .codeLensResolve
        case "inlay_hints":
            self = .inlayHints
        case "inlay_hint_resolve":
            self = .inlayHintResolve
        case "document_links":
            self = .documentLinks
        case "document_link_resolve":
            self = .documentLinkResolve
        case "semantic_tokens_full":
            self = .semanticTokensFull
        case "semantic_tokens_delta":
            self = .semanticTokensDelta
        case "semantic_tokens_range":
            self = .semanticTokensRange
        case "document_symbols":
            self = .documentSymbols
        case "workspace_symbols":
            self = .workspaceSymbols
        case "folding_ranges":
            self = .foldingRanges
        case "selection_range":
            self = .selectionRange
        case "linked_editing_range":
            self = .linkedEditingRange
        case "document_diagnostic":
            self = .documentDiagnostic
        case "workspace_diagnostic":
            self = .workspaceDiagnostic
        case "publish_diagnostics":
            self = .publishDiagnostics
        case "document_color":
            self = .documentColor
        case "color_presentation":
            self = .colorPresentation
        case "prepare_call_hierarchy":
            self = .prepareCallHierarchy
        case "call_hierarchy_incoming":
            self = .callHierarchyIncoming
        case "call_hierarchy_outgoing":
            self = .callHierarchyOutgoing
        case "prepare_type_hierarchy":
            self = .prepareTypeHierarchy
        case "type_hierarchy_supertypes":
            self = .typeHierarchySupertypes
        case "type_hierarchy_subtypes":
            self = .typeHierarchySubtypes
        case "on_type_formatting":
            self = .onTypeFormatting
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .hover:
            return "hover"
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
        case .completion:
            return "completion"
        case .completionResolve:
            return "completion_resolve"
        case .signatureHelp:
            return "signature_help"
        case .prepareRename:
            return "prepare_rename"
        case .rename:
            return "rename"
        case .codeAction:
            return "code_action"
        case .codeActionResolve:
            return "code_action_resolve"
        case .executeCommand:
            return "execute_command"
        case .codeLens:
            return "code_lens"
        case .codeLensResolve:
            return "code_lens_resolve"
        case .inlayHints:
            return "inlay_hints"
        case .inlayHintResolve:
            return "inlay_hint_resolve"
        case .documentLinks:
            return "document_links"
        case .documentLinkResolve:
            return "document_link_resolve"
        case .semanticTokensFull:
            return "semantic_tokens_full"
        case .semanticTokensDelta:
            return "semantic_tokens_delta"
        case .semanticTokensRange:
            return "semantic_tokens_range"
        case .documentSymbols:
            return "document_symbols"
        case .workspaceSymbols:
            return "workspace_symbols"
        case .foldingRanges:
            return "folding_ranges"
        case .selectionRange:
            return "selection_range"
        case .linkedEditingRange:
            return "linked_editing_range"
        case .documentDiagnostic:
            return "document_diagnostic"
        case .workspaceDiagnostic:
            return "workspace_diagnostic"
        case .publishDiagnostics:
            return "publish_diagnostics"
        case .documentColor:
            return "document_color"
        case .colorPresentation:
            return "color_presentation"
        case .prepareCallHierarchy:
            return "prepare_call_hierarchy"
        case .callHierarchyIncoming:
            return "call_hierarchy_incoming"
        case .callHierarchyOutgoing:
            return "call_hierarchy_outgoing"
        case .prepareTypeHierarchy:
            return "prepare_type_hierarchy"
        case .typeHierarchySupertypes:
            return "type_hierarchy_supertypes"
        case .typeHierarchySubtypes:
            return "type_hierarchy_subtypes"
        case .onTypeFormatting:
            return "on_type_formatting"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspResultStatus: Hashable, Sendable {
    case success
    case empty
    case error
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "success":
            self = .success
        case "empty":
            self = .empty
        case "error":
            self = .error
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .success:
            return "success"
        case .empty:
            return "empty"
        case .error:
            return "error"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspRequestPhase: Hashable, Sendable {
    case started
    case completed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "started":
            self = .started
        case "completed":
            self = .completed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .started:
            return "started"
        case .completed:
            return "completed"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspRequestStatus: Hashable, Sendable {
    case pending
    case success
    case empty
    case error
    case stale
    case mismatched
    case canceled
    case timeout
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "success":
            self = .success
        case "empty":
            self = .empty
        case "error":
            self = .error
        case "stale":
            self = .stale
        case "mismatched":
            self = .mismatched
        case "canceled":
            self = .canceled
        case "timeout":
            self = .timeout
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .pending:
            return "pending"
        case .success:
            return "success"
        case .empty:
            return "empty"
        case .error:
            return "error"
        case .stale:
            return "stale"
        case .mismatched:
            return "mismatched"
        case .canceled:
            return "canceled"
        case .timeout:
            return "timeout"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuWorkspaceDiagnosticReportKind: Hashable, Sendable {
    case full
    case unchanged
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "full":
            self = .full
        case "unchanged":
            self = .unchanged
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .full:
            return "full"
        case .unchanged:
            return "unchanged"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuWorkspaceDiagnosticsEventOperation: Hashable, Sendable {
    case apply
    case clear
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "apply":
            self = .apply
        case "clear":
            self = .clear
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .apply:
            return "apply"
        case .clear:
            return "clear"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public extension EcuDiagnosticSeverity {
    init?(lspSeverity value: UInt32?) {
        guard let value else { return nil }
        switch value {
        case 1:
            self = .error
        case 2:
            self = .warning
        case 3:
            self = .information
        case 4:
            self = .hint
        default:
            return nil
        }
    }

    var lspSeverity: UInt32 {
        switch self {
        case .error:
            return 1
        case .warning:
            return 2
        case .information:
            return 3
        case .hint:
            return 4
        }
    }
}

public extension EcuLspResultEvent {
    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }

    var slotKind: EcuLspResultSlot {
        EcuLspResultSlot(rawValue: slot)
    }

    var statusKind: EcuLspResultStatus {
        EcuLspResultStatus(rawValue: status)
    }
}

public extension EcuLspRequestEvent {
    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }

    var slotKind: EcuLspResultSlot {
        EcuLspResultSlot(rawValue: slot)
    }

    var phaseKind: EcuLspRequestPhase {
        EcuLspRequestPhase(rawValue: phase)
    }

    var statusKind: EcuLspRequestStatus {
        EcuLspRequestStatus(rawValue: status)
    }
}

public extension EcuEditorUIStateEvent {
    var kindValue: EcuEditorUIStateEventKind {
        EcuEditorUIStateEventKind(rawValue: kind)
    }

    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }
}

public extension EcuWorkspaceDiagnostic {
    var severityKind: EcuDiagnosticSeverity? {
        EcuDiagnosticSeverity(lspSeverity: severity)
            ?? severityLabel.flatMap(EcuDiagnosticSeverity.init(rawValue:))
    }
}

public extension EcuWorkspaceDiagnosticDocumentReport {
    var reportKind: EcuWorkspaceDiagnosticReportKind {
        EcuWorkspaceDiagnosticReportKind(rawValue: kind)
    }
}

public extension EcuWorkspaceDiagnosticMarker {
    var severityKind: EcuDiagnosticSeverity? {
        EcuDiagnosticSeverity(lspSeverity: severity)
            ?? severityLabel.flatMap(EcuDiagnosticSeverity.init(rawValue:))
    }
}

public extension EcuWorkspaceDiagnosticsEvent {
    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }

    var operationKind: EcuWorkspaceDiagnosticsEventOperation {
        EcuWorkspaceDiagnosticsEventOperation(rawValue: operation)
    }
}

public extension EcuMultiDocumentLSPResultEvent {
    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }

    var slotKind: EcuLspResultSlot {
        EcuLspResultSlot(rawValue: slot)
    }

    var statusKind: EcuLspResultStatus {
        EcuLspResultStatus(rawValue: status)
    }
}

public extension EcuMultiDocumentLSPRequestEvent {
    var familyKind: EcuLspEventFamily {
        EcuLspEventFamily(rawValue: family)
    }

    var slotKind: EcuLspResultSlot {
        EcuLspResultSlot(rawValue: slot)
    }

    var phaseKind: EcuLspRequestPhase {
        EcuLspRequestPhase(rawValue: phase)
    }

    var statusKind: EcuLspRequestStatus {
        EcuLspRequestStatus(rawValue: status)
    }
}
