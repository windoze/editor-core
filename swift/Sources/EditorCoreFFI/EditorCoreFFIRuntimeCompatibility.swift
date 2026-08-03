import Foundation

public struct EditorCoreFFIRuntimeFeature: Equatable, Sendable {
    public let feature: EditorCoreFFIFeatures
    public let name: String
    public let reason: String

    public init(feature: EditorCoreFFIFeatures, name: String, reason: String) {
        self.feature = feature
        self.name = name
        self.reason = reason
    }
}

public struct EditorCoreFFIRuntimeCompatibilityReport: Equatable, Sendable {
    public let runtimeInfo: EditorCoreFFIRuntimeInfo?
    public let minimumABIVersion: UInt32
    public let missingRequiredFeatures: [EditorCoreFFIRuntimeFeature]
    public let missingOptionalFeatures: [EditorCoreFFIRuntimeFeature]
    public let loadError: String?

    public init(
        runtimeInfo: EditorCoreFFIRuntimeInfo?,
        minimumABIVersion: UInt32,
        missingRequiredFeatures: [EditorCoreFFIRuntimeFeature],
        missingOptionalFeatures: [EditorCoreFFIRuntimeFeature],
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
            return "Failed to read core runtime information: \(loadError)"
        }

        guard let runtimeInfo else {
            return "Failed to read core runtime information."
        }

        var parts: [String] = []
        if runtimeInfo.abiVersion < minimumABIVersion {
            parts.append("Core FFI ABI \(runtimeInfo.abiVersion) is older than required ABI \(minimumABIVersion).")
        }

        if missingRequiredFeatures.isEmpty == false {
            let names = missingRequiredFeatures.map(\.name).joined(separator: ", ")
            parts.append("Missing core FFI features: \(names).")
        }

        if missingOptionalFeatures.isEmpty == false {
            let names = missingOptionalFeatures.map(\.name).joined(separator: ", ")
            parts.append("Unavailable optional core FFI features: \(names).")
        }

        if parts.isEmpty {
            return "Core FFI ABI \(runtimeInfo.abiVersion) is compatible."
        }
        return parts.joined(separator: " ")
    }
}

public enum EditorCoreFFIRuntimeCompatibility {
    public static let minimumABIVersion: UInt32 = 1

    public static let knownFeatures: [EditorCoreFFIRuntimeFeature] = [
        EditorCoreFFIRuntimeFeature(
            feature: .jsonCommandDispatch,
            name: "JSON command dispatch",
            reason: "Headless hosts can route lower-frequency editor commands through the JSON command bridge."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .typedHotPath,
            name: "typed hot path",
            reason: "Swift typed editing, movement, and document stats APIs call fixed-width hot-path C ABI functions."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .workspaceTypedAPI,
            name: "workspace typed API",
            reason: "Swift Workspace wrappers depend on typed open/create/info/viewport workspace APIs."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .viewportBlob,
            name: "viewport blob",
            reason: "Swift viewport rendering helpers consume the binary viewport blob ABI."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .processingEditJSON,
            name: "processing edit JSON",
            reason: "Swift processing edit helpers apply JSON style/decoration edits produced by integration crates."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .lspHelpers,
            name: "LSP helpers",
            reason: "Swift LSP bridge helpers call core FFI conversion and WorkspaceEdit helper APIs."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .sublimeProcessor,
            name: "Sublime processor",
            reason: "Swift SublimeProcessor wrappers depend on the Sublime syntax processor lifecycle and apply/process APIs."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .treeSitterProcessor,
            name: "Tree-sitter processor",
            reason: "Swift TreeSitterProcessor wrappers depend on the Tree-sitter processor and indenter APIs."
        ),
        EditorCoreFFIRuntimeFeature(
            feature: .jsonCommandEnvelope,
            name: "JSON command envelope",
            reason: "Swift command envelope APIs require structured `{ ok, value, error, version }` command results."
        ),
    ]

    public static let requiredFeatures: [EditorCoreFFIRuntimeFeature] = knownFeatures

    public static func evaluate(
        library: EditorCoreFFILibrary,
        minimumABIVersion: UInt32 = EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreFFIRuntimeFeature] = EditorCoreFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreFFIRuntimeFeature] = []
    ) -> EditorCoreFFIRuntimeCompatibilityReport {
        do {
            return evaluate(
                runtimeInfo: try library.runtimeInfo(),
                minimumABIVersion: minimumABIVersion,
                requiredFeatures: requiredFeatures,
                optionalFeatures: optionalFeatures
            )
        } catch {
            return EditorCoreFFIRuntimeCompatibilityReport(
                runtimeInfo: nil,
                minimumABIVersion: minimumABIVersion,
                missingRequiredFeatures: requiredFeatures,
                missingOptionalFeatures: optionalFeatures,
                loadError: String(describing: error)
            )
        }
    }

    public static func evaluate(
        runtimeInfo: EditorCoreFFIRuntimeInfo,
        minimumABIVersion: UInt32 = EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreFFIRuntimeFeature] = EditorCoreFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreFFIRuntimeFeature] = []
    ) -> EditorCoreFFIRuntimeCompatibilityReport {
        let missingRequired = requiredFeatures.filter { runtimeInfo.supports($0.feature) == false }
        let missingOptional = optionalFeatures.filter { runtimeInfo.supports($0.feature) == false }
        return EditorCoreFFIRuntimeCompatibilityReport(
            runtimeInfo: runtimeInfo,
            minimumABIVersion: minimumABIVersion,
            missingRequiredFeatures: missingRequired,
            missingOptionalFeatures: missingOptional,
            loadError: nil
        )
    }
}
