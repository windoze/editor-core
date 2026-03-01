import Foundation

public struct EditorPosition: Equatable, Hashable, Sendable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public enum EditorSelectionDirection: String, Equatable, Hashable, Sendable {
    case forward
    case backward
}

public struct EditorSelection: Equatable, Hashable, Sendable {
    public var start: EditorPosition
    public var end: EditorPosition
    public var direction: EditorSelectionDirection

    public init(start: EditorPosition, end: EditorPosition, direction: EditorSelectionDirection) {
        self.start = start
        self.end = end
        self.direction = direction
    }
}

public struct EditorStyleSpan: Equatable, Hashable, Sendable {
    public var startOffset: Int
    public var endOffset: Int
    public var styleID: UInt32

    public init(startOffset: Int, endOffset: Int, styleID: UInt32) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.styleID = styleID
    }
}

public enum EditorInlayPlacement: String, Equatable, Hashable, Sendable {
    case before
    case after
    case aboveLine
}

public struct EditorInlay: Equatable, Hashable, Sendable {
    public var offset: Int
    public var text: String
    public var placement: EditorInlayPlacement
    public var styleIDs: [UInt32]

    public init(offset: Int, text: String, placement: EditorInlayPlacement, styleIDs: [UInt32] = []) {
        self.offset = offset
        self.text = text
        self.placement = placement
        self.styleIDs = styleIDs
    }
}

public struct EditorFoldRegion: Equatable, Hashable, Sendable {
    public var startLine: Int
    public var endLine: Int
    public var isCollapsed: Bool
    public var placeholder: String

    public init(startLine: Int, endLine: Int, isCollapsed: Bool, placeholder: String = "[...]") {
        self.startLine = startLine
        self.endLine = endLine
        self.isCollapsed = isCollapsed
        self.placeholder = placeholder
    }
}

public struct EditorCell: Equatable, Hashable, Sendable {
    public var scalar: Unicode.Scalar
    public var width: Int
    public var styleIDs: [UInt32]

    public init(scalar: Unicode.Scalar, width: Int, styleIDs: [UInt32] = []) {
        self.scalar = scalar
        self.width = width
        self.styleIDs = styleIDs
    }
}

public struct EditorVisualLine: Equatable, Sendable {
    public var logicalLineIndex: Int
    public var visualInLogical: Int
    public var charOffsetStart: Int
    public var charOffsetEnd: Int
    public var segmentXStartCells: Int
    public var isWrappedPart: Bool
    public var isFoldPlaceholderAppended: Bool
    public var cells: [EditorCell]

    public init(
        logicalLineIndex: Int,
        visualInLogical: Int,
        charOffsetStart: Int,
        charOffsetEnd: Int,
        segmentXStartCells: Int,
        isWrappedPart: Bool,
        isFoldPlaceholderAppended: Bool,
        cells: [EditorCell]
    ) {
        self.logicalLineIndex = logicalLineIndex
        self.visualInLogical = visualInLogical
        self.charOffsetStart = charOffsetStart
        self.charOffsetEnd = charOffsetEnd
        self.segmentXStartCells = segmentXStartCells
        self.isWrappedPart = isWrappedPart
        self.isFoldPlaceholderAppended = isFoldPlaceholderAppended
        self.cells = cells
    }
}

public struct EditorSnapshot: Equatable, Sendable {
    public var startVisualRow: Int
    public var requestedCount: Int
    public var lines: [EditorVisualLine]

    public init(startVisualRow: Int, requestedCount: Int, lines: [EditorVisualLine]) {
        self.startVisualRow = startVisualRow
        self.requestedCount = requestedCount
        self.lines = lines
    }
}

public struct EditorMinimapLine: Equatable, Hashable, Sendable {
    public var logicalLineIndex: Int
    public var visualInLogical: Int
    public var totalCells: Int
    public var nonWhitespaceCells: Int
    public var dominantStyle: UInt32?

    public init(
        logicalLineIndex: Int,
        visualInLogical: Int,
        totalCells: Int,
        nonWhitespaceCells: Int,
        dominantStyle: UInt32?
    ) {
        self.logicalLineIndex = logicalLineIndex
        self.visualInLogical = visualInLogical
        self.totalCells = totalCells
        self.nonWhitespaceCells = nonWhitespaceCells
        self.dominantStyle = dominantStyle
    }
}

public struct EditorMinimapSnapshot: Equatable, Sendable {
    public var startVisualRow: Int
    public var requestedCount: Int
    public var lines: [EditorMinimapLine]

    public init(startVisualRow: Int, requestedCount: Int, lines: [EditorMinimapLine]) {
        self.startVisualRow = startVisualRow
        self.requestedCount = requestedCount
        self.lines = lines
    }
}

public struct EditorDocumentState: Equatable, Hashable, Sendable {
    public var lineCount: Int
    public var charCount: Int
    public var byteCount: Int
    public var isModified: Bool
    public var version: UInt64

    public init(lineCount: Int, charCount: Int, byteCount: Int, isModified: Bool, version: UInt64) {
        self.lineCount = lineCount
        self.charCount = charCount
        self.byteCount = byteCount
        self.isModified = isModified
        self.version = version
    }
}

public struct EditorCursorState: Equatable, Hashable, Sendable {
    public var position: EditorPosition
    public var selections: [EditorSelection]
    public var primarySelectionIndex: Int

    public init(position: EditorPosition, selections: [EditorSelection], primarySelectionIndex: Int) {
        self.position = position
        self.selections = selections
        self.primarySelectionIndex = primarySelectionIndex
    }
}

public struct EditorViewportRequest: Equatable, Hashable, Sendable {
    public var startVisualRow: Int
    public var rowCount: Int

    public init(startVisualRow: Int, rowCount: Int) {
        self.startVisualRow = startVisualRow
        self.rowCount = rowCount
    }
}

public struct EditorDiagnosticsSnapshot: Equatable, Sendable {
    public struct Item: Equatable, Hashable, Sendable {
        public var startOffset: Int
        public var endOffset: Int
        public var severity: String
        public var message: String

        public init(startOffset: Int, endOffset: Int, severity: String, message: String) {
            self.startOffset = startOffset
            self.endOffset = endOffset
            self.severity = severity
            self.message = message
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}
