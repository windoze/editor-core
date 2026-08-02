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
                documentURI: tab.fileURL.absoluteString,
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
        for pane in tab.panes {
            pane.layoutSubtreeIfNeeded()
            pane.editorView.kickProcessingPoll()
            pane.editorView.needsDisplay = true
            pane.needsDisplay = true
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
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
