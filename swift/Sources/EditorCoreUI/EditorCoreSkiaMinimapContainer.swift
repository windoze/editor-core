import AppKit
import EditorCoreUIFFI
import Foundation

public enum EditorCoreSkiaMinimapPlacement: Sendable {
    /// Minimap sits between editor content and the scrollbar.
    case leftOfScrollbar
    /// Minimap sits to the right of the scrollbar.
    case rightOfScrollbar
}

/// A simple container that composes:
/// - `EditorCoreSkiaScrollContainer` (editor + vertical scroller)
/// - `EditorCoreSkiaMinimapView` (optional)
@MainActor
public final class EditorCoreSkiaMinimapContainer: NSView {
    public let editorView: EditorCoreSkiaView
    public let scrollContainer: EditorCoreSkiaScrollContainer
    public let minimapView: EditorCoreSkiaMinimapView

    public var showsMinimap: Bool {
        didSet { updateMinimapVisibility() }
    }

    public var minimapWidth: CGFloat {
        didSet { updateMinimapVisibility() }
    }

    public var minimapPlacement: EditorCoreSkiaMinimapPlacement {
        didSet { updateMinimapPlacement() }
    }

    private let minimapWidthConstraint: NSLayoutConstraint
    private var layoutConstraints: [NSLayoutConstraint] = []

    public init(
        editorView: EditorCoreSkiaView,
        showsMinimap: Bool = false,
        minimapWidth: CGFloat = 120,
        minimapPlacement: EditorCoreSkiaMinimapPlacement = .rightOfScrollbar
    ) {
        self.editorView = editorView
        self.scrollContainer = EditorCoreSkiaScrollContainer(editorView: editorView)
        self.minimapView = EditorCoreSkiaMinimapView(editorView: editorView)
        self.showsMinimap = showsMinimap
        self.minimapWidth = minimapWidth
        self.minimapPlacement = minimapPlacement

        self.minimapWidthConstraint = minimapView.widthAnchor.constraint(equalToConstant: minimapWidth)

        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        scrollContainer.translatesAutoresizingMaskIntoConstraints = false
        minimapView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollContainer)
        updateMinimapPlacement()
        updateMinimapVisibility()
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    private func updateMinimapVisibility() {
        if showsMinimap {
            minimapView.isHidden = false
            minimapWidthConstraint.constant = max(40, minimapWidth)
        } else {
            minimapView.isHidden = true
            minimapWidthConstraint.constant = 0
        }
        needsLayout = true
    }

    private func updateMinimapPlacement() {
        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints.removeAll()

        // Always pin the scroll container to the host view; in `.rightOfScrollbar` we will
        // additionally pin it to the minimap.
        switch minimapPlacement {
        case .rightOfScrollbar:
            scrollContainer.trailingAccessoryView = nil

            if minimapView.superview !== self {
                minimapView.removeFromSuperview()
                addSubview(minimapView)
            }

            layoutConstraints = [
                scrollContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollContainer.topAnchor.constraint(equalTo: topAnchor),
                scrollContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                scrollContainer.trailingAnchor.constraint(equalTo: minimapView.leadingAnchor),

                minimapView.trailingAnchor.constraint(equalTo: trailingAnchor),
                minimapView.topAnchor.constraint(equalTo: topAnchor),
                minimapView.bottomAnchor.constraint(equalTo: bottomAnchor),
                minimapWidthConstraint,
            ]

        case .leftOfScrollbar:
            if minimapView.superview !== scrollContainer {
                minimapView.removeFromSuperview()
                scrollContainer.trailingAccessoryView = minimapView
            } else {
                scrollContainer.trailingAccessoryView = minimapView
            }

            layoutConstraints = [
                scrollContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollContainer.topAnchor.constraint(equalTo: topAnchor),
                scrollContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                minimapWidthConstraint,
            ]
        }

        NSLayoutConstraint.activate(layoutConstraints)
        needsLayout = true
    }

    // MARK: - Testing hooks

    var _minimapWidthConstraintForTesting: NSLayoutConstraint { minimapWidthConstraint }
}
