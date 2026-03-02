//! Skia-based renderer for `editor-core`.
//!
//! This crate is intentionally focused on rendering only.
//! It does **not** own editor state. See `editor-core-ui` for the UI-facing
//! composition layer (editor state + input mapping + rendering).

use editor_core::snapshot::HeadlessGrid;
use skia_safe::{
    AlphaType, Color, Color4f, ColorSpace, ColorType, Font, ImageInfo, Paint, Point, Rect, surfaces,
};
use std::collections::BTreeMap;
use thiserror::Error;

/// RGBA (premultiplied) 8-bit color.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba8 {
    pub const fn new(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }
}

/// Minimal theme for the renderer (v0).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderTheme {
    pub background: Rgba8,
    pub foreground: Rgba8,
    pub selection_background: Rgba8,
    pub caret: Rgba8,
    /// Optional per-style overrides (`StyleId -> colors`).
    pub styles: BTreeMap<u32, StyleColors>,
}

impl Default for RenderTheme {
    fn default() -> Self {
        Self {
            background: Rgba8::new(0xFF, 0xFF, 0xFF, 0xFF),
            foreground: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            selection_background: Rgba8::new(0xC7, 0xDD, 0xFF, 0xFF),
            caret: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            styles: BTreeMap::new(),
        }
    }
}

/// Per-style color overrides.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StyleColors {
    pub foreground: Option<Rgba8>,
    pub background: Option<Rgba8>,
}

impl StyleColors {
    pub const fn new(foreground: Option<Rgba8>, background: Option<Rgba8>) -> Self {
        Self {
            foreground,
            background,
        }
    }
}

/// Pixel-size configuration for rendering a viewport.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RenderConfig {
    /// Output width in pixels.
    pub width_px: u32,
    /// Output height in pixels.
    pub height_px: u32,
    /// Device scale factor (e.g. 2.0 on Retina).
    pub scale: f32,
    /// Monospace font size in points/pixels (implementation-defined).
    pub font_size: f32,
    /// Line height in pixels.
    pub line_height_px: f32,
    /// Cell width in pixels (monospace column width).
    pub cell_width_px: f32,
    /// Left padding in pixels.
    pub padding_x_px: f32,
    /// Top padding in pixels.
    pub padding_y_px: f32,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            width_px: 800,
            height_px: 600,
            scale: 1.0,
            font_size: 13.0,
            line_height_px: 18.0,
            cell_width_px: 8.0,
            padding_x_px: 8.0,
            padding_y_px: 8.0,
        }
    }
}

/// Caret position in visual space (row + x in cells).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VisualCaret {
    pub row: u32,
    pub x_cells: u32,
}

/// A single selection range in visual space.
///
/// Note: v0 keeps this simple and uses inclusive-exclusive range in cells.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VisualSelection {
    pub start_row: u32,
    pub start_x_cells: u32,
    pub end_row: u32,
    pub end_x_cells: u32,
}

#[derive(Debug, Error)]
pub enum RenderError {
    #[error("invalid render size {width_px}x{height_px}")]
    InvalidSize { width_px: u32, height_px: u32 },
    #[error("failed to create Skia surface")]
    SurfaceCreateFailed,
}

/// A renderer instance (Skia backend in later steps).
///
/// For MVP0 we keep this as a placeholder; implementation will be added
/// incrementally with deterministic tests.
#[derive(Debug)]
pub struct SkiaRenderer {
    font: Font,
}

impl SkiaRenderer {
    pub fn new() -> Self {
        let mut font = Font::default();
        font.set_size(RenderConfig::default().font_size);
        Self { font }
    }

    /// Render a viewport `grid` to an RGBA8 buffer (premultiplied).
    ///
    /// The returned buffer length is `width_px * height_px * 4`.
    pub fn render_rgba(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        config: RenderConfig,
        theme: &RenderTheme,
    ) -> Result<Vec<u8>, RenderError> {
        if config.width_px == 0 || config.height_px == 0 {
            return Err(RenderError::InvalidSize {
                width_px: config.width_px,
                height_px: config.height_px,
            });
        }

        // Keep renderer font size in sync with config.
        if (self.font.size() - config.font_size).abs() > f32::EPSILON {
            self.font.set_size(config.font_size);
        }

        let width = config.width_px as i32;
        let height = config.height_px as i32;

        let bytes_per_row = config.width_px.checked_mul(4).expect("width*4 overflow") as usize;
        let mut pixels = vec![0u8; bytes_per_row * config.height_px as usize];

        let info = ImageInfo::new(
            (width, height),
            ColorType::RGBA8888,
            AlphaType::Premul,
            Some(ColorSpace::new_srgb()),
        );

        let mut surface = surfaces::wrap_pixels(&info, pixels.as_mut_slice(), bytes_per_row, None)
            .ok_or(RenderError::SurfaceCreateFailed)?;

        let canvas = surface.canvas();
        canvas.clear(rgba_to_skia_color4f(theme.background));

        // Selections first (under text).
        for sel in selections {
            draw_selection(canvas, grid, *sel, config, theme.selection_background);
        }

        // Text.
        let (_spacing, metrics) = self.font.metrics();
        let baseline_offset = -metrics.ascent;

        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top = config.padding_y_px + row_idx as f32 * config.line_height_px;
            let baseline_y = y_top + baseline_offset;

            let mut x_cells = line.segment_x_start_cells as f32;
            for cell in &line.cells {
                let x_px = config.padding_x_px + x_cells * config.cell_width_px;
                let (fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);

                if bg != theme.background {
                    let w_px = cell.width as f32 * config.cell_width_px;
                    let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                    let mut bg_paint = Paint::default();
                    bg_paint.set_anti_alias(false);
                    bg_paint.set_color(rgba_to_skia_color(bg));
                    canvas.draw_rect(rect, &bg_paint);
                }

                let mut paint = Paint::default();
                paint.set_anti_alias(true);
                paint.set_color(rgba_to_skia_color(fg));
                canvas.draw_str(
                    cell.ch.to_string(),
                    Point::new(x_px, baseline_y),
                    &self.font,
                    &paint,
                );
                x_cells += cell.width as f32;
            }
        }

        // Carets on top.
        for caret in carets {
            draw_caret(canvas, grid, *caret, config, theme.caret);
        }

        Ok(pixels)
    }
}

fn rgba_to_skia_color(c: Rgba8) -> Color {
    Color::from_argb(c.a, c.r, c.g, c.b)
}

fn rgba_to_skia_color4f(c: Rgba8) -> Color4f {
    Color4f::new(
        c.r as f32 / 255.0,
        c.g as f32 / 255.0,
        c.b as f32 / 255.0,
        c.a as f32 / 255.0,
    )
}

fn draw_caret(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    caret: VisualCaret,
    config: RenderConfig,
    color: Rgba8,
) {
    let start_row = grid.start_visual_row as i64;
    let local_row = caret.row as i64 - start_row;
    if local_row < 0 {
        return;
    }
    let local_row = local_row as usize;
    if local_row >= grid.lines.len() {
        return;
    }

    let x_px = config.padding_x_px + caret.x_cells as f32 * config.cell_width_px;
    let y_top = config.padding_y_px + local_row as f32 * config.line_height_px;

    let caret_width = (config.scale.max(1.0)).min(2.0);
    let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

fn draw_selection(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    selection: VisualSelection,
    config: RenderConfig,
    color: Rgba8,
) {
    let (mut a_row, mut a_x) = (selection.start_row as i64, selection.start_x_cells as i64);
    let (mut b_row, mut b_x) = (selection.end_row as i64, selection.end_x_cells as i64);
    if (b_row, b_x) < (a_row, a_x) {
        std::mem::swap(&mut a_row, &mut b_row);
        std::mem::swap(&mut a_x, &mut b_x);
    }

    let grid_start = grid.start_visual_row as i64;
    let grid_end = grid_start + grid.lines.len() as i64;

    // Clamp selection to viewport range.
    let sel_start_row = a_row.max(grid_start);
    let sel_end_row = b_row.min(grid_end.saturating_sub(1));
    if sel_end_row < sel_start_row {
        return;
    }

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    for row in sel_start_row..=sel_end_row {
        let local_row = (row - grid_start) as usize;
        let line = match grid.lines.get(local_row) {
            Some(l) => l,
            None => continue,
        };

        let line_total_cells: i64 = line.cells.iter().map(|c| c.width as i64).sum::<i64>()
            + line.segment_x_start_cells as i64;

        let start_x = if row == a_row { a_x } else { 0 };
        let end_x = if row == b_row { b_x } else { line_total_cells };

        if end_x <= start_x {
            continue;
        }

        let x_px = config.padding_x_px + start_x as f32 * config.cell_width_px;
        let w_px = (end_x - start_x) as f32 * config.cell_width_px;
        let y_top = config.padding_y_px + local_row as f32 * config.line_height_px;
        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
        canvas.draw_rect(rect, &paint);
    }
}

fn resolve_cell_colors(style_ids: &[u32], theme: &RenderTheme) -> (Rgba8, Rgba8) {
    let mut fg = theme.foreground;
    let mut bg = theme.background;
    for id in style_ids {
        if let Some(colors) = theme.styles.get(id) {
            if let Some(f) = colors.foreground {
                fg = f;
            }
            if let Some(b) = colors.background {
                bg = b;
            }
        }
    }
    (fg, bg)
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::snapshot::{Cell, HeadlessGrid, HeadlessLine};

    #[test]
    fn render_rejects_zero_size() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('a', 1));
        grid.add_line(line);

        let err = renderer
            .render_rgba(
                &grid,
                &[VisualCaret { row: 0, x_cells: 0 }],
                &[],
                RenderConfig {
                    width_px: 0,
                    height_px: 10,
                    ..RenderConfig::default()
                },
                &RenderTheme::default(),
            )
            .unwrap_err();
        assert!(matches!(err, RenderError::InvalidSize { .. }));
    }

    #[test]
    fn render_fills_background_and_draws_selection_and_caret() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('a', 1));
        line.add_cell(Cell::new('b', 1));
        line.add_cell(Cell::new('c', 1));
        grid.add_line(line);

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 80,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
        };

        let rgba = renderer
            .render_rgba(
                &grid,
                &[VisualCaret { row: 0, x_cells: 3 }],
                &[VisualSelection {
                    start_row: 0,
                    start_x_cells: 0,
                    end_row: 0,
                    end_x_cells: 2,
                }],
                cfg,
                &theme,
            )
            .unwrap();

        assert_eq!(rgba.len(), (cfg.width_px * cfg.height_px * 4) as usize);

        // Background at (70, 30) should be background color (no selection/caret there).
        assert_eq!(pixel(&rgba, cfg.width_px, 70, 30), [10, 20, 30, 255]);

        // Selection area should be selection color.
        assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [200, 0, 0, 255]);

        // Caret should be caret color (x=30, y=10).
        assert_eq!(pixel(&rgba, cfg.width_px, 30, 10), [0, 0, 200, 255]);
    }

    #[test]
    fn render_applies_style_background_overrides() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('a', 1));
        line.add_cell(Cell::with_styles('b', 1, vec![42]));
        line.add_cell(Cell::new('c', 1));
        grid.add_line(line);

        let mut theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
        };
        theme
            .styles
            .insert(42, StyleColors::new(None, Some(Rgba8::new(1, 200, 2, 255))));

        let cfg = RenderConfig {
            width_px: 80,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], cfg, &theme)
            .unwrap();

        // Cell 'b' is at x in [10..20], pick center pixel.
        assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [1, 200, 2, 255]);
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }

    #[test]
    fn render_draws_multiple_carets_and_selections() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        for ch in ['a', 'b', 'c', 'd', 'e'] {
            line.add_cell(Cell::new(ch, 1));
        }
        grid.add_line(line);

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 120,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
        };

        let carets = [
            VisualCaret { row: 0, x_cells: 1 },
            VisualCaret { row: 0, x_cells: 4 },
        ];
        let selections = [
            VisualSelection {
                start_row: 0,
                start_x_cells: 0,
                end_row: 0,
                end_x_cells: 1,
            },
            VisualSelection {
                start_row: 0,
                start_x_cells: 3,
                end_row: 0,
                end_x_cells: 5,
            },
        ];

        let rgba = renderer
            .render_rgba(&grid, &carets, &selections, cfg, &theme)
            .unwrap();

        // Selection 1 should be red at x ~ 5.
        assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [200, 0, 0, 255]);
        // Selection 2 should be red at x ~ 35.
        assert_eq!(pixel(&rgba, cfg.width_px, 35, 10), [200, 0, 0, 255]);

        // Caret 1 at x=10.
        assert_eq!(pixel(&rgba, cfg.width_px, 10, 10), [0, 0, 200, 255]);
        // Caret 2 at x=40.
        assert_eq!(pixel(&rgba, cfg.width_px, 40, 10), [0, 0, 200, 255]);
    }
}
