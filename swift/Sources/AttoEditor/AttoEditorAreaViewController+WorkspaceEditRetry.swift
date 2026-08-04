import AppKit
import Foundation

enum AttoWorkspaceEditApplyOutcome {
    case applied
    case stopped
    case requestRerunStarted

    var accepted: Bool {
        switch self {
        case .applied, .requestRerunStarted:
            return true
        case .stopped:
            return false
        }
    }
}

struct AttoWorkspaceEditRequestRetryOwner {
    let label: String
    let rerun: @MainActor () -> Bool
}

extension AttoEditorAreaViewController {
    @discardableResult
    func rerunWorkspaceEditRequest(_ requestRetryOwner: AttoWorkspaceEditRequestRetryOwner) -> Bool {
        guard requestRetryOwner.rerun() else {
            setTransientStatusText("WorkspaceEdit request retry failed: \(requestRetryOwner.label)")
            NSSound.beep()
            return false
        }
        setTransientStatusText("Retrying WorkspaceEdit request: \(requestRetryOwner.label)")
        return true
    }

    func formattingWorkspaceEditRequestRetryOwner(
        context: FormattingRequestContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: context.kind.retryLabel) { [weak self] in
            guard let self else { return false }
            return self.retryFormattingWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryFormattingWorkspaceEditRequest(context: FormattingRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit formatting retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(context.kind.feedbackFeature),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        return requestFormattingWithLspInActiveTab(
            kind: context.kind,
            showFeedback: context.showFeedback
        )
    }

    func colorPresentationWorkspaceEditRequestRetryOwner(
        context: ColorPresentationRequestContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: "Color Presentation") { [weak self] in
            guard let self else { return false }
            return self.retryColorPresentationWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryColorPresentationWorkspaceEditRequest(context: ColorPresentationRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit color presentation retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(.colorPresentations),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        return requestColorPresentations(
            for: context.item,
            tabID: tab.id,
            showFeedback: context.showFeedback
        )
    }

    func inlayHintResolveWorkspaceEditRequestRetryOwner(
        context: InlayHintResolveContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: "Inlay Hint Resolve") { [weak self] in
            guard let self else { return false }
            return self.retryInlayHintResolveWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryInlayHintResolveWorkspaceEditRequest(context: InlayHintResolveContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit inlay hint retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(.inlayHintResolve),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        return requestInlayHintResolve(
            json: context.hintJSON,
            tabID: tab.id,
            editorView: tab.editCore.editorView,
            showFeedback: context.showFeedback
        )
    }

    func executeCommandWorkspaceEditRequestRetryOwner(
        context: ExecuteCommandRequestContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: "Command: \(context.commandTitle)") { [weak self] in
            guard let self else { return false }
            return self.retryExecuteCommandWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryExecuteCommandWorkspaceEditRequest(context: ExecuteCommandRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit command retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            setTransientStatusText("WorkspaceEdit command retry source unavailable")
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        do {
            cancelExecuteCommandUI()
            _ = try tab.editCore.editor.lspRequestExecuteCommand(commandJSON: context.commandJSON)
            executeCommandContext = context
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            codeLensResultsController?.hide()
            codeLensResultsController = nil
            tab.editCore.editorView.kickProcessingPoll()
            startExecuteCommandPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelExecuteCommandUI()
            setTransientStatusText("WorkspaceEdit command retry failed")
            NSSound.beep()
            return false
        }
    }

    func completionWorkspaceEditRequestRetryOwner(
        context: CompletionRequestContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: "Completion") { [weak self] in
            guard let self else { return false }
            return self.retryCompletionWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryCompletionWorkspaceEditRequest(context: CompletionRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit completion retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(.completion),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        do {
            _ = try tab.editCore.editor.lspRequestCompletion(
                logicalLine: context.logicalLine,
                logicalColumn: context.logicalColumn
            )
            cancelCompletionUI()
            completionContext = context
            startCompletionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelCompletionUI()
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .completion,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func codeActionWorkspaceEditRequestRetryOwner(
        context: CodeActionRequestContext?
    ) -> AttoWorkspaceEditRequestRetryOwner? {
        guard let context else { return nil }
        return AttoWorkspaceEditRequestRetryOwner(label: codeActionRetryLabel(context: context)) { [weak self] in
            guard let self else { return false }
            return self.retryCodeActionWorkspaceEditRequest(context: context)
        }
    }

    func codeActionRetryLabel(context: CodeActionRequestContext) -> String {
        if context.onlyKinds.isEmpty {
            return "Code Actions"
        }
        return "Code Actions: \(context.onlyKinds.joined(separator: ", "))"
    }

    @discardableResult
    func retryCodeActionWorkspaceEditRequest(context: CodeActionRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit code action retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(.codeActions),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        do {
            let contextJSON = codeActionContextJSON(
                editor: tab.editCore.editor,
                startOffset: context.startOffset,
                endOffset: context.endOffset,
                onlyKinds: context.onlyKinds
            )
            _ = try tab.editCore.editor.lspRequestCodeAction(
                startOffset: context.startOffset,
                endOffset: context.endOffset,
                contextJSON: contextJSON
            )
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            codeActionContext = context
            startCodeActionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelCodeActionUI()
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .codeActions,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    func renameWorkspaceEditRequestRetryOwner(
        context: RenameRequestContext
    ) -> AttoWorkspaceEditRequestRetryOwner {
        AttoWorkspaceEditRequestRetryOwner(label: "Rename: \(context.newName)") { [weak self] in
            guard let self else { return false }
            return self.retryRenameWorkspaceEditRequest(context: context)
        }
    }

    @discardableResult
    func retryRenameWorkspaceEditRequest(context: RenameRequestContext) -> Bool {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else {
            setTransientStatusText("WorkspaceEdit rename retry source unavailable")
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(.rename),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        if selectedTabID != tab.id {
            selectTab(id: tab.id)
        }

        do {
            _ = try tab.editCore.editor.lspRequestRename(
                logicalLine: context.logicalLine,
                logicalColumn: context.logicalColumn,
                newName: context.newName
            )
            renameContext = context
            startRenamePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelRenameUI()
            if context.showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        .rename,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }
}
