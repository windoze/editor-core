import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP hierarchy quick panels

    @discardableResult
    func showIncomingCallsInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .callIncoming)
    }

    @discardableResult
    func showOutgoingCallsInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .callOutgoing)
    }

    @discardableResult
    func showTypeSupertypesInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .typeSupertypes)
    }

    @discardableResult
    func showTypeSubtypesInActiveTab() -> Bool {
        requestLspHierarchyAtPrimaryCaret(kind: .typeSubtypes)
    }

    @discardableResult
    func showHierarchyPanelInActiveTab() -> Bool {
        guard let snapshot = hierarchyPanelSnapshot, snapshot.entries.isEmpty == false else {
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

        guard let window = view.window else {
            navigateToLspTarget(snapshot.entries[0].target)
            return true
        }

        let controller = hierarchyPanelController ?? makeHierarchyPanelController()
        hierarchyPanelController = controller
        return controller.show(
            relativeTo: window,
            snapshot: snapshot,
            metadataText: lspResultEventPanelMetadata(
                countText: AttoLspResultMetadataText.count(snapshot.entries.count, singular: "result", plural: "results"),
                family: "hierarchy"
            )
        )
    }

    @discardableResult
    func refreshHierarchyPanelInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let request = hierarchyPanelRefreshRequest, request.tabID == tab.id else {
            NSSound.beep()
            return false
        }

        return requestHierarchyChildren(
            for: request.item,
            kind: request.kind,
            tab: tab,
            showFeedback: showFeedback,
            resultMode: .refresh
        )
    }

    @discardableResult
    func expandSelectedHierarchyPanelResultInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let request = hierarchyPanelRefreshRequest, request.tabID == tab.id else {
            setTransientStatusText("Hierarchy expand: no refresh context")
            NSSound.beep()
            return false
        }
        guard let entry = hierarchyPanelController?.selectedEntry ?? hierarchyPanelSnapshot?.entries.first,
              let item = hierarchyExpansionItem(from: entry)
        else {
            setTransientStatusText("Hierarchy expand: no expandable result")
            NSSound.beep()
            return false
        }

        return requestHierarchyChildren(
            for: item,
            kind: request.kind,
            tab: tab,
            showFeedback: showFeedback
        )
    }

    func requestLspHierarchyAtPrimaryCaret(
        kind: LspHierarchyRequestKind,
        showFeedback: Bool = true
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            let message = AttoLspResultFeedback.unavailable(kind.feedbackFeature)
            markCurrentLspEventResultError(family: "hierarchy", message: message)
            if showFeedback {
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let position: (line: UInt32, column: UInt32)
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        } catch {
            let message = AttoLspResultFeedback.failed(
                kind.feedbackFeature,
                errorDescription: "Hierarchy position could not be computed.\n\(error.localizedDescription)"
            )
            markCurrentLspEventResultError(family: "hierarchy", message: message)
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

        do {
            if kind.isCallHierarchy {
                _ = try tab.editCore.editor.lspRequestPrepareCallHierarchy(
                    logicalLine: position.line,
                    logicalColumn: position.column
                )
            } else {
                _ = try tab.editCore.editor.lspRequestPrepareTypeHierarchy(
                    logicalLine: position.line,
                    logicalColumn: position.column
                )
            }
        } catch {
            cancelHierarchyUI()
            let message = AttoLspResultFeedback.requestFailed(
                kind.feedbackFeature,
                errorDescription: error.localizedDescription
            )
            markCurrentLspEventResultError(family: "hierarchy", message: message)
            if showFeedback {
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        hierarchyPrepareContext = HierarchyPrepareContext(
            tabID: tab.id,
            kind: kind,
            showFeedback: showFeedback
        )
        startHierarchyPreparePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    func startHierarchyPreparePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        hierarchyPreparePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.hierarchyPrepareContext, ctx.tabID == tabID else {
                self.cancelHierarchyUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.timeout(ctx.kind.feedbackFeature)
                self.cancelHierarchyUI()
                self.markCurrentLspEventResultError(family: "hierarchy", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHierarchyUI()
                return
            }

            let items: [AttoLspHierarchyParser.Item]
            do {
                if ctx.kind.isCallHierarchy {
                    guard let result = try tab.editCore.editor.lspTakeLastPrepareCallHierarchyResult() else {
                        return
                    }
                    items = AttoLspHierarchyParser.prepareCallItems(from: result)
                } else {
                    guard let result = try tab.editCore.editor.lspTakeLastPrepareTypeHierarchyResult() else {
                        return
                    }
                    items = AttoLspHierarchyParser.prepareTypeItems(from: result)
                }
            } catch {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.failed(
                    ctx.kind.feedbackFeature,
                    errorDescription: error.localizedDescription
                )
                self.cancelHierarchyUI()
                self.markCurrentLspEventResultError(family: "hierarchy", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }

            self.hierarchyPreparePollTimer?.cancel()
            self.hierarchyPreparePollTimer = nil
            self.hierarchyPrepareContext = nil
            self.handleHierarchyPrepareItems(
                items,
                kind: ctx.kind,
                tab: tab,
                showFeedback: ctx.showFeedback
            )
            timer.cancel()
        }

        hierarchyPreparePollTimer = timer
        timer.resume()
    }

    func handleHierarchyPrepareItems(
        _ items: [AttoLspHierarchyParser.Item],
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab,
        showFeedback: Bool
    ) {
        guard items.isEmpty == false else {
            cancelHierarchyUI()
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(kind.feedbackFeature), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return
        }

        if items.count == 1 {
            _ = requestHierarchyChildren(for: items[0], kind: kind, tab: tab, showFeedback: showFeedback)
            return
        }

        showHierarchyRootResults(items, kind: kind, tab: tab, showFeedback: showFeedback)
    }

    func showHierarchyRootResults(
        _ items: [AttoLspHierarchyParser.Item],
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab,
        showFeedback: Bool
    ) {
        guard let window = view.window else {
            if let first = items.first {
                _ = requestHierarchyChildren(for: first, kind: kind, tab: tab, showFeedback: showFeedback)
            }
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.hierarchy.root.\(idx)",
                title: displayTitle(for: item)
            ) { [weak self, weak tab] in
                guard let self, let tab, self.activeTab?.id == tab.id else { return }
                _ = self.requestHierarchyChildren(for: item, kind: kind, tab: tab, showFeedback: showFeedback)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.HierarchyRoots",
            commandsProvider: { commands }
        )
        hierarchyResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter hierarchy roots...")
    }

    @discardableResult
    func requestHierarchyChildren(
        for item: AttoLspHierarchyParser.Item,
        kind: LspHierarchyRequestKind,
        tab: AttoEditorTab,
        showFeedback: Bool,
        resultMode: HierarchyChildrenResultMode = .interactive
    ) -> Bool {
        hierarchyResultsController?.hide()
        hierarchyResultsController = nil

        do {
            switch kind {
            case .callIncoming:
                _ = try tab.editCore.editor.lspRequestCallHierarchyIncomingCalls(itemJSON: item.requestJSON)
            case .callOutgoing:
                _ = try tab.editCore.editor.lspRequestCallHierarchyOutgoingCalls(itemJSON: item.requestJSON)
            case .typeSupertypes:
                _ = try tab.editCore.editor.lspRequestTypeHierarchySupertypes(itemJSON: item.requestJSON)
            case .typeSubtypes:
                _ = try tab.editCore.editor.lspRequestTypeHierarchySubtypes(itemJSON: item.requestJSON)
            }
        } catch {
            cancelHierarchyUI()
            let message = AttoLspResultFeedback.requestFailed(
                kind.feedbackFeature,
                errorDescription: error.localizedDescription
            )
            markCurrentLspEventResultError(family: "hierarchy", message: message)
            if showFeedback {
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        hierarchyChildrenContext = HierarchyChildrenContext(
            tabID: tab.id,
            kind: kind,
            item: item,
            showFeedback: showFeedback,
            resultMode: resultMode
        )
        startHierarchyChildrenPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    func startHierarchyChildrenPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        hierarchyChildrenPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.hierarchyChildrenContext, ctx.tabID == tabID else {
                self.cancelHierarchyUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.timeout(ctx.kind.feedbackFeature)
                self.cancelHierarchyUI()
                self.markCurrentLspEventResultError(family: "hierarchy", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHierarchyUI()
                return
            }

            let entries: [AttoLspHierarchyParser.Entry]
            do {
                switch ctx.kind {
                case .callIncoming:
                    guard let result = try tab.editCore.editor.lspTakeLastCallHierarchyIncomingCallsResult() else {
                        return
                    }
                    entries = AttoLspHierarchyParser.incomingCalls(from: result)
                case .callOutgoing:
                    guard let result = try tab.editCore.editor.lspTakeLastCallHierarchyOutgoingCallsResult() else {
                        return
                    }
                    entries = AttoLspHierarchyParser.outgoingCalls(from: result)
                case .typeSupertypes:
                    guard let result = try tab.editCore.editor.lspTakeLastTypeHierarchySupertypesResult() else {
                        return
                    }
                    entries = AttoLspHierarchyParser.typeHierarchyEntries(from: result)
                case .typeSubtypes:
                    guard let result = try tab.editCore.editor.lspTakeLastTypeHierarchySubtypesResult() else {
                        return
                    }
                    entries = AttoLspHierarchyParser.typeHierarchyEntries(from: result)
                }
            } catch {
                let showFeedback = ctx.showFeedback
                let message = AttoLspResultFeedback.failed(
                    ctx.kind.feedbackFeature,
                    errorDescription: error.localizedDescription
                )
                self.cancelHierarchyUI()
                self.markCurrentLspEventResultError(family: "hierarchy", message: message)
                if showFeedback {
                    self.presentLspResultFeedback(message, in: editorView)
                }
                NSSound.beep()
                return
            }

            self.hierarchyChildrenPollTimer?.cancel()
            self.hierarchyChildrenPollTimer = nil
            self.hierarchyChildrenContext = nil
            let refreshRequest = HierarchyPanelRefreshRequest(
                tabID: ctx.tabID,
                kind: ctx.kind,
                item: ctx.item
            )
            switch ctx.resultMode {
            case .interactive:
                _ = self.showHierarchyResults(
                    entries,
                    placeholder: ctx.kind.resultPlaceholder,
                    feedbackFeature: ctx.kind.feedbackFeature,
                    showFeedback: ctx.showFeedback,
                    refreshRequest: refreshRequest
                )
            case .refresh:
                _ = self.finishHierarchyRefresh(
                    entries,
                    kind: ctx.kind,
                    refreshRequest: refreshRequest,
                    showFeedback: ctx.showFeedback,
                    editorView: editorView
                )
            }
            timer.cancel()
        }

        hierarchyChildrenPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showHierarchyResults(
        _ entries: [AttoLspHierarchyParser.Entry],
        placeholder: String,
        feedbackFeature: AttoLspResultFeedback.Feature,
        showFeedback: Bool,
        refreshRequest: HierarchyPanelRefreshRequest? = nil
    ) -> Bool {
        guard entries.isEmpty == false else {
            if showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(AttoLspResultFeedback.empty(feedbackFeature), in: editorView)
            }
            NSSound.beep()
            return false
        }

        recordHierarchyPanelSnapshot(
            entries: entries,
            title: hierarchyPanelTitle(placeholder: placeholder, feedbackFeature: feedbackFeature),
            refreshRequest: refreshRequest
        )

        guard let window = view.window else {
            navigateToLspTarget(entries[0].target)
            return true
        }

        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.hierarchy.\(idx)",
                title: displayTitle(for: entry)
            ) { [weak self] in
                self?.navigateToLspTarget(entry.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.HierarchyResults",
            commandsProvider: { commands }
        )
        hierarchyResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
        return true
    }

    @discardableResult
    func finishHierarchyRefresh(
        _ entries: [AttoLspHierarchyParser.Entry],
        kind: LspHierarchyRequestKind,
        refreshRequest: HierarchyPanelRefreshRequest?,
        showFeedback: Bool,
        editorView: EditorCoreSkiaView?
    ) -> Bool {
        guard entries.isEmpty == false else {
            if showFeedback, let editorView {
                presentLspResultFeedback(AttoLspResultFeedback.empty(kind.feedbackFeature), in: editorView)
            }
            NSSound.beep()
            return false
        }

        recordHierarchyPanelSnapshot(
            entries: entries,
            title: hierarchyPanelTitle(
                placeholder: kind.resultPlaceholder,
                feedbackFeature: kind.feedbackFeature
            ),
            refreshRequest: refreshRequest
        )

        if showFeedback, let editorView {
            presentLspResultFeedback(
                AttoLspResultFeedback.refreshed(
                    kind.feedbackFeature,
                    count: entries.count,
                    singular: "result",
                    plural: "results"
                ),
                in: editorView
            )
        }
        return true
    }

    func recordHierarchyPanelSnapshot(
        entries: [AttoLspHierarchyParser.Entry],
        title: String,
        refreshRequest: HierarchyPanelRefreshRequest? = nil
    ) {
        let snapshot = AttoHierarchyPanelController.Snapshot(title: title, entries: entries)
        hierarchyPanelSnapshot = snapshot
        hierarchyPanelRefreshRequest = refreshRequest
        let event = lspResultEventStream.record(
            family: "hierarchy",
            title: title,
            payload: .hierarchy(title: title, itemCount: entries.count)
        )
        lspWorkbenchAuxiliaryHistoryStore.record(
            event: event,
            payload: .hierarchy(snapshot)
        )
        if hierarchyPanelController?.isVisible == true {
            hierarchyPanelController?.update(
                snapshot: snapshot,
                metadataText: lspResultEventPanelMetadata(
                    countText: AttoLspResultMetadataText.count(entries.count, singular: "result", plural: "results"),
                    family: "hierarchy"
                )
            )
        }
        updateVisibleLspWorkbenchPanel()
    }

    func makeHierarchyPanelController() -> AttoHierarchyPanelController {
        AttoHierarchyPanelController(
            titleForEntry: { [weak self] entry in
                self?.displayTitle(for: entry) ?? entry.name
            },
            onOpen: { [weak self] entry in
                self?.navigateToLspTarget(entry.target)
            },
            onExpand: { [weak self] entry in
                _ = self?.expandHierarchyPanelEntry(entry)
            }
        )
    }

    @discardableResult
    func expandHierarchyPanelEntry(_ entry: AttoLspHierarchyParser.Entry) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let request = hierarchyPanelRefreshRequest, request.tabID == tab.id else {
            setTransientStatusText("Hierarchy expand: no refresh context")
            NSSound.beep()
            return false
        }
        guard let item = hierarchyExpansionItem(from: entry) else {
            setTransientStatusText("Hierarchy expand: no expandable result")
            NSSound.beep()
            return false
        }
        return requestHierarchyChildren(for: item, kind: request.kind, tab: tab, showFeedback: true)
    }

    func hierarchyExpansionItem(from entry: AttoLspHierarchyParser.Entry) -> AttoLspHierarchyParser.Item? {
        guard let requestJSON = entry.requestJSON else { return nil }
        return AttoLspHierarchyParser.Item(
            name: entry.name,
            detail: entry.detail,
            kindLabel: entry.kindLabel,
            target: entry.target,
            requestJSON: requestJSON
        )
    }

    func hierarchyPanelTitle(
        placeholder: String,
        feedbackFeature: AttoLspResultFeedback.Feature
    ) -> String {
        switch placeholder {
        case "Filter incoming calls...":
            return "Incoming Calls"
        case "Filter outgoing calls...":
            return "Outgoing Calls"
        case "Filter supertypes...":
            return "Supertypes"
        case "Filter subtypes...":
            return "Subtypes"
        default:
            return feedbackFeature.statusTitle
        }
    }

    func displayTitle(for item: AttoLspHierarchyParser.Item) -> String {
        let detail = item.detail.map { " \($0)" } ?? ""
        let kind = item.kindLabel.map { " [\($0)]" } ?? ""
        let location = displayTitle(for: item.target)
        return "\(item.name)\(detail)\(kind) — \(location)"
    }

    func displayTitle(for entry: AttoLspHierarchyParser.Entry) -> String {
        let detail = entry.detail.map { " \($0)" } ?? ""
        let kind = entry.kindLabel.map { " [\($0)]" } ?? ""
        let ranges = entry.relatedRangeCount.map { count in
            count == 1 ? " (1 range)" : " (\(count) ranges)"
        } ?? ""
        let location = displayTitle(for: entry.target)
        return "\(entry.name)\(detail)\(kind)\(ranges) — \(location)"
    }
}
