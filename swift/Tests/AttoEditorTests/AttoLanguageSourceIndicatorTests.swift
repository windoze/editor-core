@testable import AttoEditor
import EditorCoreUIFFI
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
        XCTAssertEqual(
            lsp.tooltipText,
            """
            Language source: LSP semantic tokens (rust)
            Features: Highlighting: LSP semantic tokens; Semantic tokens: LSP semantic tokens; Diagnostics: LSP diagnostics; Symbols: LSP symbols; Folding: unavailable
            """
        )

        let fallback = AttoLanguageSourceIndicator(source: .sublimeSyntax, languageId: nil)
        XCTAssertEqual(
            fallback.tooltipText,
            """
            Language source: Sublime syntax baseline
            Features: Highlighting: Sublime syntax; Semantic tokens: unavailable; Diagnostics: unavailable; Symbols: unavailable; Folding: Sublime folds
            """
        )
    }

    func testFeaturePolicyPrioritizesLspSemanticAndFoldingSources() {
        let semantic = AttoLanguageExperiencePolicy.summaryText(
            for: .lspSemantic,
            lspCapabilities: EcuLspCapabilities(semanticTokens: true, foldingRanges: true)
        )
        XCTAssertEqual(
            semantic,
            "Highlighting: LSP semantic tokens; Semantic tokens: LSP semantic tokens; Diagnostics: LSP diagnostics; Symbols: LSP symbols; Folding: LSP folding ranges"
        )

        let treeSitterFallback = AttoLanguageExperiencePolicy.summaryText(
            for: .lspTreeSitter,
            lspCapabilities: EcuLspCapabilities(foldingRanges: true)
        )
        XCTAssertEqual(
            treeSitterFallback,
            "Highlighting: Tree-sitter; Semantic tokens: unavailable; Diagnostics: LSP diagnostics; Symbols: LSP symbols; Folding: LSP folding ranges (fallback Tree-sitter folds)"
        )

        let syntaxOnly = AttoLanguageExperiencePolicy.summaryText(
            for: .treeSitter,
            lspCapabilities: nil
        )
        XCTAssertEqual(
            syntaxOnly,
            "Highlighting: Tree-sitter; Semantic tokens: unavailable; Diagnostics: unavailable; Symbols: unavailable; Folding: Tree-sitter folds"
        )
    }

    func testTooltipIncludesNormalizedFallbackReasons() {
        let indicator = AttoLanguageSourceIndicator(
            source: .lspTreeSitter,
            languageId: "rust",
            lspCapabilities: EcuLspCapabilities(foldingRanges: false),
            fallbackReasons: [
                " LSP semantic tokens are unavailable. ",
                "",
                "LSP semantic tokens are unavailable.",
                "Tree-sitter syntax fallback is active.",
            ]
        )
        XCTAssertEqual(
            indicator.tooltipText,
            """
            Language source: LSP language services plus Tree-sitter syntax (rust)
            Features: Highlighting: Tree-sitter; Semantic tokens: unavailable; Diagnostics: LSP diagnostics; Symbols: LSP symbols; Folding: Tree-sitter folds
            Fallback: LSP semantic tokens are unavailable. Tree-sitter syntax fallback is active.
            """
        )
    }
}
