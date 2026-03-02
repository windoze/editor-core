import Foundation

public final class EditorCoreFFILibrary {
    typealias FnAbiVersion = @convention(c) () -> UInt32
    typealias FnVersion = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias FnLastErrorMessage = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias FnStringFree = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    typealias FnEditorStateNew = @convention(c) (UnsafePointer<CChar>?, UInt) -> OpaquePointer?
    typealias FnEditorStateFree = @convention(c) (OpaquePointer?) -> Void
    typealias FnEditorStateExecuteJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateApplyProcessingEditsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnEditorStateFullStateJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateText = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateTextForSaving = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateDocumentSymbolsJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateDiagnosticsJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateDecorationsJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateSetLineEnding = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnEditorStateGetLineEnding = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateViewportStyledJSON = @convention(c) (OpaquePointer?, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateMinimapJSON = @convention(c) (OpaquePointer?, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateViewportComposedJSON = @convention(c) (OpaquePointer?, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateTakeLastTextDeltaJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorStateLastTextDeltaJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnEditorGetDocumentStats = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    typealias FnEditorInsertTextUTF8 = @convention(c) (OpaquePointer?, UnsafePointer<UInt8>?, UInt32) -> Int32
    typealias FnEditorBackspace = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorDeleteForward = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUndo = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorRedo = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorMoveTo = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
    typealias FnEditorMoveBy = @convention(c) (OpaquePointer?, Int32, Int32) -> Int32
    typealias FnEditorSetSelection = @convention(c) (OpaquePointer?, UInt32, UInt32, UInt32, UInt32, UInt8) -> Int32
    typealias FnEditorClearSelection = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorGetViewportBlob = @convention(c) (
        OpaquePointer?,
        UInt32,
        UInt32,
        UnsafeMutablePointer<UInt8>?,
        UInt32,
        UnsafeMutablePointer<UInt32>?
    ) -> Int32

    typealias FnWorkspaceNew = @convention(c) () -> OpaquePointer?
    typealias FnWorkspaceFree = @convention(c) (OpaquePointer?) -> Void
    typealias FnWorkspaceOpenBuffer = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceCloseBuffer = @convention(c) (OpaquePointer?, UInt64) -> Bool
    typealias FnWorkspaceCloseView = @convention(c) (OpaquePointer?, UInt64) -> Bool
    typealias FnWorkspaceCreateView = @convention(c) (OpaquePointer?, UInt64, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceSetActiveView = @convention(c) (OpaquePointer?, UInt64) -> Bool
    typealias FnWorkspaceInfoJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceExecuteJSON = @convention(c) (
        OpaquePointer?,
        UInt64,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceApplyProcessingEditsJSON = @convention(c) (OpaquePointer?, UInt64, UnsafePointer<CChar>?) -> Bool
    typealias FnWorkspaceBufferTextJSON = @convention(c) (OpaquePointer?, UInt64) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceViewportStateJSON = @convention(c) (OpaquePointer?, UInt64) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceSetViewportHeight = @convention(c) (OpaquePointer?, UInt64, UInt) -> Bool
    typealias FnWorkspaceSetSmoothScrollState = @convention(c) (OpaquePointer?, UInt64, UInt, UInt16, UInt) -> Bool
    typealias FnWorkspaceViewportStyledJSON = @convention(c) (OpaquePointer?, UInt64, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceMinimapJSON = @convention(c) (OpaquePointer?, UInt64, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceViewportComposedJSON = @convention(c) (OpaquePointer?, UInt64, UInt, UInt) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceSearchAllOpenBuffersJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceApplyTextEditsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnWorkspaceInsertTextUTF8 = @convention(c) (
        OpaquePointer?,
        UInt64,
        UnsafePointer<UInt8>?,
        UInt32
    ) -> Int32
    typealias FnWorkspaceMoveTo = @convention(c) (OpaquePointer?, UInt64, UInt32, UInt32) -> Int32
    typealias FnWorkspaceBackspace = @convention(c) (OpaquePointer?, UInt64) -> Int32
    typealias FnWorkspaceGetViewportBlob = @convention(c) (
        OpaquePointer?,
        UInt64,
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
    typealias FnLspCharOffsetToUTF16 = @convention(c) (UnsafePointer<CChar>?, UInt) -> UInt
    typealias FnLspUTF16ToCharOffset = @convention(c) (UnsafePointer<CChar>?, UInt) -> UInt
    typealias FnLspApplyTextEditsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspSemanticTokensToIntervalsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDecodeSemanticStyleID = @convention(c) (UInt32) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentHighlightsToProcessingEditJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspInlayHintsToProcessingEditJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentLinksToProcessingEditJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspCodeLensToProcessingEditJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDocumentSymbolsToProcessingEditJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspDiagnosticsToProcessingEditsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspWorkspaceSymbolsJSON = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspLocationsJSON = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FnLspCompletionItemToTextEditsJSON = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt,
        UInt,
        Bool
    ) -> UnsafeMutablePointer<CChar>?
    typealias FnLspApplyCompletionItemJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
    typealias FnLspEncodeSemanticStyleID = @convention(c) (UInt32, UInt32) -> UInt32

    typealias FnSublimeProcessorNewFromYAML = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    typealias FnSublimeProcessorNewFromPath = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    typealias FnSublimeProcessorFree = @convention(c) (OpaquePointer?) -> Void
    typealias FnSublimeProcessorAddSearchPath = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnSublimeProcessorLoadSyntaxFromYAML = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnSublimeProcessorLoadSyntaxFromPath = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnSublimeProcessorSetActiveSyntaxByReference = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Bool
    typealias FnSublimeProcessorSetPreserveCollapsedFolds = @convention(c) (OpaquePointer?, Bool) -> Bool
    typealias FnSublimeProcessorProcessJSON = @convention(c) (OpaquePointer?, OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnSublimeProcessorApply = @convention(c) (OpaquePointer?, OpaquePointer?) -> Bool
    typealias FnSublimeProcessorScopeForStyleID = @convention(c) (OpaquePointer?, UInt32) -> UnsafeMutablePointer<CChar>?

    public typealias FnTreeSitterLanguageFn = @convention(c) () -> UnsafeRawPointer?
    typealias FnTreeSitterProcessorNew = @convention(c) (
        FnTreeSitterLanguageFn?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt32,
        Bool
    ) -> OpaquePointer?
    typealias FnTreeSitterProcessorFree = @convention(c) (OpaquePointer?) -> Void
    typealias FnTreeSitterProcessorProcessJSON = @convention(c) (OpaquePointer?, OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias FnTreeSitterProcessorApply = @convention(c) (OpaquePointer?, OpaquePointer?) -> Bool
    typealias FnTreeSitterProcessorLastUpdateModeJSON = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    private let dylib: DynamicLibrary
    public let resolvedLibraryPath: String

    private let abiVersionFn: FnAbiVersion
    private let versionFn: FnVersion
    private let lastErrorMessageFn: FnLastErrorMessage
    private let stringFreeFn: FnStringFree

    let editorStateNewFn: FnEditorStateNew
    let editorStateFreeFn: FnEditorStateFree
    let editorStateExecuteJSONFn: FnEditorStateExecuteJSON
    let editorStateApplyProcessingEditsJSONFn: FnEditorStateApplyProcessingEditsJSON
    let editorStateFullStateJSONFn: FnEditorStateFullStateJSON
    let editorStateTextFn: FnEditorStateText
    let editorStateTextForSavingFn: FnEditorStateTextForSaving
    let editorStateDocumentSymbolsJSONFn: FnEditorStateDocumentSymbolsJSON
    let editorStateDiagnosticsJSONFn: FnEditorStateDiagnosticsJSON
    let editorStateDecorationsJSONFn: FnEditorStateDecorationsJSON
    let editorStateSetLineEndingFn: FnEditorStateSetLineEnding
    let editorStateGetLineEndingFn: FnEditorStateGetLineEnding
    let editorStateViewportStyledJSONFn: FnEditorStateViewportStyledJSON
    let editorStateMinimapJSONFn: FnEditorStateMinimapJSON
    let editorStateViewportComposedJSONFn: FnEditorStateViewportComposedJSON
    let editorStateTakeLastTextDeltaJSONFn: FnEditorStateTakeLastTextDeltaJSON
    let editorStateLastTextDeltaJSONFn: FnEditorStateLastTextDeltaJSON
    let editorGetDocumentStatsFn: FnEditorGetDocumentStats
    let editorInsertTextUTF8Fn: FnEditorInsertTextUTF8
    let editorBackspaceFn: FnEditorBackspace
    let editorDeleteForwardFn: FnEditorDeleteForward
    let editorUndoFn: FnEditorUndo
    let editorRedoFn: FnEditorRedo
    let editorMoveToFn: FnEditorMoveTo
    let editorMoveByFn: FnEditorMoveBy
    let editorSetSelectionFn: FnEditorSetSelection
    let editorClearSelectionFn: FnEditorClearSelection
    let editorGetViewportBlobFn: FnEditorGetViewportBlob

    let workspaceNewFn: FnWorkspaceNew
    let workspaceFreeFn: FnWorkspaceFree
    let workspaceOpenBufferFn: FnWorkspaceOpenBuffer
    let workspaceCloseBufferFn: FnWorkspaceCloseBuffer
    let workspaceCloseViewFn: FnWorkspaceCloseView
    let workspaceCreateViewFn: FnWorkspaceCreateView
    let workspaceSetActiveViewFn: FnWorkspaceSetActiveView
    let workspaceInfoJSONFn: FnWorkspaceInfoJSON
    let workspaceExecuteJSONFn: FnWorkspaceExecuteJSON
    let workspaceApplyProcessingEditsJSONFn: FnWorkspaceApplyProcessingEditsJSON
    let workspaceBufferTextJSONFn: FnWorkspaceBufferTextJSON
    let workspaceViewportStateJSONFn: FnWorkspaceViewportStateJSON
    let workspaceSetViewportHeightFn: FnWorkspaceSetViewportHeight
    let workspaceSetSmoothScrollStateFn: FnWorkspaceSetSmoothScrollState
    let workspaceViewportStyledJSONFn: FnWorkspaceViewportStyledJSON
    let workspaceMinimapJSONFn: FnWorkspaceMinimapJSON
    let workspaceViewportComposedJSONFn: FnWorkspaceViewportComposedJSON
    let workspaceSearchAllOpenBuffersJSONFn: FnWorkspaceSearchAllOpenBuffersJSON
    let workspaceApplyTextEditsJSONFn: FnWorkspaceApplyTextEditsJSON
    let workspaceInsertTextUTF8Fn: FnWorkspaceInsertTextUTF8
    let workspaceMoveToFn: FnWorkspaceMoveTo
    let workspaceBackspaceFn: FnWorkspaceBackspace
    let workspaceGetViewportBlobFn: FnWorkspaceGetViewportBlob

    let lspPathToFileURIFn: FnLspPathToFileURI
    let lspFileURIToPathFn: FnLspFileURIToPath
    let lspPercentEncodePathFn: FnLspPercentEncodePath
    let lspPercentDecodePathFn: FnLspPercentDecodePath
    let lspCharOffsetToUTF16Fn: FnLspCharOffsetToUTF16
    let lspUTF16ToCharOffsetFn: FnLspUTF16ToCharOffset
    let lspApplyTextEditsJSONFn: FnLspApplyTextEditsJSON
    let lspSemanticTokensToIntervalsJSONFn: FnLspSemanticTokensToIntervalsJSON
    let lspDecodeSemanticStyleIDFn: FnLspDecodeSemanticStyleID
    let lspDocumentHighlightsToProcessingEditJSONFn: FnLspDocumentHighlightsToProcessingEditJSON
    let lspInlayHintsToProcessingEditJSONFn: FnLspInlayHintsToProcessingEditJSON
    let lspDocumentLinksToProcessingEditJSONFn: FnLspDocumentLinksToProcessingEditJSON
    let lspCodeLensToProcessingEditJSONFn: FnLspCodeLensToProcessingEditJSON
    let lspDocumentSymbolsToProcessingEditJSONFn: FnLspDocumentSymbolsToProcessingEditJSON
    let lspDiagnosticsToProcessingEditsJSONFn: FnLspDiagnosticsToProcessingEditsJSON
    let lspWorkspaceSymbolsJSONFn: FnLspWorkspaceSymbolsJSON
    let lspLocationsJSONFn: FnLspLocationsJSON
    let lspCompletionItemToTextEditsJSONFn: FnLspCompletionItemToTextEditsJSON
    let lspApplyCompletionItemJSONFn: FnLspApplyCompletionItemJSON
    let lspEncodeSemanticStyleIDFn: FnLspEncodeSemanticStyleID

    let sublimeProcessorNewFromYAMLFn: FnSublimeProcessorNewFromYAML
    let sublimeProcessorNewFromPathFn: FnSublimeProcessorNewFromPath
    let sublimeProcessorFreeFn: FnSublimeProcessorFree
    let sublimeProcessorAddSearchPathFn: FnSublimeProcessorAddSearchPath
    let sublimeProcessorLoadSyntaxFromYAMLFn: FnSublimeProcessorLoadSyntaxFromYAML
    let sublimeProcessorLoadSyntaxFromPathFn: FnSublimeProcessorLoadSyntaxFromPath
    let sublimeProcessorSetActiveSyntaxByReferenceFn: FnSublimeProcessorSetActiveSyntaxByReference
    let sublimeProcessorSetPreserveCollapsedFoldsFn: FnSublimeProcessorSetPreserveCollapsedFolds
    let sublimeProcessorProcessJSONFn: FnSublimeProcessorProcessJSON
    let sublimeProcessorApplyFn: FnSublimeProcessorApply
    let sublimeProcessorScopeForStyleIDFn: FnSublimeProcessorScopeForStyleID

    let treeSitterRustLanguageFn: FnTreeSitterLanguageFn
    let treeSitterProcessorNewFn: FnTreeSitterProcessorNew
    let treeSitterProcessorFreeFn: FnTreeSitterProcessorFree
    let treeSitterProcessorProcessJSONFn: FnTreeSitterProcessorProcessJSON
    let treeSitterProcessorApplyFn: FnTreeSitterProcessorApply
    let treeSitterProcessorLastUpdateModeJSONFn: FnTreeSitterProcessorLastUpdateModeJSON

    public init(path: String? = nil) throws {
        let candidates = Self.candidateLibraryPaths(explicitPath: path)
        var opened: DynamicLibrary?
        var resolvedPath: String = ""
        var errors: [String] = []

        for candidate in candidates {
            do {
                opened = try DynamicLibrary(path: candidate)
                resolvedPath = candidate
                break
            } catch {
                errors.append("\(candidate): \(error)")
            }
        }

        guard let dylib = opened else {
            throw EditorCoreFFIError.failedToLoadLibrary(tried: candidates, errors: errors)
        }

        self.dylib = dylib
        self.resolvedLibraryPath = resolvedPath

        abiVersionFn = try dylib.loadSymbol("editor_core_ffi_abi_version")
        versionFn = try dylib.loadSymbol("editor_core_ffi_version")
        lastErrorMessageFn = try dylib.loadSymbol("editor_core_ffi_last_error_message")
        stringFreeFn = try dylib.loadSymbol("editor_core_ffi_string_free")

        editorStateNewFn = try dylib.loadSymbol("editor_core_ffi_editor_state_new")
        editorStateFreeFn = try dylib.loadSymbol("editor_core_ffi_editor_state_free")
        editorStateExecuteJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_execute_json")
        editorStateApplyProcessingEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_apply_processing_edits_json")
        editorStateFullStateJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_full_state_json")
        editorStateTextFn = try dylib.loadSymbol("editor_core_ffi_editor_state_text")
        editorStateTextForSavingFn = try dylib.loadSymbol("editor_core_ffi_editor_state_text_for_saving")
        editorStateDocumentSymbolsJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_document_symbols_json")
        editorStateDiagnosticsJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_diagnostics_json")
        editorStateDecorationsJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_decorations_json")
        editorStateSetLineEndingFn = try dylib.loadSymbol("editor_core_ffi_editor_state_set_line_ending")
        editorStateGetLineEndingFn = try dylib.loadSymbol("editor_core_ffi_editor_state_get_line_ending")
        editorStateViewportStyledJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_viewport_styled_json")
        editorStateMinimapJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_minimap_json")
        editorStateViewportComposedJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_viewport_composed_json")
        editorStateTakeLastTextDeltaJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_take_last_text_delta_json")
        editorStateLastTextDeltaJSONFn = try dylib.loadSymbol("editor_core_ffi_editor_state_last_text_delta_json")
        editorGetDocumentStatsFn = try dylib.loadSymbol("editor_core_ffi_editor_get_document_stats")
        editorInsertTextUTF8Fn = try dylib.loadSymbol("editor_core_ffi_editor_insert_text_utf8")
        editorBackspaceFn = try dylib.loadSymbol("editor_core_ffi_editor_backspace")
        editorDeleteForwardFn = try dylib.loadSymbol("editor_core_ffi_editor_delete_forward")
        editorUndoFn = try dylib.loadSymbol("editor_core_ffi_editor_undo")
        editorRedoFn = try dylib.loadSymbol("editor_core_ffi_editor_redo")
        editorMoveToFn = try dylib.loadSymbol("editor_core_ffi_editor_move_to")
        editorMoveByFn = try dylib.loadSymbol("editor_core_ffi_editor_move_by")
        editorSetSelectionFn = try dylib.loadSymbol("editor_core_ffi_editor_set_selection")
        editorClearSelectionFn = try dylib.loadSymbol("editor_core_ffi_editor_clear_selection")
        editorGetViewportBlobFn = try dylib.loadSymbol("editor_core_ffi_editor_get_viewport_blob")

        workspaceNewFn = try dylib.loadSymbol("editor_core_ffi_workspace_new")
        workspaceFreeFn = try dylib.loadSymbol("editor_core_ffi_workspace_free")
        workspaceOpenBufferFn = try dylib.loadSymbol("editor_core_ffi_workspace_open_buffer")
        workspaceCloseBufferFn = try dylib.loadSymbol("editor_core_ffi_workspace_close_buffer")
        workspaceCloseViewFn = try dylib.loadSymbol("editor_core_ffi_workspace_close_view")
        workspaceCreateViewFn = try dylib.loadSymbol("editor_core_ffi_workspace_create_view")
        workspaceSetActiveViewFn = try dylib.loadSymbol("editor_core_ffi_workspace_set_active_view")
        workspaceInfoJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_info_json")
        workspaceExecuteJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_execute_json")
        workspaceApplyProcessingEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_apply_processing_edits_json")
        workspaceBufferTextJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_buffer_text_json")
        workspaceViewportStateJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_viewport_state_json")
        workspaceSetViewportHeightFn = try dylib.loadSymbol("editor_core_ffi_workspace_set_viewport_height")
        workspaceSetSmoothScrollStateFn = try dylib.loadSymbol("editor_core_ffi_workspace_set_smooth_scroll_state")
        workspaceViewportStyledJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_viewport_styled_json")
        workspaceMinimapJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_minimap_json")
        workspaceViewportComposedJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_viewport_composed_json")
        workspaceSearchAllOpenBuffersJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_search_all_open_buffers_json")
        workspaceApplyTextEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_workspace_apply_text_edits_json")
        workspaceInsertTextUTF8Fn = try dylib.loadSymbol("editor_core_ffi_workspace_insert_text_utf8")
        workspaceMoveToFn = try dylib.loadSymbol("editor_core_ffi_workspace_move_to")
        workspaceBackspaceFn = try dylib.loadSymbol("editor_core_ffi_workspace_backspace")
        workspaceGetViewportBlobFn = try dylib.loadSymbol("editor_core_ffi_workspace_get_viewport_blob")

        lspPathToFileURIFn = try dylib.loadSymbol("editor_core_ffi_lsp_path_to_file_uri")
        lspFileURIToPathFn = try dylib.loadSymbol("editor_core_ffi_lsp_file_uri_to_path")
        lspPercentEncodePathFn = try dylib.loadSymbol("editor_core_ffi_lsp_percent_encode_path")
        lspPercentDecodePathFn = try dylib.loadSymbol("editor_core_ffi_lsp_percent_decode_path")
        lspCharOffsetToUTF16Fn = try dylib.loadSymbol("editor_core_ffi_lsp_char_offset_to_utf16")
        lspUTF16ToCharOffsetFn = try dylib.loadSymbol("editor_core_ffi_lsp_utf16_to_char_offset")
        lspApplyTextEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_apply_text_edits_json")
        lspSemanticTokensToIntervalsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_semantic_tokens_to_intervals_json")
        lspDecodeSemanticStyleIDFn = try dylib.loadSymbol("editor_core_ffi_lsp_decode_semantic_style_id")
        lspDocumentHighlightsToProcessingEditJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_document_highlights_to_processing_edit_json")
        lspInlayHintsToProcessingEditJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_inlay_hints_to_processing_edit_json")
        lspDocumentLinksToProcessingEditJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_document_links_to_processing_edit_json")
        lspCodeLensToProcessingEditJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_code_lens_to_processing_edit_json")
        lspDocumentSymbolsToProcessingEditJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_document_symbols_to_processing_edit_json")
        lspDiagnosticsToProcessingEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_diagnostics_to_processing_edits_json")
        lspWorkspaceSymbolsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_workspace_symbols_json")
        lspLocationsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_locations_json")
        lspCompletionItemToTextEditsJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_completion_item_to_text_edits_json")
        lspApplyCompletionItemJSONFn = try dylib.loadSymbol("editor_core_ffi_lsp_apply_completion_item_json")
        lspEncodeSemanticStyleIDFn = try dylib.loadSymbol("editor_core_ffi_lsp_encode_semantic_style_id")

        sublimeProcessorNewFromYAMLFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_new_from_yaml")
        sublimeProcessorNewFromPathFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_new_from_path")
        sublimeProcessorFreeFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_free")
        sublimeProcessorAddSearchPathFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_add_search_path")
        sublimeProcessorLoadSyntaxFromYAMLFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_load_syntax_from_yaml")
        sublimeProcessorLoadSyntaxFromPathFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_load_syntax_from_path")
        sublimeProcessorSetActiveSyntaxByReferenceFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_set_active_syntax_by_reference")
        sublimeProcessorSetPreserveCollapsedFoldsFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_set_preserve_collapsed_folds")
        sublimeProcessorProcessJSONFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_process_json")
        sublimeProcessorApplyFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_apply")
        sublimeProcessorScopeForStyleIDFn = try dylib.loadSymbol("editor_core_ffi_sublime_processor_scope_for_style_id")

        treeSitterRustLanguageFn = try dylib.loadSymbol("editor_core_ffi_treesitter_language_rust")
        treeSitterProcessorNewFn = try dylib.loadSymbol("editor_core_ffi_treesitter_processor_new")
        treeSitterProcessorFreeFn = try dylib.loadSymbol("editor_core_ffi_treesitter_processor_free")
        treeSitterProcessorProcessJSONFn = try dylib.loadSymbol("editor_core_ffi_treesitter_processor_process_json")
        treeSitterProcessorApplyFn = try dylib.loadSymbol("editor_core_ffi_treesitter_processor_apply")
        treeSitterProcessorLastUpdateModeJSONFn = try dylib.loadSymbol("editor_core_ffi_treesitter_processor_last_update_mode_json")
    }

    public var abiVersion: UInt32 {
        abiVersionFn()
    }

    public func versionString() throws -> String {
        try takeOwnedCString(versionFn(), context: "version")
    }

    func lastErrorMessage() -> String {
        guard let ptr = lastErrorMessageFn() else {
            return ""
        }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    /// 获取最近一次 FFI 调用失败时的错误消息（线程局部）。
    ///
    /// - 注意：成功调用通常会清空错误消息；不同 API 的时机略有差异。
    public func lastErrorMessageString() -> String {
        lastErrorMessage()
    }

    func takeOwnedCString(_ ptr: UnsafeMutablePointer<CChar>?, context: String) throws -> String {
        guard let ptr else {
            let message = lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: context, message: message.isEmpty ? "no last_error_message" : message)
        }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    func ensureStatus(_ status: Int32, context: String) throws {
        guard let code = EcfStatus(rawValue: status) else {
            let message = lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: context, message: "unknown status \(status); last_error=\(message)")
        }
        guard code == .ok else {
            let message = lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: code, context: context, message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    static func defaultLibraryFileName() -> String {
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
            candidates.append((root as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
            candidates.append((root as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        }

        if let repoRoot = locateRepoRoot() {
            candidates.append((repoRoot as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
            candidates.append((repoRoot as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append((cwd as NSString).appendingPathComponent("../target/debug/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("../target/release/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        candidates.append(defaultLibraryFileName())
        return candidates
    }

    private static func locateRepoRoot() -> String? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<10 {
            let probe = current.appendingPathComponent("crates/editor-core-ffi/Cargo.toml").path
            if FileManager.default.fileExists(atPath: probe) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }
}
