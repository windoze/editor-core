import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP symbols quick panels

    @discardableResult
    func showDocumentSymbolsInActiveTab() -> Bool {
        requestLspSymbols(kind: .document)
    }

    @discardableResult
    func showWorkspaceSymbolsInActiveTab(query: String = "") -> Bool {
        requestLspSymbols(kind: .workspace(query: query))
    }

    @discardableResult
    func promptWorkspaceSymbolsInActiveTab(initialQuery: String = "") -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            presentLspResultFeedback(AttoLspResultFeedback.unavailable(.workspaceSymbols), in: tab.editCore.editorView)
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return showWorkspaceSymbolsInActiveTab(query: initialQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        workspaceSymbolSearchQuery = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceSymbolSearchResults = []

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.WorkspaceSymbolSearch",
            filtersCommands: false,
            searchTextDidChange: { [weak self] query in
                self?.scheduleWorkspaceSymbolSearch(query: query)
            },
            commandsProvider: { [weak self] in
                self?.workspaceSymbolSearchCommands() ?? []
            }
        )
        lspSymbolResultsController = controller
        controller.show(
            relativeTo: window,
            placeholder: "Search workspace symbols...",
            initialQuery: workspaceSymbolSearchQuery
        )
        requestWorkspaceSymbolSearch(query: workspaceSymbolSearchQuery)
        return true
    }

    func workspaceSymbolSearchCommands() -> [AttoCommandPaletteCommand] {
        let query = workspaceSymbolSearchQuery
        let symbols = workspaceSymbolSearchResults
        return symbols.enumerated().map { idx, symbol in
            AttoCommandPaletteCommand(
                id: "lsp.workspace_symbol_search.\(idx)",
                title: displayTitle(for: symbol),
                group: AttoLspSymbolParser.kindGroupLabel(for: symbol)
            ) { [weak self] in
                self?.openWorkspaceSymbolSearchResult(symbol, symbols: symbols, query: query)
            }
        }
    }

    func scheduleWorkspaceSymbolSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceSymbolSearchQuery = trimmedQuery
        workspaceSymbolSearchResults = []
        lspSymbolResultsController?.reloadCommands()

        workspaceSymbolSearchDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.18)
        timer.setEventHandler { [weak self] in
            self?.requestWorkspaceSymbolSearch(query: trimmedQuery)
        }
        workspaceSymbolSearchDebounceTimer = timer
        timer.resume()
    }

    func requestWorkspaceSymbolSearch(query: String) {
        guard let tab = activeTab else {
            cancelSymbolUI()
            return
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            workspaceSymbolSearchResults = []
            lspSymbolResultsController?.reloadCommands()
            return
        }

        workspaceSymbolSearchDebounceTimer?.cancel()
        workspaceSymbolSearchDebounceTimer = nil
        workspaceSymbolSearchPollTimer?.cancel()

        workspaceSymbolSearchRequestID += 1
        let requestID = workspaceSymbolSearchRequestID
        workspaceSymbolSearchContext = WorkspaceSymbolSearchContext(
            tabID: tab.id,
            requestID: requestID,
            query: query
        )

        do {
            _ = try tab.editCore.editor.lspRequestWorkspaceSymbols(query: query)
        } catch {
            workspaceSymbolSearchContext = nil
            workspaceSymbolSearchResults = []
            lspSymbolResultsController?.reloadCommands()
            return
        }

        startWorkspaceSymbolSearchPollTimer(tabID: tab.id, requestID: requestID)
    }

    func startWorkspaceSymbolSearchPollTimer(tabID: UUID, requestID: Int) {
        workspaceSymbolSearchPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.workspaceSymbolSearchContext,
                  ctx.tabID == tabID,
                  ctx.requestID == requestID
            else {
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.workspaceSymbolSearchPollTimer?.cancel()
                self.workspaceSymbolSearchPollTimer = nil
                self.workspaceSymbolSearchContext = nil
                timer.cancel()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSymbolUI()
                timer.cancel()
                return
            }

            let result: EcuLspWorkspaceSymbolResult?
            do {
                result = try tab.editCore.editor.lspTakeLastWorkspaceSymbolsResult()
            } catch {
                return
            }
            guard let result else { return }

            self.workspaceSymbolSearchPollTimer?.cancel()
            self.workspaceSymbolSearchPollTimer = nil
            self.workspaceSymbolSearchContext = nil
            if ctx.query == self.workspaceSymbolSearchQuery {
                self.workspaceSymbolSearchResults = AttoLspSymbolParser.workspaceSymbols(fromResult: result)
                self.lspSymbolResultsController?.reloadCommands()
            }
            timer.cancel()
        }

        workspaceSymbolSearchPollTimer = timer
        timer.resume()
    }

    func openWorkspaceSymbolSearchResult(
        _ symbol: AttoLspSymbolParser.Symbol,
        symbols: [AttoLspSymbolParser.Symbol],
        query: String
    ) {
        let snapshot = LspSymbolResultSnapshot(
            title: workspaceSymbolTitle(query: query),
            symbols: symbols,
            placeholder: "Search workspace symbols..."
        )
        recordLspSymbolResultSnapshot(snapshot)
        navigateToLspTarget(symbol.target)
    }

    func requestLspSymbols(kind: LspSymbolRequestKind) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            let message = AttoLspResultFeedback.unavailable(kind.feedbackFeature)
            markCurrentLspSymbolResultError(message)
            presentLspResultFeedback(message, in: tab.editCore.editorView)
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        symbolContext = SymbolRequestContext(tabID: tab.id, kind: kind)

        do {
            switch kind {
            case .document:
                _ = try tab.editCore.editor.lspRequestDocumentSymbols()
            case .workspace(let query):
                _ = try tab.editCore.editor.lspRequestWorkspaceSymbols(query: query)
            }
        } catch {
            cancelSymbolUI()
            let message = AttoLspResultFeedback.requestFailed(
                kind.feedbackFeature,
                errorDescription: error.localizedDescription
            )
            markCurrentLspSymbolResultError(message)
            presentLspResultFeedback(message, in: tab.editCore.editorView)
            NSSound.beep()
            return false
        }

        startSymbolPollTimer(tabID: tab.id)
        return true
    }

    func startSymbolPollTimer(tabID: UUID) {
        symbolPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.symbolContext, ctx.tabID == tabID else {
                self.cancelSymbolUI()
                return
            }

            if remainingTicks <= 0 {
                let tab = self.activeTab
                let message = AttoLspResultFeedback.timeout(ctx.kind.feedbackFeature)
                self.cancelSymbolUI()
                if let tab, tab.id == tabID {
                    self.markCurrentLspSymbolResultError(message)
                    self.presentLspResultFeedback(message, in: tab.editCore.editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSymbolUI()
                return
            }

            do {
                switch ctx.kind {
                case .document:
                    guard let result = try tab.editCore.editor.lspTakeLastDocumentSymbolsResult() else {
                        return
                    }
                    self.cancelSymbolUI()
                    _ = self.handleLspDocumentSymbolResult(result, tab: tab)
                    timer.cancel()
                case .workspace(let query):
                    guard let result = try tab.editCore.editor.lspTakeLastWorkspaceSymbolsResult() else {
                        return
                    }
                    self.cancelSymbolUI()
                    _ = self.handleLspWorkspaceSymbolResult(result, query: query, tab: tab)
                    timer.cancel()
                }
            } catch {
                let message = AttoLspResultFeedback.failed(
                    ctx.kind.feedbackFeature,
                    errorDescription: error.localizedDescription
                )
                self.cancelSymbolUI()
                self.markCurrentLspSymbolResultError(message)
                self.presentLspResultFeedback(message, in: tab.editCore.editorView)
                NSSound.beep()
                return
            }
        }

        symbolPollTimer = timer
        timer.resume()
    }

    @discardableResult
    func showDocumentSymbolResultJSONInActiveTab(_ json: String) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return handleLspSymbolResultJSON(json, kind: .document, tab: tab)
    }

    @discardableResult
    func showWorkspaceSymbolResultJSONInActiveTab(_ json: String, query: String = "") -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return handleLspSymbolResultJSON(json, kind: .workspace(query: query), tab: tab)
    }

    @discardableResult
    func showLastLspSymbolResults() -> Bool {
        guard let entry = lspSymbolResultStore.currentEntry, entry.snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        return openLspSymbolEntry(entry)
    }

    @discardableResult
    func showLspSymbolHistory() -> Bool {
        guard lspSymbolResultStore.historyEntries.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            guard let entry = lspSymbolResultStore.historyEntries.last else { return false }
            return openLspSymbolEntry(entry)
        }

        let entries = Array(lspSymbolResultStore.historyEntries.reversed())
        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.symbol_history.\(idx)",
                title: entry.title
            ) { [weak self] in
                _ = self?.openLspSymbolEntry(entry)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.SymbolHistory",
            commandsProvider: { commands }
        )
        lspSymbolResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter symbol history...")
        return true
    }

    @discardableResult
    func showLspSymbolPanel() -> Bool {
        guard let entry = lspSymbolResultStore.currentEntry, entry.snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return openLspSymbolEntry(entry)
        }
        let controller = lspSymbolPanelController ?? AttoLspSymbolPanelController(
            titleForSymbol: { [weak self] symbol in
                self?.displayTitle(for: symbol) ?? symbol.name
            },
            onOpen: { [weak self] target in
                self?.navigateToLspTarget(target)
            }
        )
        lspSymbolPanelController = controller
        return controller.show(relativeTo: window, entry: entry)
    }

    @discardableResult
    func showWorkspaceOutlinePanel() -> Bool {
        let snapshot = workspaceOutlineSymbolSnapshot()
        guard snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }

        let entry = lspSymbolResultStore.makeCurrent(
            snapshot,
            family: "symbols",
            title: workspaceOutlineHistoryTitle(for: workspaceOutlineStore.snapshot)
        )
        lspSymbolPanelController?.update(entry: entry)
        updateVisibleLspWorkbenchPanel()

        guard let window = view.window else {
            navigateToLspTarget(snapshot.symbols[0].target)
            return true
        }
        let controller = lspSymbolPanelController ?? AttoLspSymbolPanelController(
            titleForSymbol: { [weak self] symbol in
                self?.displayTitle(for: symbol) ?? symbol.name
            },
            onOpen: { [weak self] target in
                self?.navigateToLspTarget(target)
            }
        )
        lspSymbolPanelController = controller
        return controller.show(relativeTo: window, entry: entry)
    }

    func handleLspDocumentSymbolResult(
        _ result: EcuLspDocumentSymbolResult,
        tab: AttoEditorTab
    ) -> Bool {
        let rawJSON = result.rawJSONString
        if let rawJSON {
            try? tab.editCore.editor.lspApplyDocumentSymbolsJSON(rawJSON)
            applyCoreDocumentSymbols(tab: tab, json: rawJSON)
        }
        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let text = (try? tab.editCore.editor.text()) ?? ""
        let documentURI = projectedFileURL(for: tab).absoluteString
        let typedSnapshotSymbols = AttoLspSymbolParser.documentSymbols(
            snapshot: derivedStateStore.active.documentSymbols,
            documentURI: documentURI,
            documentText: text
        )
        let symbols = typedSnapshotSymbols.isEmpty
            ? AttoLspSymbolParser.documentSymbols(fromResult: result, documentURI: documentURI)
            : typedSnapshotSymbols
        updateWorkspaceOutline(tab: tab, documentText: text, symbols: symbols)
        return finishLspSymbolResult(
            symbols,
            kind: .document,
            title: "Document Symbols",
            placeholder: "Filter document symbols...",
            tab: tab
        )
    }

    func handleLspWorkspaceSymbolResult(
        _ result: EcuLspWorkspaceSymbolResult,
        query: String,
        tab: AttoEditorTab
    ) -> Bool {
        finishLspSymbolResult(
            AttoLspSymbolParser.workspaceSymbols(fromResult: result),
            kind: .workspace(query: query),
            title: workspaceSymbolTitle(query: query),
            placeholder: "Filter workspace symbols...",
            tab: tab
        )
    }

    func handleLspSymbolResultJSON(_ json: String, kind: LspSymbolRequestKind, tab: AttoEditorTab) -> Bool {
        let symbols: [AttoLspSymbolParser.Symbol]
        let placeholder: String
        let title: String

        switch kind {
        case .document:
            try? tab.editCore.editor.lspApplyDocumentSymbolsJSON(json)
            applyCoreDocumentSymbols(tab: tab, json: json)
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            let text = (try? tab.editCore.editor.text()) ?? ""
            let documentURI = projectedFileURL(for: tab).absoluteString
            let typedSymbols = AttoLspSymbolParser.documentSymbols(
                snapshot: derivedStateStore.active.documentSymbols,
                documentURI: documentURI,
                documentText: text
            )
            if typedSymbols.isEmpty {
                symbols = AttoLspSymbolParser.documentSymbols(
                    fromResultJSON: json,
                    documentURI: documentURI
                )
            } else {
                symbols = typedSymbols
            }
            placeholder = "Filter document symbols..."
            title = "Document Symbols"

        case .workspace(let query):
            symbols = AttoLspSymbolParser.workspaceSymbols(fromResultJSON: json)
            placeholder = "Filter workspace symbols..."
            title = workspaceSymbolTitle(query: query)
        }

        if case .document = kind {
            let text = (try? tab.editCore.editor.text()) ?? ""
            updateWorkspaceOutline(tab: tab, documentText: text, symbols: symbols)
        }
        return finishLspSymbolResult(symbols, kind: kind, title: title, placeholder: placeholder, tab: tab)
    }

    func updateWorkspaceOutline(
        tab: AttoEditorTab,
        documentText: String,
        symbols: [AttoLspSymbolParser.Symbol]
    ) {
        workspaceOutlineStore.upsertDocument(
            tabID: tab.id,
            coreTabID: tab.coreTabID,
            fileURL: projectedFileURL(for: tab),
            documentText: documentText,
            symbols: symbols
        )
        guard lspSymbolPanelController?.isVisible == true,
              lspSymbolResultStore.currentEntry?.title.hasPrefix("Workspace Outline") == true
        else {
            return
        }
        let snapshot = workspaceOutlineSymbolSnapshot()
        let entry = lspSymbolResultStore.makeCurrent(
            snapshot,
            family: "symbols",
            title: workspaceOutlineHistoryTitle(for: workspaceOutlineStore.snapshot)
        )
        lspSymbolPanelController?.update(entry: entry)
    }

    func applyCoreDocumentSymbols(tab: AttoEditorTab, json: String) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }
        do {
            try coreDocuments.applyTabDocumentSymbolsJSON(tabId: coreTabID, resultJSON: json)
        } catch {
            NSLog("AttoEditor: core multi-document apply document symbols failed: %@", String(describing: error))
        }
    }

    func finishLspSymbolResult(
        _ symbols: [AttoLspSymbolParser.Symbol],
        kind: LspSymbolRequestKind,
        title: String,
        placeholder: String,
        tab: AttoEditorTab
    ) -> Bool {
        if symbols.isEmpty {
            presentLspResultFeedback(
                AttoLspResultFeedback.empty(kind.feedbackFeature, detailText: kind.emptyFeedbackDetailText),
                in: tab.editCore.editorView
            )
            NSSound.beep()
            return false
        }

        let snapshot = LspSymbolResultSnapshot(title: title, symbols: symbols, placeholder: placeholder)
        recordLspSymbolResultSnapshot(snapshot)
        showLspSymbolResults(symbols, placeholder: placeholder)
        return true
    }

    func recordLspSymbolResultSnapshot(_ snapshot: LspSymbolResultSnapshot) {
        let entry = lspSymbolResultStore.record(
            snapshot,
            family: "symbols",
            title: symbolHistoryTitle(for: snapshot)
        )
        recordLspResultLifecycleEvent(
            entry,
            payload: .symbols(title: snapshot.title, itemCount: snapshot.symbols.count)
        )
        lspSymbolPanelController?.update(entry: entry)
        updateVisibleLspWorkbenchPanel()
    }

    @discardableResult
    func openLspSymbolSnapshot(_ snapshot: LspSymbolResultSnapshot) -> Bool {
        guard snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        lspSymbolResultStore.makeCurrent(
            snapshot,
            family: "symbols",
            title: symbolHistoryTitle(for: snapshot)
        )
        showLspSymbolResults(snapshot.symbols, placeholder: snapshot.placeholder)
        return true
    }

    @discardableResult
    func openLspSymbolEntry(_ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>) -> Bool {
        let snapshot = entry.snapshot
        guard snapshot.symbols.isEmpty == false else {
            NSSound.beep()
            return false
        }
        lspSymbolResultStore.makeCurrent(entry)
        showLspSymbolResults(snapshot.symbols, placeholder: snapshot.placeholder)
        return true
    }

    func symbolHistoryTitle(for snapshot: LspSymbolResultSnapshot) -> String {
        "\(snapshot.title): \(snapshot.symbols.count) results"
    }

    func workspaceSymbolTitle(query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? "Workspace Symbols" : "Workspace Symbols: \(trimmedQuery)"
    }

    func workspaceOutlineSymbolSnapshot() -> LspSymbolResultSnapshot {
        LspSymbolResultSnapshot(
            title: "Workspace Outline",
            symbols: workspaceOutlineStore.snapshot.symbols,
            placeholder: "Filter workspace outline..."
        )
    }

    func workspaceOutlineHistoryTitle(for snapshot: AttoWorkspaceOutlineSnapshot) -> String {
        let fileCount = snapshot.documents.count
        let symbolCount = snapshot.symbols.count
        let fileLabel = fileCount == 1 ? "1 file" : "\(fileCount) files"
        let symbolLabel = symbolCount == 1 ? "1 symbol" : "\(symbolCount) symbols"
        return "Workspace Outline: \(fileLabel), \(symbolLabel)"
    }

    func showLspSymbolResults(_ symbols: [AttoLspSymbolParser.Symbol], placeholder: String) {
        guard symbols.isEmpty == false else {
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            navigateToLspTarget(symbols[0].target)
            return
        }

        let commands = symbols.enumerated().map { idx, symbol in
            AttoCommandPaletteCommand(
                id: "lsp.symbol.\(idx)",
                title: displayTitle(for: symbol),
                group: AttoLspSymbolParser.kindGroupLabel(for: symbol)
            ) { [weak self] in
                self?.navigateToLspTarget(symbol.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.SymbolResults",
            commandsProvider: { commands }
        )
        lspSymbolResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
    }

    func displayTitle(for symbol: AttoLspSymbolParser.Symbol) -> String {
        let indent = String(repeating: "  ", count: symbol.depth)
        let detail = symbol.detail.map { " \($0)" } ?? ""
        let kind = symbol.kindLabel.map { " [\($0)]" } ?? ""
        let container = symbol.containerName.map { " — \($0)" } ?? ""
        let location = displayTitle(for: symbol.target)
        return "\(indent)\(symbol.name)\(detail)\(kind)\(container) — \(location)"
    }
}
