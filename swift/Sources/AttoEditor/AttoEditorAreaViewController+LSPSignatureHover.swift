import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP signature help

    func handleCommittedTextForLspTriggers(_ text: String, tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID else { return }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        guard let status = try? tab.editCore.editor.lspStatusSnapshot() else { return }
        let shouldShowSignatureHelp = AttoLspSignatureHelpTrigger.shouldTrigger(
            committedText: text,
            lspStatus: status
        )

        if AttoLspCompletionTrigger.shouldTrigger(
            committedText: text,
            lspStatus: status
        ), shouldShowSignatureHelp == false {
            _ = showCompletionsInActiveTab(beepOnFailure: false, showFeedback: false)
        }

        if shouldShowSignatureHelp {
            _ = showSignatureHelpInActiveTab(beepOnFailure: false, showEmptyResults: false)
        }
    }

    @discardableResult
    func showSignatureHelpInActiveTab() -> Bool {
        showSignatureHelpInActiveTab(beepOnFailure: true, showEmptyResults: true)
    }

    @discardableResult
    func showSignatureHelpInActiveTab(beepOnFailure: Bool, showEmptyResults: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showEmptyResults {
                showSignatureHelpFeedback(
                    AttoLspResultFeedback.unavailable(.signatureHelp),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestSignatureHelp(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
        } catch {
            if showEmptyResults {
                showSignatureHelpFeedback(
                    AttoLspResultFeedback.requestFailed(.signatureHelp, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        signatureHelpContext = SignatureHelpRequestContext(
            tabID: tab.id,
            showEmptyResults: showEmptyResults
        )
        startSignatureHelpPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    func startSignatureHelpPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        signatureHelpPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.signatureHelpContext, ctx.tabID == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            if remainingTicks <= 0 {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpFeedback(
                        AttoLspResultFeedback.timeout(.signatureHelp),
                        in: editorView
                    )
                }
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            let result: EcuLspSignatureHelpResult?
            do {
                result = try tab.editCore.editor.lspTakeLastSignatureHelpResult()
            } catch {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpFeedback(
                        AttoLspResultFeedback.failed(.signatureHelp, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                timer.cancel()
                return
            }
            guard let result else { return }

            let display = AttoLspSignatureHelpFormatter.display(from: result)
            let showEmptyResults = ctx.showEmptyResults
            self.cancelSignatureHelpUI()
            if let display {
                self.showSignatureHelpPopover(display: display, in: editorView)
            } else if showEmptyResults {
                self.showSignatureHelpFeedback(
                    AttoLspResultFeedback.empty(.signatureHelp),
                    in: editorView
                )
            }
            timer.cancel()
        }

        signatureHelpPollTimer = timer
        timer.resume()
    }

    func showSignatureHelpFeedback(
        _ message: AttoLspResultFeedback.Message,
        in editorView: EditorCoreSkiaView
    ) {
        setTransientStatusText(message.statusText)
        showSignatureHelpPopover(
            display: AttoLspSignatureHelpFormatter.messageDisplay(message.detailText),
            in: editorView
        )
    }

    func showSignatureHelpPopover(display: AttoLspSignatureHelpFormatter.Display?, in editorView: EditorCoreSkiaView) {
        guard let display else {
            cancelSignatureHelpUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = signatureHelpPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            signatureHelpPopover = p
            signatureHelpPopoverLabel = label
            popover = p
        }

        signatureHelpPopoverLabel?.attributedStringValue = attributedSignatureHelp(display)
        popover.contentSize = preferredHoverPopoverSize(text: display.text, font: signatureHelpPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    func attributedSignatureHelp(_ display: AttoLspSignatureHelpFormatter.Display) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let activeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attributed = NSMutableAttributedString(
            string: display.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let fullRange = NSRange(location: 0, length: (display.text as NSString).length)
        let highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.24)

        for range in display.activeParameterRanges where NSIntersectionRange(range, fullRange).length == range.length {
            attributed.addAttributes(
                [
                    .font: activeFont,
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: highlightColor,
                ],
                range: range
            )
        }
        return attributed
    }

    func caretAnchorRect(in editorView: EditorCoreSkiaView) -> NSRect {
        do {
            let offsets = try editorView.editor.selectionOffsets()
            let pt = try editorView.editor.charOffsetToViewPoint(offset: offsets.end)

            let boundsSize = editorView.bounds.size
            let backingSize = editorView.convertToBacking(boundsSize)
            let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 1
            let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 1

            let xPt = CGFloat(pt.xPx) / max(1e-6, sx)
            let yPt = CGFloat(pt.yPx) / max(1e-6, sy)
            let hPt = max(1, CGFloat(pt.lineHeightPx) / max(1e-6, sy))
            return NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        } catch {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    // MARK: - LSP hover tooltip (AttoEditor UX)

    func handleHover(info: EditorCoreSkiaHoverInfo, tabID: UUID) {
        guard activeTab?.id == tabID else { return }
        guard let tab = activeTab else { return }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            cancelHoverUI()
            return
        }

        hoverContext = HoverRequestContext(tabID: tabID, info: info)
        hoverDebounceWorkItem?.cancel()
        hoverPollTimer?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.requestHoverForCurrentContext()
        }
        hoverDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func handleHoverExit(tabID: UUID) {
        guard hoverContext?.tabID == tabID else { return }
        cancelHoverUI()
    }

    func requestHoverForCurrentContext() {
        guard let ctx = hoverContext else { return }
        guard activeTab?.id == ctx.tabID else { return }
        guard let tab = activeTab else { return }

        do {
            _ = try tab.editCore.editor.lspRequestHover(
                logicalLine: ctx.info.logicalLine,
                logicalColumn: ctx.info.logicalColumn
            )
        } catch {
            return
        }

        startHoverPollTimer(tabID: ctx.tabID, editorView: tab.editCore.editorView)
    }

    func startHoverPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        hoverPollTimer?.cancel()

        var remainingTicks = 30 // ~1.5s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.hoverContext, ctx.tabID == tabID else {
                self.cancelHoverUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelHoverUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHoverUI()
                return
            }

            let result: EcuLspHoverResult?
            do {
                result = try tab.editCore.editor.lspTakeLastHoverResult()
            } catch {
                return
            }
            guard let result else { return }

            let text = AttoLspHoverFormatter.displayText(fromHoverResult: result)
            self.showHoverPopover(text: text, at: ctx.info, in: editorView)
            timer.cancel()
        }

        hoverPollTimer = timer
        timer.resume()
    }

    func showHoverPopover(text: String?, at info: EditorCoreSkiaHoverInfo, in editorView: EditorCoreSkiaView) {
        guard let text else {
            cancelHoverUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = hoverPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            hoverPopover = p
            hoverPopoverLabel = label
            popover = p
        }

        hoverPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: hoverPopoverLabel?.font)

        let rect = NSRect(x: info.viewPoint.x, y: info.viewPoint.y, width: 1, height: 1)
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: rect, of: editorView, preferredEdge: .maxY)
    }

    func presentLspFailureDetailIfNeeded(_ detail: String, editorView: EditorCoreSkiaView) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard editorView.window != nil else { return }
        guard lastPresentedLspFailureDetail != trimmed else { return }
        lastPresentedLspFailureDetail = trimmed
        NSLog("AttoEditor: LSP status failed: %@", trimmed)
        showWorkspaceEditPopover(text: "LSP failed.\n\(trimmed)", in: editorView)
    }

    func presentLspResultFeedback(
        _ message: AttoLspResultFeedback.Message,
        in editorView: EditorCoreSkiaView
    ) {
        setTransientStatusText(message.statusText)
        showWorkspaceEditPopover(text: message.detailText, in: editorView)
    }

    func showWorkspaceEditPopover(text: String, in editorView: EditorCoreSkiaView) {
        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = workspaceEditPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            workspaceEditPopover = p
            workspaceEditPopoverLabel = label
            popover = p
        }

        workspaceEditPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: workspaceEditPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    func preferredHoverPopoverSize(text: String, font: NSFont?) -> NSSize {
        let maxWidth: CGFloat = 420
        let maxHeight: CGFloat = 260
        let padW: CGFloat = 20
        let padH: CGFloat = 16

        let f = font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: max(1, maxWidth - padW), height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let h = min(maxHeight, ceil(bounds.height) + padH)
        return NSSize(width: maxWidth, height: max(44, h))
    }

    func cancelHoverUI() {
        hoverDebounceWorkItem?.cancel()
        hoverDebounceWorkItem = nil

        hoverPollTimer?.cancel()
        hoverPollTimer = nil

        hoverContext = nil

        hoverPopover?.performClose(nil)
    }

    func cancelDefinitionUI() {
        definitionPollTimer?.cancel()
        definitionPollTimer = nil
        definitionContext = nil
        lspLocationResultsController?.hide()
        lspLocationResultsController = nil
    }

    func cancelSymbolUI() {
        symbolPollTimer?.cancel()
        symbolPollTimer = nil
        symbolContext = nil
        cancelWorkspaceSymbolSearchRequestOnly()
        lspSymbolResultsController?.hide()
        lspSymbolResultsController = nil
        cancelProblemsUI()
        cancelWorkspaceDiagnosticsUI()
    }

    func cancelWorkspaceSymbolSearchRequestOnly() {
        workspaceSymbolSearchDebounceTimer?.cancel()
        workspaceSymbolSearchDebounceTimer = nil

        workspaceSymbolSearchPollTimer?.cancel()
        workspaceSymbolSearchPollTimer = nil

        workspaceSymbolSearchContext = nil
        workspaceSymbolSearchResults = []
    }

    func cancelHierarchyUI() {
        hierarchyPreparePollTimer?.cancel()
        hierarchyPreparePollTimer = nil
        hierarchyPrepareContext = nil

        hierarchyChildrenPollTimer?.cancel()
        hierarchyChildrenPollTimer = nil
        hierarchyChildrenContext = nil

        hierarchyResultsController?.hide()
        hierarchyResultsController = nil
    }

    func cancelProblemsUI() {
        problemsResultsController?.hide()
        problemsResultsController = nil
    }

    func cancelWorkspaceDiagnosticsUI() {
        workspaceDiagnosticsPollTimer?.cancel()
        workspaceDiagnosticsPollTimer = nil
        workspaceDiagnosticsContext = nil
        workspaceDiagnosticsResultsController?.hide()
        workspaceDiagnosticsResultsController = nil
    }

    func cancelSignatureHelpUI() {
        signatureHelpPollTimer?.cancel()
        signatureHelpPollTimer = nil
        signatureHelpContext = nil
        signatureHelpPopover?.performClose(nil)
    }

    func cancelCompletionUI() {
        completionPollTimer?.cancel()
        completionPollTimer = nil
        completionContext = nil

        completionResolvePollTimer?.cancel()
        completionResolvePollTimer = nil
        completionResolveContext = nil

        completionListController?.hide()
        completionListController = nil
        completionListContext = nil
    }

    func cancelRenameUI() {
        cancelRenamePrepareUI()
        renamePollTimer?.cancel()
        renamePollTimer = nil
        renameContext = nil
    }

    func cancelRenamePrepareUI() {
        renamePreparePollTimer?.cancel()
        renamePreparePollTimer = nil
        renamePrepareContext = nil
    }

    func cancelCodeActionUI() {
        codeActionPollTimer?.cancel()
        codeActionPollTimer = nil
        codeActionContext = nil

        codeActionResolvePollTimer?.cancel()
        codeActionResolvePollTimer = nil
        codeActionResolveContext = nil

        codeActionResultsController?.hide()
        codeActionResultsController = nil

        cancelCodeLensUI()
        cancelAuxiliaryRefreshUI()
        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()
        cancelExecuteCommandUI()
    }

    func cancelCodeLensUI() {
        codeLensResolvePollTimer?.cancel()
        codeLensResolvePollTimer = nil
        codeLensResolveContext = nil

        codeLensRefreshPollTimer?.cancel()
        codeLensRefreshPollTimer = nil
        codeLensRefreshContext = nil

        codeLensResultsController?.hide()
        codeLensResultsController = nil
    }

    func cancelAuxiliaryRefreshUI() {
        auxiliaryRefreshPollTimer?.cancel()
        auxiliaryRefreshPollTimer = nil
        auxiliaryRefreshContext = nil
    }

    func cancelInlayHintResolveUI() {
        inlayHintResolvePollTimer?.cancel()
        inlayHintResolvePollTimer = nil
        inlayHintResolveContext = nil
    }

    func cancelDocumentLinkResolveUI() {
        documentLinkResolvePollTimer?.cancel()
        documentLinkResolvePollTimer = nil
        documentLinkResolveContext = nil
    }

    func cancelExecuteCommandUI() {
        executeCommandPollTimer?.cancel()
        executeCommandPollTimer = nil
        executeCommandContext = nil
    }

    func cancelFoldingRangesUI() {
        foldingRangesPollTimer?.cancel()
        foldingRangesPollTimer = nil
        foldingRangesContext = nil
    }

    func cancelSelectionRangeUI() {
        selectionRangePollTimer?.cancel()
        selectionRangePollTimer = nil
        selectionRangeContext = nil
    }

    func cancelLinkedEditingUI() {
        linkedEditingPollTimer?.cancel()
        linkedEditingPollTimer = nil
        linkedEditingContext = nil
        linkedEditingSession = nil
    }

    func cancelDocumentColorUI() {
        cancelDocumentColorRequestOnly()
        documentColorPanelContext = nil
        documentColorResultsController?.hide()
        documentColorResultsController = nil
        cancelColorPresentationUI()
    }

    func cancelDocumentColorRequestOnly() {
        documentColorPollTimer?.cancel()
        documentColorPollTimer = nil
        documentColorContext = nil
    }

    func cancelColorPresentationUI() {
        cancelColorPresentationRequestOnly()
        colorPresentationResultsController?.hide()
        colorPresentationResultsController = nil
    }

    func cancelColorPresentationRequestOnly() {
        colorPresentationPollTimer?.cancel()
        colorPresentationPollTimer = nil
        colorPresentationContext = nil
    }
}
