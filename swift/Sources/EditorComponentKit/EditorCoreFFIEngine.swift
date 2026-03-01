import Foundation

public final class EditorCoreFFIEngine: EditorEngineProtocol {
    public let ffi: EditorCoreFFILibrary
    fileprivate let stateHandle: UnsafeMutableRawPointer

    private var cachedText: String
    private var diagnosticsCache: EditorDiagnosticsSnapshot = .init(items: [])

    public init(
        initialText: String,
        viewportWidth: Int = 120,
        libraryPath: String? = nil,
        library: EditorCoreFFILibrary? = nil
    ) throws {
        let resolvedLibrary: EditorCoreFFILibrary
        if let library {
            resolvedLibrary = library
        } else {
            resolvedLibrary = try EditorCoreFFILibrary(path: libraryPath)
        }
        self.ffi = resolvedLibrary
        self.cachedText = initialText

        let handle = try initialText.withCString { ptr -> UnsafeMutableRawPointer in
            guard let raw = resolvedLibrary.editorStateNewFn(ptr, max(1, viewportWidth)) else {
                let message = resolvedLibrary.lastErrorMessage()
                let fallback = message.isEmpty
                    ? "Failed to create editor-core-ffi editor state"
                    : message
                throw EditorCommandError(fallback)
            }
            return raw
        }

        self.stateHandle = handle
        self.cachedText = (try? fetchText()) ?? initialText
    }

    deinit {
        ffi.editorStateFreeFn(stateHandle)
    }

    public var text: String {
        (try? fetchText()) ?? cachedText
    }

    public func documentState() throws -> EditorDocumentState {
        let full = try fullState()
        return EditorDocumentState(
            lineCount: full.document.lineCount,
            charCount: full.document.charCount,
            byteCount: full.document.byteCount,
            isModified: full.document.isModified,
            version: UInt64(full.document.version)
        )
    }

    public func cursorState() throws -> EditorCursorState {
        let full = try fullState()
        let selections = full.cursor.selections.map { dto in
            EditorSelection(
                start: EditorPosition(line: dto.start.line, column: dto.start.column),
                end: EditorPosition(line: dto.end.line, column: dto.end.column),
                direction: dto.direction == "backward" ? .backward : .forward
            )
        }

        return EditorCursorState(
            position: EditorPosition(
                line: full.cursor.position.line,
                column: full.cursor.position.column
            ),
            selections: selections,
            primarySelectionIndex: full.cursor.primarySelectionIndex
        )
    }

    public func execute(_ command: EditorCommand) throws -> EditorCommandResult {
        let result: EditorCommandResult
        switch command {
        case .insertText(let inserted):
            let bytes = Array(inserted.utf8)
            let status = bytes.withUnsafeBufferPointer { buf in
                ffi.editorInsertTextUTF8Fn(
                    stateHandle,
                    buf.baseAddress,
                    UInt32(buf.count)
                )
            }
            try ensureStatus(status, context: "insert_text_utf8")
            result = .success

        case .backspace:
            try ensureStatus(ffi.editorBackspaceFn(stateHandle), context: "backspace")
            result = .success

        case .deleteForward:
            try ensureStatus(ffi.editorDeleteForwardFn(stateHandle), context: "delete_forward")
            result = .success

        case .undo:
            try ensureStatus(ffi.editorUndoFn(stateHandle), context: "undo")
            result = .success

        case .redo:
            try ensureStatus(ffi.editorRedoFn(stateHandle), context: "redo")
            result = .success

        case .moveTo(let position):
            try ensureStatus(
                ffi.editorMoveToFn(
                    stateHandle,
                    clampedU32(position.line),
                    clampedU32(position.column)
                ),
                context: "move_to"
            )
            result = .success

        case .moveBy(let deltaLine, let deltaColumn):
            try ensureStatus(
                ffi.editorMoveByFn(
                    stateHandle,
                    clampedI32(deltaLine),
                    clampedI32(deltaColumn)
                ),
                context: "move_by"
            )
            result = .success

        case .setSelection(let selection):
            let direction: UInt8 = selection.direction == .backward ? 1 : 0
            try ensureStatus(
                ffi.editorSetSelectionFn(
                    stateHandle,
                    clampedU32(selection.start.line),
                    clampedU32(selection.start.column),
                    clampedU32(selection.end.line),
                    clampedU32(selection.end.column),
                    direction
                ),
                context: "set_selection"
            )
            result = .success

        case .clearSelection:
            try ensureStatus(ffi.editorClearSelectionFn(stateHandle), context: "clear_selection")
            result = .success

        case .custom(let name, _):
            throw EditorCommandError("Unsupported custom command for editor-core-ffi engine: \(name)")

        default:
            let payload = try commandJSONPayload(command)
            result = try executeJSONCommand(payload)
        }

        cachedText = (try? fetchText()) ?? cachedText
        return result
    }

    public func styledViewport(_ request: EditorViewportRequest) throws -> EditorSnapshot {
        let blob = try viewportBlob(startVisualRow: request.startVisualRow, rowCount: request.rowCount)
        return try parseViewportBlob(blob, request: request)
    }

    public func minimapViewport(_ request: EditorViewportRequest) throws -> EditorMinimapSnapshot {
        let ptr = ffi.editorStateMinimapJSONFn(
            stateHandle,
            max(request.startVisualRow, 0),
            max(request.rowCount, 0)
        )
        let json = try ffi.takeOwnedCString(ptr)
        let dto = try decodeJSON(MinimapGridDTO.self, from: json, context: "minimap_viewport")
        return EditorMinimapSnapshot(
            startVisualRow: dto.startVisualRow,
            requestedCount: dto.count,
            lines: dto.lines.map {
                EditorMinimapLine(
                    logicalLineIndex: $0.logicalLineIndex,
                    visualInLogical: $0.visualInLogical,
                    totalCells: $0.totalCells,
                    nonWhitespaceCells: $0.nonWhitespaceCells,
                    dominantStyle: $0.dominantStyle
                )
            }
        )
    }

    public func styleSpans(in range: Range<Int>) throws -> [EditorStyleSpan] {
        if range.isEmpty {
            return []
        }
        let full = try fullState()
        let totalVisualLines = max(full.viewport.totalVisualLines, full.document.lineCount, 1)
        let snapshot = try styledViewport(.init(startVisualRow: 0, rowCount: totalVisualLines))
        return deriveStyleSpans(from: snapshot, in: range)
    }

    public func inlays(in range: Range<Int>) throws -> [EditorInlay] {
        let full = try fullState()
        let requestRows = max(full.viewport.totalVisualLines + full.document.lineCount + 64, 256)
        let ptr = ffi.editorStateViewportComposedJSONFn(stateHandle, 0, requestRows)
        let json = try ffi.takeOwnedCString(ptr)
        let dto = try decodeJSON(ComposedGridDTO.self, from: json, context: "inlays")
        return deriveInlays(from: dto, in: range)
    }

    public func foldRegions() throws -> [EditorFoldRegion] {
        let full = try fullState()
        return full.folding.regions.map { region in
            EditorFoldRegion(
                startLine: region.startLine,
                endLine: region.endLine,
                isCollapsed: region.isCollapsed,
                placeholder: region.placeholder
            )
        }
    }

    public func diagnostics() throws -> EditorDiagnosticsSnapshot {
        diagnosticsCache
    }

    public func applyProcessingEditsJSON(_ editsJSON: String) throws {
        let ok = editsJSON.withCString { ptr in
            ffi.editorStateApplyProcessingEditsJSONFn(stateHandle, ptr)
        }
        if !ok {
            throw commandError(context: "apply_processing_edits_json")
        }
        applyDiagnosticsCacheDelta(from: editsJSON)
    }

    public func applyLSPDiagnostics(_ publishDiagnosticsParamsJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            publishDiagnosticsParamsJSON,
            converter: ffi.lspDiagnosticsToProcessingEditsJSONFn,
            context: "lsp_diagnostics_to_processing_edits_json"
        )
    }

    public func applyLSPDocumentHighlights(_ resultJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            resultJSON,
            converter: ffi.lspDocumentHighlightsToProcessingEditJSONFn,
            context: "lsp_document_highlights_to_processing_edit_json"
        )
    }

    public func applyLSPInlayHints(_ resultJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            resultJSON,
            converter: ffi.lspInlayHintsToProcessingEditJSONFn,
            context: "lsp_inlay_hints_to_processing_edit_json"
        )
    }

    public func applyLSPDocumentLinks(_ resultJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            resultJSON,
            converter: ffi.lspDocumentLinksToProcessingEditJSONFn,
            context: "lsp_document_links_to_processing_edit_json"
        )
    }

    public func applyLSPCodeLens(_ resultJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            resultJSON,
            converter: ffi.lspCodeLensToProcessingEditJSONFn,
            context: "lsp_code_lens_to_processing_edit_json"
        )
    }

    public func applyLSPDocumentSymbols(_ resultJSON: String) throws {
        try convertLSPToProcessingEditsAndApply(
            resultJSON,
            converter: ffi.lspDocumentSymbolsToProcessingEditJSONFn,
            context: "lsp_document_symbols_to_processing_edit_json"
        )
    }

    private func convertLSPToProcessingEditsAndApply(
        _ payloadJSON: String,
        converter: @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?,
        context: String
    ) throws {
        let editsJSON = try payloadJSON.withCString { ptr in
            let out = converter(stateHandle, ptr)
            return try ffi.takeOwnedCString(out)
        }
        try applyProcessingEditsJSON(editsJSON)
        cachedText = (try? fetchText()) ?? cachedText
    }

    private func executeJSONCommand(_ payload: [String: Any]) throws -> EditorCommandResult {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCommandError("Failed to encode command payload")
        }
        let ptr = json.withCString { cJSON in
            ffi.editorStateExecuteJSONFn(stateHandle, cJSON)
        }
        let resultJSON = try ffi.takeOwnedCString(ptr)
        let dto = try decodeJSON(CommandResultDTO.self, from: resultJSON, context: "execute_json")
        return dto.asCommandResult
    }

    private func fullState() throws -> FullStateDTO {
        let ptr = ffi.editorStateFullStateJSONFn(stateHandle)
        let json = try ffi.takeOwnedCString(ptr)
        return try decodeJSON(FullStateDTO.self, from: json, context: "full_state")
    }

    private func fetchText() throws -> String {
        let ptr = ffi.editorStateTextJSONFn(stateHandle)
        let json = try ffi.takeOwnedCString(ptr)
        let envelope = try decodeJSON(TextEnvelopeDTO.self, from: json, context: "text")
        cachedText = envelope.text
        return envelope.text
    }

    private func viewportBlob(startVisualRow: Int, rowCount: Int) throws -> Data {
        var required: UInt32 = 0
        let probeStatus = ffi.editorViewportBlobFn(
            stateHandle,
            clampedU32(startVisualRow),
            clampedU32(rowCount),
            nil,
            0,
            &required
        )

        if probeStatus != EditorCoreFFIStatusCode.bufferTooSmall.rawValue,
           probeStatus != EditorCoreFFIStatusCode.ok.rawValue {
            throw commandError(context: "editor_get_viewport_blob probe", status: probeStatus)
        }
        if required == 0 {
            return Data()
        }

        var buffer = [UInt8](repeating: 0, count: Int(required))
        var actual = required
        let status = buffer.withUnsafeMutableBufferPointer { buf in
            ffi.editorViewportBlobFn(
                stateHandle,
                clampedU32(startVisualRow),
                clampedU32(rowCount),
                buf.baseAddress,
                UInt32(buf.count),
                &actual
            )
        }

        guard status == EditorCoreFFIStatusCode.ok.rawValue else {
            throw commandError(context: "editor_get_viewport_blob", status: status)
        }
        return Data(buffer.prefix(Int(actual)))
    }

    private func parseViewportBlob(_ data: Data, request: EditorViewportRequest) throws -> EditorSnapshot {
        if data.isEmpty {
            return EditorSnapshot(startVisualRow: request.startVisualRow, requestedCount: request.rowCount, lines: [])
        }
        guard data.count >= 36 else {
            throw EditorCommandError("Invalid viewport blob: header too small (\(data.count) bytes)")
        }

        let lineCount = try Int(data.readU32LE(at: 8))
        let cellCount = try Int(data.readU32LE(at: 12))
        let styleIDCount = try Int(data.readU32LE(at: 16))
        let linesOffset = try Int(data.readU32LE(at: 20))
        let cellsOffset = try Int(data.readU32LE(at: 24))
        let stylesOffset = try Int(data.readU32LE(at: 28))

        guard linesOffset <= cellsOffset, cellsOffset <= stylesOffset, stylesOffset <= data.count else {
            throw EditorCommandError("Invalid viewport blob offsets")
        }

        let lineRecordSize = lineCount == 0 ? 28 : (cellsOffset - linesOffset) / max(lineCount, 1)
        let cellRecordSize = cellCount == 0 ? 12 : (stylesOffset - cellsOffset) / max(cellCount, 1)
        if lineCount > 0 && lineRecordSize < 28 {
            throw EditorCommandError("Invalid viewport blob line record size: \(lineRecordSize)")
        }
        if cellCount > 0 && cellRecordSize < 12 {
            throw EditorCommandError("Invalid viewport blob cell record size: \(cellRecordSize)")
        }

        var styleIDs: [UInt32] = []
        styleIDs.reserveCapacity(styleIDCount)
        for i in 0..<styleIDCount {
            let off = stylesOffset + (i * 4)
            styleIDs.append(try data.readU32LE(at: off))
        }

        var cells: [BlobCell] = []
        cells.reserveCapacity(cellCount)
        for i in 0..<cellCount {
            let base = cellsOffset + (i * cellRecordSize)
            let scalarValue = try data.readU32LE(at: base)
            let width = try data.readU16LE(at: base + 4)
            let styleCount = try data.readU16LE(at: base + 6)
            let styleStartIndex = try data.readU32LE(at: base + 8)

            cells.append(
                BlobCell(
                    scalarValue: scalarValue,
                    width: Int(width),
                    styleCount: Int(styleCount),
                    styleStartIndex: Int(styleStartIndex)
                )
            )
        }

        var lines: [EditorVisualLine] = []
        lines.reserveCapacity(lineCount)
        for i in 0..<lineCount {
            let base = linesOffset + (i * lineRecordSize)
            let logicalLineIndex = try Int(data.readU32LE(at: base))
            let visualInLogical = try Int(data.readU32LE(at: base + 4))
            let charOffsetStart = try Int(data.readU32LE(at: base + 8))
            let charOffsetEnd = try Int(data.readU32LE(at: base + 12))
            let cellStartIndex = try Int(data.readU32LE(at: base + 16))
            let lineCellCount = try Int(data.readU32LE(at: base + 20))
            let segmentXStartCells = try Int(data.readU16LE(at: base + 24))
            let isWrappedPart = try data.readU8(at: base + 26) != 0
            let isFoldPlaceholderAppended = try data.readU8(at: base + 27) != 0

            let cellEndIndex = cellStartIndex + lineCellCount
            guard cellStartIndex >= 0, cellEndIndex <= cells.count else {
                throw EditorCommandError("Invalid viewport blob cell range for line \(i)")
            }

            let visualCells: [EditorCell] = try cells[cellStartIndex..<cellEndIndex].map { cell in
                guard cell.styleStartIndex + cell.styleCount <= styleIDs.count else {
                    throw EditorCommandError("Invalid viewport blob style range")
                }
                let scalar = UnicodeScalar(cell.scalarValue) ?? UnicodeScalar(0xFFFD)!
                let styles = Array(styleIDs[cell.styleStartIndex..<(cell.styleStartIndex + cell.styleCount)])
                return EditorCell(scalar: scalar, width: cell.width, styleIDs: styles)
            }

            lines.append(
                EditorVisualLine(
                    logicalLineIndex: logicalLineIndex,
                    visualInLogical: visualInLogical,
                    charOffsetStart: charOffsetStart,
                    charOffsetEnd: charOffsetEnd,
                    segmentXStartCells: segmentXStartCells,
                    isWrappedPart: isWrappedPart,
                    isFoldPlaceholderAppended: isFoldPlaceholderAppended,
                    cells: visualCells
                )
            )
        }

        return EditorSnapshot(
            startVisualRow: request.startVisualRow,
            requestedCount: request.rowCount,
            lines: lines
        )
    }

    private func deriveStyleSpans(from snapshot: EditorSnapshot, in range: Range<Int>) -> [EditorStyleSpan] {
        if snapshot.lines.isEmpty || range.isEmpty {
            return []
        }

        var spans: [EditorStyleSpan] = []
        var active: [UInt32: Int] = [:]
        var currentOffset = range.lowerBound

        func closeStyle(_ styleID: UInt32, endOffset: Int) {
            guard let start = active.removeValue(forKey: styleID), endOffset > start else {
                return
            }
            spans.append(EditorStyleSpan(startOffset: start, endOffset: endOffset, styleID: styleID))
        }

        func closeAll(endOffset: Int) {
            for styleID in Array(active.keys) {
                closeStyle(styleID, endOffset: endOffset)
            }
        }

        let sortedLines = snapshot.lines.sorted {
            if $0.charOffsetStart == $1.charOffsetStart {
                return $0.visualInLogical < $1.visualInLogical
            }
            return $0.charOffsetStart < $1.charOffsetStart
        }

        for line in sortedLines {
            if currentOffset >= range.upperBound {
                break
            }

            let lineStart = line.charOffsetStart
            if lineStart > currentOffset {
                closeAll(endOffset: min(lineStart, range.upperBound))
                currentOffset = lineStart
            }

            for (idx, cell) in line.cells.enumerated() {
                let offset = line.charOffsetStart + idx
                if offset < range.lowerBound {
                    continue
                }
                if offset >= range.upperBound {
                    closeAll(endOffset: range.upperBound)
                    currentOffset = range.upperBound
                    break
                }

                if offset > currentOffset {
                    closeAll(endOffset: offset)
                    currentOffset = offset
                }

                let currentStyles = Set(cell.styleIDs)
                for (styleID, _) in active where !currentStyles.contains(styleID) {
                    closeStyle(styleID, endOffset: offset)
                }
                for styleID in currentStyles where active[styleID] == nil {
                    active[styleID] = offset
                }
                currentOffset = offset + 1
            }

            let lineEnd = min(line.charOffsetEnd, range.upperBound)
            if lineEnd >= currentOffset {
                closeAll(endOffset: lineEnd)
                currentOffset = lineEnd
            }
        }

        closeAll(endOffset: range.upperBound)
        return spans.sorted {
            if $0.startOffset == $1.startOffset {
                if $0.endOffset == $1.endOffset {
                    return $0.styleID < $1.styleID
                }
                return $0.endOffset < $1.endOffset
            }
            return $0.startOffset < $1.startOffset
        }
    }

    private func deriveInlays(from grid: ComposedGridDTO, in range: Range<Int>) -> [EditorInlay] {
        var inlays: [EditorInlay] = []
        for line in grid.lines {
            let lineKind = line.kind.kind
            let runs = virtualRuns(from: line.cells)
            guard !runs.isEmpty else {
                continue
            }

            for run in runs {
                guard !run.text.isEmpty else {
                    continue
                }
                guard !(run.styleIDs.count == 1 && run.styleIDs[0] == 0x0300_0001) else {
                    continue // fold placeholder virtual text
                }
                guard range.contains(run.anchorOffset) || run.anchorOffset == range.upperBound else {
                    continue
                }

                let placement: EditorInlayPlacement = lineKind == "virtual_above_line" ? .aboveLine : .after
                inlays.append(
                    EditorInlay(
                        offset: run.anchorOffset,
                        text: run.text,
                        placement: placement,
                        styleIDs: run.styleIDs
                    )
                )
            }
        }
        return inlays
    }

    private func virtualRuns(from cells: [ComposedCellDTO]) -> [VirtualRun] {
        var runs: [VirtualRun] = []
        var current: VirtualRun?

        func flush() {
            if let current {
                runs.append(current)
            }
            current = nil
        }

        for cell in cells {
            guard cell.source.kind == "virtual",
                  let anchorOffset = cell.source.anchorOffset else {
                flush()
                continue
            }

            let scalar = cell.ch.unicodeScalars.first.map(String.init) ?? ""
            if var existing = current, existing.anchorOffset == anchorOffset {
                existing.text += scalar
                for style in cell.styles where !existing.styleIDs.contains(style) {
                    existing.styleIDs.append(style)
                }
                current = existing
            } else {
                flush()
                current = VirtualRun(anchorOffset: anchorOffset, text: scalar, styleIDs: cell.styles)
            }
        }
        flush()
        return runs
    }

    private func ensureStatus(_ status: Int32, context: String) throws {
        if status == EditorCoreFFIStatusCode.ok.rawValue {
            return
        }
        throw commandError(context: context, status: status)
    }

    private func commandError(context: String, status: Int32? = nil) -> EditorCommandError {
        let suffix = status.map { " (status=\($0))" } ?? ""
        let detail = ffi.lastErrorMessage()
        if detail.isEmpty {
            return EditorCommandError("\(context) failed\(suffix)")
        }
        return EditorCommandError("\(context) failed\(suffix): \(detail)")
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from json: String, context: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw EditorCommandError("Failed to decode UTF-8 JSON for \(context)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw EditorCommandError("Failed to parse JSON for \(context): \(error)")
        }
    }

    private func commandJSONPayload(_ command: EditorCommand) throws -> [String: Any] {
        switch command {
        case .insertTab:
            return ["kind": "edit", "op": "insert_tab"]
        case .insertNewline(let autoIndent):
            return ["kind": "edit", "op": "insert_newline", "auto_indent": autoIndent]
        case .moveWordLeft:
            return ["kind": "cursor", "op": "move_word_left"]
        case .moveWordRight:
            return ["kind": "cursor", "op": "move_word_right"]
        case .setViewportWidth(let width):
            return ["kind": "view", "op": "set_viewport_width", "width": max(1, width)]
        case .setWrapMode(let mode):
            return [
                "kind": "view",
                "op": "set_wrap_mode",
                "mode": wrapModeString(mode)
            ]
        case .setWrapIndent(let indent):
            return [
                "kind": "view",
                "op": "set_wrap_indent",
                "indent": wrapIndentObject(indent)
            ]
        case .setTabWidth(let width):
            return [
                "kind": "view",
                "op": "set_tab_width",
                "width": max(1, width)
            ]
        case .setTabKeyBehavior(let behavior):
            return [
                "kind": "view",
                "op": "set_tab_key_behavior",
                "behavior": behavior == .spaces ? "spaces" : "tab"
            ]
        case .fold(let startLine, let endLine):
            return [
                "kind": "style",
                "op": "fold",
                "start_line": max(0, startLine),
                "end_line": max(0, endLine)
            ]
        case .unfold(let startLine):
            return [
                "kind": "style",
                "op": "unfold",
                "start_line": max(0, startLine)
            ]
        case .unfoldAll:
            return ["kind": "style", "op": "unfold_all"]
        case .replaceCurrent(let query, let replacement, let options):
            return [
                "kind": "edit",
                "op": "replace_current",
                "query": query,
                "replacement": replacement,
                "options": searchOptionsObject(options)
            ]
        case .replaceAll(let query, let replacement, let options):
            return [
                "kind": "edit",
                "op": "replace_all",
                "query": query,
                "replacement": replacement,
                "options": searchOptionsObject(options)
            ]
        case .applyTextEdits(let edits):
            let payload = edits.map { edit in
                [
                    "start": max(0, edit.startOffset),
                    "end": max(0, edit.endOffset),
                    "text": edit.replacementText
                ]
            }
            return ["kind": "edit", "op": "apply_text_edits", "edits": payload]

        default:
            throw EditorCommandError("Command not supported by JSON fallback: \(command)")
        }
    }

    private func wrapModeString(_ mode: EditorWrapMode) -> String {
        switch mode {
        case .none: return "none"
        case .char: return "char"
        case .word: return "word"
        }
    }

    private func wrapIndentObject(_ indent: EditorWrapIndent) -> [String: Any] {
        switch indent {
        case .none:
            return ["kind": "none"]
        case .sameAsLineIndent:
            return ["kind": "same_as_line_indent"]
        case .fixedCells(let cells):
            return ["kind": "fixed_cells", "cells": max(0, cells)]
        }
    }

    private func searchOptionsObject(_ options: EditorSearchOptions) -> [String: Any] {
        [
            "case_sensitive": options.caseSensitive,
            "whole_word": options.wholeWord,
            "regex": options.regex
        ]
    }

    private func applyDiagnosticsCacheDelta(from editsJSON: String) {
        guard let data = editsJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return
        }

        let items: [Any]
        if let array = raw as? [Any] {
            items = array
        } else {
            items = [raw]
        }

        for item in items {
            guard let dict = item as? [String: Any],
                  let op = dict["op"] as? String else {
                continue
            }
            switch op {
            case "replace_diagnostics":
                let diagnostics = (dict["diagnostics"] as? [[String: Any]]) ?? []
                diagnosticsCache = .init(items: diagnostics.compactMap(Self.parseDiagnosticItem))
            case "clear_diagnostics":
                diagnosticsCache = .init(items: [])
            default:
                break
            }
        }
    }

    private static func parseDiagnosticItem(_ raw: [String: Any]) -> EditorDiagnosticsSnapshot.Item? {
        guard let range = raw["range"] as? [String: Any],
              let start = range["start"] as? Int,
              let end = range["end"] as? Int,
              let message = raw["message"] as? String else {
            return nil
        }
        let severity = (raw["severity"] as? String) ?? "info"
        return .init(startOffset: start, endOffset: end, severity: severity, message: message)
    }

    private func clampedU32(_ value: Int) -> UInt32 {
        if value < 0 {
            return 0
        }
        return UInt32(clamping: value)
    }

    private func clampedI32(_ value: Int) -> Int32 {
        if value > Int(Int32.max) {
            return Int32.max
        }
        if value < Int(Int32.min) {
            return Int32.min
        }
        return Int32(value)
    }
}

public final class EditorCoreFFILSPBridge {
    private let ffi: EditorCoreFFILibrary

    public init(libraryPath: String? = nil, library: EditorCoreFFILibrary? = nil) throws {
        if let library {
            self.ffi = library
        } else {
            self.ffi = try EditorCoreFFILibrary(path: libraryPath)
        }
    }

    public func pathToFileURI(_ path: String) throws -> String {
        try convertJSONValue(path, using: ffi.lspPathToFileURIFn, key: "uri")
    }

    public func fileURIToPath(_ uri: String) throws -> String {
        try convertJSONValue(uri, using: ffi.lspFileURIToPathFn, key: "path")
    }

    public func percentEncodePath(_ path: String) throws -> String {
        try convertJSONValue(path, using: ffi.lspPercentEncodePathFn, key: "encoded")
    }

    public func percentDecodePath(_ encodedPath: String) throws -> String {
        try convertJSONValue(encodedPath, using: ffi.lspPercentDecodePathFn, key: "decoded")
    }

    public func charOffsetToUTF16(lineText: String, charOffset: Int) -> Int {
        lineText.withCString { ptr in
            ffi.lspCharOffsetToUTF16Fn(ptr, max(0, charOffset))
        }
    }

    public func utf16OffsetToCharOffset(lineText: String, utf16Offset: Int) -> Int {
        lineText.withCString { ptr in
            ffi.lspUTF16ToCharOffsetFn(ptr, max(0, utf16Offset))
        }
    }

    private func convertJSONValue(
        _ value: String,
        using fn: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?,
        key: String
    ) throws -> String {
        let ptr = value.withCString { fn($0) }
        let json = try ffi.takeOwnedCString(ptr)
        guard let data = json.data(using: .utf8),
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extracted = raw[key] as? String else {
            throw EditorCommandError("Failed to parse LSP JSON response for key '\(key)'")
        }
        return extracted
    }
}

public final class EditorCoreFFISublimeProcessor {
    private let ffi: EditorCoreFFILibrary
    private let handle: UnsafeMutableRawPointer

    public init(yaml: String, libraryPath: String? = nil, library: EditorCoreFFILibrary? = nil) throws {
        let resolvedLibrary: EditorCoreFFILibrary
        if let library {
            resolvedLibrary = library
        } else {
            resolvedLibrary = try EditorCoreFFILibrary(path: libraryPath)
        }
        self.ffi = resolvedLibrary
        let handle = yaml.withCString { resolvedLibrary.sublimeProcessorNewFromYAMLFn($0) }
        guard let handle else {
            throw EditorCommandError("Failed to create Sublime processor: \(resolvedLibrary.lastErrorMessage())")
        }
        self.handle = handle
    }

    public init(path: String, libraryPath: String? = nil, library: EditorCoreFFILibrary? = nil) throws {
        let resolvedLibrary: EditorCoreFFILibrary
        if let library {
            resolvedLibrary = library
        } else {
            resolvedLibrary = try EditorCoreFFILibrary(path: libraryPath)
        }
        self.ffi = resolvedLibrary
        let handle = path.withCString { resolvedLibrary.sublimeProcessorNewFromPathFn($0) }
        guard let handle else {
            throw EditorCommandError("Failed to create Sublime processor: \(resolvedLibrary.lastErrorMessage())")
        }
        self.handle = handle
    }

    deinit {
        ffi.sublimeProcessorFreeFn(handle)
    }

    public func setActiveSyntax(reference: String) throws {
        let ok = reference.withCString { ffi.sublimeSetActiveSyntaxByReferenceFn(handle, $0) }
        if !ok {
            throw EditorCommandError("Failed to set active syntax: \(ffi.lastErrorMessage())")
        }
    }

    public func apply(to engine: EditorCoreFFIEngine) throws {
        let ok = ffi.sublimeProcessorApplyFn(handle, engine.stateHandle)
        if !ok {
            throw EditorCommandError("Failed to apply Sublime processor: \(ffi.lastErrorMessage())")
        }
    }

    public func processJSON(with engine: EditorCoreFFIEngine) throws -> String {
        let ptr = ffi.sublimeProcessorProcessJSONFn(handle, engine.stateHandle)
        return try ffi.takeOwnedCString(ptr)
    }

    public func scopeForStyleID(_ styleID: UInt32) throws -> String {
        let ptr = ffi.sublimeScopeForStyleIDFn(handle, styleID)
        return try ffi.takeOwnedCString(ptr)
    }
}

public final class EditorCoreFFITreeSitterProcessor {
    private let ffi: EditorCoreFFILibrary
    private let handle: UnsafeMutableRawPointer

    public init(
        languageFn: @escaping EditorCoreFFILibrary.FnTreeSitterLanguageFn,
        highlightsQuery: String? = nil,
        foldsQuery: String? = nil,
        captureStylesJSON: String? = nil,
        styleLayer: UInt32 = 0x0001_0000,
        preserveCollapsedFolds: Bool = true,
        libraryPath: String? = nil,
        library: EditorCoreFFILibrary? = nil
    ) throws {
        let resolvedLibrary: EditorCoreFFILibrary
        if let library {
            resolvedLibrary = library
        } else {
            resolvedLibrary = try EditorCoreFFILibrary(path: libraryPath)
        }
        self.ffi = resolvedLibrary
        let handle = try withOptionalCString(highlightsQuery) { highlightsPtr in
            try withOptionalCString(foldsQuery) { foldsPtr in
                try withOptionalCString(captureStylesJSON) { stylesPtr in
                    guard let ptr = resolvedLibrary.treeSitterProcessorNewFn(
                        languageFn,
                        highlightsPtr,
                        foldsPtr,
                        stylesPtr,
                        styleLayer,
                        preserveCollapsedFolds
                    ) else {
                        throw EditorCommandError(
                            "Failed to create Tree-sitter processor: \(resolvedLibrary.lastErrorMessage())"
                        )
                    }
                    return ptr
                }
            }
        }
        self.handle = handle
    }

    deinit {
        ffi.treeSitterProcessorFreeFn(handle)
    }

    public func apply(to engine: EditorCoreFFIEngine) throws {
        let ok = ffi.treeSitterProcessorApplyFn(handle, engine.stateHandle)
        if !ok {
            throw EditorCommandError("Failed to apply Tree-sitter processor: \(ffi.lastErrorMessage())")
        }
    }

    public func processJSON(with engine: EditorCoreFFIEngine) throws -> String {
        let ptr = ffi.treeSitterProcessorProcessJSONFn(handle, engine.stateHandle)
        return try ffi.takeOwnedCString(ptr)
    }

    public func lastUpdateModeJSON() throws -> String {
        let ptr = ffi.treeSitterProcessorLastUpdateModeJSONFn(handle)
        return try ffi.takeOwnedCString(ptr)
    }
}

private extension EditorCoreFFIEngine {
    struct BlobCell {
        var scalarValue: UInt32
        var width: Int
        var styleCount: Int
        var styleStartIndex: Int
    }

    struct VirtualRun {
        var anchorOffset: Int
        var text: String
        var styleIDs: [UInt32]
    }

    struct TextEnvelopeDTO: Decodable {
        var text: String
    }

    struct FullStateDTO: Decodable {
        struct DocumentDTO: Decodable {
            var lineCount: Int
            var charCount: Int
            var byteCount: Int
            var isModified: Bool
            var version: Int
        }

        struct PositionDTO: Decodable {
            var line: Int
            var column: Int
        }

        struct SelectionDTO: Decodable {
            var start: PositionDTO
            var end: PositionDTO
            var direction: String
        }

        struct CursorDTO: Decodable {
            var position: PositionDTO
            var selections: [SelectionDTO]
            var primarySelectionIndex: Int
        }

        struct FoldRegionDTO: Decodable {
            var startLine: Int
            var endLine: Int
            var isCollapsed: Bool
            var placeholder: String
        }

        struct FoldingDTO: Decodable {
            var regions: [FoldRegionDTO]
        }

        struct ViewportDTO: Decodable {
            var totalVisualLines: Int
        }

        var document: DocumentDTO
        var cursor: CursorDTO
        var folding: FoldingDTO
        var viewport: ViewportDTO
    }

    struct CommandResultDTO: Decodable {
        struct PositionDTO: Decodable {
            var line: Int
            var column: Int
        }

        var kind: String
        var text: String?
        var position: PositionDTO?
        var offset: Int?
        var start: Int?
        var end: Int?
        var replaced: Int?

        var asCommandResult: EditorCommandResult {
            switch kind {
            case "success":
                return .success
            case "text":
                return .text(text ?? "")
            case "position":
                let p = position ?? .init(line: 0, column: 0)
                return .position(.init(line: p.line, column: p.column))
            case "offset":
                return .offset(offset ?? 0)
            case "search_match":
                return .searchMatch(startOffset: start ?? 0, endOffset: end ?? 0)
            case "search_not_found":
                return .searchNotFound
            case "replace_result":
                return .replaceResult(count: replaced ?? 0)
            default:
                return .success
            }
        }
    }

    struct MinimapGridDTO: Decodable {
        struct MinimapLineDTO: Decodable {
            var logicalLineIndex: Int
            var visualInLogical: Int
            var totalCells: Int
            var nonWhitespaceCells: Int
            var dominantStyle: UInt32?
        }

        var startVisualRow: Int
        var count: Int
        var lines: [MinimapLineDTO]
    }

    struct ComposedGridDTO: Decodable {
        struct ComposedLineKindDTO: Decodable {
            var kind: String
            var logicalLine: Int?
            var visualInLogical: Int?
        }

        struct ComposedCellSourceDTO: Decodable {
            var kind: String
            var offset: Int?
            var anchorOffset: Int?
        }

        struct ComposedCellDTO: Decodable {
            var ch: String
            var width: Int
            var styles: [UInt32]
            var source: ComposedCellSourceDTO
        }

        struct ComposedLineDTO: Decodable {
            var kind: ComposedLineKindDTO
            var cells: [ComposedCellDTO]
        }

        var startVisualRow: Int
        var count: Int
        var lines: [ComposedLineDTO]
    }

    typealias ComposedLineDTO = ComposedGridDTO.ComposedLineDTO
    typealias ComposedCellDTO = ComposedGridDTO.ComposedCellDTO
}

private extension Data {
    func readU8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < count else {
            throw EditorCommandError("Viewport blob out-of-bounds read (u8 at \(offset))")
        }
        return self[offset]
    }

    func readU16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw EditorCommandError("Viewport blob out-of-bounds read (u16 at \(offset))")
        }
        let raw = self[offset..<(offset + 2)]
        return raw.withUnsafeBytes { ptr in
            UInt16(littleEndian: ptr.load(as: UInt16.self))
        }
    }

    func readU32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw EditorCommandError("Viewport blob out-of-bounds read (u32 at \(offset))")
        }
        let raw = self[offset..<(offset + 4)]
        return raw.withUnsafeBytes { ptr in
            UInt32(littleEndian: ptr.load(as: UInt32.self))
        }
    }
}

private func withOptionalCString<T>(
    _ value: String?,
    body: (UnsafePointer<CChar>?) throws -> T
) throws -> T {
    guard let value else {
        return try body(nil)
    }
    return try value.withCString { ptr in
        try body(ptr)
    }
}
