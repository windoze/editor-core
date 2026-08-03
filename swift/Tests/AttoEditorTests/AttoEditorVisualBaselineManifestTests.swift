import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorVisualBaselineManifestTests: XCTestCase {
    func testVisualBaselineManifestDeclaresRunnableFixtures() throws {
        let manifest = try AttoVisualBaselineManifest.load()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertFalse(manifest.cases.isEmpty)
        XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
        XCTAssertEqual(Set(manifest.cases.map(\.artifactName)).count, manifest.cases.count)
        XCTAssertEqual(Set(manifest.cases.map(\.baseline)).count, manifest.cases.count)

        for visualCase in manifest.cases {
            XCTAssertFalse(visualCase.id.isEmpty)
            XCTAssertNotNil(
                visualCase.artifactName.range(
                    of: #"^[a-z0-9][a-z0-9-]*$"#,
                    options: .regularExpression
                )
            )
            XCTAssertGreaterThan(visualCase.window.width, 0)
            XCTAssertGreaterThan(visualCase.window.height, 0)
            XCTAssertGreaterThan(visualCase.scale, 0)
            XCTAssertEqual(visualCase.scale, 1.0, visualCase.id)
            XCTAssertGreaterThanOrEqual(visualCase.maxDifferentPixelRatio, 0)
            XCTAssertLessThanOrEqual(visualCase.maxDifferentPixelRatio, 1)
            XCTAssertTrue(visualCase.baseline.hasSuffix(".png"))
            XCTAssertTrue(visualCase.showReplaceBar == false || visualCase.showFindBar)
            XCTAssertGreaterThan(visualCase.captureTarget.expectedWidth(defaultWindow: visualCase.window), 0)
            XCTAssertGreaterThan(visualCase.captureTarget.expectedHeight(defaultWindow: visualCase.window), 0)
            if visualCase.captureTarget.kind.requiresIdentifier {
                XCTAssertNotNil(visualCase.captureTarget.identifier)
                XCTAssertFalse(visualCase.captureTarget.identifier?.isEmpty ?? true)
            }
            if visualCase.captureTarget.kind.requiresExplicitSize {
                XCTAssertTrue(visualCase.captureTarget.hasExplicitSize, visualCase.id)
            }
            if let fontSizePoints = visualCase.fontSizePoints {
                XCTAssertGreaterThan(fontSizePoints, 0, visualCase.id)
            }
            if visualCase.selectionRanges.isEmpty == false {
                XCTAssertLessThan(Int(visualCase.primarySelectionIndex), visualCase.selectionRanges.count, visualCase.id)
            }
            for range in visualCase.selectionRanges {
                XCTAssertLessThanOrEqual(range.start, range.end, visualCase.id)
            }
            for range in visualCase.collapsedFolds {
                XCTAssertLessThanOrEqual(range.startLine, range.endLine, visualCase.id)
            }

            for fixture in visualCase.allFixturePaths {
                let fixtureURL = try visualCase.fixtureURL(path: fixture)
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
            }
            if let activeFixture = visualCase.activeFixture {
                XCTAssertTrue(visualCase.allFixturePaths.contains(activeFixture))
            }
            _ = try visualCase.makeTheme()
        }
    }

    func testVisualBaselineFixturesCaptureReviewArtifactsAndCanCompareExternalBaselines() throws {
        let manifest = try AttoVisualBaselineManifest.load()
        for visualCase in manifest.cases {
            try runVisualBaselineCase(visualCase)
        }
    }

    private func runVisualBaselineCase(_ visualCase: AttoVisualBaselineCase) throws {
        let tempDir = try makeTemporaryDirectory(caseID: visualCase.id)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let documentURLs = try materializeFixtures(for: visualCase, in: tempDir)
        let primaryDocumentURL = try XCTUnwrap(documentURLs[visualCase.fixture])

        let preferences = try makeVisualPreferences(caseID: visualCase.id)
        var configurationSnapshot = preferences.effectiveConfigurationSnapshot(workspaceRootURL: tempDir)
        visualCase.applyConfigurationOverrides(to: &configurationSnapshot)

        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: try visualCase.makeTheme(),
            workspaceRootURL: tempDir,
            configurationSnapshot: configurationSnapshot,
            preferences: preferences
        )
        let window = attachToWindow(vc, size: visualCase.window.nsSize)
        defer { window.close() }

        XCTAssertTrue(
            vc.openFile(url: primaryDocumentURL, mode: AttoEditorAreaViewController.OpenMode.pinned),
            visualCase.id
        )
        for fixture in visualCase.additionalFixtures {
            let url = try XCTUnwrap(documentURLs[fixture])
            XCTAssertTrue(vc.openFile(url: url, mode: AttoEditorAreaViewController.OpenMode.pinned), visualCase.id)
        }
        if let activeFixture = visualCase.activeFixture {
            let url = try XCTUnwrap(documentURLs[activeFixture])
            XCTAssertTrue(vc.openFile(url: url, mode: AttoEditorAreaViewController.OpenMode.pinned), visualCase.id)
        }
        if visualCase.splitActiveTabRight {
            XCTAssertTrue(vc.splitActiveTabRight(), visualCase.id)
        }
        if visualCase.showReplaceBar {
            vc.showReplaceBar()
        } else if visualCase.showFindBar {
            vc.showFindBar()
        }
        try applyScenarioActions(visualCase, to: vc, documentURLs: documentURLs, tempDir: tempDir)
        vc.view.layoutSubtreeIfNeeded()

        let captureView = try captureTargetView(for: visualCase, in: window, controller: vc, fallbackView: vc.view)
        captureView.layoutSubtreeIfNeeded()
        let expectedSize = NSSize(
            width: visualCase.captureTarget.expectedWidth(defaultWindow: visualCase.window),
            height: visualCase.captureTarget.expectedHeight(defaultWindow: visualCase.window)
        )
        let snapshot = try AttoVisualSnapshot.capture(
            view: captureView,
            scale: CGFloat(visualCase.scale),
            forcedSize: visualCase.captureTarget.hasExplicitSize ? expectedSize : nil
        )
        XCTAssertEqual(
            snapshot.width,
            visualCase.captureTarget.expectedWidth(defaultWindow: visualCase.window),
            visualCase.id
        )
        XCTAssertEqual(
            snapshot.height,
            visualCase.captureTarget.expectedHeight(defaultWindow: visualCase.window),
            visualCase.id
        )

        let artifactDirectory = try visualArtifactDirectory(fallbackRoot: tempDir)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let actualArtifact = artifactDirectory.appendingPathComponent("\(visualCase.artifactName)-actual.png")
        try snapshot.writePNG(to: actualArtifact)
        XCTAssertTrue(try Data(contentsOf: actualArtifact).starts(with: [0x89, 0x50, 0x4E, 0x47]), visualCase.id)

        if let recordRoot = try recordBaselineRootURL() {
            let baselineURL = recordRoot.appendingPathComponent(visualCase.baseline)
            try FileManager.default.createDirectory(
                at: baselineURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try snapshot.writePNG(to: baselineURL)
            XCTAssertTrue(try Data(contentsOf: baselineURL).starts(with: [0x89, 0x50, 0x4E, 0x47]), visualCase.id)
        }

        guard let baselineRoot = externalBaselineRootURL() else {
            return
        }

        let expected = try AttoVisualSnapshot.readPNG(from: baselineRoot.appendingPathComponent(visualCase.baseline))
        let comparison = try AttoVisualSnapshotHarness.compare(
            actual: snapshot,
            expected: expected,
            artifactDirectory: artifactDirectory,
            name: visualCase.artifactName,
            perChannelTolerance: visualCase.perChannelTolerance,
            maxDifferentPixelRatio: visualCase.maxDifferentPixelRatio
        )
        XCTAssertTrue(
            comparison.passed,
            """
            visual baseline mismatch for \(visualCase.id): \
            \(comparison.differentPixels)/\(comparison.totalPixels) pixels differ, \
            max channel delta \(comparison.maxChannelDelta), artifacts: \(artifactDirectory.path)
            """
        )
    }

    private func materializeFixtures(
        for visualCase: AttoVisualBaselineCase,
        in tempDir: URL
    ) throws -> [String: URL] {
        var documentURLs: [String: URL] = [:]
        for fixture in visualCase.allFixturePaths {
            let fixtureURL = try visualCase.fixtureURL(path: fixture)
            let documentURL = tempDir.appendingPathComponent(fixtureURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: documentURL.path) {
                try FileManager.default.removeItem(at: documentURL)
            }
            try FileManager.default.copyItem(at: fixtureURL, to: documentURL)
            documentURLs[fixture] = documentURL
        }
        return documentURLs
    }

    private func makeVisualPreferences(caseID: String) throws -> AttoPreferences {
        let suiteName = "atto_visual_baseline_\(caseID)_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return AttoPreferences(defaults: defaults, env: [:])
    }

    private func applyScenarioActions(
        _ visualCase: AttoVisualBaselineCase,
        to vc: AttoEditorAreaViewController,
        documentURLs: [String: URL],
        tempDir: URL
    ) throws {
        if let foldingRanges = visualCase.foldingRanges {
            XCTAssertTrue(vc.applyFoldingRangesResultToActiveTab(foldingRanges), visualCase.id)
        }
        for fold in visualCase.collapsedFolds {
            XCTAssertTrue(
                vc.executeActiveEditorCommandJSON(
                    """
                    {"kind":"style","op":"fold","start_line":\(fold.startLine),"end_line":\(fold.endLine)}
                    """,
                    treatsAsTextMutation: false
                ),
                visualCase.id
            )
        }
        if let semanticTokens = visualCase.semanticTokens {
            XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(semanticTokens), visualCase.id)
        }
        if visualCase.diagnosticMarkers.isEmpty == false {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            vc.updateDiagnosticMarkers(
                for: tab,
                projections: visualCase.diagnosticMarkers.map(\.projection)
            )
        }
        if visualCase.selectionRanges.isEmpty == false {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            try tab.editCore.editor.setSelections(
                visualCase.selectionRanges.map(\.range),
                primaryIndex: visualCase.primarySelectionIndex
            )
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            vc.updateStatusBar()
            vc.view.window?.makeFirstResponder(tab.editCore.editorView)
        }
        if let activeDiagnostics = visualCase.activeDiagnostics {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            let documentURI = vc.projectedFileURL(for: tab).standardizedFileURL.absoluteString
            try tab.editCore.editor.lspApplyDiagnosticsJSON(
                try activeDiagnostics.resultJSON(documentURI: documentURI)
            )
            vc._updateStatusBarForTesting()
        }
        if let workspaceDiagnostics = visualCase.workspaceDiagnostics {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            let documentURI = vc.projectedFileURL(for: tab).standardizedFileURL.absoluteString
            XCTAssertTrue(
                vc.showWorkspaceDiagnosticsResultJSONInActiveTab(
                    try workspaceDiagnostics.resultJSON(
                        activeDocumentURI: documentURI,
                        documentURLs: documentURLs,
                        tempDir: tempDir
                    ),
                    showFeedback: false
                ),
                visualCase.id
            )
        }
        if let symbolResults = visualCase.lspSymbolResults {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            let documentURI = vc.projectedFileURL(for: tab).standardizedFileURL.absoluteString
            let symbols = symbolResults.symbols(documentURI: documentURI)
            switch symbolResults.presentation {
            case .quickPanel:
                vc.showLspSymbolResults(symbols, placeholder: symbolResults.placeholder)
            case .persistentPanel:
                vc.recordLspSymbolResultSnapshot(AttoEditorAreaViewController.LspSymbolResultSnapshot(
                    title: symbolResults.title,
                    symbols: symbols,
                    placeholder: symbolResults.placeholder
                ))
                XCTAssertTrue(vc.showLspSymbolPanel(), visualCase.id)
            }
        }
        if let locationResults = visualCase.lspLocationResults {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            let documentURI = vc.projectedFileURL(for: tab).standardizedFileURL.absoluteString
            XCTAssertTrue(
                vc.showLspLocationResultJSONInActiveTab(
                    try locationResults.resultJSON(documentURI: documentURI),
                    kind: locationResults.requestKind
                ),
                visualCase.id
            )
            if locationResults.presentation == .persistentPanel {
                XCTAssertTrue(vc.showLspLocationPanel(), visualCase.id)
            }
        }
        if let hierarchyResults = visualCase.hierarchyResults {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            let documentURI = vc.projectedFileURL(for: tab).standardizedFileURL.absoluteString
            XCTAssertTrue(
                vc._showHierarchyResultJSONForTesting(
                    try hierarchyResults.resultJSON(documentURI: documentURI),
                    kind: hierarchyResults.kind.rawValue,
                    showFeedback: false
                ),
                visualCase.id
            )
        }
        if let codeLensResults = visualCase.codeLensResults {
            XCTAssertTrue(
                vc._applyCodeLensResultJSONForTesting(try codeLensResults.resultJSON()),
                visualCase.id
            )
        }
        if let inlayHints = visualCase.inlayHints {
            XCTAssertTrue(
                vc._applyInlayHintsResultJSONForTesting(try inlayHints.resultJSON()),
                visualCase.id
            )
        }
        if let documentLinks = visualCase.documentLinks {
            XCTAssertTrue(
                vc._applyDocumentLinksResultJSONForTesting(try documentLinks.resultJSON()),
                visualCase.id
            )
        }
        if let documentColors = visualCase.documentColors {
            XCTAssertTrue(
                vc.showDocumentColorPanelResultJSONInActiveTab(
                    try documentColors.resultJSON(),
                    showFeedback: false
                ),
                visualCase.id
            )
        }
        if let codeActionResults = visualCase.codeActionResults {
            XCTAssertTrue(
                vc._showCodeActionResultJSONForTesting(
                    try codeActionResults.resultJSON(),
                    onlyKinds: codeActionResults.onlyKinds,
                    showFeedback: false
                ),
                visualCase.id
            )
        }
        if let completionPopup = visualCase.completionPopup {
            XCTAssertTrue(
                vc._showCompletionResultJSONForTesting(try completionPopup.resultJSON(), showFeedback: false),
                visualCase.id
            )
        }
        if let hoverPopover = visualCase.hoverPopover {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            vc.showHoverPopover(
                text: hoverPopover.text,
                at: hoverPopover.info,
                in: tab.editCore.editorView
            )
        }
        if let signatureHelpPopover = visualCase.signatureHelpPopover {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            vc.showSignatureHelpPopover(
                display: signatureHelpPopover.display,
                in: tab.editCore.editorView
            )
        }
        if let failurePopover = visualCase.failurePopover {
            let tab = try XCTUnwrap(vc.activeTab, visualCase.id)
            vc.showWorkspaceEditPopover(
                text: failurePopover.text,
                in: tab.editCore.editorView
            )
        }
        if let workspaceEditJSONPreview = visualCase.workspaceEditJSONPreview {
            try workspaceEditJSONPreview.materializeSupportFiles(in: tempDir)
            var didShowPreview = false
            vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
                let panelController = AttoWorkspaceEditPreviewPanelController()
                panelController.showForTesting(relativeTo: vc.view.window, preview: preview)
                vc.workspaceEditPreviewPanelController = panelController
                didShowPreview = true
                return .cancel
            }
            defer { vc._setWorkspaceEditPreviewDecisionProviderForTesting(nil) }
            XCTAssertFalse(
                vc.applyWorkspaceEditJSONToActiveTab(try workspaceEditJSONPreview.resultJSON(tempDir: tempDir)),
                visualCase.id
            )
            XCTAssertTrue(didShowPreview, visualCase.id)
        }
        if let workspaceEditJSONApplySummary = visualCase.workspaceEditJSONApplySummary {
            try workspaceEditJSONApplySummary.materializeSupportFiles(in: tempDir)
            if workspaceEditJSONApplySummary.makeActiveDocumentDirty {
                XCTAssertTrue(
                    vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#),
                    visualCase.id
                )
            }
            vc._setWorkspaceEditPreviewDecisionProviderForTesting { _ in .apply }
            defer { vc._setWorkspaceEditPreviewDecisionProviderForTesting(nil) }
            XCTAssertEqual(
                vc.applyWorkspaceEditJSONToActiveTab(try workspaceEditJSONApplySummary.resultJSON(tempDir: tempDir)),
                workspaceEditJSONApplySummary.expectedApplied,
                visualCase.id
            )
            try workspaceEditJSONApplySummary.assertApplyState(in: vc, tempDir: tempDir, caseID: visualCase.id)
            if workspaceEditJSONApplySummary.undoAfterApply {
                XCTAssertEqual(
                    vc._undoLastCoreWorkspaceEditTransactionForTesting(),
                    workspaceEditJSONApplySummary.expectedUndo,
                    visualCase.id
                )
                try workspaceEditJSONApplySummary.assertUndoState(in: vc, tempDir: tempDir, caseID: visualCase.id)
            }
        }
        if let workspaceEditPreview = visualCase.workspaceEditPreview {
            let panelController = AttoWorkspaceEditPreviewPanelController()
            let preview = try workspaceEditPreview.preview(tempDir: tempDir)
            panelController.showForTesting(relativeTo: vc.view.window, preview: preview)
            vc.workspaceEditPreviewPanelController = panelController
        }
        if let persistentPanel = visualCase.persistentPanel {
            switch persistentPanel {
            case .problemsPanel:
                XCTAssertTrue(vc.showProblemsPanelInActiveTab(), visualCase.id)
            case .workspaceProblemsPanel:
                XCTAssertTrue(vc.showWorkspaceProblemsPanelInActiveTab(), visualCase.id)
            case .lspWorkbenchPanel:
                XCTAssertTrue(vc.showLspWorkbenchPanel(), visualCase.id)
            case .hierarchyPanel:
                XCTAssertTrue(vc.showHierarchyPanelInActiveTab(), visualCase.id)
            case .codeLensPanel:
                XCTAssertTrue(vc.showCodeLensPanelInActiveTab(), visualCase.id)
            case .inlayHintPanel:
                XCTAssertTrue(vc.showInlayHintsPanelInActiveTab(), visualCase.id)
            case .documentLinkPanel:
                XCTAssertTrue(vc.showDocumentLinksPanelInActiveTab(), visualCase.id)
            case .documentColorPanel:
                XCTAssertTrue(vc._documentColorPanelIsVisibleForTesting(), visualCase.id)
            }
        }
    }

    private func captureTargetView(
        for visualCase: AttoVisualBaselineCase,
        in window: NSWindow,
        controller vc: AttoEditorAreaViewController,
        fallbackView: NSView
    ) throws -> NSView {
        switch visualCase.captureTarget.kind {
        case .mainWindow:
            return fallbackView
        case .childWindow:
            guard let identifier = visualCase.captureTarget.identifier else {
                throw AttoVisualBaselineError.invalidManifest(
                    "\(visualCase.id) child-window capture target requires an identifier"
                )
            }
            guard let childWindow = window.childWindows?.first(where: { $0.identifier?.rawValue == identifier }),
                  let contentView = childWindow.contentView
            else {
                throw AttoVisualBaselineError.invalidManifest(
                    "\(visualCase.id) missing child window capture target: \(identifier)"
                )
            }
            if let width = visualCase.captureTarget.width,
               let height = visualCase.captureTarget.height
            {
                contentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            }
            contentView.needsLayout = true
            contentView.layoutSubtreeIfNeeded()
            return contentView
        case .hoverPopover:
            guard let contentView = vc.hoverPopover?.contentViewController?.view else {
                throw AttoVisualBaselineError.invalidManifest(
                    "\(visualCase.id) missing hover popover capture target"
                )
            }
            preparePopoverCaptureView(contentView, for: visualCase)
            return contentView
        case .signatureHelpPopover:
            guard let contentView = vc.signatureHelpPopover?.contentViewController?.view else {
                throw AttoVisualBaselineError.invalidManifest(
                    "\(visualCase.id) missing signature help popover capture target"
                )
            }
            preparePopoverCaptureView(contentView, for: visualCase)
            return contentView
        case .workspaceEditPopover:
            guard let contentView = vc.workspaceEditPopover?.contentViewController?.view else {
                throw AttoVisualBaselineError.invalidManifest(
                    "\(visualCase.id) missing workspace edit popover capture target"
                )
            }
            preparePopoverCaptureView(contentView, for: visualCase)
            return contentView
        }
    }

    private func preparePopoverCaptureView(
        _ contentView: NSView,
        for visualCase: AttoVisualBaselineCase
    ) {
        if let width = visualCase.captureTarget.width,
           let height = visualCase.captureTarget.height
        {
            contentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }

    private func makeTemporaryDirectory(caseID: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AttoEditorVisualBaselineManifestTests-\(caseID)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attachToWindow(
        _ vc: AttoEditorAreaViewController,
        size: NSSize
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.setContentSize(size)
        vc.view.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func visualArtifactDirectory(fallbackRoot: URL) throws -> URL {
        if let configured = nonEmptyEnvironmentURL("ATTO_VISUAL_ARTIFACT_DIR") {
            return configured
        }
        if let configured = try runtimeConfig()?.artifactRootURL {
            return configured
        }
        return fallbackRoot.appendingPathComponent("visual-artifacts", isDirectory: true)
    }

    private func externalBaselineRootURL() -> URL? {
        nonEmptyEnvironmentURL("ATTO_VISUAL_BASELINE_DIR")
    }

    private func recordBaselineRootURL() throws -> URL? {
        if let configured = nonEmptyEnvironmentURL("ATTO_VISUAL_RECORD_BASELINE_DIR") {
            return configured
        }
        return try runtimeConfig()?.recordBaselineRootURL
    }

    private func nonEmptyEnvironmentURL(_ key: String) -> URL? {
        guard let path = ProcessInfo.processInfo.environment[key], path.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func runtimeConfig() throws -> AttoVisualRuntimeConfig? {
        let explicitConfigURL = ProcessInfo.processInfo.environment["ATTO_VISUAL_BASELINE_CONFIG"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let defaultConfigURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/atto-visual-baseline-record.json")

        for configURL in [explicitConfigURL, defaultConfigURL].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                continue
            }
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AttoVisualRuntimeConfig.self, from: data)
        }
        return nil
    }
}

private struct AttoVisualRuntimeConfig: Decodable {
    let recordBaselineRoot: String?
    let artifactRoot: String?

    var recordBaselineRootURL: URL? {
        nonEmptyURL(recordBaselineRoot)
    }

    var artifactRootURL: URL? {
        nonEmptyURL(artifactRoot)
    }

    private func nonEmptyURL(_ path: String?) -> URL? {
        guard let path, path.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private struct AttoVisualBaselineManifest: Decodable {
    let schemaVersion: Int
    let cases: [AttoVisualBaselineCase]

    static func load() throws -> Self {
        let url = try resourceURL(path: "VisualBaselines/manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

private struct AttoVisualBaselineCase: Decodable, Equatable {
    let id: String
    let description: String
    let fixture: String
    let baseline: String
    let artifactName: String
    let themeName: String
    let window: AttoVisualBaselineWindow
    let scale: Double
    let additionalFixtures: [String]
    let activeFixture: String?
    let showFindBar: Bool
    let showReplaceBar: Bool
    let splitActiveTabRight: Bool
    let fontFamilies: [String]?
    let fontSizePoints: Double?
    let selectionRanges: [AttoVisualSelectionRange]
    let primarySelectionIndex: UInt32
    let foldingRanges: EcuLspFoldingRangeResult?
    let collapsedFolds: [AttoVisualFoldRange]
    let semanticTokens: EcuLspSemanticTokensResult?
    let diagnosticMarkers: [AttoVisualDiagnosticMarker]
    let activeDiagnostics: AttoVisualActiveDiagnostics?
    let workspaceDiagnostics: AttoVisualWorkspaceDiagnostics?
    let lspSymbolResults: AttoVisualLspSymbolResults?
    let lspLocationResults: AttoVisualLspLocationResults?
    let hierarchyResults: AttoVisualHierarchyResults?
    let codeLensResults: AttoVisualCodeLensResults?
    let inlayHints: AttoVisualInlayHints?
    let documentLinks: AttoVisualDocumentLinks?
    let documentColors: AttoVisualDocumentColors?
    let codeActionResults: AttoVisualCodeActionResults?
    let completionPopup: AttoVisualCompletionPopup?
    let hoverPopover: AttoVisualHoverPopover?
    let signatureHelpPopover: AttoVisualSignatureHelpPopover?
    let failurePopover: AttoVisualFailurePopover?
    let workspaceEditJSONPreview: AttoVisualWorkspaceEditJSONPreview?
    let workspaceEditJSONApplySummary: AttoVisualWorkspaceEditJSONApplySummary?
    let workspaceEditPreview: AttoVisualWorkspaceEditPreview?
    let persistentPanel: AttoVisualPersistentPanel?
    let captureTarget: AttoVisualCaptureTarget
    let perChannelTolerance: UInt8
    let maxDifferentPixelRatio: Double

    var allFixturePaths: [String] {
        [fixture] + additionalFixtures
    }

    func fixtureURL(path: String) throws -> URL {
        try resourceURL(path: path)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case fixture
        case baseline
        case artifactName
        case themeName = "theme"
        case window
        case scale
        case additionalFixtures
        case activeFixture
        case showFindBar
        case showReplaceBar
        case splitActiveTabRight
        case fontFamilies
        case fontSizePoints
        case selectionRanges
        case primarySelectionIndex
        case foldingRanges
        case collapsedFolds
        case semanticTokens
        case diagnosticMarkers
        case activeDiagnostics
        case workspaceDiagnostics
        case lspSymbolResults
        case lspLocationResults
        case hierarchyResults
        case codeLensResults
        case inlayHints
        case documentLinks
        case documentColors
        case codeActionResults
        case completionPopup
        case hoverPopover
        case signatureHelpPopover
        case failurePopover
        case workspaceEditJSONPreview
        case workspaceEditJSONApplySummary
        case workspaceEditPreview
        case persistentPanel
        case captureTarget
        case perChannelTolerance
        case maxDifferentPixelRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        fixture = try container.decode(String.self, forKey: .fixture)
        baseline = try container.decode(String.self, forKey: .baseline)
        artifactName = try container.decode(String.self, forKey: .artifactName)
        themeName = try container.decode(String.self, forKey: .themeName)
        window = try container.decode(AttoVisualBaselineWindow.self, forKey: .window)
        scale = try container.decode(Double.self, forKey: .scale)
        additionalFixtures = try container.decodeIfPresent([String].self, forKey: .additionalFixtures) ?? []
        activeFixture = try container.decodeIfPresent(String.self, forKey: .activeFixture)
        showFindBar = try container.decodeIfPresent(Bool.self, forKey: .showFindBar) ?? false
        showReplaceBar = try container.decodeIfPresent(Bool.self, forKey: .showReplaceBar) ?? false
        splitActiveTabRight = try container.decodeIfPresent(Bool.self, forKey: .splitActiveTabRight) ?? false
        fontFamilies = try container.decodeIfPresent([String].self, forKey: .fontFamilies)
        fontSizePoints = try container.decodeIfPresent(Double.self, forKey: .fontSizePoints)
        selectionRanges = try container.decodeIfPresent(
            [AttoVisualSelectionRange].self,
            forKey: .selectionRanges
        ) ?? []
        primarySelectionIndex = try container.decodeIfPresent(UInt32.self, forKey: .primarySelectionIndex) ?? 0
        foldingRanges = try container.decodeIfPresent(EcuLspFoldingRangeResult.self, forKey: .foldingRanges)
        collapsedFolds = try container.decodeIfPresent([AttoVisualFoldRange].self, forKey: .collapsedFolds) ?? []
        semanticTokens = try container.decodeIfPresent(EcuLspSemanticTokensResult.self, forKey: .semanticTokens)
        diagnosticMarkers = try container.decodeIfPresent(
            [AttoVisualDiagnosticMarker].self,
            forKey: .diagnosticMarkers
        ) ?? []
        activeDiagnostics = try container.decodeIfPresent(
            AttoVisualActiveDiagnostics.self,
            forKey: .activeDiagnostics
        )
        workspaceDiagnostics = try container.decodeIfPresent(
            AttoVisualWorkspaceDiagnostics.self,
            forKey: .workspaceDiagnostics
        )
        lspSymbolResults = try container.decodeIfPresent(AttoVisualLspSymbolResults.self, forKey: .lspSymbolResults)
        lspLocationResults = try container.decodeIfPresent(
            AttoVisualLspLocationResults.self,
            forKey: .lspLocationResults
        )
        hierarchyResults = try container.decodeIfPresent(
            AttoVisualHierarchyResults.self,
            forKey: .hierarchyResults
        )
        codeLensResults = try container.decodeIfPresent(
            AttoVisualCodeLensResults.self,
            forKey: .codeLensResults
        )
        inlayHints = try container.decodeIfPresent(AttoVisualInlayHints.self, forKey: .inlayHints)
        documentLinks = try container.decodeIfPresent(
            AttoVisualDocumentLinks.self,
            forKey: .documentLinks
        )
        documentColors = try container.decodeIfPresent(
            AttoVisualDocumentColors.self,
            forKey: .documentColors
        )
        codeActionResults = try container.decodeIfPresent(AttoVisualCodeActionResults.self, forKey: .codeActionResults)
        completionPopup = try container.decodeIfPresent(AttoVisualCompletionPopup.self, forKey: .completionPopup)
        hoverPopover = try container.decodeIfPresent(AttoVisualHoverPopover.self, forKey: .hoverPopover)
        signatureHelpPopover = try container.decodeIfPresent(
            AttoVisualSignatureHelpPopover.self,
            forKey: .signatureHelpPopover
        )
        failurePopover = try container.decodeIfPresent(AttoVisualFailurePopover.self, forKey: .failurePopover)
        workspaceEditJSONPreview = try container.decodeIfPresent(
            AttoVisualWorkspaceEditJSONPreview.self,
            forKey: .workspaceEditJSONPreview
        )
        workspaceEditJSONApplySummary = try container.decodeIfPresent(
            AttoVisualWorkspaceEditJSONApplySummary.self,
            forKey: .workspaceEditJSONApplySummary
        )
        workspaceEditPreview = try container.decodeIfPresent(
            AttoVisualWorkspaceEditPreview.self,
            forKey: .workspaceEditPreview
        )
        persistentPanel = try container.decodeIfPresent(AttoVisualPersistentPanel.self, forKey: .persistentPanel)
        captureTarget = try container.decodeIfPresent(AttoVisualCaptureTarget.self, forKey: .captureTarget) ?? .mainWindow
        perChannelTolerance = try container.decode(UInt8.self, forKey: .perChannelTolerance)
        maxDifferentPixelRatio = try container.decode(Double.self, forKey: .maxDifferentPixelRatio)
    }

    func applyConfigurationOverrides(to snapshot: inout AttoConfigurationSnapshot) {
        if let fontFamilies {
            snapshot.editor.fontFamilies = fontFamilies
        }
        if let fontSizePoints {
            snapshot.editor.fontSizePoints = fontSizePoints
        }
    }

    func makeTheme() throws -> EditorCoreSkiaTheme {
        switch themeName {
        case "defaultLight":
            return EditorCoreSkiaTheme.defaultLight()
        case "demoRustLspDark":
            return EditorCoreSkiaTheme.demoRustLspDark()
        default:
            throw AttoVisualBaselineError.invalidManifest("unsupported visual baseline theme: \(themeName)")
        }
    }
}

private struct AttoVisualCaptureTarget: Decodable, Equatable {
    enum Kind: String, Decodable {
        case mainWindow
        case childWindow
        case hoverPopover
        case signatureHelpPopover
        case workspaceEditPopover

        var requiresIdentifier: Bool {
            self == .childWindow
        }

        var requiresExplicitSize: Bool {
            switch self {
            case .mainWindow, .childWindow:
                return false
            case .hoverPopover, .signatureHelpPopover, .workspaceEditPopover:
                return true
            }
        }
    }

    static let mainWindow = AttoVisualCaptureTarget(
        kind: .mainWindow,
        identifier: nil,
        width: nil,
        height: nil
    )

    let kind: Kind
    let identifier: String?
    let width: Int?
    let height: Int?

    var hasExplicitSize: Bool {
        width != nil && height != nil
    }

    func expectedWidth(defaultWindow: AttoVisualBaselineWindow) -> Int {
        width ?? defaultWindow.width
    }

    func expectedHeight(defaultWindow: AttoVisualBaselineWindow) -> Int {
        height ?? defaultWindow.height
    }
}

private struct AttoVisualSelectionRange: Decodable, Equatable {
    let start: UInt32
    let end: UInt32

    var range: EcuSelectionRange {
        EcuSelectionRange(start: start, end: end)
    }
}

private struct AttoVisualFoldRange: Decodable, Equatable {
    let startLine: UInt32
    let endLine: UInt32
}

private struct AttoVisualDiagnosticMarker: Decodable, Equatable {
    let logicalLine: UInt32
    let charOffset: UInt32
    let severity: EcuDiagnosticSeverity?
    let sourceName: String?

    var projection: AttoDiagnosticMarkerProjection {
        AttoDiagnosticMarkerProjection(
            logicalLine: logicalLine,
            charOffset: charOffset,
            severity: severity,
            source: AttoDiagnosticMarkerProjection.Source(rawValue: sourceName ?? "") ?? .active
        )
    }

    enum CodingKeys: String, CodingKey {
        case logicalLine
        case charOffset
        case severity
        case sourceName = "source"
    }
}

private struct AttoVisualActiveDiagnostics: Decodable, Equatable {
    let version: Int
    let items: [AttoVisualDiagnostic]

    enum CodingKeys: String, CodingKey {
        case version
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try container.decode([AttoVisualDiagnostic].self, forKey: .items)
    }

    func resultJSON(documentURI: String) throws -> String {
        try encodeVisualJSON(
            AttoVisualPublishDiagnosticsPayload(
                uri: documentURI,
                diagnostics: items.map(\.payload),
                version: version
            ),
            context: "active diagnostics"
        )
    }
}

private struct AttoVisualWorkspaceDiagnostics: Decodable, Equatable {
    let documents: [AttoVisualWorkspaceDiagnosticDocument]

    func resultJSON(
        activeDocumentURI: String,
        documentURLs: [String: URL],
        tempDir: URL
    ) throws -> String {
        let items = try documents.map { document in
            try AttoVisualWorkspaceDiagnosticsDocumentPayload(
                uri: document.documentURI(
                    activeDocumentURI: activeDocumentURI,
                    documentURLs: documentURLs,
                    tempDir: tempDir
                ),
                kind: document.kind,
                resultId: document.resultId,
                items: document.items.map(\.payload)
            )
        }
        return try encodeVisualJSON(
            AttoVisualWorkspaceDiagnosticsPayload(items: items),
            context: "workspace diagnostics"
        )
    }
}

private struct AttoVisualWorkspaceDiagnosticDocument: Decodable, Equatable {
    let fixture: String?
    let fileName: String?
    let kind: String
    let resultId: String?
    let items: [AttoVisualDiagnostic]

    enum CodingKeys: String, CodingKey {
        case fixture
        case fileName
        case kind
        case resultId
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fixture = try container.decodeIfPresent(String.self, forKey: .fixture)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "full"
        resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
        items = try container.decode([AttoVisualDiagnostic].self, forKey: .items)
    }

    func documentURI(
        activeDocumentURI: String,
        documentURLs: [String: URL],
        tempDir: URL
    ) throws -> String {
        if let fixture {
            guard let url = documentURLs[fixture] else {
                throw AttoVisualBaselineError.invalidManifest("workspace diagnostics fixture not loaded: \(fixture)")
            }
            return url.standardizedFileURL.absoluteString
        }
        if let fileName {
            return tempDir.appendingPathComponent(fileName).standardizedFileURL.absoluteString
        }
        return activeDocumentURI
    }
}

private struct AttoVisualDiagnostic: Decodable, Equatable {
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32
    let severity: Int?
    let source: String?
    let message: String
    let code: String?

    enum CodingKeys: String, CodingKey {
        case line
        case utf16Character
        case length
        case severity
        case source
        case message
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decode(UInt32.self, forKey: .utf16Character)
        length = try container.decodeIfPresent(UInt32.self, forKey: .length) ?? 1
        severity = try container.decodeIfPresent(Int.self, forKey: .severity)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        message = try container.decode(String.self, forKey: .message)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    var payload: AttoVisualDiagnosticPayload {
        AttoVisualDiagnosticPayload(
            range: AttoVisualLspRange(
                start: AttoVisualLspPosition(line: line, character: utf16Character),
                end: AttoVisualLspPosition(line: line, character: utf16Character + length)
            ),
            severity: severity,
            source: source,
            message: message,
            code: code
        )
    }
}

private struct AttoVisualPublishDiagnosticsPayload: Encodable {
    let uri: String
    let diagnostics: [AttoVisualDiagnosticPayload]
    let version: Int
}

private struct AttoVisualWorkspaceDiagnosticsPayload: Encodable {
    let items: [AttoVisualWorkspaceDiagnosticsDocumentPayload]
}

private struct AttoVisualWorkspaceDiagnosticsDocumentPayload: Encodable {
    let uri: String
    let kind: String
    let resultId: String?
    let items: [AttoVisualDiagnosticPayload]
}

private struct AttoVisualDiagnosticPayload: Encodable {
    let range: AttoVisualLspRange
    let severity: Int?
    let source: String?
    let message: String
    let code: String?
}

private enum AttoVisualPersistentPanel: String, Decodable, Equatable {
    case problemsPanel
    case workspaceProblemsPanel
    case lspWorkbenchPanel
    case hierarchyPanel
    case codeLensPanel
    case inlayHintPanel
    case documentLinkPanel
    case documentColorPanel
}

private struct AttoVisualLspSymbolResults: Decodable, Equatable {
    let title: String
    let placeholder: String
    let presentation: AttoVisualPanelPresentation
    let symbols: [AttoVisualLspSymbol]

    enum CodingKeys: String, CodingKey {
        case title
        case placeholder
        case presentation
        case symbols
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Document Symbols"
        placeholder = try container.decode(String.self, forKey: .placeholder)
        presentation = try container.decodeIfPresent(AttoVisualPanelPresentation.self, forKey: .presentation) ?? .quickPanel
        symbols = try container.decode([AttoVisualLspSymbol].self, forKey: .symbols)
    }

    func symbols(documentURI: String) -> [AttoLspSymbolParser.Symbol] {
        symbols.map { $0.symbol(documentURI: documentURI) }
    }
}

private enum AttoVisualPanelPresentation: String, Codable, Equatable {
    case quickPanel
    case persistentPanel
}

private struct AttoVisualLspSymbol: Decodable, Equatable {
    let name: String
    let detail: String?
    let kindLabel: String?
    let containerName: String?
    let line: Int
    let utf16Character: Int
    let depth: Int

    enum CodingKeys: String, CodingKey {
        case name
        case detail
        case kindLabel
        case containerName
        case line
        case utf16Character
        case depth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        kindLabel = try container.decodeIfPresent(String.self, forKey: .kindLabel)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        utf16Character = try container.decodeIfPresent(Int.self, forKey: .utf16Character) ?? 0
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
    }

    func symbol(documentURI: String) -> AttoLspSymbolParser.Symbol {
        AttoLspSymbolParser.Symbol(
            name: name,
            detail: detail,
            kindLabel: kindLabel,
            containerName: containerName,
            target: AttoLspDefinitionParser.Target(
                uri: documentURI,
                line: line,
                utf16Character: utf16Character
            ),
            depth: depth
        )
    }
}

private struct AttoVisualLspLocationResults: Decodable, Equatable {
    let kind: AttoVisualLspLocationKind
    let presentation: AttoVisualPanelPresentation
    let targets: [AttoVisualLspLocationTarget]

    enum CodingKeys: String, CodingKey {
        case kind
        case presentation
        case targets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AttoVisualLspLocationKind.self, forKey: .kind)
        presentation = try container.decodeIfPresent(AttoVisualPanelPresentation.self, forKey: .presentation) ?? .quickPanel
        targets = try container.decode([AttoVisualLspLocationTarget].self, forKey: .targets)
    }

    var requestKind: AttoEditorAreaViewController.LspLocationRequestKind {
        switch kind {
        case .definition:
            return .definition
        case .declaration:
            return .declaration
        case .typeDefinition:
            return .typeDefinition
        case .implementation:
            return .implementation
        case .references:
            return .references
        }
    }

    func resultJSON(documentURI: String) throws -> String {
        let result = targets.map { $0.location(documentURI: documentURI) }
        let data = try JSONEncoder().encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AttoVisualBaselineError.invalidManifest("failed to encode location results JSON")
        }
        return json
    }
}

private enum AttoVisualLspLocationKind: String, Codable, Equatable {
    case definition
    case declaration
    case typeDefinition
    case implementation
    case references
}

private struct AttoVisualLspLocationTarget: Codable, Equatable {
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32

    enum CodingKeys: String, CodingKey {
        case line
        case utf16Character
        case length
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decode(UInt32.self, forKey: .utf16Character)
        length = try container.decodeIfPresent(UInt32.self, forKey: .length) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(line, forKey: .line)
        try container.encode(utf16Character, forKey: .utf16Character)
        try container.encode(length, forKey: .length)
    }

    func location(documentURI: String) -> AttoVisualLspLocation {
        AttoVisualLspLocation(
            uri: documentURI,
            range: AttoVisualLspRange(
                start: AttoVisualLspPosition(line: line, character: utf16Character),
                end: AttoVisualLspPosition(line: line, character: utf16Character + length)
            )
        )
    }
}

private struct AttoVisualLspLocation: Codable, Equatable {
    let uri: String
    let range: AttoVisualLspRange
}

private struct AttoVisualLspRange: Codable, Equatable {
    let start: AttoVisualLspPosition
    let end: AttoVisualLspPosition
}

private struct AttoVisualLspPosition: Codable, Equatable {
    let line: UInt32
    let character: UInt32
}

private struct AttoVisualHierarchyResults: Decodable, Equatable {
    let kind: AttoVisualHierarchyKind
    let entries: [AttoVisualHierarchyEntry]

    enum CodingKeys: String, CodingKey {
        case kind
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(AttoVisualHierarchyKind.self, forKey: .kind) ?? .callIncoming
        entries = try container.decode([AttoVisualHierarchyEntry].self, forKey: .entries)
    }

    func resultJSON(documentURI: String) throws -> String {
        switch kind {
        case .callIncoming:
            return try encodeVisualJSON(
                entries.map { $0.incomingCallPayload(documentURI: documentURI) },
                context: "incoming call hierarchy"
            )
        case .callOutgoing:
            return try encodeVisualJSON(
                entries.map { $0.outgoingCallPayload(documentURI: documentURI) },
                context: "outgoing call hierarchy"
            )
        case .typeSupertypes, .typeSubtypes:
            return try encodeVisualJSON(
                entries.map { $0.itemPayload(documentURI: documentURI) },
                context: "type hierarchy"
            )
        }
    }
}

private enum AttoVisualHierarchyKind: String, Decodable, Equatable {
    case callIncoming
    case callOutgoing
    case typeSupertypes
    case typeSubtypes
}

private struct AttoVisualHierarchyEntry: Decodable, Equatable {
    let name: String
    let detail: String?
    let lspKind: Int?
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32
    let relatedRangeCount: Int

    enum CodingKeys: String, CodingKey {
        case name
        case detail
        case lspKind
        case line
        case utf16Character
        case length
        case relatedRangeCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        lspKind = try container.decodeIfPresent(Int.self, forKey: .lspKind)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decode(UInt32.self, forKey: .utf16Character)
        length = try container.decodeIfPresent(UInt32.self, forKey: .length) ?? 1
        relatedRangeCount = try container.decodeIfPresent(Int.self, forKey: .relatedRangeCount) ?? 1
    }

    func incomingCallPayload(documentURI: String) -> AttoVisualIncomingCallHierarchyPayload {
        AttoVisualIncomingCallHierarchyPayload(
            from: itemPayload(documentURI: documentURI),
            fromRanges: relatedRanges
        )
    }

    func outgoingCallPayload(documentURI: String) -> AttoVisualOutgoingCallHierarchyPayload {
        AttoVisualOutgoingCallHierarchyPayload(
            to: itemPayload(documentURI: documentURI),
            fromRanges: relatedRanges
        )
    }

    func itemPayload(documentURI: String) -> AttoVisualHierarchyItemPayload {
        AttoVisualHierarchyItemPayload(
            name: name,
            kind: lspKind,
            detail: detail,
            uri: documentURI,
            selectionRange: primaryRange
        )
    }

    private var primaryRange: AttoVisualLspRange {
        AttoVisualLspRange(
            start: AttoVisualLspPosition(line: line, character: utf16Character),
            end: AttoVisualLspPosition(line: line, character: utf16Character + length)
        )
    }

    private var relatedRanges: [AttoVisualLspRange] {
        let count = max(relatedRangeCount, 1)
        return (0..<count).map { _ in primaryRange }
    }
}

private struct AttoVisualIncomingCallHierarchyPayload: Encodable {
    let from: AttoVisualHierarchyItemPayload
    let fromRanges: [AttoVisualLspRange]
}

private struct AttoVisualOutgoingCallHierarchyPayload: Encodable {
    let to: AttoVisualHierarchyItemPayload
    let fromRanges: [AttoVisualLspRange]
}

private struct AttoVisualHierarchyItemPayload: Encodable {
    let name: String
    let kind: Int?
    let detail: String?
    let uri: String
    let selectionRange: AttoVisualLspRange
}

private struct AttoVisualCodeLensResults: Decodable, Equatable {
    let items: [AttoVisualCodeLens]

    func resultJSON() throws -> String {
        try encodeVisualJSON(items.map(\.payload), context: "code lens results")
    }
}

private struct AttoVisualCodeLens: Decodable, Equatable {
    let title: String
    let command: String
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32

    enum CodingKeys: String, CodingKey {
        case title
        case command
        case line
        case utf16Character
        case length
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        command = try container.decode(String.self, forKey: .command)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decodeIfPresent(UInt32.self, forKey: .utf16Character) ?? 0
        length = try container.decodeIfPresent(UInt32.self, forKey: .length) ?? 0
    }

    var payload: AttoVisualCodeLensPayload {
        AttoVisualCodeLensPayload(
            range: visualRange(line: line, utf16Character: utf16Character, length: length),
            command: AttoVisualCommandPayload(title: title, command: command)
        )
    }
}

private struct AttoVisualCodeLensPayload: Encodable {
    let range: AttoVisualLspRange
    let command: AttoVisualCommandPayload
}

private struct AttoVisualCommandPayload: Encodable {
    let title: String
    let command: String
}

private struct AttoVisualInlayHints: Decodable, Equatable {
    let items: [AttoVisualInlayHint]

    func resultJSON() throws -> String {
        try encodeVisualJSON(items.map(\.payload), context: "inlay hint results")
    }
}

private struct AttoVisualInlayHint: Decodable, Equatable {
    let label: String
    let kind: Int?
    let line: UInt32
    let utf16Character: UInt32

    var payload: AttoVisualInlayHintPayload {
        AttoVisualInlayHintPayload(
            position: AttoVisualLspPosition(line: line, character: utf16Character),
            label: label,
            kind: kind
        )
    }
}

private struct AttoVisualInlayHintPayload: Encodable {
    let position: AttoVisualLspPosition
    let label: String
    let kind: Int?
}

private struct AttoVisualDocumentLinks: Decodable, Equatable {
    let items: [AttoVisualDocumentLink]

    func resultJSON() throws -> String {
        try encodeVisualJSON(items.map(\.payload), context: "document link results")
    }
}

private struct AttoVisualDocumentLink: Decodable, Equatable {
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32
    let target: String?
    let tooltip: String?
    let dataID: Int?

    enum CodingKeys: String, CodingKey {
        case line
        case utf16Character
        case length
        case target
        case tooltip
        case dataID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decode(UInt32.self, forKey: .utf16Character)
        length = try container.decode(UInt32.self, forKey: .length)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        dataID = try container.decodeIfPresent(Int.self, forKey: .dataID)
    }

    var payload: AttoVisualDocumentLinkPayload {
        AttoVisualDocumentLinkPayload(
            range: visualRange(line: line, utf16Character: utf16Character, length: length),
            target: target,
            tooltip: tooltip,
            data: dataID.map { AttoVisualDocumentLinkDataPayload(id: $0) }
        )
    }
}

private struct AttoVisualDocumentLinkPayload: Encodable {
    let range: AttoVisualLspRange
    let target: String?
    let tooltip: String?
    let data: AttoVisualDocumentLinkDataPayload?
}

private struct AttoVisualDocumentLinkDataPayload: Encodable {
    let id: Int
}

private struct AttoVisualDocumentColors: Decodable, Equatable {
    let items: [AttoVisualDocumentColor]

    func resultJSON() throws -> String {
        try encodeVisualJSON(items.map(\.payload), context: "document color results")
    }
}

private struct AttoVisualDocumentColor: Decodable, Equatable {
    let line: UInt32
    let utf16Character: UInt32
    let length: UInt32
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    enum CodingKeys: String, CodingKey {
        case line
        case utf16Character
        case length
        case red
        case green
        case blue
        case alpha
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(UInt32.self, forKey: .line)
        utf16Character = try container.decode(UInt32.self, forKey: .utf16Character)
        length = try container.decode(UInt32.self, forKey: .length)
        red = try container.decode(Double.self, forKey: .red)
        green = try container.decode(Double.self, forKey: .green)
        blue = try container.decode(Double.self, forKey: .blue)
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
    }

    var payload: AttoVisualDocumentColorPayload {
        AttoVisualDocumentColorPayload(
            range: visualRange(line: line, utf16Character: utf16Character, length: length),
            color: AttoVisualColorPayload(red: red, green: green, blue: blue, alpha: alpha)
        )
    }
}

private struct AttoVisualDocumentColorPayload: Encodable {
    let range: AttoVisualLspRange
    let color: AttoVisualColorPayload
}

private struct AttoVisualColorPayload: Encodable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

private struct AttoVisualCodeActionResults: Codable, Equatable {
    let onlyKinds: [String]
    let items: [AttoVisualCodeActionItem]

    enum CodingKeys: String, CodingKey {
        case onlyKinds
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onlyKinds = try container.decodeIfPresent([String].self, forKey: .onlyKinds) ?? []
        items = try container.decode([AttoVisualCodeActionItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(onlyKinds, forKey: .onlyKinds)
        try container.encode(items, forKey: .items)
    }

    func resultJSON() throws -> String {
        let data = try JSONEncoder().encode(items)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AttoVisualBaselineError.invalidManifest("failed to encode code action results JSON")
        }
        return json
    }
}

private struct AttoVisualCodeActionItem: Codable, Equatable {
    let title: String
    let kind: String?
    let isPreferred: Bool?
}

private struct AttoVisualCompletionPopup: Codable, Equatable {
    let isIncomplete: Bool
    let items: [AttoVisualCompletionItem]

    enum CodingKeys: String, CodingKey {
        case isIncomplete
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isIncomplete = try container.decodeIfPresent(Bool.self, forKey: .isIncomplete) ?? false
        items = try container.decode([AttoVisualCompletionItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isIncomplete, forKey: .isIncomplete)
        try container.encode(items, forKey: .items)
    }

    func resultJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AttoVisualBaselineError.invalidManifest("failed to encode completion popup JSON")
        }
        return json
    }
}

private struct AttoVisualCompletionItem: Codable, Equatable {
    let label: String
    let kind: Int?
    let detail: String?
    let documentation: String?
}

private struct AttoVisualHoverPopover: Decodable, Equatable {
    let text: String
    let viewX: Double
    let viewY: Double
    let logicalLine: UInt32
    let logicalColumn: UInt32
    let charOffset: UInt32

    enum CodingKeys: String, CodingKey {
        case text
        case viewX
        case viewY
        case logicalLine
        case logicalColumn
        case charOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        viewX = try container.decodeIfPresent(Double.self, forKey: .viewX) ?? 120
        viewY = try container.decodeIfPresent(Double.self, forKey: .viewY) ?? 120
        logicalLine = try container.decodeIfPresent(UInt32.self, forKey: .logicalLine) ?? 0
        logicalColumn = try container.decodeIfPresent(UInt32.self, forKey: .logicalColumn) ?? 0
        charOffset = try container.decodeIfPresent(UInt32.self, forKey: .charOffset) ?? 0
    }

    var info: EditorCoreSkiaHoverInfo {
        let point = CGPoint(x: viewX, y: viewY)
        return EditorCoreSkiaHoverInfo(
            charOffset: charOffset,
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            windowPoint: point,
            viewPoint: point,
            viewBackingXPx: Float(viewX),
            viewBackingYPx: Float(viewY),
            documentLinkJSON: nil
        )
    }
}

private struct AttoVisualSignatureHelpPopover: Decodable, Equatable {
    let text: String
    let activeParameterRanges: [AttoVisualTextRange]

    enum CodingKeys: String, CodingKey {
        case text
        case activeParameterRanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        activeParameterRanges = try container.decodeIfPresent(
            [AttoVisualTextRange].self,
            forKey: .activeParameterRanges
        ) ?? []
    }

    var display: AttoLspSignatureHelpFormatter.Display {
        AttoLspSignatureHelpFormatter.Display(
            text: text,
            activeParameterRanges: activeParameterRanges.map(\.nsRange)
        )
    }
}

private struct AttoVisualFailurePopover: Decodable, Equatable {
    let text: String
}

private struct AttoVisualWorkspaceEditJSONPreview: Decodable, Equatable {
    let supportFiles: [AttoVisualWorkspaceEditSupportFile]
    let documents: [AttoVisualWorkspaceEditJSONDocument]

    enum CodingKeys: String, CodingKey {
        case supportFiles
        case documents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportFiles = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditSupportFile].self,
            forKey: .supportFiles
        ) ?? []
        documents = try container.decode([AttoVisualWorkspaceEditJSONDocument].self, forKey: .documents)
    }

    func materializeSupportFiles(in tempDir: URL) throws {
        for file in supportFiles {
            try file.write(in: tempDir)
        }
    }

    func resultJSON(tempDir: URL) throws -> String {
        var changes: [String: [AttoVisualWorkspaceEditTextEditPayload]] = [:]
        for document in documents {
            let uri = AttoVisualWorkspaceEditPreview.fileURI(document.fileName, tempDir: tempDir)
            changes[uri, default: []].append(contentsOf: document.edits.map(\.payload))
        }
        return try encodeVisualJSON(
            AttoVisualWorkspaceEditJSONPayload(changes: changes),
            context: "WorkspaceEdit preview"
        )
    }
}

private struct AttoVisualWorkspaceEditJSONApplySummary: Decodable, Equatable {
    let supportFiles: [AttoVisualWorkspaceEditSupportFile]
    let applyMode: String?
    let makeActiveDocumentDirty: Bool
    let expectedApplied: Bool
    let undoAfterApply: Bool
    let expectedUndo: Bool
    let expectedActiveTextAfterApply: String?
    let expectedActiveTextAfterUndo: String?
    let expectedFileContentsAfterApply: [AttoVisualWorkspaceEditExpectedFileContent]
    let expectedFileContentsAfterUndo: [AttoVisualWorkspaceEditExpectedFileContent]
    let documents: [AttoVisualWorkspaceEditJSONDocument]
    let resourceOperations: [AttoVisualWorkspaceEditJSONResourceOperation]
    let orderedChanges: [AttoVisualWorkspaceEditJSONChange]?

    enum CodingKeys: String, CodingKey {
        case supportFiles
        case applyMode
        case makeActiveDocumentDirty
        case expectedApplied
        case undoAfterApply
        case expectedUndo
        case expectedActiveTextAfterApply
        case expectedActiveTextAfterUndo
        case expectedFileContentsAfterApply
        case expectedFileContentsAfterUndo
        case documents
        case resourceOperations
        case orderedChanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportFiles = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditSupportFile].self,
            forKey: .supportFiles
        ) ?? []
        applyMode = try container.decodeIfPresent(String.self, forKey: .applyMode)
        makeActiveDocumentDirty = try container.decodeIfPresent(
            Bool.self,
            forKey: .makeActiveDocumentDirty
        ) ?? false
        expectedApplied = try container.decodeIfPresent(Bool.self, forKey: .expectedApplied) ?? false
        undoAfterApply = try container.decodeIfPresent(Bool.self, forKey: .undoAfterApply) ?? false
        expectedUndo = try container.decodeIfPresent(Bool.self, forKey: .expectedUndo) ?? undoAfterApply
        expectedActiveTextAfterApply = try container.decodeIfPresent(
            String.self,
            forKey: .expectedActiveTextAfterApply
        )
        expectedActiveTextAfterUndo = try container.decodeIfPresent(
            String.self,
            forKey: .expectedActiveTextAfterUndo
        )
        expectedFileContentsAfterApply = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditExpectedFileContent].self,
            forKey: .expectedFileContentsAfterApply
        ) ?? []
        expectedFileContentsAfterUndo = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditExpectedFileContent].self,
            forKey: .expectedFileContentsAfterUndo
        ) ?? []
        documents = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditJSONDocument].self,
            forKey: .documents
        ) ?? []
        resourceOperations = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditJSONResourceOperation].self,
            forKey: .resourceOperations
        ) ?? []
        orderedChanges = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditJSONChange].self,
            forKey: .orderedChanges
        )
    }

    func materializeSupportFiles(in tempDir: URL) throws {
        for file in supportFiles {
            try file.write(in: tempDir)
        }
    }

    func resultJSON(tempDir: URL) throws -> String {
        let documentChanges = orderedChanges?.map { $0.payload(tempDir: tempDir) }
            ?? Self.legacyDocumentChanges(
                documents: documents,
                resourceOperations: resourceOperations,
                tempDir: tempDir
            )
        return try encodeVisualJSON(
            AttoVisualWorkspaceEditDocumentChangesPayload(
                applyMode: applyMode,
                documentChanges: documentChanges
            ),
            context: "WorkspaceEdit apply summary"
        )
    }

    private static func legacyDocumentChanges(
        documents: [AttoVisualWorkspaceEditJSONDocument],
        resourceOperations: [AttoVisualWorkspaceEditJSONResourceOperation],
        tempDir: URL
    ) -> [AttoVisualWorkspaceEditDocumentChangePayload] {
        var documentChanges: [AttoVisualWorkspaceEditDocumentChangePayload] = documents.map { document in
            document.payload(tempDir: tempDir)
        }
        documentChanges.append(contentsOf: resourceOperations.map { operation in
            .resourceOperation(operation.payload(tempDir: tempDir))
        })
        return documentChanges
    }

    @MainActor
    func assertApplyState(
        in vc: AttoEditorAreaViewController,
        tempDir: URL,
        caseID: String
    ) throws {
        try assertActiveText(expectedActiveTextAfterApply, in: vc, caseID: caseID)
        try assertFileContents(expectedFileContentsAfterApply, tempDir: tempDir, caseID: caseID)
    }

    @MainActor
    func assertUndoState(
        in vc: AttoEditorAreaViewController,
        tempDir: URL,
        caseID: String
    ) throws {
        try assertActiveText(expectedActiveTextAfterUndo, in: vc, caseID: caseID)
        try assertFileContents(expectedFileContentsAfterUndo, tempDir: tempDir, caseID: caseID)
    }

    @MainActor
    private func assertActiveText(
        _ expectedText: String?,
        in vc: AttoEditorAreaViewController,
        caseID: String
    ) throws {
        guard let expectedText else { return }
        guard let tab = vc.activeTab else {
            XCTFail(caseID)
            return
        }
        let actualText = try tab.editCore.editor.text()
        XCTAssertEqual(actualText, expectedText, caseID)
    }

    private func assertFileContents(
        _ expectedContents: [AttoVisualWorkspaceEditExpectedFileContent],
        tempDir: URL,
        caseID: String
    ) throws {
        for expected in expectedContents {
            let url = tempDir.appendingPathComponent(expected.fileName)
            let actualText = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(actualText, expected.text, caseID)
        }
    }
}

private struct AttoVisualWorkspaceEditSupportFile: Decodable, Equatable {
    let fileName: String
    let text: String?
    let hexBytes: String?

    func write(in tempDir: URL) throws {
        let url = tempDir.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let text {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        if let hexBytes {
            try Self.data(hexBytes: hexBytes).write(to: url, options: .atomic)
            return
        }
        throw AttoVisualBaselineError.invalidManifest("support file \(fileName) needs text or hexBytes")
    }

    private static func data(hexBytes: String) throws -> Data {
        let compact = hexBytes.filter { $0.isWhitespace == false }
        guard compact.count.isMultiple(of: 2) else {
            throw AttoVisualBaselineError.invalidManifest("hexBytes must contain whole bytes")
        }
        var data = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            let byteText = String(compact[index..<next])
            guard let byte = UInt8(byteText, radix: 16) else {
                throw AttoVisualBaselineError.invalidManifest("invalid hex byte: \(byteText)")
            }
            data.append(byte)
            index = next
        }
        return data
    }
}

private struct AttoVisualWorkspaceEditExpectedFileContent: Decodable, Equatable {
    let fileName: String
    let text: String
}

private struct AttoVisualWorkspaceEditJSONDocument: Decodable, Equatable {
    let fileName: String
    let version: Int?
    let edits: [AttoVisualWorkspaceEditTextEdit]

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditDocumentChangePayload {
        .textDocumentEdit(AttoVisualWorkspaceEditTextDocumentChangePayload(
            textDocument: AttoVisualWorkspaceEditTextDocumentPayload(
                uri: AttoVisualWorkspaceEditPreview.fileURI(fileName, tempDir: tempDir),
                version: version
            ),
            edits: edits.map(\.payload)
        ))
    }
}

private struct AttoVisualWorkspaceEditTextEdit: Decodable, Equatable {
    let startLine: UInt32
    let startUTF16Character: UInt32
    let endLine: UInt32
    let endUTF16Character: UInt32
    let newText: String

    enum CodingKeys: String, CodingKey {
        case startLine
        case startUTF16Character
        case endLine
        case endUTF16Character
        case newText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startLine = try container.decode(UInt32.self, forKey: .startLine)
        startUTF16Character = try container.decode(UInt32.self, forKey: .startUTF16Character)
        endLine = try container.decodeIfPresent(UInt32.self, forKey: .endLine) ?? startLine
        endUTF16Character = try container.decode(UInt32.self, forKey: .endUTF16Character)
        newText = try container.decode(String.self, forKey: .newText)
    }

    var payload: AttoVisualWorkspaceEditTextEditPayload {
        AttoVisualWorkspaceEditTextEditPayload(
            range: AttoVisualLspRange(
                start: AttoVisualLspPosition(line: startLine, character: startUTF16Character),
                end: AttoVisualLspPosition(line: endLine, character: endUTF16Character)
            ),
            newText: newText
        )
    }
}

private struct AttoVisualWorkspaceEditJSONPayload: Encodable {
    let changes: [String: [AttoVisualWorkspaceEditTextEditPayload]]
}

private struct AttoVisualWorkspaceEditDocumentChangesPayload: Encodable {
    let applyMode: String?
    let documentChanges: [AttoVisualWorkspaceEditDocumentChangePayload]
}

private enum AttoVisualWorkspaceEditDocumentChangePayload: Encodable {
    case textDocumentEdit(AttoVisualWorkspaceEditTextDocumentChangePayload)
    case resourceOperation(AttoVisualWorkspaceEditResourceOperationPayload)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .textDocumentEdit(let payload):
            try payload.encode(to: encoder)
        case .resourceOperation(let payload):
            try payload.encode(to: encoder)
        }
    }
}

private struct AttoVisualWorkspaceEditTextDocumentChangePayload: Encodable {
    let textDocument: AttoVisualWorkspaceEditTextDocumentPayload
    let edits: [AttoVisualWorkspaceEditTextEditPayload]
}

private struct AttoVisualWorkspaceEditTextDocumentPayload: Encodable {
    let uri: String
    let version: Int?
}

private struct AttoVisualWorkspaceEditTextEditPayload: Encodable {
    let range: AttoVisualLspRange
    let newText: String
}

private struct AttoVisualWorkspaceEditJSONResourceOperation: Decodable, Equatable {
    let kind: String
    let fileName: String?
    let oldFileName: String?
    let newFileName: String?
    let options: AttoVisualWorkspaceEditResourceOperationOptions?

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditResourceOperationPayload {
        AttoVisualWorkspaceEditResourceOperationPayload(
            kind: kind,
            uri: fileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            oldURI: oldFileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            newURI: newFileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            options: options
        )
    }
}

private enum AttoVisualWorkspaceEditJSONChange: Decodable, Equatable {
    case document(AttoVisualWorkspaceEditJSONDocument)
    case resourceOperation(AttoVisualWorkspaceEditJSONResourceOperation)

    private enum CodingKeys: String, CodingKey {
        case edits
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.edits) {
            self = .document(try AttoVisualWorkspaceEditJSONDocument(from: decoder))
            return
        }
        if container.contains(.kind) {
            self = .resourceOperation(try AttoVisualWorkspaceEditJSONResourceOperation(from: decoder))
            return
        }
        throw AttoVisualBaselineError.invalidManifest(
            "ordered workspace edit change must contain either edits or kind"
        )
    }

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditDocumentChangePayload {
        switch self {
        case .document(let document):
            return document.payload(tempDir: tempDir)
        case .resourceOperation(let operation):
            return .resourceOperation(operation.payload(tempDir: tempDir))
        }
    }
}

private struct AttoVisualWorkspaceEditResourceOperationOptions: Codable, Equatable {
    let overwrite: Bool?
    let ignoreIfExists: Bool?
    let recursive: Bool?
    let ignoreIfNotExists: Bool?
}

private struct AttoVisualWorkspaceEditResourceOperationPayload: Encodable {
    let kind: String
    let uri: String?
    let oldURI: String?
    let newURI: String?
    let options: AttoVisualWorkspaceEditResourceOperationOptions?

    private enum CodingKeys: String, CodingKey {
        case kind
        case uri
        case oldURI = "oldUri"
        case newURI = "newUri"
        case options
    }
}

private struct AttoVisualWorkspaceEditPreview: Decodable, Equatable {
    let mode: String
    let applyMode: String
    let applied: Bool
    let appliedFiles: [String]
    let appliedEditCount: Int
    let appliedResourceOperationCount: Int
    let documents: [AttoVisualWorkspaceEditPreviewDocument]
    let resourceOperations: [AttoVisualWorkspaceEditPreviewResourceOperation]
    let dirtyFiles: [String]
    let conflicts: [AttoVisualWorkspaceEditPreviewConflict]
    let skippedFiles: [String]
    let skippedDetails: [AttoVisualWorkspaceEditPreviewSkippedDetail]
    let unsupportedOperationFiles: [String]
    let sections: [AttoVisualWorkspaceEditPreviewSection]

    enum CodingKeys: String, CodingKey {
        case mode
        case applyMode
        case applied
        case appliedFiles
        case appliedEditCount
        case appliedResourceOperationCount
        case documents
        case resourceOperations
        case dirtyFiles
        case conflicts
        case skippedFiles
        case skippedDetails
        case unsupportedOperationFiles
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "preview"
        applyMode = try container.decodeIfPresent(String.self, forKey: .applyMode) ?? "partial"
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied) ?? false
        appliedFiles = try container.decodeIfPresent([String].self, forKey: .appliedFiles) ?? []
        appliedEditCount = try container.decodeIfPresent(Int.self, forKey: .appliedEditCount) ?? 0
        appliedResourceOperationCount = try container.decodeIfPresent(
            Int.self,
            forKey: .appliedResourceOperationCount
        ) ?? 0
        documents = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditPreviewDocument].self,
            forKey: .documents
        ) ?? []
        resourceOperations = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditPreviewResourceOperation].self,
            forKey: .resourceOperations
        ) ?? []
        dirtyFiles = try container.decodeIfPresent([String].self, forKey: .dirtyFiles) ?? []
        conflicts = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditPreviewConflict].self,
            forKey: .conflicts
        ) ?? []
        skippedFiles = try container.decodeIfPresent([String].self, forKey: .skippedFiles) ?? []
        skippedDetails = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditPreviewSkippedDetail].self,
            forKey: .skippedDetails
        ) ?? []
        unsupportedOperationFiles = try container.decodeIfPresent(
            [String].self,
            forKey: .unsupportedOperationFiles
        ) ?? []
        sections = try container.decodeIfPresent(
            [AttoVisualWorkspaceEditPreviewSection].self,
            forKey: .sections
        ) ?? []
    }

    func preview(tempDir: URL) throws -> AttoWorkspaceEditPreview {
        let payload = AttoVisualWorkspaceEditTransactionPayload(
            mode: mode,
            applyMode: applyMode,
            applied: applied,
            appliedURIs: appliedFiles.map { Self.fileURI($0, tempDir: tempDir) },
            appliedEditCount: appliedEditCount,
            appliedResourceOperationCount: appliedResourceOperationCount,
            resourceOperations: resourceOperations.map { $0.payload(tempDir: tempDir) },
            dirtyDocumentURIs: dirtyFiles.map { Self.fileURI($0, tempDir: tempDir) },
            conflicts: conflicts.map { $0.payload(tempDir: tempDir) },
            skippedURIs: skippedFiles.map { Self.fileURI($0, tempDir: tempDir) },
            skippedDetails: skippedDetails.map { $0.payload(tempDir: tempDir) },
            unsupportedOperationURIs: unsupportedOperationFiles.map { Self.fileURI($0, tempDir: tempDir) },
            documents: documents.map { $0.payload(tempDir: tempDir) }
        )
        let data = try JSONEncoder().encode(payload)
        let result = try JSONDecoder().decode(EcuWorkspaceEditTransactionResult.self, from: data)
        var preview = AttoWorkspaceEditPreview(result: result)
        preview.sections = sections.map { $0.previewSection(tempDir: tempDir) }
        return preview
    }

    fileprivate static func fileURI(_ fileName: String, tempDir: URL) -> String {
        tempDir.appendingPathComponent(fileName).standardizedFileURL.absoluteString
    }
}

private struct AttoVisualWorkspaceEditPreviewDocument: Decodable, Equatable {
    let fileName: String
    let editCount: Int
    let isOpen: Bool
    let isDirty: Bool
    let hasOverlappingEdits: Bool
    let versionMismatch: Bool

    enum CodingKeys: String, CodingKey {
        case fileName
        case editCount
        case isOpen
        case isDirty
        case hasOverlappingEdits
        case versionMismatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        editCount = try container.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
        isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        hasOverlappingEdits = try container.decodeIfPresent(Bool.self, forKey: .hasOverlappingEdits) ?? false
        versionMismatch = try container.decodeIfPresent(Bool.self, forKey: .versionMismatch) ?? false
    }

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditTransactionDocumentPayload {
        AttoVisualWorkspaceEditTransactionDocumentPayload(
            uri: AttoVisualWorkspaceEditPreview.fileURI(fileName, tempDir: tempDir),
            editCount: editCount,
            hasOverlappingEdits: hasOverlappingEdits,
            versionMismatch: versionMismatch,
            isOpen: isOpen,
            isDirty: isDirty
        )
    }
}

private struct AttoVisualWorkspaceEditPreviewResourceOperation: Decodable, Equatable {
    let kind: String
    let fileName: String?
    let oldFileName: String?
    let newFileName: String?
    let affectedFiles: [String]
    let supported: Bool
    let applied: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case fileName
        case oldFileName
        case newFileName
        case affectedFiles
        case supported
        case applied
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        oldFileName = try container.decodeIfPresent(String.self, forKey: .oldFileName)
        newFileName = try container.decodeIfPresent(String.self, forKey: .newFileName)
        affectedFiles = try container.decodeIfPresent([String].self, forKey: .affectedFiles) ?? []
        supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? true
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied) ?? false
    }

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditTransactionResourceOperationPayload {
        AttoVisualWorkspaceEditTransactionResourceOperationPayload(
            kind: kind,
            uri: fileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            oldURI: oldFileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            newURI: newFileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            affectedURIs: affectedFiles.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) },
            supported: supported,
            applied: applied
        )
    }
}

private struct AttoVisualWorkspaceEditPreviewConflict: Decodable, Equatable {
    let fileName: String
    let kind: String
    let reason: String
    let operation: String?
    let message: String

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditTransactionConflictPayload {
        AttoVisualWorkspaceEditTransactionConflictPayload(
            uri: AttoVisualWorkspaceEditPreview.fileURI(fileName, tempDir: tempDir),
            kind: kind,
            reason: reason,
            operation: operation,
            message: message
        )
    }
}

private struct AttoVisualWorkspaceEditPreviewSkippedDetail: Decodable, Equatable {
    let fileName: String
    let reason: String
    let operation: String?
    let message: String

    func payload(tempDir: URL) -> AttoVisualWorkspaceEditTransactionSkippedDetailPayload {
        AttoVisualWorkspaceEditTransactionSkippedDetailPayload(
            uri: AttoVisualWorkspaceEditPreview.fileURI(fileName, tempDir: tempDir),
            reason: reason,
            operation: operation,
            message: message
        )
    }
}

private struct AttoVisualWorkspaceEditPreviewSection: Decodable, Equatable {
    let fileName: String?
    let title: String
    let subtitle: String
    let detailText: String

    func previewSection(tempDir: URL) -> AttoWorkspaceEditPreview.Section {
        AttoWorkspaceEditPreview.Section(
            uri: fileName.map { AttoVisualWorkspaceEditPreview.fileURI($0, tempDir: tempDir) } ?? "",
            title: title,
            subtitle: subtitle,
            detailText: detailText
        )
    }
}

private struct AttoVisualWorkspaceEditTransactionPayload: Encodable {
    let mode: String
    let applyMode: String
    let applied: Bool
    let appliedURIs: [String]
    let appliedEditCount: Int
    let appliedResourceOperationCount: Int
    let resourceOperations: [AttoVisualWorkspaceEditTransactionResourceOperationPayload]
    let dirtyDocumentURIs: [String]
    let conflicts: [AttoVisualWorkspaceEditTransactionConflictPayload]
    let skippedURIs: [String]
    let skippedDetails: [AttoVisualWorkspaceEditTransactionSkippedDetailPayload]
    let unsupportedOperationURIs: [String]
    let documents: [AttoVisualWorkspaceEditTransactionDocumentPayload]

    private enum CodingKeys: String, CodingKey {
        case mode
        case applyMode = "apply_mode"
        case applied
        case appliedURIs = "applied_uris"
        case appliedEditCount = "applied_edit_count"
        case appliedResourceOperationCount = "applied_resource_operation_count"
        case resourceOperations = "resource_operations"
        case dirtyDocumentURIs = "dirty_document_uris"
        case conflicts
        case skippedURIs = "skipped_uris"
        case skippedDetails = "skipped_details"
        case unsupportedOperationURIs = "unsupported_operation_uris"
        case documents
    }
}

private struct AttoVisualWorkspaceEditTransactionDocumentPayload: Encodable {
    let uri: String
    let editCount: Int
    let hasOverlappingEdits: Bool
    let versionMismatch: Bool
    let isOpen: Bool
    let isDirty: Bool

    private enum CodingKeys: String, CodingKey {
        case uri
        case editCount = "edit_count"
        case hasOverlappingEdits = "has_overlapping_edits"
        case versionMismatch = "version_mismatch"
        case isOpen = "is_open"
        case isDirty = "is_dirty"
    }
}

private struct AttoVisualWorkspaceEditTransactionResourceOperationPayload: Encodable {
    let kind: String
    let uri: String?
    let oldURI: String?
    let newURI: String?
    let affectedURIs: [String]
    let supported: Bool
    let applied: Bool

    private enum CodingKeys: String, CodingKey {
        case kind
        case uri
        case oldURI = "old_uri"
        case newURI = "new_uri"
        case affectedURIs = "affected_uris"
        case supported
        case applied
    }
}

private struct AttoVisualWorkspaceEditTransactionConflictPayload: Encodable {
    let uri: String
    let kind: String
    let reason: String
    let operation: String?
    let message: String
}

private struct AttoVisualWorkspaceEditTransactionSkippedDetailPayload: Encodable {
    let uri: String
    let reason: String
    let operation: String?
    let message: String
}

private struct AttoVisualTextRange: Decodable, Equatable {
    let location: Int
    let length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

private func encodeVisualJSON<T: Encodable>(_ value: T, context: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let json = String(data: data, encoding: .utf8) else {
        throw AttoVisualBaselineError.invalidManifest("failed to encode \(context) JSON")
    }
    return json
}

private func visualRange(line: UInt32, utf16Character: UInt32, length: UInt32) -> AttoVisualLspRange {
    AttoVisualLspRange(
        start: AttoVisualLspPosition(line: line, character: utf16Character),
        end: AttoVisualLspPosition(line: line, character: utf16Character + length)
    )
}

private struct AttoVisualBaselineWindow: Decodable, Equatable {
    let width: Int
    let height: Int

    var nsSize: NSSize {
        NSSize(width: width, height: height)
    }
}

private enum AttoVisualBaselineError: Error, CustomStringConvertible {
    case invalidManifest(String)
    case missingResource(String)

    var description: String {
        switch self {
        case let .invalidManifest(message),
             let .missingResource(message):
            return message
        }
    }
}

private func resourceURL(path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    let fileName = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
    let directory = url.deletingLastPathComponent().relativePath
    let subdirectory = directory == "." ? nil : directory

    if let resource = Bundle.module.url(
        forResource: fileName,
        withExtension: ext,
        subdirectory: subdirectory
    ) {
        return resource
    }
    if let resource = Bundle.module.url(forResource: fileName, withExtension: ext) {
        return resource
    }

    throw AttoVisualBaselineError.missingResource("missing test resource: \(path)")
}
