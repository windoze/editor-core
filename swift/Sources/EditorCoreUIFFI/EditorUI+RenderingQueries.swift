import CEditorCoreUIFFI
import Foundation
import Metal

public enum EcuMinimapEnvelopeStatus: Hashable, Sendable {
    case success
    case error
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "success":
            self = .success
        case "error":
            self = .error
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .success:
            return "success"
        case .error:
            return "error"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public struct EcuMinimapEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let startVisualRow: UInt32
    public let count: UInt32
    public let value: EcuJSONValue?
    public let error: EcuMinimapEnvelopeError?
    public let version: UInt32

    public var statusKind: EcuMinimapEnvelopeStatus {
        EcuMinimapEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case startVisualRow = "start_visual_row"
        case count
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        startVisualRow = try container.decodeIfPresent(UInt32.self, forKey: .startVisualRow) ?? 0
        count = try container.decodeIfPresent(UInt32.self, forKey: .count) ?? 0
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuMinimapEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuMinimapEnvelopeError: Decodable, Equatable, Sendable {
    public let code: String
    public let status: EcuStatus?
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

extension EditorUI {
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

    public func minimapEnvelopeJSON(startVisualRow: UInt32, rowCount: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_minimap_envelope_json(handle, startVisualRow, rowCount) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_minimap_envelope_json", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func minimapEnvelope(startVisualRow: UInt32, rowCount: UInt32) throws -> EcuMinimapEnvelope {
        try Self.decodeSnapshot(
            EcuMinimapEnvelope.self,
            from: minimapEnvelopeJSON(startVisualRow: startVisualRow, rowCount: rowCount),
            context: "editor_ui_minimap_envelope_decode"
        )
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

    /// Hit-test a view point and return the raw LSP `InlayHint` JSON payload (if present).
    public func inlayHintJSONAtViewPoint(xPx: Float, yPx: Float) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_get_inlay_hint_json_at_view_point(handle, xPx, yPx, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_get_inlay_hint_json_at_view_point")
        guard has != 0, let ptr else {
            return nil
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Hit-test a view point and return the raw LSP `CodeLens` JSON payload (if present).
    public func codeLensJSONAtViewPoint(xPx: Float, yPx: Float) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(handle, xPx, yPx, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_get_code_lens_json_at_view_point")
        guard has != 0, let ptr else {
            return nil
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }
}
