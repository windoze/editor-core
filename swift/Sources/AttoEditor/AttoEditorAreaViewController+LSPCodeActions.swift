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
            let context = try codeActionRequestContext(
                tab: tab,
                onlyKinds: onlyKinds,
                showFeedback: true
            )
            let contextJSON = codeActionContextJSON(
                editor: tab.editCore.editor,
                startOffset: context.startOffset,
                endOffset: context.endOffset,
                onlyKinds: onlyKinds
            )
            _ = try tab.editCore.editor.lspRequestCodeAction(
                startOffset: context.startOffset,
                endOffset: context.endOffset,
                contextJSON: contextJSON
            )
            codeActionContext = context
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

    func codeActionRequestContextForCurrentSelection(
        onlyKinds: [String],
        showFeedback: Bool
    ) -> CodeActionRequestContext? {
        guard let tab = activeTab else { return nil }
        return try? codeActionRequestContext(
            tab: tab,
            onlyKinds: onlyKinds,
            showFeedback: showFeedback
        )
    }

    func codeActionRequestContext(
        tab: AttoEditorTab,
        onlyKinds: [String],
        showFeedback: Bool
    ) throws -> CodeActionRequestContext {
        let offsets = try tab.editCore.editor.selectionOffsets()
        return CodeActionRequestContext(
            tabID: tab.id,
            startOffset: min(offsets.start, offsets.end),
            endOffset: max(offsets.start, offsets.end),
            onlyKinds: onlyKinds,
            showFeedback: showFeedback
        )
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
            _ = self.showCodeActionResults(
                items,
                onlyKinds: ctx.onlyKinds,
                showFeedback: ctx.showFeedback,
                requestContext: ctx
            )
            timer.cancel()
        }

        codeActionPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showCodeActionResults(
        _ items: [AttoLspCodeActionParser.Item],
        onlyKinds: [String],
        showFeedback: Bool = true,
        requestContext: CodeActionRequestContext? = nil
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
            _ = applyCodeAction(items[0], showFeedback: showFeedback, requestContext: requestContext)
            return true
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_action.\(idx)",
                title: AttoLspCodeActionParser.displayTitle(for: item)
            ) { [weak self] in
                _ = self?.applyCodeAction(item, requestContext: requestContext)
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
        showFeedback: Bool = true,
        requestContext: CodeActionRequestContext? = nil
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
           let workspaceEditJSON = workspaceEdit.rawJSONString
        {
            attemptedWorkspaceEdit = true
            let outcome = applyWorkspaceEditToActiveTab(
                AttoWorkspaceEditParser.parse(workspaceEdit),
                workspaceEditJSON: workspaceEditJSON,
                requestRetryOwner: codeActionWorkspaceEditRequestRetryOwner(context: requestContext)
            )
            didApply = outcome.accepted || didApply
        } else if let editJSON = AttoLspCodeActionParser.editJSON(for: item) {
            attemptedWorkspaceEdit = true
            if let parsed = AttoWorkspaceEditParser.parse(editJSON) {
                let outcome = applyWorkspaceEditToActiveTab(
                    parsed,
                    workspaceEditJSON: editJSON,
                    requestRetryOwner: codeActionWorkspaceEditRequestRetryOwner(context: requestContext)
                )
                didApply = outcome.accepted || didApply
            } else {
                didApply = applyWorkspaceEditJSONToActiveTab(editJSON) || didApply
            }
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
        return requestCodeActionResolve(item, showFeedback: showFeedback, requestContext: requestContext)
    }

    func requestCodeActionResolve(
        _ item: AttoLspCodeActionParser.Item,
        showFeedback: Bool,
        requestContext: CodeActionRequestContext? = nil
    ) -> Bool {
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
                requestContext: requestContext,
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
            _ = self.applyCodeAction(
                resolved,
                allowResolve: false,
                showFeedback: ctx.showFeedback,
                requestContext: ctx.requestContext
            )
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
            executeCommandContext = ExecuteCommandRequestContext(
                tabID: tab.id,
                commandTitle: commandTitle,
                commandJSON: commandJSON
            )
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            tab.editCore.editorView.kickProcessingPoll()
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

            do {
                _ = try tab.editCore.editor.pollProcessing()
            } catch {
                self.showWorkspaceEditPopover(
                    text: "Command result could not be processed.",
                    in: editorView
                )
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

            if let outcome = self.applyExecuteCommandWorkspaceEditResultJSON(json, context: ctx) {
                switch outcome {
                case .applied:
                    self.showWorkspaceEditPopover(
                        text: "Command completed.\nCommand: \(ctx.commandTitle)\n\nWorkspace edit applied.",
                        in: editorView
                    )
                case .requestRerunStarted:
                    timer.cancel()
                    return
                case .stopped:
                    self.showWorkspaceEditPopover(
                        text: "Command completed.\nCommand: \(ctx.commandTitle)\n\nWorkspace edit was not applied.",
                        in: editorView
                    )
                }
            } else {
                self.showWorkspaceEditPopover(
                    text: AttoLspExecuteCommandFormatter.displayText(
                        forResultJSON: json,
                        commandTitle: ctx.commandTitle
                    ),
                    in: editorView
                )
            }
            self.cancelExecuteCommandUI()
            timer.cancel()
        }

        executeCommandPollTimer = timer
        timer.resume()
    }

    func applyExecuteCommandWorkspaceEditResultJSON(
        _ json: String,
        context: ExecuteCommandRequestContext
    ) -> AttoWorkspaceEditApplyOutcome? {
        guard let workspaceEditJSON = executeCommandWorkspaceEditJSON(fromResultJSON: json),
              let parsed = AttoWorkspaceEditParser.parse(workspaceEditJSON),
              parsed.isEmpty == false
        else {
            return nil
        }

        return applyWorkspaceEditToActiveTab(
            parsed,
            workspaceEditJSON: workspaceEditJSON,
            requestRetryOwner: executeCommandWorkspaceEditRequestRetryOwner(context: context)
        )
    }

    func executeCommandWorkspaceEditJSON(fromResultJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return nil
        }

        if let object = root as? [String: Any], object.keys.contains("result") {
            guard let result = object["result"], (result is NSNull) == false else { return nil }
            return workspaceEditJSONCandidate(from: result)
        }
        return workspaceEditJSONCandidate(from: root)
    }

    func workspaceEditJSONCandidate(from value: Any) -> String? {
        if let string = value as? String,
           let parsed = AttoWorkspaceEditParser.parse(string),
           parsed.isEmpty == false
        {
            return string
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let json = String(data: data, encoding: .utf8),
              let parsed = AttoWorkspaceEditParser.parse(json),
              parsed.isEmpty == false
        else {
            return nil
        }
        return json
    }
}
