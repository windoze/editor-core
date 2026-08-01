import Foundation

enum AttoLspCodeActionContext {
    static func contextJSON(
        diagnosticsJSON: String,
        documentText: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) -> String {
        let diagnostics = lspDiagnostics(
            diagnosticsJSON: diagnosticsJSON,
            documentText: documentText,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd
        )
        return jsonString(["diagnostics": diagnostics]) ?? #"{"diagnostics":[]}"#
    }

    static func lspDiagnostics(
        diagnosticsJSON: String,
        documentText: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) -> [[String: Any]] {
        guard let data = diagnosticsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = root as? [String: Any],
              let diagnostics = dict["diagnostics"] as? [[String: Any]]
        else {
            return []
        }

        let selection = normalizedRange(selectionStart, selectionEnd)
        return diagnostics.compactMap { diagnostic in
            guard let range = diagnostic["range"] as? [String: Any],
                  let start = intValue(range["start"]),
                  let end = intValue(range["end"])
            else {
                return nil
            }

            let diagnosticRange = normalizedRange(UInt32(clamping: start), UInt32(clamping: end))
            guard intersectsOrContainsCaret(diagnosticRange, selection) else { return nil }

            var out: [String: Any] = [
                "range": [
                    "start": lspPosition(in: documentText, charOffset: diagnosticRange.start),
                    "end": lspPosition(in: documentText, charOffset: diagnosticRange.end),
                ],
                "message": stringValue(diagnostic["message"]) ?? "",
            ]

            if let severity = lspSeverity(diagnostic["severity"]) {
                out["severity"] = severity
            }
            if let code = diagnostic["code"] as? String {
                out["code"] = code
            } else if let code = diagnostic["code"] as? NSNumber {
                out["code"] = code
            }
            if let source = stringValue(diagnostic["source"]) {
                out["source"] = source
            }
            if let relatedInformation = jsonValue(fromJSONString: stringValue(diagnostic["related_information_json"])) {
                out["relatedInformation"] = relatedInformation
            }
            if let data = jsonValue(fromJSONString: stringValue(diagnostic["data_json"])) {
                out["data"] = data
            }

            return out
        }
    }

    private static func normalizedRange(_ a: UInt32, _ b: UInt32) -> (start: UInt32, end: UInt32) {
        (min(a, b), max(a, b))
    }

    private static func intersectsOrContainsCaret(
        _ diagnostic: (start: UInt32, end: UInt32),
        _ selection: (start: UInt32, end: UInt32)
    ) -> Bool {
        if selection.start == selection.end {
            return diagnostic.start <= selection.start && selection.start <= diagnostic.end
        }
        return diagnostic.start <= selection.end && selection.start <= diagnostic.end
    }

    private static func lspPosition(in text: String, charOffset: UInt32) -> [String: Int] {
        let limit = min(Int(charOffset), text.unicodeScalars.count)
        var line = 0
        var utf16Column = 0

        for scalar in text.unicodeScalars.prefix(limit) {
            if scalar == "\n" {
                line += 1
                utf16Column = 0
            } else {
                utf16Column += String(scalar).utf16.count
            }
        }

        return ["line": line, "character": utf16Column]
    }

    private static func lspSeverity(_ value: Any?) -> Int? {
        if let int = intValue(value), (1...4).contains(int) {
            return int
        }
        guard let string = stringValue(value)?.lowercased() else { return nil }
        switch string {
        case "error": return 1
        case "warning": return 2
        case "information": return 3
        case "hint": return 4
        default: return nil
        }
    }

    private static func jsonValue(fromJSONString string: String?) -> Any? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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
