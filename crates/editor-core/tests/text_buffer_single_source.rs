use editor_core::{Command, CommandExecutor, EditCommand, EditorCore, LineIndex};

fn assert_editor_text(input: &str, expected_text: &str, expected_lines: &[&str]) {
    let core = EditorCore::new(input, 80);

    assert_eq!(core.get_text(), expected_text);
    assert_eq!(core.char_count(), expected_text.chars().count());
    assert_eq!(core.line_count(), expected_lines.len());
    assert_eq!(core.line_index.get_text(), expected_text);
    assert_eq!(core.line_index.char_count(), expected_text.chars().count());
    assert_eq!(core.line_index.byte_count(), expected_text.len());

    for (line, expected) in expected_lines.iter().enumerate() {
        assert_eq!(
            core.line_index.get_line_text(line).as_deref(),
            Some(*expected)
        );
    }
}

#[test]
fn editor_text_buffer_preserves_document_shapes() {
    assert_editor_text("", "", &[""]);
    assert_editor_text("alpha\nbeta", "alpha\nbeta", &["alpha", "beta"]);
    assert_editor_text("alpha\nbeta\n", "alpha\nbeta\n", &["alpha", "beta", ""]);
    assert_editor_text("你好\n世界", "你好\n世界", &["你好", "世界"]);
    assert_editor_text("a👋\n🌍b", "a👋\n🌍b", &["a👋", "🌍b"]);
    assert_editor_text("a\r\nb\rc", "a\nb\nc", &["a", "b", "c"]);
}

#[test]
fn line_index_text_buffer_supports_char_ranges_and_conversions() {
    let mut index = LineIndex::from_text("a你好\n🌍b");

    assert_eq!(index.char_count(), 6);
    assert_eq!(index.byte_count(), "a你好\n🌍b".len());
    assert_eq!(index.get_range(1, 2), "你好");
    assert_eq!(index.get_range(4, 1), "🌍");
    assert_eq!(index.get_line_text(0).as_deref(), Some("a你好"));
    assert_eq!(index.get_line_text(1).as_deref(), Some("🌍b"));
    assert_eq!(index.position_to_char_offset(1, 1), 5);
    assert_eq!(index.char_offset_to_position(5), (1, 1));

    for char_offset in 0..=index.char_count() {
        let byte_offset = index.char_offset_to_byte_offset(char_offset);
        assert_eq!(index.byte_offset_to_char_offset(byte_offset), char_offset);
    }

    index.insert(1, "中");
    assert_eq!(index.get_text(), "a中你好\n🌍b");
    assert_eq!(index.get_range(1, 3), "中你好");

    index.delete(2, 2);
    assert_eq!(index.get_text(), "a中\n🌍b");
    assert_eq!(index.get_line_text(0).as_deref(), Some("a中"));
}

#[test]
fn editor_text_reads_prefer_text_buffer_over_piece_table_shadow() {
    let mut core = EditorCore::new("abc", 80);

    core.piece_table.insert(0, "shadow ");

    assert_eq!(core.get_text(), "abc");
    assert_eq!(core.char_count(), 3);
    assert_eq!(core.line_index.get_text(), "abc");
}

#[test]
fn command_edits_keep_piece_table_shadow_and_text_buffer_consistent() {
    let mut executor = CommandExecutor::new("", 80);

    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "one\r\ntwo🙂".to_string(),
        }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "one\ntwo🙂");

    executor
        .execute(Command::Edit(EditCommand::Replace {
            start: 3,
            length: 1,
            text: "\n中".to_string(),
        }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "one\n中two🙂");

    executor
        .execute(Command::Edit(EditCommand::Delete {
            start: 0,
            length: 4,
        }))
        .unwrap();

    let editor = executor.editor();
    assert_eq!(editor.get_text(), "中two🙂");
    assert_eq!(editor.piece_table.get_text(), editor.get_text());
    assert_eq!(editor.line_index.get_text(), editor.get_text());
    assert_eq!(editor.line_index.get_range(0, 1), "中");
    assert_eq!(
        editor.line_index.get_line_text(0).as_deref(),
        Some("中two🙂")
    );
}
