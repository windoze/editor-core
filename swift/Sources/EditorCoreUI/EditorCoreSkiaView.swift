import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

enum EditorCoreSkiaViewError: Error {
    case metalUnavailable
    case metalCommandQueueUnavailable
}

/// Hover information produced by `EditorCoreSkiaView` hit-testing.
///
/// Notes:
/// - `charOffset` is in Unicode scalar indices (Rust `char` offsets).
/// - `logicalLine/logicalColumn` are 0-based and also counted in Unicode scalars.
public struct EditorCoreSkiaHoverInfo {
    public let charOffset: UInt32
    public let logicalLine: UInt32
    public let logicalColumn: UInt32
    public let windowPoint: CGPoint
    public let viewPoint: CGPoint
    public let viewBackingXPx: Float
    public let viewBackingYPx: Float
    public let documentLinkJSON: String?

    public init(
        charOffset: UInt32,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        windowPoint: CGPoint,
        viewPoint: CGPoint,
        viewBackingXPx: Float,
        viewBackingYPx: Float,
        documentLinkJSON: String?
    ) {
        self.charOffset = charOffset
        self.logicalLine = logicalLine
        self.logicalColumn = logicalColumn
        self.windowPoint = windowPoint
        self.viewPoint = viewPoint
        self.viewBackingXPx = viewBackingXPx
        self.viewBackingYPx = viewBackingYPx
        self.documentLinkJSON = documentLinkJSON
    }
}

/// Context information for building a context menu at a given mouse event.
public struct EditorCoreSkiaContextMenuContext {
    public let charOffset: UInt32
    public let logicalLine: UInt32
    public let logicalColumn: UInt32
    public let windowPoint: CGPoint
    public let viewPoint: CGPoint
    public let viewBackingXPx: Float
    public let viewBackingYPx: Float

    public init(
        charOffset: UInt32,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        windowPoint: CGPoint,
        viewPoint: CGPoint,
        viewBackingXPx: Float,
        viewBackingYPx: Float
    ) {
        self.charOffset = charOffset
        self.logicalLine = logicalLine
        self.logicalColumn = logicalColumn
        self.windowPoint = windowPoint
        self.viewPoint = viewPoint
        self.viewBackingXPx = viewBackingXPx
        self.viewBackingYPx = viewBackingYPx
    }
}

public enum EditorCoreLSPFormattingResult: Equatable {
    case applied
    case noEdits
    case unavailable(String)
    case failed(String)

    public var didApply: Bool {
        if case .applied = self { return true }
        return false
    }

    public var message: String? {
        switch self {
        case .applied:
            return nil
        case .noEdits:
            return "No formatting edits were returned."
        case .unavailable(let reason), .failed(let reason):
            return reason
        }
    }
}

public struct EditorCoreSkiaGutterDiagnosticMarker: Equatable {
    public enum Kind: Equatable {
        case error
        case warning
        case information
        case hint
    }

    public var logicalLine: UInt32
    public var charOffset: UInt32
    public var kind: Kind

    public init(logicalLine: UInt32, charOffset: UInt32, kind: Kind) {
        self.logicalLine = logicalLine
        self.charOffset = charOffset
        self.kind = kind
    }
}

/// 自绘版 AppKit 组件（Option 2）：
/// - Rust: editor-core + editor-core-ui + Skia（Metal/GPU 直接绘制到 `MTLTexture`）
/// - Swift/AppKit: `MTKView` 负责承接事件并把 `CAMetalDrawable` 呈现到屏幕
///
/// 这是一个“先把正确性与 IME 桥打通”的 MVP：
/// - caret / selection / mouse drag selection
/// - insertText / markedText（IME 组合输入）
/// - undo/redo
@MainActor
public final class EditorCoreSkiaView: MTKView {
    public let editor: EditorUI

    /// Pasteboard used for copy/cut/paste. Defaults to `NSPasteboard.general`.
    ///
    /// Tests can override this to avoid touching the real system clipboard.
    public var pasteboard: NSPasteboard = .general

    /// Hook for opening URLs (e.g. LSP `DocumentLink.target`). Defaults to `NSWorkspace.shared.open`.
    public var onOpenURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Called when Cmd-click hits an LSP `DocumentLink` that has no direct target URL.
    ///
    /// Hosts can use this to run `documentLink/resolve` and open the resolved target.
    public var onDocumentLinkClick: ((String) -> Bool)?

    /// Called when Cmd-click hits LSP inlay hint virtual text.
    ///
    /// The payload is the raw `InlayHint` JSON returned by the Rust hit-test. Hosts can use this
    /// to run `inlayHint/resolve` and display or apply the resolved hint.
    public var onInlayHintClick: ((String) -> Bool)?

    /// Called when Cmd-click hits LSP code lens virtual text.
    ///
    /// The payload is the raw `CodeLens` JSON returned by the Rust hit-test. Hosts should parse and
    /// execute it, resolving the lens first when needed.
    public var onCodeLensClick: ((String) -> Bool)?

    /// Called when the editor's viewport state (scroll position / total lines / viewport size) may have changed.
    ///
    /// Hosts can use this to keep native scrollbars in sync.
    public var onViewportStateDidChange: (() -> Void)?

    /// Called when the document text mutates (typing, delete, undo/redo, IME commit, etc).
    ///
    /// Hosts can use this to:
    /// - track "dirty" state
    /// - auto-pin preview tabs (VSCode behavior)
    /// - trigger external indexing, etc.
    public var onDidMutateDocumentText: (() -> Void)?

    /// Called after committed text mutates the document through `insertText`.
    ///
    /// This is only for finalized text commits. IME marked/preedit updates use `setMarkedText`
    /// and do not call this hook until the system commits text through `insertText`.
    public var onDidCommitText: ((String) -> Void)?

    /// Called after the selection/caret may have changed.
    ///
    /// `causedByTextMutation` is `true` when the selection moved as part of an edit, such as typing,
    /// paste, delete, undo/redo, or formatting. Hosts can use this to distinguish normal linked
    /// multi-cursor continuation from explicit navigation/click selection changes.
    public var onDidChangeSelection: ((_ causedByTextMutation: Bool) -> Void)?

    /// Called when the mouse hovers over a new character offset in the document.
    ///
    /// Hosts can use this to present hover UI (tooltip/popover/inspector).
    public var onHover: ((EditorCoreSkiaHoverInfo) -> Void)?

    /// Called when the mouse leaves the view, allowing hosts to dismiss hover UI.
    public var onHoverExit: (() -> Void)?

    /// Context menu hook.
    ///
    /// - If the closure returns a menu, it will be shown.
    /// - If it returns `nil`, the view falls back to a simple default menu (cut/copy/paste/select all).
    public var contextMenuProvider: ((EditorCoreSkiaContextMenuContext) -> NSMenu?)?

    /// Cmd-click hook (e.g. "Go to Definition" UX).
    ///
    /// Notes:
    /// - This fires only for Cmd-click *without* Option (Cmd+Option is reserved for multi-cursor).
    /// - It runs after document-link detection; if a document link is present, the view opens it and
    ///   does not call this hook.
    /// - Return `true` to indicate the click was handled and should not fall back to normal caret/selection.
    public var onCommandClick: ((EditorCoreSkiaContextMenuContext) -> Bool)?

    /// Cmd-hover hook (e.g. VSCode-like "Go to Definition" underline + pointer affordance).
    ///
    /// This hook must be **side-effect free** and should return whether the host considers the point
    /// "clickable" under Cmd-click.
    ///
    /// Notes:
    /// - This is called only for Cmd-hover *without* Option (Cmd+Option is reserved for multi-cursor).
    /// - When not provided, the view falls back to a conservative default (`onCommandClick != nil`).
    public var onCommandHover: ((EditorCoreSkiaContextMenuContext) -> Bool)?

    /// Called after the view becomes first responder.
    ///
    /// Hosts with multiple editor views for the same document use this to track the active pane.
    public var onDidBecomeFirstResponder: (() -> Void)?

    /// Enable/disable Cmd-hover visual feedback (underline + pointing-hand cursor).
    ///
    /// This is enabled by default because it is an important discoverability affordance.
    public var commandHoverLinkFeedbackEnabled: Bool = true

    /// Called when async derived-state processing applied edits or a short poll window finishes.
    ///
    /// This is primarily useful for tests and for hosts that want explicit derived-state/status
    /// update signals. A poll window can finish without applied edits when an async provider only
    /// changed status, such as an LSP request error.
    public var onDidApplyAsyncProcessing: (() -> Void)?

    // MARK: - Caret appearance (width + blinking)

    /// Caret width in points (logical units).
    ///
    /// The value is multiplied by the view's backing scale factor before being sent to Rust.
    public var caretWidthPoints: CGFloat = 2.0 {
        didSet { applyCaretAppearanceIfNeeded(force: true) }
    }

    /// Enable/disable caret blinking.
    ///
    /// When disabled, the caret stays visible (subject to `caretVisibleOverride`).
    public var caretBlinkEnabled: Bool = true {
        didSet { updateCaretBlinkTimer() }
    }

    /// Caret blink toggle interval in seconds (how often it flips visible/hidden).
    ///
    /// Set to a non-positive value to effectively disable blinking.
    public var caretBlinkIntervalSeconds: TimeInterval = 0.55 {
        didSet { updateCaretBlinkTimer() }
    }

    /// Optional visibility override. When non-nil, blinking is ignored and this value is used.
    ///
    /// This is mainly intended for tests and for hosts that want custom focus rules.
    public var caretVisibleOverride: Bool? {
        didSet { applyCaretAppearanceIfNeeded(force: true) }
    }

    /// Vertical alignment of glyphs within each line box (`lineHeightPx`).
    ///
    /// Notes:
    /// - This affects rendering only; hit-testing and selection/caret rectangles remain based on the
    ///   monospace grid + line height.
    /// - Default is `.center` to match common editor behavior when line height > font size.
    public var textVerticalAlign: EditorUI.TextVerticalAlign = .center {
        didSet {
            applyTextVerticalAlignIfNeeded(force: true)
            requestRedraw()
        }
    }

    // MARK: - Render metrics (font size)

    /// Base font size in points (logical units).
    ///
    /// Notes:
    /// - The value is converted to pixels using the view's backing scale factor.
    /// - Other render metrics (line height, cell width, padding) scale proportionally to preserve
    ///   the current default look.
    public var fontSizePoints: CGFloat = 13.0 {
        didSet {
            let normalized = Self.normalizeFontSizePoints(fontSizePoints)
            if fontSizePoints != normalized {
                fontSizePoints = normalized
                return
            }
            updateViewportIfNeeded()
        }
    }

    var caretBlinkPhaseVisible: Bool = true
    // 注意：`Timer` 不是 `Sendable`，而 `deinit` 是非隔离上下文；
    // 这里用 `nonisolated(unsafe)` 允许在 `deinit` 中把 timer 转交给主线程做 invalidate。
    nonisolated(unsafe) var caretBlinkTimer: Timer?
    let caretBlinkTimerDisabledForTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    var lastAppliedCaretWidthPx: Float?
    var lastAppliedCaretVisible: Bool?
    var lastAppliedTextVerticalAlign: EditorUI.TextVerticalAlign?

    // MARK: - Viewport observers (multi-subscriber)

    @MainActor
    public final class ViewportStateObserverToken {
        weak var view: EditorCoreSkiaView?
        let id: UUID

        init(view: EditorCoreSkiaView, id: UUID) {
            self.view = view
            self.id = id
        }

        deinit {
            // 注意：即使 `ViewportStateObserverToken` 标注了 `@MainActor`，`deinit` 依然是非隔离上下文，
            // 不能直接调用 MainActor-isolated 的实例方法。
            //
            // 我们使用 `DispatchQueue.main.async` 进行 best-effort 移除，避免跨线程访问 view 内部字典。
            let id = id
            let view = view
            DispatchQueue.main.async { [weak view] in
                view?.removeViewportStateObserver(id)
            }
        }
    }

    var viewportObservers: [UUID: () -> Void] = [:]

    /// Add an additional viewport-state observer without overwriting `onViewportStateDidChange`.
    ///
    /// The returned token must be retained; when it is released, the observer is removed.
    @discardableResult
    public func addViewportStateObserver(_ handler: @escaping () -> Void) -> ViewportStateObserverToken {
        let id = UUID()
        viewportObservers[id] = handler
        return ViewportStateObserverToken(view: self, id: id)
    }

    func removeViewportStateObserver(_ id: UUID) {
        viewportObservers[id] = nil
    }

    func notifyViewportStateDidChange() {
        gutterDiagnosticOverlayView.needsDisplay = true
        onViewportStateDidChange?()
        for f in viewportObservers.values {
            f()
        }
    }

    let metalCommandQueue: MTLCommandQueue
    var viewportWidthPx: UInt32 = 0
    var viewportHeightPx: UInt32 = 0
    var scaleFactor: CGFloat = 1
    var didLogScaleDebugOnce: Bool = false
    var lastInputDebugLogUptime: TimeInterval = 0
    var drawScheduled: Bool = false
    var didPresentFirstFrame: Bool = false
    var didLogDrawSetupOnce: Bool = false
    let textCacheDebugEnabled: Bool = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_TEXT_CACHE"] == "1"
    let perfDebugEnabled: Bool = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_PERF"] == "1"

    // MARK: - Perf counters (debug only)

    var perfLastReportUptime: TimeInterval = 0
    var perfInsertTextCount: Int = 0
    var perfInsertTextTotalMs: Double = 0
    var perfSetMarkedCount: Int = 0
    var perfSetMarkedTotalMs: Double = 0
    var perfDoCommandCount: Int = 0
    var perfDoCommandTotalMs: Double = 0
    var perfRenderMetalCount: Int = 0
    var perfRenderMetalTotalMs: Double = 0

    // MARK: - Caret appearance helpers

    func desiredCaretVisibleForRender() -> Bool {
        if let caretVisibleOverride {
            return caretVisibleOverride
        }
        guard caretBlinkEnabled, caretBlinkIntervalSeconds > 0 else {
            return true
        }
        // Only blink when focused; otherwise keep it visible (non-blinking).
        if window?.firstResponder === self {
            return caretBlinkPhaseVisible
        }
        return true
    }

    func applyCaretAppearanceIfNeeded(force: Bool) {
        // Keep caret width stable across DPI changes (points -> px).
        let widthPx = Float(max(1.0, caretWidthPoints * scaleFactor))
        let visible = desiredCaretVisibleForRender()

        do {
            if force || lastAppliedCaretWidthPx == nil || abs((lastAppliedCaretWidthPx ?? 0) - widthPx) > 0.01 {
                try editor.setCaretWidthPx(widthPx)
                lastAppliedCaretWidthPx = widthPx
            }
            if force || lastAppliedCaretVisible == nil || lastAppliedCaretVisible != visible {
                try editor.setCaretVisible(visible)
                lastAppliedCaretVisible = visible
            }
        } catch {
            NSLog("EditorCoreSkiaView applyCaretAppearance failed: %@", String(describing: error))
        }
    }

    func applyTextVerticalAlignIfNeeded(force: Bool) {
        let align = textVerticalAlign
        if force == false, lastAppliedTextVerticalAlign == align {
            return
        }
        do {
            try editor.setTextVerticalAlign(align)
            lastAppliedTextVerticalAlign = align
        } catch {
            NSLog("EditorCoreSkiaView setTextVerticalAlign failed: %@", String(describing: error))
        }
    }

    func updateCaretBlinkTimer() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil

        caretBlinkPhaseVisible = true
        applyCaretAppearanceIfNeeded(force: true)

        guard caretBlinkEnabled, caretBlinkIntervalSeconds > 0 else { return }
        guard window?.firstResponder === self else { return }
        guard caretBlinkTimerDisabledForTests == false else { return }

        caretBlinkTimer = Timer.scheduledTimer(
            timeInterval: caretBlinkIntervalSeconds,
            target: self,
            selector: #selector(caretBlinkTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        caretBlinkTimer?.tolerance = 0.02
    }

    @objc private func caretBlinkTimerFired(_ timer: Timer) {
        _ = timer
        caretBlinkPhaseVisible.toggle()
        applyCaretAppearanceIfNeeded(force: true)
        requestRedraw()
    }

    func perfReportIfNeeded(force: Bool = false) {
        guard perfDebugEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if force == false, perfLastReportUptime > 0, now - perfLastReportUptime < 1.0 {
            return
        }
        perfLastReportUptime = now

        let insertAvg = perfInsertTextCount > 0 ? (perfInsertTextTotalMs / Double(perfInsertTextCount)) : 0
        let markedAvg = perfSetMarkedCount > 0 ? (perfSetMarkedTotalMs / Double(perfSetMarkedCount)) : 0
        let cmdAvg = perfDoCommandCount > 0 ? (perfDoCommandTotalMs / Double(perfDoCommandCount)) : 0
        let renderAvg = perfRenderMetalCount > 0 ? (perfRenderMetalTotalMs / Double(perfRenderMetalCount)) : 0

        NSLog(
            "EditorCoreSkiaView perf(1s): insertText=%d avg=%.2fms setMarked=%d avg=%.2fms doCommand=%d avg=%.2fms renderMetal=%d avg=%.2fms",
            perfInsertTextCount,
            insertAvg,
            perfSetMarkedCount,
            markedAvg,
            perfDoCommandCount,
            cmdAvg,
            perfRenderMetalCount,
            renderAvg
        )

        perfInsertTextCount = 0
        perfInsertTextTotalMs = 0
        perfSetMarkedCount = 0
        perfSetMarkedTotalMs = 0
        perfDoCommandCount = 0
        perfDoCommandTotalMs = 0
        perfRenderMetalCount = 0
        perfRenderMetalTotalMs = 0
    }

    // MARK: - Text cache (performance)

    /// AppKit/NSTextInputClient 在输入过程中会频繁查询 `selectedRange/markedRange/firstRect/...`。
    /// 如果每次都跨 FFI 拉整份文档字符串，会造成明显卡顿（尤其是长文档 + 频繁回调）。
    var docContentEpoch: UInt64 = 1
    var docTextCacheEpoch: UInt64 = 0
    var docTextCache: String?
    var docTextCacheScalarCount: Int = 0
    var cachedSelectedRange: (epoch: UInt64, start: UInt32, end: UInt32, value: NSRange)?
    var cachedMarkedRange: (epoch: UInt64, start: UInt32, len: UInt32, value: NSRange)?

    var lineHeightPx: Float = 18
    var cellWidthPx: Float = 8
    var paddingPx: Float = 8
    struct RenderMetricsSnapshot: Equatable {
        let fontSizePx: Float
        let lineHeightPx: Float
        let cellWidthPx: Float
        let paddingPx: Float
    }

    var lastAppliedRenderMetrics: RenderMetricsSnapshot?
    /// 当前 gutter 宽度（以 cell 为单位）；用于避免频繁跨 FFI 发送重复的 set 操作。
    var gutterWidthCells: UInt32 = 4
    let gutterDiagnosticOverlayView = EditorCoreSkiaGutterDiagnosticOverlayView()

    public var gutterDiagnosticMarkers: [EditorCoreSkiaGutterDiagnosticMarker] = [] {
        didSet { gutterDiagnosticOverlayView.needsDisplay = true }
    }

    /// gutter 的最小宽度（以 cell 为单位）。
    ///
    /// - 该值会影响“行号宽度自适应”逻辑：真实需要的宽度会与该值取 max。
    /// - 典型用法：host 想要 VSCode 风格更宽的 gutter，但仍希望在超大文件（10K/1M 行）时继续自动扩展。
    public var minimumGutterWidthCells: UInt32 = 4 {
        didSet {
            if minimumGutterWidthCells == oldValue { return }
            // Best-effort：当 host 更新最小 gutter 宽度时，立即尝试同步到 Rust 侧。
            _ = updateGutterWidthIfNeeded()
            requestRedraw()
        }
    }

    var hoverTrackingArea: NSTrackingArea?
    var lastHoverCharOffset: UInt32?
    var lastHoverModifierFlags: NSEvent.ModifierFlags = []
    var lastHoverContextForCommandHover: EditorCoreSkiaContextMenuContext?
    var lastHoverDocumentLinkJSONForCommandHover: String?

    var commandHoverActiveRange: EcuSelectionRange?
    var commandHoverCursorIsPointing: Bool = false

    var lastHoverScalarIndex: (epoch: UInt64, offset: Int, index: String.UnicodeScalarView.Index)?

    lazy var textInputContext = NSTextInputContext(client: self)

    var processingPollTimer: DispatchSourceTimer?
    var processingPollDeadlineUptime: TimeInterval = 0
    /// If `true`, keep polling `editor.pollProcessing()` continuously.
    ///
    /// This is useful for live LSP demos where server-driven updates (diagnostics, semantic tokens,
    /// inlay hints) can arrive after an edit burst.
    public var alwaysPollProcessing: Bool = false {
        didSet {
            if alwaysPollProcessing {
                startProcessingPoll()
            }
        }
    }


    public init(
        library: EditorCoreUIFFILibrary,
        initialText: String = "",
        viewportWidthCells: UInt32 = 120,
        fontFamiliesCSV: String? = nil
    ) throws {
        self.editor = try EditorUI(library: library, initialText: initialText, viewportWidthCells: viewportWidthCells)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EditorCoreSkiaViewError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw EditorCoreSkiaViewError.metalCommandQueueUnavailable
        }
        self.metalCommandQueue = queue
        super.init(frame: .zero, device: device)

        if textCacheDebugEnabled {
            NSLog("EditorCoreSkiaView text cache debug enabled (EDITOR_CORE_APPKIT_DEBUG_TEXT_CACHE=1)")
        }
        if perfDebugEnabled {
            NSLog("EditorCoreSkiaView perf debug enabled (EDITOR_CORE_APPKIT_DEBUG_PERF=1)")
        }

        // 说明：
        // - 理想情况下我们希望使用“事件驱动”的 on-demand draw（`enableSetNeedsDisplay = true` + `isPaused = true`）。
        // - 但在 macOS 26.3 的部分组合下，首次显示阶段 on-demand draw 可能不会拿到 drawable，
        //   导致用户看到“编辑区空白”直到发生额外事件。
        //
        // 解决策略：启动时先连续渲染，保证首帧一定 present；首帧成功后自动切回 on-demand。
        enableSetNeedsDisplay = false
        isPaused = false
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        delegate = self
        configureGutterDiagnosticOverlay()

        // 让 Rust/Skia 走 Metal 后端渲染到 `CAMetalDrawable.texture`。
        try editor.enableMetal(device: device, commandQueue: queue)

        // 默认主题（可由 host 覆盖）。同时把 gutter 的 reserved StyleId 配色也放进默认主题里，
        // 避免后续 `setStyleColors` 被多次调用时出现“互相覆盖”的坑。
        try EditorCoreSkiaTheme.defaultLight().apply(to: editor)

        // 让 gutter 可见（行号 + 折叠标记）。
        try editor.setGutterWidthCells(gutterWidthCells)
        _ = updateGutterWidthIfNeeded()

        if let fontFamiliesCSV, fontFamiliesCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try editor.setFontFamiliesCSV(fontFamiliesCSV)
        }
    }

    /// Create an AppKit view from an existing `EditorUI` handle.
    ///
    /// This is intended for multi-view/split-pane scenarios, where multiple `EditorCoreSkiaView`
    /// instances share the same document via `EditorUI.cloneView(...)`.
    ///
    /// Notes:
    /// - Unlike `init(library:initialText:viewportWidthCells:)`, this initializer does **not**
    ///   apply a default theme or reset gutter settings. It assumes the caller has already
    ///   configured the `EditorUI` (or cloned it from an already-configured view).
    public init(editor: EditorUI, fontFamiliesCSV: String? = nil) throws {
        self.editor = editor
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EditorCoreSkiaViewError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw EditorCoreSkiaViewError.metalCommandQueueUnavailable
        }
        self.metalCommandQueue = queue
        super.init(frame: .zero, device: device)

        if textCacheDebugEnabled {
            NSLog("EditorCoreSkiaView text cache debug enabled (EDITOR_CORE_APPKIT_DEBUG_TEXT_CACHE=1)")
        }
        if perfDebugEnabled {
            NSLog("EditorCoreSkiaView perf debug enabled (EDITOR_CORE_APPKIT_DEBUG_PERF=1)")
        }

        enableSetNeedsDisplay = false
        isPaused = false
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        delegate = self
        configureGutterDiagnosticOverlay()

        // 让 Rust/Skia 走 Metal 后端渲染到 `CAMetalDrawable.texture`。
        try editor.enableMetal(device: device, commandQueue: queue)

        // Best-effort: keep the Swift-side gutter cache consistent with the underlying handle.
        if let current = try? editor.gutterWidthCells() {
            gutterWidthCells = current
        }
        _ = updateGutterWidthIfNeeded()

        if let fontFamiliesCSV, fontFamiliesCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try editor.setFontFamiliesCSV(fontFamiliesCSV)
        }
    }

    func configureGutterDiagnosticOverlay() {
        gutterDiagnosticOverlayView.editorView = self
        gutterDiagnosticOverlayView.frame = bounds
        gutterDiagnosticOverlayView.autoresizingMask = [.width, .height]
        addSubview(gutterDiagnosticOverlayView)
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public override init(frame frameRect: NSRect, device: MTLDevice?) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public required init(coder: NSCoder) {
        fatalError("unavailable")
    }


    deinit {
        processingPollTimer?.cancel()
        processingPollTimer = nil
        let timer = caretBlinkTimer
        caretBlinkTimer = nil
        DispatchQueue.main.async {
            timer?.invalidate()
        }
    }
}
struct EditorCoreSkiaGutterDiagnosticMarkerLayout {
    let marker: EditorCoreSkiaGutterDiagnosticMarker
    let rect: CGRect
}

@MainActor
final class EditorCoreSkiaGutterDiagnosticOverlayView: NSView {
    weak var editorView: EditorCoreSkiaView?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let editorView, let ctx = NSGraphicsContext.current?.cgContext else { return }

        for layout in editorView.gutterDiagnosticMarkerLayouts() where layout.rect.intersects(dirtyRect) {
            draw(layout.marker.kind, in: layout.rect, ctx: ctx)
        }
    }

    func draw(_ kind: EditorCoreSkiaGutterDiagnosticMarker.Kind, in rect: CGRect, ctx: CGContext) {
        let color = kind.gutterColor
        let r = rect.insetBy(dx: max(0.5, rect.width * 0.08), dy: max(0.5, rect.height * 0.08))

        switch kind {
        case .error:
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: r)
        case .warning:
            ctx.setFillColor(color.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: r.midX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            ctx.closePath()
            ctx.fillPath()
        case .information:
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: r)
        case .hint:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(1, min(r.width, r.height) * 0.16))
            ctx.strokeEllipse(in: r)
        }
    }
}

extension EditorCoreSkiaGutterDiagnosticMarker.Kind {
    var gutterColor: NSColor {
        switch self {
        case .error:
            return NSColor.systemRed.withAlphaComponent(0.95)
        case .warning:
            return NSColor.systemOrange.withAlphaComponent(0.95)
        case .information:
            return NSColor.systemBlue.withAlphaComponent(0.9)
        case .hint:
            return NSColor.systemGray.withAlphaComponent(0.9)
        }
    }
}

// MARK: - Testing hooks

@MainActor
extension EditorCoreSkiaView {
    var _lastAppliedCaretWidthPxForTesting: Float? { lastAppliedCaretWidthPx }
    var _lastAppliedCaretVisibleForTesting: Bool? { lastAppliedCaretVisible }
    public var _gutterDiagnosticMarkersForTesting: [EditorCoreSkiaGutterDiagnosticMarker] { gutterDiagnosticMarkers }

    public func _gutterDiagnosticMarkerRectsForTesting() -> [CGRect] {
        gutterDiagnosticMarkerLayouts().map(\.rect)
    }

    func _caretBlinkTickForTesting() {
        caretBlinkPhaseVisible.toggle()
        applyCaretAppearanceIfNeeded(force: true)
    }
}

extension EditorCoreSkiaView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // MTKView 在窗口缩放 / backing scale 变化时会回调这里；同步 Rust viewport。
        updateViewportIfNeeded()
    }

    public func draw(in view: MTKView) {
        updateViewportIfNeeded()
        renderToCurrentDrawable(debugSource: "delegate")
    }
}

extension EditorCoreSkiaView: @preconcurrency NSTextInputClient {}
