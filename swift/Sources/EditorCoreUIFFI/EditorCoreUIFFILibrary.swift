import CEditorCoreUIFFI
import Foundation

/// Swift wrapper for the Rust `editor-core-ui-ffi` C ABI.
///
/// 说明：
/// - 该 Swift 包默认使用 **静态链接**（Rust `staticlib`），因此不再通过 `dlopen/dlsym` 解析符号。
/// - Rust 侧仍保留 `cdylib` 产物（给其它宿主语言/应用使用），但 SwiftPM 这里不依赖它。
public final class EditorCoreUIFFILibrary {
    public init() {}

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

