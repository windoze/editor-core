import Foundation

enum AttoLspHoverFormatter {
    static func displayText(fromHoverResultJSON json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard let contents = obj["contents"] else { return nil }
        return normalize(contents: contents)
    }

    private static func normalize(contents: Any) -> String? {
        if let s = contents as? String {
            return normalize(string: s)
        }

        if let arr = contents as? [Any] {
            let parts = arr.compactMap { normalize(contents: $0) }
            return normalize(string: parts.joined(separator: "\n\n"))
        }

        if let dict = contents as? [String: Any] {
            // MarkupContent: { kind: "markdown"|"plaintext", value: "..." }
            if let value = dict["value"] as? String {
                return normalize(string: value)
            }
        }

        return nil
    }

    private static func normalize(string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

