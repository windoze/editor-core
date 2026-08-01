use editor_core::SearchOptions;
use editor_core_ui::MultiDocumentEditorUi;

#[test]
fn multi_document_ui_can_open_switch_and_close_tabs() {
    let mut ui = MultiDocumentEditorUi::new();

    let a = ui.open_tab("hello", 80);
    let b = ui.open_tab("world", 80);

    assert_eq!(ui.active_tab_id(), Some(a));
    ui.set_active_tab(b).unwrap();
    assert_eq!(ui.active_tab_id(), Some(b));

    assert!(ui.close_tab(b));
    assert_eq!(ui.active_tab_id(), Some(a));
    assert!(ui.close_tab(a));
    assert_eq!(ui.active_tab_id(), None);
}

#[test]
fn multi_document_ui_tabs_are_independent_documents() {
    let mut ui = MultiDocumentEditorUi::new();

    let a = ui.open_tab("A", 80);
    let b = ui.open_tab("B", 80);

    ui.set_active_tab(a).unwrap();
    ui.active_editor_mut().unwrap().insert_text("!").unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "!A");

    ui.set_active_tab(b).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "B");
}

#[test]
fn multi_document_ui_can_move_tabs() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("a", 80);
    let b = ui.open_tab("b", 80);
    let c = ui.open_tab("c", 80);

    ui.set_active_tab(b).unwrap();
    assert!(ui.move_tab_index(1, 0).unwrap());
    assert_eq!(ui.tab_ids(), vec![b, a, c]);
    assert_eq!(ui.active_tab_id(), Some(b));

    assert!(ui.move_tab_index(2, 1).unwrap());
    assert_eq!(ui.tab_ids(), vec![b, c, a]);

    assert!(!ui.move_tab_index(1, 1).unwrap());
    assert!(!ui.move_tab_index(3, 0).unwrap());

    let closed = ui.close_tabs_to_right(b).unwrap();
    assert_eq!(closed, 2);
    assert_eq!(ui.tab_ids(), vec![b]);
    assert_eq!(ui.active_tab_id(), Some(b));
}

#[test]
fn multi_document_ui_supports_splits_via_clone_view() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("abc\n", 80);

    // Put the original view's caret at EOF so we can observe delta propagation.
    ui.set_active_tab(tab).unwrap();
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(4, 4)], 0)
        .unwrap();

    // Create a split; new view becomes active.
    let new_view_idx = ui.split_tab(tab, 80).unwrap();
    assert_eq!(ui.view_count(tab), Some(2));
    assert_eq!(new_view_idx, 1);

    // Edit in the split view.
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(0, 0)], 0)
        .unwrap();
    ui.active_editor_mut().unwrap().insert_text("X").unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "Xabc\n");

    // Switch back to the original view; text is shared, but view state is independent.
    ui.set_active_view_index(tab, 0).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "Xabc\n");
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (5, 5)
    );
}

#[test]
fn multi_document_ui_can_move_split_views() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("abc\n", 80);

    ui.set_active_tab(tab).unwrap();
    ui.set_active_view_index(tab, 0).unwrap();
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(0, 0)], 0)
        .unwrap();

    assert_eq!(ui.split_tab(tab, 80).unwrap(), 1);
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(1, 1)], 0)
        .unwrap();

    assert_eq!(ui.split_tab(tab, 80).unwrap(), 2);
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(2, 2)], 0)
        .unwrap();

    assert!(ui.move_view_index(tab, 2, 0).unwrap());
    assert_eq!(ui.active_view_index(tab), Some(0));
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (2, 2)
    );

    ui.set_active_view_index(tab, 1).unwrap();
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (0, 0)
    );
    ui.set_active_view_index(tab, 2).unwrap();
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (1, 1)
    );

    assert!(!ui.move_view_index(tab, 2, 2).unwrap());
    assert!(!ui.move_view_index(tab, 2, 3).unwrap());
}

#[test]
fn multi_document_ui_can_search_across_tabs() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("hello world\n", 80);
    let _b = ui.open_tab("no match here\n", 80);

    let results = ui
        .search_all_tabs("world", SearchOptions::default())
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].tab_id, a);
    assert_eq!(results[0].matches.len(), 1);
}

#[test]
fn multi_document_ui_can_replace_tab_text_and_track_dirty_state() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("hello world\n", 80);

    ui.replace_tab_text(tab, "hello mirror\n", false).unwrap();

    assert_eq!(ui.tab_text(tab).unwrap(), "hello mirror\n");
    assert!(ui.is_tab_modified(tab).unwrap());

    let results = ui
        .search_all_tabs("mirror", SearchOptions::default())
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].tab_id, tab);
    assert_eq!(results[0].matches.len(), 1);

    ui.mark_tab_saved(tab).unwrap();
    assert!(!ui.is_tab_modified(tab).unwrap());

    ui.replace_tab_text(tab, "saved mirror\n", true).unwrap();
    assert_eq!(ui.tab_text(tab).unwrap(), "saved mirror\n");
    assert!(!ui.is_tab_modified(tab).unwrap());
}

#[test]
fn multi_document_ui_preview_tabs_are_reused_until_pinned_or_modified() {
    let mut ui = MultiDocumentEditorUi::new();

    let pinned = ui.open_tab("pinned", 80);
    ui.set_active_tab(pinned).unwrap();

    let p1 = ui.open_preview_tab("preview-1", 80);
    assert_eq!(ui.is_preview_tab(p1), Some(true));

    // Opening another preview should reuse the same tab id (replace content).
    let p1_again = ui.open_preview_tab("preview-2", 80);
    assert_eq!(p1_again, p1);

    ui.set_active_tab(p1).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "preview-2");

    // Pinning turns it into a normal tab and forces a new preview tab next time.
    ui.pin_tab(p1).unwrap();
    assert_eq!(ui.is_preview_tab(p1), Some(false));
    let p2 = ui.open_preview_tab("preview-3", 80);
    assert_ne!(p2, p1);
}

#[test]
fn multi_document_ui_can_close_other_tabs_and_tabs_to_right() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("a", 80);
    let b = ui.open_tab("b", 80);
    let _c = ui.open_tab("c", 80);

    // Close to the right of b should remove c.
    let closed = ui.close_tabs_to_right(b).unwrap();
    assert_eq!(closed, 1);
    assert_eq!(ui.tab_ids(), vec![a, b]);

    // Close others for b should leave only b.
    let closed = ui.close_other_tabs(b).unwrap();
    assert_eq!(closed, 1);
    assert_eq!(ui.tab_ids(), vec![b]);
    assert_eq!(ui.active_tab_id(), Some(b));
}
