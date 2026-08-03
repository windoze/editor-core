import EditorCoreUIFFI
import Foundation

enum AttoLspDocumentLinkParser {
    struct Item: Equatable {
        let title: String
        let target: String?
        let tooltip: String?
        let range: EcuOffsetRange
        let linkJSON: String
        let link: EcuLspDocumentLink?
    }

    static func items(fromDecorationsSnapshot snapshot: EcuDecorationsSnapshot) -> [Item] {
        snapshot.layers.flatMap { layer in
            layer.decorations.compactMap { decoration in
                guard isDocumentLinkKind(decoration.kind) else { return nil }
                guard let linkJSON = decoration.dataJSON else { return nil }
                return item(
                    fromDocumentLinkJSON: linkJSON,
                    fallbackTooltip: decoration.tooltip,
                    fallbackRange: decoration.range
                )
            }
        }
    }

    static func item(
        fromDocumentLinkJSON json: String,
        fallbackTooltip: String? = nil,
        fallbackRange: EcuOffsetRange = EcuOffsetRange(start: 0, end: 0)
    ) -> Item? {
        let link = try? JSONDecoder().decode(EcuLspDocumentLink.self, from: Data(json.utf8))
        let target = nonEmptyString(link?.target)
        let tooltip = nonEmptyString(link?.tooltip) ?? nonEmptyString(fallbackTooltip)
        let title = target ?? tooltip ?? "Unresolved Document Link"
        return Item(
            title: title,
            target: target,
            tooltip: tooltip,
            range: fallbackRange,
            linkJSON: json,
            link: link
        )
    }

    static func displayTitle(for item: Item, location: String?) -> String {
        var parts = [item.title]
        if item.target == nil {
            parts.append("[Resolve]")
        }
        if let location, location.isEmpty == false {
            parts.append("- \(location)")
        }
        return parts.joined(separator: " ")
    }

    private static func isDocumentLinkKind(_ value: EcuJSONValue) -> Bool {
        guard case .object(let dict) = value else { return false }
        guard case .string(let kind)? = dict["kind"] else { return false }
        return kind == "document_link"
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? value : nil
    }
}
