import CEditorCoreFFI
import Foundation

/// Swift wrapper for the Rust `editor-core-ffi` C ABI.
///
/// 说明：
/// - 该 Swift 包默认使用 **静态链接**（Rust `staticlib`），因此不再通过 `dlopen/dlsym` 动态加载。
/// - Rust 侧仍保留 `cdylib` 产物（给其它语言/宿主使用），但 SwiftPM 这里不依赖它。
public final class EditorCoreFFILibrary {
    public let abiVersion: UInt32
    public let featureFlags: EditorCoreFFIFeatures

    /// Backwards-compatible initializer.
    ///
    /// - Parameter path: 以前用于指定 dylib 路径（动态加载）。静态链接模式下该参数被忽略。
    public init(path: String? = nil) throws {
        _ = path
        self.abiVersion = editor_core_ffi_abi_version()
        self.featureFlags = EditorCoreFFIFeatures(rawValue: editor_core_ffi_feature_flags())
    }

    public func versionString() throws -> String {
        return try takeOwnedCString(editor_core_ffi_version(), context: "editor_core_ffi_version")
    }

    public func runtimeInfo() throws -> EditorCoreFFIRuntimeInfo {
        EditorCoreFFIRuntimeInfo(
            abiVersion: abiVersion,
            version: try versionString(),
            features: featureFlags
        )
    }

    public func runtimeInfoJSON() throws -> String {
        try takeOwnedCString(editor_core_ffi_runtime_info_json(), context: "editor_core_ffi_runtime_info_json")
    }

    public func lastErrorMessage() -> String {
        // 注意：Rust 侧返回的是“需释放”的字符串。
        guard let ptr = editor_core_ffi_last_error_message() else {
            return ""
        }
        defer { editor_core_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Backwards-compatible name used by earlier dynamic-loading implementation.
    public func lastErrorMessageString() -> String {
        lastErrorMessage()
    }

    func ensureStatus(_ status: Int32, context: String) throws {
        guard let code = EcfStatus(rawValue: status) else {
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: context, message: "unknown status \(status)")
        }
        guard code == .ok else {
            let message = lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: code, context: context, message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    func takeOwnedCString(_ ptr: UnsafeMutablePointer<CChar>?, context: String) throws -> String {
        guard let ptr else {
            let message = lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: context, message: message.isEmpty ? "no last_error_message" : message)
        }
        defer { editor_core_ffi_string_free(ptr) }
        return String(cString: ptr)
    }
}

public struct EditorCoreFFIFeatures: OptionSet, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let jsonCommandDispatch = Self(rawValue: 1 << 0)
    public static let typedHotPath = Self(rawValue: 1 << 1)
    public static let workspaceTypedAPI = Self(rawValue: 1 << 2)
    public static let viewportBlob = Self(rawValue: 1 << 3)
    public static let processingEditJSON = Self(rawValue: 1 << 4)
    public static let lspHelpers = Self(rawValue: 1 << 5)
    public static let sublimeProcessor = Self(rawValue: 1 << 6)
    public static let treeSitterProcessor = Self(rawValue: 1 << 7)
    public static let jsonCommandEnvelope = Self(rawValue: 1 << 8)
    public static let renderingSnapshotEnvelope = Self(rawValue: 1 << 9)
    public static let editorStateDerivedSnapshotEnvelope = Self(rawValue: 1 << 10)
}

public struct EditorCoreFFIRuntimeInfo: Equatable, Sendable {
    public let abiVersion: UInt32
    public let version: String
    public let features: EditorCoreFFIFeatures

    public init(abiVersion: UInt32, version: String, features: EditorCoreFFIFeatures) {
        self.abiVersion = abiVersion
        self.version = version
        self.features = features
    }

    public func supports(_ feature: EditorCoreFFIFeatures) -> Bool {
        features.contains(feature)
    }
}
