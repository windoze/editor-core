import Foundation
import XCTest
@testable import EditorCoreFFI

final class EditorStateJSONCommandBridgeTests: XCTestCase {
    private func run(_ state: EditorState, _ commandJSON: String) throws -> CommandResultJSON {
        let out = try state.executeJSON(commandJSON)
        return try JSONTestHelpers.decode(CommandResultJSON.self, from: out)
    }

    private func assertSuccess(_ result: CommandResultJSON, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.kind, "success", file: file, line: line)
    }

    func testEditCommandsCoverAllOps() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        do {
            let state = try EditorState(library: library, initialText: "abcde", viewportWidth: 80)

            assertSuccess(try run(state, #"{"kind":"edit","op":"insert","offset":0,"text":"Z"}"#))
            XCTAssertEqual(try state.text(), "Zabcde")

            assertSuccess(try run(state, #"{"kind":"edit","op":"delete","start":1,"length":2}"#))
            XCTAssertEqual(try state.text(), "Zcde")

            assertSuccess(try run(state, #"{"kind":"edit","op":"replace","start":1,"length":2,"text":"XY"}"#))
            XCTAssertEqual(try state.text(), "ZXYe")
        }

        do {
            let state = try EditorState(library: library, initialText: "x", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_text","text":"A"}"#))
            XCTAssertEqual(try state.text(), "Ax")
        }

        do {
            let state = try EditorState(library: library, initialText: "x", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_tab"}"#))
            XCTAssertEqual(try state.text(), "\tx")
        }

        do {
            let state = try EditorState(library: library, initialText: "    let a = 1", viewportWidth: 80)
            try state.moveTo(line: 0, column: 13)

            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_newline","auto_indent":true}"#))
            XCTAssertTrue((try state.text()).hasSuffix("\n    "))
        }

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 1)
            assertSuccess(try run(state, #"{"kind":"edit","op":"split_line"}"#))
            XCTAssertEqual(try state.text(), "a\nb")
        }

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 1)
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_newline","auto_indent":false}"#))
            XCTAssertEqual(try state.text(), "a\nb")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb", viewportWidth: 80)
            try state.moveTo(line: 1, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"indent"}"#))
            XCTAssertEqual(try state.text(), "a\n\tb")

            assertSuccess(try run(state, #"{"kind":"edit","op":"outdent"}"#))
            XCTAssertEqual(try state.text(), "a\nb")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"duplicate_lines"}"#))
            XCTAssertEqual(try state.text(), "a\na\nb\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\nc\n", viewportWidth: 80)
            try state.moveTo(line: 1, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_lines"}"#))
            XCTAssertEqual(try state.text(), "a\nc\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\nc\n", viewportWidth: 80)
            try state.moveTo(line: 1, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"move_lines_up"}"#))
            XCTAssertEqual(try state.text(), "b\na\nc\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\nc\n", viewportWidth: 80)
            try state.moveTo(line: 1, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"move_lines_down"}"#))
            XCTAssertEqual(try state.text(), "a\nc\nb\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"join_lines"}"#))
            XCTAssertEqual(try state.text(), "a b\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "let a = 1\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            let cmd = #"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#
            assertSuccess(try run(state, cmd))
            XCTAssertEqual(try state.text(), "// let a = 1\n")

            assertSuccess(try run(state, cmd))
            XCTAssertEqual(try state.text(), "let a = 1\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "abcdef", viewportWidth: 80)
            let r = try run(
                state,
                #"{"kind":"edit","op":"apply_text_edits","edits":[{"start":0,"end":1,"text":"Z"},{"start":5,"end":6,"text":"Q"}]}"#
            )
            assertSuccess(r)
            XCTAssertEqual(try state.text(), "ZbcdeQ")
        }

        do {
            let state = try EditorState(library: library, initialText: "        x", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"view","op":"set_tab_width","width":4}"#))
            try state.moveTo(line: 0, column: 6)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_to_prev_tab_stop"}"#))

            let after = try state.text()
            let leadingSpaces = after.prefix { $0 == " " }.count
            XCTAssertEqual(leadingSpaces, 6)
            XCTAssertTrue(after.contains("x"))
        }

        do {
            let state = try EditorState(library: library, initialText: "a🇺🇸b\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 3)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_grapheme_back"}"#))
            XCTAssertEqual(try state.text(), "ab\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "a🇺🇸b\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 1)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_grapheme_forward"}"#))
            XCTAssertEqual(try state.text(), "ab\n")
        }

        do {
            let state = try EditorState(library: library, initialText: "hello world", viewportWidth: 80)
            try state.moveTo(line: 0, column: 11)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_word_back"}"#))
            XCTAssertEqual(try state.text(), "hello ")
        }

        do {
            let state = try EditorState(library: library, initialText: "hello world", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_word_forward"}"#))
            XCTAssertEqual(try state.text(), " world")
        }

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 1)
            assertSuccess(try run(state, #"{"kind":"edit","op":"backspace"}"#))
            XCTAssertEqual(try state.text(), "b")
        }

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"delete_forward"}"#))
            XCTAssertEqual(try state.text(), "b")
        }

        do {
            let state = try EditorState(library: library, initialText: "", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_text","text":"A"}"#))
            assertSuccess(try run(state, #"{"kind":"edit","op":"end_undo_group"}"#))
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_text","text":"B"}"#))
            XCTAssertEqual(try state.text(), "AB")

            assertSuccess(try run(state, #"{"kind":"edit","op":"undo"}"#))
            XCTAssertEqual(try state.text(), "A")

            assertSuccess(try run(state, #"{"kind":"edit","op":"redo"}"#))
            XCTAssertEqual(try state.text(), "AB")
        }

        do {
            let state = try EditorState(library: library, initialText: "foo foo", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            let r = try run(state, #"{"kind":"edit","op":"replace_current","query":"foo","replacement":"bar"}"#)
            XCTAssertEqual(r.kind, "replace_result")
            XCTAssertEqual(r.replaced, 1)
            XCTAssertEqual(try state.text(), "bar foo")
        }

        do {
            let state = try EditorState(library: library, initialText: "foo foo foo", viewportWidth: 80)
            let r = try run(state, #"{"kind":"edit","op":"replace_all","query":"foo","replacement":"bar"}"#)
            XCTAssertEqual(r.kind, "replace_result")
            XCTAssertEqual(r.replaced, 3)
            XCTAssertEqual(try state.text(), "bar bar bar")
        }
    }

    func testCursorCommandsCoverAllOps() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        do {
            let state = try EditorState(library: library, initialText: "hello world\nsecond line\n", viewportWidth: 80)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":6}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position, PositionJSON(line: 0, column: 6))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_by","delta_line":1,"delta_column":-3}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position.line, 1)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to_line_start"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position.column, 0)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to_line_end"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertGreaterThan(full.cursor.position.column, 0)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_word_left"}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_word_right"}"#))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"set_selection","start":{"line":0,"column":0},"end":{"line":0,"column":5}}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNotNil(full.cursor.selection)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"extend_selection","to":{"line":0,"column":8}}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.selection?.end.column, 8)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"clear_selection"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNil(full.cursor.selection)
        }

        do {
            let state = try EditorState(library: library, initialText: "a🇺🇸b\n", viewportWidth: 80)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":1}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_grapheme_right"}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position, PositionJSON(line: 0, column: 3))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_grapheme_left"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position, PositionJSON(line: 0, column: 1))
        }

        do {
            let state = try EditorState(library: library, initialText: "abcd\nabcd\nabcd\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"set_rect_selection","anchor":{"line":0,"column":1},"active":{"line":2,"column":3}}"#))
            let full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertGreaterThanOrEqual(full.cursor.selections.count, 2)
        }

        do {
            let state = try EditorState(library: library, initialText: "foo bar\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":1}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"select_word"}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNotNil(full.cursor.selection)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"expand_selection"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNotNil(full.cursor.selection)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"expand_selection"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNotNil(full.cursor.selection)
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\nc\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"add_cursor_above"}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"add_cursor_below"}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertGreaterThanOrEqual(full.cursor.selections.count, 2)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"clear_secondary_selections"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.multiCursors.count, 0)
            XCTAssertEqual(full.cursor.selections.count, 1)
        }

        do {
            let state = try EditorState(library: library, initialText: "foo foo foo\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":1}"#))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"add_next_occurrence"}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertGreaterThanOrEqual(full.cursor.selections.count, 2)

            assertSuccess(try run(state, #"{"kind":"cursor","op":"add_all_occurrences"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.selections.count, 3)
        }

        do {
            let state = try EditorState(library: library, initialText: "a foo b foo\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#))

            let r1 = try run(state, #"{"kind":"cursor","op":"find_next","query":"foo"}"#)
            XCTAssertEqual(r1.kind, "search_match")
            XCTAssertNotNil(r1.start)
            XCTAssertNotNil(r1.end)

            let r2 = try run(state, #"{"kind":"cursor","op":"find_next","query":"foo"}"#)
            XCTAssertEqual(r2.kind, "search_match")

            let r3 = try run(state, #"{"kind":"cursor","op":"find_prev","query":"foo"}"#)
            XCTAssertEqual(r3.kind, "search_match")

            let r4 = try run(state, #"{"kind":"cursor","op":"find_next","query":"__definitely_not_found__"}"#)
            XCTAssertEqual(r4.kind, "search_not_found")
        }

        do {
            let state = try EditorState(library: library, initialText: "0123456789", viewportWidth: 80)

            assertSuccess(try run(state, #"{"kind":"view","op":"set_viewport_width","width":4}"#))
            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to_visual","row":1,"x_cells":0}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position, PositionJSON(line: 0, column: 4))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_visual_by","delta_rows":1}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.position, PositionJSON(line: 0, column: 8))

            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to_visual_line_start"}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to_visual_line_end"}"#))
        }

        do {
            let state = try EditorState(library: library, initialText: "x\ny\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"set_selections","selections":[{"start":{"line":0,"column":0},"end":{"line":0,"column":0},"direction":"forward"},{"start":{"line":1,"column":0},"end":{"line":1,"column":0},"direction":"forward"}],"primary_index":1}"#))
            let full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertEqual(full.cursor.selections.count, 2)
            XCTAssertEqual(full.cursor.primarySelectionIndex, 1)
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#))
            assertSuccess(try run(state, #"{"kind":"cursor","op":"select_line"}"#))
            let full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertNotNil(full.cursor.selection)
        }
    }

    func testViewAndStyleCommandsCoverAllOpsAndViewportResult() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        do {
            let state = try EditorState(library: library, initialText: "    abcdefghij\n", viewportWidth: 80)

            assertSuccess(try run(state, #"{"kind":"view","op":"set_viewport_width","width":4}"#))
            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#))
            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_indent","indent":{"kind":"fixed_cells","cells":2}}"#))

            let viewport = try run(state, #"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
            XCTAssertEqual(viewport.kind, "viewport")
            XCTAssertGreaterThan(viewport.viewport?.actualLineCount ?? 0, 1)

            let wrappedLines = viewport.viewport?.lines.filter { $0.isWrappedPart } ?? []
            XCTAssertTrue(wrappedLines.contains { $0.segmentXStartCells == 2 })

            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_indent","indent":{"kind":"same_as_line_indent"}}"#))
            let viewport2 = try run(state, #"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
            let wrapped2 = viewport2.viewport?.lines.filter { $0.isWrappedPart } ?? []
            // Same-as-indent 会被 clamp 到 viewport_width - 1（这里 4 -> 3）
            XCTAssertTrue(wrapped2.contains { $0.segmentXStartCells == 3 })

            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_indent","indent":{"kind":"none"}}"#))
            _ = try run(state, #"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)

            // cover remaining wrap modes too
            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_mode","mode":"word"}"#))
            assertSuccess(try run(state, #"{"kind":"view","op":"set_wrap_mode","mode":"none"}"#))
        }

        do {
            let state = try EditorState(library: library, initialText: "x", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"view","op":"set_tab_key_behavior","behavior":"spaces"}"#))
            assertSuccess(try run(state, #"{"kind":"view","op":"set_tab_width","width":2}"#))
            try state.moveTo(line: 0, column: 0)
            assertSuccess(try run(state, #"{"kind":"edit","op":"insert_tab"}"#))
            XCTAssertEqual(try state.text(), "  x")

            // cover tab behavior mode switch back
            assertSuccess(try run(state, #"{"kind":"view","op":"set_tab_key_behavior","behavior":"tab"}"#))

            // scroll_to validates line bounds
            assertSuccess(try run(state, #"{"kind":"view","op":"scroll_to","line":0}"#))
        }

        do {
            let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"style","op":"add_style","start":0,"end":1,"style_id":123}"#))
            let blob1 = try state.viewportBlob(startVisualRow: 0, rowCount: 10)
            XCTAssertTrue(blob1.styleIds.contains(123))

            assertSuccess(try run(state, #"{"kind":"style","op":"remove_style","start":0,"end":1,"style_id":123}"#))
            let blob2 = try state.viewportBlob(startVisualRow: 0, rowCount: 10)
            XCTAssertFalse(blob2.styleIds.contains(123))
        }

        do {
            let state = try EditorState(library: library, initialText: "a\nb\nc\n", viewportWidth: 80)
            assertSuccess(try run(state, #"{"kind":"style","op":"fold","start_line":0,"end_line":2}"#))
            var full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertTrue(full.folding.regions.contains { $0.isCollapsed })

            assertSuccess(try run(state, #"{"kind":"style","op":"unfold","start_line":0}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertTrue(full.folding.regions.contains { $0.isCollapsed == false })

            assertSuccess(try run(state, #"{"kind":"style","op":"unfold_all"}"#))
            full = try JSONTestHelpers.decode(FullStateJSON.self, from: try state.fullStateJSON())
            XCTAssertFalse(full.folding.regions.contains { $0.isCollapsed })
        }
    }

    func testExecuteJSONErrorPathsSetLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        // invalid JSON (parse error)
        do {
            _ = try state.executeJSON("{this is not json")
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid args (command execution error)
        do {
            _ = try state.executeJSON(#"{"kind":"view","op":"set_viewport_width","width":0}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid args (set_tab_width: width == 0)
        do {
            _ = try state.executeJSON(#"{"kind":"view","op":"set_tab_width","width":0}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid args (scroll_to out of range)
        do {
            _ = try state.executeJSON(#"{"kind":"view","op":"scroll_to","line":999999}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid range (style fold start >= end)
        do {
            _ = try state.executeJSON(#"{"kind":"style","op":"fold","start_line":1,"end_line":1}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid range (add_style start >= end)
        do {
            _ = try state.executeJSON(#"{"kind":"style","op":"add_style","start":1,"end":1,"style_id":1}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid range (apply_text_edits overlapping edits)
        do {
            _ = try state.executeJSON(
                #"{"kind":"edit","op":"apply_text_edits","edits":[{"start":0,"end":2,"text":"X"},{"start":1,"end":3,"text":"Y"}]}"#
            )
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // invalid position (rect selection beyond line count)
        do {
            _ = try state.executeJSON(
                #"{"kind":"cursor","op":"set_rect_selection","anchor":{"line":999,"column":0},"active":{"line":999,"column":1}}"#
            )
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }

        // replace_current no match is an error (not SearchNotFound)
        do {
            _ = try state.executeJSON(#"{"kind":"edit","op":"replace_current","query":"__nope__","replacement":"x"}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }
    }
}
