import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP code lens

    @discardableResult
    func refreshCodeLensInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            let message = AttoLspResultFeedback.unavailable(.codeLensRefresh)
            markCurrentLspEventResultError(family: "code_lens", message: message)
            if showFeedback {
                presentLspResultFeedback(message, in: tab.editCore.editorView)
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
        cancelAuxiliaryRefreshUI()

        do {
            _ = try tab.editCore.editor.lspRequestCodeLens()
        } catch {
            let message = AttoLspResultFeedback.failed(
                .codeLensRefresh,
                errorDescription: error.localizedDescription
            )
            markCurrentLspEventResultError(family: "code_lens", message: message)
            if showFeedback {
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        codeLensRefreshContext = CodeLensRefreshContext(tabID: tab.id, showFeedback: showFeedback)
        tab.editCore.editorView.kickProcessingPoll()
        updateStatusBar()
        startCodeLensRefreshPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showCodeLensActionsInActiveTab() -> Bool {
        guard let tab = activeTab else {
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
        cancelCodeLensUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let items = AttoLspCodeLensParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
        guard items.isEmpty == false else {
            NSSound.beep()
            return false
        }

        showCodeLensResults(items, tab: tab)
        return true
    }

    @discardableResult
    func showCodeLensActionsAtCursorInActiveTab() -> Bool {
        guard let tab = activeTab else {
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
        cancelCodeLensUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let items = AttoLspCodeLensParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
        let currentLineItems = codeLensItemsOnPrimaryCaretLine(items, in: tab)
        guard currentLineItems.isEmpty == false else {
            NSSound.beep()
            return false
        }

        showCodeLensResults(
            currentLineItems,
            tab: tab,
            placeholder: "Filter current-line code lens actions..."
        )
        return true
    }

    @discardableResult
    func showCodeLensPanelInActiveTab() -> Bool {
        guard let tab = activeTab else {
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
        cancelCodeLensUI()

        let items = currentCodeLensItems(in: tab)
        guard items.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            return applyCodeLens(items[0])
        }

        let controller = codeLensPanelController ?? makeCodeLensPanelController()
        codeLensPanelController = controller
        return controller.show(relativeTo: window, items: items)
    }

    func codeLensItemsOnPrimaryCaretLine(
        _ items: [AttoLspCodeLensParser.Item],
        in tab: AttoEditorTab
    ) -> [AttoLspCodeLensParser.Item] {
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let caret = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return items.filter { item in
                guard let pos = try? tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start) else {
                    return false
                }
                return pos.line == caret.line
            }
        } catch {
            return []
        }
    }

    func showCodeLensResults(
        _ items: [AttoLspCodeLensParser.Item],
        tab: AttoEditorTab,
        placeholder: String = "Filter code lens actions..."
    ) {
        guard let window = view.window else {
            if let first = items.first {
                _ = applyCodeLens(first)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_lens.\(idx)",
                title: displayTitle(for: item, in: tab)
            ) { [weak self] in
                _ = self?.applyCodeLens(item)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.CodeLens",
            commandsProvider: { commands }
        )
        codeLensResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
    }

    @discardableResult
    func handleCodeLensClick(json: String, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let item = AttoLspCodeLensParser.item(fromCodeLensJSON: json) else {
            NSSound.beep()
            return false
        }
        cancelHoverUI()
        return applyCodeLens(item)
    }

    @discardableResult
    func applyCodeLens(_ item: AttoLspCodeLensParser.Item, allowResolve: Bool = true) -> Bool {
        if let command = item.command {
            return requestExecuteCommandJSON(command.commandJSON, commandTitle: command.title)
        }

        guard allowResolve else {
            NSSound.beep()
            return false
        }
        return requestCodeLensResolve(item)
    }

    func requestCodeLensResolve(_ item: AttoLspCodeLensParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestCodeLensResolve(lensJSON: item.lensJSON)
            codeLensResolveContext = CodeLensResolveContext(tabID: tab.id, item: item)
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            startCodeLensResolvePollTimer(tabID: tab.id)
            return true
        } catch {
            cancelCodeLensUI()
            NSSound.beep()
            return false
        }
    }

    func startCodeLensResolvePollTimer(tabID: UUID) {
        codeLensResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeLensResolveContext, ctx.tabID == tabID else {
                self.cancelCodeLensUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeLensUI()
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeLensUI()
                return
            }

            let result: EcuLspCodeLens?
            do {
                result = try tab.editCore.editor.lspTakeLastCodeLensResolveResult()
            } catch {
                return
            }
            guard let result else { return }

            self.codeLensResolvePollTimer?.cancel()
            self.codeLensResolvePollTimer = nil
            self.codeLensResolveContext = nil

            let resolved = AttoLspCodeLensParser.item(
                from: result,
                fallbackTitle: ctx.item.title,
                fallbackRange: ctx.item.range
            ) ?? ctx.item
            _ = self.applyCodeLens(resolved, allowResolve: false)
            timer.cancel()
        }

        codeLensResolvePollTimer = timer
        timer.resume()
    }

    func startCodeLensRefreshPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        codeLensRefreshPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.codeLensRefreshContext, ctx.tabID == tabID else {
                self.cancelCodeLensUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.timeout(.codeLensRefresh)
                self.cancelCodeLensUI()
                self.markCurrentLspEventResultError(family: "code_lens", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeLensUI()
                return
            }

            do {
                _ = try tab.editCore.editor.pollProcessing()
            } catch {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.failed(
                    .codeLensRefresh,
                    errorDescription: error.localizedDescription
                )
                self.cancelCodeLensUI()
                self.markCurrentLspEventResultError(family: "code_lens", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }

            let result: EcuLspCodeLensResult?
            do {
                result = try tab.editCore.editor.lspTakeLastCodeLensResult()
            } catch {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.failed(
                    .codeLensRefresh,
                    errorDescription: error.localizedDescription
                )
                self.cancelCodeLensUI()
                self.markCurrentLspEventResultError(family: "code_lens", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let errorMessage = Self.codeLensResultErrorMessage(result)
            let showFeedback = ctx.showFeedback
            self.cancelCodeLensUI()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            self.derivedStateStore.refreshActive(editor: tab.editCore.editor)
            let items = self.currentCodeLensItems(in: tab)
            let count = items.count
            if errorMessage == nil {
                self.recordCodeLensResultEvent(items: items)
            }
            self.updateVisibleCodeLensPanel(for: tab)
            self.updateStatusBar()

            if let errorMessage {
                let message = AttoLspResultFeedback.failed(.codeLensRefresh, errorDescription: errorMessage)
                self.markCurrentLspEventResultError(family: "code_lens", message: message)
                guard showFeedback else { return }
                self.presentLspResultFeedback(
                    message,
                    in: editorView
                )
                NSSound.beep()
                return
            }
            guard showFeedback else { return }
            if count == 0 {
                self.presentLspResultFeedback(AttoLspResultFeedback.empty(.codeLensRefresh), in: editorView)
            } else {
                self.presentLspResultFeedback(
                    AttoLspResultFeedback.refreshed(.codeLensRefresh, count: count, singular: "action", plural: "actions"),
                    in: editorView
                )
            }
        }

        codeLensRefreshPollTimer = timer
        timer.resume()
    }

    static func codeLensResultCount(_ result: EcuLspCodeLensResult) -> Int {
        result.items.count
    }

    static func codeLensResultErrorMessage(_ result: EcuLspCodeLensResult) -> String? {
        result.error?.message
    }

    static func codeLensResultCount(_ json: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        if root is NSNull {
            return 0
        }
        return (root as? [Any])?.count
    }

    static func codeLensResultErrorMessage(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else {
            return nil
        }
        if let message = error["message"] as? String, message.isEmpty == false {
            return message
        }
        return "Unknown LSP error."
    }

    func displayTitle(for item: AttoLspCodeLensParser.Item, in tab: AttoEditorTab) -> String {
        let documentURL = projectedFileURL(for: tab)
        let location: String? = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start)
                return "\(documentURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return documentURL.lastPathComponent
            }
        }()
        return AttoLspCodeLensParser.displayTitle(for: item, location: location)
    }

    func _applyCodeLensResultJSONForTesting(_ json: String) -> Bool {
        guard let tab = activeTab else { return false }
        do {
            try tab.editCore.editor.lspApplyCodeLensJSON(json)
        } catch {
            return false
        }

        tab.editCore.layoutSubtreeIfNeeded()
        tab.editCore.editorView.needsDisplay = true
        tab.editCore.needsDisplay = true
        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        recordCodeLensResultEvent(items: currentCodeLensItems(in: tab))
        updateVisibleCodeLensPanel(for: tab)
        updateStatusBar()
        return true
    }

    private func recordCodeLensResultEvent(items: [AttoLspCodeLensParser.Item]) {
        let itemCount = items.count
        let countText = itemCount == 1 ? "1 action" : "\(itemCount) actions"
        let event = lspResultEventStream.record(
            family: "code_lens",
            title: "Code Lens: \(countText)",
            payload: .codeLens(itemCount: itemCount)
        )
        lspWorkbenchAuxiliaryHistoryStore.record(
            event: event,
            payload: .codeLens(items)
        )
    }

    func currentCodeLensItems(in tab: AttoEditorTab) -> [AttoLspCodeLensParser.Item] {
        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        return AttoLspCodeLensParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
    }

    func makeCodeLensPanelController() -> AttoCodeLensPanelController {
        AttoCodeLensPanelController(
            titleForItem: { [weak self] item in
                guard let self, let tab = self.activeTab else { return item.title }
                return self.displayTitle(for: item, in: tab)
            },
            onApply: { [weak self] item in
                _ = self?.applyCodeLens(item)
            }
        )
    }

    private func updateVisibleCodeLensPanel(for tab: AttoEditorTab) {
        if let controller = codeLensPanelController, controller.isVisible {
            controller.update(items: currentCodeLensItems(in: tab))
        }
        updateVisibleLspWorkbenchPanel()
    }
}
