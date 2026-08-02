import Foundation

enum AttoLspResultFeedback {
    struct Message: Equatable {
        let statusText: String
        let detailText: String
    }

    enum Feature {
        case foldingRanges
        case semanticTokens
        case definition
        case declaration
        case typeDefinition
        case implementation
        case references
        case selectionRange
        case signatureHelp
        case linkedEditing
        case codeLensRefresh
        case workspaceDiagnostics

        var statusTitle: String {
            switch self {
            case .foldingRanges:
                return "Folding ranges"
            case .semanticTokens:
                return "Semantic tokens"
            case .definition:
                return "Definition"
            case .declaration:
                return "Declaration"
            case .typeDefinition:
                return "Type definition"
            case .implementation:
                return "Implementation"
            case .references:
                return "References"
            case .selectionRange:
                return "Selection range"
            case .signatureHelp:
                return "Signature help"
            case .linkedEditing:
                return "Linked editing"
            case .codeLensRefresh:
                return "Code lens"
            case .workspaceDiagnostics:
                return "Workspace diagnostics"
            }
        }

        var requestTitle: String {
            switch self {
            case .codeLensRefresh:
                return "Code lens refresh"
            default:
                return statusTitle
            }
        }

        var refreshTitle: String {
            switch self {
            case .codeLensRefresh:
                return "Code lens"
            default:
                return requestTitle
            }
        }

        var unavailableTitle: String {
            switch self {
            case .foldingRanges:
                return "Folding ranges are unavailable."
            case .semanticTokens:
                return "Semantic tokens are unavailable."
            case .definition:
                return "Definition is unavailable."
            case .declaration:
                return "Declaration is unavailable."
            case .typeDefinition:
                return "Type definition is unavailable."
            case .implementation:
                return "Implementation is unavailable."
            case .references:
                return "References are unavailable."
            case .selectionRange:
                return "Selection range is unavailable."
            case .signatureHelp:
                return "Signature help is unavailable."
            case .linkedEditing:
                return "Linked editing is unavailable."
            case .codeLensRefresh:
                return "Code lens is unavailable."
            case .workspaceDiagnostics:
                return "Workspace diagnostics are unavailable."
            }
        }

        var emptyText: String {
            switch self {
            case .foldingRanges:
                return "No folding ranges are available for this document."
            case .semanticTokens:
                return "No semantic tokens are available for this document."
            case .definition:
                return "No definitions are available here."
            case .declaration:
                return "No declarations are available here."
            case .typeDefinition:
                return "No type definitions are available here."
            case .implementation:
                return "No implementations are available here."
            case .references:
                return "No references are available here."
            case .selectionRange:
                return "No larger selection range is available."
            case .signatureHelp:
                return "No signature help is available here."
            case .linkedEditing:
                return "No linked editing ranges are available here."
            case .codeLensRefresh:
                return "No code lens actions are available."
            case .workspaceDiagnostics:
                return "No workspace diagnostics are available."
            }
        }
    }

    static func unavailable(_ feature: Feature) -> Message {
        Message(
            statusText: "\(feature.statusTitle): unavailable",
            detailText: "\(feature.unavailableTitle)\nLSP is not enabled for this document."
        )
    }

    static func requestFailed(_ feature: Feature, errorDescription: String) -> Message {
        Message(
            statusText: "\(feature.statusTitle): request failed",
            detailText: "\(feature.requestTitle) request failed.\n\(errorDescription)"
        )
    }

    static func failed(_ feature: Feature, errorDescription: String) -> Message {
        Message(
            statusText: "\(feature.statusTitle): failed",
            detailText: "\(feature.requestTitle) failed.\n\(errorDescription)"
        )
    }

    static func timeout(_ feature: Feature) -> Message {
        Message(
            statusText: "\(feature.statusTitle): timed out",
            detailText: "\(feature.requestTitle) request timed out."
        )
    }

    static func empty(_ feature: Feature) -> Message {
        Message(
            statusText: "\(feature.statusTitle): no results",
            detailText: feature.emptyText
        )
    }

    static func refreshed(_ feature: Feature, count: Int, singular: String, plural: String) -> Message {
        let summary: String
        if count == 1 {
            summary = "1 \(singular) is available."
        } else {
            summary = "\(count) \(plural) are available."
        }
        return Message(
            statusText: "\(feature.statusTitle): \(count)",
            detailText: "\(feature.refreshTitle) refreshed.\n\(summary)"
        )
    }
}
