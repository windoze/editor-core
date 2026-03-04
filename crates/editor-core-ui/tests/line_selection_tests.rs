use editor_core_ui::EditorUi;

#[test]
fn set_line_selection_offsets_selects_union_of_lines() {
    // Lines:
    // 0: "aa"
    // 1: "bb"
    // 2: ""   (blank line)
    // 3: "cc"
    // 4: "dd"
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Anchor in line 0, drag into line 3 (inside "cc").
    ui.set_line_selection_offsets(0, 8).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 10)); // "aa\nbb\n\ncc\n"

    // Reverse direction should produce the same range.
    ui.set_line_selection_offsets(8, 0).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 10));
}

#[test]
fn set_line_selection_offsets_includes_last_line_without_newline() {
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Drag within the last line ("dd") which has no trailing newline.
    ui.set_line_selection_offsets(10, 11).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (10, 12));
}

#[test]
fn set_line_selection_offsets_single_line_selects_that_line() {
    let text = "aa\nbb\n\ncc\ndd";
    let mut ui = EditorUi::new(text, 80);

    // Within the first line.
    ui.set_line_selection_offsets(0, 1).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "aa\n"

    // Within the blank line: just the newline.
    ui.set_line_selection_offsets(6, 6).unwrap();
    assert_eq!(ui.primary_selection_offsets(), (6, 7));
}

