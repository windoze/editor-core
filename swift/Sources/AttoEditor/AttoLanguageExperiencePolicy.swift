import EditorCoreUIFFI
import Foundation

enum AttoLanguageExperienceFeature: String, CaseIterable, Equatable {
    case highlighting
    case semanticTokens
    case diagnostics
    case symbols
    case folding

    var displayTitle: String {
        switch self {
        case .highlighting:
            return "Highlighting"
        case .semanticTokens:
            return "Semantic tokens"
        case .diagnostics:
            return "Diagnostics"
        case .symbols:
            return "Symbols"
        case .folding:
            return "Folding"
        }
    }
}

enum AttoLanguageExperienceProvider: Equatable {
    case lspSemanticTokens
    case lspDiagnostics
    case lspSymbols
    case lspFoldingRanges
    case treeSitterHighlighting
    case treeSitterFolding
    case sublimeHighlighting
    case sublimeFolding
    case plainText
    case unavailable

    var displayText: String {
        switch self {
        case .lspSemanticTokens:
            return "LSP semantic tokens"
        case .lspDiagnostics:
            return "LSP diagnostics"
        case .lspSymbols:
            return "LSP symbols"
        case .lspFoldingRanges:
            return "LSP folding ranges"
        case .treeSitterHighlighting:
            return "Tree-sitter"
        case .treeSitterFolding:
            return "Tree-sitter folds"
        case .sublimeHighlighting:
            return "Sublime syntax"
        case .sublimeFolding:
            return "Sublime folds"
        case .plainText:
            return "plain text"
        case .unavailable:
            return "unavailable"
        }
    }
}

struct AttoLanguageExperienceResolution: Equatable {
    let feature: AttoLanguageExperienceFeature
    let primary: AttoLanguageExperienceProvider
    let fallbacks: [AttoLanguageExperienceProvider]

    var displayText: String {
        guard fallbacks.isEmpty == false else {
            return "\(feature.displayTitle): \(primary.displayText)"
        }
        let fallbackText = fallbacks.map(\.displayText).joined(separator: " -> ")
        return "\(feature.displayTitle): \(primary.displayText) (fallback \(fallbackText))"
    }
}

enum AttoLanguageExperiencePolicy {
    static func resolutions(
        for source: AttoLanguageSupportSource,
        lspCapabilities: EcuLspCapabilities?
    ) -> [AttoLanguageExperienceResolution] {
        [
            highlightingResolution(for: source),
            semanticTokensResolution(for: source),
            diagnosticsResolution(for: source),
            symbolsResolution(for: source),
            foldingResolution(for: source, lspCapabilities: lspCapabilities),
        ]
    }

    static func summaryText(
        for source: AttoLanguageSupportSource,
        lspCapabilities: EcuLspCapabilities?
    ) -> String {
        resolutions(for: source, lspCapabilities: lspCapabilities)
            .map(\.displayText)
            .joined(separator: "; ")
    }

    private static func highlightingResolution(
        for source: AttoLanguageSupportSource
    ) -> AttoLanguageExperienceResolution {
        let primary: AttoLanguageExperienceProvider
        switch source {
        case .lspSemantic:
            primary = .lspSemanticTokens
        case .lspTreeSitter, .treeSitter:
            primary = .treeSitterHighlighting
        case .sublimeSyntax:
            primary = .sublimeHighlighting
        case .lspServices, .plainText:
            primary = .plainText
        }
        return AttoLanguageExperienceResolution(feature: .highlighting, primary: primary, fallbacks: [])
    }

    private static func semanticTokensResolution(
        for source: AttoLanguageSupportSource
    ) -> AttoLanguageExperienceResolution {
        let primary: AttoLanguageExperienceProvider = source == .lspSemantic ? .lspSemanticTokens : .unavailable
        return AttoLanguageExperienceResolution(feature: .semanticTokens, primary: primary, fallbacks: [])
    }

    private static func diagnosticsResolution(
        for source: AttoLanguageSupportSource
    ) -> AttoLanguageExperienceResolution {
        let primary: AttoLanguageExperienceProvider = source.usesLspServices ? .lspDiagnostics : .unavailable
        return AttoLanguageExperienceResolution(feature: .diagnostics, primary: primary, fallbacks: [])
    }

    private static func symbolsResolution(
        for source: AttoLanguageSupportSource
    ) -> AttoLanguageExperienceResolution {
        let primary: AttoLanguageExperienceProvider = source.usesLspServices ? .lspSymbols : .unavailable
        return AttoLanguageExperienceResolution(feature: .symbols, primary: primary, fallbacks: [])
    }

    private static func foldingResolution(
        for source: AttoLanguageSupportSource,
        lspCapabilities: EcuLspCapabilities?
    ) -> AttoLanguageExperienceResolution {
        let lspFolding = lspCapabilities?.foldingRanges == true
        switch source {
        case .lspTreeSitter:
            return AttoLanguageExperienceResolution(
                feature: .folding,
                primary: lspFolding ? .lspFoldingRanges : .treeSitterFolding,
                fallbacks: lspFolding ? [.treeSitterFolding] : []
            )
        case .lspSemantic, .lspServices:
            return AttoLanguageExperienceResolution(
                feature: .folding,
                primary: lspFolding ? .lspFoldingRanges : .unavailable,
                fallbacks: []
            )
        case .treeSitter:
            return AttoLanguageExperienceResolution(feature: .folding, primary: .treeSitterFolding, fallbacks: [])
        case .sublimeSyntax:
            return AttoLanguageExperienceResolution(feature: .folding, primary: .sublimeFolding, fallbacks: [])
        case .plainText:
            return AttoLanguageExperienceResolution(feature: .folding, primary: .unavailable, fallbacks: [])
        }
    }
}

private extension AttoLanguageSupportSource {
    var usesLspServices: Bool {
        switch self {
        case .lspServices, .lspSemantic, .lspTreeSitter:
            return true
        case .plainText, .treeSitter, .sublimeSyntax:
            return false
        }
    }
}
