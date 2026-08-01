import CEditorCoreUIFFI
import Foundation
import Metal

public final class EditorUI {
    public let library: EditorCoreUIFFILibrary
    private let handle: OpaquePointer

    public enum TextVerticalAlign: UInt8 {
        case top = 0
        case center = 1
        case bottom = 2
    }

    public enum TabKeyBehavior: UInt8 {
        case tab = 0
        case spaces = 1
    }

    public enum WhitespaceRenderMode: UInt8 {
        case none = 0
        case selection = 1
        case all = 2
    }

    public enum FoldMarkerStyle: UInt8 {
        case hidden = 0
        case block = 1
        case triangle = 2
    }

    private init(library: EditorCoreUIFFILibrary, handle: OpaquePointer) {
        self.library = library
        self.handle = handle
    }

    public init(library: EditorCoreUIFFILibrary, initialText: String = "", viewportWidthCells: UInt32 = 120) throws {
        self.library = library
        guard let ptr = initialText.withCString({ cstr in
            editor_core_ui_ffi_editor_ui_new(cstr, viewportWidthCells)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_new", message: library.lastErrorMessageString())
        }
        self.handle = ptr
    }

    deinit {
        editor_core_ui_ffi_editor_ui_free(handle)
    }

    public func cloneView(viewportWidthCells: UInt32) throws -> EditorUI {
        guard let ptr = editor_core_ui_ffi_editor_ui_clone_view(handle, viewportWidthCells) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_clone_view", message: library.lastErrorMessageString())
        }
        return EditorUI(library: library, handle: ptr)
    }

    public func setTheme(_ theme: EcuTheme) throws {
        var ffiTheme = theme.ffi
        let status = withUnsafePointer(to: &ffiTheme) { ptr in
            editor_core_ui_ffi_editor_ui_set_theme(handle, ptr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_theme")
    }

    public func setChromeTheme(_ theme: EcuChromeTheme) throws {
        var ffiTheme = theme.ffi
        let status = withUnsafePointer(to: &ffiTheme) { ptr in
            editor_core_ui_ffi_editor_ui_set_chrome_theme(handle, ptr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_chrome_theme")
    }

    public func setStyleColors(_ styles: [EcuStyleColors]) throws {
        let ffi = styles.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_style_colors(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_style_colors")
    }

    public func setStyleFonts(_ fonts: [EcuStyleFont]) throws {
        let ffi = fonts.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_style_fonts(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_style_fonts")
    }

    public func setStyleTextDecorations(_ decorations: [EcuStyleTextDecorations]) throws {
        let ffi = decorations.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_style_text_decorations(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_style_text_decorations")
    }

    public func sublimeSetSyntaxYAML(_ yaml: String) throws {
        let status = yaml.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_yaml")
    }

    public func sublimeSetSyntaxPath(_ path: String) throws {
        let status = path.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_set_syntax_path(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_path")
    }

    public func sublimeDisable() {
        editor_core_ui_ffi_editor_ui_sublime_disable(handle)
    }

    public func sublimeStyleId(forScope scope: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = scope.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_style_id_for_scope")
        return out
    }

    public func sublimeScope(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_sublime_scope_for_style_id", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func treeSitterSetRegistryJSON(_ registryJSON: String) throws {
        let status = registryJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_set_registry_json")
    }

    public func treeSitterEnableLanguage(_ languageId: String) throws {
        let status: Int32 = languageId.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_enable_language(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_enable_language")
    }

    public func treeSitterEnableForPath(_ path: String) throws {
        let status: Int32 = path.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_enable_for_path(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_enable_for_path")
    }

    public func treeSitterRustEnableDefault() throws {
        let status = editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(handle)
        try library.ensureStatus(status, context: "editor_ui_treesitter_rust_enable_default")
    }

    /// Backwards-compatible alias: treat `packId` as Tree-sitter `languageId`.
    public func treeSitterEnableQueryPack(_ packId: String) throws {
        let status: Int32 = packId.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_enable_query_pack(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_enable_query_pack")
    }

    public func treeSitterDisable() {
        editor_core_ui_ffi_editor_ui_treesitter_disable(handle)
    }

    /// Enable an stdio LSP session managed by Rust.
    ///
    /// Notes:
    /// - `rootURI` / `documentURI` should be `file:///...` URIs for best server behavior.
    /// - `args` is a single whitespace-separated string (best-effort; no shell quoting).
    public func lspEnable(command: String, args: String? = nil, rootURI: String, documentURI: String, languageId: String) throws {
        let status: Int32 = command.withCString { cmdCStr in
            rootURI.withCString { rootCStr in
                documentURI.withCString { docCStr in
                    languageId.withCString { langCStr in
                        if let args {
                            return args.withCString { argsCStr in
                                editor_core_ui_ffi_editor_ui_lsp_enable(handle, cmdCStr, argsCStr, rootCStr, docCStr, langCStr)
                            }
                        }
                        return editor_core_ui_ffi_editor_ui_lsp_enable(handle, cmdCStr, nil, rootCStr, docCStr, langCStr)
                    }
                }
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_enable")
    }

    public func lspDisable() {
        editor_core_ui_ffi_editor_ui_lsp_disable(handle)
    }

    public func lspIsEnabled() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_is_enabled(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_is_enabled")
        return out != 0
    }

    /// Get a best-effort LSP status snapshot as JSON.
    ///
    /// This is intended for status bars and debugging overlays.
    public func lspStatusJSON() throws -> String {
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_status_json(handle, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_status_json")
        guard let ptr else {
            return "{}"
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Request an LSP hover (`textDocument/hover`) for a logical position.
    ///
    /// Notes:
    /// - `logicalLine` / `logicalColumn` are 0-based and counted in Unicode scalars.
    /// - This request is non-blocking; the result is delivered via internal LSP polling.
    public func lspRequestHover(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_hover(handle, logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_hover")
        return out
    }

    /// Take the last LSP hover `result` payload as JSON (`Hover | null`).
    ///
    /// Returns `nil` when there is no new hover result.
    public func lspTakeLastHoverResultJSON() throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(handle, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_take_last_hover_json")
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Request LSP go-to-definition (`textDocument/definition`) for a logical position.
    ///
    /// Notes:
    /// - `logicalLine` / `logicalColumn` are 0-based and counted in Unicode scalars.
    /// - This request is non-blocking; the result is delivered via internal LSP polling.
    public func lspRequestDefinition(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_definition(handle, logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_definition")
        return out
    }

    /// Take the last LSP definition `result` payload as JSON (`Definition | null`).
    ///
    /// Returns `nil` when there is no new definition result.
    public func lspTakeLastDefinitionResultJSON() throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(handle, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_take_last_definition_json")
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    private func lspRequestPosition(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        context: String,
        _ request: (UInt32, UInt32, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = request(logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: context)
        return out
    }

    private func lspTakeLastResultJSON(
        context: String,
        _ take: (UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    ) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = take(&has, &ptr)
        try library.ensureStatus(status, context: context)
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    private func lspRequestJSON(
        _ json: String,
        context: String,
        _ request: (UnsafePointer<CChar>, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = json.withCString { cstr in
            request(cstr, &out)
        }
        try library.ensureStatus(status, context: context)
        return out
    }

    public func lspRequestDeclaration(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_declaration"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_declaration(handle, line, column, out)
        }
    }

    public func lspTakeLastDeclarationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_declaration_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_declaration_json(handle, has, ptr)
        }
    }

    public func lspRequestTypeDefinition(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_type_definition"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_definition(handle, line, column, out)
        }
    }

    public func lspTakeLastTypeDefinitionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_definition_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_definition_json(handle, has, ptr)
        }
    }

    public func lspRequestImplementation(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_implementation"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_implementation(handle, line, column, out)
        }
    }

    public func lspTakeLastImplementationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_implementation_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_implementation_json(handle, has, ptr)
        }
    }

    public func lspRequestReferences(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        includeDeclaration: Bool = true
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_references(
            handle,
            logicalLine,
            logicalColumn,
            includeDeclaration ? 1 : 0,
            &out
        )
        try library.ensureStatus(status, context: "editor_ui_lsp_request_references")
        return out
    }

    public func lspTakeLastReferencesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_references_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_references_json(handle, has, ptr)
        }
    }

    public func lspRequestCompletion(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_completion"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_completion(handle, line, column, out)
        }
    }

    public func lspTakeLastCompletionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_completion_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_completion_json(handle, has, ptr)
        }
    }

    public func lspRequestCompletionItemResolve(itemJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = itemJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_completion_item_resolve(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_completion_item_resolve")
        return out
    }

    public func lspTakeLastCompletionItemResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_completion_item_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_completion_item_resolve_json(handle, has, ptr)
        }
    }

    public func lspRequestSignatureHelp(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_signature_help"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_signature_help(handle, line, column, out)
        }
    }

    public func lspTakeLastSignatureHelpResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_signature_help_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_signature_help_json(handle, has, ptr)
        }
    }

    public func lspRequestPrepareRename(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_rename"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_rename(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareRenameResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_rename_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_rename_json(handle, has, ptr)
        }
    }

    public func lspRequestRename(logicalLine: UInt32, logicalColumn: UInt32, newName: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = newName.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_rename(handle, logicalLine, logicalColumn, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_rename")
        return out
    }

    public func lspTakeLastRenameResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_rename_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_rename_json(handle, has, ptr)
        }
    }

    public func lspRequestCodeAction(
        startOffset: UInt32,
        endOffset: UInt32,
        contextJSON: String = #"{"diagnostics":[]}"#
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = contextJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_code_action(handle, startOffset, endOffset, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_action")
        return out
    }

    public func lspTakeLastCodeActionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_action_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_json(handle, has, ptr)
        }
    }

    public func lspRequestCodeActionResolve(actionJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = actionJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_code_action_resolve(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_action_resolve")
        return out
    }

    public func lspTakeLastCodeActionResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_action_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_resolve_json(handle, has, ptr)
        }
    }

    public func lspRequestExecuteCommand(commandJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = commandJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_execute_command(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_execute_command")
        return out
    }

    public func lspTakeLastExecuteCommandResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_execute_command_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(handle, has, ptr)
        }
    }

    public func lspRequestCodeLens() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_code_lens(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_lens")
        return out
    }

    public func lspTakeLastCodeLensResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_lens_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_json(handle, has, ptr)
        }
    }

    public func lspRequestCodeLensResolve(lensJSON: String) throws -> UInt64 {
        try lspRequestJSON(lensJSON, context: "editor_ui_lsp_request_code_lens_resolve") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_code_lens_resolve(handle, cstr, out)
        }
    }

    public func lspTakeLastCodeLensResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_lens_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_resolve_json(handle, has, ptr)
        }
    }

    public func lspRequestDocumentSymbols() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_document_symbols(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_symbols")
        return out
    }

    public func lspTakeLastDocumentSymbolsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_symbols_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_symbols_json(handle, has, ptr)
        }
    }

    public func lspRequestFoldingRanges() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_folding_ranges")
        return out
    }

    public func lspTakeLastFoldingRangesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_folding_ranges_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json(handle, has, ptr)
        }
    }

    public func lspRequestSelectionRange(positionsJSON: String) throws -> UInt64 {
        try lspRequestJSON(positionsJSON, context: "editor_ui_lsp_request_selection_range") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_selection_range(handle, cstr, out)
        }
    }

    public func lspTakeLastSelectionRangeResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_selection_range_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_selection_range_json(handle, has, ptr)
        }
    }

    public func lspRequestLinkedEditingRange(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_linked_editing_range"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_linked_editing_range(handle, line, column, out)
        }
    }

    public func lspTakeLastLinkedEditingRangeResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_linked_editing_range_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_linked_editing_range_json(handle, has, ptr)
        }
    }

    public func lspRequestDocumentDiagnostic(previousResultId: String? = nil) throws -> UInt64 {
        var out: UInt64 = 0
        let status: Int32
        if let previousResultId {
            status = previousResultId.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(handle, cstr, &out)
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(handle, nil, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_diagnostic")
        return out
    }

    public func lspTakeLastDocumentDiagnosticResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_diagnostic_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_diagnostic_json(handle, has, ptr)
        }
    }

    public func lspRequestWorkspaceDiagnostic(previousResultIdsJSON: String = "[]") throws -> UInt64 {
        try lspRequestJSON(previousResultIdsJSON, context: "editor_ui_lsp_request_workspace_diagnostic") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_workspace_diagnostic(handle, cstr, out)
        }
    }

    public func lspTakeLastWorkspaceDiagnosticResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_workspace_diagnostic_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_diagnostic_json(handle, has, ptr)
        }
    }

    public func lspRequestDocumentColor() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_document_color(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_color")
        return out
    }

    public func lspTakeLastDocumentColorResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_color_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_color_json(handle, has, ptr)
        }
    }

    public func lspRequestColorPresentation(
        startOffset: UInt32,
        endOffset: UInt32,
        colorJSON: String
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = colorJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_color_presentation(
                handle,
                startOffset,
                endOffset,
                cstr,
                &out
            )
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_color_presentation")
        return out
    }

    public func lspTakeLastColorPresentationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_color_presentation_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_color_presentation_json(handle, has, ptr)
        }
    }

    public func lspRequestPrepareCallHierarchy(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_call_hierarchy"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_call_hierarchy(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareCallHierarchyResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_call_hierarchy_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_call_hierarchy_json(handle, has, ptr)
        }
    }

    public func lspRequestCallHierarchyIncomingCalls(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_call_hierarchy_incoming_calls") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_incoming_calls(handle, cstr, out)
        }
    }

    public func lspTakeLastCallHierarchyIncomingCallsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json(handle, has, ptr)
        }
    }

    public func lspRequestCallHierarchyOutgoingCalls(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_call_hierarchy_outgoing_calls") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_outgoing_calls(handle, cstr, out)
        }
    }

    public func lspTakeLastCallHierarchyOutgoingCallsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json(handle, has, ptr)
        }
    }

    public func lspRequestPrepareTypeHierarchy(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_type_hierarchy"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_type_hierarchy(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareTypeHierarchyResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_type_hierarchy_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_type_hierarchy_json(handle, has, ptr)
        }
    }

    public func lspRequestTypeHierarchySupertypes(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_type_hierarchy_supertypes") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_supertypes(handle, cstr, out)
        }
    }

    public func lspTakeLastTypeHierarchySupertypesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_hierarchy_supertypes_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_supertypes_json(handle, has, ptr)
        }
    }

    public func lspRequestTypeHierarchySubtypes(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_type_hierarchy_subtypes") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_subtypes(handle, cstr, out)
        }
    }

    public func lspTakeLastTypeHierarchySubtypesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_hierarchy_subtypes_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_subtypes_json(handle, has, ptr)
        }
    }

    public func lspRequestWorkspaceSymbols(query: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_workspace_symbols(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_workspace_symbols")
        return out
    }

    public func lspTakeLastWorkspaceSymbolsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_workspace_symbols_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_symbols_json(handle, has, ptr)
        }
    }

    /// Format the current document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// Notes:
    /// - This is a blocking request intended for explicit user actions (e.g. "Format Document").
    /// - `formattingOptionsJSON` should match LSP `FormattingOptions`.
    @discardableResult
    public func lspFormatDocument(formattingOptionsJSON: String? = nil, timeoutMs: UInt32 = 2000) throws -> Bool {
        var applied: UInt8 = 0
        let status: Int32
        if let formattingOptionsJSON {
            status = formattingOptionsJSON.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_format_document(handle, cstr, timeoutMs, &applied)
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_format_document(handle, nil, timeoutMs, &applied)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_document")
        return applied != 0
    }

    /// Format a range via LSP (`textDocument/rangeFormatting`) and apply edits locally.
    ///
    /// Offsets use editor-core char offsets. `formattingOptionsJSON` should match LSP `FormattingOptions`.
    @discardableResult
    public func lspFormatRange(
        startOffset: UInt32,
        endOffset: UInt32,
        formattingOptionsJSON: String? = nil,
        timeoutMs: UInt32 = 2000
    ) throws -> Bool {
        var applied: UInt8 = 0
        let status: Int32
        if let formattingOptionsJSON {
            status = formattingOptionsJSON.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_format_range(
                    handle,
                    startOffset,
                    endOffset,
                    cstr,
                    timeoutMs,
                    &applied
                )
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_format_range(
                handle,
                startOffset,
                endOffset,
                nil,
                timeoutMs,
                &applied
            )
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_range")
        return applied != 0
    }

    /// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits locally.
    ///
    /// `logicalLine` and `logicalColumn` are the logical editor position after `trigger` was inserted.
    @discardableResult
    public func lspFormatOnType(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        trigger: String,
        formattingOptionsJSON: String? = nil,
        timeoutMs: UInt32 = 2000
    ) throws -> Bool {
        var applied: UInt8 = 0
        let status = trigger.withCString { triggerCStr in
            if let formattingOptionsJSON {
                formattingOptionsJSON.withCString { optionsCStr in
                    editor_core_ui_ffi_editor_ui_lsp_format_on_type(
                        handle,
                        logicalLine,
                        logicalColumn,
                        triggerCStr,
                        optionsCStr,
                        timeoutMs,
                        &applied
                    )
                }
            } else {
                editor_core_ui_ffi_editor_ui_lsp_format_on_type(
                    handle,
                    logicalLine,
                    logicalColumn,
                    triggerCStr,
                    nil,
                    timeoutMs,
                    &applied
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_on_type")
        return applied != 0
    }

    /// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
    ///
    /// This call is non-blocking: it never waits for background work.
    ///
    /// - Returns:
    ///   - `applied`: whether new processing edits were applied.
    ///   - `pending`: whether there is still work pending in the background.
    public func pollProcessing() throws -> (applied: Bool, pending: Bool) {
        var applied: UInt8 = 0
        var pending: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_poll_processing(handle, &applied, &pending)
        try library.ensureStatus(status, context: "editor_ui_poll_processing")
        return (applied != 0, pending != 0)
    }

    public func treeSitterStyleId(forCapture captureName: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = captureName.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_style_id_for_capture")
        return out
    }

    public func treeSitterCapture(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_treesitter_capture_for_style_id", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspApplyDiagnosticsJSON(_ publishDiagnosticsParamsJSON: String) throws {
        let status = publishDiagnosticsParamsJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_diagnostics_json")
    }

    public func lspApplyInlayHintsJSON(_ inlayHintsResultJSON: String) throws {
        let status = inlayHintsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_inlay_hints_json")
    }

    public func lspApplyCodeLensJSON(_ codeLensResultJSON: String) throws {
        let status = codeLensResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_code_lens_json")
    }

    public func lspApplyDocumentLinksJSON(_ documentLinksResultJSON: String) throws {
        let status = documentLinksResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_links_json")
    }

    public func lspApplyDocumentHighlightsJSON(_ documentHighlightsResultJSON: String) throws {
        let status = documentHighlightsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_highlights_json")
    }

    public func lspApplyDocumentSymbolsJSON(_ documentSymbolsResultJSON: String) throws {
        let status = documentSymbolsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_symbols_json")
    }

    public func lspApplyFoldingRangesJSON(_ foldingRangesResultJSON: String) throws {
        let status = foldingRangesResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_folding_ranges_json")
    }

    @discardableResult
    public func lspApplyWorkspaceEditJSON(_ workspaceEditJSON: String, documentURI: String? = nil) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = workspaceEditJSON.withCString { editPtr in
            if let documentURI {
                return documentURI.withCString { uriPtr in
                    editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(handle, editPtr, uriPtr)
                }
            }
            return editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(handle, editPtr, nil)
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_apply_workspace_edit_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspApplySemanticTokens(_ data: [UInt32]) throws {
        let status = data.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_semantic_tokens")
    }

    public func setRenderMetrics(fontSize: Float, lineHeightPx: Float, cellWidthPx: Float, paddingXPx: Float, paddingYPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_render_metrics(handle, fontSize, lineHeightPx, cellWidthPx, paddingXPx, paddingYPx)
        try library.ensureStatus(status, context: "editor_ui_set_render_metrics")
    }

    public func setTextVerticalAlign(_ align: TextVerticalAlign) throws {
        let status = editor_core_ui_ffi_editor_ui_set_text_vertical_align(handle, align.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_text_vertical_align")
    }

    /// Configure a font fallback list for rendering (comma-separated family names).
    ///
    /// Example: `"Menlo, PingFang SC, Apple Color Emoji"`.
    ///
    /// Notes:
    /// - This affects glyph rasterization only; layout remains monospace-grid based.
    public func setFontFamiliesCSV(_ families: String) throws {
        let status = families.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_font_families_csv(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_font_families_csv")
    }

    /// Enable/disable font ligatures (e.g. Fira Code `->`, `!=`) in the Skia renderer.
    ///
    /// Notes:
    /// - This is visual-only; the editor model and hit-testing remain monospace-grid based.
    public func setFontLigaturesEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_font_ligatures_enabled")
    }

    /// Set caret width in pixels (minimum 1px when visible).
    ///
    /// Notes:
    /// - This is an absolute pixel width; if you want a "point" width, multiply by the view's backing scale.
    public func setCaretWidthPx(_ widthPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_caret_width_px(handle, widthPx)
        try library.ensureStatus(status, context: "editor_ui_set_caret_width_px")
    }

    /// Show/hide carets during rendering.
    ///
    /// Useful for UI-side caret blinking and focus handling.
    public func setCaretVisible(_ visible: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_caret_visible(handle, visible ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_caret_visible")
    }

    public func setIndentGuidesEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_indent_guides_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_indent_guides_enabled")
    }

    public func setWhitespaceRenderMode(_ mode: WhitespaceRenderMode) throws {
        let status = editor_core_ui_ffi_editor_ui_set_whitespace_render_mode(handle, mode.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_whitespace_render_mode")
    }

    public func setFoldMarkerStyle(_ style: FoldMarkerStyle) throws {
        let status = editor_core_ui_ffi_editor_ui_set_fold_marker_style(handle, style.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_fold_marker_style")
    }

    public func setTabWidth(_ widthCells: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_tab_width(handle, widthCells)
        try library.ensureStatus(status, context: "editor_ui_set_tab_width")
    }

    public func setTabKeyBehavior(_ behavior: TabKeyBehavior) throws {
        let status = editor_core_ui_ffi_editor_ui_set_tab_key_behavior(handle, behavior.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_tab_key_behavior")
    }

    /// Enable/disable auto-pairs behavior for typed characters.
    ///
    /// When enabled, single-character typing is routed through auto-pairs rules (auto-close,
    /// wrap selection, skip-over closing, delete-pair).
    public func setAutoPairsEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_auto_pairs_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_auto_pairs_enabled")
    }

    /// Enable/disable bracket-match highlighting.
    ///
    /// When enabled, the UI wrapper updates `StyleLayerId::BRACKET_MATCHES` after cursor moves and
    /// edits so the renderer can highlight matching delimiters.
    public func setBracketMatchHighlightsEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_bracket_match_highlights_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_bracket_match_highlights_enabled")
    }

    /// Configure the ASCII word-boundary character set for editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    ///
    /// Notes:
    /// - Only ASCII characters are configurable here; non-ASCII characters are always treated as boundaries.
    /// - ASCII whitespace is always treated as a boundary.
    public func setWordBoundaryAsciiBoundaryChars(_ boundaryChars: String) throws {
        let status = boundaryChars.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_word_boundary_ascii_boundary_chars")
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    public func resetWordBoundaryDefaults() throws {
        let status = editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(handle)
        try library.ensureStatus(status, context: "editor_ui_reset_word_boundary_defaults")
    }

    public func setGutterWidthCells(_ widthCells: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_gutter_width_cells(handle, widthCells)
        try library.ensureStatus(status, context: "editor_ui_set_gutter_width_cells")
    }

    public func logicalLineCount() throws -> UInt32 {
        var out: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_logical_line_count(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_get_logical_line_count")
        return out
    }

    public func gutterWidthCells() throws -> UInt32 {
        var out: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_gutter_width_cells(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_get_gutter_width_cells")
        return out
    }

    public func setViewportPx(widthPx: UInt32, heightPx: UInt32, scale: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_viewport_px(handle, widthPx, heightPx, scale)
        try library.ensureStatus(status, context: "editor_ui_set_viewport_px")
    }

    public func scrollByRows(_ deltaRows: Int32) {
        editor_core_ui_ffi_editor_ui_scroll_by_rows(handle, deltaRows)
    }

    /// Smooth-scroll by a pixel delta (positive = scroll down, reveal later lines).
    public func scrollByPixels(_ deltaYPx: Float) {
        editor_core_ui_ffi_editor_ui_scroll_by_pixels(handle, deltaYPx)
    }

    public func viewportState() throws -> EcuViewportState {
        var ffi = CEditorCoreUIFFI.EcuViewportState(
            width_cells: 0,
            height_rows: 0,
            has_height: 0,
            scroll_top: 0,
            sub_row_offset: 0,
            overscan_rows: 0,
            visible_start: 0,
            visible_end: 0,
            prefetch_start: 0,
            prefetch_end: 0,
            total_visual_lines: 0
        )
        let status = withUnsafeMutablePointer(to: &ffi) { ptr in
            editor_core_ui_ffi_editor_ui_get_viewport_state(handle, ptr)
        }
        try library.ensureStatus(status, context: "editor_ui_get_viewport_state")
        return EcuViewportState(ffi: ffi)
    }

    /// Set the smooth-scroll position directly.
    ///
    /// - Parameters:
    ///   - topVisualRow: Top visual row anchor (after wrapping/folding).
    ///   - subRowOffset: Normalized 0..=65535 fraction within the row.
    public func setSmoothScrollState(topVisualRow: UInt32, subRowOffset: UInt32) {
        editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(handle, topVisualRow, subRowOffset)
    }

    /// Adjust scroll position to ensure the primary caret is visible (best-effort).
    public func revealPrimaryCaret() throws {
        let status = editor_core_ui_ffi_editor_ui_reveal_primary_caret(handle)
        try library.ensureStatus(status, context: "editor_ui_reveal_primary_caret")
    }

    public func insertText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_insert_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_insert_text")
    }

    /// Execute one editor command encoded as JSON and return command-result JSON.
    ///
    /// The schema matches the headless `EditorState.executeJSON(_:)` command plane, with UI-layer
    /// additions for snippets, auto-pairs config, and bracket-match highlight commands.
    public func executeCommandJSON(_ commandJSON: String) throws -> String {
        guard let ptr = commandJSON.withCString({ cstr in
            editor_core_ui_ffi_editor_ui_execute_command_json(handle, cstr)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_execute_command_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func diagnosticsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_diagnostics_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_diagnostics_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func diagnosticsSnapshot() throws -> EcuDiagnosticsSnapshot {
        try Self.decodeSnapshot(
            EcuDiagnosticsSnapshot.self,
            from: diagnosticsJSON(),
            context: "editor_ui_diagnostics_snapshot"
        )
    }

    public func decorationsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_decorations_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_decorations_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func decorationsSnapshot() throws -> EcuDecorationsSnapshot {
        try Self.decodeSnapshot(
            EcuDecorationsSnapshot.self,
            from: decorationsJSON(),
            context: "editor_ui_decorations_snapshot"
        )
    }

    public func documentSymbolsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_document_symbols_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_document_symbols_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func documentSymbolsSnapshot() throws -> EcuDocumentSymbolsSnapshot {
        try Self.decodeSnapshot(
            EcuDocumentSymbolsSnapshot.self,
            from: documentSymbolsJSON(),
            context: "editor_ui_document_symbols_snapshot"
        )
    }

    public func foldingRegionsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_folding_regions_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_folding_regions_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func foldingRegionsSnapshot() throws -> EcuFoldingRegionsSnapshot {
        try Self.decodeSnapshot(
            EcuFoldingRegionsSnapshot.self,
            from: foldingRegionsJSON(),
            context: "editor_ui_folding_regions_snapshot"
        )
    }

    public func styleIntervalsJSON(start: UInt32, end: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_style_intervals_json(handle, start, end) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_style_intervals_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func styleIntervalsSnapshot(start: UInt32, end: UInt32) throws -> EcuStyleIntervalsSnapshot {
        try Self.decodeSnapshot(
            EcuStyleIntervalsSnapshot.self,
            from: styleIntervalsJSON(start: start, end: end),
            context: "editor_ui_style_intervals_snapshot"
        )
    }

    @discardableResult
    private func executeCommandObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: "editor_ui_encode_command_json",
                message: "failed to encode command JSON as UTF-8"
            )
        }
        return try executeCommandJSON(json)
    }

    @discardableResult
    private func executeEditorCommand(kind: String, op: String, fields: [String: Any] = [:]) throws -> String {
        var object: [String: Any] = ["kind": kind, "op": op]
        for (key, value) in fields {
            object[key] = value
        }
        return try executeCommandObject(object)
    }

    private static func decodeSnapshot<T: Decodable>(_ type: T.Type, from json: String, context: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: "snapshot JSON is not valid UTF-8"
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }

    private static func jsonObject(for options: EcuSearchOptions) -> [String: Any] {
        [
            "case_sensitive": options.caseSensitive,
            "whole_word": options.wholeWord,
            "regex": options.regex,
        ]
    }

    @discardableResult
    public func replace(start: UInt32, length: UInt32, text: String) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndo(start: UInt32, length: UInt32, text: String) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndoWithSelection(
        start: UInt32,
        length: UInt32,
        text: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo_with_selection",
            fields: [
                "start": Int(start),
                "length": Int(length),
                "text": text,
                "selection_start": Int(selectionStart),
                "selection_end": Int(selectionEnd),
            ]
        )
    }

    @discardableResult
    public func typeChar(_ ch: String) throws -> String {
        try executeEditorCommand(kind: "edit", op: "type_char", fields: ["ch": ch])
    }

    @discardableResult
    public func insertNewline(autoIndent: Bool = false) throws -> String {
        try executeEditorCommand(kind: "edit", op: "insert_newline", fields: ["auto_indent": autoIndent])
    }

    @discardableResult
    public func indent() throws -> String {
        try executeEditorCommand(kind: "edit", op: "indent")
    }

    @discardableResult
    public func outdent() throws -> String {
        try executeEditorCommand(kind: "edit", op: "outdent")
    }

    @discardableResult
    public func duplicateLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "duplicate_lines")
    }

    @discardableResult
    public func deleteLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "delete_lines")
    }

    @discardableResult
    public func moveLinesUp() throws -> String {
        try executeEditorCommand(kind: "edit", op: "move_lines_up")
    }

    @discardableResult
    public func moveLinesDown() throws -> String {
        try executeEditorCommand(kind: "edit", op: "move_lines_down")
    }

    @discardableResult
    public func joinLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "join_lines")
    }

    @discardableResult
    public func splitLine() throws -> String {
        try executeEditorCommand(kind: "edit", op: "split_line")
    }

    @discardableResult
    public func toggleComment(_ config: EcuCommentConfig) throws -> String {
        try executeEditorCommand(kind: "edit", op: "toggle_comment", fields: ["config": config.jsonObject])
    }

    @discardableResult
    public func applyTextEdits(_ edits: [EcuTextEdit]) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "apply_text_edits",
            fields: ["edits": edits.map(\.jsonObject)]
        )
    }

    @discardableResult
    public func applySnippet(
        start: UInt32,
        end: UInt32,
        snippet: String,
        additionalEdits: [EcuTextEdit] = []
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "apply_snippet",
            fields: [
                "start": Int(start),
                "end": Int(end),
                "snippet": snippet,
                "additional_edits": additionalEdits.map(\.jsonObject),
            ]
        )
    }

    @discardableResult
    public func deleteToPrevTabStop() throws -> String {
        try executeEditorCommand(kind: "edit", op: "delete_to_prev_tab_stop")
    }

    @discardableResult
    public func endUndoGroup() throws -> String {
        try executeEditorCommand(kind: "edit", op: "end_undo_group")
    }

    @discardableResult
    public func moveTo(line: UInt32, column: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "move_to",
            fields: ["line": Int(line), "column": Int(column)]
        )
    }

    @discardableResult
    public func moveBy(deltaLine: Int32, deltaColumn: Int32) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "move_by",
            fields: ["delta_line": Int(deltaLine), "delta_column": Int(deltaColumn)]
        )
    }

    @discardableResult
    public func addNextOccurrence(options: EcuSearchOptions = EcuSearchOptions()) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "add_next_occurrence",
            fields: ["options": Self.jsonObject(for: options)]
        )
    }

    @discardableResult
    public func addAllOccurrences(options: EcuSearchOptions = EcuSearchOptions()) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "add_all_occurrences",
            fields: ["options": Self.jsonObject(for: options)]
        )
    }

    @discardableResult
    public func snippetNextPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_next_placeholder")
    }

    @discardableResult
    public func snippetPrevPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_prev_placeholder")
    }

    @discardableResult
    public func setViewportWidthCells(_ widthCells: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_viewport_width",
            fields: ["width": Int(widthCells)]
        )
    }

    @discardableResult
    public func setWrapMode(_ mode: EcuWrapMode) throws -> String {
        try executeEditorCommand(kind: "view", op: "set_wrap_mode", fields: ["mode": mode.rawValue])
    }

    @discardableResult
    public func setWrapIndent(_ indent: EcuWrapIndent) throws -> String {
        try executeEditorCommand(kind: "view", op: "set_wrap_indent", fields: ["indent": indent.jsonObject])
    }

    @discardableResult
    public func setIndentationConfig(_ config: EcuIndentationConfig) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_indentation_config",
            fields: ["config": config.jsonObject]
        )
    }

    @discardableResult
    public func setAutoPairsConfig(_ config: EcuAutoPairsConfig) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_auto_pairs_config",
            fields: ["config": config.jsonObject]
        )
    }

    public func viewportJSON(startRow: UInt32, count: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "get_viewport",
            fields: ["start_row": Int(startRow), "count": Int(count)]
        )
    }

    @discardableResult
    public func fold(startLine: UInt32, endLine: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "style",
            op: "fold",
            fields: ["start_line": Int(startLine), "end_line": Int(endLine)]
        )
    }

    @discardableResult
    public func unfold(startLine: UInt32) throws -> String {
        try executeEditorCommand(kind: "style", op: "unfold", fields: ["start_line": Int(startLine)])
    }

    @discardableResult
    public func unfoldAll() throws -> String {
        try executeEditorCommand(kind: "style", op: "unfold_all")
    }

    @discardableResult
    public func updateBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "update_bracket_match_highlights")
    }

    @discardableResult
    public func clearBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "clear_bracket_match_highlights")
    }

    public func insertTab() throws {
        let status = editor_core_ui_ffi_editor_ui_insert_tab(handle)
        try library.ensureStatus(status, context: "editor_ui_insert_tab")
    }

    public func insertBacktab() throws {
        let status = editor_core_ui_ffi_editor_ui_insert_backtab(handle)
        try library.ensureStatus(status, context: "editor_ui_insert_backtab")
    }

    public func hasActiveSnippetSession() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_has_active_snippet_session(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_has_active_snippet_session")
        return out != 0
    }

    public func backspace() throws {
        let status = editor_core_ui_ffi_editor_ui_backspace(handle)
        try library.ensureStatus(status, context: "editor_ui_backspace")
    }

    public func deleteForward() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_forward")
    }

    public func deleteWordBack() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_word_back(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_word_back")
    }

    public func deleteWordForward() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_word_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_word_forward")
    }

    public func addStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_add_style(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_add_style")
    }

    public func removeStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_remove_style(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_remove_style")
    }

    /// Replace match highlight ranges (e.g. search matches) as a dedicated overlay layer.
    ///
    /// Passing an empty array clears the layer.
    public func setMatchHighlights(_ ranges: [EcuSelectionRange]) throws {
        let ffi = ranges.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_match_highlights(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_match_highlights")
    }

    /// Set an active search query and update match highlights accordingly.
    ///
    /// Returns the match count.
    public func setSearchQuery(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> UInt32 {
        var count: UInt32 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_search_set_query(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &count)
        }
        try library.ensureStatus(status, context: "editor_ui_search_set_query")
        return count
    }

    public func clearSearchQuery() throws {
        let status = editor_core_ui_ffi_editor_ui_search_clear(handle)
        try library.ensureStatus(status, context: "editor_ui_search_clear")
    }

    /// Find the next occurrence of `query` and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    public func findNext(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> Bool {
        var found: UInt8 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_find_next(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &found)
        }
        try library.ensureStatus(status, context: "editor_ui_find_next")
        return found != 0
    }

    /// Find the previous occurrence of `query` and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    public func findPrev(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> Bool {
        var found: UInt8 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_find_prev(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &found)
        }
        try library.ensureStatus(status, context: "editor_ui_find_prev")
        return found != 0
    }

    /// Replace the current match (based on selection/caret) and return how many occurrences were replaced.
    public func replaceCurrent(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions()
    ) throws -> UInt32 {
        var replaced: UInt32 = 0
        let status = query.withCString { queryCStr in
            replacement.withCString { replCStr in
                editor_core_ui_ffi_editor_ui_replace_current(
                    handle,
                    queryCStr,
                    replCStr,
                    options.ffiCaseSensitive,
                    options.ffiWholeWord,
                    options.ffiRegex,
                    &replaced
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_replace_current")
        return replaced
    }

    /// Replace all matches and return how many occurrences were replaced.
    public func replaceAll(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions()
    ) throws -> UInt32 {
        var replaced: UInt32 = 0
        let status = query.withCString { queryCStr in
            replacement.withCString { replCStr in
                editor_core_ui_ffi_editor_ui_replace_all(
                    handle,
                    queryCStr,
                    replCStr,
                    options.ffiCaseSensitive,
                    options.ffiWholeWord,
                    options.ffiRegex,
                    &replaced
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_replace_all")
        return replaced
    }

    public func undo() throws {
        let status = editor_core_ui_ffi_editor_ui_undo(handle)
        try library.ensureStatus(status, context: "editor_ui_undo")
    }

    public func redo() throws {
        let status = editor_core_ui_ffi_editor_ui_redo(handle)
        try library.ensureStatus(status, context: "editor_ui_redo")
    }

    public func moveVisualByRows(_ deltaRows: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_rows(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows")
    }

    public func moveGraphemeLeft() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_left(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left")
    }

    public func moveGraphemeRight() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_right(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right")
    }

    public func moveWordLeft() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_left(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_left")
    }

    public func moveWordRight() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_right(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_right")
    }

    /// Jump the primary caret to the matching bracket (if any).
    public func moveToMatchingBracket() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_matching_bracket(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_matching_bracket")
    }

    // MARK: - Bookmarks / marks / jump list

    /// Toggle a bookmark at the current cursor line.
    ///
    /// Returns `true` if a bookmark was added, or `false` if an existing bookmark on that line was removed.
    @discardableResult
    public func toggleBookmarkAtCursorLine() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_toggle_bookmark_at_cursor_line(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_toggle_bookmark_at_cursor_line")
        return out != 0
    }

    /// Move the caret to the next bookmark (wraps to the first bookmark).
    public func goToNextBookmark() throws {
        let status = editor_core_ui_ffi_editor_ui_goto_next_bookmark(handle)
        try library.ensureStatus(status, context: "editor_ui_goto_next_bookmark")
    }

    /// Move the caret to the previous bookmark (wraps to the last bookmark).
    public func goToPrevBookmark() throws {
        let status = editor_core_ui_ffi_editor_ui_goto_prev_bookmark(handle)
        try library.ensureStatus(status, context: "editor_ui_goto_prev_bookmark")
    }

    /// Set (or replace) a named mark at the current caret position.
    public func setMarkAtCursor(_ name: String) throws {
        let status: Int32 = name.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_mark_at_cursor(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_mark_at_cursor")
    }

    /// Move the caret to a named mark (if present).
    public func goToMark(_ name: String) throws {
        let status: Int32 = name.withCString { cstr in
            editor_core_ui_ffi_editor_ui_goto_mark(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_goto_mark")
    }

    /// Record the current caret location into the jump list.
    public func pushJumpLocation() throws {
        let status = editor_core_ui_ffi_editor_ui_push_jump_location(handle)
        try library.ensureStatus(status, context: "editor_ui_push_jump_location")
    }

    /// Jump back in the jump list (no-op when empty).
    public func jumpBack() throws {
        let status = editor_core_ui_ffi_editor_ui_jump_back(handle)
        try library.ensureStatus(status, context: "editor_ui_jump_back")
    }

    /// Jump forward in the jump list (no-op when empty).
    public func jumpForward() throws {
        let status = editor_core_ui_ffi_editor_ui_jump_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_jump_forward")
    }

    public func moveToVisualLineStart() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_start(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_start")
    }

    public func moveToVisualLineEnd() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_end(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_end")
    }

    public func moveToDocumentStart() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_start(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_start")
    }

    public func moveToDocumentEnd() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_end(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_end")
    }

    public func moveVisualByPages(_ deltaPages: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_pages(handle, deltaPages)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_pages")
    }

    public func moveGraphemeLeftAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left_and_modify_selection")
    }

    public func moveGraphemeRightAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right_and_modify_selection")
    }

    public func moveWordLeftAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_left_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_left_and_modify_selection")
    }

    public func moveWordRightAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_right_and_modify_selection")
    }

    public func moveToVisualLineStartAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_start_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_start_and_modify_selection")
    }

    public func moveToVisualLineEndAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_end_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_end_and_modify_selection")
    }

    public func moveToDocumentStartAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_start_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_start_and_modify_selection")
    }

    public func moveToDocumentEndAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_end_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_end_and_modify_selection")
    }

    public func moveVisualByPagesAndModifySelection(_ deltaPages: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_pages_and_modify_selection(handle, deltaPages)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_pages_and_modify_selection")
    }

    public func moveVisualByRowsAndModifySelection(_ deltaRows: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows_and_modify_selection")
    }

    public func setMarkedText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text")
    }

    /// Set IME marked text (preedit) with selection and optional replacement range.
    ///
    /// - `selectedStart/selectedLen`: selection within `text` (Unicode scalar offsets).
    /// - `replaceStart/replaceLen`: document char-offset range to replace.
    ///   Pass `UInt32.max` for `replaceStart` to let Rust pick (existing marked range / current selection).
    public func setMarkedText(
        _ text: String,
        selectedStart: UInt32,
        selectedLen: UInt32,
        replaceStart: UInt32 = UInt32.max,
        replaceLen: UInt32 = 0
    ) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text_ex(handle, cstr, selectedStart, selectedLen, replaceStart, replaceLen)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text_ex")
    }

    public func unmarkText() {
        editor_core_ui_ffi_editor_ui_unmark_text(handle)
    }

    public func commitText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_commit_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_commit_text")
    }

    /// Paste text from the clipboard.
    ///
    /// Notes:
    /// - This always uses the bulk insert path in Rust (no auto-pairs), even for a single character,
    ///   to match typical editor semantics for paste operations.
    public func pasteText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_paste_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_paste_text")
    }

    public func mouseDown(xPx: Float, yPx: Float) throws {
        try mouseDownEx(xPx: xPx, yPx: yPx, modifiers: 0, clickCount: 1)
    }

    /// Mouse down with modifier + click-count support.
    ///
    /// - Parameters:
    ///   - modifiers: bit layout mirrors the C header (`editor_core_ui_ffi.h`)
    ///   - clickCount: 1=single, 2=double, 3=triple, 4+=paragraph.
    public func mouseDownEx(
        xPx: Float,
        yPx: Float,
        modifiers: UInt32,
        clickCount: UInt32
    ) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_down_ex(handle, xPx, yPx, modifiers, clickCount)
        try library.ensureStatus(status, context: "editor_ui_mouse_down_ex")
    }

    public func mouseDragged(xPx: Float, yPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_dragged(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_dragged")
    }

    public func mouseUp() {
        editor_core_ui_ffi_editor_ui_mouse_up(handle)
    }

    public func renderRGBA(into buffer: inout [UInt8]) throws -> Int {
        var required: UInt32 = 0
        var status = editor_core_ui_ffi_editor_ui_render_rgba(handle, nil, 0, &required)
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_render_rgba(size_query)", message: "unknown status \(status)")
        }
        guard code == .bufferTooSmall || code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: "editor_ui_render_rgba(size_query)", message: library.lastErrorMessageString())
        }

        let requiredCount = Int(required)
        if buffer.count != requiredCount {
            buffer = Array(repeating: 0, count: requiredCount)
        }

        status = buffer.withUnsafeMutableBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_render_rgba(handle, ptr.baseAddress, UInt32(ptr.count), &required)
        }
        try library.ensureStatus(status, context: "editor_ui_render_rgba")
        return requiredCount
    }

    // MARK: - Metal / GPU rendering (macOS)

    public func enableMetal(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()
        let queuePtr = Unmanaged.passUnretained(commandQueue).toOpaque()
        let status = editor_core_ui_ffi_editor_ui_enable_metal(handle, devicePtr, queuePtr)
        try library.ensureStatus(status, context: "editor_ui_enable_metal")
    }

    public func renderMetal(into texture: MTLTexture) throws {
        let texPtr = Unmanaged.passUnretained(texture).toOpaque()
        let status = editor_core_ui_ffi_editor_ui_render_metal(handle, texPtr)
        try library.ensureStatus(status, context: "editor_ui_render_metal")
    }

    public func text() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_get_text(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_text", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func isModified() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_is_modified(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_is_modified")
        return out != 0
    }

    public func markSaved() throws {
        let status = editor_core_ui_ffi_editor_ui_mark_saved(handle)
        try library.ensureStatus(status, context: "editor_ui_mark_saved")
    }

    /// Get selected text (primary + secondary selections), joined with `\\n`.
    public func selectedText() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_get_selected_text(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_selected_text", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func minimapJSON(startVisualRow: UInt32, rowCount: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_minimap_json(handle, startVisualRow, rowCount) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_minimap_json", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func selectionOffsets() throws -> (start: UInt32, end: UInt32) {
        var start: UInt32 = 0
        var end: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_selection_offsets(handle, &start, &end)
        try library.ensureStatus(status, context: "editor_ui_get_selection_offsets")
        return (start, end)
    }

    /// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
    ///
    /// Intended for clipboard "cut" behavior.
    public func deleteSelectionsOnly() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_selections_only(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_selections_only")
    }

    public func selections() throws -> (ranges: [EcuSelectionRange], primaryIndex: UInt32) {
        var required: UInt32 = 0
        var primary: UInt32 = 0
        var status = editor_core_ui_ffi_editor_ui_get_selections(handle, nil, 0, &required, &primary)
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_selections(size_query)", message: "unknown status \(status)")
        }
        guard code == .bufferTooSmall || code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: "editor_ui_get_selections(size_query)", message: library.lastErrorMessageString())
        }

        var ffiRanges = Array(repeating: CEditorCoreUIFFI.EcuSelectionRange(start: 0, end: 0), count: Int(required))
        status = ffiRanges.withUnsafeMutableBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_get_selections(handle, ptr.baseAddress, UInt32(ptr.count), &required, &primary)
        }
        try library.ensureStatus(status, context: "editor_ui_get_selections")
        let ranges = ffiRanges.map { EcuSelectionRange(start: $0.start, end: $0.end) }
        return (ranges, primary)
    }

    public func setSelections(_ ranges: [EcuSelectionRange], primaryIndex: UInt32) throws {
        let ffi = ranges.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_selections(handle, ptr.baseAddress, UInt32(ptr.count), primaryIndex)
        }
        try library.ensureStatus(status, context: "editor_ui_set_selections")
    }

    public func setRectSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_rect_selection(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_rect_selection")
    }

    public func clearSecondarySelections() throws {
        let status = editor_core_ui_ffi_editor_ui_clear_secondary_selections(handle)
        try library.ensureStatus(status, context: "editor_ui_clear_secondary_selections")
    }

    public func addCursorAbove() throws {
        let status = editor_core_ui_ffi_editor_ui_add_cursor_above(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_above")
    }

    public func addCursorBelow() throws {
        let status = editor_core_ui_ffi_editor_ui_add_cursor_below(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_below")
    }

    public func selectWord() throws {
        let status = editor_core_ui_ffi_editor_ui_select_word(handle)
        try library.ensureStatus(status, context: "editor_ui_select_word")
    }

    public func selectLine() throws {
        let status = editor_core_ui_ffi_editor_ui_select_line(handle)
        try library.ensureStatus(status, context: "editor_ui_select_line")
    }

    public func setLineSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_line_selection_offsets(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_line_selection_offsets")
    }

    public func selectParagraph(atCharOffset charOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(handle, charOffset)
        try library.ensureStatus(status, context: "editor_ui_select_paragraph_at_char_offset")
    }

    public func setParagraphSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_paragraph_selection_offsets")
    }

    public func expandSelection() throws {
        let status = editor_core_ui_ffi_editor_ui_expand_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_expand_selection")
    }

    public func expandSelectionBy(unit: EcuExpandSelectionUnit, count: UInt32, direction: EcuExpandSelectionDirection) throws {
        let status = editor_core_ui_ffi_editor_ui_expand_selection_by(handle, unit.rawValue, count, direction.rawValue)
        try library.ensureStatus(status, context: "editor_ui_expand_selection_by")
    }

    public func addCaret(atCharOffset charOffset: UInt32, makePrimary: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(handle, charOffset, makePrimary ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_add_caret_at_char_offset")
    }

    public func markedRange() throws -> (hasMarked: Bool, start: UInt32, len: UInt32) {
        var has: UInt8 = 0
        var start: UInt32 = 0
        var len: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_marked_range(handle, &has, &start, &len)
        try library.ensureStatus(status, context: "editor_ui_get_marked_range")
        return (has != 0, start, len)
    }

    public func charOffsetToLogicalPosition(offset: UInt32) throws -> (line: UInt32, column: UInt32) {
        var line: UInt32 = 0
        var col: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(handle, offset, &line, &col)
        try library.ensureStatus(status, context: "editor_ui_char_offset_to_logical_position")
        return (line, col)
    }

    public func charOffsetToViewPoint(offset: UInt32) throws -> (xPx: Float, yPx: Float, lineHeightPx: Float) {
        var x: Float = 0
        var y: Float = 0
        var lineH: Float = 0
        let status = editor_core_ui_ffi_editor_ui_char_offset_to_view_point(handle, offset, &x, &y, &lineH)
        try library.ensureStatus(status, context: "editor_ui_char_offset_to_view_point")
        return (x, y, lineH)
    }

    public func viewPointToCharOffset(xPx: Float, yPx: Float) throws -> UInt32 {
        var offset: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_view_point_to_char_offset(handle, xPx, yPx, &offset)
        try library.ensureStatus(status, context: "editor_ui_view_point_to_char_offset")
        return offset
    }

    /// Hit-test a view point and return the raw LSP `DocumentLink` JSON payload (if present).
    public func documentLinkJSONAtViewPoint(xPx: Float, yPx: Float) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(handle, xPx, yPx, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_get_document_link_json_at_view_point")
        guard has != 0, let ptr else {
            return nil
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }
}
