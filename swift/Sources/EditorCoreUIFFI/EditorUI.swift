import CEditorCoreUIFFI
import Foundation
import Metal

public struct EcuLspResultEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let family: String
    public let title: String
    public let slot: String
    public let method: String
    public let viewId: UInt64
    public let requestId: UInt64
    public let status: String
    public let hasResult: Bool
    public let resultJSONLength: Int
    public let errorCode: Int64?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case sequence
        case family
        case title
        case slot
        case method
        case viewId = "view_id"
        case requestId = "request_id"
        case status
        case hasResult = "has_result"
        case resultJSONLength = "result_json_len"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

public struct EcuLspResultEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuLspResultEvent]

    enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuLspRequestEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let family: String
    public let title: String
    public let slot: String
    public let method: String
    public let viewId: UInt64
    public let requestId: UInt64
    public let phase: String
    public let status: String
    public let resultSequence: UInt64?
    public let errorCode: Int64?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case sequence
        case family
        case title
        case slot
        case method
        case viewId = "view_id"
        case requestId = "request_id"
        case phase
        case status
        case resultSequence = "result_sequence"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

public struct EcuLspRequestEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuLspRequestEvent]

    enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuEditorUITextStateEvent: Decodable, Equatable, Sendable {
    public let textVersion: UInt64
    public let charLen: Int
    public let isModified: Bool

    enum CodingKeys: String, CodingKey {
        case textVersion = "text_version"
        case charLen = "char_len"
        case isModified = "is_modified"
    }
}

public struct EcuEditorUIDirtyStateEvent: Decodable, Equatable, Sendable {
    public let isModified: Bool

    enum CodingKeys: String, CodingKey {
        case isModified = "is_modified"
    }
}

public struct EcuEditorUIPositionStateEvent: Decodable, Equatable, Sendable {
    public let line: Int
    public let column: Int
    public let offset: Int
}

public struct EcuEditorUISelectionRangeStateEvent: Decodable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let anchor: Int
    public let active: Int
}

public struct EcuEditorUISelectionStateEvent: Decodable, Equatable, Sendable {
    public let viewVersion: UInt64
    public let primary: EcuEditorUIPositionStateEvent
    public let primarySelectionIndex: Int
    public let selectionCount: Int
    public let hasSelection: Bool
    public let selections: [EcuEditorUISelectionRangeStateEvent]

    enum CodingKeys: String, CodingKey {
        case viewVersion = "view_version"
        case primary
        case primarySelectionIndex = "primary_selection_index"
        case selectionCount = "selection_count"
        case hasSelection = "has_selection"
        case selections
    }
}

public struct EcuEditorUIViewportRangeStateEvent: Decodable, Equatable, Sendable {
    public let start: Int
    public let end: Int
}

public struct EcuEditorUIViewportStateEvent: Decodable, Equatable, Sendable {
    public let viewVersion: UInt64
    public let width: Int
    public let height: Int?
    public let scrollTop: Int
    public let subRowOffset: UInt16
    public let overscanRows: Int
    public let visibleLines: EcuEditorUIViewportRangeStateEvent
    public let prefetchLines: EcuEditorUIViewportRangeStateEvent
    public let totalVisualLines: Int

    enum CodingKeys: String, CodingKey {
        case viewVersion = "view_version"
        case width
        case height
        case scrollTop = "scroll_top"
        case subRowOffset = "sub_row_offset"
        case overscanRows = "overscan_rows"
        case visibleLines = "visible_lines"
        case prefetchLines = "prefetch_lines"
        case totalVisualLines = "total_visual_lines"
    }
}

public struct EcuEditorUILayoutStateEvent: Decodable, Equatable, Sendable {
    public let widthPx: UInt32
    public let heightPx: UInt32
    public let scale: Float
    public let fontSize: Float
    public let lineHeightPx: Float
    public let cellWidthPx: Float
    public let paddingXPx: Float
    public let paddingYPx: Float
    public let gutterWidthCells: UInt32
    public let tabWidthCells: UInt32
    public let textVerticalAlign: String

    enum CodingKeys: String, CodingKey {
        case widthPx = "width_px"
        case heightPx = "height_px"
        case scale
        case fontSize = "font_size"
        case lineHeightPx = "line_height_px"
        case cellWidthPx = "cell_width_px"
        case paddingXPx = "padding_x_px"
        case paddingYPx = "padding_y_px"
        case gutterWidthCells = "gutter_width_cells"
        case tabWidthCells = "tab_width_cells"
        case textVerticalAlign = "text_vertical_align"
    }
}

public struct EcuEditorUIDerivedStateEvent: Decodable, Equatable, Sendable {
    public let status: String
    public let reason: String
    public let textVersion: UInt64
    public let editCount: Int
    public let families: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case reason
        case textVersion = "text_version"
        case editCount = "edit_count"
        case families
    }
}

public struct EcuEditorUIStateEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let kind: String
    public let family: String
    public let title: String
    public let viewId: UInt64
    public let sourceSequence: UInt64
    public let lspRequest: EcuLspRequestEvent?
    public let lspResult: EcuLspResultEvent?
    public let text: EcuEditorUITextStateEvent?
    public let dirty: EcuEditorUIDirtyStateEvent?
    public let selection: EcuEditorUISelectionStateEvent?
    public let viewport: EcuEditorUIViewportStateEvent?
    public let layout: EcuEditorUILayoutStateEvent?
    public let derivedState: EcuEditorUIDerivedStateEvent?

    enum CodingKeys: String, CodingKey {
        case sequence
        case kind
        case family
        case title
        case viewId = "view_id"
        case sourceSequence = "source_sequence"
        case lspRequest = "lsp_request"
        case lspResult = "lsp_result"
        case text
        case dirty
        case selection
        case viewport
        case layout
        case derivedState = "derived_state"
    }
}

public struct EcuEditorUIStateEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuEditorUIStateEvent]

    enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public final class EditorUI {
    public let library: EditorCoreUIFFILibrary
    let handle: OpaquePointer

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

    init(library: EditorCoreUIFFILibrary, handle: OpaquePointer) {
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
}
