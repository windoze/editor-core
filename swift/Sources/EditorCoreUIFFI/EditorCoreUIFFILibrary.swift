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
