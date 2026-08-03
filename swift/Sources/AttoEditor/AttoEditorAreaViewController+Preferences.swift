import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Preferences (editor rendering)

    func applyEditorPreferences() {
        let fontFamiliesCSV = configuredFontFamiliesCSVForApplying()
        let ligaturesEnabled = configuredLigaturesEnabledForApplying()
        let autoPairsEnabled = configuredAutoPairsEnabledForApplying()
        let wrapMode = configuredWrapModeForApplying()
        let wrapIndent = configuredWrapIndentForApplying()
        let fontSizePoints = configuredFontSizePointsForApplying()

        for tab in tabs {
            for editCore in tab.panes {
                // Font families: empty CSV means "reset to default" (Skia renderer falls back).
                do {
                    try editCore.editor.setFontFamiliesCSV(fontFamiliesCSV)
                } catch {
                    NSLog("AttoEditor: setFontFamiliesCSV failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setFontLigaturesEnabled(ligaturesEnabled)
                } catch {
                    NSLog("AttoEditor: setFontLigaturesEnabled failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setAutoPairsEnabled(autoPairsEnabled)
                } catch {
                    NSLog("AttoEditor: setAutoPairsEnabled failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapMode(wrapMode)
                } catch {
                    NSLog("AttoEditor: setWrapMode failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapIndent(wrapIndent)
                } catch {
                    NSLog("AttoEditor: setWrapIndent failed: %@", String(describing: error))
                }

                editCore.editorView.fontSizePoints = CGFloat(fontSizePoints)
                editCore.editorView.needsDisplay = true
            }
        }

        applyFindPreferences()
    }

    func configuredFontFamiliesCSVForApplying() -> String {
        configurationSnapshot.editor.fontFamilies.joined(separator: ", ")
    }

    func configuredLigaturesEnabledForApplying() -> Bool {
        configurationSnapshot.rendering.fontLigaturesEnabled
    }

    func configuredAutoPairsEnabledForApplying() -> Bool {
        configurationSnapshot.editor.autoPairsEnabled
    }

    func configuredFontSizePointsForApplying() -> Double {
        configurationSnapshot.editor.fontSizePoints
    }

    func configuredWrapModeForApplying() -> EcuWrapMode {
        EcuWrapMode(rawValue: configurationSnapshot.editor.wrapMode) ?? preferences.effectiveWrapMode
    }

    func configuredWrapIndentForApplying() -> EcuWrapIndent {
        AttoPreferences.parseWrapIndentString(configurationSnapshot.editor.wrapIndent) ?? preferences.effectiveWrapIndent
    }

    func configuredSearchOptionsForApplying() -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: configurationSnapshot.editor.findCaseSensitive,
            wholeWord: configurationSnapshot.editor.findWholeWord,
            regex: configurationSnapshot.editor.findRegex
        )
    }

    func applyFindPreferences() {
        let options = configuredSearchOptionsForApplying()
        findReplaceBarView.caseSensitiveButton.state = options.caseSensitive ? .on : .off
        findReplaceBarView.wholeWordButton.state = options.wholeWord ? .on : .off
        findReplaceBarView.regexButton.state = options.regex ? .on : .off
        applyFindStateToActiveTab()
    }

    func applyTheme(_ theme: EditorCoreSkiaTheme) {
        self.theme = theme

        if isViewLoaded {
            let bg = NSColor(ecuRgba8: theme.editorBackground).cgColor
            view.layer?.backgroundColor = bg
            contentHostView.layer?.backgroundColor = bg
        }

        for tab in tabs {
            for editCore in tab.panes {
                do {
                    try editCore.applyTheme(theme)
                } catch {
                    NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
                }
            }
        }
    }
}
