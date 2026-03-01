import Foundation

public protocol EditorEngineProtocol: AnyObject {
    var text: String { get }

    func documentState() throws -> EditorDocumentState
    func cursorState() throws -> EditorCursorState

    func execute(_ command: EditorCommand) throws -> EditorCommandResult

    func styledViewport(_ request: EditorViewportRequest) throws -> EditorSnapshot
    func minimapViewport(_ request: EditorViewportRequest) throws -> EditorMinimapSnapshot

    func styleSpans(in range: Range<Int>) throws -> [EditorStyleSpan]
    func inlays(in range: Range<Int>) throws -> [EditorInlay]
    func foldRegions() throws -> [EditorFoldRegion]
    func diagnostics() throws -> EditorDiagnosticsSnapshot
}

public protocol EditorEngineFactoryProtocol: AnyObject {
    func makeEngine(initialText: String, viewportWidth: Int) throws -> EditorEngineProtocol
}
