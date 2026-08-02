import Foundation
import EditorCoreUIFFI

struct AttoLspStatusFormatter {
    struct Display: Equatable {
        let text: String
        let failureDetail: String?
    }

    static func display(statusJSON: String, fallbackEnabled: Bool) -> Display {
        guard let data = statusJSON.data(using: .utf8),
              let status = try? JSONDecoder().decode(EcuLspStatusSnapshot.self, from: data)
        else {
            return Display(text: fallbackEnabled ? "LSP: on" : "LSP: off", failureDetail: nil)
        }

        return display(status: status, fallbackEnabled: fallbackEnabled)
    }

    static func display(status: EcuLspStatusSnapshot, fallbackEnabled _: Bool) -> Display {
        let detail = nonEmptyString(status.detail)
        let prefix = statusPrefix(from: status)

        switch status.state {
        case .ready:
            return Display(text: textWithCapabilities("\(prefix) Ready", status.capabilities), failureDetail: nil)
        case .indexing:
            let title = nonEmptyString(status.activity?.title) ?? "Indexing"
            if let pct = percentageString(status.activity?.percentage) {
                return Display(text: textWithCapabilities("\(prefix) \(title) \(pct)", status.capabilities), failureDetail: nil)
            }
            return Display(text: textWithCapabilities("\(prefix) \(title)", status.capabilities), failureDetail: nil)
        case .busy:
            let title = nonEmptyString(status.activity?.title) ?? "Busy"
            if let pct = percentageString(status.activity?.percentage) {
                return Display(text: textWithCapabilities("\(prefix) \(title) \(pct)", status.capabilities), failureDetail: nil)
            }
            return Display(text: textWithCapabilities("\(prefix) \(title)", status.capabilities), failureDetail: nil)
        case .failed:
            return Display(text: "\(prefix) Failed", failureDetail: detail)
        case .disabled, .unknown(_):
            return Display(text: "\(prefix) Off", failureDetail: nil)
        }
    }

    private static func statusPrefix(from status: EcuLspStatusSnapshot) -> String {
        var parts = ["LSP"]
        if let name = nonEmptyString(status.server?.name) ?? nonEmptyString(status.server?.command) {
            parts.append(name)
        }
        if let workspace = workspaceLabel(from: status.workspaceFolders) {
            parts.append("@ \(workspace)")
        }
        return "\(parts.joined(separator: " ")):"
    }

    private static func workspaceLabel(from folders: [EcuLspWorkspaceFolder]) -> String? {
        guard let first = folders.first else { return nil }
        guard var label = nonEmptyString(first.name) ?? workspaceLabel(fromURI: first.uri) else {
            return nil
        }
        if folders.count > 1 {
            label += " +\(folders.count - 1)"
        }
        return label
    }

    private static func workspaceLabel(fromURI uri: String) -> String? {
        if let url = URL(string: uri) {
            if let lastPathComponent = nonEmptyString(url.lastPathComponent) {
                return lastPathComponent
            }
            if let host = nonEmptyString(url.host) {
                return host
            }
        }
        return nonEmptyString(uri)
    }

    private static func textWithCapabilities(_ text: String, _ capabilities: EcuLspCapabilities?) -> String {
        guard let summary = capabilitySummary(from: capabilities) else { return text }
        return "\(text) [\(summary)]"
    }

    private static func capabilitySummary(from capabilities: EcuLspCapabilities?) -> String? {
        guard let capabilities else { return nil }
        var labels: [String] = []
        if capabilities.semanticTokens {
            labels.append("semantic")
        }
        if capabilities.semanticTokensDelta {
            labels.append("semantic delta")
        }
        if capabilities.completion.supported {
            labels.append("completion")
        }
        if capabilities.completionItemResolve {
            labels.append("completion resolve")
        }
        if capabilities.signatureHelp.supported {
            labels.append("signature")
        }
        if capabilities.foldingRanges {
            labels.append("folding")
        }
        if capabilities.onTypeFormatting {
            labels.append("on-type")
        }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    private static func percentageString(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(Int(value))%"
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let text = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
