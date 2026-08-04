import Foundation
import EditorCoreUIFFI

enum AttoLspSignatureHelpFormatter {
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

    static func parse(fromSignatureHelpResultJSON json: String) -> EcuLspSignatureHelpResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let help = try? JSONDecoder().decode(EcuLspSignatureHelpResult.self, from: data) else { return nil }
        return help.isEmpty ? nil : help
    }

    static func display(from help: EcuLspSignatureHelpResult) -> Display? {
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

        if let documentation = sig.documentation?.text {
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

    private static func activeParameterDisplay(
        signature sig: EcuLspSignatureInformation,
        help: EcuLspSignatureHelpResult
    ) -> ParameterDisplay? {
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
            guard label.isEmpty == false else { return nil }
            let signatureRange = sig.label.range(of: label).map { NSRange($0, in: sig.label) }
            return ParameterDisplay(text: label, signatureRange: signatureRange)
        case let .utf16Range(start, end):
            guard let substring = substringUTF16(
                sig.label,
                start: Int(start),
                end: Int(end)
            ) else { return nil }
            return ParameterDisplay(text: substring.text, signatureRange: substring.range)
        case .unknown:
            return nil
        }
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

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        max(lower, min(value, upper))
    }
}
