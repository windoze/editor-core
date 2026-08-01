import EditorCoreUIFFI
import Foundation

struct AttoDerivedStateSnapshot: Equatable {
    var diagnostics: EcuDiagnosticsSnapshot
    var decorations: EcuDecorationsSnapshot
    var documentSymbols: EcuDocumentSymbolsSnapshot
    var foldingRegions: EcuFoldingRegionsSnapshot
    var styleIntervals: EcuStyleIntervalsSnapshot

    static let empty = AttoDerivedStateSnapshot(
        diagnostics: EcuDiagnosticsSnapshot(diagnostics: []),
        decorations: EcuDecorationsSnapshot(layers: []),
        documentSymbols: EcuDocumentSymbolsSnapshot(symbols: []),
        foldingRegions: EcuFoldingRegionsSnapshot(regions: []),
        styleIntervals: EcuStyleIntervalsSnapshot(layers: [])
    )

    var problemsStatusText: String? {
        let count = diagnostics.diagnostics.count
        guard count > 0 else { return nil }
        return count == 1 ? "Problems: 1" : "Problems: \(count)"
    }

    var foldedStatusText: String? {
        let count = foldingRegions.regions.filter(\.isCollapsed).count
        guard count > 0 else { return nil }
        return count == 1 ? "Folded: 1" : "Folded: \(count)"
    }

    var codeLensStatusText: String? {
        let count = AttoLspCodeLensParser.items(fromDecorationsSnapshot: decorations).count
        guard count > 0 else { return nil }
        return count == 1 ? "Code Lens: 1" : "Code Lens: \(count)"
    }

    var statusBarLeftText: String? {
        let parts = [problemsStatusText, foldedStatusText, codeLensStatusText].compactMap { $0 }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " | ")
    }
}

final class AttoDerivedStateStore {
    private(set) var active: AttoDerivedStateSnapshot = .empty

    func clearActive() {
        active = .empty
    }

    func refreshActive(editor: EditorUI) {
        let textLength = UInt32(clamping: ((try? editor.text()) ?? "").unicodeScalars.count)
        active = AttoDerivedStateSnapshot(
            diagnostics: (try? editor.diagnosticsSnapshot()) ?? EcuDiagnosticsSnapshot(diagnostics: []),
            decorations: (try? editor.decorationsSnapshot()) ?? EcuDecorationsSnapshot(layers: []),
            documentSymbols: (try? editor.documentSymbolsSnapshot()) ?? EcuDocumentSymbolsSnapshot(symbols: []),
            foldingRegions: (try? editor.foldingRegionsSnapshot()) ?? EcuFoldingRegionsSnapshot(regions: []),
            styleIntervals: (try? editor.styleIntervalsSnapshot(start: 0, end: textLength)) ?? EcuStyleIntervalsSnapshot(layers: [])
        )
    }
}
