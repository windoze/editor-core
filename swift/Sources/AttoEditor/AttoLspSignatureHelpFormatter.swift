import Foundation

enum AttoLspSignatureHelpFormatter {
    struct SignatureHelp {
        let signatures: [Signature]
        let activeSignature: Int
        let activeParameter: Int?
    }

    struct Signature {
        let label: String
        let documentation: String?
        let parameters: [Parameter]
        let activeParameter: Int?
    }

    struct Parameter {
        let label: ParameterLabel
    }

    enum ParameterLabel: Equatable {
        case string(String)
        case utf16Range(NSRange)
    }

    struct Display {
        let text: String
        let activeParameterRanges: [NSRange]
    }

    static func displayText(fromSignatureHelpResultJSON json: String) -> String? {
        display(fromSignatureHelpResultJSON: json)?.text
    }

    static func display(fromSignatureHelpResultJSON json: String) -> Display? {
        guard let help = parse(fromSignatureHelpResultJSON: json) else { return nil }
        return display(from: help)
    }

    static func parse(fromSignatureHelpResultJSON json: String) -> SignatureHelp? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard !(root is NSNull) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        guard let signatures = dict["signatures"] as? [[String: Any]], signatures.isEmpty == false else {
            return nil
        }

        let parsedSignatures = signatures.compactMap(parseSignature(_:))
        guard parsedSignatures.isEmpty == false else { return nil }
        return SignatureHelp(
            signatures: parsedSignatures,
            activeSignature: clamp(
                intValue(dict["activeSignature"]) ?? 0,
                lower: 0,
                upper: parsedSignatures.count - 1
            ),
            activeParameter: intValue(dict["activeParameter"])
        )
    }

    static func display(from help: SignatureHelp) -> Display? {
        guard help.signatures.isEmpty == false else { return nil }
        let activeSignature = clamp(
            help.activeSignature,
            lower: 0,
            upper: help.signatures.count - 1
        )
        let sig = help.signatures[activeSignature]
        let label = sig.label

        var text = label
        var activeParameterRanges: [NSRange] = []

        if let activeParam = activeParameterDisplay(signature: sig, help: help) {
            if let signatureRange = activeParam.signatureRange {
                activeParameterRanges.append(signatureRange)
            }

            let prefix = "parameter: "
            let parameterLineStart = text.utf16.count + 1
            text += "\n\(prefix)\(activeParam.text)"
            activeParameterRanges.append(NSRange(
                location: parameterLineStart + prefix.utf16.count,
                length: activeParam.text.utf16.count
            ))
        }

        if let documentation = sig.documentation {
            text += "\n\n\(documentation)"
        }

        return Display(text: text, activeParameterRanges: activeParameterRanges)
    }

    static func messageDisplay(_ message: String) -> Display {
        Display(text: message, activeParameterRanges: [])
    }

    private struct ParameterDisplay {
        let text: String
        let signatureRange: NSRange?
    }

    private static func activeParameterDisplay(signature sig: Signature, help: SignatureHelp) -> ParameterDisplay? {
        guard sig.parameters.isEmpty == false else {
            return nil
        }

        let idx = clamp(
            sig.activeParameter ?? help.activeParameter ?? 0,
            lower: 0,
            upper: sig.parameters.count - 1
        )
        let param = sig.parameters[idx]

        switch param.label {
        case let .string(label):
            let signatureRange = sig.label.range(of: label).map { NSRange($0, in: sig.label) }
            return ParameterDisplay(text: label, signatureRange: signatureRange)
        case let .utf16Range(range):
            guard let substring = substringUTF16(
                sig.label,
                start: range.location,
                end: range.location + range.length
            ) else { return nil }
            return ParameterDisplay(text: substring.text, signatureRange: substring.range)
        }
    }

    private static func parseSignature(_ dict: [String: Any]) -> Signature? {
        guard let label = dict["label"] as? String, label.isEmpty == false else { return nil }
        let parameters = (dict["parameters"] as? [[String: Any]] ?? [])
            .compactMap(parseParameter(_:))
        return Signature(
            label: label,
            documentation: markdownText(dict["documentation"]),
            parameters: parameters,
            activeParameter: intValue(dict["activeParameter"])
        )
    }

    private static func parseParameter(_ dict: [String: Any]) -> Parameter? {
        guard let label = parameterLabel(dict["label"]) else { return nil }
        return Parameter(label: label)
    }

    private static func parameterLabel(_ any: Any?) -> ParameterLabel? {
        if let label = any as? String, label.isEmpty == false {
            return .string(label)
        }
        if let range = any as? [Any],
           range.count == 2,
           let start = intValue(range[0]),
           let end = intValue(range[1]),
           end > start
        {
            return .utf16Range(NSRange(location: start, length: end - start))
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

    private static func substringUTF16(_ text: String, start: Int, end: Int) -> (text: String, range: NSRange)? {
        let utf16 = text.utf16
        let safeStart = max(0, min(start, utf16.count))
        let safeEnd = max(safeStart, min(end, utf16.count))
        guard safeEnd > safeStart else { return nil }
        let utf16Start = utf16.index(utf16.startIndex, offsetBy: safeStart)
        let utf16End = utf16.index(utf16.startIndex, offsetBy: safeEnd)
        guard let startIdx = String.Index(utf16Start, within: text),
              let endIdx = String.Index(utf16End, within: text)
        else {
            return nil
        }
        let out = String(text[startIdx..<endIdx])
        return out.isEmpty ? nil : (out, NSRange(location: safeStart, length: safeEnd - safeStart))
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
