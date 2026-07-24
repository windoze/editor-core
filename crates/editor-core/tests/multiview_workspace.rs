use editor_core::{
    Command, CursorCommand, EditCommand, OpenBufferResult, Position, StyleCommand,
    ViewCommand, ViewSmoothScrollState, Workspace,
};

#[test]
fn test_two_views_share_buffer_but_keep_independent_view_state() {
    let mut ws = Workspace::new();

    let OpenBufferResult {
        buffer_id,
        view_id: view_a,
    } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "0123456789\n", 10)
        .unwrap();

    let view_b = ws.create_view(buffer_id, 5).unwrap();

    // Independent scrolling state.
    ws.set_scroll_top(view_a, 0).unwrap();
    ws.set_scroll_top(view_b, 2).unwrap();
    assert_eq!(ws.scroll_top_for_view(view_a).unwrap(), 0);
    assert_eq!(ws.scroll_top_for_view(view_b).unwrap(), 2);

    // Independent cursor/selection state.
    ws.execute(
        view_a,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    ws.execute(
        view_b,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 5 }),
    )
    .unwrap();
    assert_eq!(ws.cursor_position_for_view(view_a).unwrap().column, 1);
    assert_eq!(ws.cursor_position_for_view(view_b).unwrap().column, 5);

    // Different wrap widths should yield different visual line counts.
    let grid_a = ws.get_viewport_content_styled(view_a, 0, 100).unwrap();
    let grid_b = ws.get_viewport_content_styled(view_b, 0, 100).unwrap();
    assert_eq!(grid_a.actual_line_count(), 2); // "0123456789" + trailing empty line
    assert_eq!(grid_b.actual_line_count(), 3); // wrapped into 2 + trailing empty line
    assert_eq!(ws.total_visual_lines_for_view(view_a).unwrap(), 2);
    assert_eq!(ws.total_visual_lines_for_view(view_b).unwrap(), 3);

    // View-local visual/logical mapping APIs.
    assert_eq!(ws.visual_to_logical_for_view(view_b, 1).unwrap(), (0, 1));
    assert_eq!(
        ws.logical_to_visual_for_view(view_b, 0, 5).unwrap(),
        Some((1, 0))
    );
    assert_eq!(
        ws.visual_position_to_logical_for_view(view_b, 1, 2)
            .unwrap(),
        Some(Position::new(0, 7))
    );

    // Lightweight minimap path should also work off-viewport.
    let minimap = ws.get_minimap_content(view_b, 0, 10).unwrap();
    assert_eq!(minimap.actual_line_count(), 3);
    assert_eq!(minimap.lines[0].logical_line_index, 0);

    // Edit in view A applies to the shared buffer and broadcasts the same delta to view B.
    ws.execute(
        view_a,
        Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }),
    )
    .unwrap();

    assert_eq!(ws.buffer_text(buffer_id).unwrap(), "0X123456789\n");

    let delta_a = ws.take_last_text_delta_for_view(view_a).unwrap();
    let delta_b = ws.take_last_text_delta_for_view(view_b).unwrap();
    assert_eq!(delta_a.edits, delta_b.edits);

    // View B caret should shift by the inserted length.
    assert_eq!(ws.cursor_position_for_view(view_b).unwrap().column, 6);

    // Smooth-scroll state and viewport query API are view-local.
    ws.set_viewport_height(view_b, 1).unwrap();
    ws.set_smooth_scroll_state(
        view_b,
        ViewSmoothScrollState {
            top_visual_row: 1,
            sub_row_offset: 123,
            overscan_rows: 2,
        },
    )
    .unwrap();
    let viewport = ws.viewport_state_for_view(view_b).unwrap();
    assert_eq!(viewport.scroll_top, 1);
    assert_eq!(viewport.visible_lines, 1..2);
    assert_eq!(viewport.smooth_scroll.sub_row_offset, 123);
    assert_eq!(viewport.prefetch_lines, 0..4);
}

/// C-4: two edits between consumptions must coalesce into one equivalent delta rather than the
/// second overwriting (and losing) the first.
#[test]
fn buffer_delta_coalesces_across_edits_without_consumption() {
    let mut ws = Workspace::new();
    let OpenBufferResult { buffer_id, view_id } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "abc\n", 80)
        .unwrap();

    // Consume the didOpen-time state (if any) so the slot starts clean.
    let _ = ws.take_last_text_delta_for_buffer(buffer_id).unwrap();

    // Two edits, no take in between.
    ws.execute(
        view_id,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }),
    )
    .unwrap();
    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: ">>".to_string(),
        }),
    )
    .unwrap(); // ">>abc\n"
    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: "!".to_string(),
        }),
    )
    .unwrap(); // ">>!abc\n"

    assert_eq!(ws.buffer_text(buffer_id).unwrap(), ">>!abc\n");

    let delta = ws
        .take_last_text_delta_for_buffer(buffer_id)
        .unwrap()
        .expect("coalesced delta present");

    // The coalesced delta must span the original buffer through the final state and, applied in
    // order to the pre-edit text, reproduce the final buffer text.
    assert_eq!(delta.before_char_count, 4); // "abc\n"
    assert_eq!(delta.after_char_count, 7); // ">>!abc\n"

    let mut chars: Vec<char> = "abc\n".chars().collect();
    for edit in &delta.edits {
        let start = edit.start;
        let end = edit.end();
        let inserted: Vec<char> = edit.inserted_text.chars().collect();
        chars.splice(start..end, inserted);
    }
    let replayed: String = chars.into_iter().collect();
    assert_eq!(replayed, ">>!abc\n", "both edits must survive coalescing");
}

/// C-4: a non-text (style-only) change must not clear an unconsumed text delta.
#[test]
fn style_change_does_not_clear_unconsumed_text_delta() {
    let mut ws = Workspace::new();
    let OpenBufferResult { buffer_id, view_id } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "abc\n", 80)
        .unwrap();
    let _ = ws.take_last_text_delta_for_buffer(buffer_id).unwrap();

    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: "Z".to_string(),
        }),
    )
    .unwrap(); // "Zabc\n"

    // A style-only change (no text delta) must not wipe the pending text delta.
    ws.execute(
        view_id,
        Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 1,
            style_id: 1,
        }),
    )
    .unwrap();

    let delta = ws
        .take_last_text_delta_for_buffer(buffer_id)
        .unwrap()
        .expect("text delta must survive an interleaved style change");
    assert_eq!(delta.before_char_count, 4);
    assert_eq!(delta.after_char_count, 5);
}

/// C-6: `create_view` must yield the buffer's deterministic default config, independent of which
/// view most recently executed a command (which used to leak into new views via shared executor
/// scratch state).
#[test]
fn create_view_config_is_independent_of_last_active_view() {
    let mut ws = Workspace::new();
    let OpenBufferResult {
        buffer_id,
        view_id: view_a,
    } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "abc\n", 80)
        .unwrap();

    let default_tab_width = ws.tab_width_for_view(view_a).unwrap();
    let custom_tab_width = default_tab_width + 3;

    // Give view A a distinct tab width, then execute on A so its config loads into the shared
    // executor.
    ws.execute(
        view_a,
        Command::View(ViewCommand::SetTabWidth {
            width: custom_tab_width,
        }),
    )
    .unwrap();
    ws.execute(
        view_a,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    assert_eq!(ws.tab_width_for_view(view_a).unwrap(), custom_tab_width);

    // A plain new view must NOT inherit view A's tab width; it gets the buffer default.
    let view_c = ws.create_view(buffer_id, 80).unwrap();
    assert_eq!(
        ws.tab_width_for_view(view_c).unwrap(),
        default_tab_width,
        "create_view must use the deterministic default, not view A's scratch config"
    );

    // create_view_from(view_a) explicitly clones view A's config.
    let view_d = ws.create_view_from(view_a, 80).unwrap();
    assert_eq!(
        ws.tab_width_for_view(view_d).unwrap(),
        custom_tab_width,
        "create_view_from must clone the parent view's config"
    );

    // Cursor/selection are still reset independently for the cloned view.
    assert_eq!(
        ws.cursor_position_for_view(view_d).unwrap(),
        Position::new(0, 0)
    );
}
