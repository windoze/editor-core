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
    private var pagingHoldTargetProportion: Double?
    private var pagingHoldDirection: Int = 0

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
        // 默认的 NSScroller 在 track click 场景往往只在 mouseUp 触发 action；
        // 我们需要在 mouseDown 就开始 smooth paging（并在按住时持续 paging）。
        verticalScroller.sendAction(on: [.leftMouseDown, .leftMouseUp, .leftMouseDragged])

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
        // 注意：`NSScroller` 会在 mouseUp 也触发 action；我们只在 mouseDown/drag 时发起滚动，
        // mouseUp 只用于结束“按住持续翻页”的状态。
        if NSApp.currentEvent?.type == .leftMouseUp {
            pagingHoldTargetProportion = nil
            pagingHoldDirection = 0
            return
        }
        if NSApp.currentEvent?.type == .leftMouseDragged {
            // Track click hold should keep paging toward the original mouseDown position;
            // moving the mouse while holding should NOT change the target.
            //
            // Only allow dragging the thumb to update scroll position continuously.
            if sender.hitPart != .knob {
                return
            }
        }

        switch sender.hitPart {
        case .knob:
            // Dragging the thumb should map to an absolute scroll position (0..1).
            stopPagingScroll()
            let desired = sender.doubleValue.clamped(to: 0.0...1.0)
            applyScrollerProportion(desired)
        case .decrementPage:
            requestTrackClickPageScroll(sender: sender, direction: -1)
        case .incrementPage:
            requestTrackClickPageScroll(sender: sender, direction: 1)
        case .decrementLine:
            requestLineScroll(direction: -1)
        case .incrementLine:
            requestLineScroll(direction: 1)
        case .knobSlot:
            // Some scroller styles report a track click as `.knobSlot` and update `doubleValue`
            // to the click location (jump-to). We prefer page-scrolling semantics:
            // - click above thumb: page up
            // - click below thumb: page down
            requestTrackClickPageScrollTowardEventOrProportion(sender: sender)
        default:
            break
        }
    }

    private func trackClickProportionForCurrentEvent(scroller: NSScroller) -> Double? {
        guard let event = NSApp.currentEvent else { return nil }
        let p = scroller.convert(event.locationInWindow, from: nil)
        let slot = scroller.rect(for: .knobSlot)
        guard slot.height.isFinite, slot.height > 0 else { return nil }
        let t = ((p.y - slot.minY) / slot.height).clamped(to: 0.0...1.0) // 0=bottom, 1=top
        return (1.0 - t).clamped(to: 0.0...1.0) // 0=top, 1=bottom
    }

    private func requestTrackClickPageScroll(sender: NSScroller, direction: Int) {
        // Track click: if this is a mouseDown, start a "hold-to-page" session with a fixed target
        // (mouse move while holding should not change the target).
        if NSApp.currentEvent?.type == .leftMouseDown,
           let prop = trackClickProportionForCurrentEvent(scroller: sender)
        {
            pagingHoldTargetProportion = prop
            pagingHoldDirection = direction
        }
        requestPageScroll(direction: direction)
    }

    private func requestTrackClickPageScrollTowardEventOrProportion(sender: NSScroller) {
        // Prefer a geometry-based proportion from the mouseDown event so we can stop
        // when the thumb reaches the original click position.
        let prop = trackClickProportionForCurrentEvent(scroller: sender) ?? sender.doubleValue

        do {
            let vp = try editor.viewportState()
            let total = max(1.0, Double(vp.totalVisualLines))
            let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
            let maxScroll = max(0.0, total - visible)
            guard maxScroll > 0 else { return }

            let currentPosRows = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
            let currentProp = (currentPosRows / maxScroll).clamped(to: 0.0...1.0)
            let desired = prop.clamped(to: 0.0...1.0)
            let direction = desired < currentProp ? -1 : 1

            if NSApp.currentEvent?.type == .leftMouseDown {
                pagingHoldTargetProportion = desired
                pagingHoldDirection = direction
            }

            requestSmoothScrollBy(deltaRows: Double(direction) * visible, vp: vp)
        } catch {
            NSSound.beep()
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
        pagingTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(pagingTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        pagingTimer?.tolerance = 0.004
    }

    private func stopPagingScroll() {
        pagingTargetPosRows = nil
        pagingHoldTargetProportion = nil
        pagingHoldDirection = 0
        pagingTimer?.invalidate()
        pagingTimer = nil
    }

    @objc private func pagingTimerFired(_ timer: Timer) {
        _ = timer
        pagingTick(mouseButtonsMask: UInt(NSEvent.pressedMouseButtons))
    }

    private func pagingTick(mouseButtonsMask: UInt) {
        guard var target = pagingTargetPosRows else {
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

            // Track-click hold behavior:
            // - While the mouse is held down, keep paging until the thumb reaches the original click position.
            // - Releasing the mouse stops further extension, but we still complete the current smooth page.
            if let holdTarget = pagingHoldTargetProportion, pagingHoldDirection != 0 {
                let leftPressed = (mouseButtonsMask & 0x1) != 0
                if leftPressed == false {
                    pagingHoldTargetProportion = nil
                    pagingHoldDirection = 0
                } else {
                    let currentProp = (current / maxScroll).clamped(to: 0.0...1.0)
                    let knobProportion = (visible / total).clamped(to: 0.0...1.0)
                    let knobTop = currentProp * (1.0 - knobProportion)
                    let knobBottom = (knobTop + knobProportion).clamped(to: 0.0...1.0)
                    let hold = holdTarget.clamped(to: 0.0...1.0)
                    if hold >= knobTop && hold <= knobBottom {
                        // Thumb reached the click location: stop immediately (do not finish the remaining animation).
                        stopPagingScroll()
                        return
                    }
                }
            }

            var delta = target - current
            if abs(delta) < 0.0001 {
                // Target reached. If the mouse is still held, extend by one more page (until thumb reaches click).
                if pagingHoldTargetProportion != nil, pagingHoldDirection != 0 {
                    let dir = pagingHoldDirection
                    let nextTarget = (current + Double(dir) * visible).clamped(to: 0.0...maxScroll)
                    if abs(nextTarget - current) < 0.0001 {
                        stopPagingScroll()
                        return
                    }
                    target = nextTarget
                    pagingTargetPosRows = target
                    delta = target - current
                } else {
                    stopPagingScroll()
                    return
                }
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

    func _stopPagingScrollForTesting() {
        stopPagingScroll()
    }

    func _beginTrackClickHoldForTesting(targetProportion: Double, direction: Int) {
        pagingHoldTargetProportion = targetProportion.clamped(to: 0.0...1.0)
        pagingHoldDirection = direction
    }

    var _isPagingActiveForTesting: Bool { pagingTargetPosRows != nil }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
