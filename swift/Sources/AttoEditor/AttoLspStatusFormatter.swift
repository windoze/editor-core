import Foundation

struct AttoLspStatusFormatter {
    struct Display: Equatable {
        let text: String
        let failureDetail: String?
    }

    static func display(statusJSON: String, fallbackEnabled: Bool) -> Display {
        guard let data = statusJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return Display(text: fallbackEnabled ? "LSP: on" : "LSP: off", failureDetail: nil)
        }

        let state = (obj["state"] as? String) ?? "disabled"
        let detail = nonEmptyString(obj["detail"])
        let prefix = statusPrefix(from: obj)

        switch state {
        case "ready":
            return Display(text: "\(prefix) Ready", failureDetail: nil)
        case "indexing":
            let activity = obj["activity"] as? [String: Any]
            let title = nonEmptyString(activity?["title"]) ?? "Indexing"
            if let pct = percentageString(activity?["percentage"]) {
                return Display(text: "\(prefix) \(title) \(pct)", failureDetail: nil)
            }
            return Display(text: "\(prefix) \(title)", failureDetail: nil)
        case "busy":
            let activity = obj["activity"] as? [String: Any]
            let title = nonEmptyString(activity?["title"]) ?? "Busy"
            if let pct = percentageString(activity?["percentage"]) {
                return Display(text: "\(prefix) \(title) \(pct)", failureDetail: nil)
            }
            return Display(text: "\(prefix) \(title)", failureDetail: nil)
        case "failed":
            return Display(text: "\(prefix) Failed", failureDetail: detail)
        default:
            return Display(text: "\(prefix) Off", failureDetail: nil)
        }
    }

    private static func statusPrefix(from obj: [String: Any]) -> String {
        if let server = obj["server"] as? [String: Any],
           let name = nonEmptyString(server["name"]) ?? nonEmptyString(server["command"]) {
            return "LSP \(name):"
        }
        return "LSP:"
    }

    private static func percentageString(_ value: Any?) -> String? {
        if let p = value as? UInt { return "\(p)%" }
        if let p = value as? Int { return "\(p)%" }
        if let p = value as? Double { return "\(Int(p))%" }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
