import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Editor commands

    @discardableResult
    func executeActiveEditorCommandJSON(_ commandJSON: String, treatsAsTextMutation: Bool? = nil) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let isTextMutation = treatsAsTextMutation ?? Self.commandJSONIsTextMutation(commandJSON)
        let mayChangeSelection = Self.commandJSONMayChangeSelection(commandJSON)

        do {
            _ = try tab.editCore.editor.executeCommandJSON(commandJSON)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true

            if isTextMutation {
                handleTabDidMutateDocumentText(tabID: tab.id)
            } else if mayChangeSelection {
                handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            }

            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applySnippetInActiveTab(_ snippet: String) -> Bool {
        guard snippet.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let selections = try tab.editCore.editor.selections()
            guard selections.ranges.isEmpty == false else {
                NSSound.beep()
                return false
            }

            let requestedPrimaryIndex = Int(selections.primaryIndex)
            let primaryIndex = min(requestedPrimaryIndex, selections.ranges.count - 1)
            let range = selections.ranges[primaryIndex]
            _ = try tab.editCore.editor.applySnippet(start: range.start, end: range.end, snippet: snippet)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func promptApplySnippetInActiveTab(initialSnippet: String = "") -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = initialSnippet
        field.placeholderString = "println!(${1:msg})$0"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Apply Snippet"
        alert.informativeText = "Enter an editor-core snippet string using $0 and ${1:name} placeholders."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return applySnippetInActiveTab(field.stringValue)
    }

    @discardableResult
    func addNextOccurrenceInActiveTab() -> Bool {
        addOccurrenceInActiveTab(selectAll: false)
    }

    @discardableResult
    func addAllOccurrencesInActiveTab() -> Bool {
        addOccurrenceInActiveTab(selectAll: true)
    }

    @discardableResult
    func addOccurrenceInActiveTab(selectAll: Bool) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            if selectAll {
                try tab.editCore.editor.addAllOccurrences(options: currentSearchOptions())
            } else {
                try tab.editCore.editor.addNextOccurrence(options: currentSearchOptions())
            }
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func performCursorMovementCommand(_ command: CursorMovementCommand) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            tab.editCore.layoutSubtreeIfNeeded()
            try Self.applyCursorMovementCommand(command, editor: tab.editCore.editor)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            tab.editCore.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: cursor movement command failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func performCursorMovementCommand(id commandID: String) -> Bool {
        guard let command = CursorMovementCommand(rawValue: commandID) else {
            NSSound.beep()
            return false
        }
        return performCursorMovementCommand(command)
    }

    static func applyCursorMovementCommand(_ command: CursorMovementCommand, editor: EditorUI) throws {
        switch command {
        case .moveLeft:
            if try collapseSelection(editor, to: .start) == false {
                try editor.moveGraphemeLeft()
            }
        case .moveRight:
            if try collapseSelection(editor, to: .end) == false {
                try editor.moveGraphemeRight()
            }
        case .moveWordLeft:
            _ = try collapseSelection(editor, to: .start)
            try editor.moveWordLeft()
        case .moveWordRight:
            _ = try collapseSelection(editor, to: .end)
            try editor.moveWordRight()
        case .moveUp:
            try editor.moveVisualByRows(-1)
        case .moveDown:
            try editor.moveVisualByRows(1)
        case .pageUp:
            try editor.moveVisualByPages(-1)
        case .pageDown:
            try editor.moveVisualByPages(1)
        case .lineStart:
            try editor.moveToVisualLineStart()
        case .lineEnd:
            try editor.moveToVisualLineEnd()
        case .documentStart:
            try editor.moveToDocumentStart()
        case .documentEnd:
            try editor.moveToDocumentEnd()
        case .selectLeft:
            try editor.moveGraphemeLeftAndModifySelection()
        case .selectRight:
            try editor.moveGraphemeRightAndModifySelection()
        case .selectWordLeft:
            try editor.moveWordLeftAndModifySelection()
        case .selectWordRight:
            try editor.moveWordRightAndModifySelection()
        case .selectUp:
            try editor.moveVisualByRowsAndModifySelection(-1)
        case .selectDown:
            try editor.moveVisualByRowsAndModifySelection(1)
        case .selectPageUp:
            try editor.moveVisualByPagesAndModifySelection(-1)
        case .selectPageDown:
            try editor.moveVisualByPagesAndModifySelection(1)
        case .selectLineStart:
            try editor.moveToVisualLineStartAndModifySelection()
        case .selectLineEnd:
            try editor.moveToVisualLineEndAndModifySelection()
        case .selectDocumentStart:
            try editor.moveToDocumentStartAndModifySelection()
        case .selectDocumentEnd:
            try editor.moveToDocumentEndAndModifySelection()
        }
    }

    enum SelectionCollapseEdge {
        case start
        case end
    }

    static func collapseSelection(_ editor: EditorUI, to edge: SelectionCollapseEdge) throws -> Bool {
        let offsets = try editor.selectionOffsets()
        guard offsets.start != offsets.end else { return false }

        let target = edge == .start ? offsets.start : offsets.end
        try editor.setSelections([EcuSelectionRange(start: target, end: target)], primaryIndex: 0)
        return true
    }

    @discardableResult
    func toggleLineCommentInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return executeActiveEditorCommandObject([
            "kind": "edit",
            "op": "toggle_comment",
            "config": AttoLanguageConfiguration.commentConfig(
                fileURL: projectedFileURL(for: tab),
                syntaxLanguageId: tab.syntaxLanguageId,
                preferences: preferences
            ).jsonObject,
        ])
    }

    @discardableResult
    func foldSelectionInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            let effectiveEndOffset = endOffset > startOffset ? endOffset - 1 : endOffset
            let start = try tab.editCore.editor.charOffsetToLogicalPosition(offset: startOffset)
            let end = try tab.editCore.editor.charOffsetToLogicalPosition(offset: effectiveEndOffset)

            guard end.line > start.line else {
                NSSound.beep()
                return false
            }

            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"fold","start_line":\#(start.line),"end_line":\#(end.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAtCursorInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"unfold","start_line":\#(pos.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAllInActiveTab() -> Bool {
        executeActiveEditorCommandJSON(
            #"{"kind":"style","op":"unfold_all"}"#,
            treatsAsTextMutation: false
        )
    }

    @discardableResult
    func refreshFoldingRangesInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.foldingRanges), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()

        if let status = try? tab.editCore.editor.lspStatusSnapshot(),
           AttoLspFoldingRangesSupport.availability(status: status) == .unsupported {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: AttoLspFoldingRangesSupport.unsupportedMessage,
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestFoldingRanges()
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.foldingRanges, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        foldingRangesContext = FoldingRangesRequestContext(tabID: tab.id, showFeedback: showFeedback)
        startFoldingRangesPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applyFoldingRangesResultJSONToActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let result = try JSONDecoder().decode(EcuLspFoldingRangeResult.self, from: Data(json.utf8))
            return applyFoldingRangesResultToActiveTab(result, showFeedback: showFeedback)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.foldingRanges, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyFoldingRangesResultToActiveTab(
        _ result: EcuLspFoldingRangeResult,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            try tab.editCore.editor.lspApplyFoldingRanges(result)
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            updateStatusBar()

            if showFeedback, result.ranges.isEmpty {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.foldingRanges), in: tab.editCore.editorView)
            }
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.foldingRanges, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applySemanticTokensResultToActiveTab(
        _ result: EcuLspSemanticTokensResult,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let data = try tab.editCore.editor.lspApplySemanticTokens(
                result,
                baseline: tab.semanticTokensData
            )
            tab.semanticTokensData = data
            tab.semanticTokensResultId = result.resultId
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            updateStatusBar()

            if showFeedback, result.isEmpty {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.semanticTokens), in: tab.editCore.editorView)
            }
            return true
        } catch {
            tab.semanticTokensData = []
            tab.semanticTokensResultId = nil
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.semanticTokens, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func startFoldingRangesPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        foldingRangesPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.foldingRangesContext, ctx.tabID == tabID else {
                self.cancelFoldingRangesUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelFoldingRangesUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.foldingRanges), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelFoldingRangesUI()
                return
            }

            let result: EcuLspFoldingRangeResult?
            do {
                result = try tab.editCore.editor.lspTakeLastFoldingRangesResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelFoldingRangesUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.foldingRanges, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            self.cancelFoldingRangesUI()
            _ = self.applyFoldingRangesResultToActiveTab(result, showFeedback: showFeedback)
        }

        foldingRangesPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func expandSelectionWithLspInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.selectionRange), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let positionsJSON: String
        do {
            let selections = try tab.editCore.editor.selections().ranges
            let positions = try selections.map { range in
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: range.end)
                return ["line": Int(pos.line), "column": Int(pos.column)]
            }
            let data = try JSONSerialization.data(
                withJSONObject: positions,
                options: []
            )
            guard let json = String(data: data, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            positionsJSON = json
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Selection range position could not be computed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()

        do {
            _ = try tab.editCore.editor.lspRequestSelectionRange(positionsJSON: positionsJSON)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.selectionRange, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        selectionRangeContext = SelectionRangeRequestContext(tabID: tab.id, showFeedback: showFeedback)
        startSelectionRangePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applySelectionRangeResultJSONToActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let candidateChains = AttoLspSelectionRangeParser.candidateChains(
                fromResultJSON: json,
                documentText: text
            )
            return applySelectionRangeCandidateChainsToActiveTab(candidateChains, showFeedback: showFeedback)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.selectionRange, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applySelectionRangeResultToActiveTab(
        _ result: EcuLspSelectionRangeResult,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let candidateChains = AttoLspSelectionRangeParser.candidateChains(
                from: result,
                documentText: text
            )
            return applySelectionRangeCandidateChainsToActiveTab(candidateChains, showFeedback: showFeedback)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.selectionRange, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applySelectionRangeCandidateChainsToActiveTab(
        _ candidateChains: [[AttoLspSelectionRangeParser.Candidate]],
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let selections = try tab.editCore.editor.selections()

            var nextRanges: [EcuSelectionRange] = []
            nextRanges.reserveCapacity(selections.ranges.count)
            var didExpand = false

            for (idx, range) in selections.ranges.enumerated() {
                let candidates = idx < candidateChains.count ? candidateChains[idx] : []
                if let candidate = AttoLspSelectionRangeParser.nextCandidate(
                    from: candidates,
                    currentStart: range.start,
                    currentEnd: range.end
                ) {
                    nextRanges.append(EcuSelectionRange(start: candidate.start, end: candidate.end))
                    didExpand = true
                } else {
                    nextRanges.append(range)
                }
            }

            guard didExpand else {
                if showFeedback {
                    presentLspResultFeedback(AttoLspResultFeedback.empty(.selectionRange), in: tab.editCore.editorView)
                }
                NSSound.beep()
                return false
            }

            try tab.editCore.editor.setSelections(
                nextRanges,
                primaryIndex: min(selections.primaryIndex, UInt32(max(0, nextRanges.count - 1)))
            )
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            tab.editCore.editorView.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.selectionRange, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func startSelectionRangePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        selectionRangePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.selectionRangeContext, ctx.tabID == tabID else {
                self.cancelSelectionRangeUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelSelectionRangeUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.selectionRange), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSelectionRangeUI()
                return
            }

            let result: EcuLspSelectionRangeResult?
            do {
                result = try tab.editCore.editor.lspTakeLastSelectionRangeResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelSelectionRangeUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.selectionRange, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            self.cancelSelectionRangeUI()
            _ = self.applySelectionRangeResultToActiveTab(result, showFeedback: showFeedback)
        }

        selectionRangePollTimer = timer
        timer.resume()
    }

    @discardableResult
    func startLinkedEditingInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.linkedEditing), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let caretOffset: UInt32
        let position: (line: UInt32, column: UInt32)
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            caretOffset = offsets.end
            position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        } catch {
            if showFeedback {
                showWorkspaceEditPopover(
                    text: "Linked editing position could not be computed.\n\(error.localizedDescription)",
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            _ = try tab.editCore.editor.lspRequestLinkedEditingRange(
                logicalLine: position.line,
                logicalColumn: position.column
            )
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.linkedEditing, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        linkedEditingContext = LinkedEditingRequestContext(
            tabID: tab.id,
            caretOffset: caretOffset,
            showFeedback: showFeedback
        )
        startLinkedEditingPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func applyLinkedEditingRangeResultJSONToActiveTab(
        _ json: String,
        caretOffset: UInt32? = nil,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let effectiveCaretOffset = caretOffset ?? offsets.end
            let result = AttoLspLinkedEditingParser.result(
                fromLinkedEditingRangeResultJSON: json,
                documentText: text
            )
            return applyLinkedEditingParserResultToActiveTab(
                result,
                effectiveCaretOffset: effectiveCaretOffset,
                showFeedback: showFeedback
            )
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.linkedEditing, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyLinkedEditingRangeResultToActiveTab(
        _ result: EcuLspLinkedEditingRangeResult,
        caretOffset: UInt32? = nil,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let text = try tab.editCore.editor.text()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let effectiveCaretOffset = caretOffset ?? offsets.end
            let result = AttoLspLinkedEditingParser.result(
                from: result,
                documentText: text
            )
            return applyLinkedEditingParserResultToActiveTab(
                result,
                effectiveCaretOffset: effectiveCaretOffset,
                showFeedback: showFeedback
            )
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.linkedEditing, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyLinkedEditingParserResultToActiveTab(
        _ result: AttoLspLinkedEditingParser.Result?,
        effectiveCaretOffset: UInt32,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard let result, result.ranges.count > 1 else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.linkedEditing), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        do {
            try tab.editCore.editor.setSelections(
                result.ranges,
                primaryIndex: result.primaryIndex(containing: effectiveCaretOffset)
            )
            linkedEditingSession = LinkedEditingSession(tabID: tab.id, selectionCount: result.ranges.count)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.linkedEditing, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func startLinkedEditingPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        linkedEditingPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.linkedEditingContext, ctx.tabID == tabID else {
                self.cancelLinkedEditingUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelLinkedEditingUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.linkedEditing), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelLinkedEditingUI()
                return
            }

            let result: EcuLspLinkedEditingRangeResult?
            do {
                result = try tab.editCore.editor.lspTakeLastLinkedEditingRangeResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelLinkedEditingUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.linkedEditing, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let caretOffset = ctx.caretOffset
            let showFeedback = ctx.showFeedback
            self.cancelLinkedEditingUI()
            _ = self.applyLinkedEditingRangeResultToActiveTab(
                result,
                caretOffset: caretOffset,
                showFeedback: showFeedback
            )
        }

        linkedEditingPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showDocumentColorsInActiveTab(showFeedback: Bool = true) -> Bool {
        requestDocumentColorsInActiveTab(mode: .presentations, showFeedback: showFeedback)
    }

    @discardableResult
    func pickDocumentColorInActiveTab(showFeedback: Bool = true) -> Bool {
        requestDocumentColorsInActiveTab(mode: .picker, showFeedback: showFeedback)
    }

    @discardableResult
    func showDocumentColorsPanelInActiveTab(showFeedback: Bool = true) -> Bool {
        requestDocumentColorsInActiveTab(mode: .panel, showFeedback: showFeedback)
    }

    @discardableResult
    func requestDocumentColorsInActiveTab(
        mode: DocumentColorResultMode,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.documentColors), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelFoldingRangesUI()
        cancelSelectionRangeUI()
        cancelLinkedEditingUI()
        cancelDocumentColorUI()

        do {
            _ = try tab.editCore.editor.lspRequestDocumentColor()
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.documentColors, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        documentColorContext = DocumentColorRequestContext(
            tabID: tab.id,
            showFeedback: showFeedback,
            mode: mode
        )
        startDocumentColorPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showDocumentColorResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        handleDocumentColorResultJSON(json, mode: .presentations, showFeedback: showFeedback)
    }

    @discardableResult
    func pickDocumentColorResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        handleDocumentColorResultJSON(json, mode: .picker, showFeedback: showFeedback)
    }

    @discardableResult
    func showDocumentColorPanelResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        handleDocumentColorResultJSON(json, mode: .panel, showFeedback: showFeedback)
    }

    @discardableResult
    func handleDocumentColorResultJSON(
        _ json: String,
        mode: DocumentColorResultMode,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let items = AttoLspDocumentColorParser.items(
            fromDocumentColorResultJSON: json,
            documentText: text
        )
        return finishDocumentColorResult(items, mode: mode, tab: tab, showFeedback: showFeedback)
    }

    @discardableResult
    func handleDocumentColorResult(
        _ result: EcuLspDocumentColorResult,
        mode: DocumentColorResultMode,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let items = AttoLspDocumentColorParser.items(
            fromDocumentColorResult: result,
            documentText: text
        )
        return finishDocumentColorResult(items, mode: mode, tab: tab, showFeedback: showFeedback)
    }

    @discardableResult
    func finishDocumentColorResult(
        _ items: [AttoLspDocumentColorParser.Item],
        mode: DocumentColorResultMode,
        tab: AttoEditorTab,
        showFeedback: Bool
    ) -> Bool {
        guard items.isEmpty == false else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.documentColors), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        recordDocumentColorResultLifecycle(items: items, mode: mode)
        switch mode {
        case .presentations:
            updateVisibleDocumentColorPanel(items: items)
            showDocumentColorResults(items, tabID: tab.id)
        case .picker:
            updateVisibleDocumentColorPanel(items: items)
            showDocumentColorPickerResults(items, tabID: tab.id)
        case .panel:
            showDocumentColorPanel(items, tabID: tab.id)
        }
        return true
    }

    func recordDocumentColorResultLifecycle(
        items: [AttoLspDocumentColorParser.Item],
        mode: DocumentColorResultMode
    ) {
        lspResultEventStream.record(
            family: "document_colors",
            title: items.count == 1 ? "Document Colors: 1 color" : "Document Colors: \(items.count) colors",
            payload: .documentColors(mode: mode.lifecycleMode, itemCount: items.count)
        )
    }

    func showDocumentColorResults(_ items: [AttoLspDocumentColorParser.Item], tabID: UUID) {
        guard let window = view.window else {
            if let first = items.first {
                _ = selectDocumentColor(first, tabID: tabID, requestPresentations: false)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.document_color.\(idx)",
                title: AttoLspDocumentColorParser.displayTitle(for: item),
                swatchColor: nsColor(for: item.color)
            ) { [weak self] in
                _ = self?.selectDocumentColor(item, tabID: tabID, requestPresentations: true)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.DocumentColors",
            commandsProvider: { commands }
        )
        documentColorResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter document colors...")
    }

    func showDocumentColorPanel(_ items: [AttoLspDocumentColorParser.Item], tabID: UUID) {
        guard let window = view.window else {
            if let first = items.first {
                _ = selectDocumentColor(first, tabID: tabID, requestPresentations: false)
            }
            return
        }

        let controller = documentColorPanelController ?? makeDocumentColorPanelController()
        documentColorPanelController = controller
        controller.show(relativeTo: window, items: items)
    }

    func updateVisibleDocumentColorPanel(items: [AttoLspDocumentColorParser.Item]) {
        guard let controller = documentColorPanelController, controller.isVisible else { return }
        controller.update(items: items)
    }

    func makeDocumentColorPanelController() -> AttoDocumentColorPanelController {
        AttoDocumentColorPanelController(
            titleForItem: { item in
                AttoLspDocumentColorParser.displayTitle(for: item)
            },
            colorForItem: { [weak self] item in
                self?.nsColor(for: item.color) ?? .clear
            },
            onOpen: { [weak self] item in
                guard let self, let tab = self.activeTab else {
                    NSSound.beep()
                    return
                }
                _ = self.selectDocumentColor(item, tabID: tab.id, requestPresentations: true)
            }
        )
    }

    func showDocumentColorPickerResults(_ items: [AttoLspDocumentColorParser.Item], tabID: UUID) {
        guard items.count > 1, let window = view.window else {
            if let first = items.first {
                _ = openDocumentColorPicker(for: first, tabID: tabID)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.pick_document_color.\(idx)",
                title: "Pick \(AttoLspDocumentColorParser.displayTitle(for: item))",
                swatchColor: nsColor(for: item.color)
            ) { [weak self] in
                _ = self?.openDocumentColorPicker(for: item, tabID: tabID)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.DocumentColorPicker",
            commandsProvider: { commands }
        )
        documentColorResultsController = controller
        controller.show(relativeTo: window, placeholder: "Pick document color...")
    }

    @discardableResult
    func selectDocumentColor(
        _ item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        requestPresentations: Bool
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        do {
            try tab.editCore.editor.setSelections([item.range], primaryIndex: 0)
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
        } catch {
            NSSound.beep()
            return false
        }

        if requestPresentations {
            return requestColorPresentations(for: item, tabID: tabID, showFeedback: true)
        }
        return true
    }

    @discardableResult
    func openDocumentColorPicker(
        for item: AttoLspDocumentColorParser.Item,
        tabID: UUID
    ) -> Bool {
        guard selectDocumentColor(item, tabID: tabID, requestPresentations: false) else {
            return false
        }

        let initialColor = nsColor(for: item.color)
        if let documentColorPickerForTesting {
            guard let pickedColor = documentColorPickerForTesting(initialColor) else {
                return true
            }
            return handlePickedDocumentColor(pickedColor, item: item, tabID: tabID, showFeedback: true)
        }

        documentColorPanelContext = DocumentColorPanelContext(tabID: tabID, item: item)
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = initialColor
        panel.setTarget(self)
        panel.setAction(#selector(documentColorPanelDidChange(_:)))
        panel.orderFront(nil)
        return true
    }

    @objc func documentColorPanelDidChange(_ sender: NSColorPanel) {
        guard let ctx = documentColorPanelContext else { return }
        _ = handlePickedDocumentColor(sender.color, item: ctx.item, tabID: ctx.tabID, showFeedback: false)
    }

    @discardableResult
    func handlePickedDocumentColor(
        _ pickedColor: NSColor,
        item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool
    ) -> Bool {
        guard let color = lspColor(for: pickedColor) else {
            guard let tab = activeTab, tab.id == tabID else { return false }
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .documentColors,
                        errorDescription: "Selected color could not be converted to RGB."
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        let pickedItem = AttoLspDocumentColorParser.Item(
            range: item.range,
            startLine: item.startLine,
            startUTF16Character: item.startUTF16Character,
            color: color
        )
        return requestColorPresentations(for: pickedItem, tabID: tabID, showFeedback: showFeedback)
    }

    @discardableResult
    func requestColorPresentations(
        for item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }
        guard let colorJSON = AttoLspDocumentColorParser.colorJSON(for: item) else {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .colorPresentations,
                        errorDescription: "Color presentation request could not encode the color."
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        cancelColorPresentationUI()
        do {
            _ = try tab.editCore.editor.lspRequestColorPresentation(
                startOffset: item.range.start,
                endOffset: item.range.end,
                colorJSON: colorJSON
            )
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .colorPresentations,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        colorPresentationContext = ColorPresentationRequestContext(
            tabID: tabID,
            item: item,
            showFeedback: showFeedback
        )
        startColorPresentationPollTimer(tabID: tabID, editorView: tab.editCore.editorView)
        return true
    }

    func startDocumentColorPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        documentColorPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.documentColorContext, ctx.tabID == tabID else {
                self.cancelDocumentColorUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentColorUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.documentColors), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelDocumentColorUI()
                return
            }

            let result: EcuLspDocumentColorResult?
            do {
                result = try tab.editCore.editor.lspTakeLastDocumentColorResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentColorUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(
                            .documentColors,
                            errorDescription: error.localizedDescription
                        ),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            let mode = ctx.mode
            self.cancelDocumentColorRequestOnly()
            _ = self.handleDocumentColorResult(result, mode: mode, showFeedback: showFeedback)
        }

        documentColorPollTimer = timer
        timer.resume()
    }

    func startColorPresentationPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        colorPresentationPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.colorPresentationContext, ctx.tabID == tabID else {
                self.cancelColorPresentationUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelColorPresentationUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.colorPresentations), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelColorPresentationUI()
                return
            }

            let result: EcuLspColorPresentationResult?
            do {
                result = try tab.editCore.editor.lspTakeLastColorPresentationResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelColorPresentationUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(
                            .colorPresentations,
                            errorDescription: error.localizedDescription
                        ),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let item = ctx.item
            let showFeedback = ctx.showFeedback
            self.cancelColorPresentationRequestOnly()
            _ = self.showColorPresentationResultInActiveTab(
                result,
                item: item,
                tabID: tabID,
                showFeedback: showFeedback
            )
        }

        colorPresentationPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showColorPresentationResultJSONInActiveTab(
        _ json: String,
        item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let presentations = AttoLspDocumentColorParser.presentations(
            fromColorPresentationResultJSON: json,
            documentText: text
        )
        return finishColorPresentationResult(
            presentations,
            item: item,
            tab: tab,
            showFeedback: showFeedback
        )
    }

    @discardableResult
    func showColorPresentationResultInActiveTab(
        _ result: EcuLspColorPresentationResult,
        item: AttoLspDocumentColorParser.Item,
        tabID: UUID,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        let text = (try? tab.editCore.editor.text()) ?? ""
        let presentations = AttoLspDocumentColorParser.presentations(
            fromColorPresentationResult: result,
            documentText: text
        )
        return finishColorPresentationResult(
            presentations,
            item: item,
            tab: tab,
            showFeedback: showFeedback
        )
    }

    @discardableResult
    func finishColorPresentationResult(
        _ presentations: [AttoLspDocumentColorParser.Presentation],
        item: AttoLspDocumentColorParser.Item,
        tab: AttoEditorTab,
        showFeedback: Bool
    ) -> Bool {
        guard presentations.isEmpty == false else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.colorPresentations), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        recordColorPresentationResultLifecycle(presentations: presentations)
        guard let window = view.window else {
            return applyColorPresentationToActiveTab(presentations[0], showFeedback: showFeedback)
        }

        let commands = presentations.enumerated().map { idx, presentation in
            AttoCommandPaletteCommand(
                id: "lsp.color_presentation.\(idx)",
                title: AttoLspDocumentColorParser.displayTitle(for: presentation),
                swatchColor: nsColor(for: item.color),
                isEnabled: presentation.isApplicable
            ) { [weak self] in
                _ = self?.applyColorPresentationToActiveTab(presentation, showFeedback: true)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ColorPresentations",
            commandsProvider: { commands }
        )
        colorPresentationResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter color presentations...")
        return true
    }

    func recordColorPresentationResultLifecycle(
        presentations: [AttoLspDocumentColorParser.Presentation]
    ) {
        let title: String
        if presentations.count == 1 {
            title = "Color Presentations: 1 presentation"
        } else {
            title = "Color Presentations: \(presentations.count) presentations"
        }
        lspResultEventStream.record(
            family: "color_presentations",
            title: title,
            payload: .colorPresentations(itemCount: presentations.count)
        )
    }

    @discardableResult
    func applyColorPresentationToActiveTab(
        _ presentation: AttoLspDocumentColorParser.Presentation,
        showFeedback: Bool = true
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard presentation.isApplicable else {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .colorPresentations,
                        errorDescription: "This color presentation has no text edit to apply."
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.applyTextEdits(presentation.edits)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .colorPresentations,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func nsColor(for color: AttoLspDocumentColorParser.Color) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(max(0, min(1, color.red))),
            green: CGFloat(max(0, min(1, color.green))),
            blue: CGFloat(max(0, min(1, color.blue))),
            alpha: CGFloat(max(0, min(1, color.alpha)))
        )
    }

    func lspColor(for color: NSColor) -> AttoLspDocumentColorParser.Color? {
        guard let rgb = color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB) else {
            return nil
        }

        return AttoLspDocumentColorParser.Color(
            red: Double(max(0, min(1, rgb.redComponent))),
            green: Double(max(0, min(1, rgb.greenComponent))),
            blue: Double(max(0, min(1, rgb.blueComponent))),
            alpha: Double(max(0, min(1, rgb.alphaComponent)))
        )
    }

    func moveToMatchingBracketInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.moveToMatchingBracket()
    }

    func jumpBackInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpBack()
    }

    func jumpForwardInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpForward()
    }

    @discardableResult
    func formatDocumentWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        let result = tab.editCore.editorView.formatDocumentWithLSPResult()
        if result.didApply {
            updateStatusBar()
        }
        return handleFormattingResult(result, feature: .formatDocument, editorView: tab.editCore.editorView)
    }

    @discardableResult
    func formatSelectionWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            guard startOffset < endOffset else {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.formatSelection), in: tab.editCore.editorView)
                NSSound.beep()
                return false
            }

            let result = tab.editCore.editorView.formatRangeWithLSPResult(
                startOffset: startOffset,
                endOffset: endOffset
            )
            if result.didApply {
                updateStatusBar()
            }
            return handleFormattingResult(result, feature: .formatSelection, editorView: tab.editCore.editorView)
        } catch {
            presentLspResultFeedback(
                AttoLspResultFeedback.failed(.formatSelection, errorDescription: error.localizedDescription),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func handleFormattingResult(
        _ result: EditorCoreLSPFormattingResult,
        feature: AttoLspResultFeedback.Feature,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        switch result {
        case .applied:
            return true
        case .noEdits:
            presentLspResultFeedback(AttoLspResultFeedback.empty(feature), in: editorView)
            return false
        case .unavailable(let reason):
            presentLspResultFeedback(AttoLspResultFeedback.unavailable(feature, reason: reason), in: editorView)
            NSSound.beep()
            return false
        case .failed(let message):
            presentLspResultFeedback(AttoLspResultFeedback.failed(feature, errorDescription: message), in: editorView)
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func executeActiveEditorCommandObject(_ object: [String: Any], treatsAsTextMutation: Bool? = nil) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [])
            guard let json = String(data: data, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            return executeActiveEditorCommandJSON(json, treatsAsTextMutation: treatsAsTextMutation)
        } catch {
            NSSound.beep()
            return false
        }
    }

    static func commandJSONIsTextMutation(_ commandJSON: String) -> Bool {
        guard let data = commandJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (obj["kind"] as? String) == "edit"
        else {
            return false
        }
        return (obj["op"] as? String) != "end_undo_group"
    }

    static func commandJSONMayChangeSelection(_ commandJSON: String) -> Bool {
        guard let data = commandJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return false
        }
        return (obj["kind"] as? String) == "cursor"
    }
}
