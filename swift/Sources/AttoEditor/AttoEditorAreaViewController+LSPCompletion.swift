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
            _ = try tab.editCore.editor.lspRequestCompletion(
                logicalLine: context.logicalLine,
                logicalColumn: context.logicalColumn
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
        let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
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
            logicalLine: position.line,
            logicalColumn: position.column,
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
                if let outcome = applySnippetCompletionAdditionalEditsWithWorkspaceEdit(
                    plan,
                    documentText: text,
                    tab: tab,
                    context: context
                ) {
                    switch outcome {
                    case let .applied(start, end):
                        _ = try tab.editCore.editor.applySnippet(
                            start: start,
                            end: end,
                            snippet: plan.text
                        )
                    case .requestRerunStarted:
                        return true
                    case .stopped:
                        if beepOnFailure {
                            NSSound.beep()
                        }
                        return false
                    }
                } else {
                    _ = try tab.editCore.editor.applySnippet(
                        start: plan.start,
                        end: plan.end,
                        snippet: plan.text,
                        additionalEdits: plan.additionalEdits
                    )
                }
            } else {
                if let outcome = applyCompletionPlanWithWorkspaceEdit(
                    plan,
                    documentText: text,
                    tab: tab,
                    context: context
                ) {
                    switch outcome {
                    case .applied:
                        break
                    case .requestRerunStarted:
                        return true
                    case .stopped:
                        if beepOnFailure {
                            NSSound.beep()
                        }
                        return false
                    }
                } else {
                    let edits = [EcuTextEdit(start: plan.start, end: plan.end, text: plan.text)] + plan.additionalEdits
                    _ = try tab.editCore.editor.applyTextEdits(edits)
                }
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

    enum CompletionSnippetAdditionalEditsOutcome {
        case applied(start: UInt32, end: UInt32)
        case requestRerunStarted
        case stopped
    }

    func applySnippetCompletionAdditionalEditsWithWorkspaceEdit(
        _ plan: AttoLspCompletionParser.ApplicationPlan,
        documentText: String,
        tab: AttoEditorTab,
        context: CompletionRequestContext
    ) -> CompletionSnippetAdditionalEditsOutcome? {
        guard plan.additionalEdits.isEmpty == false else { return nil }
        guard let transformedRange = completionSnippetRangeAfterApplyingAdditionalEdits(
            start: plan.start,
            end: plan.end,
            additionalEdits: plan.additionalEdits
        ) else {
            return nil
        }

        let documentURI = projectedFileURL(for: tab).absoluteString
        guard let workspaceEditJSON = completionWorkspaceEditJSON(
            edits: plan.additionalEdits,
            documentText: documentText,
            documentURI: documentURI
        ) else {
            return nil
        }
        guard let parsed = AttoWorkspaceEditParser.parse(workspaceEditJSON) else {
            return nil
        }

        let outcome = applyWorkspaceEditToActiveTab(
            parsed,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI,
            requestRetryOwner: completionWorkspaceEditRequestRetryOwner(context: context)
        )
        switch outcome {
        case .applied:
            return .applied(start: transformedRange.start, end: transformedRange.end)
        case .requestRerunStarted:
            return .requestRerunStarted
        case .stopped:
            return .stopped
        }
    }

    func completionSnippetRangeAfterApplyingAdditionalEdits(
        start: UInt32,
        end: UInt32,
        additionalEdits: [EcuTextEdit]
    ) -> (start: UInt32, end: UInt32)? {
        guard start <= end else { return nil }
        let sortedEdits = additionalEdits.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }

        var previousEnd: UInt32 = 0
        var deltaBeforeSnippet: Int64 = 0
        for edit in sortedEdits {
            guard edit.start <= edit.end else { return nil }
            guard edit.start >= previousEnd else { return nil }
            previousEnd = max(previousEnd, edit.end)

            let isBeforeSnippet = edit.end <= start
            let isAfterSnippet = edit.start >= end
            guard isBeforeSnippet || isAfterSnippet else { return nil }

            if isBeforeSnippet {
                deltaBeforeSnippet += Int64(edit.text.unicodeScalars.count) - Int64(edit.end - edit.start)
            }
        }

        let transformedStart = Int64(start) + deltaBeforeSnippet
        let transformedEnd = Int64(end) + deltaBeforeSnippet
        guard transformedStart >= 0,
              transformedEnd >= transformedStart,
              transformedStart <= Int64(UInt32.max),
              transformedEnd <= Int64(UInt32.max)
        else {
            return nil
        }
        return (start: UInt32(transformedStart), end: UInt32(transformedEnd))
    }

    func applyCompletionPlanWithWorkspaceEdit(
        _ plan: AttoLspCompletionParser.ApplicationPlan,
        documentText: String,
        tab: AttoEditorTab,
        context: CompletionRequestContext
    ) -> AttoWorkspaceEditApplyOutcome? {
        let documentURI = projectedFileURL(for: tab).absoluteString
        guard let workspaceEditJSON = completionWorkspaceEditJSON(
            for: plan,
            documentText: documentText,
            documentURI: documentURI
        ) else {
            return nil
        }
        guard let parsed = AttoWorkspaceEditParser.parse(workspaceEditJSON) else {
            return nil
        }

        return applyWorkspaceEditToActiveTab(
            parsed,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI,
            requestRetryOwner: completionWorkspaceEditRequestRetryOwner(context: context)
        )
    }

    func completionWorkspaceEditJSON(
        for plan: AttoLspCompletionParser.ApplicationPlan,
        documentText: String,
        documentURI: String
    ) -> String? {
        let edits = [EcuTextEdit(start: plan.start, end: plan.end, text: plan.text)] + plan.additionalEdits
        return completionWorkspaceEditJSON(
            edits: edits,
            documentText: documentText,
            documentURI: documentURI
        )
    }

    func completionWorkspaceEditJSON(
        edits: [EcuTextEdit],
        documentText: String,
        documentURI: String
    ) -> String? {
        let editObjects = edits.compactMap {
            completionTextEditObject($0, documentText: documentText)
        }
        guard editObjects.count == edits.count else { return nil }

        let root: [String: Any] = [
            "changes": [
                documentURI: editObjects,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func completionTextEditObject(_ edit: EcuTextEdit, documentText: String) -> [String: Any]? {
        guard edit.start <= edit.end,
              Int(edit.end) <= documentText.unicodeScalars.count
        else {
            return nil
        }

        return [
            "range": [
                "start": completionLspPosition(in: documentText, charOffset: edit.start),
                "end": completionLspPosition(in: documentText, charOffset: edit.end),
            ],
            "newText": edit.text,
        ]
    }

    func completionLspPosition(in text: String, charOffset: UInt32) -> [String: Int] {
        let limit = min(Int(charOffset), text.unicodeScalars.count)
        var line = 0
        var utf16Column = 0

        for scalar in text.unicodeScalars.prefix(limit) {
            if scalar == "\n" {
                line += 1
                utf16Column = 0
            } else {
                utf16Column += String(scalar).utf16.count
            }
        }

        return ["line": line, "character": utf16Column]
    }
}
