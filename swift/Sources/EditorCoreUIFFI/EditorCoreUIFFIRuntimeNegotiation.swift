import Foundation

public enum EditorCoreUIFFIRuntimeFeatureAvailabilityState: String, Equatable, Sendable {
    case available
    case unsupported
    case runtimeUnavailable = "runtime_unavailable"
    case versionMismatch = "version_mismatch"
}

public struct EditorCoreUIFFIRuntimeFeatureNegotiation: Equatable, Sendable {
    public let feature: EditorCoreUIFFIFeatures
    public let featureFlag: UInt64
    public let name: String
    public let hostReason: String
    public let isRequired: Bool
    public let availability: EditorCoreUIFFIRuntimeFeatureAvailabilityState
    public let runtimeABIVersion: UInt32?
    public let minimumABIVersion: UInt32
    public let runtimeVersion: String?
    public let runtimeFeatureFlags: UInt64?
    public let descriptor: EditorCoreUIFFIRuntimeFeatureDescriptor?
    public let unsupportedReason: String?

    public init(
        feature: EditorCoreUIFFIFeatures,
        featureFlag: UInt64,
        name: String,
        hostReason: String,
        isRequired: Bool,
        availability: EditorCoreUIFFIRuntimeFeatureAvailabilityState,
        runtimeABIVersion: UInt32?,
        minimumABIVersion: UInt32,
        runtimeVersion: String?,
        runtimeFeatureFlags: UInt64?,
        descriptor: EditorCoreUIFFIRuntimeFeatureDescriptor?,
        unsupportedReason: String?
    ) {
        self.feature = feature
        self.featureFlag = featureFlag
        self.name = name
        self.hostReason = hostReason
        self.isRequired = isRequired
        self.availability = availability
        self.runtimeABIVersion = runtimeABIVersion
        self.minimumABIVersion = minimumABIVersion
        self.runtimeVersion = runtimeVersion
        self.runtimeFeatureFlags = runtimeFeatureFlags
        self.descriptor = descriptor
        self.unsupportedReason = unsupportedReason
    }

    public var isAvailable: Bool {
        availability == .available
    }
}

extension EditorCoreUIFFIRuntimeCompatibility {
    public static func negotiate(
        runtimeInfo: EditorCoreUIFFIRuntimeInfo,
        minimumABIVersion: UInt32 = EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = EditorCoreUIFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature] = []
    ) -> [EditorCoreUIFFIRuntimeFeatureNegotiation] {
        negotiateFeatures(
            runtimeInfo: runtimeInfo,
            minimumABIVersion: minimumABIVersion,
            requiredFeatures: requiredFeatures,
            optionalFeatures: optionalFeatures,
            descriptors: []
        )
    }

    public static func negotiate(
        capabilitySnapshot: EditorCoreUIFFIRuntimeCapabilitySnapshot,
        minimumABIVersion: UInt32 = EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = EditorCoreUIFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature] = []
    ) -> [EditorCoreUIFFIRuntimeFeatureNegotiation] {
        negotiateFeatures(
            runtimeInfo: capabilitySnapshot.runtimeInfo,
            minimumABIVersion: minimumABIVersion,
            requiredFeatures: requiredFeatures,
            optionalFeatures: optionalFeatures,
            descriptors: capabilitySnapshot.features
        )
    }

    public static func negotiateUnavailable(
        loadError: String,
        minimumABIVersion: UInt32 = EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature] = EditorCoreUIFFIRuntimeCompatibility.requiredFeatures,
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature] = []
    ) -> [EditorCoreUIFFIRuntimeFeatureNegotiation] {
        negotiateUnavailableFeatures(
            loadError: loadError,
            minimumABIVersion: minimumABIVersion,
            requiredFeatures: requiredFeatures,
            optionalFeatures: optionalFeatures
        )
    }

    static func negotiateUnavailableFeatures(
        loadError: String,
        minimumABIVersion: UInt32,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature],
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature]
    ) -> [EditorCoreUIFFIRuntimeFeatureNegotiation] {
        requestedFeatures(requiredFeatures: requiredFeatures, optionalFeatures: optionalFeatures).map { request in
            EditorCoreUIFFIRuntimeFeatureNegotiation(
                feature: request.feature.feature,
                featureFlag: request.feature.feature.rawValue,
                name: request.feature.name,
                hostReason: request.feature.reason,
                isRequired: request.isRequired,
                availability: .runtimeUnavailable,
                runtimeABIVersion: nil,
                minimumABIVersion: minimumABIVersion,
                runtimeVersion: nil,
                runtimeFeatureFlags: nil,
                descriptor: nil,
                unsupportedReason: "UI FFI runtime information is unavailable: \(loadError)"
            )
        }
    }

    static func negotiateFeatures(
        runtimeInfo: EditorCoreUIFFIRuntimeInfo,
        minimumABIVersion: UInt32,
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature],
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature],
        descriptors: [EditorCoreUIFFIRuntimeFeatureDescriptor]
    ) -> [EditorCoreUIFFIRuntimeFeatureNegotiation] {
        let descriptorsByFlag = Dictionary(
            descriptors.map { ($0.flag, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let requests = requestedFeatures(
            requiredFeatures: requiredFeatures,
            optionalFeatures: optionalFeatures
        )
        return requests.map { request in
            let feature = request.feature
            let featureFlag = feature.feature.rawValue
            let descriptor = descriptorsByFlag[featureFlag]
            let availability: EditorCoreUIFFIRuntimeFeatureAvailabilityState
            let unsupportedReason: String?

            if runtimeInfo.abiVersion < minimumABIVersion {
                availability = .versionMismatch
                unsupportedReason = "\(feature.name) requires UI FFI ABI >= \(minimumABIVersion); " +
                    "runtime \(runtimeInfo.version) reports ABI \(runtimeInfo.abiVersion)."
            } else if runtimeInfo.supports(feature.feature) {
                availability = .available
                unsupportedReason = nil
            } else {
                availability = .unsupported
                unsupportedReason = "\(feature.reason) Runtime feature flag " +
                    "\(featureFlagHex(featureFlag)) is not set by UI FFI runtime \(runtimeInfo.version)."
            }

            return EditorCoreUIFFIRuntimeFeatureNegotiation(
                feature: feature.feature,
                featureFlag: featureFlag,
                name: feature.name,
                hostReason: feature.reason,
                isRequired: request.isRequired,
                availability: availability,
                runtimeABIVersion: runtimeInfo.abiVersion,
                minimumABIVersion: minimumABIVersion,
                runtimeVersion: runtimeInfo.version,
                runtimeFeatureFlags: runtimeInfo.features.rawValue,
                descriptor: descriptor,
                unsupportedReason: unsupportedReason
            )
        }
    }

    private static func requestedFeatures(
        requiredFeatures: [EditorCoreUIFFIRuntimeFeature],
        optionalFeatures: [EditorCoreUIFFIRuntimeFeature]
    ) -> [(feature: EditorCoreUIFFIRuntimeFeature, isRequired: Bool)] {
        requiredFeatures.map { ($0, true) } + optionalFeatures.map { ($0, false) }
    }

    private static func featureFlagHex(_ flag: UInt64) -> String {
        "0x" + String(flag, radix: 16, uppercase: false)
    }
}
