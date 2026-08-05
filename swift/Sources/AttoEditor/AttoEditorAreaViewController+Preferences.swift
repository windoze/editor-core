import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Preferences (editor rendering)

    func applyEditorPreferences() {
        for tab in tabs {
            let snapshot = documentConfigurationSnapshot(for: tab)
            applyEditorPreferences(to: tab, configurationSnapshot: snapshot)

            let semanticHighlightingEnabled = configuredSemanticHighlightingEnabledForApplying(snapshot)
            for editCore in tab.panes {
                editCore.editorView.needsDisplay = true
            }

            if semanticHighlightingEnabled == false {
                clearSemanticTokens(for: tab)
            }
        }

        if let activeTab,
           configuredSemanticHighlightingEnabledForApplying(documentConfigurationSnapshot(for: activeTab)) == false
        {
            derivedStateStore.refreshActive(editor: activeTab.editCore.editor)
            updateStatusBar()
        }

        updateEditorBackgroundForActiveTab()
        applyFindPreferences()
    }

    func applyEditorPreferences(
        to tab: AttoEditorTab,
        configurationSnapshot snapshot: AttoConfigurationSnapshot
    ) {
        for editCore in tab.panes {
            applyEditorPreferences(to: editCore, configurationSnapshot: snapshot)
        }
    }

    func applyEditorPreferences(
        to editCore: EditCoreUI,
        configurationSnapshot snapshot: AttoConfigurationSnapshot
    ) {
        do {
            try editCore.applyTheme(configuredThemeForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
        }

        do {
            try editCore.editor.setFontFamiliesCSV(configuredFontFamiliesCSVForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setFontFamiliesCSV failed: %@", String(describing: error))
        }

        do {
            try editCore.editor.setFontLigaturesEnabled(configuredLigaturesEnabledForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setFontLigaturesEnabled failed: %@", String(describing: error))
        }

        do {
            try editCore.editor.setFontFeatureMap(configuredFontFeatureMapForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setFontFeatureMap failed: %@", String(describing: error))
        }

        do {
            try editCore.editor.setAutoPairsEnabled(configuredAutoPairsEnabledForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setAutoPairsEnabled failed: %@", String(describing: error))
        }

        do {
            try editCore.editor.setLspOnTypeFormattingEnabled(configuredFormatOnTypeEnabledForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setLspOnTypeFormattingEnabled failed: %@", String(describing: error))
        }

        do {
            _ = try editCore.editor.setWrapMode(configuredWrapModeForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setWrapMode failed: %@", String(describing: error))
        }

        do {
            _ = try editCore.editor.setWrapIndent(configuredWrapIndentForApplying(snapshot))
        } catch {
            NSLog("AttoEditor: setWrapIndent failed: %@", String(describing: error))
        }

        do {
            try applyWordBoundaryConfiguration(to: editCore.editor, configurationSnapshot: snapshot)
        } catch {
            NSLog("AttoEditor: applyWordBoundaryConfiguration failed: %@", String(describing: error))
        }

        editCore.editorView.fontSizePoints = CGFloat(configuredFontSizePointsForApplying(snapshot))
    }

    func documentConfigurationSnapshot(for tab: AttoEditorTab) -> AttoConfigurationSnapshot {
        documentConfigurationSnapshot(
            for: projectedFileURL(for: tab),
            syntaxLanguageId: tab.syntaxLanguageId
        )
    }

    func documentConfigurationSnapshot(
        for fileURL: URL,
        syntaxLanguageId: String?
    ) -> AttoConfigurationSnapshot {
        let languageId = AttoLanguageConfiguration.languageKey(
            fileURL: fileURL,
            syntaxLanguageId: syntaxLanguageId
        )
        let context = AttoConfigurationDocumentContext(
            fileURL: fileURL.standardizedFileURL,
            languageId: languageId.isEmpty ? nil : languageId
        )
        return configurationSnapshotProvider?(workspaceRootURL, context) ?? configurationSnapshot
    }

    func configuredFontFamiliesCSVForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> String {
        (snapshot ?? configurationSnapshot).editor.fontFamilies.joined(separator: ", ")
    }

    func configuredFontFamiliesCSVForNewView(_ snapshot: AttoConfigurationSnapshot) -> String? {
        let csv = configuredFontFamiliesCSVForApplying(snapshot)
        return csv.isEmpty ? nil : csv
    }

    func configuredLigaturesEnabledForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Bool {
        (snapshot ?? configurationSnapshot).rendering.fontLigaturesEnabled
    }

    func configuredFontFeatureMapForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> [String: String] {
        (snapshot ?? configurationSnapshot).rendering.fontFeatureMap
    }

    func configuredAutoPairsEnabledForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Bool {
        (snapshot ?? configurationSnapshot).editor.autoPairsEnabled
    }

    func configuredFontSizePointsForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Double {
        (snapshot ?? configurationSnapshot).editor.fontSizePoints
    }

    func configuredWrapModeForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> EcuWrapMode {
        EcuWrapMode(rawValue: (snapshot ?? configurationSnapshot).editor.wrapMode) ?? preferences.effectiveWrapMode
    }

    func configuredWrapIndentForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> EcuWrapIndent {
        AttoPreferences.parseWrapIndentString((snapshot ?? configurationSnapshot).editor.wrapIndent)
            ?? preferences.effectiveWrapIndent
    }

    func configuredSemanticHighlightingEnabledForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Bool {
        (snapshot ?? configurationSnapshot).language.semanticHighlightingEnabled
    }

    func configuredFormatOnSaveEnabledForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Bool {
        (snapshot ?? configurationSnapshot).language.formatOnSaveEnabled
    }

    func configuredFormatOnTypeEnabledForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> Bool {
        (snapshot ?? configurationSnapshot).language.formatOnTypeEnabled
    }

    func configuredSearchOptionsForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> EcuSearchOptions {
        let snapshot = snapshot ?? activeTab.map(documentConfigurationSnapshot(for:)) ?? configurationSnapshot
        return EcuSearchOptions(
            caseSensitive: snapshot.editor.findCaseSensitive,
            wholeWord: snapshot.editor.findWholeWord,
            regex: snapshot.editor.findRegex
        )
    }

    func configuredWordBoundaryAsciiBoundaryCharsForApplying(_ snapshot: AttoConfigurationSnapshot? = nil) -> String? {
        (snapshot ?? configurationSnapshot).editor.wordBoundaryAsciiBoundaryChars
    }

    func applyWordBoundaryConfiguration(
        to editor: EditorUI,
        configurationSnapshot snapshot: AttoConfigurationSnapshot
    ) throws {
        if let boundaryChars = configuredWordBoundaryAsciiBoundaryCharsForApplying(snapshot) {
            try editor.setWordBoundaryAsciiBoundaryChars(boundaryChars)
        } else {
            try editor.resetWordBoundaryDefaults()
        }
    }

    func applyFindPreferences() {
        let options = configuredSearchOptionsForApplying()
        findReplaceBarView.caseSensitiveButton.state = options.caseSensitive ? .on : .off
        findReplaceBarView.wholeWordButton.state = options.wholeWord ? .on : .off
        findReplaceBarView.regexButton.state = options.regex ? .on : .off
        applyFindStateToActiveTab()
    }

    func configuredThemeForApplying(_ snapshot: AttoConfigurationSnapshot) -> EditorCoreSkiaTheme {
        themeResolver?(snapshot.rendering.themeName) ?? theme
    }

    func configuredThemeForApplying(_ tab: AttoEditorTab) -> EditorCoreSkiaTheme {
        configuredThemeForApplying(documentConfigurationSnapshot(for: tab))
    }

    func applyEditorBackground(_ theme: EditorCoreSkiaTheme) {
        guard isViewLoaded else { return }
        let bg = NSColor(ecuRgba8: theme.editorBackground).cgColor
        view.layer?.backgroundColor = bg
        contentHostView.layer?.backgroundColor = bg
    }

    func updateEditorBackgroundForActiveTab() {
        if let activeTab {
            applyEditorBackground(configuredThemeForApplying(activeTab))
        } else {
            applyEditorBackground(theme)
        }
    }

    func applyTheme(_ theme: EditorCoreSkiaTheme) {
        self.theme = theme

        for tab in tabs {
            let tabTheme = configuredThemeForApplying(tab)
            for editCore in tab.panes {
                do {
                    try editCore.applyTheme(tabTheme)
                } catch {
                    NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
                }
            }
        }

        updateEditorBackgroundForActiveTab()
    }
}
