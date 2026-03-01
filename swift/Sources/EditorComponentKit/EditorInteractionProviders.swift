#if canImport(AppKit)
import AppKit

public struct EditorHoverTooltip: Equatable, Sendable {
    public var title: String?
    public var message: String

    public init(title: String? = nil, message: String) {
        self.title = title
        self.message = message
    }

    public var renderedText: String {
        if let title, !title.isEmpty {
            return "\(title)\n\(message)"
        }
        return message
    }
}

public struct EditorContextMenuItem {
    public var title: String
    public var command: EditorCommand?
    public var action: (() -> Void)?
    public var isEnabled: Bool
    public var isSeparator: Bool

    public init(
        title: String,
        command: EditorCommand? = nil,
        action: (() -> Void)? = nil,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.command = command
        self.action = action
        self.isEnabled = isEnabled
        self.isSeparator = false
    }

    public static var separator: Self {
        Self(title: "", command: nil, action: nil, isEnabled: false, isSeparator: true)
    }

    private init(
        title: String,
        command: EditorCommand?,
        action: (() -> Void)?,
        isEnabled: Bool,
        isSeparator: Bool
    ) {
        self.title = title
        self.command = command
        self.action = action
        self.isEnabled = isEnabled
        self.isSeparator = isSeparator
    }
}

@MainActor
public protocol EditorHoverProvider: AnyObject {
    func editorComponent(_ component: EditorComponentView, hoverAt position: EditorPosition) -> EditorHoverTooltip?
}

@MainActor
public protocol EditorContextMenuProvider: AnyObject {
    func editorComponent(
        _ component: EditorComponentView,
        contextMenuItemsAt position: EditorPosition
    ) -> [EditorContextMenuItem]
}
#endif
