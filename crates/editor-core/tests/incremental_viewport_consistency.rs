use editor_core::{
    Command, CommandExecutor, EditCommand, HeadlessGrid, SnapshotGenerator, ViewCommand, WrapIndent,
};

#[derive(Debug, Clone, PartialEq, Eq)]
struct PlainLine {
    logical_line_index: usize,
    is_wrapped_part: bool,
    text: String,
    widths: Vec<usize>,
}

fn plain_lines(grid: &HeadlessGrid) -> Vec<PlainLine> {
    grid.lines
        .iter()
        .map(|line| PlainLine {
            logical_line_index: line.logical_line_index,
            is_wrapped_part: line.is_wrapped_part,
            text: line.cells.iter().map(|c| c.ch).collect(),
            widths: line.cells.iter().map(|c| c.width).collect(),
        })
        .collect()
}

fn assert_viewport_matches_reference(
    executor: &mut CommandExecutor,
    start_row: usize,
    count: usize,
) {
    let text = executor.editor().get_text();

    let reference = SnapshotGenerator::from_text_with_layout_options(
        &text,
        executor.editor().viewport_width,
        executor.editor().layout_engine.tab_width(),
        executor.editor().layout_engine.wrap_mode(),
        executor.editor().layout_engine.wrap_indent(),
    )
    .get_headless_grid(start_row, count);

    let actual = executor
        .execute(Command::View(ViewCommand::GetViewport { start_row, count }))
        .expect("GetViewport should succeed");

    let editor_core::CommandResult::Viewport(actual_grid) = actual else {
        panic!("expected CommandResult::Viewport");
    };

    assert_eq!(
        plain_lines(&actual_grid),
        plain_lines(&reference),
        "增量更新后的 viewport 输出应与参考实现一致"
    );
}

fn offset_at(executor: &CommandExecutor, line: usize, column: usize) -> usize {
    let line_count = executor.editor().line_index.line_count().max(1);
    let line = line.min(line_count - 1);
    let line_text = executor
        .editor()
        .line_index
        .get_line_text(line)
        .unwrap_or_default();
    let column = column.min(line_text.chars().count());
    executor
        .editor()
        .line_index
        .position_to_char_offset(line, column)
}

#[test]
fn test_incremental_viewport_matches_reference_across_edits_and_undo_redo() {
    // 选择一个会触发软换行的 viewport 宽度，让 layout 变化更明显。
    let mut executor = CommandExecutor::new("    0123456789ABCDEF\nline2\nline3", 10);

    executor
        .execute(Command::View(ViewCommand::SetWrapIndent {
            indent: WrapIndent::SameAsLineIndent,
        }))
        .unwrap();

    // 初始状态应该匹配参考生成器。
    assert_viewport_matches_reference(&mut executor, 0, 50);

    // 1) 单行插入（不含换行）
    let offset = offset_at(&executor, 0, 6);
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset,
            text: "ZZZZZ".to_string(),
        }))
        .unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);

    // 2) 多行插入（包含换行）
    let offset = offset_at(&executor, 0, 2);
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset,
            text: "\nMID\n".to_string(),
        }))
        .unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);

    // 3) 跨行删除（覆盖换行符）
    let start = offset_at(&executor, 0, 1);
    let end = offset_at(&executor, 2, 2);
    executor
        .execute(Command::Edit(EditCommand::Delete {
            start,
            length: end.saturating_sub(start),
        }))
        .unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);

    // 4) Replace：替换为不同换行数的内容
    let start = offset_at(&executor, 1, 0);
    executor
        .execute(Command::Edit(EditCommand::Replace {
            start,
            length: 2,
            text: "R\nS".to_string(),
        }))
        .unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);

    // 5) undo/redo 也必须保持一致性（这里的 undo/redo 路径会触发批量 text ops）
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);
    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_viewport_matches_reference(&mut executor, 0, 50);
}
