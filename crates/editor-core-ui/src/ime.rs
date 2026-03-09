/// Convert a UTF-8 byte offset (as used by some platform IME APIs) into a Unicode scalar offset
/// (Rust `char` index) within the same string.
///
/// Notes:
/// - If `byte_offset` is not a char boundary, this rounds down to the nearest valid boundary.
/// - If `byte_offset` is out of range, it clamps to `s.len()`.
pub fn utf8_byte_offset_to_char_offset(s: &str, byte_offset: usize) -> usize {
    let mut idx = byte_offset.min(s.len());
    while idx > 0 && !s.is_char_boundary(idx) {
        idx = idx.saturating_sub(1);
    }
    s[..idx].chars().count()
}

/// Convert a UTF-8 byte range into a `(start, len)` char-range (Unicode scalar offsets).
pub fn utf8_byte_range_to_char_range(s: &str, start: usize, end: usize) -> (usize, usize) {
    let a = utf8_byte_offset_to_char_offset(s, start);
    let b = utf8_byte_offset_to_char_offset(s, end);
    if b >= a { (a, b - a) } else { (b, a - b) }
}
