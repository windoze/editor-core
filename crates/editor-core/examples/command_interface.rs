//! Command interface example
//!
//! Demonstrates how to use `CommandExecutor` to drive the editor.

use editor_core::{
    Command, CommandExecutor, CommandResult, CursorCommand, EditCommand, Position, StyleCommand,
    ViewCommand,
};

fn main() {
    println!("=== 编辑器命令接口示例 ===\n");

    // 创建命令执行器，初始文本为空，视口宽度80
    let mut executor = CommandExecutor::new("", 80);
    println!("初始化空编辑器\n");

    // 示例 1：文本编辑
    println!("1. 文本编辑操作：");

    // 插入文本
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "Hello World".to_string(),
        }))
        .unwrap();
    println!("  插入 'Hello World'");
    println!("  当前文本: '{}'", executor.editor().get_text());

    // 替换文本
    executor
        .execute(Command::Edit(EditCommand::Replace {
            start: 6,
            length: 5,
            text: "Rust".to_string(),
        }))
        .unwrap();
    println!("  替换 'World' 为 'Rust'");
    println!("  当前文本: '{}'\n", executor.editor().get_text());

    // 示例 2：光标操作
    println!("2. 光标操作：");

    // 移动光标
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 5,
        }))
        .unwrap();
    println!("  移动光标到 (0, 5)");
    println!("  当前光标位置: {:?}", executor.editor().cursor_position());

    // 创建选择
    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 0),
            end: Position::new(0, 5),
        }))
        .unwrap();
    println!("  选择文本从 (0, 0) 到 (0, 5)");
    println!("  当前选择: {:?}\n", executor.editor().selection());

    // 示例 3：视图操作
    println!("3. 视图操作：");

    // 设置视口宽度
    executor
        .execute(Command::View(ViewCommand::SetViewportWidth { width: 40 }))
        .unwrap();
    println!("  设置视口宽度为 40");

    // 获取视口内容
    if let Ok(CommandResult::Viewport(grid)) =
        executor.execute(Command::View(ViewCommand::GetViewport {
            start_row: 0,
            count: 10,
        }))
    {
        println!("  获取视口快照:");
        println!("    行数: {}", grid.actual_line_count());
        println!("    起始行: {}", grid.start_visual_row);
    }
    println!();

    // 示例 4：样式操作
    println!("4. 样式操作：");

    // 添加样式
    executor
        .execute(Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 5,
            style_id: 1, // 假设 1 是关键字样式
        }))
        .unwrap();
    println!("  添加样式 ID 1 到范围 [0, 5)");

    // 折叠操作（需要多行文档）
    let mut multi_line_executor = CommandExecutor::new(
        "fn main() {\n    println!(\"Hello\");\n    println!(\"World\");\n}",
        80,
    );

    multi_line_executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 2,
        }))
        .unwrap();
    println!("  折叠行 1-2\n");

    // 示例 5：批量命令
    println!("5. 批量命令执行：");

    let mut batch_executor = CommandExecutor::empty(80);
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
            text: "Line 3".to_string(),
        }),
    ];

    batch_executor.execute_batch(commands).unwrap();
    println!("  批量执行 3 个插入命令");
    println!("  最终文本:");
    for (i, line) in batch_executor.editor().get_text().lines().enumerate() {
        println!("    行 {}: '{}'", i, line);
    }
    println!();

    // 示例 6：错误处理
    println!("6. 错误处理：");

    let mut error_executor = CommandExecutor::new("Short", 80);

    // 尝试在无效偏移处插入
    match error_executor.execute(Command::Edit(EditCommand::Insert {
        offset: 100,
        text: "X".to_string(),
    })) {
        Ok(_) => println!("  意外成功"),
        Err(e) => println!("  预期错误: {}", e),
    }

    // 尝试删除超出范围
    match error_executor.execute(Command::Edit(EditCommand::Delete {
        start: 0,
        length: 100,
    })) {
        Ok(_) => println!("  意外成功"),
        Err(e) => println!("  预期错误: {}", e),
    }
    println!();

    // 示例 7：命令历史
    println!("7. 命令历史：");
    println!("  总命令数: {}", executor.get_command_history().len());
    println!("  最近 3 个命令:");
    for (i, cmd) in executor
        .get_command_history()
        .iter()
        .rev()
        .take(3)
        .enumerate()
    {
        println!("    {}: {:?}", i + 1, cmd);
    }

    println!("\n=== 示例完成 ===");
}
