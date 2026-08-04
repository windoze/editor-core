import Foundation

struct AttoWorkspaceEditRequestRetryDescriptor: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case unknown
        case formatDocument = "format_document"
        case formatSelection = "format_selection"
        case rename
        case codeAction = "code_action"
        case executeCommand = "execute_command"
        case completion
        case inlayHintResolve = "inlay_hint_resolve"
        case colorPresentation = "color_presentation"
    }

    enum InvalidationReason: String, Codable, Equatable {
        case sourceTabClosed = "source_tab_closed"
        case documentURIUnavailable = "document_uri_unavailable"
        case workspaceRootUnavailable = "workspace_root_unavailable"
        case lspUnavailable = "lsp_unavailable"
        case requestParametersUnavailable = "request_parameters_unavailable"
        case requestClosureUnavailable = "request_closure_unavailable"
        case serverCapabilityChanged = "server_capability_changed"
        case expired
    }

    struct Parameter: Codable, Equatable {
        let name: String
        let value: String
    }

    struct Source: Codable, Equatable {
        let tabID: UUID?
        let coreTabID: UInt64?
        let title: String?
        let documentURI: String?

        private enum CodingKeys: String, CodingKey {
            case tabID = "tab_id"
            case coreTabID = "core_tab_id"
            case title
            case documentURI = "document_uri"
        }

        static let unavailable = Source(
            tabID: nil,
            coreTabID: nil,
            title: nil,
            documentURI: nil
        )
    }

    let kind: Kind
    let label: String
    let workspaceRootURI: String?
    let documentURI: String?
    let source: Source
    let parameterSummary: [Parameter]
    let invalidationReason: InvalidationReason?

    private enum CodingKeys: String, CodingKey {
        case kind
        case label
        case workspaceRootURI = "workspace_root_uri"
        case documentURI = "document_uri"
        case source
        case parameterSummary = "parameter_summary"
        case invalidationReason = "invalidation_reason"
    }

    var canRerun: Bool {
        invalidationReason == nil
    }

    var invalidationReasonText: String? {
        invalidationReason.map(Self.invalidationReasonText)
    }

    var retryUnavailableStatusText: String {
        let reason = invalidationReasonText ?? "retry unavailable"
        return "WorkspaceEdit request retry unavailable: \(label) (\(reason))"
    }

    var requestSummaryText: String {
        guard let invalidationReasonText else {
            return "Request: \(label)"
        }
        return "Request: \(label) unavailable (\(invalidationReasonText))"
    }

    var parameterSummaryText: String {
        guard parameterSummary.isEmpty == false else { return "" }
        return parameterSummary.map { "\($0.name)=\($0.value)" }.joined(separator: ", ")
    }

    var searchableText: String {
        [
            kind.rawValue,
            label,
            workspaceRootURI ?? "",
            documentURI ?? "",
            source.title ?? "",
            source.tabID?.uuidString ?? "",
            source.coreTabID.map(String.init) ?? "",
            parameterSummaryText,
            invalidationReason?.rawValue ?? "",
        ].filter { $0.isEmpty == false }.joined(separator: " ")
    }

    func invalidated(_ reason: InvalidationReason) -> Self {
        Self(
            kind: kind,
            label: label,
            workspaceRootURI: workspaceRootURI,
            documentURI: documentURI,
            source: source,
            parameterSummary: parameterSummary,
            invalidationReason: reason
        )
    }

    static func unknown(label: String) -> Self {
        Self(
            kind: .unknown,
            label: label,
            workspaceRootURI: nil,
            documentURI: nil,
            source: .unavailable,
            parameterSummary: [],
            invalidationReason: nil
        )
    }

    static func parameter(_ name: String, _ value: some CustomStringConvertible) -> Parameter {
        Parameter(name: name, value: summarizedValue(String(describing: value)))
    }

    static func jsonParameter(_ name: String, _ json: String) -> Parameter {
        Parameter(name: name, value: summarizedValue(normalizedJSONSummary(json)))
    }

    static func invalidationReasonText(_ reason: InvalidationReason) -> String {
        switch reason {
        case .sourceTabClosed:
            return "source tab closed"
        case .documentURIUnavailable:
            return "document URI unavailable"
        case .workspaceRootUnavailable:
            return "workspace root unavailable"
        case .lspUnavailable:
            return "LSP unavailable"
        case .requestParametersUnavailable:
            return "request parameters unavailable"
        case .requestClosureUnavailable:
            return "retry closure unavailable"
        case .serverCapabilityChanged:
            return "server capability changed"
        case .expired:
            return "request expired"
        }
    }

    private static func summarizedValue(_ value: String, limit: Int = 160) -> String {
        let normalized = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<end]) + "..."
    }

    private static func normalizedJSONSummary(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              JSONSerialization.isValidJSONObject(object),
              let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: encoded, encoding: .utf8)
        else {
            return json
        }
        return text
    }
}

extension AttoWorkspaceEditRequestRetryDescriptor.Parameter {
    static func parameter(_ name: String, _ value: some CustomStringConvertible) -> Self {
        AttoWorkspaceEditRequestRetryDescriptor.parameter(name, value)
    }

    static func jsonParameter(_ name: String, _ json: String) -> Self {
        AttoWorkspaceEditRequestRetryDescriptor.jsonParameter(name, json)
    }
}
