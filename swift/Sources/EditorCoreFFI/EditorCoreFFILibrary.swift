import CEditorCoreFFI
import Foundation

/// Swift wrapper for the Rust `editor-core-ffi` C ABI.
///
/// 说明：
/// - 该 Swift 包默认使用 **静态链接**（Rust `staticlib`），因此不再通过 `dlopen/dlsym` 动态加载。
/// - Rust 侧仍保留 `cdylib` 产物（给其它语言/宿主使用），但 SwiftPM 这里不依赖它。
public final class EditorCoreFFILibrary {
    public let abiVersion: UInt32

    /// Backwards-compatible initializer.
    ///
    /// - Parameter path: 以前用于指定 dylib 路径（动态加载）。静态链接模式下该参数被忽略。
    public init(path: String? = nil) throws {
        _ = path
        self.abiVersion = editor_core_ffi_abi_version()
    }

    /// Built-in Tree-sitter Rust language function pointer.
    ///
    /// Rust 侧通过 `editor_core_ffi_treesitter_language_rust()` 导出 language pointer，
    /// C ABI 里把它抽象成 `EcfTreeSitterLanguageFn`，便于传入 processor 构造函数。
    public var treeSitterRustLanguageFn: EcfTreeSitterLanguageFn {
        editor_core_ffi_treesitter_language_rust
    }

    public func versionString() throws -> String {
        return try takeOwnedCString(editor_core_ffi_version(), context: "editor_core_ffi_version")
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
