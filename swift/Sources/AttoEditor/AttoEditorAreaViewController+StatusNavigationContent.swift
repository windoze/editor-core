import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Status bar

    var activeTab: AttoEditorTab? {
        if let coreActiveTab = coreProjectedActiveTab() {
            return coreActiveTab
        }
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    func updateWindowTitle() {
        guard let win = view.window else { return }
        guard let tab = activeTab else {
            win.title = "AttoEditor"
            return
        }

        let name = projectedFileURL(for: tab).lastPathComponent
        if refreshTabDirtyState(tab) {
            win.title = "AttoEditor — ● \(name)"
        } else {
            win.title = "AttoEditor — \(name)"
        }
    }

    func handleTabDidMutateDocumentText(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.semanticTokensData = []
        tab.semanticTokensResultId = nil
        let preserveCompletionUI = shouldPreserveCompletionUIForCurrentTextMutation
        if selectedTabID == tabID {
            cancelSignatureHelpUI()
            if preserveCompletionUI == false {
                cancelCompletionUI()
            }
        }

        let didUnpreview = tab.isPreview
        if tab.isPreview {
            tab.isPreview = false
        }

        tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true
        syncCoreTabText(tab, markSaved: tab.isDirty == false)
        if didUnpreview {
            pinCoreTabIfPreview(tab)
        }

        refreshTabBar()
        updateWindowTitle()
        if didUnpreview {
            notifySessionStateChanged()
        }

        handleTabDidChangeSelection(tabID: tabID, causedByTextMutation: true)
    }

    func handleTabDidChangeSelection(tabID: UUID, causedByTextMutation: Bool) {
        guard let session = linkedEditingSession, session.tabID == tabID else { return }
        guard selectedTabID == tabID,
              let tab = tabs.first(where: { $0.id == tabID })
        else {
            linkedEditingSession = nil
            return
        }

        if causedByTextMutation {
            guard let selections = try? tab.editCore.editor.selections(),
                  selections.ranges.count == session.selectionCount,
                  selections.ranges.count > 1
            else {
                linkedEditingSession = nil
                return
            }
            linkedEditingSession = LinkedEditingSession(tabID: tabID, selectionCount: selections.ranges.count)
        } else {
            linkedEditingSession = nil
        }
    }

    func attachStatusObserver(to editorView: EditorCoreSkiaView) {
        activeViewportObserver = editorView.addViewportStateObserver { [weak self] in
            self?.updateStatusBar()
        }
    }

    func updateAlwaysPollProcessingForSelectedTab() {
        for tab in tabs {
            for editCore in tab.panes {
                editCore.alwaysPollProcessing = false
            }
        }

        guard let tab = activeTab else { return }
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            tab.editCore.alwaysPollProcessing = true
        }
    }

    func updateStatusBar() {
        drainProjectLspPanelLifecycleEvents()

        guard let tab = activeTab else {
            derivedStateStore.clearActive()
            problemsPanelController?.update(problems: [])
            clearDiagnosticMarkers()
            statusBarView.update(
                leftText: transientStatusText,
                languageId: nil,
                languageIsEnabled: false,
                lspText: nil,
                positionText: "Ln -, Col -",
                selectionText: nil,
                fileSizeText: nil
            )
            return
        }

        let editor = tab.editCore.editor
        let editorText = try? editor.text()
        if let editorText {
            markActiveDiagnosticsStaleIfNeeded(for: tab, text: editorText)
        }
        derivedStateStore.refreshActive(editor: editor)
        clearActiveDiagnosticsStaleIfDiagnosticsChanged(
            for: tab,
            diagnostics: derivedStateStore.active.diagnostics.diagnostics
        )
        let diagnosticsSnapshot = unifiedDiagnosticsSnapshot(
            for: tab,
            text: editorText,
            includeActiveDiagnostics: true
        )
        recordActiveDiagnosticsLifecycle(diagnosticsSnapshot, for: tab)
        updateProblemsPanelIfVisible(snapshot: diagnosticsSnapshot)
        updateDiagnosticMarkers(for: tab, projections: diagnosticsSnapshot.markerProjections)

        let (line1, col1): (UInt32, UInt32) = {
            do {
                let offsets = try editor.selectionOffsets()
                let pos = try editor.charOffsetToLogicalPosition(offset: offsets.end)
                return (pos.line + 1, pos.column + 1)
            } catch {
                return (0, 0)
            }
        }()

        let selectionText: String? = {
            do {
                let sel = try editor.selections()
                let totalSelected: UInt64 = sel.ranges.reduce(0) { acc, r in
                    let a = UInt64(r.start)
                    let b = UInt64(r.end)
                    let len = a <= b ? (b - a) : (a - b)
                    return acc + len
                }
                let cursors = sel.ranges.count
                if cursors <= 1, let primary = sel.ranges.first {
                    let a = primary.start
                    let b = primary.end
                    let start = min(a, b)
                    let end = max(a, b)
                    let len = UInt64(end - start)
                    if len == 0 {
                        return nil
                    }
                    let startPos = try editor.charOffsetToLogicalPosition(offset: start)
                    let endPos = try editor.charOffsetToLogicalPosition(offset: end)
                    return "Sel \(len) (\(startPos.line + 1):\(startPos.column + 1)-\(endPos.line + 1):\(endPos.column + 1))"
                }
                if totalSelected == 0 {
                    return "\(cursors) cursors"
                }
                return "Sel \(totalSelected) (\(cursors) cursors)"
            } catch {
                return nil
            }
        }()

        let documentURL = projectedFileURL(for: tab)

        let fileSizeText: String? = {
            do {
                let values = try documentURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize else { return nil }
                return AttoFormat.byteCount(Int64(size))
            } catch {
                return nil
            }
        }()

        let lspText: String? = {
            // Keep the status bar clean unless LSP is likely relevant.
            //
            // - Historically, AttoEditor only auto-enabled LSP for Rust.
            // - With configurable LSPs, show LSP status when it is enabled (any language), or for Rust files.
            let isRustFile = (documentURL.pathExtension.lowercased() == "rs")
            let isEnabled = (try? editor.lspIsEnabled()) == true
            guard isRustFile || isEnabled else { return nil }

            do {
                let status = try editor.lspStatusSnapshot()
                let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: isEnabled)
                if let detail = display.failureDetail {
                    presentLspFailureDetailIfNeeded(detail, editorView: tab.editCore.editorView)
                } else {
                    lastPresentedLspFailureDetail = nil
                }
                return display.text
            } catch {
                // Best-effort: never break status bar rendering because of FFI errors.
                return (try? editor.lspIsEnabled()) == true ? "LSP: on" : "LSP: off"
            }
        }()

        statusBarView.update(
            leftText: transientStatusText ?? statusBarLeftText(for: tab, diagnostics: diagnosticsSnapshot),
            languageId: tab.syntaxLanguageId,
            languageIsEnabled: true,
            lspText: lspText,
            positionText: "Ln \(line1), Col \(col1)",
            selectionText: selectionText,
            fileSizeText: fileSizeText
        )
    }

    func clearDiagnosticMarkers() {
        for tab in tabs {
            for pane in tab.panes {
                pane.minimapDiagnosticMarkers = []
                pane.gutterDiagnosticMarkers = []
            }
        }
    }

    func updateDiagnosticMarkers(for tab: AttoEditorTab, includeActiveDiagnostics: Bool) {
        let projections = unifiedDiagnosticsSnapshot(
            for: tab,
            includeActiveDiagnostics: includeActiveDiagnostics
        ).markerProjections
        updateDiagnosticMarkers(for: tab, projections: projections)
    }

    func updateDiagnosticMarkers(
        for tab: AttoEditorTab,
        projections: [AttoDiagnosticMarkerProjection]
    ) {
        let minimapMarkers = projections.map {
            EditorCoreSkiaMinimapMarker(
                logicalLine: $0.logicalLine,
                kind: minimapMarkerKind(for: $0.severity)
            )
        }
        let gutterMarkers = projections.map {
            EditorCoreSkiaGutterDiagnosticMarker(
                logicalLine: $0.logicalLine,
                charOffset: $0.charOffset,
                kind: gutterMarkerKind(for: $0.severity)
            )
        }

        for pane in tab.panes {
            pane.minimapDiagnosticMarkers = minimapMarkers
            pane.gutterDiagnosticMarkers = gutterMarkers
        }
    }

    func updateProblemsPanelIfVisible(snapshot: AttoUnifiedDiagnosticsSnapshot) {
        guard problemsPanelController?.isVisible == true else { return }
        problemsPanelController?.update(problems: snapshot.problems)
    }

    func unifiedDiagnosticsSnapshot(
        for tab: AttoEditorTab,
        text: String? = nil,
        includeActiveDiagnostics: Bool
    ) -> AttoUnifiedDiagnosticsSnapshot {
        guard let text = text ?? (try? tab.editCore.editor.text()) else { return .empty }
        return AttoDiagnosticsModel.snapshot(
            activeDiagnostics: derivedStateStore.active.diagnostics.diagnostics,
            includeActiveDiagnostics: includeActiveDiagnostics,
            workspaceDiagnostics: workspaceProblemsStore.diagnostics,
            workspaceMarkers: workspaceProblemsStore.diagnosticMarkerProjections(),
            tabURL: projectedFileURL(for: tab),
            text: text,
            logicalPositionForOffset: { offset in
                try? tab.editCore.editor.charOffsetToLogicalPosition(offset: offset)
            }
        )
    }

    func statusBarLeftText(
        for tab: AttoEditorTab,
        diagnostics: AttoUnifiedDiagnosticsSnapshot
    ) -> String? {
        let parts = [
            diagnostics.problemsStatusText,
            derivedStateStore.active.foldedStatusText,
            derivedStateStore.active.codeLensStatusText,
        ].compactMap { $0 }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " | ")
    }

    func markActiveDiagnosticsStaleIfNeeded(for tab: AttoEditorTab, text: String) {
        let fingerprint = DiagnosticsTextFingerprint(text)
        if let previous = activeDiagnosticsTextFingerprintsByTabID[tab.id], previous != fingerprint {
            activeDiagnosticsStaleReasonsByTabID[tab.id] = .documentEdited
            markCurrentLspResultPanelsStale(reason: "document edited")
        }
        activeDiagnosticsTextFingerprintsByTabID[tab.id] = fingerprint
    }

    func markCurrentLspResultPanelsStale(reason: String) {
        let state = AttoLspResultLifecycleState.stale(reason: reason)
        if let entry = lspLocationResultStore.updateCurrentState(state) {
            lspLocationPanelController?.update(entry: entry)
        }
        if let entry = lspSymbolResultStore.updateCurrentState(state) {
            lspSymbolPanelController?.update(entry: entry)
        }
    }

    func markCurrentLspLocationResultError(_ message: AttoLspResultFeedback.Message) {
        if let entry = lspLocationResultStore.updateCurrentState(.error(message: message.statusText)) {
            lspLocationPanelController?.update(entry: entry)
        }
    }

    func markCurrentLspSymbolResultError(_ message: AttoLspResultFeedback.Message) {
        if let entry = lspSymbolResultStore.updateCurrentState(.error(message: message.statusText)) {
            lspSymbolPanelController?.update(entry: entry)
        }
    }

    func drainProjectLspPanelLifecycleEvents() {
        guard let coreDocuments else { return }

        do {
            let requestSnapshot = try coreDocuments.lspRequestEvents(after: coreLspRequestEventCursor)
            coreLspRequestEventCursor = requestSnapshot.latestSequence
            for event in requestSnapshot.events {
                recordProjectLspPanelError(
                    source: .request,
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    family: event.family,
                    title: event.title,
                    slot: event.slot,
                    method: event.method,
                    requestId: event.requestId,
                    status: event.status,
                    errorMessage: event.errorMessage
                )
            }

            let resultSnapshot = try coreDocuments.lspResultEvents(after: coreLspResultEventCursor)
            coreLspResultEventCursor = resultSnapshot.latestSequence
            for event in resultSnapshot.events {
                recordProjectLspPanelError(
                    source: .result,
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    family: event.family,
                    title: event.title,
                    slot: event.slot,
                    method: event.method,
                    requestId: event.requestId,
                    status: event.status,
                    errorMessage: event.errorMessage
                )
            }
        } catch {
            NSLog("AttoEditor: project LSP panel lifecycle event drain failed: %@", String(describing: error))
        }
    }

    @discardableResult
    func recordProjectLspPanelError(
        source: AttoProjectLspPanelErrorEvent.Source,
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        family: String,
        title: String,
        slot: String,
        method: String,
        requestId: UInt64,
        status: String,
        errorMessage: String?
    ) -> AttoProjectLspPanelErrorEvent? {
        guard Self.isProjectLspPanelErrorStatus(status),
              let panelFamily = Self.projectLspPanelFamily(family: family, slot: slot)
        else {
            return nil
        }

        let message = Self.projectLspPanelErrorMessage(title: title, status: status, errorMessage: errorMessage)
        let event = projectLspPanelErrorEventStore.record(
            source: source,
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            family: family,
            title: title,
            slot: slot,
            method: method,
            requestId: requestId,
            status: status,
            message: message
        )

        switch panelFamily {
        case .locations:
            if let entry = lspLocationResultStore.updateCurrentState(.error(message: message)) {
                lspLocationPanelController?.update(entry: entry)
            }
        case .symbols:
            if let entry = lspSymbolResultStore.updateCurrentState(.error(message: message)) {
                lspSymbolPanelController?.update(entry: entry)
            }
        }

        return event
    }

    static func isProjectLspPanelErrorStatus(_ status: String) -> Bool {
        switch EcuLspRequestStatus(rawValue: status) {
        case .error, .timeout:
            return true
        case .pending, .success, .empty, .stale, .mismatched, .canceled, .unknown(_):
            return EcuLspResultStatus(rawValue: status) == .error
        }
    }

    static func projectLspPanelFamily(family: String, slot: String) -> ProjectLspPanelFamily? {
        if family == "locations" {
            return .locations
        }
        if family == "symbols" {
            return .symbols
        }

        switch slot {
        case "definition",
             "declaration",
             "type_definition",
             "implementation",
             "references":
            return .locations
        case "document_symbols",
             "workspace_symbols":
            return .symbols
        default:
            return nil
        }
    }

    static func projectLspPanelErrorMessage(
        title: String,
        status: String,
        errorMessage: String?
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = trimmedTitle.isEmpty ? "LSP request" : trimmedTitle
        if let errorMessage {
            let trimmedMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty == false {
                return "\(fallbackTitle): \(trimmedMessage)"
            }
        }
        return "\(fallbackTitle): \(status)"
    }

    func clearActiveDiagnosticsStaleIfDiagnosticsChanged(
        for tab: AttoEditorTab,
        diagnostics: [EcuDiagnostic]
    ) {
        if let previous = activeDiagnosticsBaselinesByTabID[tab.id], previous != diagnostics {
            activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tab.id)
        }
        activeDiagnosticsBaselinesByTabID[tab.id] = diagnostics
    }

    func clearDiagnosticsLifecycleState(forTabID tabID: UUID) {
        activeDiagnosticsTextFingerprintsByTabID.removeValue(forKey: tabID)
        activeDiagnosticsBaselinesByTabID.removeValue(forKey: tabID)
        activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tabID)
    }

    func recordLspResultLifecycleEvent<Snapshot>(
        _ entry: AttoLspResultLifecycleEntry<Snapshot>,
        payload: AttoLspResultLifecycleEvent.Payload
    ) {
        lspResultEventStream.record(
            family: entry.family,
            title: entry.title,
            recordedAt: entry.recordedAt,
            sourceSequence: entry.sequence,
            payload: payload
        )
    }

    func recordActiveDiagnosticsLifecycle(
        _ snapshot: AttoUnifiedDiagnosticsSnapshot,
        for tab: AttoEditorTab
    ) {
        let documentURL = projectedFileURL(for: tab)
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .activeTab(tabID: tab.id, fileURL: documentURL.standardizedFileURL),
            problems: snapshot.problems,
            markerProjections: snapshot.markerProjections,
            statusText: snapshot.problemsStatusText,
            staleReason: activeDiagnosticsStaleReasonsByTabID[tab.id]
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.active",
            title: documentURL.lastPathComponent
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    func recordWorkspaceDiagnosticsLifecycle(
        problems: [AttoUnifiedDiagnosticProblem]
    ) {
        let statusText: String? = {
            let count = problems.count
            guard count > 0 else { return nil }
            return count == 1 ? "Problems: 1" : "Problems: \(count)"
        }()
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .workspace,
            problems: problems,
            markerProjections: [],
            statusText: statusText,
            staleReason: workspaceDiagnosticsStaleReason
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.workspace",
            title: "Workspace Problems"
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    func diagnosticsLifecycleEvents(
        after sequence: UInt64
    ) -> [AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>] {
        diagnosticsLifecycleStore.entries(after: sequence)
    }

    func updateWorkspaceDiagnosticMarkersForOpenTabs() {
        for tab in tabs {
            updateDiagnosticMarkers(for: tab, includeActiveDiagnostics: tab.id == activeTab?.id)
        }
    }

    func minimapMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaMinimapMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    func gutterMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaGutterDiagnosticMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    func setTransientStatusText(_ text: String?) {
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = normalized?.isEmpty == false ? normalized : nil
        guard transientStatusText != next else { return }
        transientStatusText = next
        updateStatusBar()
    }

    func setSyntaxLanguageForActiveTab(languageId: String?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        // "Plain Tex" => disable all syntax engines.
        if languageId == nil {
            tab.editCore.editor.lspDisable()
            tab.editCore.editor.treeSitterDisable()
            tab.editCore.editor.sublimeDisable()
            tab.syntaxLanguageId = nil
            applyLanguageConfiguration(for: tab)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
            return
        }

        let lang = (languageId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if lang.isEmpty {
            NSSound.beep()
            return
        }

        // Force Tree-sitter with an explicit language id.
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            // Best-effort (each editor view owns its own registry state).
            try? tab.editCore.editor.treeSitterSetRegistryJSON(registryJSON)
        }

        tab.editCore.editor.lspDisable()
        tab.editCore.editor.sublimeDisable()

        do {
            try tab.editCore.editor.treeSitterEnableLanguage(lang)
            tab.syntaxLanguageId = lang
            applyLanguageConfiguration(for: tab)
            tab.editCore.editorView.kickProcessingPoll()
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
            NSLog(
                "AttoEditor: failed to set Tree-sitter language %@ for %@: %@",
                lang,
                tab.fileURL.path,
                String(describing: error)
            )
            updateStatusBar()
        }
    }

    // MARK: - Navigation

    func navigate(tab: AttoEditorTab, to location: AttoCommandLine.FileLocation) {
        let line1 = max(1, location.line1)
        let column1 = max(1, location.column1 ?? 1)

        do {
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = Self.charOffsetForLineColumn1(text: text, line1: line1, column1: column1)
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    static func parseGoToLineTarget(_ raw: String) -> GoToLineTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let parts = trimmed
            .split(omittingEmptySubsequences: false) { ch in ch == ":" || ch == "," }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let line1 = Int(parts[0]), line1 > 0 else { return nil }

        let column1: Int
        if parts.count == 2 {
            guard let parsedColumn = Int(parts[1]), parsedColumn > 0 else { return nil }
            column1 = parsedColumn
        } else {
            column1 = 1
        }

        return GoToLineTarget(line1: line1, column1: column1)
    }

    @discardableResult
    func goToLineInActiveTab(input: String) -> Bool {
        guard let target = Self.parseGoToLineTarget(input) else {
            NSSound.beep()
            return false
        }
        return goToLineInActiveTab(line1: target.line1, column1: target.column1)
    }

    @discardableResult
    func goToLineInActiveTab(line1: Int, column1: Int = 1) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let line0 = UInt32(clamping: max(1, line1) - 1)
        let column0 = UInt32(clamping: max(1, column1) - 1)
        do {
            _ = try tab.editCore.editor.moveTo(line: line0, column: column0)
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            tab.editCore.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: go to line failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func promptGoToLineInActiveTab(initialInput: String = "") -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initialInput
        field.placeholderString = "Line or line:column"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a 1-based line number, optionally followed by :column."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return goToLineInActiveTab(input: field.stringValue)
    }

    static func charOffsetForLineColumn1(text: String, line1: Int, column1: Int) -> UInt32 {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let targetLineIdx = max(0, line1 - 1)
        if targetLineIdx >= lines.count {
            return UInt32(text.count)
        }

        var offset: Int = 0
        if targetLineIdx > 0 {
            for i in 0..<targetLineIdx {
                offset += lines[i].count
                offset += 1 // '\n'
            }
        }

        let lineText = lines[targetLineIdx]
        let col0 = max(0, min(lineText.count, column1 - 1))
        offset += col0
        return UInt32(max(0, offset))
    }
}
