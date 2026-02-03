//! End-to-end integration tests
//!
//! Tests the full editor workflow.

use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, EditorStateManager, Position,
    StateChangeType, StyleCommand, ViewCommand,
};

/// Test a full editing session.
#[test]
fn test_full_editing_session() {
    println!("测试完整编辑会话...");

    // 1. 创建编辑器
    let mut executor = CommandExecutor::empty(80);

    // 2. 插入初始内容
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "fn main() {\n    println!(\"Hello\");\n}\n".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().line_count(), 4);
    assert!(executor.editor().get_text().contains("Hello"));

    // 3. 移动光标到第二行
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 4,
        }))
        .unwrap();

    assert_eq!(executor.editor().cursor_position(), Position::new(1, 4));

    // 4. 设置选择范围
    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(1, 4),
            end: Position::new(1, 27),
        }))
        .unwrap();

    assert!(executor.editor().selection().is_some());

    // 5. 替换选中文本
    executor
        .execute(Command::Edit(EditCommand::Replace {
            start: 8,   // "fn main() {\n    " 之后
            length: 19, // println!("Hello");
            text: "println!(\"World\");".to_string(),
        }))
        .unwrap();

    assert!(executor.editor().get_text().contains("World"));
    assert!(!executor.editor().get_text().contains("Hello"));

    // 6. 添加样式
    executor
        .execute(Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 2,
            style_id: 1, // 关键字样式
        }))
        .unwrap();

    // 7. 获取视口
    let result = executor.execute(Command::View(ViewCommand::GetViewport {
        start_row: 0,
        count: 10,
    }));

    assert!(result.is_ok());

    println!("✓ 完整编辑会话测试通过");
}

/// Test state management integration.
#[test]
fn test_state_management_integration() {
    println!("测试状态管理集成...");

    let mut manager = EditorStateManager::new("Initial text", 80);

    // 记录初始状态
    let initial_version = manager.version();
    let initial_state = manager.get_full_state();

    assert_eq!(initial_state.document.line_count, 1);
    assert!(!initial_state.document.is_modified);

    // 修改文档
    manager.editor_mut().piece_table.insert(0, "New: ");
    manager.editor_mut().line_index =
        editor_core::LineIndex::from_text(&manager.editor().get_text());
    manager.mark_modified(StateChangeType::DocumentModified);

    // 验证状态变更
    assert!(manager.version() > initial_version);
    assert!(manager.has_changed_since(initial_version));
    assert!(manager.get_document_state().is_modified);

    // 保存文档
    manager.mark_saved();
    assert!(!manager.get_document_state().is_modified);

    println!("✓ 状态管理集成测试通过");
}

/// Test multi-cursor editing scenario (simulated).
#[test]
fn test_multi_cursor_scenario() {
    println!("测试多光标编辑场景...");

    let mut executor = CommandExecutor::new("line1\nline2\nline3\n", 80);

    // 在每行开头插入行号
    // 第1行
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "1: ".to_string(),
        }))
        .unwrap();

    // 第2行 (offset需要调整，因为前面插入了3个字符)
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 9, // "1: line1\n" = 9
            text: "2: ".to_string(),
        }))
        .unwrap();

    // 第3行
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 18, // "1: line1\n2: line2\n" = 18
            text: "3: ".to_string(),
        }))
        .unwrap();

    let text = executor.editor().get_text();
    assert!(text.contains("1: line1"));
    assert!(text.contains("2: line2"));
    assert!(text.contains("3: line3"));

    println!("✓ 多光标编辑场景测试通过");
}

/// Test large file performance.
#[test]
fn test_large_file_performance() {
    println!("测试大文件性能...");

    use std::time::Instant;

    // 创建一个中等大小的文档（1000行）
    let mut lines = Vec::new();
    for i in 0..1000 {
        lines.push(format!("Line {} with some content to make it realistic", i));
    }
    let text = lines.join("\n");

    // 测试加载性能
    let start = Instant::now();
    let mut executor = CommandExecutor::new(&text, 80);
    let load_time = start.elapsed();

    println!("  加载1000行耗时: {:?}", load_time);
    assert!(load_time.as_millis() < 100, "加载时间过长");

    // 测试插入性能
    let start = Instant::now();
    for i in 0..100 {
        let offset = i * 50; // 分散插入
        executor
            .execute(Command::Edit(EditCommand::Insert {
                offset: offset.min(executor.editor().char_count()),
                text: "X".to_string(),
            }))
            .unwrap();
    }
    let insert_time = start.elapsed();

    println!("  100次插入耗时: {:?}", insert_time);
    assert!(insert_time.as_millis() < 100, "插入时间过长");

    // 测试行访问性能
    let start = Instant::now();
    for _ in 0..1000 {
        let _ = executor.editor().line_count();
    }
    let access_time = start.elapsed();

    println!("  1000次行访问耗时: {:?}", access_time);
    assert!(access_time.as_millis() < 10, "访问时间过长");

    println!("✓ 大文件性能测试通过");
}

/// Test Unicode handling.
#[test]
fn test_unicode_handling() {
    println!("测试Unicode处理...");

    let mut executor = CommandExecutor::new("Hello 世界 👋\nこんにちは\n🎉🎊🎈", 80);

    // 验证行数正确
    assert_eq!(executor.editor().line_count(), 3);

    // 在Unicode字符中插入
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 6, // "Hello " 之后
            text: "美丽的".to_string(),
        }))
        .unwrap();

    let text = executor.editor().get_text();
    assert!(text.contains("Hello 美丽的世界"));

    // 删除emoji
    executor
        .execute(Command::Edit(EditCommand::Delete {
            start: text.find('👋').unwrap(),
            length: 1,
        }))
        .unwrap();

    println!("✓ Unicode处理测试通过");
}

/// Test error recovery.
#[test]
fn test_error_recovery() {
    println!("测试错误恢复...");

    let mut executor = CommandExecutor::new("Test", 80);

    // 尝试无效操作
    let result = executor.execute(Command::Edit(EditCommand::Insert {
        offset: 1000,
        text: "X".to_string(),
    }));

    assert!(result.is_err());

    // 验证编辑器仍然可用
    let result = executor.execute(Command::Edit(EditCommand::Insert {
        offset: 4,
        text: " OK".to_string(),
    }));

    assert!(result.is_ok());
    assert_eq!(executor.editor().get_text(), "Test OK");

    println!("✓ 错误恢复测试通过");
}

/// Test command history.
#[test]
fn test_command_history() {
    println!("测试命令历史...");

    let mut executor = CommandExecutor::empty(80);

    // 执行一系列命令
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "A".to_string(),
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 1,
            text: "B".to_string(),
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 2,
            text: "C".to_string(),
        }))
        .unwrap();

    // 验证历史记录
    assert_eq!(executor.get_command_history().len(), 3);
    assert_eq!(executor.editor().get_text(), "ABC");

    println!("✓ 命令历史测试通过");
}

/// Test style and folding integration.
#[test]
fn test_styles_and_folding() {
    println!("测试样式和折叠集成...");

    let mut manager =
        EditorStateManager::new("fn main() {\n    code();\n    more_code();\n}\n", 80);

    // 添加样式
    manager.editor_mut().interval_tree.insert(
        editor_core::intervals::Interval::new(0, 2, 1), // "fn" 关键字
    );

    // 添加折叠区域
    let mut region = editor_core::intervals::FoldRegion::new(1, 2);
    region.collapse();
    manager.editor_mut().folding_manager.add_region(region);

    // 验证状态
    let folding_state = manager.get_folding_state();
    assert_eq!(folding_state.regions.len(), 1);
    assert_eq!(folding_state.collapsed_line_count, 1);

    let style_state = manager.get_style_state();
    assert_eq!(style_state.style_count, 1);

    // 查询样式
    let styles = manager.get_styles_at(0);
    assert_eq!(styles.len(), 1);
    assert_eq!(styles[0], 1);

    println!("✓ 样式和折叠集成测试通过");
}

/// Test batch command execution.
#[test]
fn test_batch_commands() {
    println!("测试批量命令执行...");

    let mut executor = CommandExecutor::empty(80);

    let commands = vec![
        Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "Line 1\n".to_string(),
        }),
        Command::Edit(EditCommand::Insert {
            offset: 7,
            text: "Line 2\n".to_string(),
        }),
        Command::Edit(EditCommand::Insert {
            offset: 14,
            text: "Line 3\n".to_string(),
        }),
        Command::Cursor(CursorCommand::MoveTo { line: 1, column: 0 }),
    ];

    let results = executor.execute_batch(commands);
    assert!(results.is_ok());

    assert_eq!(executor.editor().line_count(), 4);
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 0));

    println!("✓ 批量命令执行测试通过");
}

/// Test viewport management.
#[test]
fn test_viewport_management() {
    println!("测试视口管理...");

    let mut manager = EditorStateManager::new(
        &(0..100)
            .map(|i| format!("Line {}", i))
            .collect::<Vec<_>>()
            .join("\n"),
        80,
    );

    manager.set_viewport_height(20);
    manager.set_scroll_top(0);

    let viewport = manager.get_viewport_state();
    assert_eq!(viewport.visible_lines, 0..20);

    // 滚动到中间
    manager.set_scroll_top(40);
    let viewport = manager.get_viewport_state();
    assert_eq!(viewport.visible_lines, 40..60);

    // 获取视口内容
    let content = manager.get_viewport_content(40, 20);
    assert!(content.actual_line_count() <= 20);

    println!("✓ 视口管理测试通过");
}
