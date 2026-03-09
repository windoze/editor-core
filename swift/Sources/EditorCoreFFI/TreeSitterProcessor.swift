import CEditorCoreFFI
import Foundation

private struct TreeSitterUpdateModeResponse: Decodable {
    let mode: String
}

public final class TreeSitterProcessor {
    public let ffi: EditorCoreFFILibrary
    private let handle: OpaquePointer

    public init(
        library: EditorCoreFFILibrary,
        languageFn: EcfTreeSitterLanguageFn,
        highlightsQuery: String,
        foldsQuery: String? = nil,
        captureStylesJSON: String? = nil,
        styleLayer: UInt32,
        preserveCollapsedFolds: Bool
    ) throws {
        self.ffi = library

        let handle: OpaquePointer? = highlightsQuery.withCString { highlightsPtr in
            let foldsPtrThunk: (UnsafePointer<CChar>?) -> OpaquePointer? = { foldsPtr in
                let capturePtrThunk: (UnsafePointer<CChar>?) -> OpaquePointer? = { capturePtr in
                    editor_core_ffi_treesitter_processor_new(
                        languageFn,
                        highlightsPtr,
                        foldsPtr,
                        capturePtr,
                        styleLayer,
                        preserveCollapsedFolds
                    )
                }

                if let captureStylesJSON {
                    return captureStylesJSON.withCString { capturePtr in
                        capturePtrThunk(capturePtr)
                    }
                }
                return capturePtrThunk(nil)
            }

            if let foldsQuery {
                return foldsQuery.withCString { foldsPtr in
                    foldsPtrThunk(foldsPtr)
                }
            }
            return foldsPtrThunk(nil)
        }

        guard let handle else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "treesitter_processor_new", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        editor_core_ffi_treesitter_processor_free(handle)
    }

    public func processJSON(state: EditorState) throws -> String {
        try ffi.takeOwnedCString(
            editor_core_ffi_treesitter_processor_process_json(handle, state.handle),
            context: "treesitter_processor_process_json"
        )
    }

    public func apply(state: EditorState) throws {
        let ok = editor_core_ffi_treesitter_processor_apply(handle, state.handle)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "treesitter_processor_apply", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func lastUpdateMode() throws -> String {
        let json = try ffi.takeOwnedCString(
            editor_core_ffi_treesitter_processor_last_update_mode_json(handle),
            context: "treesitter_processor_last_update_mode_json"
        )
        return try JSON.decode(TreeSitterUpdateModeResponse.self, from: json, context: "treesitter_last_update_mode").mode
    }
}
