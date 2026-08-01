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
            return Display(text: "\(prefix) Ready", failureDetail: nil)
        case .indexing:
            let title = nonEmptyString(status.activity?.title) ?? "Indexing"
            if let pct = percentageString(status.activity?.percentage) {
                return Display(text: "\(prefix) \(title) \(pct)", failureDetail: nil)
            }
            return Display(text: "\(prefix) \(title)", failureDetail: nil)
        case .busy:
            let title = nonEmptyString(status.activity?.title) ?? "Busy"
            if let pct = percentageString(status.activity?.percentage) {
                return Display(text: "\(prefix) \(title) \(pct)", failureDetail: nil)
            }
            return Display(text: "\(prefix) \(title)", failureDetail: nil)
        case .failed:
            return Display(text: "\(prefix) Failed", failureDetail: detail)
        case .disabled, .unknown(_):
            return Display(text: "\(prefix) Off", failureDetail: nil)
        }
    }

    private static func statusPrefix(from status: EcuLspStatusSnapshot) -> String {
        if let name = nonEmptyString(status.server?.name) ?? nonEmptyString(status.server?.command) {
            return "LSP \(name):"
        }
        return "LSP:"
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
