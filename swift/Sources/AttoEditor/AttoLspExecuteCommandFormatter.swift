import Foundation

enum AttoLspExecuteCommandFormatter {
    static func displayText(forResultJSON json: String, commandTitle: String?) -> String {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return joinedTitle("Command completed.", detail: json, commandTitle: commandTitle)
        }

        if let object = root as? [String: Any],
           let error = object["error"] as? [String: Any]
        {
            let message = stringValue(error["message"]) ?? "Unknown LSP error."
            var detail = message
            if let code = intValue(error["code"]) {
                detail += "\nCode: \(code)"
            }
            if let data = error["data"] {
                detail += "\nData: \(jsonPreview(data))"
            }
            return joinedTitle("Command failed.", detail: detail, commandTitle: commandTitle)
        }

        if let object = root as? [String: Any], object.keys.contains("result") {
            let result = object["result"] ?? NSNull()
            if result is NSNull {
                return joinedTitle("Command completed.", detail: nil, commandTitle: commandTitle)
            }
            return joinedTitle("Command completed.", detail: jsonPreview(result), commandTitle: commandTitle)
        }

        return joinedTitle("Command completed.", detail: jsonPreview(root), commandTitle: commandTitle)
    }

    static func timeoutText(commandTitle: String?) -> String {
        joinedTitle(
            "Command result was not returned.",
            detail: "The server may have returned null, failed without a payload, or not responded yet.",
            commandTitle: commandTitle
        )
    }

    private static func joinedTitle(_ title: String, detail: String?, commandTitle: String?) -> String {
        var lines = [title]
        if let commandTitle, commandTitle.isEmpty == false {
            lines.append("Command: \(commandTitle)")
        }
        if let detail, detail.isEmpty == false {
            lines.append("")
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }

    private static func jsonPreview(_ value: Any) -> String {
        if let string = value as? String {
            return truncated(string)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if value is NSNull {
            return "null"
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return truncated(text)
    }

    private static func truncated(_ text: String) -> String {
        let limit = 900
        guard text.count > limit else { return text }
        let idx = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<idx]) + "\n..."
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
