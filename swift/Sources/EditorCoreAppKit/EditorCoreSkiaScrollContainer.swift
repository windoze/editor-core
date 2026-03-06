import AppKit
import EditorCoreUIFFI
import Foundation

/// A simple AppKit container that adds a vertical scrollbar (`NSScroller`) to `EditorCoreSkiaView`.
///
/// The editor's scroll state lives in Rust (`scroll_top + sub_row_offset`). This container keeps
/// the native scroller in sync by querying `EditorUI.viewportState()` and by setting the smooth
/// scroll state when the user interacts with the scroller.
@MainActor
public final class EditorCoreSkiaScrollContainer: NSView {
    public let editorView: EditorCoreSkiaView

    /// Convenience access to the underlying Rust UI wrapper.
    public var editor: EditorUI { editorView.editor }

    private let verticalScroller: NSScroller
    private var scrollerUpdatePending: Bool = false
    private var viewportObserverToken: EditorCoreSkiaView.ViewportStateObserverToken?

    public init(editorView: EditorCoreSkiaView) {
        self.editorView = editorView
        self.verticalScroller = NSScroller(frame: .zero)
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Force a visible scrollbar by default.
        verticalScroller.scrollerStyle = .legacy
        verticalScroller.controlSize = .regular
        verticalScroller.target = self
        verticalScroller.action = #selector(scrollerAction(_:))

        editorView.translatesAutoresizingMaskIntoConstraints = false
        verticalScroller.translatesAutoresizingMaskIntoConstraints = false

        addSubview(editorView)
        addSubview(verticalScroller)

        let scrollerWidth = NSScroller.scrollerWidth(
            for: verticalScroller.controlSize,
            scrollerStyle: verticalScroller.scrollerStyle
        )

        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorView.topAnchor.constraint(equalTo: topAnchor),
            editorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            editorView.trailingAnchor.constraint(equalTo: verticalScroller.leadingAnchor),

            verticalScroller.trailingAnchor.constraint(equalTo: trailingAnchor),
            verticalScroller.topAnchor.constraint(equalTo: topAnchor),
            verticalScroller.bottomAnchor.constraint(equalTo: bottomAnchor),
            verticalScroller.widthAnchor.constraint(equalToConstant: scrollerWidth),
        ])

        // 通过“多订阅”机制监听 viewport 变化，避免覆盖宿主设置的 `onViewportStateDidChange`。
        viewportObserverToken = editorView.addViewportStateObserver { [weak self] in
            self?.scheduleScrollerUpdate()
        }

        scheduleScrollerUpdate()
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleScrollerUpdate()
    }

    public override func layout() {
        super.layout()
        // Layout changes can change the viewport height (rows), so update knob proportion.
        scheduleScrollerUpdate()
    }

    private func scheduleScrollerUpdate() {
        guard scrollerUpdatePending == false else { return }
        scrollerUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollerUpdatePending = false
            self.updateScrollerNow()
        }
    }

    private func updateScrollerNow() {
        do {
            let vp = try editor.viewportState()
            applyViewportStateToScroller(vp)
        } catch {
            // If the editor cannot provide viewport state, hide the scrollbar to avoid misleading UI.
            verticalScroller.isHidden = true
            verticalScroller.isEnabled = false
        }
    }

    private func applyViewportStateToScroller(_ vp: EcuViewportState) {
        let total = max(1, Double(vp.totalVisualLines))
        let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
        let maxScroll = max(0, total - visible)

        verticalScroller.isHidden = false
        verticalScroller.isEnabled = maxScroll > 0
        verticalScroller.knobProportion = min(1.0, visible / total)

        let posRows = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
        let value = maxScroll > 0 ? (posRows / maxScroll) : 0
        verticalScroller.doubleValue = value.clamped(to: 0.0...1.0)
    }

    @objc private func scrollerAction(_ sender: NSScroller) {
        // `NSScroller.doubleValue` is in 0..1.
        let desired = sender.doubleValue.clamped(to: 0.0...1.0)
        applyScrollerProportion(desired)
    }

    private func applyScrollerProportion(_ value: Double) {
        do {
            let vp = try editor.viewportState()
            let total = max(1, Double(vp.totalVisualLines))
            let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
            let maxScroll = max(0, total - visible)
            guard maxScroll > 0 else { return }

            // Map 0..1 to a scroll position in row units (allowing sub-row fractional offsets).
            let posRows = (value * maxScroll).clamped(to: 0.0...maxScroll)
            let top = floor(posRows)
            let frac = posRows - top
            let sub = UInt32((frac * 65536.0).rounded(.down)).clamped(to: 0...65535)

            editor.setSmoothScrollState(topVisualRow: UInt32(top), subRowOffset: sub)
            editorView.needsDisplay = true
            editorView.notifyViewportStateDidChange()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Testing hooks

    // Expose scroller for unit tests (`@testable import EditorCoreAppKit`).
    var _verticalScrollerForTesting: NSScroller { verticalScroller }

    func _updateScrollerForTesting() {
        updateScrollerNow()
    }

    func _applyScrollerProportionForTesting(_ value: Double) {
        applyScrollerProportion(value)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
