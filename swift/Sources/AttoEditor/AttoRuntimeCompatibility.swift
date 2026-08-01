import EditorCoreUIFFI
import Foundation

struct AttoRuntimeCompatibility {
    struct RequiredFeature: Equatable {
        let feature: EditorCoreUIFFIFeatures
        let name: String
        let reason: String
    }

    struct Report: Equatable {
        let runtimeInfo: EditorCoreUIFFIRuntimeInfo?
        let minimumABIVersion: UInt32
        let missingFeatures: [RequiredFeature]
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

            if parts.isEmpty {
                return "UI FFI ABI \(runtimeInfo.abiVersion) is compatible."
            }
            return parts.joined(separator: " ")
        }
    }

    static let minimumUIABIVersion: UInt32 = 1

    static let requiredFeatures: [RequiredFeature] = [
        RequiredFeature(
            feature: .jsonCommandDispatch,
            name: "JSON command dispatch",
            reason: "AttoEditor routes low-frequency editor commands through the UI JSON command dispatcher."
        ),
        RequiredFeature(
            feature: .typedDerivedSnapshots,
            name: "typed derived snapshots",
            reason: "Status bar, panels, and tests consume typed diagnostics/decorations/symbol/folding snapshots."
        ),
        RequiredFeature(
            feature: .lspInteractiveRequests,
            name: "LSP interactive requests",
            reason: "LSP quick panels and editor commands depend on request/take APIs."
        ),
        RequiredFeature(
            feature: .lspStatusSnapshot,
            name: "LSP status snapshot",
            reason: "Status bar and LSP capability gates consume typed status/capability snapshots."
        ),
        RequiredFeature(
            feature: .workspaceEditApplication,
            name: "WorkspaceEdit application",
            reason: "Rename, code actions, completion resolve, and color presentations apply WorkspaceEdit payloads."
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
                loadError: String(describing: error)
            )
        }
    }

    static func evaluate(runtimeInfo: EditorCoreUIFFIRuntimeInfo) -> Report {
        let missing = requiredFeatures.filter { runtimeInfo.supports($0.feature) == false }
        return Report(
            runtimeInfo: runtimeInfo,
            minimumABIVersion: minimumUIABIVersion,
            missingFeatures: missing,
            loadError: nil
        )
    }
}
