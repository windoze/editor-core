@testable import AttoEditor
import XCTest

final class AttoLanguageSourceIndicatorTests: XCTestCase {
    func testStatusTextNamesPrimaryLanguageSource() {
        XCTAssertEqual(
            AttoLanguageSourceIndicator(source: .lspSemantic, languageId: "rust").statusText,
            "LSP semantic"
        )
        XCTAssertEqual(
            AttoLanguageSourceIndicator(source: .lspTreeSitter, languageId: "rust").statusText,
            "LSP + Tree-sitter"
        )
        XCTAssertEqual(
            AttoLanguageSourceIndicator(source: .treeSitter, languageId: "swift").statusText,
            "Tree-sitter"
        )
        XCTAssertEqual(
            AttoLanguageSourceIndicator(source: .sublimeSyntax, languageId: nil).statusText,
            "Sublime baseline"
        )
        XCTAssertEqual(
            AttoLanguageSourceIndicator(source: .plainText, languageId: nil).statusText,
            "Plain Text"
        )
    }

    func testTooltipIncludesLanguageWhenKnown() {
        let lsp = AttoLanguageSourceIndicator(source: .lspSemantic, languageId: "rust")
        XCTAssertEqual(lsp.tooltipText, "Language source: LSP semantic tokens (rust)")

        let fallback = AttoLanguageSourceIndicator(source: .sublimeSyntax, languageId: nil)
        XCTAssertEqual(fallback.tooltipText, "Language source: Sublime syntax baseline")
    }
}
