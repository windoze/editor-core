import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP completion

    @discardableResult
    func showCompletionsInActiveTab() -> Bool {
        showCompletionsInActiveTab(beepOnFailure: true, showFeedback: true)
    }

    @discardableResult
    func showCompletionsInActiveTab(beepOnFailure: Bool, showFeedback: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.completion), in: tab.editCore.editorView)
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let context = try completionRequestContextForCurrentSelection(
                tab,
                beepOnFailure: beepOnFailure,
                showFeedback: showFeedback
            )
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestCompletion(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )

            completionContext = context
            startCompletionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.completion, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }
    }

    func completionRequestContextForCurrentSelection(
        _ tab: AttoEditorTab,
        beepOnFailure: Bool = false,
        showFeedback: Bool = false
    ) throws -> CompletionRequestContext {
        let offsets = try tab.editCore.editor.selectionOffsets()
        let text = try tab.editCore.editor.text()
        let fallback: (start: UInt32, end: UInt32) = {
            let start = min(offsets.start, offsets.end)
            let end = max(offsets.start, offsets.end)
            if start != end {
                return (start, end)
            }
            return AttoLspCompletionParser.identifierFallbackRange(in: text, caretOffset: offsets.end)
        }()
        return CompletionRequestContext(
            tabID: tab.id,
            fallbackStart: fallback.start,
            fallbackEnd: fallback.end,
            beepOnFailure: beepOnFailure,
            showFeedback: showFeedback
        )
    }

    func startCompletionPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        completionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.completionContext, ctx.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                if ctx.showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.completion), in: editorView)
                }
                self.cancelCompletionUI()
                if ctx.beepOnFailure {
                    NSSound.beep()
                }
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let result: EcuLspCompletionResult?
            do {
                result = try tab.editCore.editor.lspTakeLastCompletionResult()
            } catch {
                if ctx.showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.completion, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                self.cancelCompletionUI()
                if ctx.beepOnFailure {
                    NSSound.beep()
                }
                return
            }
            guard let result else { return }

            let items = AttoLspCompletionParser.items(fromCompletionResult: result)
            self.completionPollTimer?.cancel()
            self.completionPollTimer = nil
            self.completionContext = nil
            _ = self.showCompletionList(items: items, context: ctx, editorView: editorView)
            timer.cancel()
        }

        completionPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showCompletionList(
        items: [AttoLspCompletionParser.Item],
        context: CompletionRequestContext,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        guard items.isEmpty == false else {
            cancelCompletionUI()
            if context.showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.completion), in: editorView)
            }
            if context.beepOnFailure { NSSound.beep() }
            return false
        }
        recordCompletionResultLifecycle(items: items)
        guard editorView.window != nil else { return false }

        let controller = AttoCompletionListController()
        completionListController = controller
        completionListContext = context
        controller.onTextInput = { [weak self, weak controller] text in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterTextInput(text, tabID: context.tabID)
        }
        controller.onDeleteBackward = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterDeleteBackward(tabID: context.tabID)
        }
        controller.onDismiss = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return }
            self.completionListController = nil
            self.completionListContext = nil
        }
        controller.show(
            items: items,
            relativeTo: editorView,
            anchorRect: caretAnchorRect(in: editorView)
        ) { [weak self] item, commitCharacter in
            self?.applyCompletion(item, context: context, commitCharacter: commitCharacter)
        }
        return true
    }

    func recordCompletionResultLifecycle(items: [AttoLspCompletionParser.Item]) {
        lspResultEventStream.record(
            family: "completion",
            title: items.count == 1 ? "Completion: 1 item" : "Completion: \(items.count) items",
            payload: .completion(itemCount: items.count)
        )
    }

    @discardableResult
    func handleCompletionFilterTextInput(_ text: String, tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    @discardableResult
    func handleCompletionFilterDeleteBackward(tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    func refreshCompletionFilter(tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID,
              let context = completionListContext,
              let controller = completionListController
        else {
            return
        }

        guard let prefix = completionFilterPrefix(context: context, editor: tab.editCore.editor) else {
            cancelCompletionUI()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return
        }

        if controller.updateFilter(
            prefix: prefix,
            relativeTo: tab.editCore.editorView,
            anchorRect: caretAnchorRect(in: tab.editCore.editorView)
        ) == false {
            view.window?.makeFirstResponder(tab.editCore.editorView)
        }
    }

    func completionFilterPrefix(context: CompletionRequestContext, editor: EditorUI) -> String? {
        guard let offsets = try? editor.selectionOffsets() else { return nil }
        guard offsets.start == offsets.end else { return nil }
        guard offsets.end >= context.fallbackStart else { return nil }
        guard let text = try? editor.text() else { return nil }
        return AttoLspCompletionParser.completionPrefix(
            in: text,
            start: context.fallbackStart,
            caretOffset: offsets.end
        )
    }

    func applyCompletion(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil
    ) {
        guard let tab = activeTab, tab.id == context.tabID else { return }

        guard completionItemResolveSupported(for: tab.editCore.editor) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        guard let itemJSON = AttoLspCompletionParser.rawJSON(for: item) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        do {
            _ = try tab.editCore.editor.lspRequestCompletionItemResolve(itemJSON: itemJSON)
            completionResolveContext = CompletionResolveContext(
                request: context,
                item: item,
                commitCharacter: commitCharacter
            )
            completionListController?.hide()
            completionListController = nil
            startCompletionResolvePollTimer(tabID: tab.id)
        } catch {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
        }
    }

    func completionItemResolveSupported(for editor: EditorUI) -> Bool {
        guard let status = try? editor.lspStatusSnapshot() else { return true }
        return status.capabilities?.completionItemResolve ?? true
    }

    func startCompletionResolvePollTimer(tabID: UUID) {
        completionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.completionResolveContext, ctx.request.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                self.finishCompletionResolve(
                    with: ctx.item,
                    fallback: ctx.item,
                    context: ctx.request,
                    commitCharacter: ctx.commitCharacter,
                    timer: timer
                )
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let result: EcuLspCompletionItem?
            do {
                result = try tab.editCore.editor.lspTakeLastCompletionItemResolveResult()
            } catch {
                return
            }
            guard let result else { return }

            let resolved = AttoLspCompletionParser.item(fromCompletionItem: result) ?? ctx.item
            self.finishCompletionResolve(
                with: resolved,
                fallback: ctx.item,
                context: ctx.request,
                commitCharacter: ctx.commitCharacter,
                timer: timer
            )
        }

        completionResolvePollTimer = timer
        timer.resume()
    }

    func finishCompletionResolve(
        with item: AttoLspCompletionParser.Item,
        fallback: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String?,
        timer: DispatchSourceTimer
    ) {
        completionResolvePollTimer = nil
        completionResolveContext = nil
        timer.cancel()

        if applyCompletionItem(
            item,
            context: context,
            commitCharacter: commitCharacter,
            beepOnFailure: false
        ) == false {
            _ = applyCompletionItem(
                fallback,
                context: context,
                commitCharacter: commitCharacter,
                beepOnFailure: true
            )
        }
    }

    @discardableResult
    func applyCompletionItem(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard let tab = activeTab, tab.id == context.tabID else { return false }

        do {
            let text = try tab.editCore.editor.text()
            guard let plan = AttoLspCompletionParser.applicationPlan(
                for: item,
                documentText: text,
                fallbackStart: context.fallbackStart,
                fallbackEnd: context.fallbackEnd
            ) else {
                if beepOnFailure {
                    NSSound.beep()
                }
                return false
            }

            if plan.isSnippet {
                _ = try tab.editCore.editor.applySnippet(
                    start: plan.start,
                    end: plan.end,
                    snippet: plan.text,
                    additionalEdits: plan.additionalEdits
                )
            } else {
                let edits = [EcuTextEdit(start: plan.start, end: plan.end, text: plan.text)] + plan.additionalEdits
                _ = try tab.editCore.editor.applyTextEdits(edits)
            }
            var didCommitCharacter = false
            if let commitCharacter {
                do {
                    try tab.editCore.editor.commitText(commitCharacter)
                    didCommitCharacter = true
                } catch {
                    if beepOnFailure {
                        NSSound.beep()
                    }
                }
            }

            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            if let commitCharacter, didCommitCharacter {
                handleCommittedTextForLspTriggers(commitCharacter, tabID: tab.id)
            }
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
    }
}
