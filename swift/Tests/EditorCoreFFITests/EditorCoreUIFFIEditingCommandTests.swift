import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testParagraphSelectionAPIs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        try ui.selectParagraph(atCharOffset: 0)
        let p1 = try ui.selectionOffsets()
        XCTAssertEqual(p1.start, 0)
        XCTAssertEqual(p1.end, 6) // "aa\nbb\n"

        try ui.selectParagraph(atCharOffset: 6)
        let blank = try ui.selectionOffsets()
        XCTAssertEqual(blank.start, 6)
        XCTAssertEqual(blank.end, 7) // the blank line's newline

        try ui.selectParagraph(atCharOffset: 8)
        let p2 = try ui.selectionOffsets()
        XCTAssertEqual(p2.start, 7)
        XCTAssertEqual(p2.end, 12) // "cc\ndd"

        // Union selection: from first paragraph into second paragraph.
        try ui.setParagraphSelection(anchorOffset: 0, activeOffset: 8)
        let u = try ui.selectionOffsets()
        XCTAssertEqual(u.start, 0)
        XCTAssertEqual(u.end, 12)
    }

    func testLineSelectionOffsetsAPI() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        // Anchor in line 0, drag into line 3 (inside "cc").
        try ui.setLineSelection(anchorOffset: 0, activeOffset: 8)
        let a = try ui.selectionOffsets()
        XCTAssertEqual(a.start, 0)
        XCTAssertEqual(a.end, 10) // "aa\nbb\n\ncc\n"

        // Reverse direction should produce the same range.
        try ui.setLineSelection(anchorOffset: 8, activeOffset: 0)
        let b = try ui.selectionOffsets()
        XCTAssertEqual(b.start, 0)
        XCTAssertEqual(b.end, 10)

        // Last line has no trailing newline.
        try ui.setLineSelection(anchorOffset: 10, activeOffset: 11)
        let last = try ui.selectionOffsets()
        XCTAssertEqual(last.start, 10)
        XCTAssertEqual(last.end, 12)
    }

    func testExpandSelectionByWordAPI() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "one two three", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        try ui.expandSelectionBy(unit: .word, count: 2, direction: .forward)
        let s1 = try ui.selectionOffsets()
        XCTAssertEqual(s1.start, 4)
        XCTAssertEqual(s1.end, 13)

        // Expand-only: changing direction extends the other end without shrinking.
        try ui.expandSelectionBy(unit: .word, count: 1, direction: .backward)
        let s2 = try ui.selectionOffsets()
        XCTAssertEqual(s2.start, 0)
        XCTAssertEqual(s2.end, 13)
    }

    func testWordBoundaryConfigAffectsSelectWord() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo-bar", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s1 = try ui.selectionOffsets()
        XCTAssertEqual(s1.start, 0)
        XCTAssertEqual(s1.end, 3)

        // Make '-' a word char by not including it in the boundary set.
        try ui.setWordBoundaryAsciiBoundaryChars(".")
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s2 = try ui.selectionOffsets()
        XCTAssertEqual(s2.start, 0)
        XCTAssertEqual(s2.end, 7)

        // Reset defaults: '-' becomes a boundary again.
        try ui.resetWordBoundaryDefaults()
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s3 = try ui.selectionOffsets()
        XCTAssertEqual(s3.start, 0)
        XCTAssertEqual(s3.end, 3)
    }

    func testInsertTabDefaultSpacesModeInsertsToNextStop() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        // Caret at end of "abc" (col=3, tab_width=4) => inserts 1 space.
        try ui.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "abc ")
    }

    func testInsertTabRespectsTabWidthSettingInSpacesMode() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a", viewportWidthCells: 80)

        try ui.setTabWidth(2)
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "a ")
    }

    func testInsertTabRespectsTabKeyBehaviorTabMode() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

        try ui.setTabKeyBehavior(.tab)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "\t")
    }

    func testExecuteCommandJSONExposesCoreLineCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"duplicate_lines"}"#)
            XCTAssertEqual(try ui.text(), "a\na\nb\n")

            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"delete_lines"}"#)
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"move_lines_up"}"#)
            XCTAssertEqual(try ui.text(), "b\na\nc\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"move_lines_down"}"#)
            XCTAssertEqual(try ui.text(), "a\nc\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"join_lines"}"#)
            XCTAssertEqual(try ui.text(), "a b\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":1}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"split_line"}"#)
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }
    }

    func testExecuteCommandJSONExposesCommentTextEditAndUndoGroupingCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "let a = 1\n", viewportWidthCells: 80)

        try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
        try assertCommandSuccess(ui, #"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#)
        XCTAssertEqual(try ui.text(), "// let a = 1\n")

        try assertCommandSuccess(ui, #"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#)
        XCTAssertEqual(try ui.text(), "let a = 1\n")

        try assertCommandSuccess(
            ui,
            #"{"kind":"edit","op":"apply_text_edits","edits":[{"start":0,"end":3,"text":"var"},{"start":8,"end":9,"text":"2"}]}"#
        )
        XCTAssertEqual(try ui.text(), "var a = 2\n")

        try assertCommandSuccess(ui, #"{"kind":"edit","op":"end_undo_group"}"#)
        try ui.undo()
        XCTAssertEqual(try ui.text(), "let a = 1\n")
    }

    func testExecuteCommandJSONExposesWrapAndFoldCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abcdef\nsecond\nthird\n", viewportWidthCells: 80)

        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_viewport_width","width":4}"#)
        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#)
        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_wrap_indent","indent":{"kind":"fixed_cells","cells":2}}"#)

        let viewportJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let data = try XCTUnwrap(viewportJSON.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        XCTAssertEqual(obj["kind"] as? String, "viewport")
        let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
        let lines = try XCTUnwrap(viewport["lines"] as? [[String: Any]])
        XCTAssertTrue(lines.contains { ($0["is_wrapped_part"] as? Bool) == true && ($0["segment_x_start_cells"] as? Int) == 2 })

        try assertCommandSuccess(ui, #"{"kind":"style","op":"fold","start_line":0,"end_line":2}"#)
        let foldedJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let foldedData = try XCTUnwrap(foldedJSON.data(using: .utf8))
        let foldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: foldedData, options: []) as? [String: Any])
        let foldedViewport = try XCTUnwrap(foldedObj["viewport"] as? [String: Any])
        let foldedLines = try XCTUnwrap(foldedViewport["lines"] as? [[String: Any]])
        XCTAssertTrue(foldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })

        try assertCommandSuccess(ui, #"{"kind":"style","op":"unfold_all"}"#)
        let unfoldedJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let unfoldedData = try XCTUnwrap(unfoldedJSON.data(using: .utf8))
        let unfoldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: unfoldedData, options: []) as? [String: Any])
        let unfoldedViewport = try XCTUnwrap(unfoldedObj["viewport"] as? [String: Any])
        let unfoldedLines = try XCTUnwrap(unfoldedViewport["lines"] as? [[String: Any]])
        XCTAssertFalse(unfoldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })
    }

    func testExecuteCommandJSONExposesSnippetAndAutoPairsCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try assertCommandSuccess(
                ui,
                #"{"kind":"view","op":"set_auto_pairs_config","config":{"enabled":true,"pairs":[{"open":"<","close":">"}],"wrap_selection":true,"skip_over_closing":true,"delete_pair":true}}"#
            )
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"type_char","ch":"<"}"#)
            XCTAssertEqual(try ui.text(), "<>")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try assertCommandSuccess(
                ui,
                #"{"kind":"edit","op":"apply_snippet","start":0,"end":0,"snippet":"println!(${1:msg})$0","additional_edits":[]}"#
            )
            XCTAssertEqual(try ui.text(), "println!(msg)")
            XCTAssertTrue(try ui.hasActiveSnippetSession())

            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"snippet_next_placeholder"}"#)
            XCTAssertFalse(try ui.hasActiveSnippetSession())
        }
    }

    func testTypedCommandConvenienceAPIsCoverCoreEditingCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.duplicateLines()
            XCTAssertEqual(try ui.text(), "a\na\nb\n")

            try ui.moveTo(line: 1, column: 0)
            try ui.deleteLines()
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try ui.moveTo(line: 1, column: 0)
            try ui.moveLinesUp()
            XCTAssertEqual(try ui.text(), "b\na\nc\n")

            try ui.moveTo(line: 0, column: 0)
            try ui.moveLinesDown()
            XCTAssertEqual(try ui.text(), "a\nb\nc\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.joinLines()
            XCTAssertEqual(try ui.text(), "a b\n")

            try ui.moveTo(line: 0, column: 1)
            try ui.splitLine()
            XCTAssertEqual(try ui.text(), "a\n b\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "let a = 1\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.toggleComment(EcuCommentConfig(line: "//"))
            XCTAssertEqual(try ui.text(), "// let a = 1\n")

            try ui.toggleComment(EcuCommentConfig(line: "//"))
            XCTAssertEqual(try ui.text(), "let a = 1\n")

            try ui.applyTextEdits(
                [
                    EcuTextEdit(start: 0, end: 3, text: "var"),
                    EcuTextEdit(start: 8, end: 9, text: "2"),
                ]
            )
            XCTAssertEqual(try ui.text(), "var a = 2\n")

            try ui.endUndoGroup()
            try ui.undo()
            XCTAssertEqual(try ui.text(), "let a = 1\n")
        }
    }

    func testTypedCommandConvenienceAPIsCoverConfigSnippetAndFoldCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "abcdef\nsecond\nthird\n", viewportWidthCells: 80)
            try ui.setViewportWidthCells(4)
            try ui.setWrapMode(.char)
            try ui.setWrapIndent(.fixedCells(2))

            let viewportJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let data = try XCTUnwrap(viewportJSON.data(using: .utf8))
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
            XCTAssertEqual(obj["kind"] as? String, "viewport")
            let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
            let lines = try XCTUnwrap(viewport["lines"] as? [[String: Any]])
            XCTAssertTrue(lines.contains { ($0["is_wrapped_part"] as? Bool) == true && ($0["segment_x_start_cells"] as? Int) == 2 })

            try ui.fold(startLine: 0, endLine: 2)
            let foldedJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let foldedData = try XCTUnwrap(foldedJSON.data(using: .utf8))
            let foldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: foldedData, options: []) as? [String: Any])
            let foldedViewport = try XCTUnwrap(foldedObj["viewport"] as? [String: Any])
            let foldedLines = try XCTUnwrap(foldedViewport["lines"] as? [[String: Any]])
            XCTAssertTrue(foldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })

            try ui.unfoldAll()
            let unfoldedJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let unfoldedData = try XCTUnwrap(unfoldedJSON.data(using: .utf8))
            let unfoldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: unfoldedData, options: []) as? [String: Any])
            let unfoldedViewport = try XCTUnwrap(unfoldedObj["viewport"] as? [String: Any])
            let unfoldedLines = try XCTUnwrap(unfoldedViewport["lines"] as? [[String: Any]])
            XCTAssertFalse(unfoldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "{", viewportWidthCells: 80)
            try ui.setIndentationConfig(
                EcuIndentationConfig(
                    style: .spaces(width: 2),
                    indentTriggers: ["{"],
                    outdentTriggers: ["}"]
                )
            )
            try ui.moveTo(line: 0, column: 1)
            try ui.insertNewline(autoIndent: true)
            XCTAssertEqual(try ui.text(), "{\n  ")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try ui.setAutoPairsConfig(
                EcuAutoPairsConfig(
                    enabled: true,
                    pairs: [EcuAutoPair(open: "<", close: ">")],
                    wrapSelection: true,
                    skipOverClosing: true,
                    deletePair: true
                )
            )
            try ui.typeChar("<")
            XCTAssertEqual(try ui.text(), "<>")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try ui.applySnippet(start: 0, end: 0, snippet: "println!(${1:msg})$0")
            XCTAssertEqual(try ui.text(), "println!(msg)")
            XCTAssertTrue(try ui.hasActiveSnippetSession())

            try ui.snippetNextPlaceholder()
            XCTAssertFalse(try ui.hasActiveSnippetSession())
        }
    }
}
