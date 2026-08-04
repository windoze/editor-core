import AppKit
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private enum CoreTabCloseGroupCommand {
        case all
        case other(keeping: UInt64)
        case right(of: UInt64)
    }

    private struct PreparedTabClose {
        let tab: AttoEditorTab
        let coreTabID: UInt64
        let url: URL
    }

    @discardableResult
    func closeAllTabsForWindow() -> UInt32 {
        let targets = projectedTabOrderForCloseCommands()
        return closeTabGroupWithCoreCommand(targets, command: .all) ?? closeTabGroup(targets)
    }

    @discardableResult
    func closeOtherTabsForActiveTab() -> UInt32 {
        guard let activeTab else { return 0 }
        let targets = projectedTabOrderForCloseCommands().filter { $0.id != activeTab.id }
        guard let coreTabID = activeTab.coreTabID else {
            return closeTabGroup(targets)
        }
        return closeTabGroupWithCoreCommand(targets, command: .other(keeping: coreTabID)) ?? closeTabGroup(targets)
    }

    @discardableResult
    func closeTabsToRightOfActiveTab() -> UInt32 {
        guard let activeTab else { return 0 }
        let orderedTabs = projectedTabOrderForCloseCommands()
        guard let activeIndex = orderedTabs.firstIndex(where: { $0.id == activeTab.id }) else {
            return 0
        }
        guard activeIndex < orderedTabs.index(before: orderedTabs.endIndex) else {
            return 0
        }
        let targets = Array(orderedTabs[orderedTabs.index(after: activeIndex)...])
        guard let coreTabID = activeTab.coreTabID else {
            return closeTabGroup(targets)
        }
        return closeTabGroupWithCoreCommand(targets, command: .right(of: coreTabID)) ?? closeTabGroup(targets)
    }

    private func projectedTabOrderForCloseCommands() -> [AttoEditorTab] {
        guard let coreDocuments,
              let snapshot = try? coreDocuments.snapshot()
        else {
            return tabs
        }

        var tabsByCoreID: [UInt64: AttoEditorTab] = [:]
        for tab in tabs {
            guard let coreTabID = tab.coreTabID, tabsByCoreID[coreTabID] == nil else {
                return tabs
            }
            tabsByCoreID[coreTabID] = tab
        }
        let projectedTabs = snapshot.tabs.compactMap { tabsByCoreID[$0.id] }
        guard projectedTabs.count == tabs.count else { return tabs }
        return projectedTabs
    }

    @discardableResult
    private func closeTabGroup(_ targets: [AttoEditorTab]) -> UInt32 {
        var closed: UInt32 = 0
        for target in targets {
            guard tabs.contains(where: { $0.id == target.id }) else { continue }
            closeTab(id: target.id)
            if tabs.contains(where: { $0.id == target.id }) {
                break
            }
            closed += 1
        }
        return closed
    }

    @discardableResult
    private func closeTabGroupWithCoreCommand(
        _ targets: [AttoEditorTab],
        command: CoreTabCloseGroupCommand
    ) -> UInt32? {
        guard let coreDocuments else { return nil }
        guard targets.isEmpty == false else { return 0 }
        guard targets.allSatisfy({ $0.coreTabID != nil }) else { return nil }

        var prepared: [PreparedTabClose] = []
        prepared.reserveCapacity(targets.count)
        for target in targets {
            guard tabs.contains(where: { $0.id == target.id }),
                  let coreTabID = target.coreTabID
            else {
                continue
            }
            guard let close = prepareTabForCoreCloseGroup(target, coreTabID: coreTabID) else {
                return 0
            }
            prepared.append(close)
        }
        guard prepared.isEmpty == false else { return 0 }

        guard performCoreTabCloseGroup(command, coreDocuments: coreDocuments) else {
            NSSound.beep()
            return 0
        }

        let closed = coreClosedTabs(from: prepared, coreDocuments: coreDocuments)
        let closedTabIDs = Set(closed.map { $0.tab.id })
        let removedSelectedTab = selectedTabID.map { closedTabIDs.contains($0) } ?? false

        tabs.removeAll { closedTabIDs.contains($0.id) }
        syncProjectLspServerConfigsToCore()
        for close in closed {
            onDidCloseFile?(close.url)
        }
        notifySessionStateChanged()
        synchronizeAfterCoreCloseGroup(removedSelectedTab: removedSelectedTab)
        return UInt32(clamping: closed.count)
    }

    private func prepareTabForCoreCloseGroup(
        _ tab: AttoEditorTab,
        coreTabID: UInt64
    ) -> PreparedTabClose? {
        if isTabDirtyForDataLossDecision(tab) {
            switch confirmCloseDirtyTab(tab) {
            case .cancel:
                return nil
            case .save:
                guard saveTabWithSavePanelIfNeeded(tab) else { return nil }
            case .dontSave:
                break
            }
        }

        let url = projectedFileURL(for: tab)
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            stopOwnedLspSessionForClosingTab(tab)
        } else {
            notifyLspDocumentClosedForOpenSessions(tab, documentURL: url)
        }
        clearDiagnosticsLifecycleState(forTabID: tab.id)
        return PreparedTabClose(tab: tab, coreTabID: coreTabID, url: url)
    }

    private func performCoreTabCloseGroup(
        _ command: CoreTabCloseGroupCommand,
        coreDocuments: MultiDocumentEditorUI
    ) -> Bool {
        do {
            switch command {
            case .all:
                try coreDocuments.closeAllTabs()
            case .other(let coreTabID):
                _ = try coreDocuments.closeOtherTabs(keeping: coreTabID)
            case .right(let coreTabID):
                _ = try coreDocuments.closeTabsToRight(of: coreTabID)
            }
            return true
        } catch {
            NSLog("AttoEditor: core multi-document close tab group failed: %@", String(describing: error))
            return false
        }
    }

    private func coreClosedTabs(
        from prepared: [PreparedTabClose],
        coreDocuments: MultiDocumentEditorUI
    ) -> [PreparedTabClose] {
        guard let snapshot = try? coreDocuments.snapshot() else { return prepared }
        let remainingCoreTabIDs = Set(snapshot.tabs.map(\.id))
        return prepared.filter { remainingCoreTabIDs.contains($0.coreTabID) == false }
    }

    private func synchronizeAfterCoreCloseGroup(removedSelectedTab: Bool) {
        if tabs.isEmpty {
            selectedTabID = nil
            showEmptyState()
            refreshTabBar()
            updateStatusBar()
            updateWindowTitle()
            return
        }

        if removedSelectedTab, let projectedActiveTab = coreProjectedActiveTab() {
            selectTab(id: projectedActiveTab.id)
        } else if removedSelectedTab, let fallbackTab = tabs.last {
            selectTab(id: fallbackTab.id)
        } else {
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
        }
    }
}
