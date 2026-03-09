use editor_core_render_skia::RenderConfig;
use editor_core_ui::{EditorUi, Modifiers};

fn main() {
    let mut ui = EditorUi::new("one two three\nabc\ndef\nghi\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 400,
        height_px: 200,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(400, 200, 1.0).unwrap();

    // 1) Double click: select word ("two")
    ui.mouse_down_with_modifiers_and_click_count(45.0, 10.0, Modifiers::NONE, 2)
        .unwrap();
    println!(
        "double-click selection: {:?}",
        ui.primary_selection_offsets()
    );

    // 2) Drag into "three": expand by word
    ui.mouse_dragged(85.0, 10.0).unwrap();
    println!(
        "word-drag selection:    {:?}",
        ui.primary_selection_offsets()
    );

    // 3) Option/Alt + drag: rect selection across 3 lines
    ui.mouse_down_with_modifiers_and_click_count(15.0, 70.0, Modifiers::ALT, 1)
        .unwrap();
    ui.mouse_dragged(25.0, 110.0).unwrap();
    println!("rect selection ranges:  {:?}", ui.selections_offsets().0);
}
