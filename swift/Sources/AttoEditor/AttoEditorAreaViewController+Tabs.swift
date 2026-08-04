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
            let paneCount = tab.panes.count
            let activePaneIndex = max(0, min(tab.activePaneIndex, paneCount - 1))
            return makeTabSessionSnapshot(
                tab: tab,
                fileURL: tab.fileURL.standardizedFileURL,
                isPreview: tab.isPreview,
                paneCount: paneCount,
                activePaneIndex: activePaneIndex
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
                makeTabSessionSnapshot(
                    tab: projected.tab,
                    fileURL: projected.fileURL.standardizedFileURL,
                    isPreview: coreTab.isPreview,
                    paneCount: paneCount,
                    activePaneIndex: activePaneIndex
                )
            )
        }

        return (tabs: tabSnaps, selectedTabIndex: selectedIndex)
    }

    private func makeTabSessionSnapshot(
        tab: AttoEditorTab,
        fileURL: URL,
        isPreview: Bool,
        paneCount: Int,
        activePaneIndex: Int
    ) -> AttoTabSnapshot {
        AttoTabSnapshot(
            filePath: fileURL.standardizedFileURL.path,
            isPreview: isPreview,
            showsMinimap: tab.editCore.showsMinimap,
            paneCount: paneCount,
            activePaneIndex: activePaneIndex,
            paneLayout: AttoPaneLayoutSnapshot.horizontalSplit(
                paneCount: paneCount,
                activePaneIndex: activePaneIndex
            ),
            isUntitled: tab.isUntitled ? true : nil,
            unsavedText: tab.isUntitled ? unsavedSessionText(for: tab) : nil
        )
    }

    private func unsavedSessionText(for tab: AttoEditorTab) -> String {
        if let text = try? tab.editCore.editor.text() {
            return text
        }
        if let coreDocuments, let coreTabID = tab.coreTabID, let text = try? coreDocuments.tabText(tabId: coreTabID) {
            return text
        }
        return ""
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

    func coreProjectedPaneState(for tab: AttoEditorTab) -> (viewCount: Int, activeViewIndex: Int)? {
        guard let projection = makeCoreProjectedTabs(),
              let projected = projection.tabs.first(where: { $0.tab.id == tab.id }),
              tab.panes.isEmpty == false
        else {
            return nil
        }

        let localPaneCount = tab.panes.count
        let viewCount = max(1, Int(projected.coreTab.viewCount))
        let activeViewIndex = max(0, min(Int(projected.coreTab.activeViewIndex), localPaneCount - 1))
        return (viewCount: viewCount, activeViewIndex: activeViewIndex)
    }

    @discardableResult
    func syncActivePaneIndexFromCoreProjectionIfAvailable(for tab: AttoEditorTab) -> Bool {
        guard let paneState = coreProjectedPaneState(for: tab),
              paneState.viewCount == tab.panes.count,
              tab.activePaneIndex != paneState.activeViewIndex
        else {
            return false
        }

        tab.activePaneIndex = paneState.activeViewIndex
        return true
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

    func coreProjectedTabsForWorkspaceLifecycle() -> [(tab: AttoEditorTab, fileURL: URL)] {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.map { projected in
                (tab: projected.tab, fileURL: projected.fileURL.standardizedFileURL)
            }
        }

        return tabs.map { tab in
            (tab: tab, fileURL: tab.fileURL.standardizedFileURL)
        }
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
        syncProjectLspServerConfigsToCore()

        var didUsePreview = false
        var newTabs: [AttoEditorTab] = []
        newTabs.reserveCapacity(tabSnapshots.count)

        for snap in tabSnapshots {
            let isUntitled = snap.isUntitled == true
            let url = URL(fileURLWithPath: snap.filePath).standardizedFileURL
            guard isUntitled || FileManager.default.fileExists(atPath: url.path) else { continue }

            let wantsPreview = isUntitled ? false : snap.isPreview && (didUsePreview == false)
            if wantsPreview { didUsePreview = true }

            do {
                let tab = try makeTab(
                    for: url,
                    isPreview: wantsPreview,
                    showsMinimap: snap.showsMinimap ?? true,
                    isUntitled: isUntitled,
                    initialTextOverride: isUntitled ? "" : nil
                )

                if isUntitled, let unsavedText = snap.unsavedText {
                    guard restoreUntitledText(unsavedText, to: tab) else { continue }
                }

                try restorePaneLayout(for: tab, from: snap)
                newTabs.append(tab)
            } catch {
                NSLog("AttoEditor: session restore failed to open file %@: %@", url.path, String(describing: error))
            }
        }

        tabs = newTabs
        syncProjectLspServerConfigsToCore()
        startProjectLspServersForOpenTabs()

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

    private func restorePaneLayout(for tab: AttoEditorTab, from snap: AttoTabSnapshot) throws {
        let paneCount = max(1, min(snap.paneLayout?.flattenedPaneCount ?? snap.paneCount ?? 1, 8))
        if paneCount > 1 {
            for _ in 1..<paneCount {
                _ = try appendSplitPane(to: tab)
            }
        }
        let activePaneIndex = snap.paneLayout?.clampedActivePaneIndex ?? snap.activePaneIndex ?? 0
        tab.activePaneIndex = max(0, min(activePaneIndex, tab.panes.count - 1))
        setCoreActiveView(tab)
    }

    @discardableResult
    private func restoreUntitledText(_ text: String, to tab: AttoEditorTab) -> Bool {
        do {
            let oldText = try tab.editCore.editor.text()
            let fullRange = UInt32(clamping: oldText.unicodeScalars.count)
            _ = try tab.editCore.editor.applyTextEdits([
                EcuTextEdit(start: 0, end: fullRange, text: text),
            ])
            if oldText != text {
                try tab.editCore.editor.endUndoGroup()
            }
            tab.isDirty = text.isEmpty == false || ((try? tab.editCore.editor.isModified()) ?? false)
            syncCoreTabText(tab, markSaved: tab.isDirty == false)
            return true
        } catch {
            NSLog("AttoEditor: session restore failed to restore untitled text %@: %@", tab.fileURL.path, String(describing: error))
            return false
        }
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

    func updateCoreTabDocumentURI(_ tab: AttoEditorTab, documentURL: URL? = nil) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        let url = documentURL?.standardizedFileURL ?? tab.fileURL.standardizedFileURL
        do {
            try coreDocuments.setTabDocumentURI(
                url.absoluteString,
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

    func splitCoreTab(_ tab: AttoEditorTab, targetViewIndex: Int? = nil) throws -> Int? {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return nil }

        try coreDocuments.setActiveViewIndex(
            tabId: coreTabID,
            viewIndex: UInt32(clamping: tab.activePaneIndex)
        )

        let createdViewIndex = Int(try coreDocuments.splitTab(coreTabID, viewportWidthCells: 120))
        guard let targetViewIndex, targetViewIndex != createdViewIndex else {
            return createdViewIndex
        }

        let moved = try coreDocuments.moveView(
            tabId: coreTabID,
            fromIndex: UInt32(clamping: createdViewIndex),
            toIndex: UInt32(clamping: targetViewIndex)
        )
        guard moved else {
            throw NSError(
                domain: "AttoEditor.CoreWorkspace",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "core multi-document split view drop did not move view \(createdViewIndex) to \(targetViewIndex)"
                ]
            )
        }
        try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: UInt32(clamping: targetViewIndex))
        return targetViewIndex
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
            if mode == .pinned, projectedIsPreview(existing) {
                existing.isPreview = false
                pinCoreTabIfPreview(existing)
            }
            selectTab(id: existing.id)
            installXCUISmokeResultFixturesIfEnabled(for: existing)
            refreshTabBar()
            updateWindowTitle()
            notifySessionStateChanged()
            return true
        }

        do {
            switch mode {
            case .preview:
                if let previewIdx = projectedPreviewReplacementIndex() {
                    // Safety: never discard dirty state; pin the preview tab if it got edited.
                    if isTabDirtyForDataLossDecision(tabs[previewIdx]) {
                        tabs[previewIdx].isPreview = false
                        pinCoreTabIfPreview(tabs[previewIdx])
                    } else {
                        let oldURL = projectedFileURL(for: tabs[previewIdx])
                        let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                        tabs[previewIdx] = tab
                        selectTab(id: tab.id)
                        installXCUISmokeResultFixturesIfEnabled(for: tab)
                        syncProjectLspServerConfigsToCore()
                        notifyOtherLspSessionsDocumentOpened(tab)
                        onDidCloseFile?(oldURL)
                        notifySessionStateChanged()
                        return true
                    }
                }

                let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                installXCUISmokeResultFixturesIfEnabled(for: tab)
                syncProjectLspServerConfigsToCore()
                notifyOtherLspSessionsDocumentOpened(tab)
                notifySessionStateChanged()

            case .pinned:
                let tab = try makeTab(for: url, isPreview: false, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                installXCUISmokeResultFixturesIfEnabled(for: tab)
                syncProjectLspServerConfigsToCore()
                notifyOtherLspSessionsDocumentOpened(tab)
                notifySessionStateChanged()
            }
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to open file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    private func projectedPreviewReplacementIndex() -> Int? {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.first(where: { $0.coreTab.isPreview }).flatMap { projected in
                tabs.firstIndex(where: { $0.id == projected.tab.id })
            }
        }

        return tabs.firstIndex(where: { $0.isPreview })
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

    func findInOpenTabs(
        query: String,
        options: AttoFindInFilesViewController.SearchOptions = .default
    ) -> [AttoFindInFilesViewController.SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false, let coreDocuments else { return [] }

        do {
            let coreResults = try coreDocuments.searchAllTabs(
                query: q,
                options: ecuSearchOptions(from: options)
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

    func findInWorkspaceFiles(
        query: String,
        includeGlobs: [String],
        excludeGlobs: [String],
        options: AttoFindInFilesViewController.SearchOptions = .default
    ) -> [AttoFindInFilesViewController.SearchResult]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false, let coreDocuments else { return nil }

        do {
            let coreResults = try coreDocuments.searchWorkspaceFiles(
                query: q,
                options: ecuSearchOptions(from: options),
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                maxResults: 2000
            )

            var out: [AttoFindInFilesViewController.SearchResult] = []
            out.reserveCapacity(coreResults.count)
            for result in coreResults {
                let resultURL = URL(fileURLWithPath: result.path).standardizedFileURL
                out.append(
                    AttoFindInFilesViewController.SearchResult(
                        url: resultURL,
                        line1: Int(result.line1),
                        column1: Int(result.column1),
                        lineText: result.lineText
                    )
                )
            }

            out.sort { a, b in
                if a.url.path != b.url.path { return a.url.path < b.url.path }
                if a.line1 != b.line1 { return a.line1 < b.line1 }
                return a.column1 < b.column1
            }
            return out
        } catch {
            NSLog("AttoEditor: core multi-document workspace file search failed: %@", String(describing: error))
            return nil
        }
    }

    @discardableResult
    func replaceInWorkspaceFiles(
        query: String,
        replacement: String,
        includeGlobs: [String],
        excludeGlobs: [String],
        options: AttoFindInFilesViewController.SearchOptions = .default
    ) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty == false, let coreDocuments else {
            NSSound.beep()
            return false
        }

        do {
            let workspaceEditJSON = try coreDocuments.workspaceFileReplacementWorkspaceEditJSON(
                query: q,
                replacement: replacement,
                options: ecuSearchOptions(from: options),
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                applyMode: "atomic",
                maxResults: 2000
            )
            let applied = applyWorkspaceEditJSONToActiveTab(workspaceEditJSON)
            if applied {
                setTransientStatusText("Replace in Files applied")
            }
            return applied
        } catch {
            NSLog("AttoEditor: core multi-document workspace file replacement failed: %@", String(describing: error))
            setTransientStatusText("Replace in Files failed")
            NSSound.beep()
            return false
        }
    }

    private func ecuSearchOptions(
        from options: AttoFindInFilesViewController.SearchOptions
    ) -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: options.caseSensitive,
            wholeWord: options.wholeWord,
            regex: options.regex
        )
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

    func saveActiveTab() {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }
        _ = saveTabWithSavePanelIfNeeded(tab)
    }

    @discardableResult
    func reloadActiveTab(discardingUnsavedChanges: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        return reloadTabFromDisk(tab, discardingUnsavedChanges: discardingUnsavedChanges)
    }

    @discardableResult
    func reloadTabFromDisk(_ tab: AttoEditorTab, discardingUnsavedChanges: Bool = false) -> Bool {
        guard tab.isUntitled == false else {
            setTransientStatusText("Reload unavailable for untitled file")
            NSSound.beep()
            return false
        }

        let url = projectedFileURL(for: tab)
        if discardingUnsavedChanges == false, isTabDirtyForDataLossDecision(tab) {
            guard confirmReloadDirtyTab(tab) else { return false }
        }

        let diskText: String
        do {
            diskText = try String(contentsOf: url, encoding: .utf8)
        } catch {
            setTransientStatusText("Reload failed: \(url.lastPathComponent)")
            NSSound.beep()
            NSLog("AttoEditor: failed to reload file %@: %@", url.path, String(describing: error))
            return false
        }

        guard replaceOpenTabTextForReload(tab, with: diskText, documentURL: url) else {
            setTransientStatusText("Reload failed: \(url.lastPathComponent)")
            NSSound.beep()
            return false
        }

        setTransientStatusText("Reloaded \(url.lastPathComponent)")
        if activeTab?.id == tab.id, let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        }
        return true
    }

    @discardableResult
    private func replaceOpenTabTextForReload(
        _ tab: AttoEditorTab,
        with text: String,
        documentURL: URL
    ) -> Bool {
        do {
            let oldText = try tab.editCore.editor.text()
            let fullRange = UInt32(clamping: oldText.unicodeScalars.count)
            _ = try tab.editCore.editor.applyTextEdits([
                EcuTextEdit(start: 0, end: fullRange, text: text),
            ])
            if oldText != text {
                try tab.editCore.editor.endUndoGroup()
            }
            try tab.editCore.editor.markSaved()
            tab.isDirty = false
            tab.isUntitled = false
            syncCoreTabText(tab, markSaved: true)
            notifyLspDocumentChangedForOpenSessions(tab, documentURL: documentURL, text: text)
            refreshTabAfterReload(tab, documentURL: documentURL)
            return true
        } catch {
            NSLog("AttoEditor: failed to replace reloaded tab %@: %@", documentURL.path, String(describing: error))
            return false
        }
    }

    private func refreshTabAfterReload(_ tab: AttoEditorTab, documentURL: URL) {
        tab.semanticTokensData = []
        tab.semanticTokensResultId = nil
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
            applyLanguageConfiguration(fileURL: documentURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        }
        updateCoreTabTitle(tab)
        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
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

    func confirmReloadDirtyTab(_ tab: AttoEditorTab) -> Bool {
        let name = projectedFileURL(for: tab).lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to reload \"\(name)\" from disk?"
        alert.informativeText = "Your unsaved changes will be discarded."
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func confirmCloseDirtyTab(_ tab: AttoEditorTab) -> DirtyCloseDecision {
        let documentURL = projectedFileURL(for: tab)
        if let dirtyCloseDecisionProviderForTesting {
            return dirtyCloseDecisionProviderForTesting(documentURL)
        }

        let name = documentURL.lastPathComponent
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
    func saveTab(_ tab: AttoEditorTab, documentURL explicitDocumentURL: URL? = nil) -> Bool {
        let documentURL = (explicitDocumentURL ?? projectedFileURL(for: tab)).standardizedFileURL
        let fm = FileManager.default
        let existedOnDiskBeforeSave = fm.fileExists(atPath: documentURL.path)
        do {
            applyFormatOnSaveIfNeeded(for: tab)
            let text = try tab.editCore.editor.text()
            try text.write(to: documentURL, atomically: true, encoding: .utf8)
            try tab.editCore.editor.markSaved()
            tab.isUntitled = false
            tab.isDirty = false
            tab.isPreview = false
            syncCoreTabText(tab, markSaved: true)
            pinCoreTabIfPreview(tab)
            updateCoreTabDocumentURI(tab, documentURL: documentURL)
            updateCoreTabTitle(tab)
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
            notifySessionStateChanged()
            notifyLspDocumentSavedForOpenSessions(tab, documentURL: documentURL, text: text)
            onDidSaveFile?(documentURL, existedOnDiskBeforeSave == false)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save file %@: %@", documentURL.path, String(describing: error))
            return false
        }
    }

    func applyFormatOnSaveIfNeeded(for tab: AttoEditorTab) {
        guard configuredFormatOnSaveEnabledForApplying(documentConfigurationSnapshot(for: tab)) else { return }

        let result = tab.editCore.editorView.formatDocumentWithLSPResult()
        switch result {
        case .applied:
            updateStatusBar()
        case .noEdits:
            break
        case .unavailable(let reason):
            NSLog(
                "AttoEditor: format-on-save unavailable for %@: %@",
                projectedFileURL(for: tab).path,
                reason
            )
        case .failed(let message):
            NSLog(
                "AttoEditor: format-on-save failed for %@: %@",
                projectedFileURL(for: tab).path,
                message
            )
        }
    }

    func saveAllDirtyTabs() -> Bool {
        for tab in projectedTabsForBulkOperations() {
            if isTabDirtyForDataLossDecision(tab) {
                if saveTabWithSavePanelIfNeeded(tab) == false {
                    return false
                }
            }
        }
        return true
    }

    private func projectedTabsForBulkOperations() -> [AttoEditorTab] {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.map(\.tab)
        }

        return tabs
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

        let url = projectedFileURL(for: tab)
        let wasSelected = (selectedTabID == id)
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            stopOwnedLspSessionForClosingTab(tab)
        } else {
            notifyLspDocumentClosedForOpenSessions(tab, documentURL: url)
        }
        closeCoreTab(tab)
        clearDiagnosticsLifecycleState(forTabID: tab.id)
        tabs.remove(at: idx)
        syncProjectLspServerConfigsToCore()
        onDidCloseFile?(url)
        notifySessionStateChanged()

        if wasSelected {
            selectTabAfterClosingSelectedTab()
        } else {
            refreshTabBar()
        }
    }

    private func selectTabAfterClosingSelectedTab() {
        guard tabs.isEmpty == false else {
            selectedTabID = nil
            showEmptyState()
            refreshTabBar()
            updateStatusBar()
            return
        }

        if let projection = makeCoreProjectedTabs(),
           let selectedID = projectedSelectedTabID(
               snapshot: projection.snapshot,
               projectedTabs: projection.tabs
           ),
           tabs.contains(where: { $0.id == selectedID })
        {
            selectTab(id: selectedID)
            return
        }

        if let next = tabs.indices.last {
            selectTab(id: tabs[next].id)
        }
    }

    func notifyOtherLspSessionsDocumentOpened(_ openedTab: AttoEditorTab) {
        guard (try? openedTab.editCore.editor.lspIsEnabled()) != true else { return }
        let documentURL = projectedFileURL(for: openedTab)
        let languageId = lspLanguageIdForDocument(tab: openedTab, documentURL: documentURL)
        let text = (try? openedTab.editCore.editor.text()) ?? ""
        for tab in tabs where tab.id != openedTab.id {
            notifyLspDocumentOpened(
                tab,
                documentURL: documentURL,
                languageId: languageId,
                text: text
            )
        }
    }

    func notifyLspDocumentOpened(
        _ tab: AttoEditorTab,
        documentURL: URL,
        languageId: String,
        text: String
    ) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        do {
            try tab.editCore.editor.lspDidOpenDocument(
                uri: documentURL.standardizedFileURL.absoluteString,
                languageId: languageId,
                text: text
            )
        } catch {
            NSLog("AttoEditor: failed to notify LSP didOpen for %@: %@", documentURL.path, String(describing: error))
        }
    }

    func lspLanguageIdForDocument(tab: AttoEditorTab, documentURL: URL) -> String {
        if let syntaxLanguageId = tab.syntaxLanguageId?.trimmingCharacters(in: .whitespacesAndNewlines),
           syntaxLanguageId.isEmpty == false
        {
            return syntaxLanguageId
        }
        if let guessed = AttoLspLanguageId.guess(forExtension: documentURL.pathExtension) {
            return guessed
        }
        return "plaintext"
    }

    func notifyLspDocumentChangedForOpenSessions(_ tab: AttoEditorTab, documentURL: URL, text: String) {
        guard (try? tab.editCore.editor.lspIsEnabled()) != true else { return }

        for other in tabs where other.id != tab.id {
            notifyLspDocumentChanged(other, documentURL: documentURL, text: text)
        }
    }

    func notifyLspDocumentChanged(_ tab: AttoEditorTab, documentURL: URL, text: String) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        do {
            try tab.editCore.editor.lspDidChangeDocument(
                uri: documentURL.standardizedFileURL.absoluteString,
                text: text
            )
        } catch {
            NSLog("AttoEditor: failed to notify LSP didChange for %@: %@", documentURL.path, String(describing: error))
        }
    }

    func notifyLspDocumentSavedForOpenSessions(_ tab: AttoEditorTab, documentURL: URL, text: String) {
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            notifyLspDocumentSaved(tab, documentURL: documentURL, text: text)
            return
        }

        for other in tabs where other.id != tab.id {
            notifyLspDocumentSaved(other, documentURL: documentURL, text: text)
        }
    }

    func notifyLspDocumentSaved(_ tab: AttoEditorTab, documentURL: URL, text: String) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        do {
            try tab.editCore.editor.lspDidSaveDocument(
                uri: documentURL.standardizedFileURL.absoluteString,
                text: text
            )
        } catch {
            NSLog("AttoEditor: failed to notify LSP didSave for %@: %@", documentURL.path, String(describing: error))
        }
    }

    func notifyLspDocumentClosedForOpenSessions(_ tab: AttoEditorTab, documentURL: URL) {
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            notifyLspDocumentClosed(tab, documentURL: documentURL)
            return
        }

        for other in tabs where other.id != tab.id {
            notifyLspDocumentClosed(other, documentURL: documentURL)
        }
    }

    func notifyLspDocumentClosed(_ tab: AttoEditorTab, documentURL: URL) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        do {
            try tab.editCore.editor.lspDidCloseDocument(uri: documentURL.standardizedFileURL.absoluteString)
        } catch {
            NSLog("AttoEditor: failed to notify LSP didClose for %@: %@", documentURL.path, String(describing: error))
        }
    }

    func stopOwnedLspSessionForClosingTab(_ tab: AttoEditorTab) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        let projectedURL = projectedFileURL(for: tab)
        let config = tab.lspServerConfig
        let stopPlanEntry = config.flatMap { config in
            projectLspStopPlanDecision(
                for: tab,
                documentURL: projectedURL,
                config: config
            ).planEntry
        }
        let stopAttemptId: UInt64? = {
            guard let config else { return nil }
            return recordProjectLspStopOutcome(
                for: tab,
                documentURL: projectedURL,
                config: config,
                trigger: "tab_close",
                status: "requested",
                planEntry: stopPlanEntry
            )
        }()
        tab.editCore.editor.lspDisable()
        if let config {
            recordProjectLspStopOutcome(
                for: tab,
                documentURL: projectedURL,
                config: config,
                trigger: "tab_close",
                status: "stopped",
                attemptId: stopAttemptId,
                planEntry: stopPlanEntry
            )
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

        applyFindPreferences()
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
        applyFindPreferences()
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

    @discardableResult
    func pinActiveTabIfPreview() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return pinTabIfPreview(id: tab.id)
    }

    @discardableResult
    func pinTabIfPreview(id: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        guard projectedIsPreview(tab) else { return false }
        tab.isPreview = false
        pinCoreTabIfPreview(tab)
        refreshTabBar()
        notifySessionStateChanged()
        return true
    }

    private func projectedIsPreview(_ tab: AttoEditorTab) -> Bool {
        if let projection = makeCoreProjectedTabs(),
           let projected = projection.tabs.first(where: { $0.tab.id == tab.id })
        {
            return projected.coreTab.isPreview
        }

        return tab.isPreview
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
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let from = projectedTabOrder().firstIndex(where: { $0.id == tab.id }) else {
            NSSound.beep()
            return false
        }

        return moveTab(id: tab.id, toProjectedIndex: from + delta)
    }

    @discardableResult
    func moveTab(id: UUID, toProjectedIndex requestedIndex: Int, beepOnFailure: Bool = true) -> Bool {
        let projectedTabs = projectedTabOrder()
        guard let from = projectedTabs.firstIndex(where: { $0.id == id }),
              projectedTabs.count > 1
        else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        let to = requestedIndex
        guard to >= 0, to < projectedTabs.count else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        guard from != to else {
            return false
        }

        guard moveCoreTab(fromIndex: from, toIndex: to) else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        var reorderedTabs = projectedTabs
        let tab = reorderedTabs.remove(at: from)
        reorderedTabs.insert(tab, at: to)
        tabs = reorderedTabs
        refreshTabBar()
        updateWindowTitle()
        notifySessionStateChanged()
        return true
    }

    func projectedTabOrder() -> [AttoEditorTab] {
        if let projection = makeCoreProjectedTabs() {
            return projection.tabs.map(\.tab)
        }

        return tabs
    }
}
