use editor_core::SearchOptions;
use editor_core_ui::MultiDocumentEditorUi;

fn main() {
    let mut ui = MultiDocumentEditorUi::new();

    let a = ui.open_tab("hello\nworld\n", 80);
    let b = ui.open_tab("no matches here\n", 80);

    ui.set_active_tab(a).unwrap();
    ui.active_editor_mut().unwrap().insert_text(">> ").unwrap();

    let results = ui
        .search_all_tabs("world", SearchOptions::default())
        .unwrap();
    println!("found {} tab(s) with matches", results.len());
    for r in results {
        println!("tab={} matches={}", r.tab_id.get(), r.matches.len());
    }

    // Close one tab.
    ui.close_tab(b);
}
