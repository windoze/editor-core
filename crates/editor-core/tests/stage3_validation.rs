//! Stage 3 validation tests
//!
//! Validation criteria:
//! 1. Dynamic reflow: After changing the viewport width, the total visual line count must update accordingly.
//! 2. Double-width wrapping: If a line has 1 cell remaining and the next character is double-width, it must wrap entirely to the next line.

use editor_core::layout::{LayoutEngine, calculate_wrap_points, char_width, str_width};

#[test]
fn test_dynamic_reflow() {
    println!("测试动态重排...");

    let lines = vec![
        "This is a long line that will need wrapping",
        "Short",
        "Another long line with lots of content here",
    ];

    // 宽视口
    let mut engine = LayoutEngine::new(50);
    engine.from_lines(&lines);

    let wide_visual_lines = engine.visual_line_count();
    println!("宽视口 (50)：{} 个视觉行", wide_visual_lines);
    assert_eq!(wide_visual_lines, 3); // 都不需要换行

    // 窄视口
    let mut engine = LayoutEngine::new(20);
    engine.from_lines(&lines);

    let narrow_visual_lines = engine.visual_line_count();
    println!("窄视口 (20)：{} 个视觉行", narrow_visual_lines);
    assert!(
        narrow_visual_lines > wide_visual_lines,
        "窄视口应该有更多视觉行"
    );

    // 非常窄的视口
    let mut engine = LayoutEngine::new(10);
    engine.from_lines(&lines);

    let very_narrow_visual_lines = engine.visual_line_count();
    println!("很窄视口 (10)：{} 个视觉行", very_narrow_visual_lines);
    assert!(
        very_narrow_visual_lines > narrow_visual_lines,
        "更窄的视口应该有更多视觉行"
    );

    println!("✓ 动态重排测试通过！");
}

#[test]
fn test_double_width_wrap() {
    println!("测试双宽字符换行...");

    // 测试场景：剩余 1 格，下一个字符是双宽
    // "Hello" = 5 格，"你" = 2 格，视口 = 6 格
    let text = "Hello你";
    let wraps = calculate_wrap_points(text, 6);

    println!("文本: {:?}", text);
    println!("视口宽度: 6");
    println!("'Hello' 宽度: {}", str_width("Hello"));
    println!("'你' 宽度: {}", char_width('你'));
    println!("换行点: {:?}", wraps);

    // "Hello" 占 5 格，剩余 1 格
    // "你" 需要 2 格，不能分割，必须完整换到下一行
    assert_eq!(wraps.len(), 1);
    assert_eq!(wraps[0].char_index, 5); // 在 "你" 之前换行

    // 类似测试：剩余 1 格，下一个是 emoji
    let text2 = "Hello👋";
    let wraps2 = calculate_wrap_points(text2, 6);

    println!("\n文本: {:?}", text2);
    println!("'👋' 宽度: {}", char_width('👋'));
    println!("换行点: {:?}", wraps2);

    assert_eq!(wraps2.len(), 1);
    assert_eq!(wraps2[0].char_index, 5);

    println!("✓ 双宽字符换行测试通过！");
}

#[test]
fn test_cjk_line_wrap() {
    println!("测试 CJK 行换行...");

    // 10 个 CJK 字符 = 20 个单元格
    let text = "你好世界这是测试文本";
    let char_count = text.chars().count();
    let total_width = str_width(text);

    println!("文本: {:?}", text);
    println!("字符数: {}", char_count);
    println!("总宽度: {}", total_width);

    assert_eq!(char_count, 10);
    assert_eq!(total_width, 20);

    // 视口宽度 10，每行最多 5 个 CJK 字符
    let wraps = calculate_wrap_points(text, 10);

    println!("视口: 10");
    println!("换行点数量: {}", wraps.len());

    // 应该有 1 个换行点（分成 2 行）
    assert_eq!(wraps.len(), 1);
    assert_eq!(wraps[0].char_index, 5); // 在第 5 个字符后换行

    println!("✓ CJK 行换行测试通过！");
}

#[test]
fn test_mixed_width_wrap() {
    println!("测试混合宽度字符换行...");

    // "Hello" = 5, "世界" = 4, "!" = 1，总共 10
    let text = "Hello世界!";
    assert_eq!(str_width(text), 10);

    // 视口宽度 10，正好填满
    let wraps1 = calculate_wrap_points(text, 10);
    assert_eq!(wraps1.len(), 0, "正好填满不应该换行");

    // 视口宽度 9，需要换行
    let wraps2 = calculate_wrap_points(text, 9);
    println!("视口 9，换行点: {:?}", wraps2);
    assert!(!wraps2.is_empty(), "宽度 9 应该需要换行");

    // 视口宽度 8，"Hello世" = 5 + 2 = 7
    let wraps3 = calculate_wrap_points(text, 8);
    println!("视口 8，换行点: {:?}", wraps3);
    assert!(!wraps3.is_empty());

    println!("✓ 混合宽度字符换行测试通过！");
}

#[test]
fn test_layout_engine_visual_line_count() {
    println!("测试布局引擎视觉行数...");

    let mut engine = LayoutEngine::new(10);

    // 添加不同长度的行
    engine.add_line("Short"); // 5 格，1 视觉行
    engine.add_line("1234567890"); // 10 格，1 视觉行
    engine.add_line("12345678901234567890"); // 20 格，2 视觉行
    engine.add_line("你好世界测试"); // 12 格（6 个 CJK），2 视觉行

    let total_logical = engine.logical_line_count();
    let total_visual = engine.visual_line_count();

    println!("逻辑行数: {}", total_logical);
    println!("视觉行数: {}", total_visual);

    assert_eq!(total_logical, 4);
    assert_eq!(total_visual, 6); // 1 + 1 + 2 + 2

    println!("✓ 视觉行数测试通过！");
}

#[test]
fn test_logical_visual_conversion() {
    println!("测试逻辑/视觉行号转换...");

    let mut engine = LayoutEngine::new(10);
    engine.from_lines(&[
        "Line 1",        // 6 格，1 视觉行，视觉行 0
        "1234567890abc", // 13 格，2 视觉行，视觉行 1-2
        "Short",         // 5 格，1 视觉行，视觉行 3
        "你好世界测试",  // 12 格，2 视觉行，视觉行 4-5
    ]);

    // 逻辑到视觉
    assert_eq!(engine.logical_to_visual_line(0), 0);
    assert_eq!(engine.logical_to_visual_line(1), 1);
    assert_eq!(engine.logical_to_visual_line(2), 3);
    assert_eq!(engine.logical_to_visual_line(3), 4);

    // 视觉到逻辑
    assert_eq!(engine.visual_to_logical_line(0), (0, 0));
    assert_eq!(engine.visual_to_logical_line(1), (1, 0));
    assert_eq!(engine.visual_to_logical_line(2), (1, 1));
    assert_eq!(engine.visual_to_logical_line(3), (2, 0));
    assert_eq!(engine.visual_to_logical_line(4), (3, 0));
    assert_eq!(engine.visual_to_logical_line(5), (3, 1));

    println!("✓ 逻辑/视觉行号转换测试通过！");
}

#[test]
fn test_viewport_width_change() {
    println!("测试视口宽度变化...");

    let lines = vec!["Hello World Programming"];

    // 宽视口
    let mut engine = LayoutEngine::new(30);
    engine.from_lines(&lines);
    assert_eq!(engine.visual_line_count(), 1);

    // 改变宽度并重新布局
    engine.set_viewport_width(10);
    engine.from_lines(&lines);
    let visual_after = engine.visual_line_count();

    println!("宽度 30：1 行");
    println!("宽度 10：{} 行", visual_after);
    assert!(visual_after > 1, "窄视口应该产生多行");

    println!("✓ 视口宽度变化测试通过！");
}

#[test]
fn test_edge_cases() {
    println!("测试边界情况...");

    let mut engine = LayoutEngine::new(10);

    // 空行
    engine.add_line("");
    assert_eq!(engine.visual_line_count(), 1);

    // 只有一个字符
    engine.add_line("a");
    assert_eq!(engine.visual_line_count(), 2);

    // 只有一个双宽字符
    engine.add_line("你");
    assert_eq!(engine.visual_line_count(), 3);

    // 正好填满
    engine.add_line("1234567890");
    assert_eq!(engine.visual_line_count(), 4);

    // 超出一个字符
    engine.add_line("12345678901");
    assert_eq!(engine.visual_line_count(), 6); // 需要 2 行

    println!("✓ 边界情况测试通过！");
}

#[test]
fn test_zero_width_viewport() {
    println!("测试零宽度视口...");

    let text = "Hello World";
    let wraps = calculate_wrap_points(text, 0);

    // 零宽度视口应该返回空的换行点列表
    assert_eq!(wraps.len(), 0);

    println!("✓ 零宽度视口测试通过！");
}

#[test]
fn test_very_long_line() {
    println!("测试非常长的行...");

    // 创建一个 1000 字符的行
    let long_line = "a".repeat(1000);

    let wraps = calculate_wrap_points(&long_line, 80);

    // 1000 / 80 = 12.5，所以需要 12 个换行点（13 行）
    let expected_wraps = 12;
    assert_eq!(
        wraps.len(),
        expected_wraps,
        "应该有 {} 个换行点",
        expected_wraps
    );

    // 验证换行点位置
    for (i, wrap) in wraps.iter().enumerate() {
        let expected_pos = (i + 1) * 80;
        assert_eq!(
            wrap.char_index, expected_pos,
            "第 {} 个换行点应该在位置 {}",
            i, expected_pos
        );
    }

    println!("✓ 非常长的行测试通过！");
}

#[test]
fn test_consecutive_double_width() {
    println!("测试连续双宽字符...");

    // 连续的双宽字符
    let text = "你好世界测试文本";
    let char_count = text.chars().count();
    let width = str_width(text);

    println!("字符数: {}", char_count);
    println!("总宽度: {}", width);

    assert_eq!(char_count, 8);
    assert_eq!(width, 16); // 每个字符 2 格

    // 视口宽度 10，应该在第 5 个字符后换行
    let wraps = calculate_wrap_points(text, 10);
    assert_eq!(wraps.len(), 1);
    assert_eq!(wraps[0].char_index, 5);

    println!("✓ 连续双宽字符测试通过！");
}
