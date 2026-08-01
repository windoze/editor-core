import Foundation

enum AttoLspSymbolRequestFeedback {
    enum Kind {
        case document
        case workspace

        var title: String {
            switch self {
            case .document: return "Document symbols"
            case .workspace: return "Workspace symbols"
            }
        }
    }

    static func unavailableMessage(kind: Kind) -> String {
        "\(kind.title) are unavailable.\nLSP is not enabled for this document."
    }

    static func requestFailedMessage(kind: Kind, errorDescription: String) -> String {
        "\(kind.title) request failed.\n\(errorDescription)"
    }

    static func failedMessage(kind: Kind, errorDescription: String) -> String {
        "\(kind.title) failed.\n\(errorDescription)"
    }

    static func timeoutMessage(kind: Kind) -> String {
        "\(kind.title) request timed out."
    }

    static func emptyMessage(kind: Kind, query: String? = nil) -> String {
        switch kind {
        case .document:
            return "No document symbols are available for this document."
        case .workspace:
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return "No workspace symbols are available."
            }
            return "No workspace symbols match \"\(trimmed)\"."
        }
    }
}
