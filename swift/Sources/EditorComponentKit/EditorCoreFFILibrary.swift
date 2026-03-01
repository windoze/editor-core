import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum EditorCoreFFIStatusCode: Int32 {
    case ok = 0
    case invalidArgument = 1
    case invalidUTF8 = 2
    case notFound = 3
    case bufferTooSmall = 4
    case parse = 5
    case commandFailed = 6
    case `internal` = 7
    case unsupported = 8
    case versionMismatch = 9
}

public final class EditorCoreFFILibrary {
    typealias FnAbiVersion = @convention(c) () -> UInt32
    typealias FnLastErrorMessage = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias FnStringFree = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    typealias FnEditorStateNew = @convention(c) (UnsafePointer<CChar>?, Int) -> UnsafeMutableRawPointer?
    typealias FnEditorStateFree = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnEditorStateExecuteJSON = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateApplyProcessingEditsJSON = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> Bool
    typealias FnEditorStateFullStateJSON = @convention(c) (UnsafeRawPointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateTextJSON = @convention(c) (UnsafeRawPointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateMinimapJSON = @convention(c) (
        UnsafeRawPointer?,
        Int,
        Int
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateViewportComposedJSON = @convention(c) (
        UnsafeRawPointer?,
        Int,
        Int
    ) -> UnsafeMutablePointer<CChar>?

    typealias FnEditorInsertTextUTF8 = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<UInt8>?,
        UInt32
    ) -> Int32
    typealias FnEditorBackspace = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorDeleteForward = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorUndo = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorRedo = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorMoveTo = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32) -> Int32
    typealias FnEditorMoveBy = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Int32
    typealias FnEditorSetSelection = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32,
        UInt32,
        UInt32,
        UInt32,
        UInt8
    ) -> Int32
    typealias FnEditorClearSelection = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorViewportBlob = @convention(c) (
        UnsafeRawPointer?,
        UInt32,
        UInt32,
        UnsafeMutablePointer<UInt8>?,
        UInt32,
        UnsafeMutablePointer<UInt32>?
    ) -> Int32

    typealias FnLspPathToFileURI = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspFileURIToPath = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspPercentEncodePath = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspPercentDecodePath = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspCharOffsetToUTF16 = @convention(c) (UnsafePointer<CChar>?, Int) -> Int
    typealias FnLspUTF16ToCharOffset = @convention(c) (UnsafePointer<CChar>?, Int) -> Int
    typealias FnLspDiagnosticsToProcessingEditsJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentHighlightsToProcessingEditJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspInlayHintsToProcessingEditJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentLinksToProcessingEditJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspCodeLensToProcessingEditJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentSymbolsToProcessingEditJSON = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?

    typealias FnSublimeProcessorNewFromYAML = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    typealias FnSublimeProcessorNewFromPath = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    typealias FnSublimeProcessorFree = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnSublimeProcessorApply = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
    typealias FnSublimeProcessorProcessJSON = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeRawPointer?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnSublimeScopeForStyleID = @convention(c) (
        UnsafeRawPointer?,
        UInt32
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnSublimeSetActiveSyntaxByReference = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> Bool

    public typealias FnTreeSitterLanguageFn = @convention(c) () -> UnsafeRawPointer?
    typealias FnTreeSitterProcessorNew = @convention(c) (
        FnTreeSitterLanguageFn?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt32,
        Bool
    ) -> UnsafeMutableRawPointer?
    typealias FnTreeSitterProcessorFree = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnTreeSitterProcessorApply = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
    typealias FnTreeSitterProcessorProcessJSON = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeRawPointer?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnTreeSitterProcessorLastUpdateModeJSON = @convention(c) (
        UnsafeRawPointer?
    ) -> UnsafeMutablePointer<CChar>?

    private let handle: UnsafeMutableRawPointer
    public let resolvedLibraryPath: String

    let abiVersionFn: FnAbiVersion
    let lastErrorMessageFn: FnLastErrorMessage
    let stringFreeFn: FnStringFree

    let editorStateNewFn: FnEditorStateNew
    let editorStateFreeFn: FnEditorStateFree
    let editorStateExecuteJSONFn: FnEditorStateExecuteJSON
    let editorStateApplyProcessingEditsJSONFn: FnEditorStateApplyProcessingEditsJSON
    let editorStateFullStateJSONFn: FnEditorStateFullStateJSON
    let editorStateTextJSONFn: FnEditorStateTextJSON
    let editorStateMinimapJSONFn: FnEditorStateMinimapJSON
    let editorStateViewportComposedJSONFn: FnEditorStateViewportComposedJSON

    let editorInsertTextUTF8Fn: FnEditorInsertTextUTF8
    let editorBackspaceFn: FnEditorBackspace
    let editorDeleteForwardFn: FnEditorDeleteForward
    let editorUndoFn: FnEditorUndo
    let editorRedoFn: FnEditorRedo
    let editorMoveToFn: FnEditorMoveTo
    let editorMoveByFn: FnEditorMoveBy
    let editorSetSelectionFn: FnEditorSetSelection
    let editorClearSelectionFn: FnEditorClearSelection
    let editorViewportBlobFn: FnEditorViewportBlob

    let lspPathToFileURIFn: FnLspPathToFileURI
    let lspFileURIToPathFn: FnLspFileURIToPath
    let lspPercentEncodePathFn: FnLspPercentEncodePath
    let lspPercentDecodePathFn: FnLspPercentDecodePath
    let lspCharOffsetToUTF16Fn: FnLspCharOffsetToUTF16
    let lspUTF16ToCharOffsetFn: FnLspUTF16ToCharOffset
    let lspDiagnosticsToProcessingEditsJSONFn: FnLspDiagnosticsToProcessingEditsJSON
    let lspDocumentHighlightsToProcessingEditJSONFn: FnLspDocumentHighlightsToProcessingEditJSON
    let lspInlayHintsToProcessingEditJSONFn: FnLspInlayHintsToProcessingEditJSON
    let lspDocumentLinksToProcessingEditJSONFn: FnLspDocumentLinksToProcessingEditJSON
    let lspCodeLensToProcessingEditJSONFn: FnLspCodeLensToProcessingEditJSON
    let lspDocumentSymbolsToProcessingEditJSONFn: FnLspDocumentSymbolsToProcessingEditJSON

    let sublimeProcessorNewFromYAMLFn: FnSublimeProcessorNewFromYAML
    let sublimeProcessorNewFromPathFn: FnSublimeProcessorNewFromPath
    let sublimeProcessorFreeFn: FnSublimeProcessorFree
    let sublimeProcessorApplyFn: FnSublimeProcessorApply
    let sublimeProcessorProcessJSONFn: FnSublimeProcessorProcessJSON
    let sublimeScopeForStyleIDFn: FnSublimeScopeForStyleID
    let sublimeSetActiveSyntaxByReferenceFn: FnSublimeSetActiveSyntaxByReference

    let treeSitterProcessorNewFn: FnTreeSitterProcessorNew
    let treeSitterProcessorFreeFn: FnTreeSitterProcessorFree
    let treeSitterProcessorApplyFn: FnTreeSitterProcessorApply
    let treeSitterProcessorProcessJSONFn: FnTreeSitterProcessorProcessJSON
    let treeSitterProcessorLastUpdateModeJSONFn: FnTreeSitterProcessorLastUpdateModeJSON

    public init(path: String? = nil) throws {
        let candidates = Self.candidateLibraryPaths(explicitPath: path)
        var openedHandle: UnsafeMutableRawPointer?
        var resolvedPath = ""
        var errors: [String] = []

        for candidate in candidates {
            let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL)
            if let loaded {
                openedHandle = loaded
                resolvedPath = candidate
                break
            }
            if let err = dlerror() {
                errors.append("\(candidate): \(String(cString: err))")
            } else {
                errors.append("\(candidate): failed to load")
            }
        }

        guard let handle = openedHandle else {
            let message = errors.joined(separator: "\n")
            throw EditorCommandError(
                "Failed to load editor-core-ffi dynamic library.\nTried:\n\(message)"
            )
        }

        self.handle = handle
        self.resolvedLibraryPath = resolvedPath

        abiVersionFn = try Self.loadSymbol("editor_core_ffi_abi_version", from: handle)
        lastErrorMessageFn = try Self.loadSymbol("editor_core_ffi_last_error_message", from: handle)
        stringFreeFn = try Self.loadSymbol("editor_core_ffi_string_free", from: handle)

        editorStateNewFn = try Self.loadSymbol("editor_core_ffi_editor_state_new", from: handle)
        editorStateFreeFn = try Self.loadSymbol("editor_core_ffi_editor_state_free", from: handle)
        editorStateExecuteJSONFn = try Self.loadSymbol("editor_core_ffi_editor_state_execute_json", from: handle)
        editorStateApplyProcessingEditsJSONFn = try Self.loadSymbol(
            "editor_core_ffi_editor_state_apply_processing_edits_json",
            from: handle
        )
        editorStateFullStateJSONFn = try Self.loadSymbol(
            "editor_core_ffi_editor_state_full_state_json",
            from: handle
        )
        editorStateTextJSONFn = try Self.loadSymbol("editor_core_ffi_editor_state_text", from: handle)
        editorStateMinimapJSONFn = try Self.loadSymbol(
            "editor_core_ffi_editor_state_minimap_json",
            from: handle
        )
        editorStateViewportComposedJSONFn = try Self.loadSymbol(
            "editor_core_ffi_editor_state_viewport_composed_json",
            from: handle
        )

        editorInsertTextUTF8Fn = try Self.loadSymbol("editor_core_ffi_editor_insert_text_utf8", from: handle)
        editorBackspaceFn = try Self.loadSymbol("editor_core_ffi_editor_backspace", from: handle)
        editorDeleteForwardFn = try Self.loadSymbol("editor_core_ffi_editor_delete_forward", from: handle)
        editorUndoFn = try Self.loadSymbol("editor_core_ffi_editor_undo", from: handle)
        editorRedoFn = try Self.loadSymbol("editor_core_ffi_editor_redo", from: handle)
        editorMoveToFn = try Self.loadSymbol("editor_core_ffi_editor_move_to", from: handle)
        editorMoveByFn = try Self.loadSymbol("editor_core_ffi_editor_move_by", from: handle)
        editorSetSelectionFn = try Self.loadSymbol("editor_core_ffi_editor_set_selection", from: handle)
        editorClearSelectionFn = try Self.loadSymbol("editor_core_ffi_editor_clear_selection", from: handle)
        editorViewportBlobFn = try Self.loadSymbol("editor_core_ffi_editor_get_viewport_blob", from: handle)

        lspPathToFileURIFn = try Self.loadSymbol("editor_core_ffi_lsp_path_to_file_uri", from: handle)
        lspFileURIToPathFn = try Self.loadSymbol("editor_core_ffi_lsp_file_uri_to_path", from: handle)
        lspPercentEncodePathFn = try Self.loadSymbol("editor_core_ffi_lsp_percent_encode_path", from: handle)
        lspPercentDecodePathFn = try Self.loadSymbol("editor_core_ffi_lsp_percent_decode_path", from: handle)
        lspCharOffsetToUTF16Fn = try Self.loadSymbol("editor_core_ffi_lsp_char_offset_to_utf16", from: handle)
        lspUTF16ToCharOffsetFn = try Self.loadSymbol("editor_core_ffi_lsp_utf16_to_char_offset", from: handle)
        lspDiagnosticsToProcessingEditsJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_diagnostics_to_processing_edits_json",
            from: handle
        )
        lspDocumentHighlightsToProcessingEditJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_document_highlights_to_processing_edit_json",
            from: handle
        )
        lspInlayHintsToProcessingEditJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_inlay_hints_to_processing_edit_json",
            from: handle
        )
        lspDocumentLinksToProcessingEditJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_document_links_to_processing_edit_json",
            from: handle
        )
        lspCodeLensToProcessingEditJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_code_lens_to_processing_edit_json",
            from: handle
        )
        lspDocumentSymbolsToProcessingEditJSONFn = try Self.loadSymbol(
            "editor_core_ffi_lsp_document_symbols_to_processing_edit_json",
            from: handle
        )

        sublimeProcessorNewFromYAMLFn = try Self.loadSymbol(
            "editor_core_ffi_sublime_processor_new_from_yaml",
            from: handle
        )
        sublimeProcessorNewFromPathFn = try Self.loadSymbol(
            "editor_core_ffi_sublime_processor_new_from_path",
            from: handle
        )
        sublimeProcessorFreeFn = try Self.loadSymbol("editor_core_ffi_sublime_processor_free", from: handle)
        sublimeProcessorApplyFn = try Self.loadSymbol("editor_core_ffi_sublime_processor_apply", from: handle)
        sublimeProcessorProcessJSONFn = try Self.loadSymbol(
            "editor_core_ffi_sublime_processor_process_json",
            from: handle
        )
        sublimeScopeForStyleIDFn = try Self.loadSymbol(
            "editor_core_ffi_sublime_processor_scope_for_style_id",
            from: handle
        )
        sublimeSetActiveSyntaxByReferenceFn = try Self.loadSymbol(
            "editor_core_ffi_sublime_processor_set_active_syntax_by_reference",
            from: handle
        )

        treeSitterProcessorNewFn = try Self.loadSymbol("editor_core_ffi_treesitter_processor_new", from: handle)
        treeSitterProcessorFreeFn = try Self.loadSymbol("editor_core_ffi_treesitter_processor_free", from: handle)
        treeSitterProcessorApplyFn = try Self.loadSymbol("editor_core_ffi_treesitter_processor_apply", from: handle)
        treeSitterProcessorProcessJSONFn = try Self.loadSymbol(
            "editor_core_ffi_treesitter_processor_process_json",
            from: handle
        )
        treeSitterProcessorLastUpdateModeJSONFn = try Self.loadSymbol(
            "editor_core_ffi_treesitter_processor_last_update_mode_json",
            from: handle
        )
    }

    deinit {
        dlclose(handle)
    }

    public var abiVersion: UInt32 {
        abiVersionFn()
    }

    func lastErrorMessage() -> String {
        guard let ptr = lastErrorMessageFn() else {
            return ""
        }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    func takeOwnedCString(_ ptr: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let ptr else {
            let message = lastErrorMessage()
            let fallback = message.isEmpty ? "FFI call returned null C string" : message
            throw EditorCommandError(fallback)
        }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw EditorCommandError("Missing FFI symbol: \(name)")
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func candidateLibraryPaths(explicitPath: String?) -> [String] {
        if let explicitPath, !explicitPath.isEmpty {
            return [explicitPath]
        }

        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let envPath = env["EDITOR_CORE_FFI_DYLIB_PATH"], !envPath.isEmpty {
            candidates.append(envPath)
        }
        if let root = env["EDITOR_CORE_REPO_ROOT"], !root.isEmpty {
            candidates.append((root as NSString).appendingPathComponent("target/debug/\(libraryFileName())"))
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append((cwd as NSString).appendingPathComponent("../target/debug/\(libraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("target/debug/\(libraryFileName())"))
        candidates.append(libraryFileName())
        return candidates
    }

    private static func libraryFileName() -> String {
        #if os(macOS)
        return "libeditor_core_ffi.dylib"
        #elseif os(Linux)
        return "libeditor_core_ffi.so"
        #elseif os(Windows)
        return "editor_core_ffi.dll"
        #else
        return "libeditor_core_ffi.dylib"
        #endif
    }
}
