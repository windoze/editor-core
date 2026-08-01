import EditorCoreUIFFI
import Foundation

enum AttoLspDocumentColorParser {
    struct Color: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    struct Item: Equatable {
        let range: EcuSelectionRange
        let startLine: Int
        let startUTF16Character: Int
        let color: Color
    }

    struct Presentation: Equatable {
        let label: String
        let edits: [EcuTextEdit]

        var isApplicable: Bool {
            edits.isEmpty == false
        }
    }

    static func items(fromDocumentColorResultJSON json: String, documentText: String) -> [Item] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []),
              let array = root as? [Any]
        else {
            return []
        }

        return array.compactMap { any in
            guard let object = any as? [String: Any],
                  let rangeObject = object["range"] as? [String: Any],
                  let colorObject = object["color"] as? [String: Any],
                  let range = range(from: rangeObject, documentText: documentText),
                  let color = color(from: colorObject)
            else {
                return nil
            }
            return Item(
                range: range.selectionRange,
                startLine: range.startLine,
                startUTF16Character: range.startUTF16Character,
                color: color
            )
        }
    }

    static func presentations(fromColorPresentationResultJSON json: String, documentText: String) -> [Presentation] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []),
              let array = root as? [Any]
        else {
            return []
        }

        return array.compactMap { any in
            guard let object = any as? [String: Any],
                  let label = stringValue(object["label"]),
                  label.isEmpty == false
            else {
                return nil
            }

            var edits: [EcuTextEdit] = []
            if let textEdit = textEdit(from: object["textEdit"], documentText: documentText) {
                edits.append(textEdit)
            }
            edits.append(contentsOf: textEdits(from: object["additionalTextEdits"], documentText: documentText))
            return Presentation(label: label, edits: edits)
        }
    }

    static func colorJSON(for item: Item) -> String? {
        let object: [String: Double] = [
            "red": item.color.red,
            "green": item.color.green,
            "blue": item.color.blue,
            "alpha": item.color.alpha,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func displayTitle(for item: Item) -> String {
        "\(hexString(for: item.color)) at \(item.startLine + 1):\(item.startUTF16Character + 1)"
    }

    static func displayTitle(for presentation: Presentation) -> String {
        presentation.isApplicable ? "\(presentation.label)  [apply]" : "\(presentation.label)  [label only]"
    }

    static func hexString(for color: Color) -> String {
        let r = byte(color.red)
        let g = byte(color.green)
        let b = byte(color.blue)
        let a = byte(color.alpha)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    private static func range(
        from object: [String: Any],
        documentText: String
    ) -> (selectionRange: EcuSelectionRange, startLine: Int, startUTF16Character: Int)? {
        guard let start = object["start"] as? [String: Any],
              let end = object["end"] as? [String: Any],
              let startLine = intValue(start["line"]),
              let startCharacter = intValue(start["character"]),
              let endLine = intValue(end["line"]),
              let endCharacter = intValue(end["character"])
        else {
            return nil
        }

        let startOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: startLine,
            utf16Character: startCharacter
        )
        let endOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: endLine,
            utf16Character: endCharacter
        )

        return (
            EcuSelectionRange(start: min(startOffset, endOffset), end: max(startOffset, endOffset)),
            startLine,
            startCharacter
        )
    }

    private static func textEdits(from any: Any?, documentText: String) -> [EcuTextEdit] {
        guard let array = any as? [Any] else { return [] }
        return array.compactMap { textEdit(from: $0, documentText: documentText) }
    }

    private static func textEdit(from any: Any?, documentText: String) -> EcuTextEdit? {
        guard let object = any as? [String: Any],
              let rangeObject = object["range"] as? [String: Any],
              let newText = stringValue(object["newText"]),
              let range = range(from: rangeObject, documentText: documentText)
        else {
            return nil
        }
        return EcuTextEdit(start: range.selectionRange.start, end: range.selectionRange.end, text: newText)
    }

    private static func color(from object: [String: Any]) -> Color? {
        guard let red = doubleValue(object["red"]),
              let green = doubleValue(object["green"]),
              let blue = doubleValue(object["blue"]),
              let alpha = doubleValue(object["alpha"])
        else {
            return nil
        }
        return Color(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func byte(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 255).rounded())
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let number = any as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        any as? String
    }
}
