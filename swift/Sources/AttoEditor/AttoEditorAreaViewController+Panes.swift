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

        do {
            let pane = try appendSplitPane(to: tab)
            showTabContent(tab)
            attachStatusObserver(to: pane.editorView)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            pane.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: split active tab failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func appendSplitPane(to tab: AttoEditorTab) throws -> EditCoreUI {
        let editor = try tab.editCore.editor.cloneView(viewportWidthCells: 120)
        let pane = try EditCoreUI(
            editor: editor,
            fontFamiliesCSV: AttoPreferences.shared.fontFamiliesCSVForNewViews(),
            showsMinimap: tab.editCore.showsMinimap,
            minimapPlacement: .rightOfScrollbar
        )

        try configureEditorChrome(pane)
        applyLanguageConfiguration(fileURL: projectedFileURL(for: tab), syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        configureEditCoreHooks(pane, tabID: tab.id)

        tab.panes.append(pane)
        tab.activePaneIndex = tab.panes.count - 1
        splitCoreTab(tab)
        return pane
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

        showTabContent(tab)
        attachStatusObserver(to: pane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        pane.focusEditor()
        return true
    }
}
