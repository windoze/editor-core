import Foundation

enum AttoLspSignatureHelpFormatter {
    static func displayText(fromSignatureHelpResultJSON json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard !(root is NSNull) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        guard let signatures = dict["signatures"] as? [[String: Any]], signatures.isEmpty == false else {
            return nil
        }

        let activeSignature = clamp(
            intValue(dict["activeSignature"]) ?? 0,
            lower: 0,
            upper: signatures.count - 1
        )
        let sig = signatures[activeSignature]
        guard let label = sig["label"] as? String, label.isEmpty == false else { return nil }

        var lines: [String] = [label]

        if let activeParamText = activeParameterText(signature: sig, help: dict) {
            lines.append("parameter: \(activeParamText)")
        }

        if let documentation = markdownText(sig["documentation"]) {
            lines.append("")
            lines.append(documentation)
        }

        return lines.joined(separator: "\n")
    }

    private static func activeParameterText(signature sig: [String: Any], help: [String: Any]) -> String? {
        guard let params = sig["parameters"] as? [[String: Any]], params.isEmpty == false else {
            return nil
        }

        let idx = clamp(
            intValue(sig["activeParameter"]) ?? intValue(help["activeParameter"]) ?? 0,
            lower: 0,
            upper: params.count - 1
        )
        let param = params[idx]

        if let label = param["label"] as? String, label.isEmpty == false {
            return label
        }

        if let range = param["label"] as? [Any],
           range.count == 2,
           let start = intValue(range[0]),
           let end = intValue(range[1]),
           let sigLabel = sig["label"] as? String
        {
            return substringUTF16(sigLabel, start: start, end: end)
        }

        return nil
    }

    private static func markdownText(_ any: Any?) -> String? {
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : s
        }
        if let dict = any as? [String: Any],
           let value = dict["value"] as? String
        {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }
        return nil
    }

    private static func substringUTF16(_ text: String, start: Int, end: Int) -> String? {
        let utf16 = text.utf16
        let safeStart = max(0, min(start, utf16.count))
        let safeEnd = max(safeStart, min(end, utf16.count))
        let utf16Start = utf16.index(utf16.startIndex, offsetBy: safeStart)
        let utf16End = utf16.index(utf16.startIndex, offsetBy: safeEnd)
        guard let startIdx = String.Index(utf16Start, within: text),
              let endIdx = String.Index(utf16End, within: text)
        else {
            return nil
        }
        let out = String(text[startIdx..<endIdx])
        return out.isEmpty ? nil : out
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        max(lower, min(value, upper))
    }
}
