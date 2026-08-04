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
    private(set) var activeIsStale = false
    private(set) var activeLspStatus: EcuLspStatusSnapshot?
    private(set) var lastStateEventKinds: [EcuEditorUIStateEventKind] = []
    private(set) var lastStateEventSequence: UInt64 = 0
    private(set) var snapshotRefreshCount = 0
    private var activeEditorID: ObjectIdentifier?
    private var hasActiveSnapshot = false

    func clearActive() {
        active = .empty
        activeIsStale = false
        activeLspStatus = nil
        lastStateEventKinds = []
        lastStateEventSequence = 0
        snapshotRefreshCount = 0
        activeEditorID = nil
        hasActiveSnapshot = false
    }

    func refreshActive(editor: EditorUI) {
        let editorID = ObjectIdentifier(editor)
        if activeEditorID != editorID {
            activeEditorID = editorID
            active = .empty
            activeIsStale = false
            activeLspStatus = nil
            lastStateEventKinds = []
            lastStateEventSequence = 0
            hasActiveSnapshot = false
        }

        do {
            let events = try editor.stateEvents(after: lastStateEventSequence)
            lastStateEventSequence = events.latestSequence
            lastStateEventKinds = events.events.map(\.kindValue)

            var shouldRefreshSnapshot = hasActiveSnapshot == false
            var stale = activeIsStale
            for event in events.events {
                switch event.kindValue {
                case .derivedStateChanged:
                    shouldRefreshSnapshot = true
                    stale = false
                case .viewportChanged:
                    shouldRefreshSnapshot = true
                case .derivedStateStale:
                    stale = true
                case .lspStatusChanged:
                    activeLspStatus = event.lspStatus
                default:
                    continue
                }
            }

            if shouldRefreshSnapshot {
                refreshActiveFromSnapshots(editor: editor)
            }
            activeIsStale = stale
        } catch {
            lastStateEventKinds = []
            activeLspStatus = nil
            refreshActiveFromSnapshots(editor: editor)
            activeIsStale = false
        }
    }

    private func refreshActiveFromSnapshots(editor: EditorUI) {
        let textLength = UInt32(clamping: ((try? editor.text()) ?? "").unicodeScalars.count)
        active = AttoDerivedStateSnapshot(
            diagnostics: (try? editor.diagnosticsSnapshot()) ?? EcuDiagnosticsSnapshot(diagnostics: []),
            decorations: (try? editor.decorationsSnapshot()) ?? EcuDecorationsSnapshot(layers: []),
            documentSymbols: (try? editor.documentSymbolsSnapshot()) ?? EcuDocumentSymbolsSnapshot(symbols: []),
            foldingRegions: (try? editor.foldingRegionsSnapshot()) ?? EcuFoldingRegionsSnapshot(regions: []),
            styleIntervals: (try? editor.styleIntervalsSnapshot(start: 0, end: textLength)) ?? EcuStyleIntervalsSnapshot(layers: [])
        )
        hasActiveSnapshot = true
        snapshotRefreshCount += 1
    }
}
