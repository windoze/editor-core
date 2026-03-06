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

    // MARK: - Smooth paging scroll (track clicks)

    private var pagingTargetPosRows: Double?
    private var pagingTimer: Timer?
    private let pagingTimerDisabledForTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
        switch sender.hitPart {
        case .knob:
            // Dragging the thumb should map to an absolute scroll position (0..1).
            stopPagingScroll()
            let desired = sender.doubleValue.clamped(to: 0.0...1.0)
            applyScrollerProportion(desired)
        case .decrementPage:
            requestPageScroll(direction: -1)
        case .incrementPage:
            requestPageScroll(direction: 1)
        case .decrementLine:
            requestLineScroll(direction: -1)
        case .incrementLine:
            requestLineScroll(direction: 1)
        case .knobSlot:
            // Some scroller styles report a track click as `.knobSlot` and update `doubleValue`
            // to the click location (jump-to). We prefer page-scrolling semantics:
            // - click above thumb: page up
            // - click below thumb: page down
            requestPageScrollTowardProportion(sender.doubleValue)
        default:
            break
        }
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

    private func requestPageScroll(direction: Int) {
        do {
            let vp = try editor.viewportState()
            let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
            requestSmoothScrollBy(deltaRows: Double(direction) * visible, vp: vp)
        } catch {
            NSSound.beep()
        }
    }

    private func requestLineScroll(direction: Int) {
        do {
            let vp = try editor.viewportState()
            requestSmoothScrollBy(deltaRows: Double(direction), vp: vp)
        } catch {
            NSSound.beep()
        }
    }

    private func requestPageScrollTowardProportion(_ desiredProportion: Double) {
        do {
            let vp = try editor.viewportState()
            let total = max(1.0, Double(vp.totalVisualLines))
            let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
            let maxScroll = max(0.0, total - visible)
            guard maxScroll > 0 else { return }

            let currentPosRows = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
            let currentProp = (currentPosRows / maxScroll).clamped(to: 0.0...1.0)
            let desired = desiredProportion.clamped(to: 0.0...1.0)
            let direction = desired < currentProp ? -1 : 1

            requestSmoothScrollBy(deltaRows: Double(direction) * visible, vp: vp)
        } catch {
            NSSound.beep()
        }
    }

    private func requestSmoothScrollBy(deltaRows: Double, vp: EcuViewportState) {
        let total = max(1.0, Double(vp.totalVisualLines))
        let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
        let maxScroll = max(0.0, total - visible)
        guard maxScroll > 0 else { return }

        let current = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
        let target = (current + deltaRows).clamped(to: 0.0...maxScroll)

        // Merge repeated page clicks (mouse held down) into a single moving target.
        if let existing = pagingTargetPosRows {
            let merged = (existing + deltaRows).clamped(to: 0.0...maxScroll)
            pagingTargetPosRows = merged
        } else {
            pagingTargetPosRows = target
        }

        startPagingScrollIfNeeded()
    }

    private func startPagingScrollIfNeeded() {
        guard pagingTimer == nil else { return }
        if pagingTimerDisabledForTests {
            return
        }
        pagingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pagingTick(mouseButtonsMask: UInt(NSEvent.pressedMouseButtons))
        }
        pagingTimer?.tolerance = 0.004
    }

    private func stopPagingScroll() {
        pagingTargetPosRows = nil
        pagingTimer?.invalidate()
        pagingTimer = nil
    }

    private func pagingTick(mouseButtonsMask: UInt) {
        // Stop when the mouse button is released; this matches native scrollbar semantics.
        if (mouseButtonsMask & 1) == 0 {
            stopPagingScroll()
            return
        }

        guard let target = pagingTargetPosRows else {
            stopPagingScroll()
            return
        }

        do {
            let vp = try editor.viewportState()
            let total = max(1.0, Double(vp.totalVisualLines))
            let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
            let maxScroll = max(0.0, total - visible)
            guard maxScroll > 0 else {
                stopPagingScroll()
                return
            }

            let current = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
            let delta = target - current
            if abs(delta) < 0.0001 {
                stopPagingScroll()
                return
            }

            // Smooth speed in "rows per second". Keep it stable across small/large viewports.
            let rowsPerSecond = min(200.0, max(30.0, visible * 12.0))
            let step = rowsPerSecond * (1.0 / 60.0)
            let dir: Double = delta == 0 ? 0 : (delta < 0 ? -1 : 1)
            let next = current + dir * min(abs(delta), step)
            setSmoothScrollPosRows(next.clamped(to: 0.0...maxScroll))
        } catch {
            stopPagingScroll()
        }
    }

    private func setSmoothScrollPosRows(_ posRows: Double) {
        let top = floor(posRows).clamped(to: 0.0...Double(UInt32.max))
        let frac = (posRows - top).clamped(to: 0.0...0.999_999)
        let sub = UInt32((frac * 65536.0).rounded(.down)).clamped(to: 0...65535)

        editor.setSmoothScrollState(topVisualRow: UInt32(top), subRowOffset: sub)
        editorView.needsDisplay = true
        editorView.notifyViewportStateDidChange()
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

    func _requestPageScrollForTesting(direction: Int) {
        requestPageScroll(direction: direction)
    }

    func _pagingTickForTesting(mouseButtonsMask: UInt) {
        pagingTick(mouseButtonsMask: mouseButtonsMask)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
