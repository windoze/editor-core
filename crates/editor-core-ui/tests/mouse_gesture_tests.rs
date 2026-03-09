use editor_core::Position;
use editor_core_render_skia::RenderConfig;
use editor_core_ui::{EditorUi, Modifiers};

fn make_ui(text: &str) -> EditorUi {
    let mut ui = EditorUi::new(text, 80);
    ui.set_render_config(RenderConfig {
        width_px: 240,
        height_px: 120,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(240, 120, 1.0).unwrap();
    ui
}

#[test]
fn double_click_selects_word() {
    let mut ui = make_ui("hello world\n");

    // 双击：点击在 "hello" 内部（col 1）。
    ui.mouse_down_with_modifiers_and_click_count(15.0, 10.0, Modifiers::NONE, 2)
        .unwrap();
    let (start, end) = ui.primary_selection_offsets();
    assert_eq!((start, end), (0, 5));
}

#[test]
fn word_drag_extends_by_words() {
    let mut ui = make_ui("hello world\n");

    // 双击选中 hello。
    ui.mouse_down_with_modifiers_and_click_count(15.0, 10.0, Modifiers::NONE, 2)
        .unwrap();

    // 拖到 world 内部（col 8）。
    ui.mouse_dragged(85.0, 10.0).unwrap();
    let (start, end) = ui.primary_selection_offsets();
    assert_eq!((start, end), (0, 11));
}

#[test]
fn triple_click_selects_line_and_drag_extends_lines() {
    let mut ui = make_ui("abcd\nefgh\n");

    // 三击选中第一行（包括换行）。
    ui.mouse_down_with_modifiers_and_click_count(25.0, 10.0, Modifiers::NONE, 3)
        .unwrap();
    let s0 = ui.primary_selection_offsets();
    assert_eq!(s0, (0, 5));

    // 拖到第二行中间，按行扩展应包含两行。
    ui.mouse_dragged(15.0, 30.0).unwrap();
    let s1 = ui.primary_selection_offsets();
    assert_eq!(s1, (0, 10));
}

#[test]
fn alt_drag_creates_rect_selection() {
    let mut ui = make_ui("abc\ndef\nghi\n");

    // ALT + 拖拽：矩形选择 col 1..2，覆盖 line 0..2。
    ui.mouse_down_with_modifiers_and_click_count(15.0, 10.0, Modifiers::ALT, 1)
        .unwrap();
    ui.mouse_dragged(25.0, 50.0).unwrap();

    let (ranges, _primary) = ui.selections_offsets();
    assert_eq!(ranges, vec![(1, 2), (5, 6), (9, 10)]);
}

#[test]
fn shift_click_extends_selection_from_anchor() {
    let mut ui = make_ui("abcd\n");

    // 单击到 col 1。
    ui.mouse_down(15.0, 10.0).unwrap();
    assert_eq!(ui.cursor_state().position, Position::new(0, 1));
    ui.mouse_up();

    // SHIFT 单击到 col 3，应选择 [1, 3)。
    ui.mouse_down_with_modifiers_and_click_count(35.0, 10.0, Modifiers::SHIFT, 1)
        .unwrap();
    let s = ui.primary_selection_offsets();
    assert_eq!(s, (1, 3));
}

#[test]
fn ctrl_click_adds_caret() {
    let mut ui = make_ui("abc\ndef\n");

    // 初始 caret 在 offset 0。CTRL 单击第二行 col 1 => offset 5，应添加第二个 caret。
    ui.mouse_down_with_modifiers_and_click_count(15.0, 30.0, Modifiers::CTRL, 1)
        .unwrap();

    let (ranges, primary) = ui.selections_offsets();
    assert_eq!(ranges.len(), 2);
    assert_eq!(primary, 1);
    assert_eq!(ranges[0], (0, 0));
    assert_eq!(ranges[1], (5, 5));
}
