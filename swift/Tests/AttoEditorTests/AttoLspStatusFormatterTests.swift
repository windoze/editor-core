import XCTest
import EditorCoreUIFFI
@testable import AttoEditor

final class AttoLspStatusFormatterTests: XCTestCase {
    func testFormatsReadyStatusWithServerName() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"ready","server":{"name":"rust-analyzer"}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP rust-analyzer: Ready")
        XCTAssertNil(display.failureDetail)
    }

    func testFormatsIndexingActivityWithPercentage() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"indexing","activity":{"title":"Indexing crates","percentage":42}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP: Indexing crates 42%")
        XCTAssertNil(display.failureDetail)
    }

    func testFormatsWorkspaceRootAndCapabilitySummary() {
        let status = EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: .init(name: "rust-analyzer", version: nil, command: "rust-analyzer", args: []),
            activity: nil,
            detail: nil,
            capabilities: EcuLspCapabilities(
                semanticTokens: true,
                completionItemResolve: true,
                completion: .init(supported: true),
                foldingRanges: true,
                onTypeFormatting: true,
                signatureHelp: .init(supported: true)
            ),
            workspaceFolders: [
                EcuLspWorkspaceFolder(uri: "file:///tmp/editor-core", name: "editor-core"),
                EcuLspWorkspaceFolder(uri: "file:///tmp/fixtures", name: "fixtures"),
            ]
        )

        let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: true)

        XCTAssertEqual(
            display.text,
            "LSP rust-analyzer @ editor-core +1: Ready [semantic, completion, completion resolve, signature, folding, on-type]"
        )
        XCTAssertNil(display.failureDetail)
    }

    func testFormatsFailedStatusWithDetailForHud() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"failed","detail":"formatter exploded","server":{"command":"fake-lsp"}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP fake-lsp: Failed")
        XCTAssertEqual(display.failureDetail, "formatter exploded")
    }

    func testFormatsTypedFailedStatusWithDetailForHud() {
        let status = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: .init(name: nil, version: nil, command: "typed-lsp", args: []),
            activity: nil,
            detail: " typed failure ",
            capabilities: nil
        )

        let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: true)

        XCTAssertEqual(display.text, "LSP typed-lsp: Failed")
        XCTAssertEqual(display.failureDetail, "typed failure")
    }

    func testInvalidStatusJSONFallsBackToEnabledText() {
        let display = AttoLspStatusFormatter.display(statusJSON: "not json", fallbackEnabled: true)

        XCTAssertEqual(display.text, "LSP: on")
        XCTAssertNil(display.failureDetail)
    }
}
