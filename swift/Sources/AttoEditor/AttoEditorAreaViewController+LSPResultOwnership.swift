import Foundation

extension AttoEditorAreaViewController {
    func lspDocumentResultOwner(for tab: AttoEditorTab) -> AttoLspResultOwner {
        AttoLspResultOwner.document(
            tabID: tab.id,
            coreTabID: tab.coreTabID,
            documentURI: projectedFileURL(for: tab).standardizedFileURL.absoluteString,
            workspaceRootURI: workspaceRootURI
        )
    }

    func lspWorkspaceResultOwner() -> AttoLspResultOwner {
        AttoLspResultOwner.workspace(workspaceRootURI: workspaceRootURI)
    }

    func lspSymbolResultOwner(for snapshot: LspSymbolResultSnapshot) -> AttoLspResultOwner? {
        if snapshot.title == "Workspace Outline" || snapshot.title.hasPrefix("Workspace ") {
            return lspWorkspaceResultOwner()
        }
        return activeTab.map(lspDocumentResultOwner(for:))
    }

    func lspHierarchyResultOwner(refreshRequest: HierarchyPanelRefreshRequest?) -> AttoLspResultOwner? {
        if let tabID = refreshRequest?.tabID,
           let tab = tabs.first(where: { $0.id == tabID }) {
            return lspDocumentResultOwner(for: tab)
        }
        return activeTab.map(lspDocumentResultOwner(for:))
    }

    func lspLocationResultEntryForActiveDocument() -> AttoLspResultLifecycleEntry<LspLocationResultSnapshot>? {
        if let currentEntry = lspLocationResultStore.currentEntry,
           lspResultOwnerMatchesActiveDocument(currentEntry.owner) {
            return currentEntry
        }
        return lspLocationResultStore.historyEntries.reversed().first {
            lspResultOwnerMatchesActiveDocument($0.owner)
        }
    }

    func lspSymbolResultEntryForActiveDocument() -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        if let currentEntry = lspSymbolResultStore.currentEntry,
           lspSymbolResultIsWorkspaceOutline(currentEntry) == false,
           lspResultOwnerMatchesActiveDocument(currentEntry.owner) {
            return currentEntry
        }
        return lspSymbolResultStore.historyEntries.reversed().first {
            lspSymbolResultIsWorkspaceOutline($0) == false && lspResultOwnerMatchesActiveDocument($0.owner)
        }
    }

    func lspWorkspaceOutlineResultEntryForCurrentWorkspace() -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        if let currentEntry = lspSymbolResultStore.currentEntry,
           lspSymbolResultIsWorkspaceOutline(currentEntry),
           lspResultOwnerMatchesWorkspace(currentEntry.owner) {
            return currentEntry
        }
        return lspSymbolResultStore.historyEntries.reversed().first {
            lspSymbolResultIsWorkspaceOutline($0) && lspResultOwnerMatchesWorkspace($0.owner)
        }
    }

    func lspSymbolResultIsWorkspaceOutline(
        _ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>
    ) -> Bool {
        entry.snapshot.title == "Workspace Outline" || entry.title.hasPrefix("Workspace Outline")
    }

    func lspResultOwnerMatchesActiveDocument(_ owner: AttoLspResultOwner?) -> Bool {
        guard let owner else { return true }
        guard let tab = activeTab else { return false }

        switch owner.scope {
        case .document:
            if let tabID = owner.tabID {
                return tabID == tab.id
            }
            if let coreTabID = owner.coreTabID, let activeCoreTabID = tab.coreTabID {
                return coreTabID == activeCoreTabID
            }
            return owner.documentURI == projectedFileURL(for: tab).standardizedFileURL.absoluteString

        case .workspace:
            return lspResultOwnerMatchesWorkspace(owner)

        case .global:
            return true
        }
    }

    func lspResultOwnerMatchesWorkspace(_ owner: AttoLspResultOwner?) -> Bool {
        guard let owner else { return true }
        switch owner.scope {
        case .document:
            return lspResultOwnerMatchesActiveDocument(owner)
        case .workspace:
            guard let ownerWorkspaceRootURI = owner.workspaceRootURI else { return true }
            return ownerWorkspaceRootURI == workspaceRootURI
        case .global:
            return true
        }
    }

    var workspaceRootURI: String {
        workspaceRootURL.standardizedFileURL.absoluteString
    }
}
