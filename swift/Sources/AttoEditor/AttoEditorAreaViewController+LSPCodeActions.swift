import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP code actions

    @discardableResult
    func showCodeActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: [])
    }

    @discardableResult
    func showQuickFixesInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["quickfix"])
    }

    @discardableResult
    func showRefactorActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["refactor"])
    }

    @discardableResult
    func showSourceActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source"])
    }

    @discardableResult
    func organizeImportsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.organizeImports"])
    }

    @discardableResult
    func fixAllInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.fixAll"])
    }

    @discardableResult
    func showCodeActionsInActiveTab(onlyKinds: [String]) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            presentLspResultFeedback(AttoLspResultFeedback.unavailable(.codeActions), in: tab.editCore.editorView)
            NSSound.beep()
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
            let offsets = try tab.editCore.editor.selectionOffsets()
            let start = min(offsets.start, offsets.end)
            let end = max(offsets.start, offsets.end)
            let contextJSON = codeActionContextJSON(
                editor: tab.editCore.editor,
                startOffset: start,
                endOffset: end,
                onlyKinds: onlyKinds
            )
            _ = try tab.editCore.editor.lspRequestCodeAction(
                startOffset: start,
                endOffset: end,
                contextJSON: contextJSON
            )
            codeActionContext = CodeActionRequestContext(tabID: tab.id, onlyKinds: onlyKinds, showFeedback: true)
            startCodeActionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelCodeActionUI()
            presentLspResultFeedback(
                AttoLspResultFeedback.requestFailed(.codeActions, errorDescription: error.localizedDescription),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }
    }

    func codeActionContextJSON(
        editor: EditorUI,
        startOffset: UInt32,
        endOffset: UInt32,
        onlyKinds: [String]
    ) -> String {
        derivedStateStore.refreshActive(editor: editor)
        let text = (try? editor.text()) ?? ""
        return AttoLspCodeActionContext.contextJSON(
            diagnostics: derivedStateStore.active.diagnostics,
            documentText: text,
            selectionStart: startOffset,
            selectionEnd: endOffset,
            onlyKinds: onlyKinds
        )
    }

    func startCodeActionPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        codeActionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.codeActionContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelCodeActionUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.codeActions), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let result: EcuLspCodeActionResult?
            do {
                result = try tab.editCore.editor.lspTakeLastCodeActionResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelCodeActionUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.codeActions, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let items = AttoLspCodeActionParser.filteredItems(
                AttoLspCodeActionParser.items(fromCodeActionResult: result),
                onlyKinds: ctx.onlyKinds
            )
            self.codeActionPollTimer?.cancel()
            self.codeActionPollTimer = nil
            self.codeActionContext = nil
            _ = self.showCodeActionResults(items, onlyKinds: ctx.onlyKinds, showFeedback: ctx.showFeedback)
            timer.cancel()
        }

        codeActionPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showCodeActionResults(
        _ items: [AttoLspCodeActionParser.Item],
        onlyKinds: [String],
        showFeedback: Bool = true
    ) -> Bool {
        guard items.isEmpty == false else {
            cancelCodeActionUI()
            if showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.codeActions), in: editorView)
            }
            NSSound.beep()
            return false
        }

        recordCodeActionResultLifecycle(items: items, onlyKinds: onlyKinds)
        guard let window = view.window else {
            _ = applyCodeAction(items[0], showFeedback: showFeedback)
            return true
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_action.\(idx)",
                title: AttoLspCodeActionParser.displayTitle(for: item)
            ) { [weak self] in
                _ = self?.applyCodeAction(item)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.CodeActions",
            commandsProvider: { commands }
        )
        codeActionResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter code actions...")
        return true
    }

    func recordCodeActionResultLifecycle(
        items: [AttoLspCodeActionParser.Item],
        onlyKinds: [String]
    ) {
        lspResultEventStream.record(
            family: "code_actions",
            title: codeActionResultTitle(itemCount: items.count, onlyKinds: onlyKinds),
            payload: .codeActions(onlyKinds: onlyKinds, itemCount: items.count)
        )
    }

    func codeActionResultTitle(itemCount: Int, onlyKinds: [String]) -> String {
        let scope: String
        if onlyKinds.isEmpty {
            scope = "Code Actions"
        } else {
            scope = "Code Actions: \(onlyKinds.joined(separator: ", "))"
        }
        return itemCount == 1 ? "\(scope): 1 result" : "\(scope): \(itemCount) results"
    }

    @discardableResult
    func applyCodeAction(
        _ item: AttoLspCodeActionParser.Item,
        allowResolve: Bool = true,
        showFeedback: Bool = true
    ) -> Bool {
        guard item.disabledReason == nil else {
            if showFeedback, let editorView = activeTab?.editCore.editorView {
                let reason = item.disabledReason ?? "Selected code action is disabled."
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(.codeActions, errorDescription: reason),
                    in: editorView
                )
            }
            NSSound.beep()
            return false
        }

        var didApply = false
        var attemptedWorkspaceEdit = false
        if let workspaceEdit = AttoLspCodeActionParser.workspaceEdit(for: item),
           workspaceEdit.rawJSONString != nil
        {
            attemptedWorkspaceEdit = true
            didApply = applyWorkspaceEditToActiveTab(workspaceEdit) || didApply
        } else if let editJSON = AttoLspCodeActionParser.editJSON(for: item) {
            attemptedWorkspaceEdit = true
            didApply = applyWorkspaceEditJSONToActiveTab(editJSON) || didApply
        }

        if let command = item.command {
            didApply = requestExecuteCodeActionCommand(command) || didApply
        }

        if didApply {
            return true
        }

        guard allowResolve, item.isLegacyCommand == false else {
            if showFeedback, attemptedWorkspaceEdit == false, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(
                    AttoLspResultFeedback.empty(.codeActionResolve),
                    in: editorView
                )
            }
            NSSound.beep()
            return false
        }
        return requestCodeActionResolve(item, showFeedback: showFeedback)
    }

    func requestCodeActionResolve(_ item: AttoLspCodeActionParser.Item, showFeedback: Bool) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let actionJSON = AttoLspCodeActionParser.rawJSON(for: item) else {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .codeActionResolve,
                        errorDescription: "Selected code action cannot be resolved."
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestCodeActionResolve(actionJSON: actionJSON)
            codeActionResolveContext = CodeActionResolveContext(
                tabID: tab.id,
                item: item,
                showFeedback: showFeedback
            )
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            startCodeActionResolvePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .codeActionResolve,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func startCodeActionResolvePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        codeActionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.codeActionResolveContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelCodeActionUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.codeActionResolve), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let result: EcuLspCodeAction?
            do {
                result = try tab.editCore.editor.lspTakeLastCodeActionResolveResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelCodeActionUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(
                            .codeActionResolve,
                            errorDescription: error.localizedDescription
                        ),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            self.codeActionResolvePollTimer?.cancel()
            self.codeActionResolvePollTimer = nil
            self.codeActionResolveContext = nil
            let resolved = AttoLspCodeActionParser.item(fromCodeAction: result) ?? ctx.item
            _ = self.applyCodeAction(resolved, allowResolve: false, showFeedback: ctx.showFeedback)
            timer.cancel()
        }

        codeActionResolvePollTimer = timer
        timer.resume()
    }

    func requestExecuteCodeActionCommand(_ command: AttoLspCodeActionParser.Command) -> Bool {
        guard let commandJSON = AttoLspCodeActionParser.commandJSON(for: command) else {
            NSSound.beep()
            return false
        }
        return requestExecuteCommandJSON(commandJSON, commandTitle: command.title)
    }

    func requestExecuteCommandJSON(_ commandJSON: String, commandTitle: String) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestExecuteCommand(commandJSON: commandJSON)
            executeCommandContext = ExecuteCommandRequestContext(tabID: tab.id, commandTitle: commandTitle)
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            startExecuteCommandPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    func startExecuteCommandPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        executeCommandPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.executeCommandContext, ctx.tabID == tabID else {
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.showWorkspaceEditPopover(
                    text: AttoLspExecuteCommandFormatter.timeoutText(commandTitle: ctx.commandTitle),
                    in: editorView
                )
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastExecuteCommandResultJSON()
            } catch {
                self.showWorkspaceEditPopover(
                    text: "Command result could not be read.",
                    in: editorView
                )
                self.cancelExecuteCommandUI()
                timer.cancel()
                return
            }
            guard let json else { return }

            self.showWorkspaceEditPopover(
                text: AttoLspExecuteCommandFormatter.displayText(
                    forResultJSON: json,
                    commandTitle: ctx.commandTitle
                ),
                in: editorView
            )
            self.cancelExecuteCommandUI()
            timer.cancel()
        }

        executeCommandPollTimer = timer
        timer.resume()
    }
}
