//! Stage 6 validation tests
//!
//! End-to-end integration tests: validates the full pipeline from text input to headless grid output.

use editor_core::{Cell, LayoutEngine, LineIndex, SnapshotGenerator, storage::PieceTable};

/// Test basic snapshot generation flow.
#[test]
fn test_basic_snapshot_generation() {
    println!("测试基本快照生成流程...");

    let text = "Hello World\n你好世界\nRust编程";
    let generator = SnapshotGenerator::from_text(text, 80);

    // 获取所有行
    let grid = generator.get_headless_grid(0, 3);

    assert_eq!(grid.actual_line_count(), 3);
    assert_eq!(grid.lines[0].logical_line_index, 0);
    assert_eq!(grid.lines[1].logical_line_index, 1);
    assert_eq!(grid.lines[2].logical_line_index, 2);

    // 验证第一行
    let line0 = &grid.lines[0];
    assert_eq!(line0.cells.len(), 11); // "Hello World"
    assert_eq!(line0.cells[0].ch, 'H');
    assert_eq!(line0.cells[0].width, 1);

    // 验证第二行（CJK）
    let line1 = &grid.lines[1];
    assert_eq!(line1.cells.len(), 4); // 4个CJK字符
    assert_eq!(line1.visual_width(), 8); // 每个CJK字符占2格

    println!("✓ 基本快照生成测试通过！");
}

/// Test integration with `PieceTable`.
#[test]
fn test_integration_with_piece_table() {
    println!("测试与 PieceTable 的集成...");

    let mut piece_table = PieceTable::new("Line 1\nLine 2\nLine 3");

    // 修改文档
    piece_table.insert(0, "New ");
    piece_table.insert(piece_table.char_count(), "\nLine 4");

    let text = piece_table.get_text();
    let generator = SnapshotGenerator::from_text(&text, 80);

    let grid = generator.get_headless_grid(0, 10);
    assert_eq!(grid.actual_line_count(), 4);

    // 验证修改后的内容
    assert_eq!(generator.get_line(0), Some("New Line 1"));
    assert_eq!(generator.get_line(3), Some("Line 4"));

    println!("✓ PieceTable 集成测试通过！");
}

/// Test integration with `LineIndex`.
#[test]
fn test_integration_with_line_index() {
    println!("测试与 LineIndex 的集成...");

    let text = "First line\nSecond line\nThird line";
    let piece_table = PieceTable::new(text);
    let line_index = LineIndex::from_text(&piece_table.get_text());

    // 验证行数
    assert_eq!(line_index.line_count(), 3);

    // 使用首列 position 获取每行在规范文本中的起始 char offset。
    let line0_offset = line_index.position_to_char_offset(0, 0);
    let line1_offset = line_index.position_to_char_offset(1, 0);
    let line2_offset = line_index.position_to_char_offset(2, 0);

    assert_eq!(line0_offset, 0);
    assert_eq!(line1_offset, 11); // "First line\n"
    assert_eq!(line2_offset, 23); // "First line\nSecond line\n"

    // 生成快照
    let generator = SnapshotGenerator::from_text(text, 80);
    let grid = generator.get_headless_grid(0, 3);

    assert_eq!(grid.actual_line_count(), 3);

    println!("✓ LineIndex 集成测试通过！");
}

/// Test integration with `LayoutEngine` (soft wrapping).
#[test]
fn test_integration_with_layout_engine() {
    println!("测试与 LayoutEngine 的集成...");

    // 创建一个需要软换行的长行
    let text = "This is a very long line that should wrap when the viewport is narrow";

    // 使用窄视口
    let viewport_width = 20;
    let mut layout_engine = LayoutEngine::new(viewport_width);
    let lines: Vec<&str> = text.lines().collect();
    layout_engine.from_lines(&lines);

    // 计算视觉行数
    let visual_line_count = layout_engine.visual_line_count();
    assert!(visual_line_count > 1, "应该有多个视觉行");

    println!(
        "  视口宽度: {}, 视觉行数: {}",
        viewport_width, visual_line_count
    );

    let generator = SnapshotGenerator::from_text(text, viewport_width);
    let grid = generator.get_headless_grid(0, 10);

    // SnapshotGenerator 应与 LayoutEngine 的视觉行计算保持一致。
    assert_eq!(grid.actual_line_count(), visual_line_count.min(10));
    assert_eq!(grid.lines[0].logical_line_index, 0);
    assert!(!grid.lines[0].is_wrapped_part);
    if grid.actual_line_count() > 1 {
        assert_eq!(grid.lines[1].logical_line_index, 0);
        assert!(grid.lines[1].is_wrapped_part);
    }

    println!("✓ LayoutEngine 集成测试通过！");
}

/// Test snapshot generation with styles.
#[test]
fn test_snapshot_with_styles() {
    println!("测试带样式的快照生成...");

    let text = "Hello World";
    let generator = SnapshotGenerator::from_text(text, 80);

    // 获取快照
    let grid = generator.get_headless_grid(0, 1);
    let line = &grid.lines[0];

    // 验证单元格
    assert_eq!(line.cells.len(), 11);

    // `SnapshotGenerator` 本身不负责样式合成；带样式快照由 `EditorCore::get_headless_grid_styled`
    // / `EditorStateManager::get_viewport_content_styled` 覆盖。这里验证默认样式为空即可。
    for cell in &line.cells {
        assert!(cell.styles.is_empty());
    }

    // 测试手动创建带样式的单元格
    let styled_cell = Cell::with_styles('H', 1, vec![1, 2, 3]);
    assert_eq!(styled_cell.styles, vec![1, 2, 3]);

    println!("✓ 样式快照测试通过！");
}

/// Test paginated snapshots.
#[test]
fn test_paginated_snapshot() {
    println!("测试分页获取快照...");

    // 创建100行文档
    let mut lines = Vec::new();
    for i in 0..100 {
        lines.push(format!("Line {}", i));
    }
    let text = lines.join("\n");

    let generator = SnapshotGenerator::from_text(&text, 80);

    // 分页获取
    let page_size = 20;

    // 第一页
    let page1 = generator.get_headless_grid(0, page_size);
    assert_eq!(page1.start_visual_row, 0);
    assert_eq!(page1.actual_line_count(), page_size);

    // 第二页
    let page2 = generator.get_headless_grid(20, page_size);
    assert_eq!(page2.start_visual_row, 20);
    assert_eq!(page2.actual_line_count(), page_size);

    // 最后一页
    let page_last = generator.get_headless_grid(80, page_size);
    assert_eq!(page_last.start_visual_row, 80);
    assert_eq!(page_last.actual_line_count(), 20); // 只剩20行

    // 验证内容
    let first_line = &page1.lines[0];
    let last_line = &page_last.lines[19];

    // 通过检查单元格内容来验证
    assert_eq!(first_line.logical_line_index, 0);
    assert_eq!(last_line.logical_line_index, 99);

    println!("✓ 分页快照测试通过！");
}

/// Test dynamic update scenario.
#[test]
fn test_dynamic_update_scenario() {
    println!("测试动态更新场景...");

    // 初始文档
    let mut piece_table = PieceTable::new("Line 1\nLine 2\nLine 3");
    let mut generator = SnapshotGenerator::from_text(&piece_table.get_text(), 80);

    // 初始快照
    let grid1 = generator.get_headless_grid(0, 3);
    assert_eq!(grid1.actual_line_count(), 3);

    // 修改文档
    piece_table.insert(7, "NEW ");

    // 更新快照生成器
    let updated_text = piece_table.get_text();
    generator.set_lines(
        updated_text
            .split('\n')
            .map(|s| s.strip_suffix('\r').unwrap_or(s).to_string())
            .collect(),
    );

    // 新快照
    let grid2 = generator.get_headless_grid(0, 3);
    assert_eq!(grid2.actual_line_count(), 3);

    // 验证第二行已更新
    assert_eq!(generator.get_line(1), Some("NEW Line 2"));

    println!("✓ 动态更新测试通过！");
}

/// Test empty documents and edge cases.
#[test]
fn test_edge_cases() {
    println!("测试边界情况...");

    // 空文档
    let empty_gen = SnapshotGenerator::new(80);
    let empty_grid = empty_gen.get_headless_grid(0, 10);
    assert_eq!(empty_grid.actual_line_count(), 1);

    // 单行文档
    let single_gen = SnapshotGenerator::from_text("Single line", 80);
    let single_grid = single_gen.get_headless_grid(0, 10);
    assert_eq!(single_grid.actual_line_count(), 1);

    // 只有换行符的文档
    let newline_gen = SnapshotGenerator::from_text("\n\n\n", 80);
    let newline_grid = newline_gen.get_headless_grid(0, 10);
    assert_eq!(newline_grid.actual_line_count(), 4);

    // 每行应该是空的
    for line in &newline_grid.lines {
        assert_eq!(line.cells.len(), 0);
        assert_eq!(line.visual_width(), 0);
    }

    println!("✓ 边界情况测试通过！");
}

/// Test snapshot performance on large documents.
#[test]
fn test_large_document_snapshot() {
    println!("测试大文档快照性能...");

    // 创建1000行文档
    let mut lines = Vec::new();
    for i in 0..1000 {
        lines.push(format!("This is line {} with some content", i));
    }
    let text = lines.join("\n");

    let generator = SnapshotGenerator::from_text(&text, 80);

    println!("  文档行数: {}", generator.line_count());

    // 获取不同位置的快照
    let snapshots = [
        generator.get_headless_grid(0, 50),
        generator.get_headless_grid(500, 50),
        generator.get_headless_grid(950, 50),
    ];

    for (i, snapshot) in snapshots.iter().enumerate() {
        println!(
            "  快照 {}: 起始行 {}, 实际行数 {}",
            i,
            snapshot.start_visual_row,
            snapshot.actual_line_count()
        );
        assert!(snapshot.actual_line_count() > 0);
    }

    println!("✓ 大文档快照性能测试通过！");
}

/// Test the full pipeline with complex Unicode.
#[test]
fn test_unicode_full_pipeline() {
    println!("测试 Unicode 完整管道...");

    // 混合 ASCII、CJK、Emoji 的文档
    let text = "Hello 👋\n你好世界 🌍\nRust 编程语言\nEmoji: 👨‍👩‍👧‍👦";

    let mut piece_table = PieceTable::new(text);
    let line_index = LineIndex::from_text(&piece_table.get_text());
    let generator = SnapshotGenerator::from_text(&piece_table.get_text(), 80);

    // 验证行数一致
    assert_eq!(line_index.line_count(), 4);
    assert_eq!(generator.line_count(), 4);

    // 获取快照
    let grid = generator.get_headless_grid(0, 4);
    assert_eq!(grid.actual_line_count(), 4);

    // 验证第一行：Hello 👋
    let line0 = &grid.lines[0];
    assert_eq!(line0.cells.len(), 7); // H,e,l,l,o,空格,👋

    // 验证第二行：你好世界 🌍
    let line1 = &grid.lines[1];
    // 4个CJK字符 + 空格 + emoji
    assert_eq!(line1.cells.len(), 6);

    // 修改文档并验证
    piece_table.insert(0, "NEW: ");
    let updated_text = piece_table.get_text();
    let updated_gen = SnapshotGenerator::from_text(&updated_text, 80);
    let updated_grid = updated_gen.get_headless_grid(0, 1);

    // 第一行应该变长了
    assert!(updated_grid.lines[0].cells.len() > line0.cells.len());

    println!("✓ Unicode 完整管道测试通过！");
}

/// Test viewport width changes.
#[test]
fn test_viewport_width_changes() {
    println!("测试视口宽度变化...");

    let text = "This is a line with some content\nAnother line here";
    let mut generator = SnapshotGenerator::from_text(text, 80);

    // 宽视口
    let grid_wide = generator.get_headless_grid(0, 2);
    assert_eq!(grid_wide.actual_line_count(), 2);

    // 改变视口宽度
    generator.set_viewport_width(20);

    // 视口变窄后，第一行应发生软换行，从而产生更多视觉行。
    let grid_narrow = generator.get_headless_grid(0, 10);
    assert_eq!(grid_narrow.actual_line_count(), 3);
    assert_eq!(grid_narrow.lines[0].logical_line_index, 0);
    assert!(!grid_narrow.lines[0].is_wrapped_part);
    assert_eq!(grid_narrow.lines[1].logical_line_index, 0);
    assert!(grid_narrow.lines[1].is_wrapped_part);
    assert_eq!(grid_narrow.lines[2].logical_line_index, 1);
    assert!(!grid_narrow.lines[2].is_wrapped_part);

    println!("✓ 视口宽度变化测试通过！");
}
