//! A minimal cross-platform GUI “shell” demo using `winit` + `softbuffer`.
//!
//! Run:
//! - `cargo run -p editor-core-ui --example winit_editor`
//!
//! Notes:
//! - This is intentionally lightweight and CPU-rendered (Skia → RGBA → softbuffer blit).
//! - The goal is to demonstrate a workable window/event loop integration path.

use editor_core_render_skia::RenderConfig;
use editor_core_ui::{
    rgba8_to_argb_u32, utf8_byte_range_to_char_range, EditorUi, Modifiers,
};
use std::num::NonZeroU32;
use std::rc::Rc;
use std::time::{Duration, Instant};

use softbuffer::{Context as SoftbufferContext, Surface as SoftbufferSurface};
use winit::{
    dpi::{LogicalSize, PhysicalPosition, PhysicalSize},
    event::{ElementState, Event, MouseButton, MouseScrollDelta, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    window::WindowBuilder,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let event_loop = EventLoop::new()?;
    let window = Rc::new(
        WindowBuilder::new()
        .with_title("editor-core-ui (winit demo)")
        .with_inner_size(LogicalSize::new(900.0, 600.0))
        .build(&event_loop)?,
    );

    window.set_ime_allowed(true);

    // softbuffer needs a context tied to the window.
    let context = SoftbufferContext::new(window.as_ref())?;
    let mut surface = SoftbufferSurface::new(&context, window.as_ref())?;

    let mut ui = EditorUi::new(
        "one two three\n\n\
         你好，世界\n\
         (try typing, arrows, mouse selection, wheel scroll)\n",
        80,
    );

    let mut rgba: Vec<u8> = Vec::new();
    let mut argb: Vec<u32> = Vec::new();

    let mut cursor_pos_px: PhysicalPosition<f64> = PhysicalPosition::new(0.0, 0.0);
    let mut mouse_down_left = false;
    let mut click_tracker = ClickTracker::default();
    let mut current_mods = Modifiers::NONE;

    // Initial viewport sizing.
    let mut physical_size = window.inner_size();
    let (mut cell_width_px, mut line_height_px) =
        resize_ui(&mut ui, physical_size, window.scale_factor() as f32)?;
    surface.resize(nz(physical_size.width), nz(physical_size.height))?;

    let mut needs_redraw = true;

    let window = Rc::clone(&window);
    event_loop.run(move |event, elwt| {
        match event {
            Event::WindowEvent { event, .. } => match event {
                WindowEvent::CloseRequested => elwt.exit(),
                WindowEvent::RedrawRequested => {
                    let w = physical_size.width.max(1) as usize;
                    let h = physical_size.height.max(1) as usize;

                    let required = ui.required_rgba_len();
                    if rgba.len() != required {
                        rgba.resize(required, 0);
                    }
                    let _ = ui.render_rgba_visible_into(&mut rgba);

                    let pixels = w.saturating_mul(h);
                    if argb.len() != pixels {
                        argb.resize(pixels, 0);
                    }
                    let _ = rgba8_to_argb_u32(&rgba, &mut argb);

                    if let Ok(mut buffer) = surface.buffer_mut() {
                        buffer.copy_from_slice(&argb);
                        let _ = buffer.present();
                    }
                }
                WindowEvent::Resized(size) => {
                    physical_size = size;
                    let _ = surface.resize(nz(size.width), nz(size.height));
                    if let Ok((cw, lh)) = resize_ui(&mut ui, size, window.scale_factor() as f32) {
                        cell_width_px = cw;
                        line_height_px = lh;
                    }
                    needs_redraw = true;
                }
                WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                    physical_size = window.inner_size();
                    let _ = surface.resize(nz(physical_size.width), nz(physical_size.height));
                    if let Ok((cw, lh)) = resize_ui(&mut ui, physical_size, scale_factor as f32) {
                        cell_width_px = cw;
                        line_height_px = lh;
                    }
                    needs_redraw = true;
                }

                WindowEvent::ModifiersChanged(mods) => {
                    current_mods = winit_mods_to_ecu(mods.state());
                }

                WindowEvent::Ime(ime) => {
                    match ime {
                        winit::event::Ime::Enabled => {
                            // Candidate window positioning: tell the OS where the caret is.
                            update_ime_cursor_area(&window, &mut ui, cell_width_px, line_height_px);
                        }
                        winit::event::Ime::Preedit(text, cursor_byte_range) => {
                            // IMPORTANT:
                            // - winit uses UTF-8 byte indices for the cursor range.
                            // - winit also sends an empty Preedit event right before Commit.
                            //
                            // We intentionally ignore the "empty preedit" event to keep the
                            // marked range alive until Commit arrives (so `commit_text` can
                            // replace it instead of inserting).
                            if text.is_empty() {
                                // Best-effort caret area update (candidate window may still move
                                // due to arrow keys / view scrolling).
                                if ui.marked_range().is_some() {
                                    update_ime_cursor_area(&window, &mut ui, cell_width_px, line_height_px);
                                }
                                return;
                            }

                            let (sel_start, sel_len) = cursor_byte_range
                                .map(|(a, b)| utf8_byte_range_to_char_range(&text, a, b))
                                .unwrap_or((text.chars().count(), 0));

                            let _ = ui.set_marked_text_with_selection(
                                &text,
                                sel_start,
                                sel_len,
                                None,
                            );
                            update_ime_cursor_area(&window, &mut ui, cell_width_px, line_height_px);
                            needs_redraw = true;
                        }
                        winit::event::Ime::Commit(text) => {
                            if !text.is_empty() {
                                let _ = ui.commit_text(&text);
                                update_ime_cursor_area(&window, &mut ui, cell_width_px, line_height_px);
                                needs_redraw = true;
                            }
                        }
                        winit::event::Ime::Disabled => {
                            // Treat "IME disabled" as a best-effort cancellation signal.
                            let _ = ui.set_marked_text_with_selection("", 0, 0, None);
                            needs_redraw = true;
                        }
                    }
                }

                WindowEvent::KeyboardInput { event, .. } => {
                    if event.state != ElementState::Pressed {
                        return;
                    }

                    // Text input on some platforms can arrive via `event.text`.
                    if let Some(text) = event.text.as_ref().map(|s| s.as_str()) {
                        let text = text;
                        if !text.is_empty()
                            && !current_mods.contains(Modifiers::CTRL)
                            && !current_mods.contains(Modifiers::META)
                            && !current_mods.contains(Modifiers::ALT)
                        {
                            let _ = ui.commit_text(text);
                            needs_redraw = true;
                            return;
                        }
                    }

                    // Key-based commands (navigation/editing).
                    if handle_key_command(&mut ui, &event.logical_key, current_mods) {
                        needs_redraw = true;
                    }
                }

                WindowEvent::CursorMoved { position, .. } => {
                    cursor_pos_px = position;
                    if mouse_down_left {
                        let _ = ui.mouse_dragged(position.x as f32, position.y as f32);
                        needs_redraw = true;
                    }
                }

                WindowEvent::MouseInput { state, button, .. } => {
                    if button != MouseButton::Left {
                        return;
                    }

                    match state {
                        ElementState::Pressed => {
                            mouse_down_left = true;
                            let click_count = click_tracker.register_click(cursor_pos_px, Instant::now());
                            let _ = ui.mouse_down_with_modifiers_and_click_count(
                                cursor_pos_px.x as f32,
                                cursor_pos_px.y as f32,
                                current_mods,
                                click_count,
                            );
                            needs_redraw = true;
                        }
                        ElementState::Released => {
                            mouse_down_left = false;
                            ui.mouse_up();
                            needs_redraw = true;
                        }
                    }
                }

                WindowEvent::MouseWheel { delta, .. } => {
                    let delta_y_px = match delta {
                        MouseScrollDelta::LineDelta(_x, y) => -(y as f32) * line_height_px.max(1.0),
                        MouseScrollDelta::PixelDelta(pos) => -(pos.y as f32),
                    };
                    ui.scroll_by_pixels(delta_y_px);
                    needs_redraw = true;
                }

                _ => {}
            },

            Event::AboutToWait => {
                if needs_redraw {
                    window.request_redraw();
                    needs_redraw = false;
                }
                elwt.set_control_flow(ControlFlow::Wait);
            }

            _ => {}
        }
    })?;

    Ok(())
}

fn resize_ui(
    ui: &mut EditorUi,
    size: PhysicalSize<u32>,
    scale: f32,
) -> Result<(f32, f32), editor_core_ui::UiError> {
    let scale = if scale.is_finite() { scale.max(1.0) } else { 1.0 };

    // Small, readable defaults (logical sizes scaled to backing pixels).
    let font_size_px = 14.0 * scale;
    let line_height_px = 18.0 * scale;
    let cell_width_px = 8.0 * scale;

    ui.set_render_config(RenderConfig {
        width_px: size.width.max(1),
        height_px: size.height.max(1),
        font_size: font_size_px,
        line_height_px,
        cell_width_px,
        padding_x_px: 8.0 * scale,
        padding_y_px: 8.0 * scale,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(size.width.max(1), size.height.max(1), scale)?;
    Ok((cell_width_px, line_height_px))
}

fn nz(v: u32) -> NonZeroU32 {
    NonZeroU32::new(v.max(1)).unwrap()
}

fn update_ime_cursor_area(
    window: &winit::window::Window,
    ui: &mut EditorUi,
    cell_width_px: f32,
    line_height_px: f32,
) {
    let caret_off = ui.cursor_state().offset;
    let Some((x, y)) = ui.char_offset_to_view_point_px(caret_off) else {
        return;
    };

    // Winit takes either logical or physical coordinates; we use physical.
    let x = x.round().max(0.0) as i32;
    let y = y.round().max(0.0) as i32;
    let w = cell_width_px.ceil().max(1.0) as u32;
    let h = line_height_px.ceil().max(1.0) as u32;
    window.set_ime_cursor_area(PhysicalPosition::new(x, y), PhysicalSize::new(w, h));
}

fn handle_key_command(ui: &mut EditorUi, key: &Key, mods: Modifiers) -> bool {
    let is_shift = mods.contains(Modifiers::SHIFT);
    let is_ctrl = mods.contains(Modifiers::CTRL) || mods.contains(Modifiers::META);

    // A few common bindings.
    if is_ctrl {
        if matches!(key, Key::Character(s) if s.eq_ignore_ascii_case("z")) {
            let _ = if is_shift { ui.redo() } else { ui.undo() };
            return true;
        }
        if matches!(key, Key::Character(s) if s.eq_ignore_ascii_case("y")) {
            let _ = ui.redo();
            return true;
        }
    }

    match key {
        Key::Named(NamedKey::ArrowLeft) => {
            let _ = if is_shift {
                ui.move_grapheme_left_and_modify_selection()
            } else {
                ui.move_grapheme_left()
            };
            true
        }
        Key::Named(NamedKey::ArrowRight) => {
            let _ = if is_shift {
                ui.move_grapheme_right_and_modify_selection()
            } else {
                ui.move_grapheme_right()
            };
            true
        }
        Key::Named(NamedKey::ArrowUp) => {
            let _ = if is_shift {
                ui.move_visual_by_rows_and_modify_selection(-1)
            } else {
                ui.move_visual_by_rows(-1)
            };
            true
        }
        Key::Named(NamedKey::ArrowDown) => {
            let _ = if is_shift {
                ui.move_visual_by_rows_and_modify_selection(1)
            } else {
                ui.move_visual_by_rows(1)
            };
            true
        }
        Key::Named(NamedKey::Backspace) => {
            let _ = ui.backspace();
            true
        }
        Key::Named(NamedKey::Delete) => {
            let _ = ui.delete_forward();
            true
        }
        Key::Named(NamedKey::Enter) => {
            let _ = ui.commit_text("\n");
            true
        }
        Key::Named(NamedKey::Tab) => {
            let _ = ui.insert_tab();
            true
        }
        Key::Named(NamedKey::Escape) => {
            ui.unmark_text();
            true
        }
        Key::Named(NamedKey::Home) => {
            let _ = if is_shift {
                ui.move_to_visual_line_start_and_modify_selection()
            } else {
                ui.move_to_visual_line_start()
            };
            true
        }
        Key::Named(NamedKey::End) => {
            let _ = if is_shift {
                ui.move_to_visual_line_end_and_modify_selection()
            } else {
                ui.move_to_visual_line_end()
            };
            true
        }
        _ => false,
    }
}

fn winit_mods_to_ecu(mods: winit::keyboard::ModifiersState) -> Modifiers {
    let mut out = Modifiers::NONE;
    if mods.shift_key() {
        out.insert(Modifiers::SHIFT);
    }
    if mods.control_key() {
        out.insert(Modifiers::CTRL);
    }
    if mods.alt_key() {
        out.insert(Modifiers::ALT);
    }
    if mods.super_key() {
        out.insert(Modifiers::META);
    }
    out
}

#[derive(Debug, Default)]
struct ClickTracker {
    last_click_at: Option<Instant>,
    last_click_pos: Option<PhysicalPosition<f64>>,
    click_count: u8,
}

impl ClickTracker {
    fn register_click(&mut self, pos: PhysicalPosition<f64>, now: Instant) -> u8 {
        let within_time = self
            .last_click_at
            .map(|t| now.duration_since(t) <= Duration::from_millis(450))
            .unwrap_or(false);
        let within_dist = self
            .last_click_pos
            .map(|p| {
                let dx = (p.x - pos.x).abs();
                let dy = (p.y - pos.y).abs();
                dx <= 6.0 && dy <= 6.0
            })
            .unwrap_or(false);

        if within_time && within_dist {
            self.click_count = self.click_count.saturating_add(1).min(4);
        } else {
            self.click_count = 1;
        }
        self.last_click_at = Some(now);
        self.last_click_pos = Some(pos);
        self.click_count
    }
}
