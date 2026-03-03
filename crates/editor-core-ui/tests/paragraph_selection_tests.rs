use editor_core_ui::EditorUi;

#[test]
fn select_paragraph_at_char_offset_selects_non_blank_block() {
    // Lines:
    // 0: "aa"
    // 1: "bb"
    // 2: ""   (blank line)
    // 3: "cc"
    // 4: "dd"
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Click in first paragraph.
    ui.select_paragraph_at_char_offset(0).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 6)); // "aa\nbb\n"

    // Click in second paragraph.
    ui.select_paragraph_at_char_offset(8).unwrap(); // inside "cc"
    assert_eq!(ui.primary_selection_offsets(), (7, 12)); // "cc\ndd"
}

#[test]
fn select_paragraph_at_char_offset_selects_blank_paragraph() {
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Char offset 6 points at the blank line's newline.
    ui.select_paragraph_at_char_offset(6).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (6, 7));
}

#[test]
fn set_paragraph_selection_offsets_selects_union_of_paragraphs() {
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Anchor in first paragraph, drag into second paragraph.
    ui.set_paragraph_selection_offsets(0, 8).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 12));

    // Anchor in blank line, drag into second paragraph.
    ui.set_paragraph_selection_offsets(6, 8).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (6, 12));
}

