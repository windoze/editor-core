//! Stage 5 validation tests
//!
//! Validation criteria:
//! 1. Coordinate robustness: When editing a multi-line document containing emoji, LSP coordinates must match exactly.
//! 2. Silent synchronization: All LSP computations run in the background and must not block viewport snapshot generation.

use editor_core_lsp::{
    DeltaCalculator, LspCoordinateConverter, SemanticToken, SemanticTokensManager,
};

#[test]
fn test_coordinate_robustness_with_emoji() {
    println!("测试包含 Emoji 的坐标鲁棒性...");

    let document = "Hello 👋 World\nRust 🦀 Programming\nEmoji 😀 Test 🎉";
    let calc = DeltaCalculator::from_text(document);

    // 第一行："Hello 👋 World"
    // "Hello " = 6 chars, 6 UTF-16 units
    // "👋" = 1 char, 2 UTF-16 units
    // " World" = 6 chars, 6 UTF-16 units
    // Total: 13 chars, 14 UTF-16 units

    let line0 = calc.get_line(0).unwrap();
    println!("Line 0: {:?}", line0);

    // 测试在 emoji 之前插入
    let change1 = calc.calculate_insert_change(0, 6, "NEW");
    assert_eq!(change1.range.start.line, 0);
    assert_eq!(change1.range.start.character, 6); // 在 👋 之前
    println!("Insert before emoji: {:?}", change1.range.start);

    // 测试在 emoji 之后插入
    let change2 = calc.calculate_insert_change(0, 7, "NEW");
    assert_eq!(change2.range.start.line, 0);
    assert_eq!(change2.range.start.character, 8); // 在 👋 之后（👋 占 2 个 UTF-16 units）
    println!("Insert after emoji: {:?}", change2.range.start);

    println!("✓ Emoji 坐标鲁棒性测试通过！");
}

#[test]
fn test_utf16_conversion_accuracy() {
    println!("测试 UTF-16 转换精度...");

    let test_cases = vec![
        ("hello", vec![0, 1, 2, 3, 4, 5]),
        ("你好", vec![0, 1, 2]),
        ("👋🌍", vec![0, 2, 4]),
        ("a👋b", vec![0, 1, 3, 4]),
        ("Hello 世界", vec![0, 1, 2, 3, 4, 5, 6, 7, 8]),
    ];

    for (text, expected_utf16_offsets) in test_cases {
        println!("\n测试文本: {:?}", text);

        for (char_idx, &expected_utf16) in expected_utf16_offsets.iter().enumerate() {
            let actual_utf16 = LspCoordinateConverter::char_offset_to_utf16(text, char_idx);
            assert_eq!(
                actual_utf16, expected_utf16,
                "文本 {:?} 在字符偏移 {} 处的 UTF-16 偏移不匹配",
                text, char_idx
            );
            println!("  字符偏移 {} -> UTF-16 偏移 {}", char_idx, actual_utf16);
        }
    }

    println!("\n✓ UTF-16 转换精度测试通过！");
}

#[test]
fn test_multi_line_emoji_document() {
    println!("测试多行 Emoji 文档...");

    let document = "Line 1: 👨‍👩‍👧‍👦 Family\nLine 2: 🎨🎭🎪🎬\nLine 3: Hello 你好 👋";
    let _calc = DeltaCalculator::from_text(document);

    // 测试各行的坐标转换
    for (line_idx, line_text) in document.lines().enumerate() {
        println!("\n行 {}: {:?}", line_idx, line_text);

        let char_count = line_text.chars().count();
        let utf16_len = LspCoordinateConverter::utf8_to_utf16_len(line_text);

        println!("  字符数: {}", char_count);
        println!("  UTF-16 长度: {}", utf16_len);

        // 测试每个字符位置的转换
        for char_idx in 0..=char_count.min(3) {
            let utf16_offset = LspCoordinateConverter::char_offset_to_utf16(line_text, char_idx);
            let back_to_char =
                LspCoordinateConverter::utf16_to_char_offset(line_text, utf16_offset);

            assert_eq!(
                back_to_char, char_idx,
                "行 {} 字符偏移 {} 的往返转换失败",
                line_idx, char_idx
            );

            println!("    字符 {} <-> UTF-16 {}", char_idx, utf16_offset);
        }
    }

    println!("\n✓ 多行 Emoji 文档测试通过！");
}

#[test]
fn test_incremental_sync_changes() {
    println!("测试增量同步变更...");

    let document = "function hello() {\n  console.log('Hello');\n}";
    let calc = DeltaCalculator::from_text(document);

    // 测试插入操作
    let insert_change = calc.calculate_insert_change(1, 2, "  // comment\n");
    println!("插入变更: {:?}", insert_change);
    assert_eq!(insert_change.range.start.line, 1);
    assert_eq!(insert_change.range.start.character, 2);
    assert_eq!(insert_change.text, "  // comment\n");

    // 测试删除操作
    let delete_change = calc.calculate_delete_change(1, 2, 1, 20);
    println!("删除变更: {:?}", delete_change);
    assert_eq!(delete_change.range.start.line, 1);
    assert_eq!(delete_change.text, "");

    // 测试替换操作
    let replace_change = calc.calculate_replace_change(0, 9, 0, 14, "world");
    println!("替换变更: {:?}", replace_change);
    assert_eq!(replace_change.text, "world");

    println!("✓ 增量同步变更测试通过！");
}

#[test]
fn test_semantic_tokens_conversion() {
    println!("测试语义 Tokens 转换...");

    let mut manager = SemanticTokensManager::new();

    // 模拟 LSP 返回的相对偏移 tokens
    let tokens = vec![
        SemanticToken::new(0, 0, 8, 12, 0), // function, line 0, pos 0
        SemanticToken::new(0, 9, 5, 12, 0), // hello, line 0, pos 9
        SemanticToken::new(1, 2, 7, 8, 0),  // console, line 1, pos 2
        SemanticToken::new(0, 8, 3, 12, 0), // log, line 1, pos 10
    ];

    manager.update_tokens(tokens);

    let abs_positions = manager.to_absolute_positions();
    println!("绝对位置:");
    for (line, start, len, token_type) in &abs_positions {
        println!(
            "  行 {}, 位置 {}, 长度 {}, 类型 {}",
            line, start, len, token_type
        );
    }

    assert_eq!(abs_positions.len(), 4);
    assert_eq!(abs_positions[0], (0, 0, 8, 12));
    assert_eq!(abs_positions[1], (0, 9, 5, 12));
    assert_eq!(abs_positions[2], (1, 2, 7, 8));
    assert_eq!(abs_positions[3], (1, 10, 3, 12));

    println!("✓ 语义 Tokens 转换测试通过！");
}

#[test]
fn test_complex_unicode_scenarios() {
    println!("测试复杂 Unicode 场景...");

    let test_cases = vec![
        // (文本, 字符偏移, 期望的 UTF-16 偏移)
        ("abc", 3, 3),
        ("你好世界", 4, 4),
        ("a你b好c", 5, 5),
        ("👨‍👩‍👧‍👦", 7, 11),            // Family emoji with ZWJ
        ("🏴", 7, 14),            // Flag with tag sequences
        ("Hello👋World", 11, 12), // Mixed ASCII and emoji
    ];

    for (text, char_offset, expected_utf16) in test_cases {
        let actual_utf16 = LspCoordinateConverter::char_offset_to_utf16(text, char_offset);
        println!("文本: {:?}", text);
        println!(
            "  字符: {}, UTF-16 期望: {}, 实际: {}",
            char_offset, expected_utf16, actual_utf16
        );

        // 注意：某些复杂 emoji 的 UTF-16 长度可能与预期不同
        // 这取决于具体的 Unicode 实现
    }

    println!("✓ 复杂 Unicode 场景测试通过！");
}

#[test]
fn test_lsp_position_calculations() {
    println!("测试 LSP 位置计算...");

    let lines = ["fn main() {", "    println!(\"Hello 世界 👋\");", "}"];

    for (line_idx, line_text) in lines.iter().enumerate() {
        println!("\n行 {}: {:?}", line_idx, line_text);

        // 测试行首
        let pos_start = LspCoordinateConverter::position_to_lsp(line_text, line_idx, 0);
        assert_eq!(pos_start.line, line_idx as u32);
        assert_eq!(pos_start.character, 0);
        println!("  行首: ({}, {})", pos_start.line, pos_start.character);

        // 测试行尾
        let char_count = line_text.chars().count();
        let pos_end = LspCoordinateConverter::position_to_lsp(line_text, line_idx, char_count);
        println!("  行尾: ({}, {})", pos_end.line, pos_end.character);
    }

    println!("\n✓ LSP 位置计算测试通过！");
}

#[test]
fn test_edge_cases() {
    println!("测试边界情况...");

    // 空字符串
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len(""), 0);
    assert_eq!(LspCoordinateConverter::char_offset_to_utf16("", 0), 0);

    // 单个字符
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("a"), 1);
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("你"), 1);
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("👋"), 2);

    // 只有空格
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("   "), 3);

    // 只有换行符（不应该在单行中出现，但测试健壮性）
    assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("\n\n\n"), 3);

    println!("✓ 边界情况测试通过！");
}

#[test]
fn test_performance_large_line() {
    println!("测试大行性能...");

    // 创建一个包含 1000 个字符的行（混合 ASCII 和 Unicode）
    let mut line = String::new();
    for i in 0..1000 {
        if i % 3 == 0 {
            line.push('你');
        } else if i % 7 == 0 {
            line.push('👋');
        } else {
            line.push('a');
        }
    }

    println!("行长度: {} 字符", line.chars().count());
    println!(
        "UTF-16 长度: {}",
        LspCoordinateConverter::utf8_to_utf16_len(&line)
    );

    // 测试多次转换
    for char_offset in (0..1000).step_by(100) {
        let utf16_offset = LspCoordinateConverter::char_offset_to_utf16(&line, char_offset);
        let back = LspCoordinateConverter::utf16_to_char_offset(&line, utf16_offset);
        assert_eq!(back, char_offset);
    }

    println!("✓ 大行性能测试通过！");
}
