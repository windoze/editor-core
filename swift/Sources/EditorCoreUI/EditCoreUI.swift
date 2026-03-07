import AppKit
import EditorCoreUIFFI
import Foundation

/// AppKit facade that composes editor + scrollbar + minimap into a single view.
///
/// This is the preferred embedding surface for Swift/AppKit hosts.
@MainActor
public final class EditCoreUI: NSView {
    public let editorView: EditorCoreSkiaView
    private let container: EditorCoreSkiaMinimapContainer

    /// Convenience access to the underlying Rust UI wrapper.
    public var editor: EditorUI { editorView.editor }

    // MARK: - Minimap

    public var showsMinimap: Bool {
        get { container.showsMinimap }
        set { container.showsMinimap = newValue }
    }

    public var minimapWidth: CGFloat {
        get { container.minimapWidth }
        set { container.minimapWidth = newValue }
    }

    public var minimapPlacement: EditorCoreSkiaMinimapPlacement {
        get { container.minimapPlacement }
        set { container.minimapPlacement = newValue }
    }

    // MARK: - EditorCoreSkiaView forwarding (common host hooks)

    public var pasteboard: NSPasteboard {
        get { editorView.pasteboard }
        set { editorView.pasteboard = newValue }
    }

    public var onOpenURL: (URL) -> Void {
        get { editorView.onOpenURL }
        set { editorView.onOpenURL = newValue }
    }

    public var onViewportStateDidChange: (() -> Void)? {
        get { editorView.onViewportStateDidChange }
        set { editorView.onViewportStateDidChange = newValue }
    }

    public var onDidMutateDocumentText: (() -> Void)? {
        get { editorView.onDidMutateDocumentText }
        set { editorView.onDidMutateDocumentText = newValue }
    }

    public var onHover: ((EditorCoreSkiaHoverInfo) -> Void)? {
        get { editorView.onHover }
        set { editorView.onHover = newValue }
    }

    public var onHoverExit: (() -> Void)? {
        get { editorView.onHoverExit }
        set { editorView.onHoverExit = newValue }
    }

    public var contextMenuProvider: ((EditorCoreSkiaContextMenuContext) -> NSMenu?)? {
        get { editorView.contextMenuProvider }
        set { editorView.contextMenuProvider = newValue }
    }

    public var onDidApplyAsyncProcessing: (() -> Void)? {
        get { editorView.onDidApplyAsyncProcessing }
        set { editorView.onDidApplyAsyncProcessing = newValue }
    }

    public var alwaysPollProcessing: Bool {
        get { editorView.alwaysPollProcessing }
        set { editorView.alwaysPollProcessing = newValue }
    }

    // MARK: - Caret appearance (forwarded)

    public var caretWidthPoints: CGFloat {
        get { editorView.caretWidthPoints }
        set { editorView.caretWidthPoints = newValue }
    }

    public var caretBlinkEnabled: Bool {
        get { editorView.caretBlinkEnabled }
        set { editorView.caretBlinkEnabled = newValue }
    }

    public var caretBlinkIntervalSeconds: TimeInterval {
        get { editorView.caretBlinkIntervalSeconds }
        set { editorView.caretBlinkIntervalSeconds = newValue }
    }

    public var caretVisibleOverride: Bool? {
        get { editorView.caretVisibleOverride }
        set { editorView.caretVisibleOverride = newValue }
    }

    public var textVerticalAlign: EditorUI.TextVerticalAlign {
        get { editorView.textVerticalAlign }
        set { editorView.textVerticalAlign = newValue }
    }

    // MARK: - Viewport observers (forwarded)

    public typealias ViewportStateObserverToken = EditorCoreSkiaView.ViewportStateObserverToken

    @discardableResult
    public func addViewportStateObserver(_ handler: @escaping () -> Void) -> ViewportStateObserverToken {
        editorView.addViewportStateObserver(handler)
    }

    // MARK: - Init / theme

    public init(
        library: EditorCoreUIFFILibrary,
        initialText: String = "",
        viewportWidthCells: UInt32 = 120,
        fontFamiliesCSV: String? = nil,
        showsMinimap: Bool = true,
        minimapWidth: CGFloat = 120,
        minimapPlacement: EditorCoreSkiaMinimapPlacement = .rightOfScrollbar
    ) throws {
        self.editorView = try EditorCoreSkiaView(
            library: library,
            initialText: initialText,
            viewportWidthCells: viewportWidthCells,
            fontFamiliesCSV: fontFamiliesCSV
        )
        self.container = EditorCoreSkiaMinimapContainer(
            editorView: editorView,
            showsMinimap: showsMinimap,
            minimapWidth: minimapWidth,
            minimapPlacement: minimapPlacement
        )

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    public func applyTheme(_ theme: EditorCoreSkiaTheme) throws {
        try theme.apply(to: container)
    }

    public func focusEditor() {
        window?.makeFirstResponder(editorView)
    }
}

