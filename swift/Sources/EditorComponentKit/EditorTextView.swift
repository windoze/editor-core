#if canImport(AppKit)
import AppKit

final class EditorTextView: NSTextView {
    var keybindingRegistry: EditorKeybindingRegistry?
    var commandDispatcher: EditorCommandDispatching?

    override func keyDown(with event: NSEvent) {
        if let command = resolveCommand(from: event) {
            commandDispatcher?.dispatch(command)
            return
        }

        if !event.charactersIgnoringModifiers.isNilOrEmpty,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let text = event.characters,
           !text.isEmpty,
           text != "\u{7F}",
           text != "\u{8}",
           text != "\t",
           text != "\r" {
            commandDispatcher?.dispatch(.insertText(text))
            return
        }

        super.keyDown(with: event)
    }

    private func resolveCommand(from event: NSEvent) -> EditorCommand? {
        guard let chars = event.charactersIgnoringModifiers else {
            return nil
        }

        let flags = Self.modifiers(from: event.modifierFlags)
        let chord = EditorKeyChord(key: chars.lowercased(), modifiers: flags)
        return keybindingRegistry?.resolve(chord)
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> EditorModifierFlags {
        var result: EditorModifierFlags = []
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.command) {
            result.insert(.command)
        }
        return result
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
#endif
