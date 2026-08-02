import Foundation
import EditorCoreUIFFI

enum AttoLspHoverFormatter {
    static func displayText(fromHoverResult result: EcuLspHoverResult) -> String? {
        result.displayText
    }

    static func displayText(fromHoverResultJSON json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let result = try? JSONDecoder().decode(EcuLspHoverResult.self, from: data) else { return nil }
        return displayText(fromHoverResult: result)
    }
}
