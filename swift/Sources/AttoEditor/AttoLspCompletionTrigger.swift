import Foundation

enum AttoLspCompletionTrigger {
    static func shouldTrigger(committedText text: String, lspStatusJSON json: String) -> Bool {
        guard text.count == 1 else { return false }
        return triggerCharacters(fromLSPStatusJSON: json).contains(text)
    }

    static func triggerCharacters(fromLSPStatusJSON json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = root as? [String: Any],
              let capabilities = dict["capabilities"] as? [String: Any],
              let completion = capabilities["completion"] as? [String: Any]
        else {
            return []
        }
        if let supported = completion["supported"] as? Bool, supported == false {
            return []
        }

        var out = Set<String>()
        appendStrings(completion["trigger_characters"], to: &out)
        return out
    }

    private static func appendStrings(_ value: Any?, to out: inout Set<String>) {
        guard let strings = value as? [String] else { return }
        for string in strings where string.isEmpty == false {
            out.insert(string)
        }
    }
}
