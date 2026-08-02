import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Preferences (editor rendering)

    func applyEditorPreferences() {
        let fontFamiliesCSV = preferences.fontFamiliesCSVForApplying()
        let ligaturesEnabled = preferences.effectiveLigaturesEnabled
        let autoPairsEnabled = preferences.effectiveAutoPairsEnabled
        let wrapMode = preferences.effectiveWrapMode
        let wrapIndent = preferences.effectiveWrapIndent
        let fontSizePoints = preferences.effectiveFontSizePoints

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
