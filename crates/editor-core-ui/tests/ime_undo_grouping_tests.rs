use editor_core_ui::EditorUi;

#[test]
fn ime_commit_undo_is_single_group() {
    let mut ui = EditorUi::new("", 80);

    // Simulate an IME composition session:
    // - preedit updates replace the same marked range repeatedly
    // - commit replaces the marked range with the final committed text
    ui.set_marked_text("n").unwrap();
    ui.set_marked_text("ni").unwrap();
    ui.set_marked_text("ni hao").unwrap();
    ui.commit_text("你好").unwrap();
    assert_eq!(ui.text(), "你好");

    // Undo should remove the entire committed string and the whole preedit session in one step.
    ui.undo().unwrap();
    assert_eq!(ui.text(), "");
}

#[test]
fn ime_does_not_merge_with_prior_typing_group() {
    let mut ui = EditorUi::new("", 80);

    // Normal typing starts a coalescible typing undo group.
    ui.insert_text("a").unwrap();
    assert_eq!(ui.text(), "a");

    // IME composition must not merge with that typing group.
    ui.set_marked_text("n").unwrap();
    ui.set_marked_text("ni").unwrap();
    ui.commit_text("你").unwrap();
    assert_eq!(ui.text(), "a你");

    // Undo once should undo only the IME commit, leaving prior typing intact.
    ui.undo().unwrap();
    assert_eq!(ui.text(), "a");

    // Undo again should undo the prior typing.
    ui.undo().unwrap();
    assert_eq!(ui.text(), "");
}

#[test]
fn ime_group_ends_on_commit_so_followup_typing_undo_is_separate() {
    let mut ui = EditorUi::new("", 80);

    ui.set_marked_text("ni hao").unwrap();
    ui.commit_text("你好").unwrap();
    assert_eq!(ui.text(), "你好");

    // Follow-up typing should not coalesce into the IME undo group.
    ui.insert_text("x").unwrap();
    assert_eq!(ui.text(), "你好x");

    ui.undo().unwrap();
    assert_eq!(ui.text(), "你好");

    ui.undo().unwrap();
    assert_eq!(ui.text(), "");
}

#[test]
fn ime_undo_grouping_survives_interleaved_viewport_updates() {
    let mut ui = EditorUi::new("", 80);

    // Simulate what real UI hosts do: they may call `set_viewport_px` on every draw/layout pass,
    // including during IME composition updates.
    ui.set_viewport_px(320, 200, 2.0).unwrap();
    ui.set_marked_text("h").unwrap();
    ui.set_viewport_px(320, 200, 2.0).unwrap();
    ui.set_marked_text("ha").unwrap();
    ui.set_viewport_px(320, 200, 2.0).unwrap();
    ui.set_marked_text("han zi").unwrap();

    ui.set_viewport_px(320, 200, 2.0).unwrap();
    ui.commit_text("汉字").unwrap();
    assert_eq!(ui.text(), "汉字");

    ui.undo().unwrap();
    assert_eq!(ui.text(), "");
}
