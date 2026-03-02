import Foundation

struct CommandResultJSON: Decodable {
    let kind: String

    // kind == "viewport"
    let viewport: HeadlessGridJSON?

    // kind == "search_match"
    let start: Int?
    let end: Int?

    // kind == "replace_result"
    let replaced: Int?

    // Unused today but part of ABI
    let text: String?
    let position: PositionJSON?
    let offset: Int?
}

struct HeadlessGridJSON: Decodable {
    let startVisualRow: Int
    let count: Int
    let actualLineCount: Int
    let lines: [HeadlessLineJSON]
}

struct HeadlessLineJSON: Decodable {
    let logicalLineIndex: Int
    let isWrappedPart: Bool
    let visualInLogical: Int
    let charOffsetStart: Int
    let charOffsetEnd: Int
    let segmentXStartCells: Int
    let isFoldPlaceholderAppended: Bool
    let cells: [HeadlessCellJSON]
}

struct HeadlessCellJSON: Decodable {
    let ch: String
    let width: Int
    let styles: [UInt32]
}

struct FullStateJSON: Decodable {
    let document: DocumentStateJSON
    let cursor: CursorStateJSON
    let viewport: ViewportStateJSON
    let undoRedo: UndoRedoStateJSON
    let folding: FoldingStateJSON
    let diagnostics: DiagnosticsStateJSON
    let decorations: DecorationsStateJSON
    let style: StyleStateJSON
}

struct DocumentStateJSON: Decodable {
    let lineCount: Int
    let charCount: Int
    let byteCount: Int
    let isModified: Bool
    let version: UInt64
}

struct CursorStateJSON: Decodable {
    let position: PositionJSON
    let offset: Int
    let multiCursors: [PositionJSON]
    let selection: SelectionJSON?
    let selections: [SelectionJSON]
    let primarySelectionIndex: Int
}

struct PositionJSON: Decodable, Equatable {
    let line: Int
    let column: Int
}

struct SelectionJSON: Decodable {
    let start: PositionJSON
    let end: PositionJSON
    let direction: String
}

struct ViewportStateJSON: Decodable {
    let width: Int
    let height: Int?
    let scrollTop: Int
    let subRowOffset: Int
    let overscanRows: Int
    let visibleLines: RangeJSON
    let prefetchLines: RangeJSON
    let totalVisualLines: Int
}

struct RangeJSON: Decodable {
    let start: Int
    let end: Int
}

struct UndoRedoStateJSON: Decodable {
    let canUndo: Bool
    let canRedo: Bool
    let undoDepth: Int
    let redoDepth: Int
    let currentChangeGroup: Int?
}

struct FoldingStateJSON: Decodable {
    let regions: [FoldRegionJSON]
    let collapsedLineCount: Int
    let visibleLogicalLines: Int
    let totalVisualLines: Int
}

struct FoldRegionJSON: Decodable {
    let startLine: Int
    let endLine: Int
    let isCollapsed: Bool
    let placeholder: String
}

struct DiagnosticsStateJSON: Decodable {
    let diagnosticsCount: Int
}

struct DecorationsStateJSON: Decodable {
    let layerCount: Int
    let decorationCount: Int
}

struct StyleStateJSON: Decodable {
    let styleCount: Int
}
