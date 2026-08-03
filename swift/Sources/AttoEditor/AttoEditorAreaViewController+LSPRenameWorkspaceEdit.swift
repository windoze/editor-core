import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP rename

    @discardableResult
    func promptRenameSymbolInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.rename), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let fallbackSeed = renameDialogSeedInActiveTab()
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestPrepareRename(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
            renamePrepareContext = RenamePrepareContext(
                tabID: tab.id,
                fallbackSeed: fallbackSeed,
                showFeedback: showFeedback
            )
            startRenamePreparePollTimer(tabID: tab.id)
            return true
        } catch {
            return showRenameDialog(seed: fallbackSeed, showFeedback: showFeedback)
        }
    }

    @discardableResult
    func showRenameDialog(seed: AttoLspRenameSupport.DialogSeed, showFeedback: Bool = true) -> Bool {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = seed.initialName
        field.placeholderString = seed.placeholder ?? "New symbol name"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Symbol"
        alert.informativeText = "Enter the new name for the symbol."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return renameSymbolInActiveTab(to: newName, showFeedback: showFeedback)
    }

    @discardableResult
    func renameSymbolInActiveTab(to newName: String, showFeedback: Bool = true) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.unavailable(.rename), in: tab.editCore.editorView)
            }
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
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestRename(
                logicalLine: pos.line,
                logicalColumn: pos.column,
                newName: trimmed
            )
            renameContext = RenameRequestContext(
                tabID: tab.id,
                documentURI: projectedFileURL(for: tab).absoluteString,
                newName: trimmed,
                showFeedback: showFeedback
            )
            startRenamePollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            cancelRenameUI()
            if showFeedback {
                presentLspResultFeedback(
                    AttoLspResultFeedback.requestFailed(.rename, errorDescription: error.localizedDescription),
                    in: tab.editCore.editorView
                )
            }
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyWorkspaceEditJSONToActiveTab(_ workspaceEditJSON: String, documentURI: String? = nil) -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        guard let workspaceEdit = AttoWorkspaceEditParser.parse(workspaceEditJSON) else {
            NSSound.beep()
            return false
        }

        return applyWorkspaceEditToActiveTab(
            workspaceEdit,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI
        )
    }

    @discardableResult
    func applyWorkspaceEditToActiveTab(_ workspaceEdit: EcuLspWorkspaceEdit, documentURI: String? = nil) -> Bool {
        guard let workspaceEditJSON = workspaceEdit.rawJSONString else {
            NSSound.beep()
            return false
        }
        return applyWorkspaceEditToActiveTab(
            AttoWorkspaceEditParser.parse(workspaceEdit),
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI
        )
    }

    @discardableResult
    func applyWorkspaceEditToActiveTab(
        _ workspaceEdit: AttoWorkspaceEditParser.ParseResult,
        workspaceEditJSON: String,
        documentURI: String? = nil
    ) -> Bool {
        guard let initialActiveTab = activeTab else {
            NSSound.beep()
            return false
        }

        if coreDocuments != nil {
            return applyWorkspaceEditWithCoreTransaction(
                workspaceEdit,
                workspaceEditJSON: workspaceEditJSON,
                documentURI: documentURI,
                initialActiveTab: initialActiveTab
            )
        }

        return applyWorkspaceEditWithSwiftFallback(
            workspaceEdit,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: documentURI,
            initialActiveTab: initialActiveTab
        )
    }

    @discardableResult
    func applyWorkspaceEditWithCoreTransaction(
        _ workspaceEdit: AttoWorkspaceEditParser.ParseResult,
        workspaceEditJSON: String,
        documentURI: String?,
        initialActiveTab: AttoEditorTab
    ) -> Bool {
        guard let coreDocuments else { return false }
        let feedbackEditorView = activeTab?.editCore.editorView ?? initialActiveTab.editCore.editorView

        do {
            try syncOpenTabsToCoreBeforeWorkspaceEditApply(coreDocuments)
            let transientStatusBeforeConfirmation = transientStatusText
            guard try confirmCoreWorkspaceEditPreviewIfNeeded(
                coreDocuments,
                workspaceEdit: workspaceEdit,
                workspaceEditJSON: workspaceEditJSON,
                editorView: feedbackEditorView
            ) else {
                if transientStatusText == transientStatusBeforeConfirmation {
                    setTransientStatusText("Workspace edit cancelled")
                }
                return false
            }
            let projectedURLsBeforeApply = projectedFileURLsByTabID()
            let coreResult = try coreDocuments.applyWorkspaceEditTransaction(workspaceEditJSON)
            try syncAppTabsFromCoreWorkspaceEditTransaction(
                coreDocuments,
                projectedURLsBeforeSync: projectedURLsBeforeApply
            )

            let result = AttoWorkspaceEditApplyResult(
                applied: coreResult.applied,
                appliedURI: coreResult.appliedURI ?? documentURI ?? initialActiveTab.fileURL.absoluteString,
                appliedEditCount: coreResult.appliedEditCount + coreResult.appliedResourceOperationCount,
                skippedURIs: coreResult.skippedURIs,
                documents: coreResult.documents.map {
                    AttoWorkspaceEditApplyResult.Document(
                        uri: $0.uri,
                        editCount: $0.editCount,
                        hasOverlappingEdits: $0.hasOverlappingEdits
                    )
                }
            )

            guard result.applied else {
                showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
                refreshWorkspaceEditHistoryPanelIfVisible()
                if result.skippedURIs.isEmpty == false {
                    NSLog(
                        "AttoEditor: core WorkspaceEdit transaction was not applied; skipped URIs: %@",
                        result.skippedURIs.joined(separator: ", ")
                    )
                }
                NSSound.beep()
                return false
            }

            if result.skippedURIs.isEmpty == false {
                NSLog(
                    "AttoEditor: core WorkspaceEdit transaction partially applied; skipped URIs: %@",
                    result.skippedURIs.joined(separator: ", ")
                )
            }

            updateStatusBar()
            showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
            registerWorkspaceEditUndoManagerAction()
            refreshWorkspaceEditHistoryPanelIfVisible()
            if let activeEditorView = activeTab?.editCore.editorView {
                view.window?.makeFirstResponder(activeEditorView)
            }
            return true
        } catch {
            NSLog(
                "AttoEditor: core WorkspaceEdit transaction apply failed: %@",
                String(describing: error)
            )
            NSSound.beep()
            return false
        }
    }

    func confirmCoreWorkspaceEditPreviewIfNeeded(
        _ coreDocuments: MultiDocumentEditorUI,
        workspaceEdit: AttoWorkspaceEditParser.ParseResult,
        workspaceEditJSON: String,
        editorView: EditorCoreSkiaView
    ) throws -> Bool {
        let result = try coreDocuments.previewWorkspaceEditTransaction(workspaceEditJSON)
        var preview = AttoWorkspaceEditPreview(
            result: result,
            parsedWorkspaceEdit: workspaceEdit
        )
        preview.sections = AttoWorkspaceEditPreviewDetailBuilder.sections(
            preview: preview,
            workspaceEdit: workspaceEdit,
            textForURI: workspaceEditPreviewText(for:)
        )
        guard preview.requiresConfirmation else { return true }
        return confirmWorkspaceEditPreview(preview, editorView: editorView)
    }

    func confirmWorkspaceEditPreview(
        _ preview: AttoWorkspaceEditPreview,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        if let decisionProvider = workspaceEditPreviewDecisionProviderForTesting {
            return handleWorkspaceEditPreviewDecision(
                decisionProvider(preview),
                preview: preview,
                editorView: editorView
            )
        }
        guard view.window != nil || editorView.window != nil else {
            return handleWorkspaceEditPreviewDecision(
                .apply,
                preview: preview,
                editorView: editorView
            )
        }

        let panelController = AttoWorkspaceEditPreviewPanelController()
        workspaceEditPreviewPanelController = panelController
        let decision = panelController.runModal(
            relativeTo: editorView.window ?? view.window,
            preview: preview
        )
        workspaceEditPreviewPanelController = nil
        return handleWorkspaceEditPreviewDecision(
            decision,
            preview: preview,
            editorView: editorView
        )
    }

    func handleWorkspaceEditPreviewDecision(
        _ decision: AttoWorkspaceEditPreviewDecision,
        preview: AttoWorkspaceEditPreview,
        editorView: EditorCoreSkiaView
    ) -> Bool {
        switch decision {
        case .apply:
            guard preview.canApply else {
                setTransientStatusText("Resolve WorkspaceEdit conflicts before applying")
                NSSound.beep()
                return false
            }
            return true
        case .cancel:
            return false
        case .openConflict(let uri):
            openWorkspaceEditConflictTarget(uri, editorView: editorView)
            return false
        case .saveConflict(let uri):
            saveWorkspaceEditConflictTarget(uri, editorView: editorView)
            return false
        case .discardConflict(let uri):
            discardWorkspaceEditConflictTarget(uri, editorView: editorView)
            return false
        }
    }

    @discardableResult
    func openWorkspaceEditConflictTarget(_ uri: String, editorView: EditorCoreSkiaView) -> Bool {
        guard let url = Self.fileURL(fromDocumentURI: uri)?.standardizedFileURL else {
            setTransientStatusText("WorkspaceEdit conflict target unavailable")
            NSSound.beep()
            return false
        }

        guard openFile(url: url, mode: .pinned) else {
            setTransientStatusText("WorkspaceEdit conflict target unavailable")
            return false
        }
        setTransientStatusText("Opened WorkspaceEdit conflict: \(url.lastPathComponent)")
        if let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        } else {
            view.window?.makeFirstResponder(editorView)
        }
        return true
    }

    @discardableResult
    func saveWorkspaceEditConflictTarget(_ uri: String, editorView: EditorCoreSkiaView) -> Bool {
        guard let url = Self.fileURL(fromDocumentURI: uri)?.standardizedFileURL,
              let tab = projectedTab(forFileURL: url)
        else {
            setTransientStatusText("WorkspaceEdit conflict target unavailable")
            NSSound.beep()
            return false
        }

        guard saveTabWithSavePanelIfNeeded(tab) else {
            setTransientStatusText("WorkspaceEdit conflict save cancelled")
            return false
        }

        setTransientStatusText("Saved WorkspaceEdit conflict: \(url.lastPathComponent)")
        if activeTab?.id == tab.id, let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        } else {
            view.window?.makeFirstResponder(editorView)
        }
        return true
    }

    @discardableResult
    func discardWorkspaceEditConflictTarget(_ uri: String, editorView: EditorCoreSkiaView) -> Bool {
        guard let url = Self.fileURL(fromDocumentURI: uri)?.standardizedFileURL,
              let tab = projectedTab(forFileURL: url)
        else {
            setTransientStatusText("WorkspaceEdit conflict target unavailable")
            NSSound.beep()
            return false
        }

        let diskText: String
        do {
            diskText = try String(contentsOf: url, encoding: .utf8)
        } catch {
            setTransientStatusText("WorkspaceEdit conflict discard failed")
            NSSound.beep()
            NSLog(
                "AttoEditor: failed to read WorkspaceEdit conflict target %@ for discard: %@",
                url.path,
                String(describing: error)
            )
            return false
        }

        guard replaceOpenTabText(tab, with: diskText, markSaved: true) else {
            setTransientStatusText("WorkspaceEdit conflict discard failed")
            return false
        }

        setTransientStatusText("Discarded WorkspaceEdit conflict changes: \(url.lastPathComponent)")
        if activeTab?.id == tab.id, let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        } else {
            view.window?.makeFirstResponder(editorView)
        }
        return true
    }

    func workspaceEditPreviewText(for uri: String) -> String? {
        guard let url = Self.fileURL(fromDocumentURI: uri)?.standardizedFileURL else { return nil }
        if let tab = projectedTab(forFileURL: url) {
            return try? tab.editCore.editor.text()
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    func applyWorkspaceEditWithSwiftFallback(
        _ workspaceEdit: AttoWorkspaceEditParser.ParseResult,
        workspaceEditJSON: String,
        documentURI: String?,
        initialActiveTab: AttoEditorTab
    ) -> Bool {
        let coreTransactionPreview = previewCoreWorkspaceEditTransaction(workspaceEditJSON)
        let coreBlockedTextEditURIs = coreWorkspaceEditBlockedTextEditURIs(coreTransactionPreview)

        var documents = workspaceEdit.documents.map { document in
            AttoWorkspaceEditApplyResult.Document(
                uri: document.uri,
                editCount: document.edits.count,
                hasOverlappingEdits: document.hasOverlappingEdits
            )
        }
        for uri in workspaceEdit.unsupportedURIs where documents.contains(where: { $0.uri == uri }) == false {
            documents.append(
                AttoWorkspaceEditApplyResult.Document(
                    uri: uri,
                    editCount: 0,
                    hasOverlappingEdits: false
                )
            )
        }
        for operation in workspaceEdit.resourceOperations {
            for uri in operation.affectedURIs where documents.contains(where: { $0.uri == uri }) == false {
                documents.append(
                    AttoWorkspaceEditApplyResult.Document(
                        uri: uri,
                        editCount: 0,
                        hasOverlappingEdits: false
                    )
                )
            }
        }

        var appliedURIs: [String] = []
        var appliedEditCount = 0
        var appliedResourceOperationCount = 0
        var skippedURIs = Set(workspaceEdit.unsupportedURIs)
        skippedURIs.formUnion(coreBlockedTextEditURIs)

        for operation in workspaceEdit.resourceOperations {
            guard applyWorkspaceResourceOperation(operation) else {
                skippedURIs.formUnion(operation.affectedURIs)
                continue
            }

            appliedURIs.append(contentsOf: operation.affectedURIs)
            appliedResourceOperationCount += 1
        }

        for document in workspaceEdit.documents {
            guard document.edits.isEmpty == false else { continue }

            if document.hasOverlappingEdits {
                skippedURIs.insert(document.uri)
                continue
            }

            if coreBlockedTextEditURIs.contains(document.uri) {
                continue
            }

            if let tab = tabForDocumentURI(document.uri) {
                do {
                    let resultJSON = try tab.editCore.editor.lspApplyWorkspaceEditJSON(
                        workspaceEditJSON,
                        documentURI: document.uri
                    )
                    let result = AttoWorkspaceEditApplyResult(json: resultJSON)
                    guard result.applied else {
                        skippedURIs.insert(document.uri)
                        continue
                    }

                    appliedURIs.append(document.uri)
                    appliedEditCount += result.appliedEditCount
                    refreshTabAfterWorkspaceEdit(tab)
                } catch {
                    skippedURIs.insert(document.uri)
                    NSLog(
                        "AttoEditor: failed to apply WorkspaceEdit to open document %@: %@",
                        document.uri,
                        String(describing: error)
                    )
                }
                continue
            }

            guard let url = Self.fileURL(fromDocumentURI: document.uri) else {
                skippedURIs.insert(document.uri)
                continue
            }

            guard applyWorkspaceEdit(document, toFileAt: url) else {
                skippedURIs.insert(document.uri)
                continue
            }

            appliedURIs.append(document.uri)
            appliedEditCount += document.edits.count
        }

        let result = AttoWorkspaceEditApplyResult(
            applied: (appliedEditCount + appliedResourceOperationCount) > 0,
            appliedURI: appliedURIs.first ?? documentURI ?? initialActiveTab.fileURL.absoluteString,
            appliedEditCount: appliedEditCount + appliedResourceOperationCount,
            skippedURIs: Array(skippedURIs).sorted(),
            documents: documents
        )

        let feedbackEditorView = activeTab?.editCore.editorView ?? initialActiveTab.editCore.editorView
        guard result.applied else {
            showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
            if result.skippedURIs.isEmpty == false {
                NSLog(
                    "AttoEditor: WorkspaceEdit was not applied; skipped URIs: %@",
                    result.skippedURIs.joined(separator: ", ")
                )
            }
            NSSound.beep()
            return false
        }

        if result.skippedURIs.isEmpty == false {
            NSLog(
                "AttoEditor: WorkspaceEdit partially applied; skipped URIs: %@",
                result.skippedURIs.joined(separator: ", ")
            )
        }

        updateStatusBar()
        showWorkspaceEditSummaryIfNeeded(result, editorView: feedbackEditorView)
        if let activeEditorView = activeTab?.editCore.editorView {
            view.window?.makeFirstResponder(activeEditorView)
        }
        return true
    }

    func syncOpenTabsToCoreBeforeWorkspaceEditApply(_ coreDocuments: MultiDocumentEditorUI) throws {
        let snapshot = try coreDocuments.snapshot()
        let coreTabsByID = Dictionary(uniqueKeysWithValues: snapshot.tabs.map { ($0.id, $0) })

        for tab in tabs {
            guard let coreTabID = tab.coreTabID else { continue }
            let isDirty = localTabDirtyState(tab)
            let text = try tab.editCore.editor.text()
            let coreText = try coreDocuments.tabText(tabId: coreTabID)
            let coreIsDirty = coreTabsByID[coreTabID]?.isModified ?? false
            let documentURL = projectedWorkspaceEditSyncURL(
                coreTab: coreTabsByID[coreTabID],
                fallback: tab.fileURL
            )
            try coreDocuments.setTabTitle(documentURL.lastPathComponent, tabId: coreTabID)
            try coreDocuments.setTabDocumentURI(documentURL.absoluteString, tabId: coreTabID)
            if coreText != text || coreIsDirty != isDirty {
                try coreDocuments.replaceTabText(tabId: coreTabID, text: text, markSaved: isDirty == false)
            }
            try coreDocuments.setActiveViewIndex(
                tabId: coreTabID,
                viewIndex: UInt32(clamping: tab.activePaneIndex)
            )
        }
        if let activeTab, let coreTabID = activeTab.coreTabID {
            try coreDocuments.setActiveTab(coreTabID)
        }
    }

    func projectedWorkspaceEditSyncURL(coreTab: EcuMultiDocumentTabSnapshot?, fallback: URL) -> URL {
        if let documentURI = coreTab?.documentURI,
           let url = Self.fileURL(fromDocumentURI: documentURI)
        {
            return url.standardizedFileURL
        }

        return fallback.standardizedFileURL
    }

    func syncAppTabsFromCoreWorkspaceEditTransaction(
        _ coreDocuments: MultiDocumentEditorUI,
        projectedURLsBeforeSync: [UUID: URL] = [:]
    ) throws {
        let snapshot = try coreDocuments.snapshot()
        let coreTabsByID = Dictionary(uniqueKeysWithValues: snapshot.tabs.map { ($0.id, $0) })
        var removedSelectedTab = false

        let removedTabs = tabs.compactMap { tab -> (id: UUID, url: URL)? in
            guard let coreTabID = tab.coreTabID,
                  coreTabsByID[coreTabID] == nil
            else { return nil }
            return (tab.id, projectedURLsBeforeSync[tab.id] ?? projectedFileURL(for: tab))
        }
        for removedTab in removedTabs {
            removedSelectedTab = removedSelectedTab || selectedTabID == removedTab.id
            clearDiagnosticsLifecycleState(forTabID: removedTab.id)
            tabs.removeAll { $0.id == removedTab.id }
            onDidCloseFile?(removedTab.url)
        }

        for tab in tabs {
            guard let coreTabID = tab.coreTabID,
                  let snapshotTab = coreTabsByID[coreTabID]
            else {
                continue
            }

            if let documentURI = snapshotTab.documentURI,
               let url = Self.fileURL(fromDocumentURI: documentURI) {
                tab.fileURL = url
                tab.isUntitled = false
            }
            tab.isPreview = snapshotTab.isPreview
            tab.isDirty = snapshotTab.isModified
            let text = try coreDocuments.tabText(tabId: coreTabID)
            try replaceAppTabTextFromCoreProjection(
                tab,
                text: text,
                markSaved: snapshotTab.isModified == false
            )
            refreshTabAfterCoreWorkspaceEditProjection(tab)
        }

        let selectedTabStillExists = selectedTabID.map { selectedID in
            tabs.contains(where: { $0.id == selectedID })
        } ?? false
        if removedSelectedTab || selectedTabStillExists == false {
            if let activeCoreTabID = snapshot.activeTabId,
               let tab = tabs.first(where: { $0.coreTabID == activeCoreTabID }) {
                selectTab(id: tab.id)
            } else if let first = tabs.first {
                selectTab(id: first.id)
            } else {
                selectedTabID = nil
                showEmptyState()
            }
        } else if let activeTab {
            showTabContent(activeTab)
        }

        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
    }

    @discardableResult
    func undoLastCoreWorkspaceEditTransaction() -> Bool {
        guard let coreDocuments else {
            NSSound.beep()
            return false
        }

        do {
            let undoneSequence = latestUndoableWorkspaceEditTransactionSequence()
            let projectedURLsBeforeUndo = projectedFileURLsByTabID()
            let result = try coreDocuments.undoLastWorkspaceEditTransaction()
            guard result.undone else {
                setTransientStatusText("No WorkspaceEdit transaction to undo")
                return false
            }
            try syncAppTabsFromCoreWorkspaceEditTransaction(
                coreDocuments,
                projectedURLsBeforeSync: projectedURLsBeforeUndo
            )
            if let undoneSequence {
                workspaceEditConsumedUndoSequences.insert(undoneSequence)
            }
            if view.window?.undoManager?.isUndoing == true {
                registerWorkspaceEditRedoManagerAction()
            }
            setTransientStatusText("Workspace edit undone")
            refreshWorkspaceEditHistoryPanelIfVisible()
            return true
        } catch {
            NSLog("AttoEditor: failed to undo WorkspaceEdit transaction: %@", String(describing: error))
            setTransientStatusText("Workspace edit undo failed")
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func redoLastCoreWorkspaceEditTransaction() -> Bool {
        guard let coreDocuments else {
            NSSound.beep()
            return false
        }

        do {
            let projectedURLsBeforeRedo = projectedFileURLsByTabID()
            let result = try coreDocuments.redoLastWorkspaceEditTransaction()
            guard result.applied else {
                setTransientStatusText("No WorkspaceEdit transaction to redo")
                return false
            }
            try syncAppTabsFromCoreWorkspaceEditTransaction(
                coreDocuments,
                projectedURLsBeforeSync: projectedURLsBeforeRedo
            )
            if view.window?.undoManager?.isRedoing == true {
                registerWorkspaceEditUndoManagerAction()
            }
            setTransientStatusText("Workspace edit redone")
            refreshWorkspaceEditHistoryPanelIfVisible()
            return true
        } catch {
            NSLog("AttoEditor: failed to redo WorkspaceEdit transaction: %@", String(describing: error))
            setTransientStatusText("Workspace edit redo failed")
            NSSound.beep()
            return false
        }
    }

    func registerWorkspaceEditUndoManagerAction() {
        guard let undoManager = view.window?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.undoLastCoreWorkspaceEditTransaction()
        }
        undoManager.setActionName("Workspace Edit")
    }

    func registerWorkspaceEditRedoManagerAction() {
        guard let undoManager = view.window?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.redoLastCoreWorkspaceEditTransaction()
        }
        undoManager.setActionName("Workspace Edit")
    }

    func projectedFileURLsByTabID() -> [UUID: URL] {
        Dictionary(uniqueKeysWithValues: tabs.map { tab in
            (tab.id, projectedFileURL(for: tab))
        })
    }

    func replaceAppTabTextFromCoreProjection(
        _ tab: AttoEditorTab,
        text: String,
        markSaved: Bool
    ) throws {
        let oldText = try tab.editCore.editor.text()
        if oldText != text {
            let fullRange = UInt32(clamping: oldText.unicodeScalars.count)
            _ = try tab.editCore.editor.applyTextEdits([
                EcuTextEdit(start: 0, end: fullRange, text: text),
            ])
            try tab.editCore.editor.endUndoGroup()
        }
        if markSaved {
            try tab.editCore.editor.markSaved()
            tab.isDirty = false
        } else {
            tab.isDirty = true
        }
    }

    func refreshTabAfterCoreWorkspaceEditProjection(_ tab: AttoEditorTab) {
        let fileURL = projectedFileURL(for: tab)
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
            applyLanguageConfiguration(fileURL: fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        }
    }

    func previewCoreWorkspaceEditTransaction(_ workspaceEditJSON: String) -> EcuWorkspaceEditTransactionResult? {
        guard let coreDocuments else { return nil }
        do {
            return try coreDocuments.previewWorkspaceEditTransaction(workspaceEditJSON)
        } catch {
            NSLog(
                "AttoEditor: core WorkspaceEdit transaction preview failed: %@",
                String(describing: error)
            )
            return nil
        }
    }

    func coreWorkspaceEditBlockedTextEditURIs(
        _ preview: EcuWorkspaceEditTransactionResult?
    ) -> Set<String> {
        guard let preview else { return [] }
        return Set(preview.skippedDetails.compactMap { detail in
            guard detail.operation == "text_edit",
                  detail.reason == "version_mismatch"
            else {
                return nil
            }
            return detail.uri
        })
    }

    func showWorkspaceEditSummaryIfNeeded(
        _ result: AttoWorkspaceEditApplyResult,
        editorView: EditorCoreSkiaView
    ) {
        guard let text = AttoWorkspaceEditApplyResult.displayText(for: result) else { return }
        showWorkspaceEditPopover(text: text, in: editorView)
    }

    func tabForDocumentURI(_ uri: String) -> AttoEditorTab? {
        guard let url = Self.fileURL(fromDocumentURI: uri) else { return nil }
        return tabForFileURL(url)
    }

    func tabForFileURL(_ url: URL) -> AttoEditorTab? {
        return tabs.first { tab in
            tab.fileURL.standardizedFileURL == url.standardizedFileURL
        }
    }

    func refreshTabAfterWorkspaceEdit(_ tab: AttoEditorTab) {
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
        }
        try? tab.editCore.editor.revealPrimaryCaret()
        handleTabDidMutateDocumentText(tabID: tab.id)
    }

    func applyWorkspaceEdit(
        _ document: AttoWorkspaceEditParser.DocumentEdit,
        toFileAt url: URL
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            return false
        }

        do {
            let oldText = try String(contentsOf: url, encoding: .utf8)
            guard let result = AttoWorkspaceEditParser.apply(document, to: oldText),
                  result.hasOverlappingEdits == false,
                  result.editCount > 0
            else {
                return false
            }
            try result.text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to apply WorkspaceEdit to file %@: %@",
                url.path,
                String(describing: error)
            )
            return false
        }
    }

    func applyWorkspaceResourceOperation(_ operation: AttoWorkspaceEditParser.ResourceOperation) -> Bool {
        switch operation {
        case .create(let op):
            guard let url = workspaceFileURL(fromDocumentURI: op.uri) else { return false }
            if let tab = tabForFileURL(url) {
                if op.ignoreIfExists { return true }
                guard op.overwrite, isTabDirtyForDataLossDecision(tab) == false else { return false }
                guard createWorkspaceFile(at: url, overwrite: true, ignoreIfExists: false) else { return false }
                return replaceOpenTabText(tab, with: "", markSaved: true)
            }
            return createWorkspaceFile(at: url, overwrite: op.overwrite, ignoreIfExists: op.ignoreIfExists)

        case .rename(let op):
            guard let oldURL = workspaceFileURL(fromDocumentURI: op.oldURI),
                  let newURL = workspaceFileURL(fromDocumentURI: op.newURI)
            else { return false }

            if oldURL.standardizedFileURL == newURL.standardizedFileURL {
                return true
            }

            let oldTab = tabForFileURL(oldURL)
            let targetTab = tabForFileURL(newURL)
            let targetExists = FileManager.default.fileExists(atPath: newURL.path)
            if targetExists, op.ignoreIfExists {
                return true
            }

            if let targetTab, targetTab.id != oldTab?.id {
                guard op.overwrite, isTabDirtyForDataLossDecision(targetTab) == false else { return false }
                closeTab(id: targetTab.id)
            }

            guard renameWorkspaceFile(
                from: oldURL,
                to: newURL,
                overwrite: op.overwrite,
                ignoreIfExists: op.ignoreIfExists
            ) else {
                return false
            }

            if let oldTab {
                oldTab.fileURL = newURL
                oldTab.isUntitled = false
                refreshTabAfterWorkspaceResourceOperation(oldTab)
                return true
            }

            return true

        case .delete(let op):
            guard let url = workspaceFileURL(fromDocumentURI: op.uri) else { return false }
            if let tab = tabForFileURL(url) {
                guard isTabDirtyForDataLossDecision(tab) == false else { return false }
                guard deleteWorkspaceFile(
                    at: url,
                    recursive: op.recursive,
                    ignoreIfNotExists: op.ignoreIfNotExists
                ) else {
                    return false
                }
                closeTab(id: tab.id)
                return true
            }
            return deleteWorkspaceFile(
                at: url,
                recursive: op.recursive,
                ignoreIfNotExists: op.ignoreIfNotExists
            )
        }
    }

    func workspaceFileURL(fromDocumentURI uri: String) -> URL? {
        guard let url = Self.fileURL(fromDocumentURI: uri) else { return nil }
        let path = url.standardizedFileURL.path
        let root = workspaceRootURL.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        return url
    }

    func createWorkspaceFile(at url: URL, overwrite: Bool, ignoreIfExists: Bool) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists {
            if ignoreIfExists { return true }
            guard overwrite, isDirectory.boolValue == false else { return false }
        }

        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("AttoEditor: failed to create WorkspaceEdit file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    func renameWorkspaceFile(
        from oldURL: URL,
        to newURL: URL,
        overwrite: Bool,
        ignoreIfExists: Bool
    ) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldURL.path) else { return false }

        let targetExists = fm.fileExists(atPath: newURL.path)
        if targetExists {
            if ignoreIfExists { return true }
            guard overwrite else { return false }
        }

        do {
            try fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if targetExists {
                try fm.removeItem(at: newURL)
            }
            try fm.moveItem(at: oldURL, to: newURL)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to rename WorkspaceEdit file %@ -> %@: %@",
                oldURL.path,
                newURL.path,
                String(describing: error)
            )
            return false
        }
    }

    func deleteWorkspaceFile(at url: URL, recursive: Bool, ignoreIfNotExists: Bool) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { return ignoreIfNotExists }
        guard recursive || isDirectory.boolValue == false else { return false }

        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            NSLog("AttoEditor: failed to delete WorkspaceEdit file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    func replaceOpenTabText(_ tab: AttoEditorTab, with text: String, markSaved: Bool) -> Bool {
        do {
            let oldText = try tab.editCore.editor.text()
            let fullRange = UInt32(clamping: oldText.unicodeScalars.count)
            _ = try tab.editCore.editor.applyTextEdits([
                EcuTextEdit(start: 0, end: fullRange, text: text),
            ])
            if oldText != text {
                try tab.editCore.editor.endUndoGroup()
            }
            if markSaved {
                try tab.editCore.editor.markSaved()
                tab.isDirty = false
                tab.isUntitled = false
            } else {
                tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true
            }
            syncCoreTabText(tab, markSaved: markSaved || tab.isDirty == false)
            refreshTabAfterWorkspaceResourceOperation(tab)
            return true
        } catch {
            NSLog(
                "AttoEditor: failed to replace open WorkspaceEdit tab %@: %@",
                tab.fileURL.path,
                String(describing: error)
            )
            return false
        }
    }

    func refreshTabAfterWorkspaceResourceOperation(_ tab: AttoEditorTab) {
        let fileURL = projectedFileURL(for: tab)
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
            applyLanguageConfiguration(fileURL: fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
        }
        updateCoreTabTitle(tab)
        updateCoreTabDocumentURI(tab)
        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
    }

    static func fileURL(fromDocumentURI uri: String) -> URL? {
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    func startRenamePreparePollTimer(tabID: UUID) {
        renamePreparePollTimer?.cancel()

        var remainingTicks = 20 // ~1s at 50ms; fall back to local identifier if no prepare result arrives.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.renamePrepareContext, ctx.tabID == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            let result: EcuLspPrepareRenameResult?
            do {
                result = try tab.editCore.editor.lspTakeLastPrepareRenameResult()
            } catch {
                return
            }

            if let result {
                self.cancelRenamePrepareUI()
                let seed = self.renameDialogSeedInActiveTab(
                    prepareRenameResult: result,
                    fallback: ctx.fallbackSeed
                )
                _ = self.showRenameDialog(seed: seed, showFeedback: ctx.showFeedback)
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.cancelRenamePrepareUI()
                _ = self.showRenameDialog(seed: ctx.fallbackSeed, showFeedback: ctx.showFeedback)
                timer.cancel()
                return
            }
            remainingTicks -= 1
        }

        renamePreparePollTimer = timer
        timer.resume()
    }

    func startRenamePollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        renamePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.renameContext, ctx.tabID == tabID else {
                self.cancelRenameUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.cancelRenameUI()
                if showFeedback {
                    self.presentLspResultFeedback(AttoLspResultFeedback.timeout(.rename), in: editorView)
                }
                NSSound.beep()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenameUI()
                return
            }

            let result: EcuLspWorkspaceEdit?
            do {
                result = try tab.editCore.editor.lspTakeLastRenameResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.cancelRenameUI()
                if showFeedback {
                    self.presentLspResultFeedback(
                        AttoLspResultFeedback.failed(.rename, errorDescription: error.localizedDescription),
                        in: editorView
                    )
                }
                NSSound.beep()
                return
            }
            guard let result else { return }

            self.renamePollTimer?.cancel()
            self.renamePollTimer = nil
            self.renameContext = nil
            _ = self.applyRenameResult(result, context: ctx)
            timer.cancel()
        }

        renamePollTimer = timer
        timer.resume()
    }

    @discardableResult
    func applyRenameResultJSON(_ json: String, context: RenameRequestContext) -> Bool {
        guard let workspaceEdit = AttoWorkspaceEditParser.parse(json) else {
            if context.showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .rename,
                        errorDescription: "Rename result could not be decoded."
                    ),
                    in: editorView
                )
            }
            NSSound.beep()
            recordRenameResultLifecycle(json, newName: context.newName, applied: false)
            return false
        }

        guard workspaceEdit.isEmpty == false else {
            if context.showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.rename), in: editorView)
            }
            NSSound.beep()
            recordRenameResultLifecycle(json, newName: context.newName, applied: false)
            return false
        }

        let applied = applyWorkspaceEditToActiveTab(
            workspaceEdit,
            workspaceEditJSON: json,
            documentURI: context.documentURI
        )
        recordRenameResultLifecycle(json, newName: context.newName, applied: applied)
        return applied
    }

    @discardableResult
    func applyRenameResult(_ workspaceEdit: EcuLspWorkspaceEdit, context: RenameRequestContext) -> Bool {
        let parsed = AttoWorkspaceEditParser.parse(workspaceEdit)
        guard parsed.isEmpty == false else {
            if context.showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.rename), in: editorView)
            }
            NSSound.beep()
            recordRenameResultLifecycle(workspaceEdit, newName: context.newName, applied: false)
            return false
        }

        guard let workspaceEditJSON = workspaceEdit.rawJSONString else {
            if context.showFeedback, let editorView = activeTab?.editCore.editorView {
                presentLspResultFeedback(
                    AttoLspResultFeedback.failed(
                        .rename,
                        errorDescription: "Rename result could not be encoded for application."
                    ),
                    in: editorView
                )
            }
            NSSound.beep()
            recordRenameResultLifecycle(workspaceEdit, newName: context.newName, applied: false)
            return false
        }

        let applied = applyWorkspaceEditToActiveTab(
            parsed,
            workspaceEditJSON: workspaceEditJSON,
            documentURI: context.documentURI
        )
        recordRenameResultLifecycle(workspaceEdit, newName: context.newName, applied: applied)
        return applied
    }

    func recordRenameResultLifecycle(_ json: String, newName: String, applied: Bool) {
        let workspaceEdit = AttoWorkspaceEditParser.parse(json)
        lspResultEventStream.record(
            family: "rename",
            title: "Rename: \(newName)",
            payload: .rename(
                newName: newName,
                documentCount: workspaceEdit?.documents.count ?? 0,
                resourceOperationCount: workspaceEdit?.resourceOperations.count ?? 0,
                applied: applied
            )
        )
    }

    func recordRenameResultLifecycle(_ workspaceEdit: EcuLspWorkspaceEdit, newName: String, applied: Bool) {
        let parsed = AttoWorkspaceEditParser.parse(workspaceEdit)
        lspResultEventStream.record(
            family: "rename",
            title: "Rename: \(newName)",
            payload: .rename(
                newName: newName,
                documentCount: parsed.documents.count,
                resourceOperationCount: parsed.resourceOperations.count,
                applied: applied
            )
        )
    }

    func renameDialogSeedInActiveTab(
        prepareRenameResultJSON: String? = nil,
        fallback fallbackSeed: AttoLspRenameSupport.DialogSeed? = nil
    ) -> AttoLspRenameSupport.DialogSeed {
        guard let tab = activeTab else {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
        do {
            let selected = try tab.editCore.editor.selectedText()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let text = try tab.editCore.editor.text()
            let fallback = fallbackSeed ?? AttoLspRenameSupport.DialogSeed(
                initialName: AttoLspRenameSupport.candidateName(
                    documentText: text,
                    selectedText: selected,
                    caretOffset: offsets.end
                ),
                placeholder: nil
            )
            return AttoLspRenameSupport.dialogSeed(
                documentText: text,
                selectedText: selected,
                caretOffset: offsets.end,
                prepareRenameResultJSON: prepareRenameResultJSON,
                fallback: fallback
            )
        } catch {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
    }

    func renameDialogSeedInActiveTab(
        prepareRenameResult: EcuLspPrepareRenameResult?,
        fallback fallbackSeed: AttoLspRenameSupport.DialogSeed? = nil
    ) -> AttoLspRenameSupport.DialogSeed {
        guard let tab = activeTab else {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
        do {
            let selected = try tab.editCore.editor.selectedText()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let text = try tab.editCore.editor.text()
            let fallback = fallbackSeed ?? AttoLspRenameSupport.DialogSeed(
                initialName: AttoLspRenameSupport.candidateName(
                    documentText: text,
                    selectedText: selected,
                    caretOffset: offsets.end
                ),
                placeholder: nil
            )
            return AttoLspRenameSupport.dialogSeed(
                documentText: text,
                selectedText: selected,
                caretOffset: offsets.end,
                prepareRenameResult: prepareRenameResult,
                fallback: fallback
            )
        } catch {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
    }
}
