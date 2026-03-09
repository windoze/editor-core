use editor_core::{Command, CursorCommand};
use editor_core_render_skia::{RenderTheme, Rgba8};
use editor_core_ui::{DamageRect, EditorUi};

fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
    let idx = (y as usize * width_px as usize + x as usize) * 4;
    [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
}

#[test]
fn incremental_render_returns_damage_rects_for_caret_moves() {
    let mut ui = EditorUi::new(" \n \n \n \n \n", 80);
    ui.set_theme(RenderTheme {
        background: Rgba8::new(10, 20, 30, 255),
        foreground: Rgba8::new(10, 20, 30, 255), // keep text invisible for deterministic pixel checks
        selection_background: Rgba8::new(200, 0, 0, 255),
        caret: Rgba8::new(0, 0, 200, 255),
        ..RenderTheme::default()
    });

    ui.set_render_metrics(12.0, 20.0, 10.0, 0.0, 0.0);
    ui.set_viewport_px(80, 100, 1.0).unwrap(); // 5 rows visible

    let required = ui.required_rgba_len();
    let mut rgba = vec![0u8; required];

    let (_len0, damage0) = ui.render_rgba_visible_into_with_damage(&mut rgba).unwrap();
    assert_eq!(
        damage0,
        vec![DamageRect {
            x: 0,
            y: 0,
            width: 80,
            height: 100
        }]
    );

    let (_len1, damage1) = ui.render_rgba_visible_into_with_damage(&mut rgba).unwrap();
    assert!(damage1.is_empty());

    // Move caret from row 0 -> row 4.
    ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 4, column: 0 }))
        .unwrap();

    let (_len2, damage2) = ui.render_rgba_visible_into_with_damage(&mut rgba).unwrap();
    assert_eq!(
        damage2,
        vec![
            DamageRect {
                x: 0,
                y: 0,
                width: 80,
                height: 20
            },
            DamageRect {
                x: 0,
                y: 80,
                width: 80,
                height: 20
            }
        ]
    );

    // Old caret row cleared; new caret row painted.
    assert_eq!(pixel(&rgba, 80, 0, 10), [10, 20, 30, 255]);
    assert_eq!(pixel(&rgba, 80, 0, 90), [0, 0, 200, 255]);

    // Incremental output matches a fresh full render.
    let mut full = vec![0u8; required];
    let _ = ui.render_rgba_visible_into(&mut full).unwrap();
    assert_eq!(rgba, full);
}
