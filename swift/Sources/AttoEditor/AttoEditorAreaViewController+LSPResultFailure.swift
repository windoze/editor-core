import AppKit
import EditorCoreUI

extension AttoEditorAreaViewController {
    @discardableResult
    func failLspEventResult(
        family: String,
        message: AttoLspResultFeedback.Message,
        showFeedback: Bool,
        editorView: EditorCoreSkiaView?,
        cancel: (() -> Void)? = nil,
        beep: Bool = true
    ) -> Bool {
        cancel?()
        markCurrentLspEventResultError(family: family, message: message)
        if showFeedback, let editorView {
            presentLspResultFeedback(message, in: editorView)
        }
        if beep {
            NSSound.beep()
        }
        return false
    }
}
