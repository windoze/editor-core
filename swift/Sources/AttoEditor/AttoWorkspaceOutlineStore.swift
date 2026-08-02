import Foundation

struct AttoWorkspaceOutlineDocument: Equatable {
    let tabID: UUID?
    let coreTabID: UInt64?
    let uri: String
    let title: String
    let path: String
    let symbolCount: Int
}

struct AttoWorkspaceOutlineSnapshot: Equatable {
    let documents: [AttoWorkspaceOutlineDocument]
    let symbols: [AttoLspSymbolParser.Symbol]

    static let empty = AttoWorkspaceOutlineSnapshot(documents: [], symbols: [])
}

final class AttoWorkspaceOutlineStore {
    private struct DocumentEntry {
        let document: AttoWorkspaceOutlineDocument
        let symbols: [AttoLspSymbolParser.Symbol]
    }

    private var entriesByURI: [String: DocumentEntry] = [:]
    private var documentOrder: [String] = []

    var snapshot: AttoWorkspaceOutlineSnapshot {
        let entries = documentOrder.compactMap { entriesByURI[$0] }
        return AttoWorkspaceOutlineSnapshot(
            documents: entries.map(\.document),
            symbols: entries.flatMap(\.symbols)
        )
    }

    var isEmpty: Bool {
        snapshot.symbols.isEmpty
    }

    @discardableResult
    func upsertDocument(
        tabID: UUID?,
        coreTabID: UInt64?,
        fileURL: URL,
        symbols: [AttoLspSymbolParser.Symbol]
    ) -> AttoWorkspaceOutlineSnapshot {
        let normalizedURL = fileURL.standardizedFileURL
        let uri = normalizedURL.absoluteString
        remember(uri: uri)
        let document = AttoWorkspaceOutlineDocument(
            tabID: tabID,
            coreTabID: coreTabID,
            uri: uri,
            title: normalizedURL.lastPathComponent,
            path: normalizedURL.path,
            symbolCount: symbols.count
        )
        entriesByURI[uri] = DocumentEntry(
            document: document,
            symbols: symbols.map { symbol in
                normalizedSymbol(symbol, documentTitle: document.title)
            }
        )
        return snapshot
    }

    @discardableResult
    func removeDocument(uri: String) -> AttoWorkspaceOutlineSnapshot {
        entriesByURI.removeValue(forKey: uri)
        documentOrder.removeAll { $0 == uri }
        return snapshot
    }

    @discardableResult
    func removeDocument(fileURL: URL) -> AttoWorkspaceOutlineSnapshot {
        removeDocument(uri: fileURL.standardizedFileURL.absoluteString)
    }

    func clear() {
        entriesByURI.removeAll()
        documentOrder.removeAll()
    }

    private func remember(uri: String) {
        guard documentOrder.contains(uri) == false else { return }
        documentOrder.append(uri)
    }

    private func normalizedSymbol(
        _ symbol: AttoLspSymbolParser.Symbol,
        documentTitle: String
    ) -> AttoLspSymbolParser.Symbol {
        AttoLspSymbolParser.Symbol(
            name: symbol.name,
            detail: symbol.detail,
            kindLabel: symbol.kindLabel,
            containerName: symbol.containerName ?? documentTitle,
            target: symbol.target,
            depth: symbol.depth
        )
    }
}
