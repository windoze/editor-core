import Foundation

public final class MockEditorEngine: EditorEngineProtocol {
    public private(set) var text: String

    private var selection: EditorSelection?
    private var version: UInt64 = 0
    public var styleSpanData: [EditorStyleSpan]
    public var inlayData: [EditorInlay]
    public var foldRegionData: [EditorFoldRegion]
    public var diagnosticsData: EditorDiagnosticsSnapshot

    public init(
        text: String = "",
        styleSpanData: [EditorStyleSpan] = [],
        inlayData: [EditorInlay] = [],
        foldRegionData: [EditorFoldRegion] = [],
        diagnosticsData: EditorDiagnosticsSnapshot = .init(items: [])
    ) {
        self.text = text
        self.styleSpanData = styleSpanData
        self.inlayData = inlayData
        self.foldRegionData = foldRegionData
        self.diagnosticsData = diagnosticsData
    }

    public func documentState() throws -> EditorDocumentState {
        let lines = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return EditorDocumentState(
            lineCount: lines,
            charCount: text.count,
            byteCount: text.utf8.count,
            isModified: version > 0,
            version: version
        )
    }

    public func cursorState() throws -> EditorCursorState {
        let pos = EditorPosition(line: 0, column: 0)
        let selections = selection.map { [$0] } ?? []
        return EditorCursorState(position: pos, selections: selections, primarySelectionIndex: 0)
    }

    public func execute(_ command: EditorCommand) throws -> EditorCommandResult {
        switch command {
        case .insertText(let inserted):
            text += inserted
            version &+= 1
            return .success
        case .insertTab:
            text += "\t"
            version &+= 1
            return .success
        case .insertNewline:
            text += "\n"
            version &+= 1
            return .success
        case .backspace:
            if !text.isEmpty {
                text.removeLast()
                version &+= 1
            }
            return .success
        case .fold(let startLine, let endLine):
            if let index = foldRegionData.firstIndex(where: { $0.startLine == startLine }) {
                foldRegionData[index].endLine = endLine
                foldRegionData[index].isCollapsed = true
            } else {
                foldRegionData.append(
                    EditorFoldRegion(
                        startLine: startLine,
                        endLine: endLine,
                        isCollapsed: true
                    )
                )
            }
            version &+= 1
            return .success
        case .unfold(let startLine):
            if let index = foldRegionData.firstIndex(where: { $0.startLine == startLine }) {
                foldRegionData[index].isCollapsed = false
            }
            version &+= 1
            return .success
        case .unfoldAll:
            for index in foldRegionData.indices {
                foldRegionData[index].isCollapsed = false
            }
            version &+= 1
            return .success
        case .deleteForward,
             .undo,
             .redo,
             .moveTo,
             .moveBy,
             .moveWordLeft,
             .moveWordRight,
             .setViewportWidth,
             .setWrapMode,
             .setWrapIndent,
             .setTabWidth,
             .setTabKeyBehavior,
             .replaceCurrent,
             .replaceAll,
             .applyTextEdits,
             .custom:
            return .success
        case .setSelection(let selection):
            self.selection = selection
            return .success
        case .clearSelection:
            selection = nil
            return .success
        }
    }

    public func styledViewport(_ request: EditorViewportRequest) throws -> EditorSnapshot {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = max(request.startVisualRow, 0)
        let end = min(start + max(request.rowCount, 0), lines.count)
        var visualLines: [EditorVisualLine] = []

        var charOffset = 0
        for (idx, line) in lines.enumerated() {
            let lineString = String(line)
            let chars = Array(lineString.unicodeScalars)
            let endOffset = charOffset + chars.count
            if idx >= start && idx < end {
                let cells = chars.map { scalar in
                    EditorCell(scalar: scalar, width: 1, styleIDs: [])
                }
                visualLines.append(
                    EditorVisualLine(
                        logicalLineIndex: idx,
                        visualInLogical: 0,
                        charOffsetStart: charOffset,
                        charOffsetEnd: endOffset,
                        segmentXStartCells: 0,
                        isWrappedPart: false,
                        isFoldPlaceholderAppended: false,
                        cells: cells
                    )
                )
            }
            charOffset = endOffset + 1
        }

        return EditorSnapshot(startVisualRow: start, requestedCount: request.rowCount, lines: visualLines)
    }

    public func minimapViewport(_ request: EditorViewportRequest) throws -> EditorMinimapSnapshot {
        let snapshot = try styledViewport(request)
        let lines = snapshot.lines.map { line in
            EditorMinimapLine(
                logicalLineIndex: line.logicalLineIndex,
                visualInLogical: line.visualInLogical,
                totalCells: line.cells.count,
                nonWhitespaceCells: line.cells.filter { !$0.scalar.properties.isWhitespace }.count,
                dominantStyle: nil
            )
        }
        return EditorMinimapSnapshot(
            startVisualRow: snapshot.startVisualRow,
            requestedCount: snapshot.requestedCount,
            lines: lines
        )
    }

    public func styleSpans(in range: Range<Int>) throws -> [EditorStyleSpan] {
        styleSpanData.filter { span in
            span.startOffset < range.upperBound && span.endOffset > range.lowerBound
        }
    }

    public func inlays(in range: Range<Int>) throws -> [EditorInlay] {
        inlayData.filter { inlay in
            range.contains(inlay.offset) || inlay.offset == range.upperBound
        }
    }

    public func foldRegions() throws -> [EditorFoldRegion] {
        foldRegionData
    }

    public func diagnostics() throws -> EditorDiagnosticsSnapshot {
        diagnosticsData
    }
}
