import EditorCoreUIFFI
import Foundation

struct AttoRuntimeCompatibility {
    struct RuntimeFeature: Equatable {
        let feature: EditorCoreUIFFIFeatures
        let name: String
        let reason: String
    }

    struct Report: Equatable {
        let runtimeInfo: EditorCoreUIFFIRuntimeInfo?
        let minimumABIVersion: UInt32
        let missingFeatures: [RuntimeFeature]
        let missingOptionalFeatures: [RuntimeFeature]
        let loadError: String?

        var isCompatible: Bool {
            guard loadError == nil else {
                return false
            }
            guard let runtimeInfo, runtimeInfo.abiVersion >= minimumABIVersion else {
                return false
            }
            return missingFeatures.isEmpty
        }

        var diagnosticMessage: String {
            if let loadError {
                return "Failed to read editor runtime information: \(loadError)"
            }

            guard let runtimeInfo else {
                return "Failed to read editor runtime information."
            }

            var parts: [String] = []
            if runtimeInfo.abiVersion < minimumABIVersion {
                parts.append("UI FFI ABI \(runtimeInfo.abiVersion) is older than required ABI \(minimumABIVersion).")
            }

            if missingFeatures.isEmpty == false {
                let names = missingFeatures.map(\.name).joined(separator: ", ")
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

    static let minimumUIABIVersion: UInt32 = 1

    static let requiredFeatures: [RuntimeFeature] = [
        RuntimeFeature(
            feature: .jsonCommandDispatch,
            name: "JSON command dispatch",
            reason: "AttoEditor routes low-frequency editor commands through the UI JSON command dispatcher."
        ),
        RuntimeFeature(
            feature: .typedDerivedSnapshots,
            name: "typed derived snapshots",
            reason: "Status bar, panels, and tests consume typed diagnostics/decorations/symbol/folding snapshots."
        ),
        RuntimeFeature(
            feature: .multiDocumentUI,
            name: "multi-document UI",
            reason: "AttoEditor mirrors AppKit tabs and split panes into the core-owned MultiDocumentEditorUi model."
        ),
    ]

    static let optionalFeatures: [RuntimeFeature] = [
        RuntimeFeature(
            feature: .lspInteractiveRequests,
            name: "LSP interactive requests",
            reason: "LSP quick panels and editor commands depend on request/take APIs; commands degrade when unavailable."
        ),
        RuntimeFeature(
            feature: .lspStatusSnapshot,
            name: "LSP status snapshot",
            reason: "Status bar and LSP capability gates consume typed status/capability snapshots; LSP commands degrade when unavailable."
        ),
        RuntimeFeature(
            feature: .workspaceEditApplication,
            name: "WorkspaceEdit application",
            reason: "Rename, code actions, completion resolve, and color presentations apply WorkspaceEdit payloads; edit-producing commands degrade when unavailable."
        ),
        RuntimeFeature(
            feature: .workspaceDiagnosticsStore,
            name: "workspace diagnostics store",
            reason: "Project Problems can use the core-owned multi-document workspace diagnostics snapshot; Swift falls back to local parsing when unavailable."
        ),
        RuntimeFeature(
            feature: .workspaceDiagnosticsEvents,
            name: "workspace diagnostics events",
            reason: "Project Problems and LSP result consumers can cursor over core-owned workspace diagnostics changes; Swift falls back to App-level lifecycle events when unavailable."
        ),
        RuntimeFeature(
            feature: .lspResultEvents,
            name: "LSP result events",
            reason: "LSP result consumers can cursor over core-owned per-editor result slot events; Swift falls back to App-level lifecycle events when unavailable."
        ),
        RuntimeFeature(
            feature: .multiDocumentLSPResultEvents,
            name: "multi-document LSP result events",
            reason: "Project-level result consumers can cursor over core-owned LSP result events aggregated across tabs and split views; Swift falls back to App-level lifecycle events when unavailable."
        ),
        RuntimeFeature(
            feature: .lspRequestEvents,
            name: "LSP request events",
            reason: "LSP request consumers can cursor over core-owned request start/completion lifecycle events; Swift falls back to App-level lifecycle events when unavailable."
        ),
        RuntimeFeature(
            feature: .multiDocumentLSPRequestEvents,
            name: "multi-document LSP request events",
            reason: "Project-level request consumers can cursor over core-owned LSP request lifecycle events aggregated across tabs and split views; Swift falls back to App-level lifecycle events when unavailable."
        ),
        RuntimeFeature(
            feature: .lspRequestCancelTimeoutEvents,
            name: "LSP request cancel/timeout events",
            reason: "Request lifecycle consumers can explicitly close pending request events as canceled or timed out; Swift falls back to App-level timeout/cancel bookkeeping when unavailable."
        ),
        RuntimeFeature(
            feature: .lspSemanticTokensRequests,
            name: "LSP semantic tokens requests",
            reason: "Semantic highlighting refresh can consume typed semantic tokens full/delta/range payloads; Swift falls back to automatic processing when unavailable."
        ),
    ]

    static func evaluate(library: EditorCoreUIFFILibrary) -> Report {
        do {
            return evaluate(runtimeInfo: try library.runtimeInfo())
        } catch {
            return Report(
                runtimeInfo: nil,
                minimumABIVersion: minimumUIABIVersion,
                missingFeatures: requiredFeatures,
                missingOptionalFeatures: optionalFeatures,
                loadError: String(describing: error)
            )
        }
    }

    static func evaluate(runtimeInfo: EditorCoreUIFFIRuntimeInfo) -> Report {
        let missing = requiredFeatures.filter { runtimeInfo.supports($0.feature) == false }
        let missingOptional = optionalFeatures.filter { runtimeInfo.supports($0.feature) == false }
        return Report(
            runtimeInfo: runtimeInfo,
            minimumABIVersion: minimumUIABIVersion,
            missingFeatures: missing,
            missingOptionalFeatures: missingOptional,
            loadError: nil
        )
    }
}
