import CEditorCoreFFI
import Foundation

private struct SublimeScopeResponse: Decodable {
    let scope: String
}

public final class SublimeProcessor {
    public let ffi: EditorCoreFFILibrary
    private let handle: OpaquePointer

    public init(library: EditorCoreFFILibrary, yaml: String) throws {
        self.ffi = library
        let handle: OpaquePointer? = yaml.withCString { yamlPtr in
            editor_core_ffi_sublime_processor_new_from_yaml(yamlPtr)
        }
        guard let handle else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "sublime_processor_new_from_yaml", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    public init(library: EditorCoreFFILibrary, path: String) throws {
        self.ffi = library
        let handle: OpaquePointer? = path.withCString { pathPtr in
            editor_core_ffi_sublime_processor_new_from_path(pathPtr)
        }
        guard let handle else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "sublime_processor_new_from_path", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        editor_core_ffi_sublime_processor_free(handle)
    }

    public func addSearchPath(_ path: String) throws {
        let ok = path.withCString { pathPtr in
            editor_core_ffi_sublime_processor_add_search_path(handle, pathPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_add_search_path", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func loadSyntaxFromYAML(_ yaml: String) throws {
        let ok = yaml.withCString { yamlPtr in
            editor_core_ffi_sublime_processor_load_syntax_from_yaml(handle, yamlPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_load_syntax_from_yaml", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func loadSyntaxFromPath(_ path: String) throws {
        let ok = path.withCString { pathPtr in
            editor_core_ffi_sublime_processor_load_syntax_from_path(handle, pathPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_load_syntax_from_path", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func setActiveSyntax(reference: String) throws {
        let ok = reference.withCString { refPtr in
            editor_core_ffi_sublime_processor_set_active_syntax_by_reference(handle, refPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_set_active_syntax_by_reference", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func setPreserveCollapsedFolds(_ preserve: Bool) throws {
        let ok = editor_core_ffi_sublime_processor_set_preserve_collapsed_folds(handle, preserve)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_set_preserve_collapsed_folds", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func processJSON(state: EditorState) throws -> String {
        try ffi.takeOwnedCString(
            editor_core_ffi_sublime_processor_process_json(handle, state.handle),
            context: "sublime_processor_process_json"
        )
    }

    public func apply(state: EditorState) throws {
        let ok = editor_core_ffi_sublime_processor_apply(handle, state.handle)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "sublime_processor_apply", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func scopeForStyleId(_ styleId: UInt32) throws -> String {
        let ptr = editor_core_ffi_sublime_processor_scope_for_style_id(handle, styleId)
        let json = try ffi.takeOwnedCString(ptr, context: "sublime_processor_scope_for_style_id")
        return try JSON.decode(SublimeScopeResponse.self, from: json, context: "sublime_scope_for_style_id").scope
    }
}
