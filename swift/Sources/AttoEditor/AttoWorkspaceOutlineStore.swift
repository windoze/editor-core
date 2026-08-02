import EditorCoreUIFFI
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
        let documentText: String
        let symbols: [AttoLspSymbolParser.Symbol]
    }

    private let coreDocuments: MultiDocumentEditorUI?
    private var entriesByURI: [String: DocumentEntry] = [:]
    private var uriByCoreTabID: [UInt64: String] = [:]
    private var documentOrder: [String] = []

    init(coreDocuments: MultiDocumentEditorUI? = nil) {
        self.coreDocuments = coreDocuments
    }

    var snapshot: AttoWorkspaceOutlineSnapshot {
        if let coreSnapshot = coreBackedSnapshot() {
            return coreSnapshot
        }
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
        documentText: String,
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
            documentText: documentText,
            symbols: symbols.map { symbol in
                normalizedSymbol(symbol, documentTitle: document.title)
            }
        )
        if let coreTabID {
            uriByCoreTabID[coreTabID] = uri
        }
        return snapshot
    }

    @discardableResult
    func removeDocument(uri: String) -> AttoWorkspaceOutlineSnapshot {
        entriesByURI.removeValue(forKey: uri)
        documentOrder.removeAll { $0 == uri }
        uriByCoreTabID = uriByCoreTabID.filter { $0.value != uri }
        return snapshot
    }

    @discardableResult
    func removeDocument(fileURL: URL) -> AttoWorkspaceOutlineSnapshot {
        removeDocument(uri: fileURL.standardizedFileURL.absoluteString)
    }

    func clear() {
        entriesByURI.removeAll()
        uriByCoreTabID.removeAll()
        documentOrder.removeAll()
    }

    private func coreBackedSnapshot() -> AttoWorkspaceOutlineSnapshot? {
        guard let coreDocuments,
              let coreSnapshot = try? coreDocuments.workspaceOutlineSnapshot()
        else {
            return nil
        }

        var documents: [AttoWorkspaceOutlineDocument] = []
        var symbols: [AttoLspSymbolParser.Symbol] = []
        for coreDocument in coreSnapshot.documents {
            guard let uri = coreDocument.documentURI ?? uriByCoreTabID[coreDocument.tabId],
                  let fallback = entriesByURI[uri]
            else {
                continue
            }
            let document = AttoWorkspaceOutlineDocument(
                tabID: fallback.document.tabID,
                coreTabID: coreDocument.tabId,
                uri: fallback.document.uri,
                title: coreDocument.title ?? fallback.document.title,
                path: fallback.document.path,
                symbolCount: Int(coreDocument.symbolCount)
            )
            documents.append(document)
            let documentSymbols = AttoLspSymbolParser.documentSymbols(
                snapshot: EcuDocumentSymbolsSnapshot(symbols: coreDocument.symbols),
                documentURI: fallback.document.uri,
                documentText: fallback.documentText
            ).map { symbol in
                normalizedSymbol(symbol, documentTitle: document.title)
            }
            symbols.append(contentsOf: documentSymbols)
        }
        if documents.isEmpty, entriesByURI.isEmpty == false {
            return nil
        }
        return AttoWorkspaceOutlineSnapshot(documents: documents, symbols: symbols)
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
