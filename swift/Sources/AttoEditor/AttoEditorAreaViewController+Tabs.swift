import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Tabs

    func makeSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?) {
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
            try coreDocuments.setTabTitle(tab.fileURL.lastPathComponent, tabId: coreTabID)
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
        if let existing = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
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
        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else { return true }
        navigate(tab: tab, to: location)
        return true
    }

    func containsFile(url: URL) -> Bool {
        tabs.contains { $0.fileURL.standardizedFileURL == url.standardizedFileURL }
    }

    func openFileURLs() -> [URL] {
        tabs.map(\.fileURL)
    }

    func openFileItems() -> [OpenFileItem] {
        tabs.map { tab in
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

            let maxResults = 2000
            for result in coreResults {
                guard out.count < maxResults else { break }
                guard let tab = tabs.first(where: { $0.coreTabID == result.tabId }) else { continue }
                let text = (try? tab.editCore.editor.text()) ?? ""

                for match in result.matches {
                    guard out.count < maxResults else { break }
                    let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: match.start)
                    out.append(
                        AttoFindInFilesViewController.SearchResult(
                            url: tab.fileURL.standardizedFileURL,
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
        guard let tab = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) else { return }
        selectTab(id: tab.id)
    }

    func closeActiveTab() {
        guard let selectedTabID else { return }
        closeTab(id: selectedTabID)
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
        refreshAllTabDirtyStates()
        tabBarView.updateTabs(
            tabs: tabs.map { .init(id: $0.id, title: $0.displayTitle, toolTip: $0.fileURL.path, isPreview: $0.isPreview) },
            selectedID: selectedTabID
        )
        onOpenFilesChanged?(openFileItems(), selectedTabID)
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
