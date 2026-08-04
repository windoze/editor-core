import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

extension EditorCoreSkiaView {
    // MARK: - Mouse

    func debugLogInput(_ event: NSEvent, xPx: Float, yPx: Float, phase: String, force: Bool) {
        guard ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_INPUT"] == "1" else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if force == false, now - lastInputDebugLogUptime < 0.1 {
            return
        }
        lastInputDebugLogUptime = now

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let boundsSize = bounds.size
        let backingSize = convertToBacking(boundsSize)
        let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 0
        let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 0

        var extra = ""
        if let scalar = try? editor.viewPointToCharOffset(xPx: xPx, yPx: yPx) {
            if let snapped = try? editor.charOffsetToViewPoint(offset: scalar) {
                let dx = snapped.xPx - xPx
                let dy = snapped.yPx - yPx
                extra = String(format: " off=%u snapped=(%.1f,%.1f) d=(%.1f,%.1f)", scalar, snapped.xPx, snapped.yPx, dx, dy)
            } else {
                extra = " off=\(scalar)"
            }
        }

        NSLog(
            "EditorCoreSkiaView input %@: window=%@ view=%@ sx=%.3f sy=%.3f -> px=(%.1f,%.1f) viewport=%ux%u%@",
            phase,
            NSStringFromPoint(windowPoint),
            NSStringFromPoint(viewPoint),
            Double(sx),
            Double(sy),
            Double(xPx),
            Double(yPx),
            viewportWidthPx,
            viewportHeightPx,
            extra
        )
    }

    func clearCommandHoverFeedback() {
        if let range = commandHoverActiveRange {
            do {
                try editor.removeStyle(
                    start: range.start,
                    end: range.end,
                    styleId: EditorCoreSkiaBuiltinStyleId.commandHoverLink
                )
            } catch {
                // Hover feedback is best-effort; ignore failures.
            }
            commandHoverActiveRange = nil
        }

        if commandHoverCursorIsPointing {
            NSCursor.iBeam.set()
            commandHoverCursorIsPointing = false
        }
    }

    /// Dismiss host hover UI (e.g. LSP hover popovers) on any explicit user action.
    ///
    /// Rationale:
    /// - Hover is triggered by mouse movement, but should not "stick" when the user starts typing,
    ///   moves the caret, clicks, scrolls, etc.
    /// - Cmd-hover feedback (underline + pointing cursor) can also become stale when the document
    ///   changes without further mouse movement.
    func dismissHoverUIForUserAction() {
        clearCommandHoverFeedback()
        lastHoverModifierFlags = []
        lastHoverContextForCommandHover = nil
        lastHoverDocumentLinkJSONForCommandHover = nil

        if lastHoverCharOffset != nil {
            lastHoverCharOffset = nil
            onHoverExit?()
        }
    }

    func updateCommandHoverFeedbackIfNeeded(
        eventFlags: NSEvent.ModifierFlags,
        hoverContext: EditorCoreSkiaContextMenuContext,
        documentLinkJSON: String?
    ) {
        guard commandHoverLinkFeedbackEnabled else {
            clearCommandHoverFeedback()
            return
        }

        // Cmd+Option is reserved for multi-cursor; do not show "clickable symbol" affordance.
        let isCmdHover = eventFlags.contains(.command) && eventFlags.contains(.option) == false
        guard isCmdHover else {
            clearCommandHoverFeedback()
            return
        }

        var wantsPointer = false
        var wantsUnderlineRange: EcuSelectionRange?

        // Document links are always Cmd-clickable.
        if documentLinkJSON != nil {
            wantsPointer = true
        }

        let hostAllows = onCommandHover?(hoverContext) ?? (onCommandClick != nil)
        if hostAllows {
            if let text = documentTextForInputQueries() {
                wantsUnderlineRange = tokenRangeForCommandHover(
                    in: text,
                    atCharOffset: hoverContext.charOffset
                )
                if wantsUnderlineRange != nil {
                    wantsPointer = true
                }
            }
        }

        if wantsUnderlineRange != commandHoverActiveRange {
            if let old = commandHoverActiveRange {
                do {
                    try editor.removeStyle(
                        start: old.start,
                        end: old.end,
                        styleId: EditorCoreSkiaBuiltinStyleId.commandHoverLink
                    )
                } catch {
                    // Best-effort.
                }
                commandHoverActiveRange = nil
            }

            if let next = wantsUnderlineRange {
                do {
                    try editor.addStyle(
                        start: next.start,
                        end: next.end,
                        styleId: EditorCoreSkiaBuiltinStyleId.commandHoverLink
                    )
                    commandHoverActiveRange = next
                } catch {
                    commandHoverActiveRange = nil
                }
            }

            requestRedraw()
        }

        if wantsPointer {
            if commandHoverCursorIsPointing == false {
                NSCursor.pointingHand.set()
                commandHoverCursorIsPointing = true
            } else {
                // Keep pointer cursor stable across moves.
                NSCursor.pointingHand.set()
            }
        } else {
            if commandHoverCursorIsPointing {
                NSCursor.iBeam.set()
                commandHoverCursorIsPointing = false
            }
        }
    }

    static func isNewlineScalar(_ s: UnicodeScalar) -> Bool {
        s.value == 10 /* \n */ || s.value == 13 /* \r */
    }

    static func isAsciiWordScalar(_ s: UnicodeScalar) -> Bool {
        guard s.isASCII else { return false }
        switch s.value {
        case 48...57: // 0-9
            return true
        case 65...90: // A-Z
            return true
        case 97...122: // a-z
            return true
        case 95: // _
            return true
        default:
            return false
        }
    }

    static func isWordTokenScalar(_ s: UnicodeScalar) -> Bool {
        if s.properties.isWhitespace {
            return false
        }
        if s.isASCII {
            return isAsciiWordScalar(s)
        }
        // Match the kernel's editor-friendly word model: treat non-ASCII as a single "word unit".
        return true
    }

    func scalarIndexForCachedText(
        scalars: String.UnicodeScalarView,
        targetOffset: Int
    ) -> String.UnicodeScalarView.Index? {
        guard targetOffset >= 0 else { return nil }
        guard docTextCacheScalarCount > 0 else { return nil }
        guard targetOffset < docTextCacheScalarCount else { return nil }

        let epoch = docContentEpoch
        if let cached = lastHoverScalarIndex, cached.epoch == epoch {
            if cached.offset == targetOffset {
                return cached.index
            }

            var idx = cached.index
            var off = cached.offset
            if targetOffset > off {
                while off < targetOffset, idx != scalars.endIndex {
                    idx = scalars.index(after: idx)
                    off += 1
                }
            } else {
                while off > targetOffset, idx != scalars.startIndex {
                    idx = scalars.index(before: idx)
                    off -= 1
                }
            }

            lastHoverScalarIndex = (epoch: epoch, offset: off, index: idx)
            return idx
        }

        let idx = scalars.index(scalars.startIndex, offsetBy: targetOffset)
        lastHoverScalarIndex = (epoch: epoch, offset: targetOffset, index: idx)
        return idx
    }

    func tokenRangeForCommandHover(in text: String, atCharOffset offset: UInt32) -> EcuSelectionRange? {
        let scalarCount = docTextCacheScalarCount
        guard scalarCount > 0 else { return nil }

        let requested = Int(offset)
        let clamped = min(max(0, requested), scalarCount - 1)
        let scalars = text.unicodeScalars
        guard let anchorIndex = scalarIndexForCachedText(scalars: scalars, targetOffset: clamped) else {
            return nil
        }

        func tokenSpanAt(foundOffset: Int, foundIndex: String.UnicodeScalarView.Index) -> (start: Int, end: Int)? {
            let s = scalars[foundIndex]
            guard Self.isWordTokenScalar(s) else { return nil }

            // ASCII word runs expand; non-ASCII token chars are single-char units.
            if Self.isAsciiWordScalar(s) {
                var startOffset = foundOffset
                var startIndex = foundIndex
                while startOffset > 0 {
                    let prev = scalars.index(before: startIndex)
                    let ps = scalars[prev]
                    if Self.isNewlineScalar(ps) { break }
                    if Self.isAsciiWordScalar(ps) {
                        startOffset -= 1
                        startIndex = prev
                    } else {
                        break
                    }
                }

                var endOffset = foundOffset + 1
                var endIndex = scalars.index(after: foundIndex)
                while endOffset < scalarCount, endIndex != scalars.endIndex {
                    let ns = scalars[endIndex]
                    if Self.isNewlineScalar(ns) { break }
                    if Self.isAsciiWordScalar(ns) {
                        endOffset += 1
                        endIndex = scalars.index(after: endIndex)
                    } else {
                        break
                    }
                }
                return (startOffset, endOffset)
            }

            return (foundOffset, foundOffset + 1)
        }

        // Prefer token under the cursor; if not a token, search within the same logical line.
        if let span = tokenSpanAt(foundOffset: clamped, foundIndex: anchorIndex) {
            return EcuSelectionRange(start: UInt32(span.start), end: UInt32(span.end))
        }

        // Search right.
        var rightOffset = clamped
        var rightIndex = anchorIndex
        while rightOffset + 1 < scalarCount {
            rightOffset += 1
            rightIndex = scalars.index(after: rightIndex)
            if rightIndex == scalars.endIndex { break }
            let s = scalars[rightIndex]
            if Self.isNewlineScalar(s) { break }
            if let span = tokenSpanAt(foundOffset: rightOffset, foundIndex: rightIndex) {
                return EcuSelectionRange(start: UInt32(span.start), end: UInt32(span.end))
            }
        }

        // Search left.
        if clamped > 0 {
            var leftOffset = clamped
            var leftIndex = anchorIndex
            while leftOffset > 0 {
                leftOffset -= 1
                leftIndex = scalars.index(before: leftIndex)
                let s = scalars[leftIndex]
                if Self.isNewlineScalar(s) { break }
                if let span = tokenSpanAt(foundOffset: leftOffset, foundIndex: leftIndex) {
                    return EcuSelectionRange(start: UInt32(span.start), end: UInt32(span.end))
                }
            }
        }

        return nil
    }

    public override func mouseMoved(with event: NSEvent) {
        updateViewportIfNeeded()

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: windowPoint,
            view: self
        )

        do {
            let offset = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
            let pos = try editor.charOffsetToLogicalPosition(offset: offset)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let shouldQueryLink = (onHover != nil) || (flags.contains(.command) && flags.contains(.option) == false)
            let linkJSON = shouldQueryLink ? (try? editor.documentLinkJSONAtViewPoint(xPx: xPx, yPx: yPx)) : nil

            let ctx = EditorCoreSkiaContextMenuContext(
                charOffset: offset,
                logicalLine: pos.line,
                logicalColumn: pos.column,
                windowPoint: windowPoint,
                viewPoint: viewPoint,
                viewBackingXPx: xPx,
                viewBackingYPx: yPx
            )
            lastHoverContextForCommandHover = ctx
            lastHoverDocumentLinkJSONForCommandHover = linkJSON ?? nil

            let didChangeOffset = (offset != lastHoverCharOffset)
            if didChangeOffset {
                lastHoverCharOffset = offset
            }

            if didChangeOffset, onHover != nil {
                onHover?(
                    EditorCoreSkiaHoverInfo(
                        charOffset: offset,
                        logicalLine: pos.line,
                        logicalColumn: pos.column,
                        windowPoint: windowPoint,
                        viewPoint: viewPoint,
                        viewBackingXPx: xPx,
                        viewBackingYPx: yPx,
                        documentLinkJSON: linkJSON ?? nil
                    )
                )
            }

            lastHoverModifierFlags = flags
            updateCommandHoverFeedbackIfNeeded(
                eventFlags: flags,
                hoverContext: ctx,
                documentLinkJSON: linkJSON ?? nil
            )
        } catch {
            // Hover is best-effort: never beep or disrupt input.
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)

        guard commandHoverLinkFeedbackEnabled else { return }
        guard let ctx = lastHoverContextForCommandHover else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdHover = flags.contains(.command) && flags.contains(.option) == false

        let linkJSON: String?
        if isCmdHover {
            // If the user toggles Cmd without moving the mouse, re-query link hit-test using the
            // last known hover point so cursor feedback stays responsive.
            linkJSON = (try? editor.documentLinkJSONAtViewPoint(xPx: ctx.viewBackingXPx, yPx: ctx.viewBackingYPx))
                ?? lastHoverDocumentLinkJSONForCommandHover
        } else {
            linkJSON = nil
        }

        updateCommandHoverFeedbackIfNeeded(
            eventFlags: flags,
            hoverContext: ctx,
            documentLinkJSON: linkJSON
        )
    }

    public override func mouseExited(with event: NSEvent) {
        clearCommandHoverFeedback()
        lastHoverModifierFlags = []
        lastHoverContextForCommandHover = nil
        lastHoverDocumentLinkJSONForCommandHover = nil
        if lastHoverCharOffset != nil {
            lastHoverCharOffset = nil
            onHoverExit?()
        }
        super.mouseExited(with: event)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let context = buildContextMenuContext(for: event)
        if let menu = contextMenuProvider?(context) {
            return menu
        }
        return defaultContextMenu(for: context)
    }

    public override func rightMouseDown(with event: NSEvent) {
        dismissHoverUIForUserAction()

        // Ensure we become first responder so standard actions (copy/cut/paste) go through our overrides.
        window?.makeFirstResponder(self)

        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    func buildContextMenuContext(for event: NSEvent) -> EditorCoreSkiaContextMenuContext {
        updateViewportIfNeeded()

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: windowPoint,
            view: self
        )

        let offset = (try? editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)) ?? 0
        let pos = (try? editor.charOffsetToLogicalPosition(offset: offset)) ?? (line: 0, column: 0)

        return EditorCoreSkiaContextMenuContext(
            charOffset: offset,
            logicalLine: pos.line,
            logicalColumn: pos.column,
            windowPoint: windowPoint,
            viewPoint: viewPoint,
            viewBackingXPx: xPx,
            viewBackingYPx: yPx
        )
    }

    func defaultContextMenu(for context: EditorCoreSkiaContextMenuContext) -> NSMenu {
        let menu = NSMenu(title: "Editor")
        menu.autoenablesItems = false

        let hasSelection: Bool
        do {
            let s = try editor.selectionOffsets()
            hasSelection = s.start != s.end
        } catch {
            hasSelection = false
        }

        let canPaste = pasteboard.string(forType: .string) != nil

        let cut = NSMenuItem(title: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        cut.target = self
        cut.isEnabled = hasSelection

        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = hasSelection

        let paste = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        paste.target = self
        paste.isEnabled = canPaste

        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAll.target = self
        selectAll.isEnabled = true

        menu.addItem(cut)
        menu.addItem(copy)
        menu.addItem(paste)
        menu.addItem(.separator())
        menu.addItem(selectAll)

        // Keep `context` referenced (future-proof: allow providers to attach representedObject via userInfo).
        _ = context
        return menu
    }

    public override func mouseDown(with event: NSEvent) {
        dismissHoverUIForUserAction()

        window?.makeFirstResponder(self)
        onDidBecomeFirstResponder?()
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: event.locationInWindow,
            view: self
        )
        debugLogInput(event, xPx: xPx, yPx: yPx, phase: "down", force: true)

        do {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+Click 依然保留给“文档链接 / go-to-definition”等 host 级 hook。
            // 但 Cmd+Option+Click 需要保留给 multi-cursor（避免与 cmd-click hook 冲突）。
            if flags.contains(.command), flags.contains(.option) == false {
                if event.clickCount == 1, performCodeLensClickIfPresent(xPx: xPx, yPx: yPx) {
                    return
                }

                if event.clickCount == 1, performInlayHintClickIfPresent(xPx: xPx, yPx: yPx) {
                    return
                }

                if event.clickCount == 1, openDocumentLinkIfPresent(xPx: xPx, yPx: yPx) {
                    return
                }

                if event.clickCount == 1, let onCommandClick {
                    let ctx = buildContextMenuContext(for: event)
                    if onCommandClick(ctx) {
                        return
                    }
                }

                // Cmd-click hook 未处理：退化成“普通点选/选择”。
                // 注意：这里刻意 strip `.command`，避免 Rust 的 mouse policy 把 Cmd 解释成 multi-cursor。
                let stripped = flags.subtracting(.command)
                let mods = Self.ecuMouseModifiers(from: stripped)
                try editor.mouseDownEx(
                    xPx: xPx,
                    yPx: yPx,
                    modifiers: mods,
                    clickCount: UInt32(max(1, event.clickCount))
                )
            } else {
                let mods = Self.ecuMouseModifiers(from: flags)
                try editor.mouseDownEx(
                    xPx: xPx,
                    yPx: yPx,
                    modifiers: mods,
                    clickCount: UInt32(max(1, event.clickCount))
                )
            }
        } catch {
            NSSound.beep()
        }
        notifySelectionDidChange(causedByTextMutation: false)
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    /// Try to open an LSP document link at the given view point (in backing pixels).
    ///
    /// Returns `true` when a link was found and opened.
    @discardableResult
    public func openDocumentLinkIfPresent(xPx: Float, yPx: Float) -> Bool {
        do {
            guard let json = try editor.documentLinkJSONAtViewPoint(xPx: xPx, yPx: yPx) else {
                return false
            }
            if let url = Self.documentLinkTargetURL(from: json) {
                onOpenURL(url)
                return true
            }
            return onDocumentLinkClick?(json) ?? false
        } catch {
            return false
        }
    }

    /// Try to resolve an LSP inlay hint at the given view point (in backing pixels).
    ///
    /// Returns `true` when an inlay hint was found and the host handled it.
    @discardableResult
    public func performInlayHintClickIfPresent(xPx: Float, yPx: Float) -> Bool {
        do {
            guard let json = try editor.inlayHintJSONAtViewPoint(xPx: xPx, yPx: yPx) else {
                return false
            }
            return onInlayHintClick?(json) ?? false
        } catch {
            return false
        }
    }

    /// Try to execute an LSP code lens at the given view point (in backing pixels).
    ///
    /// Returns `true` when a code lens was found and the host handled it.
    @discardableResult
    public func performCodeLensClickIfPresent(xPx: Float, yPx: Float) -> Bool {
        do {
            guard let json = try editor.codeLensJSONAtViewPoint(xPx: xPx, yPx: yPx) else {
                return false
            }
            return onCodeLensClick?(json) ?? false
        } catch {
            return false
        }
    }

    public static func documentLinkTargetURL(from json: String) -> URL? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let target = obj["target"] as? String, target.isEmpty == false else { return nil }

        return documentLinkTargetURL(fromTarget: target)
    }

    public static func documentLinkTargetURL(fromTarget target: String) -> URL? {
        // LSP `DocumentLink.target` is typically a URI string (file://, https://, ...).
        if let url = URL(string: target), url.scheme != nil {
            return url
        }
        // Fallback: treat it as a filesystem path.
        return URL(fileURLWithPath: target)
    }

    public override func mouseDragged(with event: NSEvent) {
        dismissHoverUIForUserAction()

        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: event.locationInWindow,
            view: self
        )
        debugLogInput(event, xPx: xPx, yPx: yPx, phase: "drag", force: false)
        do {
            try editor.mouseDragged(xPx: xPx, yPx: yPx)
        } catch {
            NSSound.beep()
        }
        notifySelectionDidChange(causedByTextMutation: false)
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    public override func mouseUp(with event: NSEvent) {
        dismissHoverUIForUserAction()

        editor.mouseUp()
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    static func ecuMouseModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        // Bit layout mirrors `editor_core_ui::Modifiers` (see `editor_core_ui_ffi.h`):
        // - bit0: shift
        // - bit1: ctrl
        // - bit2: alt/option
        // - bit3: meta/cmd
        var out: UInt32 = 0
        if flags.contains(.shift) { out |= 0b0001 }
        if flags.contains(.control) { out |= 0b0010 }
        if flags.contains(.option) { out |= 0b0100 }
        if flags.contains(.command) { out |= 0b1000 }
        return out
    }

    public override func scrollWheel(with event: NSEvent) {
        handleScroll(deltaYPoints: event.scrollingDeltaY, hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas)
    }

    // MARK: - Smooth scroll helper (testable)

    /// Smooth-scroll handler shared by `scrollWheel(with:)` and unit tests.
    ///
    /// - Parameters:
    ///   - deltaYPoints: For precise scrolling events, this is the point delta. For coarse scrolling
    ///     (mouse wheel), AppKit's delta is closer to “line units”.
    ///   - hasPreciseScrollingDeltas: Mirrors `NSEvent.hasPreciseScrollingDeltas`.
    func handleScroll(
        deltaYPoints: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) {
        dismissHoverUIForUserAction()

        // 平滑滚动：
        // - trackpad（hasPreciseScrollingDeltas == true）给出的是 point 级连续 delta
        // - 传统鼠标滚轮（hasPreciseScrollingDeltas == false）更接近“行数”delta
        //
        // UI 侧统一换算成“backing pixels”的 delta，再交给 Rust UI 层维护
        // `(scroll_top, sub_row_offset)`，并在渲染/hit-test 中使用子行偏移。
        var scale = window?.backingScaleFactor ?? (NSScreen.main?.backingScaleFactor ?? 1)
        scale = max(1, scale)

        var deltaPt = deltaYPoints
        if hasPreciseScrollingDeltas == false {
            // 注意：这里不能直接用 `convertToBacking/convertFromBacking` 来换算 delta，
            // 因为 `NSSize` 在语义上是“尺寸”，某些情况下系统可能会丢掉符号位（导致滚动方向错）。
            //
            // 我们使用明确的 `backingScaleFactor` 做乘除，确保 delta 的正负号稳定。
            let lineHeightPt = CGFloat(max(1, lineHeightPx)) / scale
            if lineHeightPt > 0 {
                deltaPt *= lineHeightPt
            }
        }

        let deltaPx = deltaPt * scale
        if deltaPx != 0 {
            // 约定：Rust `scrollByPixels` 的正值表示“向下滚动”（内容向上，显示更靠后的行）。
            // AppKit: scrollingDeltaY > 0 通常表示“向上滚动”（内容向下）。
            // 我们约定 Rust `scrollByPixels` 的正值表示“向下滚动”（内容向上），因此取负号。
            editor.scrollByPixels(Float(-deltaPx))
            requestRedraw()
            invalidateIMECharacterCoordinates()
            notifyViewportStateDidChange()
        }
    }
}
