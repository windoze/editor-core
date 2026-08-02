import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Find / Replace

    func showFindBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .find)
            return
        }

        if findReplaceBarView.currentMode() == .find {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .find)
    }

    func showReplaceBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .replace)
            return
        }

        if findReplaceBarView.currentMode() == .replace {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .replace)
    }

    func ensureFindReplaceBar(mode: AttoFindReplaceBarView.Mode) {
        let wasHidden = findReplaceBarView.isHidden
        let oldMode = findReplaceBarView.currentMode()

        findReplaceBarView.setMode(mode)
        findReplaceBarView.isHidden = false
        findReplaceBarHeightConstraint?.constant = (mode == .find) ? 42 : 76

        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
        findReplaceBarView.searchField.selectText(nil)

        // Always re-apply highlights on show/switch; `activeTab == nil` is fine (no-op).
        if wasHidden || oldMode != mode {
            applyFindStateToActiveTab()
        } else {
            refreshSearchHighlights()
        }
    }

    func hideFindBar() {
        guard findReplaceBarView.isHidden == false else { return }
        clearSearchHighlightsForAllTabs()
        findReplaceBarView.isHidden = true
        findReplaceBarHeightConstraint?.constant = 0
        activeTab?.editCore.focusEditor()
    }

    func currentSearchOptions() -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: findReplaceBarView.caseSensitiveButton.state == .on,
            wholeWord: findReplaceBarView.wholeWordButton.state == .on,
            regex: findReplaceBarView.regexButton.state == .on
        )
    }

    func setMatchCountLabel(_ count: UInt32) {
        findReplaceBarView.matchCountLabel.stringValue = "\(count) matches"
    }

    func applyFindStateToActiveTab() {
        guard findReplaceBarView.isHidden == false else { return }
        refreshSearchHighlights()
    }

    func clearSearchHighlightsForAllTabs() {
        for tab in tabs {
            do {
                try tab.editCore.editor.clearSearchQuery()
                tab.editCore.editorView.needsDisplay = true
            } catch {
                // Ignore best-effort cleanup errors.
            }
        }
        setMatchCountLabel(0)
    }

    func refreshSearchHighlights() {
        guard let tab = activeTab else {
            setMatchCountLabel(0)
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            if query.isEmpty {
                try tab.editCore.editor.clearSearchQuery()
                setMatchCountLabel(0)
            } else {
                let count = try tab.editCore.editor.setSearchQuery(query, options: currentSearchOptions())
                setMatchCountLabel(count)
            }
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    @objc func findOptionsChanged(_ sender: Any?) {
        refreshSearchHighlights()
    }

    @objc func clearFindClicked(_ sender: Any?) {
        findReplaceBarView.searchField.stringValue = ""
        refreshSearchHighlights()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
    }

    @objc func findNextClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findNext(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc func findPrevClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findPrev(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc func replaceCurrentClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceCurrent(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc func replaceAllClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceAll(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc func closeFindBarClicked(_ sender: Any?) {
        hideFindBar()
    }
}
