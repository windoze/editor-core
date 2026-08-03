import Foundation

public struct EditorCoreUIFFIRuntimeFeature: Equatable, Sendable {
    public let feature: EditorCoreUIFFIFeatures
    public let name: String
    public let reason: String

    public init(feature: EditorCoreUIFFIFeatures, name: String, reason: String) {
        self.feature = feature
        self.name = name
        self.reason = reason
    }
}

public struct EditorCoreUIFFIRuntimeCompatibilityReport: Equatable, Sendable {
    public let runtimeInfo: EditorCoreUIFFIRuntimeInfo?
    public let minimumABIVersion: UInt32
    public let missingRequiredFeatures: [EditorCoreUIFFIRuntimeFeature]
    public let missingOptionalFeatures: [EditorCoreUIFFIRuntimeFeature]
    public let loadError: String?

    public init(
        runtimeInfo: EditorCoreUIFFIRuntimeInfo?,
        minimumABIVersion: UInt32,
        missingRequiredFeatures: [EditorCoreUIFFIRuntimeFeature],
        missingOptionalFeatures: [EditorCoreUIFFIRuntimeFeature],
        loadError: String?
    ) {
        self.runtimeInfo = runtimeInfo
        self.minimumABIVersion = minimumABIVersion
        self.missingRequiredFeatures = missingRequiredFeatures
        self.missingOptionalFeatures = missingOptionalFeatures
        self.loadError = loadError
    }

    public var isCompatible: Bool {
        guard loadError == nil else {
            return false
        }
        guard let runtimeInfo, runtimeInfo.abiVersion >= minimumABIVersion else {
            return false
        }
        return missingRequiredFeatures.isEmpty
    }

    public var diagnosticMessage: String {
        if let loadError {
            return "Failed to read UI FFI runtime information: \(loadError)"
        }

        guard let runtimeInfo else {
            return "Failed to read UI FFI runtime information."
        }

        var parts: [String] = []
        if runtimeInfo.abiVersion < minimumABIVersion {
            parts.append("UI FFI ABI \(runtimeInfo.abiVersion) is older than required ABI \(minimumABIVersion).")
        }

        if missingRequiredFeatures.isEmpty == false {
            let names = missingRequiredFeatures.map(\.name).joined(separator: ", ")
            parts.append("Missing UI FFI features: \(names).")
        }

        if missingOptionalFeatures.isEmpty == false {
            let names = missingOptionalFeatures.map(\.name).joined(separator: ", ")
            parts.append("Unavailable optional UI FFI features: \(names).")
        }

        if parts.isEmpty {
            return "UI FFI ABI \(runtimeInfo.abiVersion) is compatible."
        }
        return parts.joined(separator: " ")
    }
}

public enum EditorCoreUIFFIRuntimeCompatibility {
    public static let minimumABIVersion: UInt32 = 1

    public static let knownFeatures: [EditorCoreUIFFIRuntimeFeature] = [
        EditorCoreUIFFIRuntimeFeature(
            feature: .jsonCommandDispatch,
            name: "JSON command dispatch",
            reason: "Swift hosts can route low-frequency editor commands through the UI JSON command dispatcher."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .typedDerivedSnapshots,
            name: "typed derived snapshots",
            reason: "Swift hosts can read typed diagnostics, decorations, symbols, folding ranges, and related derived snapshots."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspInteractiveRequests,
            name: "LSP interactive requests",
            reason: "Swift hosts can issue request/take LSP flows for interactive editor commands."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspStatusSnapshot,
            name: "LSP status snapshot",
            reason: "Swift hosts can read typed LSP status and capability snapshots before enabling LSP commands."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .workspaceEditApplication,
            name: "WorkspaceEdit application",
            reason: "Swift hosts can apply LSP WorkspaceEdit payloads through UI FFI helpers."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentUI,
            name: "multi-document UI",
            reason: "Swift hosts can mirror tabs, split views, and project-level state into the core-owned multi-document UI model."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .workspaceDiagnosticsStore,
            name: "workspace diagnostics store",
            reason: "Swift hosts can use the core-owned workspace diagnostics snapshot."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .workspaceDiagnosticsEvents,
            name: "workspace diagnostics events",
            reason: "Swift hosts can cursor over core-owned workspace diagnostics changes."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspResultEvents,
            name: "LSP result events",
            reason: "Swift hosts can drain per-editor LSP result slot events."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentLSPResultEvents,
            name: "multi-document LSP result events",
            reason: "Swift hosts can drain LSP result events aggregated across tabs and split views."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspRequestEvents,
            name: "LSP request events",
            reason: "Swift hosts can drain per-editor LSP request lifecycle events."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentLSPRequestEvents,
            name: "multi-document LSP request events",
            reason: "Swift hosts can drain LSP request lifecycle events aggregated across tabs and split views."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspRequestCancelTimeoutEvents,
            name: "LSP request cancel/timeout events",
            reason: "Swift hosts can explicitly mark pending LSP requests as canceled or timed out."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspSemanticTokensRequests,
            name: "LSP semantic tokens requests",
            reason: "Swift hosts can request and consume semantic tokens full, delta, and range payloads."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspAuxiliaryRequests,
            name: "LSP auxiliary requests",
            reason: "Swift hosts can request auxiliary inlay hint and document link payloads."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspAuxiliaryResolveRequests,
            name: "LSP auxiliary resolve requests",
            reason: "Swift hosts can resolve auxiliary inlay hint and document link payloads."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .editorUIStateEvents,
            name: "Editor UI state events",
            reason: "Swift hosts can drain per-editor state changes through one cursor."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentStateEvents,
            name: "multi-document state events",
            reason: "Swift hosts can drain project-level state changes aggregated across tabs and split views."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .workspaceOutlineSnapshot,
            name: "workspace outline snapshot",
            reason: "Swift hosts can read the core-owned workspace outline snapshot."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentTabDocumentURI,
            name: "multi-document tab document URI",
            reason: "Swift hosts can resolve open core tabs by document URI."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentWorkspaceEditTransaction,
            name: "multi-document WorkspaceEdit transaction",
            reason: "Swift hosts can preview and apply WorkspaceEdit payloads through core-owned multi-document transactions."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentWorkspaceEditTransactionEvents,
            name: "multi-document WorkspaceEdit transaction events",
            reason: "Swift hosts can observe core-owned WorkspaceEdit transaction results through an event cursor."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentWorkspaceRoots,
            name: "multi-document workspace roots",
            reason: "Swift hosts can project workspace root metadata into the core-owned multi-document model."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentWorkspaceEditTransactionUndo,
            name: "multi-document WorkspaceEdit transaction undo",
            reason: "Swift hosts can undo the most recent core-owned WorkspaceEdit transaction."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentTabLanguageID,
            name: "multi-document tab language id",
            reason: "Swift hosts can attach language id metadata to core-owned tabs for project-level language features."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .jsonCommandEnvelope,
            name: "JSON command envelope",
            reason: "Swift command envelope APIs require structured `{ ok, value, error, version }` command results."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .lspResultEnvelope,
            name: "LSP result envelope",
            reason: "Swift hosts can read LSP take-last result slots through structured `{ ok, value, error, version }` envelopes."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .eventStreamEnvelope,
            name: "event stream envelope",
            reason: "Swift hosts can drain EditorUi and multi-document event streams through structured `{ ok, value, error, version }` envelopes."
        ),
        EditorCoreUIFFIRuntimeFeature(
            feature: .multiDocumentSpecialEventStreamEnvelope,
            name: "multi-document special event stream envelope",
            reason: "Swift hosts can drain workspace diagnostics and WorkspaceEdit transaction event streams through structured envelopes."
        ),
    ]

    public static let requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = knownFeatures

    public static func evaluate(
        library: EditorCoreUIFFILibrary,
        minimumABIVersion: UInt32 = EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = EditorCoreUIFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature] = []
    ) -> EditorCoreUIFFIRuntimeCompatibilityReport {
        do {
            return evaluate(
                runtimeInfo: try library.runtimeInfo(),
                minimumABIVersion: minimumABIVersion,
                requiredFeatures: requiredFeatures,
                optionalFeatures: optionalFeatures
            )
        } catch {
            return EditorCoreUIFFIRuntimeCompatibilityReport(
                runtimeInfo: nil,
                minimumABIVersion: minimumABIVersion,
                missingRequiredFeatures: requiredFeatures,
                missingOptionalFeatures: optionalFeatures,
                loadError: String(describing: error)
            )
        }
    }

    public static func evaluate(
        runtimeInfo: EditorCoreUIFFIRuntimeInfo,
        minimumABIVersion: UInt32 = EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = EditorCoreUIFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature] = []
    ) -> EditorCoreUIFFIRuntimeCompatibilityReport {
        let missingRequired = requiredFeatures.filter { runtimeInfo.supports($0.feature) == false }
        let missingOptional = optionalFeatures.filter { runtimeInfo.supports($0.feature) == false }
        return EditorCoreUIFFIRuntimeCompatibilityReport(
            runtimeInfo: runtimeInfo,
            minimumABIVersion: minimumABIVersion,
            missingRequiredFeatures: missingRequired,
            missingOptionalFeatures: missingOptional,
            loadError: nil
        )
    }
}
