//! State management example
//!
//! Demonstrates how to use `EditorStateManager` to query editor state.

use editor_core::{EditorStateManager, Position, StateChangeType};
use std::sync::{Arc, Mutex};

fn main() {
    println!("=== 编辑器状态管理示例 ===\n");

    // 创建状态管理器
    let mut manager =
        EditorStateManager::new("fn main() {\n    println!(\"Hello, World!\");\n}\n", 80);

    println!("1. 初始文档状态：");
    print_document_state(&manager);

    println!("\n2. 光标状态：");
    print_cursor_state(&manager);

    println!("\n3. 视口状态：");
    manager.set_viewport_height(20);
    print_viewport_state(&manager);

    println!("\n4. 折叠状态：");
    print_folding_state(&manager);

    println!("\n5. 样式状态：");
    print_style_state(&manager);

    // 状态变更监听
    println!("\n6. 状态变更监听：");
    let change_count = Arc::new(Mutex::new(0));
    let change_count_clone = change_count.clone();

    manager.subscribe(move |change| {
        let mut count = change_count_clone.lock().unwrap();
        *count += 1;
        println!(
            "  状态变更 #{}: {:?} (版本: {} -> {})",
            count, change.change_type, change.old_version, change.new_version
        );
    });

    // 修改文档
    println!("\n7. 执行编辑操作：");
    manager.editor_mut().piece_table.insert(0, "// Comment\n");
    manager.editor_mut().line_index =
        editor_core::LineIndex::from_text(&manager.editor().get_text());
    manager.mark_modified(StateChangeType::DocumentModified);

    println!("  文档已修改");
    println!("  新版本号: {}", manager.version());
    println!("  是否修改: {}", manager.get_document_state().is_modified);

    // 移动光标
    manager.editor_mut().cursor_position = Position::new(1, 4);
    manager.mark_modified(StateChangeType::CursorMoved);

    println!("\n8. 光标移动后：");
    print_cursor_state(&manager);

    // 设置选择
    println!("\n9. 设置选择范围：");
    let selection = editor_core::Selection {
        start: Position::new(0, 0),
        end: Position::new(0, 10),
        direction: editor_core::SelectionDirection::Forward,
    };
    manager.editor_mut().selection = Some(selection);
    manager.mark_modified(StateChangeType::SelectionChanged);

    let cursor_state = manager.get_cursor_state();
    if let Some(sel) = &cursor_state.selection {
        println!("  选择: {:?} -> {:?}", sel.start, sel.end);
    }

    // 滚动视口
    println!("\n10. 视口滚动：");
    println!(
        "  滚动前: scroll_top = {}",
        manager.get_viewport_state().scroll_top
    );
    manager.set_scroll_top(5);
    println!(
        "  滚动后: scroll_top = {}",
        manager.get_viewport_state().scroll_top
    );

    // 版本跟踪
    println!("\n11. 版本跟踪：");
    let current_version = manager.version();
    println!("  当前版本: {}", current_version);
    println!("  从版本 0 开始变更: {}", manager.has_changed_since(0));
    println!(
        "  从版本 {} 开始变更: {}",
        current_version,
        manager.has_changed_since(current_version)
    );

    // 保存文档
    println!("\n12. 保存文档：");
    println!(
        "  保存前是否修改: {}",
        manager.get_document_state().is_modified
    );
    manager.mark_saved();
    println!(
        "  保存后是否修改: {}",
        manager.get_document_state().is_modified
    );

    // 获取完整状态
    println!("\n13. 完整状态快照：");
    let full_state = manager.get_full_state();
    println!("  文档行数: {}", full_state.document.line_count);
    println!("  文档字符数: {}", full_state.document.char_count);
    println!("  光标位置: {:?}", full_state.cursor.position);
    println!("  视口宽度: {}", full_state.viewport.width);
    println!("  样式数量: {}", full_state.style.style_count);
    println!("  诊断数量: {}", full_state.diagnostics.diagnostics_count);
    println!("  装饰数量: {}", full_state.decorations.decoration_count);
    println!("  总状态变更: {}", *change_count.lock().unwrap());

    // 获取视口内容
    println!("\n14. 获取视口内容：");
    let viewport_content = manager.get_viewport_content(0, 5);
    println!("  视口行数: {}", viewport_content.actual_line_count());
    for (i, line) in viewport_content.lines.iter().take(3).enumerate() {
        println!("  行 {}: {} 个单元格", i, line.cells.len());
    }

    println!("\n=== 示例完成 ===");
}

fn print_document_state(manager: &EditorStateManager) {
    let state = manager.get_document_state();
    println!("  总行数: {}", state.line_count);
    println!("  总字符数: {}", state.char_count);
    println!("  总字节数: {}", state.byte_count);
    println!("  是否修改: {}", state.is_modified);
    println!("  版本号: {}", state.version);
}

fn print_cursor_state(manager: &EditorStateManager) {
    let state = manager.get_cursor_state();
    println!(
        "  位置: 行 {}, 列 {}",
        state.position.line, state.position.column
    );
    println!("  字符偏移: {}", state.offset);
    println!("  选择: {:?}", state.selection.is_some());
}

fn print_viewport_state(manager: &EditorStateManager) {
    let state = manager.get_viewport_state();
    println!("  宽度: {}", state.width);
    println!("  高度: {:?}", state.height);
    println!("  滚动位置: {}", state.scroll_top);
    println!("  可见行范围: {:?}", state.visible_lines);
}

fn print_folding_state(manager: &EditorStateManager) {
    let state = manager.get_folding_state();
    println!("  折叠区域数: {}", state.regions.len());
    println!("  折叠行数: {}", state.collapsed_line_count);
    println!("  可见逻辑行数: {}", state.visible_logical_lines);
    println!("  总视觉行数: {}", state.total_visual_lines);
}

fn print_style_state(manager: &EditorStateManager) {
    let state = manager.get_style_state();
    println!("  样式数量: {}", state.style_count);
}
