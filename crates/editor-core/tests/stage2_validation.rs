//! Stage 2 validation tests
//!
//! Validation criteria:
//! 1. O(log N) access: Given a line number, return that line's start offset in logarithmic time.
//!    Note: The current implementation is O(1), which is even better.
//! 2. CJK-aware: Ensure `char_count` correctly treats multi-byte UTF-8 characters as single chars.

use editor_core::{LineIndex, line_index::LineMetadata};

#[test]
fn test_line_access_performance() {
    println!("创建包含 10000 行的大文档...");
    let mut lines = Vec::new();
    for i in 0..10000 {
        lines.push(format!("This is line number {} with some content", i));
    }
    let text = lines.join("\n");
    let index = LineIndex::from_text(&text);

    assert_eq!(index.line_count(), 10000);

    println!("测试随机行访问性能...");
    // 当前 `LineIndex` 基于 Rope（ropey），单次访问通常为 O(log N)；
    // 这里不做严格基准，仅验证接口与转换一致性。
    for line_num in [0, 100, 1000, 5000, 9999] {
        let line = index.get_line(line_num);
        assert!(line.is_some(), "行 {} 应该存在", line_num);

        // 验证行号到偏移的转换
        let offset = index.line_to_offset(line_num);
        let recovered_line = index.offset_to_line(offset);
        assert_eq!(recovered_line, line_num, "偏移转换不一致");
    }

    println!("✓ 行访问性能测试通过！");
}

#[test]
fn test_cjk_character_awareness() {
    println!("测试 CJK 字符识别...");

    // 测试中文
    let chinese_text = "你好世界\n这是测试\n中文字符";
    let index = LineIndex::from_text(chinese_text);

    assert_eq!(index.line_count(), 3);

    let line0 = index.get_line(0).unwrap();
    assert_eq!(line0.char_count, 4, "你好世界 应该是 4 个字符");
    assert_eq!(line0.byte_length, 12, "你好世界 应该是 12 字节 (4 × 3)");
    assert!(!line0.is_pure_ascii);

    let line1 = index.get_line(1).unwrap();
    assert_eq!(line1.char_count, 4, "这是测试 应该是 4 个字符");
    assert_eq!(line1.byte_length, 12);

    // 测试日文
    let japanese_text = "こんにちは\n日本語テスト";
    let jp_index = LineIndex::from_text(japanese_text);

    let jp_line0 = jp_index.get_line(0).unwrap();
    assert_eq!(jp_line0.char_count, 5, "こんにちは 应该是 5 个字符");
    assert!(!jp_line0.is_pure_ascii);

    // 测试韩文
    let korean_text = "안녕하세요\n한국어";
    let kr_index = LineIndex::from_text(korean_text);

    let kr_line0 = kr_index.get_line(0).unwrap();
    assert_eq!(kr_line0.char_count, 5, "안녕하세요 应该是 5 个字符");
    assert!(!kr_line0.is_pure_ascii);

    println!("✓ CJK 字符识别测试通过！");
}

#[test]
fn test_emoji_and_grapheme_clusters() {
    println!("测试 Emoji 和 Grapheme Clusters...");

    let emoji_text = "Hello 👋\nWorld 🌍\nRust 🦀";
    let index = LineIndex::from_text(emoji_text);

    assert_eq!(index.line_count(), 3);

    let line0 = index.get_line(0).unwrap();
    // "Hello 👋" = 7 个字符 (包括空格和 emoji)
    assert_eq!(line0.char_count, 7);
    // "Hello " = 6 bytes, "👋" = 4 bytes
    assert_eq!(line0.byte_length, 10);

    let line1 = index.get_line(1).unwrap();
    assert_eq!(line1.char_count, 7); // "World 🌍"
    assert_eq!(line1.byte_length, 10);

    let line2 = index.get_line(2).unwrap();
    assert_eq!(line2.char_count, 6); // "Rust 🦀"
    assert_eq!(line2.byte_length, 9); // "Rust " = 5, "🦀" = 4

    println!("✓ Emoji 和 Grapheme Clusters 测试通过！");
}

#[test]
fn test_mixed_content() {
    println!("测试混合内容（ASCII + CJK + Emoji）...");

    let mixed = "Hello世界!\n你好World🌍\nRust编程🦀语言";
    let index = LineIndex::from_text(mixed);

    assert_eq!(index.line_count(), 3);

    // 第一行: "Hello世界!"
    let line0 = index.get_line(0).unwrap();
    assert_eq!(line0.char_count, 8); // H,e,l,l,o,世,界,!
    assert!(!line0.is_pure_ascii);

    // 第二行: "你好World🌍"
    let line1 = index.get_line(1).unwrap();
    assert_eq!(line1.char_count, 8); // 你,好,W,o,r,l,d,🌍
    assert!(!line1.is_pure_ascii);

    // 第三行: "Rust编程🦀语言"
    let line2 = index.get_line(2).unwrap();
    assert_eq!(line2.char_count, 9); // R,u,s,t,编,程,🦀,语,言
    assert!(!line2.is_pure_ascii);

    println!("✓ 混合内容测试通过！");
}

#[test]
fn test_char_offset_conversions() {
    println!("测试字符偏移转换...");

    let text = "Line1\nLine2你好\nLine3🌍";
    let index = LineIndex::from_text(text);

    // 测试 char_offset_to_position (Rope 语义：换行符属于当前行)
    assert_eq!(index.char_offset_to_position(0), (0, 0)); // 'L' in "Line1"
    assert_eq!(index.char_offset_to_position(5), (0, 5)); // '\n' 第0行的换行符
    assert_eq!(index.char_offset_to_position(6), (1, 0)); // 'L' in "Line2你好"
    assert_eq!(index.char_offset_to_position(11), (1, 5)); // '你'
    assert_eq!(index.char_offset_to_position(14), (2, 0)); // 'L' in "Line3🌍"

    // 测试 position_to_char_offset
    assert_eq!(index.position_to_char_offset(0, 0), 0);
    assert_eq!(index.position_to_char_offset(0, 5), 5); // '\n'
    assert_eq!(index.position_to_char_offset(1, 0), 6); // 'L'
    assert_eq!(index.position_to_char_offset(1, 5), 11); // '你'
    assert_eq!(index.position_to_char_offset(2, 0), 14); // 'L'

    // 往返转换测试
    for test_offset in [0, 5, 6, 11, 14, 18] {
        if test_offset <= index.char_count() {
            let (line, col) = index.char_offset_to_position(test_offset);
            let recovered = index.position_to_char_offset(line, col);
            assert_eq!(recovered, test_offset, "字符偏移往返转换失败");
        }
    }

    println!("✓ 字符偏移转换测试通过！");
}

#[test]
fn test_byte_offset_conversions() {
    println!("测试字节偏移转换...");

    let text = "abc\n你好\n🌍";
    let index = LineIndex::from_text(text);

    // "abc" = 3 bytes
    assert_eq!(index.line_to_offset(0), 0);
    assert_eq!(index.line_to_offset(1), 3);

    // "abc" + "你好" = 3 + 6 = 9 bytes
    assert_eq!(index.line_to_offset(2), 9);

    // 反向转换
    assert_eq!(index.offset_to_line(0), 0);
    assert_eq!(index.offset_to_line(3), 1);
    assert_eq!(index.offset_to_line(9), 2);

    println!("✓ 字节偏移转换测试通过！");
}

#[test]
fn test_line_operations_with_cjk() {
    println!("测试包含 CJK 的行操作...");

    let mut index = LineIndex::new();

    // 插入包含 CJK 的行
    index.append_line(LineMetadata::from_text("第一行"));
    index.append_line(LineMetadata::from_text("第二行"));
    index.append_line(LineMetadata::from_text("第三行"));

    assert_eq!(index.line_count(), 3);

    // 在中间插入
    index.insert_line(1, LineMetadata::from_text("插入的行"));
    assert_eq!(index.line_count(), 4);
    assert_eq!(index.get_line(1).unwrap().char_count, 4); // "插入的行"

    // 删除行
    index.delete_line(1);
    assert_eq!(index.line_count(), 3);
    assert_eq!(index.get_line(1).unwrap().char_count, 3); // "第二行"

    println!("✓ CJK 行操作测试通过！");
}

#[test]
fn test_empty_lines() {
    println!("测试空行处理...");

    let text = "Line1\n\nLine3\n\n\nLine6";
    let index = LineIndex::from_text(text);

    assert_eq!(index.line_count(), 6);

    // 检查空行
    let line1 = index.get_line(1).unwrap();
    assert_eq!(line1.byte_length, 0);
    assert_eq!(line1.char_count, 0);
    assert!(line1.is_pure_ascii);

    let line3 = index.get_line(3).unwrap();
    assert_eq!(line3.byte_length, 0);

    let line4 = index.get_line(4).unwrap();
    assert_eq!(line4.byte_length, 0);

    println!("✓ 空行处理测试通过！");
}
