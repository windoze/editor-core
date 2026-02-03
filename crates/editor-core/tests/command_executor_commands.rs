use editor_core::{
    Command, CommandError, CommandExecutor, CommandResult, CursorCommand, EditCommand, Position,
    StyleCommand, ViewCommand,
};

#[test]
fn test_insert_empty_text_is_error_and_does_not_change_state() {
    let mut executor = CommandExecutor::new("abc", 10);
    let before_text = executor.editor().get_text();
    let before_cursor = executor.editor().cursor_position();
    let before_history = executor.get_command_history().len();

    let result = executor.execute(Command::Edit(EditCommand::Insert {
        offset: 1,
        text: String::new(),
    }));

    assert!(matches!(result, Err(CommandError::EmptyText)));
    assert_eq!(executor.editor().get_text(), before_text);
    assert_eq!(executor.editor().cursor_position(), before_cursor);
    // 当前实现会记录所有尝试过的命令（包括失败的）
    assert_eq!(executor.get_command_history().len(), before_history + 1);
}

#[test]
fn test_insert_updates_line_index_and_layout_engine() {
    let mut executor = CommandExecutor::empty(10);

    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "12345678901".to_string(), // 11 chars, viewport 10 => wraps
        }))
        .unwrap();

    assert_eq!(executor.editor().line_count(), 1);
    assert_eq!(
        executor.editor().layout_engine.logical_line_count(),
        executor.editor().line_count()
    );
    assert_eq!(executor.editor().layout_engine.visual_line_count(), 2);

    // 插入换行，增加逻辑行
    let end = executor.editor().char_count();
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: end,
            text: "\nX".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().line_count(), 2);
    assert_eq!(
        executor.editor().layout_engine.logical_line_count(),
        executor.editor().line_count()
    );
}

#[test]
fn test_delete_zero_length_is_noop() {
    let mut executor = CommandExecutor::new("Hello", 10);
    let before_text = executor.editor().get_text();
    let before_lines = executor.editor().line_count();

    executor
        .execute(Command::Edit(EditCommand::Delete {
            start: 0,
            length: 0,
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), before_text);
    assert_eq!(executor.editor().line_count(), before_lines);
}

#[test]
fn test_delete_clamps_cursor_when_lines_removed() {
    let mut executor = CommandExecutor::new("a\nb\nc", 10);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 2,
            column: 0,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(2, 0));

    // 删除 "a\nb\n"（4 chars）
    executor
        .execute(Command::Edit(EditCommand::Delete {
            start: 0,
            length: 4,
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "c");
    assert_eq!(executor.editor().line_count(), 1);
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn test_replace_with_empty_text_is_delete() {
    let mut executor = CommandExecutor::new("Hello World", 10);
    executor
        .execute(Command::Edit(EditCommand::Replace {
            start: 5,
            length: 6,
            text: String::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "Hello");
}

#[test]
fn test_cursor_move_to_clamps_column_to_line_len() {
    let mut executor = CommandExecutor::new("abc\nx", 10);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 999,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 3));

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 999,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 1));
}

#[test]
fn test_cursor_move_to_invalid_line_is_error() {
    let mut executor = CommandExecutor::new("abc", 10);

    let result = executor.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }));

    assert!(matches!(result, Err(CommandError::InvalidPosition { .. })));
}

#[test]
fn test_cursor_move_by_validates_line_and_clamps_column() {
    let mut executor = CommandExecutor::new("abc\nx", 10);

    executor
        .execute(Command::Cursor(CursorCommand::MoveBy {
            delta_line: 1,
            delta_column: 100,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 1));

    let result = executor.execute(Command::Cursor(CursorCommand::MoveBy {
        delta_line: 10,
        delta_column: 0,
    }));
    assert!(matches!(result, Err(CommandError::InvalidPosition { .. })));
}

#[test]
fn test_selection_direction_forward_and_backward() {
    let mut executor = CommandExecutor::new("abc\ndef", 10);

    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 1),
            end: Position::new(1, 2),
        }))
        .unwrap();
    assert_eq!(
        executor.editor().selection().unwrap().direction,
        editor_core::SelectionDirection::Forward
    );

    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(1, 2),
            end: Position::new(0, 1),
        }))
        .unwrap();
    assert_eq!(
        executor.editor().selection().unwrap().direction,
        editor_core::SelectionDirection::Backward
    );
}

#[test]
fn test_extend_selection_creates_from_cursor_and_tracks_direction() {
    let mut executor = CommandExecutor::new("abc\ndef", 10);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 2,
        }))
        .unwrap();

    executor
        .execute(Command::Cursor(CursorCommand::ExtendSelection {
            to: Position::new(0, 1),
        }))
        .unwrap();

    let sel = executor.editor().selection().unwrap();
    assert_eq!(sel.start, Position::new(1, 2));
    assert_eq!(sel.end, Position::new(0, 1));
    assert_eq!(sel.direction, editor_core::SelectionDirection::Backward);
}

#[test]
fn test_view_set_viewport_width_triggers_reflow() {
    let mut executor = CommandExecutor::new("12345678901", 20);
    assert_eq!(executor.editor().layout_engine.visual_line_count(), 1);

    executor
        .execute(Command::View(ViewCommand::SetViewportWidth { width: 10 }))
        .unwrap();

    assert_eq!(executor.editor().viewport_width, 10);
    assert_eq!(executor.editor().layout_engine.visual_line_count(), 2);
}

#[test]
fn test_view_scroll_to_validates_line() {
    let mut executor = CommandExecutor::new("a\nb", 10);

    executor
        .execute(Command::View(ViewCommand::ScrollTo { line: 1 }))
        .unwrap();

    let result = executor.execute(Command::View(ViewCommand::ScrollTo { line: 2 }));
    assert!(matches!(result, Err(CommandError::InvalidPosition { .. })));
}

#[test]
fn test_view_get_viewport_respects_bounds() {
    let mut executor = CommandExecutor::new("L1\nL2\nL3", 10);

    let result = executor.execute(Command::View(ViewCommand::GetViewport {
        start_row: 1,
        count: 10,
    }));

    let CommandResult::Viewport(grid) = result.unwrap() else {
        panic!("expected CommandResult::Viewport");
    };
    assert_eq!(grid.actual_line_count(), 2);
    assert_eq!(grid.lines[0].logical_line_index, 1);
    assert_eq!(grid.lines[1].logical_line_index, 2);
}

#[test]
fn test_view_get_viewport_on_empty_document_includes_empty_line() {
    let mut executor = CommandExecutor::empty(10);
    let result = executor.execute(Command::View(ViewCommand::GetViewport {
        start_row: 0,
        count: 10,
    }));

    let CommandResult::Viewport(grid) = result.unwrap() else {
        panic!("expected CommandResult::Viewport");
    };
    assert_eq!(grid.actual_line_count(), 1);
    assert_eq!(grid.lines[0].logical_line_index, 0);
    assert!(grid.lines[0].cells.is_empty());
}

#[test]
fn test_style_add_and_remove_updates_interval_tree() {
    let mut executor = CommandExecutor::new("abcdef", 10);

    executor
        .execute(Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 3,
            style_id: 42,
        }))
        .unwrap();
    let styles = executor.editor().interval_tree.query_point(1);
    assert_eq!(styles.len(), 1);
    assert_eq!(styles[0].style_id, 42);

    executor
        .execute(Command::Style(StyleCommand::RemoveStyle {
            start: 0,
            end: 3,
            style_id: 42,
        }))
        .unwrap();
    assert!(executor.editor().interval_tree.query_point(1).is_empty());
}

#[test]
fn test_style_add_invalid_range_is_error() {
    let mut executor = CommandExecutor::new("abcdef", 10);

    let result = executor.execute(Command::Style(StyleCommand::AddStyle {
        start: 3,
        end: 3,
        style_id: 1,
    }));
    assert!(matches!(result, Err(CommandError::InvalidRange { .. })));
}

#[test]
fn test_folding_commands_fold_unfold_unfold_all() {
    let mut executor = CommandExecutor::new("a\nb\nc\nd\ne", 10);

    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .unwrap();

    let region = executor.editor().folding_manager.regions()[0].clone();
    assert!(region.is_collapsed);
    assert_eq!(region.start_line, 1);
    assert_eq!(region.end_line, 3);

    executor
        .execute(Command::Style(StyleCommand::Unfold { start_line: 1 }))
        .unwrap();
    assert!(!executor.editor().folding_manager.regions()[0].is_collapsed);

    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .unwrap();
    executor
        .execute(Command::Style(StyleCommand::UnfoldAll))
        .unwrap();
    assert!(!executor.editor().folding_manager.regions()[0].is_collapsed);
}

#[test]
fn test_layout_engine_logical_position_to_visual_for_wrapped_lines() {
    use editor_core::LayoutEngine;

    let mut engine = LayoutEngine::new(10);
    engine.from_lines(&["12345678901"]);

    assert_eq!(engine.logical_position_to_visual(0, 0), Some((0, 0)));
    assert_eq!(engine.logical_position_to_visual(0, 10), Some((1, 0)));
    assert_eq!(engine.logical_position_to_visual(0, 11), Some((1, 1)));
    assert_eq!(engine.logical_position_to_visual(0, 999), Some((1, 1))); // clamp

    let mut engine = LayoutEngine::new(6);
    engine.from_lines(&["Hello你"]);
    assert_eq!(engine.logical_position_to_visual(0, 5), Some((1, 0)));
    assert_eq!(engine.logical_position_to_visual(0, 6), Some((1, 2)));
}
