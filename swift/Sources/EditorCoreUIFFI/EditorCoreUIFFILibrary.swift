import CEditorCoreUIFFI
import Foundation

/// Swift wrapper for the Rust `editor-core-ui-ffi` C ABI.
///
/// 说明：
/// - 该 Swift 包默认使用 **静态链接**（Rust `staticlib`），因此不再通过 `dlopen/dlsym` 解析符号。
/// - Rust 侧仍保留 `cdylib` 产物（给其它宿主语言/应用使用），但 SwiftPM 这里不依赖它。
public final class EditorCoreUIFFILibrary {
    public let abiVersion: UInt32
    public let featureFlags: EditorCoreUIFFIFeatures

    public init() {
        self.abiVersion = editor_core_ui_ffi_abi_version()
        self.featureFlags = EditorCoreUIFFIFeatures(rawValue: editor_core_ui_ffi_feature_flags())
    }

    public func versionString() throws -> String {
        guard let ptr = editor_core_ui_ffi_version() else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_core_ui_ffi_version",
                message: lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func runtimeInfo() throws -> EditorCoreUIFFIRuntimeInfo {
        EditorCoreUIFFIRuntimeInfo(
            abiVersion: abiVersion,
            version: try versionString(),
            features: featureFlags
        )
    }

    public func runtimeInfoJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_runtime_info_json() else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_core_ui_ffi_runtime_info_json",
                message: lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func runtimeCapabilitySnapshot() throws -> EditorCoreUIFFIRuntimeCapabilitySnapshot {
        let data = Data(try runtimeInfoJSON().utf8)
        return try JSONDecoder().decode(EditorCoreUIFFIRuntimeCapabilitySnapshot.self, from: data)
    }

    func lastErrorMessageString() -> String {
        guard let ptr = editor_core_ui_ffi_last_error_message() else {
            return ""
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    func ensureStatus(_ status: Int32, context: String) throws {
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: context, message: "unknown status \(status)")
        }
        guard code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: context, message: lastErrorMessageString())
        }
    }
}

public struct EditorCoreUIFFIFeatures: OptionSet, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let jsonCommandDispatch = Self(rawValue: 1 << 0)
    public static let typedDerivedSnapshots = Self(rawValue: 1 << 1)
    public static let lspInteractiveRequests = Self(rawValue: 1 << 2)
    public static let lspStatusSnapshot = Self(rawValue: 1 << 3)
    public static let workspaceEditApplication = Self(rawValue: 1 << 4)
    public static let multiDocumentUI = Self(rawValue: 1 << 5)
    public static let workspaceDiagnosticsStore = Self(rawValue: 1 << 6)
    public static let workspaceDiagnosticsEvents = Self(rawValue: 1 << 7)
    public static let lspResultEvents = Self(rawValue: 1 << 8)
    public static let multiDocumentLSPResultEvents = Self(rawValue: 1 << 9)
    public static let lspRequestEvents = Self(rawValue: 1 << 10)
    public static let multiDocumentLSPRequestEvents = Self(rawValue: 1 << 11)
    public static let lspRequestCancelTimeoutEvents = Self(rawValue: 1 << 12)
    public static let lspSemanticTokensRequests = Self(rawValue: 1 << 13)
    public static let lspAuxiliaryRequests = Self(rawValue: 1 << 14)
    public static let lspAuxiliaryResolveRequests = Self(rawValue: 1 << 15)
    public static let editorUIStateEvents = Self(rawValue: 1 << 16)
    public static let multiDocumentStateEvents = Self(rawValue: 1 << 17)
    public static let workspaceOutlineSnapshot = Self(rawValue: 1 << 18)
    public static let multiDocumentTabDocumentURI = Self(rawValue: 1 << 19)
    public static let multiDocumentWorkspaceEditTransaction = Self(rawValue: 1 << 20)
    public static let multiDocumentWorkspaceEditTransactionEvents = Self(rawValue: 1 << 21)
    public static let multiDocumentWorkspaceRoots = Self(rawValue: 1 << 22)
    public static let multiDocumentWorkspaceEditTransactionUndo = Self(rawValue: 1 << 23)
    public static let multiDocumentTabLanguageID = Self(rawValue: 1 << 24)
    public static let jsonCommandEnvelope = Self(rawValue: 1 << 25)
    public static let lspResultEnvelope = Self(rawValue: 1 << 26)
    public static let eventStreamEnvelope = Self(rawValue: 1 << 27)
    public static let multiDocumentSpecialEventStreamEnvelope = Self(rawValue: 1 << 28)
    public static let workspaceEditTransactionEnvelope = Self(rawValue: 1 << 29)
    public static let workspaceDiagnosticsEnvelope = Self(rawValue: 1 << 30)
    public static let workspaceOutlineSnapshotEnvelope = Self(rawValue: 1 << 31)
    public static let multiDocumentSnapshotEnvelope = Self(rawValue: 1 << 32)
    public static let multiDocumentSearchEnvelope = Self(rawValue: 1 << 33)
    public static let multiDocumentWorkspaceRootsChangeEnvelope = Self(rawValue: 1 << 34)
    public static let multiDocumentProjectLSPServersEnvelope = Self(rawValue: 1 << 35)
    public static let editorUIDerivedSnapshotEnvelope = Self(rawValue: 1 << 36)
    public static let lspStatusEnvelope = Self(rawValue: 1 << 37)
    public static let lspWorkspaceEditApplicationEnvelope = Self(rawValue: 1 << 38)
    public static let editorUIMinimapEnvelope = Self(rawValue: 1 << 39)
    public static let multiDocumentWorkspaceEditTransactionRedo = Self(rawValue: 1 << 40)
    public static let editorUIViewPointPayloadEnvelope = Self(rawValue: 1 << 41)
    public static let multiDocumentProjectLSPStartPlan = Self(rawValue: 1 << 42)
    public static let multiDocumentProjectLSPLifecycleEvents = Self(rawValue: 1 << 43)
    public static let multiDocumentProjectLSPStopPlan = Self(rawValue: 1 << 44)
    public static let multiDocumentProjectLSPRestartPlan = Self(rawValue: 1 << 45)
    public static let multiDocumentProjectLSPLifecycleEnvelope = Self(rawValue: 1 << 46)
    public static let lspDerivedStateApplicationEnvelope = Self(rawValue: 1 << 47)
    public static let lspSemanticTokensApplicationEnvelope = Self(rawValue: 1 << 48)
    public static let multiDocumentWorkspaceFileSearch = Self(rawValue: 1 << 49)
    public static let multiDocumentWorkspaceFileReplacement = Self(rawValue: 1 << 50)
    public static let multiDocumentRecentFiles = Self(rawValue: 1 << 51)
    public static let multiDocumentWorkspaceFileList = Self(rawValue: 1 << 52)
    public static let multiDocumentRecentProjects = Self(rawValue: 1 << 53)
    public static let multiDocumentProjectFileIndex = Self(rawValue: 1 << 54)
    public static let multiDocumentProjectFileIndexQuery = Self(rawValue: 1 << 55)
    public static let multiDocumentWorkspaceFileOperationEnvelope = Self(rawValue: 1 << 56)
}

public struct EditorCoreUIFFIRuntimeInfo: Equatable, Sendable {
    public let abiVersion: UInt32
    public let version: String
    public let features: EditorCoreUIFFIFeatures

    public init(abiVersion: UInt32, version: String, features: EditorCoreUIFFIFeatures) {
        self.abiVersion = abiVersion
        self.version = version
        self.features = features
    }

    public func supports(_ feature: EditorCoreUIFFIFeatures) -> Bool {
        features.contains(feature)
    }
}

public struct EditorCoreUIFFIRuntimeFeatureDescriptor: Equatable, Sendable, Decodable {
    public let bit: UInt8
    public let flag: UInt64
    public let name: String
    public let description: String

    public init(bit: UInt8, flag: UInt64, name: String, description: String) {
        self.bit = bit
        self.flag = flag
        self.name = name
        self.description = description
    }

    public var feature: EditorCoreUIFFIFeatures {
        EditorCoreUIFFIFeatures(rawValue: flag)
    }
}

public struct EditorCoreUIFFIRuntimeCapabilitySnapshot: Equatable, Sendable, Decodable {
    public let kind: String
    public let abiVersion: UInt32
    public let version: String
    public let featureFlags: EditorCoreUIFFIFeatures
    public let features: [EditorCoreUIFFIRuntimeFeatureDescriptor]

    public init(
        kind: String,
        abiVersion: UInt32,
        version: String,
        featureFlags: EditorCoreUIFFIFeatures,
        features: [EditorCoreUIFFIRuntimeFeatureDescriptor]
    ) {
        self.kind = kind
        self.abiVersion = abiVersion
        self.version = version
        self.featureFlags = featureFlags
        self.features = features
    }

    public var runtimeInfo: EditorCoreUIFFIRuntimeInfo {
        EditorCoreUIFFIRuntimeInfo(
            abiVersion: abiVersion,
            version: version,
            features: featureFlags
        )
    }

    public func supports(_ feature: EditorCoreUIFFIFeatures) -> Bool {
        featureFlags.contains(feature)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case abiVersion = "abi_version"
        case version
        case featureFlags = "feature_flags"
        case features
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        abiVersion = try container.decode(UInt32.self, forKey: .abiVersion)
        version = try container.decode(String.self, forKey: .version)
        featureFlags = EditorCoreUIFFIFeatures(rawValue: try container.decode(UInt64.self, forKey: .featureFlags))
        features = try container.decode([EditorCoreUIFFIRuntimeFeatureDescriptor].self, forKey: .features)
    }
}
