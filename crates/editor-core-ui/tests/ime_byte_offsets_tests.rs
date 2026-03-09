use editor_core_ui::{utf8_byte_offset_to_char_offset, utf8_byte_range_to_char_range};

#[test]
fn utf8_byte_offset_to_char_offset_handles_emoji() {
    let s = "a😀b";
    // UTF-8 bytes: "a"(1) + "😀"(4) + "b"(1) => len 6
    assert_eq!(s.len(), 6);

    assert_eq!(utf8_byte_offset_to_char_offset(s, 0), 0);
    assert_eq!(utf8_byte_offset_to_char_offset(s, 1), 1); // after 'a'
    assert_eq!(utf8_byte_offset_to_char_offset(s, 5), 2); // after 'a😀'
    assert_eq!(utf8_byte_offset_to_char_offset(s, 6), 3); // after full string

    // Non-char-boundary index inside the emoji bytes should round down.
    assert_eq!(utf8_byte_offset_to_char_offset(s, 2), 1);
}

#[test]
fn utf8_byte_range_to_char_range_converts_cursor_ranges() {
    let s = "a😀b";

    // Select only the emoji (byte 1..5).
    let (start, len) = utf8_byte_range_to_char_range(s, 1, 5);
    assert_eq!((start, len), (1, 1));

    // Reversed input should still produce a valid range.
    let (start, len) = utf8_byte_range_to_char_range(s, 5, 1);
    assert_eq!((start, len), (1, 1));
}
