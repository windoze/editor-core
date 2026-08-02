import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private struct CoreProjectedTab {
        let tab: AttoEditorTab
        let coreTab: EcuMultiDocumentTabSnapshot
        let fileURL: URL
    }

    // MARK: - Tabs

    func makeSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?) {
        if let coreSnapshot = makeCoreProjectedSessionSnapshot() {
            return coreSnapshot
        }

        return makeLocalSessionSnapshot()
    }

    private func makeLocalSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?) {
        let selectedIndex: Int? = {
            guard let selectedTabID else { return nil }
            return tabs.firstIndex(where: { $0.id == selectedTabID })
        }()

        let tabSnaps: [AttoTabSnapshot] = tabs.map { tab in
            AttoTabSnapshot(
                filePath: tab.fileURL.standardizedFileURL.path,
                isPreview: tab.isPreview,
                showsMinimap: tab.editCore.showsMinimap,
                paneCount: tab.panes.count,
                activePaneIndex: max(0, min(tab.activePaneIndex, tab.panes.count - 1))
            )
        }

        return (tabs: tabSnaps, selectedTabIndex: selectedIndex)
    }

    private func makeCoreProjectedSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?)? {
        guard let projection = makeCoreProjectedTabs() else { return nil }
        let coreSnapshot = projection.snapshot
        let projectedTabs = projection.tabs

        var tabSnaps: [AttoTabSnapshot] = []
        tabSnaps.reserveCapacity(projectedTabs.count)
        var selectedIndex: Int?

        for projected in projectedTabs {
            let coreTab = projected.coreTab
            let paneCount = max(1, Int(coreTab.viewCount))
            let activePaneIndex = max(0, min(Int(coreTab.activeViewIndex), paneCount - 1))

            if coreTab.isActive || coreSnapshot.activeTabId == coreTab.id {
                selectedIndex = tabSnaps.count
            }

            tabSnaps.append(
                AttoTabSnapshot(
                    filePath: projected.fileURL.standardizedFileURL.path,
                    isPreview: coreTab.isPreview,
                    showsMinimap: projected.tab.editCore.showsMinimap,
                    paneCount: paneCount,
                    activePaneIndex: activePaneIndex
                )
            )
        }

        return (tabs: tabSnaps, selectedTabIndex: selectedIndex)
    }

    private func makeCoreProjectedTabs() -> (snapshot: EcuMultiDocumentSnapshot, tabs: [CoreProjectedTab])? {
        guard let coreDocuments else { return nil }
        let coreSnapshot: EcuMultiDocumentSnapshot
        do {
            coreSnapshot = try coreDocuments.snapshot()
        } catch {
            NSLog("AttoEditor: core multi-document session snapshot failed: %@", String(describing: error))
            return nil
        }

        var tabsByCoreID: [UInt64: AttoEditorTab] = [:]
        tabsByCoreID.reserveCapacity(tabs.count)
        for tab in tabs {
            guard let coreTabID = tab.coreTabID else { return nil }
            guard tabsByCoreID[coreTabID] == nil else { return nil }
            tabsByCoreID[coreTabID] = tab
        }

        var projectedTabs: [CoreProjectedTab] = []
        projectedTabs.reserveCapacity(coreSnapshot.tabs.count)

        for coreTab in coreSnapshot.tabs {
            guard let tab = tabsByCoreID[coreTab.id] else { return nil }
            let fileURL = sessionFileURL(for: coreTab, fallback: tab.fileURL)
            projectedTabs.append(CoreProjectedTab(tab: tab, coreTab: coreTab, fileURL: fileURL))
        }

        guard projectedTabs.count == tabs.count else { return nil }
        return (snapshot: coreSnapshot, tabs: projectedTabs)
    }

    func coreProjectedActiveTab() -> AttoEditorTab? {
        guard let projection = makeCoreProjectedTabs(),
              let selectedID = projectedSelectedTabID(
                  snapshot: projection.snapshot,
                  projectedTabs: projection.tabs
              )
        else {
            return nil
        }
        return projection.tabs.first(where: { $0.tab.id == selectedID })?.tab
    }

    private func sessionFileURL(for coreTab: EcuMultiDocumentTabSnapshot, fallback: URL) -> URL {
        if let documentURI = coreTab.documentURI,
           let url = URL(string: documentURI),
           url.isFileURL
        {
            return url.standardizedFileURL
        }

        return fallback.standardizedFileURL
    }

    func projectedTab(forFileURL url: URL) -> AttoEditorTab? {
        let target = url.standardizedFileURL
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.first {
                $0.fileURL.standardizedFileURL == target
            }?.tab
        }

        return tabs.first { $0.fileURL.standardizedFileURL == target }
    }

    func projectedFileURL(for tab: AttoEditorTab) -> URL {
        if let projection = makeCoreProjectedTabs(),
           let projected = projection.tabs.first(where: { $0.tab.id == tab.id })
        {
            return projected.fileURL.standardizedFileURL
        }

        return tab.fileURL.standardizedFileURL
    }

    func restoreSession(tabs tabSnapshots: [AttoTabSnapshot], selectedTabIndex: Int?) {
        isRestoringSession = true
        defer { isRestoringSession = false }

        cancelHoverUI()
        cancelRenameUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        closeAllCoreDocumentTabs()
        tabs = []
        selectedTabID = nil

        var didUsePreview = false
        var newTabs: [AttoEditorTab] = []
        newTabs.reserveCapacity(tabSnapshots.count)

        for snap in tabSnapshots {
            let url = URL(fileURLWithPath: snap.filePath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let wantsPreview = snap.isPreview && (didUsePreview == false)
            if wantsPreview { didUsePreview = true }

            do {
                let tab = try makeTab(
                    for: url,
                    isPreview: wantsPreview,
                    showsMinimap: snap.showsMinimap ?? true
                )

                let paneCount = max(1, min(snap.paneCount ?? 1, 8))
                if paneCount > 1 {
                    for _ in 1..<paneCount {
                        _ = try appendSplitPane(to: tab)
                    }
                    tab.activePaneIndex = max(0, min(snap.activePaneIndex ?? 0, tab.panes.count - 1))
                    setCoreActiveView(tab)
                }

                newTabs.append(tab)
            } catch {
                NSLog("AttoEditor: session restore failed to open file %@: %@", url.path, String(describing: error))
            }
        }

        tabs = newTabs

        if newTabs.isEmpty {
            showEmptyState()
            refreshTabBar()
            updateStatusBar()
            updateWindowTitle()
            onOpenFilesChanged?(openFileItems(), selectedTabID)
            return
        }

        let idx = selectedTabIndex ?? 0
        let safeIdx = (0..<newTabs.count).contains(idx) ? idx : 0
        selectTab(id: newTabs[safeIdx].id)
    }

    func notifySessionStateChanged() {
        guard isRestoringSession == false else { return }
        onSessionStateChanged?()
    }

    func openCoreDocumentTab(for url: URL, initialText: String, isPreview: Bool) -> UInt64? {
        guard let coreDocuments else { return nil }
        do {
            let tabID: UInt64
            if isPreview {
                tabID = try coreDocuments.openPreviewTab(text: initialText, viewportWidthCells: 120)
            } else {
                tabID = try coreDocuments.openTab(text: initialText, viewportWidthCells: 120)
            }
            try coreDocuments.setTabTitle(url.lastPathComponent, tabId: tabID)
            try coreDocuments.setTabDocumentURI(url.standardizedFileURL.absoluteString, tabId: tabID)
            return tabID
        } catch {
            NSLog("AttoEditor: core multi-document open failed for %@: %@", url.path, String(describing: error))
            return nil
        }
    }

    func closeAllCoreDocumentTabs() {
        guard let coreDocuments else { return }
        do {
            try coreDocuments.closeAllTabs()
        } catch {
            NSLog("AttoEditor: core multi-document closeAllTabs failed: %@", String(describing: error))
        }
    }

    func setCoreActiveTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setActiveTab(coreTabID)
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document setActive failed: %@", String(describing: error))
        }
    }

    func updateCoreTabTitle(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setTabTitle(projectedFileURL(for: tab).lastPathComponent, tabId: coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document setTabTitle failed: %@", String(describing: error))
        }
    }

    func updateCoreTabDocumentURI(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setTabDocumentURI(
                tab.fileURL.standardizedFileURL.absoluteString,
                tabId: coreTabID
            )
        } catch {
            NSLog("AttoEditor: core multi-document setTabDocumentURI failed: %@", String(describing: error))
        }
    }

    func syncCoreTabText(_ tab: AttoEditorTab, markSaved: Bool) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            let text = try tab.editCore.editor.text()
            try coreDocuments.replaceTabText(tabId: coreTabID, text: text, markSaved: markSaved)
        } catch {
            NSLog("AttoEditor: core multi-document text sync failed: %@", String(describing: error))
        }
    }

    func coreTabDirtyState(_ tab: AttoEditorTab) -> Bool? {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return nil }
        do {
            return try coreDocuments.isTabModified(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document dirty query failed: %@", String(describing: error))
            return nil
        }
    }

    func localTabDirtyState(_ tab: AttoEditorTab) -> Bool {
        (try? tab.editCore.editor.isModified()) ?? tab.isDirty
    }

    @discardableResult
    func refreshTabDirtyState(_ tab: AttoEditorTab) -> Bool {
        let localDirty = localTabDirtyState(tab)
        guard let coreDirty = coreTabDirtyState(tab) else {
            tab.isDirty = localDirty
            return localDirty
        }

        let isDirty = coreDirty || localDirty
        tab.isDirty = isDirty
        return isDirty
    }

    func refreshAllTabDirtyStates() {
        for tab in tabs {
            refreshTabDirtyState(tab)
        }
    }

    func isTabDirtyForDataLossDecision(_ tab: AttoEditorTab) -> Bool {
        refreshTabDirtyState(tab)
    }

    func pinCoreTabIfPreview(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.pinTab(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document pinTab failed: %@", String(describing: error))
        }
    }

    func closeCoreTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.closeTab(coreTabID)
        } catch {
            NSLog("AttoEditor: core multi-document closeTab failed: %@", String(describing: error))
        }
    }

    func splitCoreTab(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.splitTab(coreTabID, viewportWidthCells: 120)
        } catch {
            NSLog("AttoEditor: core multi-document splitTab failed: %@", String(describing: error))
        }
    }

    func closeCoreView(tab: AttoEditorTab, viewIndex: Int) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            _ = try coreDocuments.closeView(tabId: coreTabID, viewIndex: UInt32(clamping: viewIndex))
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document closeView failed: %@", String(describing: error))
        }
    }

    func moveCoreView(tab: AttoEditorTab, fromIndex: Int, toIndex: Int) -> Bool {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return false }
        do {
            return try coreDocuments.moveView(
                tabId: coreTabID,
                fromIndex: UInt32(clamping: fromIndex),
                toIndex: UInt32(clamping: toIndex)
            )
        } catch {
            NSLog("AttoEditor: core multi-document moveView failed: %@", String(describing: error))
            return false
        }
    }

    func moveCoreTab(fromIndex: Int, toIndex: Int) -> Bool {
        guard let coreDocuments else { return false }
        do {
            return try coreDocuments.moveTab(
                fromIndex: UInt32(clamping: fromIndex),
                toIndex: UInt32(clamping: toIndex)
            )
        } catch {
            NSLog("AttoEditor: core multi-document moveTab failed: %@", String(describing: error))
            return false
        }
    }

    func setCoreActiveView(_ tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: tab.activePaneIndex))
        } catch {
            NSLog("AttoEditor: core multi-document setActiveViewIndex failed: %@", String(describing: error))
        }
    }

    func openFile(url: URL) {
        openFile(url: url, mode: .pinned)
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, isUntitled: Bool = false) -> Bool {
        if let existing = projectedTab(forFileURL: url) {
            if mode == .pinned, existing.isPreview {
                existing.isPreview = false
                pinCoreTabIfPreview(existing)
            }
            selectTab(id: existing.id)
            refreshTabBar()
            updateWindowTitle()
            notifySessionStateChanged()
            return true
        }

        do {
            switch mode {
            case .preview:
                if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
                    // Safety: never discard dirty state; pin the preview tab if it got edited.
                    if isTabDirtyForDataLossDecision(tabs[previewIdx]) {
                        tabs[previewIdx].isPreview = false
                        pinCoreTabIfPreview(tabs[previewIdx])
                    } else {
                        let oldURL = tabs[previewIdx].fileURL
                        let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                        tabs[previewIdx] = tab
                        selectTab(id: tab.id)
                        onDidCloseFile?(oldURL)
                        notifySessionStateChanged()
                        return true
                    }
                }

                let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()

            case .pinned:
                let tab = try makeTab(for: url, isPreview: false, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()
            }
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to open file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, location: AttoCommandLine.FileLocation?) -> Bool {
        let ok = openFile(url: url, mode: mode)
        guard ok else { return false }
        guard let location else { return true }
        guard let tab = activeTab, projectedFileURL(for: tab) == url.standardizedFileURL else { return true }
        navigate(tab: tab, to: location)
        return true
    }

    func containsFile(url: URL) -> Bool {
        openFileURLs().contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    func openFileURLs() -> [URL] {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.map(\.fileURL)
        }

        return tabs.map(\.fileURL)
    }

    func openFileItems() -> [OpenFileItem] {
        if let projection = makeCoreProjectedTabs() {
            return makeOpenFileItems(from: projection.tabs)
        }

        return tabs.map { tab in
            let isDirty = refreshTabDirtyState(tab)
            return OpenFileItem(
                id: tab.id,
                url: tab.fileURL,
                title: tab.displayTitle,
                isDirty: isDirty,
                isPreview: tab.isPreview
            )
        }
    }

    private func makeOpenFileItems(from projectedTabs: [CoreProjectedTab]) -> [OpenFileItem] {
        projectedTabs.map { projected in
            let isDirty = projectedDirtyState(tab: projected.tab, coreTab: projected.coreTab)
            let title = projectedTitle(
                fileURL: projected.fileURL,
                coreTab: projected.coreTab,
                isDirty: isDirty
            )
            return OpenFileItem(
                id: projected.tab.id,
                url: projected.fileURL,
                title: title,
                isDirty: isDirty,
                isPreview: projected.coreTab.isPreview
            )
        }
    }

    private func projectedDirtyState(tab: AttoEditorTab, coreTab: EcuMultiDocumentTabSnapshot) -> Bool {
        let isDirty = coreTab.isModified || localTabDirtyState(tab)
        tab.isDirty = isDirty
        return isDirty
    }

    private func projectedTitle(
        fileURL: URL,
        coreTab: EcuMultiDocumentTabSnapshot,
        isDirty: Bool
    ) -> String {
        let title = coreTab.title ?? fileURL.lastPathComponent
        return isDirty ? "● \(title)" : title
    }

    func findInOpenTabs(query: String) -> [AttoFindInFilesViewController.SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false, let coreDocuments else { return [] }

        do {
            let coreResults = try coreDocuments.searchAllTabs(
                query: q,
                options: EcuSearchOptions(caseSensitive: false)
            )

            var out: [AttoFindInFilesViewController.SearchResult] = []
            out.reserveCapacity(coreResults.reduce(0) { $0 + $1.matches.count })

            var projectedURLsByCoreTabID: [UInt64: URL] = [:]
            if let projection = makeCoreProjectedTabs() {
                projectedURLsByCoreTabID = Dictionary(uniqueKeysWithValues: projection.tabs.compactMap { projected in
                    guard let coreTabID = projected.tab.coreTabID else { return nil }
                    return (coreTabID, projected.fileURL.standardizedFileURL)
                })
            }

            let maxResults = 2000
            for result in coreResults {
                guard out.count < maxResults else { break }
                guard let tab = tabs.first(where: { $0.coreTabID == result.tabId }) else { continue }
                let resultURL = projectedURLsByCoreTabID[result.tabId] ?? tab.fileURL.standardizedFileURL
                let text = (try? tab.editCore.editor.text()) ?? ""

                for match in result.matches {
                    guard out.count < maxResults else { break }
                    let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: match.start)
                    out.append(
                        AttoFindInFilesViewController.SearchResult(
                            url: resultURL,
                            line1: Int(position.line) + 1,
                            column1: Int(position.column) + 1,
                            lineText: Self.findResultLinePreview(in: text, zeroBasedLine: Int(position.line))
                        )
                    )
                }
            }

            out.sort { a, b in
                if a.url.path != b.url.path { return a.url.path < b.url.path }
                if a.line1 != b.line1 { return a.line1 < b.line1 }
                return a.column1 < b.column1
            }
            return out
        } catch {
            NSLog("AttoEditor: core multi-document open-tab search failed: %@", String(describing: error))
            return []
        }
    }

    static func findResultLinePreview(in text: String, zeroBasedLine: Int) -> String {
        guard zeroBasedLine >= 0 else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard zeroBasedLine < lines.count else { return "" }
        let line = String(lines[zeroBasedLine]).trimmingCharacters(in: .whitespaces)
        return line.count > 240 ? String(line.prefix(240)) + "…" : line
    }

    func selectFile(url: URL) {
        guard let tab = projectedTab(forFileURL: url) else { return }
        selectTab(id: tab.id)
    }

    func closeActiveTab() {
        guard let activeTab else { return }
        closeTab(id: activeTab.id)
    }

    @discardableResult
    func closeAllTabsForWindow() -> UInt32 {
        closeTabGroup(projectedTabOrderForCommands())
    }

    @discardableResult
    func closeOtherTabsForActiveTab() -> UInt32 {
        guard let activeTab else { return 0 }
        let targets = projectedTabOrderForCommands().filter { $0.id != activeTab.id }
        return closeTabGroup(targets)
    }

    @discardableResult
    func closeTabsToRightOfActiveTab() -> UInt32 {
        guard let activeTab else { return 0 }
        let orderedTabs = projectedTabOrderForCommands()
        guard let activeIndex = orderedTabs.firstIndex(where: { $0.id == activeTab.id }) else {
            return 0
        }
        guard activeIndex < orderedTabs.index(before: orderedTabs.endIndex) else {
            return 0
        }
        return closeTabGroup(Array(orderedTabs[orderedTabs.index(after: activeIndex)...]))
    }

    private func projectedTabOrderForCommands() -> [AttoEditorTab] {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.map(\.tab)
        }
        return tabs
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

    func saveActiveTab() {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }
        _ = saveTabWithSavePanelIfNeeded(tab)
    }

    func confirmClosingDirtyTabsIfNeeded() -> Bool {
        let dirtyTabs = tabs.filter { isTabDirtyForDataLossDecision($0) }
        guard dirtyTabs.isEmpty == false else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save your changes before closing?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAllDirtyTabs()
        case .alertSecondButtonReturn:
            return false
        default:
            return true
        }
    }

    enum DirtyCloseDecision {
        case save
        case dontSave
        case cancel
    }

    func confirmCloseDirtyTab(_ tab: AttoEditorTab) -> DirtyCloseDecision {
        let name = tab.fileURL.lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \"\(name)\" before closing?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .cancel
        default:
            return .dontSave
        }
    }

    @discardableResult
    func saveTab(_ tab: AttoEditorTab) -> Bool {
        let fm = FileManager.default
        let existedOnDiskBeforeSave = fm.fileExists(atPath: tab.fileURL.path)
        do {
            let text = try tab.editCore.editor.text()
            try text.write(to: tab.fileURL, atomically: true, encoding: .utf8)
            try tab.editCore.editor.markSaved()
            tab.isUntitled = false
            tab.isDirty = false
            tab.isPreview = false
            syncCoreTabText(tab, markSaved: true)
            pinCoreTabIfPreview(tab)
            updateCoreTabTitle(tab)
            updateCoreTabDocumentURI(tab)
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
            notifySessionStateChanged()
            onDidSaveFile?(tab.fileURL, existedOnDiskBeforeSave == false)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save file %@: %@", tab.fileURL.path, String(describing: error))
            return false
        }
    }

    func saveAllDirtyTabs() -> Bool {
        for tab in tabs {
            if isTabDirtyForDataLossDecision(tab) {
                if saveTabWithSavePanelIfNeeded(tab) == false {
                    return false
                }
            }
        }
        return true
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        if isTabDirtyForDataLossDecision(tab) {
            switch confirmCloseDirtyTab(tab) {
            case .cancel:
                return
            case .save:
                guard saveTabWithSavePanelIfNeeded(tab) else { return }
            case .dontSave:
                break
            }
        }

        let url = tab.fileURL
        let wasSelected = (selectedTabID == id)
        closeCoreTab(tab)
        clearDiagnosticsLifecycleState(forTabID: tab.id)
        tabs.remove(at: idx)
        onDidCloseFile?(url)
        notifySessionStateChanged()

        if wasSelected {
            if let next = tabs.indices.last {
                selectTab(id: tabs[next].id)
            } else {
                selectedTabID = nil
                showEmptyState()
                refreshTabBar()
                updateStatusBar()
            }
        } else {
            refreshTabBar()
        }
    }

    func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        setCoreActiveTab(tab)

        updateAlwaysPollProcessingForSelectedTab()
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        showTabContent(tab)
        refreshTabBar()
        attachStatusObserver(to: tab.editCore.editorView)
        updateStatusBar()
        updateWindowTitle()
        tab.editCore.focusEditor()

        applyFindStateToActiveTab()
        notifySessionStateChanged()
    }

    func refreshTabBar() {
        if let projection = makeCoreProjectedTabs() {
            let projectedTabs = projection.tabs
            let selectedID = projectedSelectedTabID(
                snapshot: projection.snapshot,
                projectedTabs: projectedTabs
            ) ?? selectedTabID
            syncAppKitActiveTabProjection(selectedID: selectedID, focusEditor: false)
            tabBarView.updateTabs(
                tabs: projectedTabs.map { projected in
                    let isDirty = projectedDirtyState(tab: projected.tab, coreTab: projected.coreTab)
                    return .init(
                        id: projected.tab.id,
                        title: projectedTitle(
                            fileURL: projected.fileURL,
                            coreTab: projected.coreTab,
                            isDirty: isDirty
                        ),
                        toolTip: projected.fileURL.path,
                        isPreview: projected.coreTab.isPreview
                    )
                },
                selectedID: selectedID
            )
            onOpenFilesChanged?(makeOpenFileItems(from: projectedTabs), selectedID)
            return
        }

        refreshAllTabDirtyStates()
        tabBarView.updateTabs(
            tabs: tabs.map { .init(id: $0.id, title: $0.displayTitle, toolTip: $0.fileURL.path, isPreview: $0.isPreview) },
            selectedID: selectedTabID
        )
        onOpenFilesChanged?(openFileItems(), selectedTabID)
    }

    @discardableResult
    private func syncAppKitActiveTabProjection(selectedID: UUID?, focusEditor: Bool) -> Bool {
        guard let selectedID,
              selectedID != selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedID })
        else {
            return false
        }

        selectedTabID = selectedID
        showTabContent(tab)
        attachStatusObserver(to: tab.editCore.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        updateWindowTitle()
        if focusEditor {
            tab.editCore.focusEditor()
        }
        applyFindStateToActiveTab()
        return true
    }

    private func projectedSelectedTabID(
        snapshot: EcuMultiDocumentSnapshot,
        projectedTabs: [CoreProjectedTab]
    ) -> UUID? {
        guard let activeCoreTabID = snapshot.activeTabId else {
            return projectedTabs.first(where: { $0.coreTab.isActive })?.tab.id
        }
        return projectedTabs.first(where: { $0.coreTab.id == activeCoreTabID })?.tab.id
    }

    func pinTabIfPreview(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.isPreview else { return }
        tab.isPreview = false
        pinCoreTabIfPreview(tab)
        refreshTabBar()
        notifySessionStateChanged()
    }

    @discardableResult
    func moveActiveTabLeft() -> Bool {
        moveActiveTab(delta: -1)
    }

    @discardableResult
    func moveActiveTabRight() -> Bool {
        moveActiveTab(delta: 1)
    }

    @discardableResult
    func moveActiveTab(delta: Int) -> Bool {
        guard let selectedTabID,
              let from = tabs.firstIndex(where: { $0.id == selectedTabID }),
              tabs.count > 1
        else {
            NSSound.beep()
            return false
        }

        let to = from + delta
        guard to >= 0, to < tabs.count else {
            NSSound.beep()
            return false
        }

        guard moveCoreTab(fromIndex: from, toIndex: to) else {
            NSSound.beep()
            return false
        }

        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        refreshTabBar()
        updateWindowTitle()
        notifySessionStateChanged()
        return true
    }
}
