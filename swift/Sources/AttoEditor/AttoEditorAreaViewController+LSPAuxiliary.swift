import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP auxiliary decorations

    @discardableResult
    func refreshInlayHintsInActiveTab(showFeedback: Bool = true) -> Bool {
        refreshAuxiliaryLspDecorationsInActiveTab(kind: .inlayHints, showFeedback: showFeedback)
    }

    @discardableResult
    func refreshDocumentLinksInActiveTab(showFeedback: Bool = true) -> Bool {
        refreshAuxiliaryLspDecorationsInActiveTab(kind: .documentLinks, showFeedback: showFeedback)
    }

    @discardableResult
    func showInlayHintsPanelInActiveTab() -> Bool {
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
        cancelAuxiliaryRefreshUI()
        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()

        let items = currentInlayHintItems(in: tab)
        guard items.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            return resolveInlayHintPanelItem(items[0])
        }

        let controller = inlayHintPanelController ?? makeInlayHintPanelController()
        inlayHintPanelController = controller
        return controller.show(relativeTo: window, items: items)
    }

    @discardableResult
    func showDocumentLinksPanelInActiveTab() -> Bool {
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
        cancelAuxiliaryRefreshUI()
        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()

        let items = currentDocumentLinkItems(in: tab)
        guard items.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            return openDocumentLinkPanelItem(items[0])
        }

        let controller = documentLinkPanelController ?? makeDocumentLinkPanelController()
        documentLinkPanelController = controller
        return controller.show(relativeTo: window, items: items)
    }

    @discardableResult
    func refreshAuxiliaryLspDecorationsInActiveTab(
        kind: AuxiliaryRefreshKind,
        showFeedback: Bool = true
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(kind.feedbackFeature),
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
        cancelAuxiliaryRefreshUI()
        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()

        do {
            switch kind {
            case .inlayHints:
                let scalarCount = try tab.editCore.editor.text().unicodeScalars.count
                guard scalarCount <= Int(UInt32.max) else {
                    throw NSError(
                        domain: "AttoEditor.LSP",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Document is too large for inlay hint range offsets."]
                    )
                }
                _ = try tab.editCore.editor.lspRequestInlayHints(
                    startOffset: 0,
                    endOffset: UInt32(scalarCount)
                )
            case .documentLinks:
                _ = try tab.editCore.editor.lspRequestDocumentLinks()
            }
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(
                        kind.feedbackFeature,
                        errorDescription: error.localizedDescription
                    ),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }

        auxiliaryRefreshContext = AuxiliaryRefreshContext(
            tabID: tab.id,
            kind: kind,
            showFeedback: showFeedback
        )
        tab.editCore.editorView.kickProcessingPoll()
        updateStatusBar()
        startAuxiliaryRefreshPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    func startAuxiliaryRefreshPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        auxiliaryRefreshPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.auxiliaryRefreshContext, ctx.tabID == tabID else {
                self.cancelAuxiliaryRefreshUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelAuxiliaryRefreshUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(feature), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelAuxiliaryRefreshUI()
                return
            }

            do {
                _ = try tab.editCore.editor.pollProcessing()
            } catch {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelAuxiliaryRefreshUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            let summary: (errorMessage: String?, count: Int)?
            do {
                switch ctx.kind {
                case .inlayHints:
                    guard let result = try tab.editCore.editor.lspTakeLastInlayHintsResult() else { return }
                    summary = (
                        Self.inlayHintResultErrorMessage(result),
                        Self.inlayHintResultCount(result)
                    )
                    if summary?.errorMessage == nil {
                        try tab.editCore.editor.lspApplyInlayHintsJSON(result.rawJSONString ?? "null")
                    }
                case .documentLinks:
                    guard let result = try tab.editCore.editor.lspTakeLastDocumentLinksResult() else { return }
                    summary = (
                        Self.documentLinkResultErrorMessage(result),
                        Self.documentLinkResultCount(result)
                    )
                    if summary?.errorMessage == nil {
                        try tab.editCore.editor.lspApplyDocumentLinksJSON(result.rawJSONString ?? "null")
                    }
                }
            } catch {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelAuxiliaryRefreshUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            guard let summary else { return }
            let showFeedback = ctx.showFeedback
            let kind = ctx.kind
            self.cancelAuxiliaryRefreshUI()

            if let errorMessage = summary.errorMessage {
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(kind.feedbackFeature, errorDescription: errorMessage),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }

            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            self.derivedStateStore.refreshActive(editor: tab.editCore.editor)
            if kind == .inlayHints {
                self.updateVisibleInlayHintPanel(for: tab)
            } else if kind == .documentLinks {
                self.updateVisibleDocumentLinkPanel(for: tab)
            }
            self.updateStatusBar()

            guard showFeedback else { return }
            if summary.count == 0 {
                self.presentLspResultFeedback(AttoLspResultFeedback.empty(kind.feedbackFeature), in: editorView)
            } else {
                self.presentLspResultFeedback(
                    AttoLspResultFeedback.refreshed(
                        kind.feedbackFeature,
                        count: summary.count,
                        singular: kind.singularNoun,
                        plural: kind.pluralNoun
                    ),
                    in: editorView
                )
            }
        }

        auxiliaryRefreshPollTimer = timer
        timer.resume()
    }

    static func inlayHintResultCount(_ result: EcuLspInlayHintResult) -> Int {
        result.hints.count
    }

    static func inlayHintResultErrorMessage(_ result: EcuLspInlayHintResult) -> String? {
        result.error?.message
    }

    static func documentLinkResultCount(_ result: EcuLspDocumentLinkResult) -> Int {
        result.links.count
    }

    static func documentLinkResultErrorMessage(_ result: EcuLspDocumentLinkResult) -> String? {
        result.error?.message
    }

    @discardableResult
    func handleInlayHintClick(json: String, tabID: UUID, editorView: EditorCoreSkiaView) -> Bool {
        guard activeTab?.id == tabID else { return false }
        return requestInlayHintResolve(json: json, tabID: tabID, editorView: editorView)
    }

    @discardableResult
    func requestInlayHintResolve(
        json: String,
        tabID: UUID,
        editorView: EditorCoreSkiaView,
        showFeedback: Bool = true
    ) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        guard (try? editorView.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.inlayHintResolve), in: editorView)
            }
            NSSound.beep()
            return false
        }

        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()

        do {
            _ = try editorView.editor.lspRequestInlayHintResolve(hintJSON: json)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.inlayHintResolve, errorDescription: error.localizedDescription),
                    in: editorView
                )
            }
            NSSound.beep()
            return false
        }

        inlayHintResolveContext = InlayHintResolveContext(tabID: tabID, showFeedback: showFeedback)
        editorView.kickProcessingPoll()
        updateStatusBar()
        startInlayHintResolvePollTimer(tabID: tabID, editorView: editorView)
        return true
    }

    func startInlayHintResolvePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        inlayHintResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.inlayHintResolveContext, ctx.tabID == tabID else {
                self.cancelInlayHintResolveUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelInlayHintResolveUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.inlayHintResolve), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard self.activeTab?.id == tabID else {
                self.cancelInlayHintResolveUI()
                return
            }

            let result: EcuLspInlayHint?
            do {
                result = try editorView.editor.lspTakeLastInlayHintResolveResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelInlayHintResolveUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.inlayHintResolve, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            self.cancelInlayHintResolveUI()
            guard self.consumeResolvedInlayHint(result, in: editorView, showFeedback: showFeedback) else {
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.empty(.inlayHintResolve), in: editorView)
                }
                NSSound.beep()
                return
            }
        }

        inlayHintResolvePollTimer = timer
        timer.resume()
    }

    @discardableResult
    func consumeResolvedInlayHint(
        _ hint: EcuLspInlayHint,
        in editorView: EditorCoreSkiaView,
        showFeedback: Bool
    ) -> Bool {
        var didHandle = false
        var attemptedEdit = false

        if let tab = activeTab {
            let documentURI = projectedFileURL(for: tab).absoluteString
            if let workspaceEditJSON = AttoLspInlayHintResolver.workspaceEditJSON(
                for: hint,
                documentURI: documentURI
            ) {
                attemptedEdit = true
                didHandle = applyWorkspaceEditJSONToActiveTab(
                    workspaceEditJSON,
                    documentURI: documentURI
                ) || didHandle
            }
        }

        if let command = AttoLspInlayHintResolver.command(for: hint) {
            didHandle = requestExecuteCommandJSON(command.commandJSON, commandTitle: command.title) || didHandle
        }

        if let text = AttoLspInlayHintResolver.displayText(for: hint) {
            if showFeedback {
                setTransientStatusText("Inlay hint resolve: resolved")
                showWorkspaceEditPopover(text: text, in: editorView)
            }
            didHandle = true
        }

        return didHandle || attemptedEdit
    }

    @discardableResult
    func handleDocumentLinkClick(json: String, tabID: UUID, editorView: EditorCoreSkiaView) -> Bool {
        guard activeTab?.id == tabID else { return false }
        if let url = EditorCoreSkiaView.documentLinkTargetURL(from: json) {
            editorView.onOpenURL(url)
            return true
        }
        return requestDocumentLinkResolve(json: json, tabID: tabID, editorView: editorView)
    }

    @discardableResult
    func requestDocumentLinkResolve(json: String, tabID: UUID, editorView: EditorCoreSkiaView, showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab, tab.id == tabID else {
            NSSound.beep()
            return false
        }

        guard (try? editorView.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.documentLinkResolve), in: editorView)
            }
            NSSound.beep()
            return false
        }

        cancelInlayHintResolveUI()
        cancelDocumentLinkResolveUI()

        do {
            _ = try editorView.editor.lspRequestDocumentLinkResolve(linkJSON: json)
        } catch {
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.documentLinkResolve, errorDescription: error.localizedDescription),
                    in: editorView
                )
            }
            NSSound.beep()
            return false
        }

        documentLinkResolveContext = DocumentLinkResolveContext(tabID: tabID, showFeedback: showFeedback)
        editorView.kickProcessingPoll()
        updateStatusBar()
        startDocumentLinkResolvePollTimer(tabID: tabID, editorView: editorView)
        return true
    }

    func startDocumentLinkResolvePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        documentLinkResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.documentLinkResolveContext, ctx.tabID == tabID else {
                self.cancelDocumentLinkResolveUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentLinkResolveUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.documentLinkResolve), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard self.activeTab?.id == tabID else {
                self.cancelDocumentLinkResolveUI()
                return
            }

            let result: EcuLspDocumentLink?
            do {
                result = try editorView.editor.lspTakeLastDocumentLinkResolveResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelDocumentLinkResolveUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.documentLinkResolve, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            self.cancelDocumentLinkResolveUI()

            guard let target = result.target,
                  let url = EditorCoreSkiaView.documentLinkTargetURL(fromTarget: target)
            else {
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.empty(.documentLinkResolve), in: editorView)
                }
                NSSound.beep()
                return
            }

            editorView.onOpenURL(url)
        }

        documentLinkResolvePollTimer = timer
        timer.resume()
    }

    private func currentInlayHintItems(in tab: AttoEditorTab) -> [AttoLspInlayHintParser.Item] {
        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        return AttoLspInlayHintParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
    }

    private func makeInlayHintPanelController() -> AttoInlayHintPanelController {
        AttoInlayHintPanelController(
            titleForItem: { [weak self] item in
                guard let self, let tab = self.activeTab else { return item.title }
                return self.displayTitle(for: item, in: tab)
            },
            onResolve: { [weak self] item in
                _ = self?.resolveInlayHintPanelItem(item)
            }
        )
    }

    private func displayTitle(for item: AttoLspInlayHintParser.Item, in tab: AttoEditorTab) -> String {
        let documentURL = projectedFileURL(for: tab)
        let location: String? = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start)
                return "\(documentURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return documentURL.lastPathComponent
            }
        }()
        return AttoLspInlayHintParser.displayTitle(for: item, location: location)
    }

    private func resolveInlayHintPanelItem(_ item: AttoLspInlayHintParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return requestInlayHintResolve(
            json: item.hintJSON,
            tabID: tab.id,
            editorView: tab.editCore.editorView
        )
    }

    private func updateVisibleInlayHintPanel(for tab: AttoEditorTab) {
        guard let controller = inlayHintPanelController, controller.isVisible else { return }
        controller.update(items: currentInlayHintItems(in: tab))
    }

    private func currentDocumentLinkItems(in tab: AttoEditorTab) -> [AttoLspDocumentLinkParser.Item] {
        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        return AttoLspDocumentLinkParser.items(fromDecorationsSnapshot: derivedStateStore.active.decorations)
    }

    private func makeDocumentLinkPanelController() -> AttoDocumentLinkPanelController {
        AttoDocumentLinkPanelController(
            titleForItem: { [weak self] item in
                guard let self, let tab = self.activeTab else { return item.title }
                return self.displayTitle(for: item, in: tab)
            },
            onOpen: { [weak self] item in
                _ = self?.openDocumentLinkPanelItem(item)
            }
        )
    }

    private func displayTitle(for item: AttoLspDocumentLinkParser.Item, in tab: AttoEditorTab) -> String {
        let documentURL = projectedFileURL(for: tab)
        let location: String? = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: item.range.start)
                return "\(documentURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return documentURL.lastPathComponent
            }
        }()
        return AttoLspDocumentLinkParser.displayTitle(for: item, location: location)
    }

    private func openDocumentLinkPanelItem(_ item: AttoLspDocumentLinkParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return handleDocumentLinkClick(
            json: item.linkJSON,
            tabID: tab.id,
            editorView: tab.editCore.editorView
        )
    }

    private func updateVisibleDocumentLinkPanel(for tab: AttoEditorTab) {
        guard let controller = documentLinkPanelController, controller.isVisible else { return }
        controller.update(items: currentDocumentLinkItems(in: tab))
    }
}
