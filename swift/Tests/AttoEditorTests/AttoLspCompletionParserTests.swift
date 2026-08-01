import EditorCoreUIFFI
@testable import AttoEditor
import XCTest

final class AttoLspCompletionParserTests: XCTestCase {
    func testCompletionListParsesItemsAndDisplayTitle() throws {
        let json = """
        {
          "isIncomplete": false,
          "items": [
            {
              "label": "print",
              "kind": 3,
              "detail": "(value: Any)"
            },
            {
              "label": "private",
              "kind": 14
            }
          ]
        }
        """

        let items = AttoLspCompletionParser.items(fromCompletionResultJSON: json)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].label, "print")
        XCTAssertEqual(items[0].kindLabel, "Function")
        XCTAssertEqual(AttoLspCompletionParser.displayTitle(for: items[0]), "print  [Function] (value: Any)")
        XCTAssertEqual(AttoLspCompletionParser.displayTitle(for: items[1]), "private  [Keyword]")
    }

    func testArrayCompletionResultParsesItems() throws {
        let items = AttoLspCompletionParser.items(fromCompletionResultJSON: #"[{"label":"abc"}]"#)
        XCTAssertEqual(items.map(\.label), ["abc"])
    }

    func testResolvedCompletionItemSerializesAndAddsEditsToPlan() throws {
        let unresolved = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: #"[{"label":"foo","data":{"id":1}}]"#).first)
        XCTAssertNotNil(AttoLspCompletionParser.rawJSON(for: unresolved))

        let resolvedJSON = """
        {
          "label": "foo",
          "insertText": "foo()",
          "additionalTextEdits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "import Foo\\n"
            }
          ]
        }
        """
        let resolved = try XCTUnwrap(AttoLspCompletionParser.item(fromCompletionItemJSON: resolvedJSON))
        let plan = try XCTUnwrap(AttoLspCompletionParser.applicationPlan(
            for: resolved,
            documentText: "fo",
            fallbackStart: 0,
            fallbackEnd: 2
        ))

        XCTAssertEqual(plan.start, 0)
        XCTAssertEqual(plan.end, 2)
        XCTAssertEqual(plan.text, "foo()")
        XCTAssertEqual(plan.additionalEdits, [EcuTextEdit(start: 0, end: 0, text: "import Foo\n")])
    }

    func testApplicationPlanUsesTextEditAndAdditionalTextEdits() throws {
        let json = """
        [
          {
            "label": "bar",
            "textEdit": {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 3 }
              },
              "newText": "bar()"
            },
            "additionalTextEdits": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "import x\\n"
              }
            ]
          }
        ]
        """
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: json).first)
        let plan = try XCTUnwrap(AttoLspCompletionParser.applicationPlan(
            for: item,
            documentText: "abc\nfoo\n",
            fallbackStart: 7,
            fallbackEnd: 7
        ))

        XCTAssertEqual(plan.start, 4)
        XCTAssertEqual(plan.end, 7)
        XCTAssertEqual(plan.text, "bar()")
        XCTAssertFalse(plan.isSnippet)
        XCTAssertEqual(plan.additionalEdits, [EcuTextEdit(start: 0, end: 0, text: "import x\n")])
    }

    func testApplicationPlanUsesInsertRangeForInsertReplaceEdit() throws {
        let json = """
        [
          {
            "label": "foobar",
            "textEdit": {
              "insert": {
                "start": { "line": 0, "character": 3 },
                "end": { "line": 0, "character": 6 }
              },
              "replace": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 6 }
              },
              "newText": "foobar"
            }
          }
        ]
        """
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: json).first)
        let plan = try XCTUnwrap(AttoLspCompletionParser.applicationPlan(
            for: item,
            documentText: "foobaz",
            fallbackStart: 0,
            fallbackEnd: 6
        ))

        XCTAssertEqual(plan.start, 3)
        XCTAssertEqual(plan.end, 6)
        XCTAssertEqual(plan.text, "foobar")
    }

    func testSnippetFallbackReplacesIdentifierPrefix() throws {
        let json = """
        [
          {
            "label": "print",
            "insertText": "print(${1:value})$0",
            "insertTextFormat": 2
          }
        ]
        """
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: json).first)
        let fallback = AttoLspCompletionParser.identifierFallbackRange(in: "pri", caretOffset: 3)
        let plan = try XCTUnwrap(AttoLspCompletionParser.applicationPlan(
            for: item,
            documentText: "pri",
            fallbackStart: fallback.start,
            fallbackEnd: fallback.end
        ))

        XCTAssertEqual(plan.start, 0)
        XCTAssertEqual(plan.end, 3)
        XCTAssertEqual(plan.text, "print(${1:value})$0")
        XCTAssertTrue(plan.isSnippet)
    }
}
