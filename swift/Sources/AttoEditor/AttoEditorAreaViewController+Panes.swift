import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Minimap

    func toggleMinimapForActiveTab() {
        guard let tab = activeTab else { return }
        let nextValue = tab.editCore.showsMinimap == false
        for editCore in tab.panes {
            editCore.showsMinimap = nextValue
            editCore.needsLayout = true
            editCore.needsDisplay = true
        }
        notifySessionStateChanged()
    }

    // MARK: - Split panes

    @discardableResult
    func splitActiveTabRight() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        return splitTabIntoPane(tab, targetPaneIndex: nil, beepOnFailure: true)
    }

    @discardableResult
    func dropTabIntoSplit(
        id: UUID,
        targetPaneIndex: Int? = nil,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard let tab = projectedTabOrder().first(where: { $0.id == id }) else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        if selectedTabID != id {
            selectTab(id: id)
        }
        return splitTabIntoPane(tab, targetPaneIndex: targetPaneIndex, beepOnFailure: beepOnFailure)
    }

    @discardableResult
    private func splitTabIntoPane(
        _ tab: AttoEditorTab,
        targetPaneIndex: Int?,
        beepOnFailure: Bool
    ) -> Bool {
        do {
            let pane = try appendSplitPane(to: tab, targetPaneIndex: targetPaneIndex)
            showTabContent(tab)
            attachStatusObserver(to: pane.editorView)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            pane.focusEditor()
            notifySessionStateChanged()
            return true
        } catch {
            if beepOnFailure {
                NSSound.beep()
            }
            NSLog("AttoEditor: split active tab failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func appendSplitPane(to tab: AttoEditorTab, targetPaneIndex: Int? = nil) throws -> EditCoreUI {
        let insertionIndex = try validatedSplitPaneInsertionIndex(targetPaneIndex, paneCount: tab.panes.count)
        let sourcePane = tab.editCore
        let coreInsertedViewIndex = try splitCoreTab(tab, targetViewIndex: insertionIndex)

        do {
            return try appendAppKitSplitPane(
                to: tab,
                sourcePane: sourcePane,
                insertionIndex: insertionIndex
            )
        } catch {
            rollbackCoreSplitPane(tab: tab, viewIndex: coreInsertedViewIndex)
            throw error
        }
    }

    private func appendAppKitSplitPane(
        to tab: AttoEditorTab,
        sourcePane: EditCoreUI,
        insertionIndex: Int?
    ) throws -> EditCoreUI {
        let editor = try sourcePane.editor.cloneView(viewportWidthCells: 120)
        let documentConfiguration = documentConfigurationSnapshot(for: tab)
        let pane = try EditCoreUI(
            editor: editor,
            fontFamiliesCSV: configuredFontFamiliesCSVForNewView(documentConfiguration),
            showsMinimap: sourcePane.showsMinimap,
            minimapPlacement: .rightOfScrollbar
        )

        try configureEditorChrome(pane, configurationSnapshot: documentConfiguration)
        applyLanguageConfiguration(fileURL: projectedFileURL(for: tab), syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        configureEditCoreHooks(pane, tabID: tab.id)

        if let insertionIndex, insertionIndex < tab.panes.count {
            tab.panes.insert(pane, at: insertionIndex)
            tab.activePaneIndex = insertionIndex
        } else {
            tab.panes.append(pane)
            tab.activePaneIndex = tab.panes.count - 1
        }
        return pane
    }

    private func validatedSplitPaneInsertionIndex(_ index: Int?, paneCount: Int) throws -> Int? {
        guard let index else { return nil }
        guard index >= 0, index <= paneCount else {
            throw NSError(
                domain: "AttoEditor.CoreWorkspace",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "invalid split pane insertion index \(index) for \(paneCount) panes"
                ]
            )
        }
        return index
    }

    private func rollbackCoreSplitPane(tab: AttoEditorTab, viewIndex: Int?) {
        guard let viewIndex else { return }
        closeCoreView(tab: tab, viewIndex: viewIndex)
    }

    @discardableResult
    func focusNextPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: 1)
    }

    @discardableResult
    func focusPreviousPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: -1)
    }

    @discardableResult
    func closeActivePane() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        syncActivePaneIndexFromCoreProjectionIfAvailable(for: tab)
        guard tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let idx = max(0, min(tab.activePaneIndex, tab.panes.count - 1))
        let pane = tab.panes.remove(at: idx)
        pane.removeFromSuperview()
        tab.activePaneIndex = min(idx, tab.panes.count - 1)
        closeCoreView(tab: tab, viewIndex: idx)

        let activePane = tab.editCore
        showTabContent(tab)
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    @discardableResult
    func moveActivePaneLeft() -> Bool {
        moveActivePaneInActiveTab(delta: -1)
    }

    @discardableResult
    func moveActivePaneRight() -> Bool {
        moveActivePaneInActiveTab(delta: 1)
    }

    @discardableResult
    func focusPaneInActiveTab(delta: Int) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        syncActivePaneIndexFromCoreProjectionIfAvailable(for: tab)
        guard tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let count = tab.panes.count
        let current = max(0, min(tab.activePaneIndex, count - 1))
        let next = (current + delta + count) % count
        tab.activePaneIndex = next
        setCoreActiveView(tab)

        let activePane = tab.editCore
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    @discardableResult
    func moveActivePaneInActiveTab(delta: Int) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        syncActivePaneIndexFromCoreProjectionIfAvailable(for: tab)
        guard tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let count = tab.panes.count
        let from = max(0, min(tab.activePaneIndex, count - 1))
        let to = from + delta
        guard to >= 0, to < count else {
            NSSound.beep()
            return false
        }

        guard moveCoreView(tab: tab, fromIndex: from, toIndex: to) else {
            NSSound.beep()
            return false
        }

        let pane = tab.panes.remove(at: from)
        tab.panes.insert(pane, at: to)
        tab.activePaneIndex = to

        renderDroppedPane(tab: tab, pane: pane, focus: true)
        return true
    }

    @discardableResult
    func dropPaneInActiveTab(
        fromProjectedIndex from: Int,
        toProjectedIndex to: Int,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
        syncActivePaneIndexFromCoreProjectionIfAvailable(for: tab)

        let count = tab.panes.count
        guard count > 1,
              from >= 0,
              from < count,
              to >= 0,
              to < count,
              from != to
        else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        tab.activePaneIndex = from
        setCoreActiveView(tab)

        guard moveCoreView(tab: tab, fromIndex: from, toIndex: to) else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        let pane = tab.panes.remove(at: from)
        tab.panes.insert(pane, at: to)
        tab.activePaneIndex = to

        renderDroppedPane(tab: tab, pane: pane, focus: true)
        notifySessionStateChanged()
        return true
    }

    private func renderDroppedPane(tab: AttoEditorTab, pane: EditCoreUI, focus: Bool) {
        showTabContent(tab)
        attachStatusObserver(to: pane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        if focus {
            pane.focusEditor()
        }
    }
}
