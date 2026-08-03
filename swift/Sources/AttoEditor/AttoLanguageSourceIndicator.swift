import Foundation

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
    }
}
