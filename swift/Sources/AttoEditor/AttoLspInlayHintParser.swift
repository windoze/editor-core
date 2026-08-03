import EditorCoreUIFFI
import Foundation

enum AttoLspInlayHintParser {
    struct Item: Equatable {
        let title: String
        let kindLabel: String?
        let range: EcuOffsetRange
        let hintJSON: String
        let hint: EcuLspInlayHint?
    }

    static func items(fromDecorationsSnapshot snapshot: EcuDecorationsSnapshot) -> [Item] {
        snapshot.layers.flatMap { layer in
            layer.decorations.compactMap { decoration in
                guard isInlayHintKind(decoration.kind) else { return nil }
                guard let hintJSON = decoration.dataJSON else { return nil }
                return item(
                    fromInlayHintJSON: hintJSON,
                    fallbackTitle: decoration.text,
                    fallbackRange: decoration.range
                )
            }
        }
    }

    static func item(
        fromInlayHintJSON json: String,
        fallbackTitle: String? = nil,
        fallbackRange: EcuOffsetRange = EcuOffsetRange(start: 0, end: 0)
    ) -> Item? {
        let hint = try? JSONDecoder().decode(EcuLspInlayHint.self, from: Data(json.utf8))
        let title = nonEmptyString(hint?.label.plainText) ?? nonEmptyString(fallbackTitle) ?? "Inlay Hint"
        return Item(
            title: title,
            kindLabel: hint?.kind.map(kindLabel),
            range: fallbackRange,
            hintJSON: json,
            hint: hint
        )
    }

    static func displayTitle(for item: Item, location: String?) -> String {
        var parts = [item.title]
        if let kindLabel = item.kindLabel {
            parts.append("[\(kindLabel)]")
        }
        if let location, location.isEmpty == false {
            parts.append("- \(location)")
        }
        return parts.joined(separator: " ")
    }

    private static func isInlayHintKind(_ value: EcuJSONValue) -> Bool {
        guard case .object(let dict) = value else { return false }
        guard case .string(let kind)? = dict["kind"] else { return false }
        return kind == "inlay_hint"
    }

    private static func kindLabel(_ kind: EcuLspInlayHintKind) -> String {
        switch kind {
        case .type:
            return "Type"
        case .parameter:
            return "Parameter"
        case .unknown(let value):
            return "Kind \(value)"
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? value : nil
    }
}
