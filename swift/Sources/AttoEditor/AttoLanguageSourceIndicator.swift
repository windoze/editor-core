import Foundation
import EditorCoreUIFFI

enum AttoLanguageSupportSource: String, Codable, Equatable {
    case plainText = "plain_text"
    case lspServices = "lsp_services"
    case lspSemantic = "lsp_semantic"
    case lspTreeSitter = "lsp_tree_sitter"
    case treeSitter = "tree_sitter"
    case sublimeSyntax = "sublime_syntax"
}

struct AttoLanguageSourceIndicator: Equatable {
    let source: AttoLanguageSupportSource
    let languageId: String?
    let lspCapabilities: EcuLspCapabilities?
    let fallbackReasons: [String]

    init(
        source: AttoLanguageSupportSource,
        languageId: String?,
        lspCapabilities: EcuLspCapabilities? = nil,
        fallbackReasons: [String] = []
    ) {
        self.source = source
        self.languageId = languageId
        self.lspCapabilities = lspCapabilities
        self.fallbackReasons = fallbackReasons
    }

    var statusText: String {
        switch source {
        case .plainText:
            return "Plain Text"
        case .lspServices:
            return "LSP"
        case .lspSemantic:
            return "LSP semantic"
        case .lspTreeSitter:
            return "LSP + Tree-sitter"
        case .treeSitter:
            return "Tree-sitter"
        case .sublimeSyntax:
            return "Sublime baseline"
        }
    }

    var tooltipText: String {
        let suffix = languageId.map { " (\($0))" } ?? ""
        let base: String = {
            switch source {
            case .plainText:
                return "Language source: plain text\(suffix)"
            case .lspServices:
                return "Language source: LSP language services\(suffix)"
            case .lspSemantic:
                return "Language source: LSP semantic tokens\(suffix)"
            case .lspTreeSitter:
                return "Language source: LSP language services plus Tree-sitter syntax\(suffix)"
            case .treeSitter:
                return "Language source: Tree-sitter syntax\(suffix)"
            case .sublimeSyntax:
                return "Language source: Sublime syntax baseline\(suffix)"
            }
        }()

        let featureSummary = AttoLanguageExperiencePolicy.summaryText(
            for: source,
            lspCapabilities: lspCapabilities
        )
        let fallbackSummary = normalizedFallbackReasons()
        guard fallbackSummary.isEmpty == false else {
            return "\(base)\nFeatures: \(featureSummary)"
        }
        return "\(base)\nFeatures: \(featureSummary)\nFallback: \(fallbackSummary.joined(separator: " "))"
    }

    private func normalizedFallbackReasons() -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for reason in fallbackReasons {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}
