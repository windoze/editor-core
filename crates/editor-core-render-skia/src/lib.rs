//! Skia-based renderer for `editor-core`.
//!
//! This crate is intentionally focused on rendering only.
//! It does **not** own editor state. See `editor-core-ui` for the UI-facing
//! composition layer (editor state + input mapping + rendering).

use editor_core::snapshot::HeadlessGrid;
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
}

impl Default for RenderTheme {
    fn default() -> Self {
        Self {
            background: Rgba8::new(0xFF, 0xFF, 0xFF, 0xFF),
            foreground: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            selection_background: Rgba8::new(0xC7, 0xDD, 0xFF, 0xFF),
            caret: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
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
    #[error("rendering backend not initialized")]
    NotInitialized,
    #[error("render not implemented yet")]
    NotImplemented,
}

/// A renderer instance (Skia backend in later steps).
///
/// For MVP0 we keep this as a placeholder; implementation will be added
/// incrementally with deterministic tests.
#[derive(Debug, Default)]
pub struct SkiaRenderer;

impl SkiaRenderer {
    pub fn new() -> Self {
        Self
    }

    /// Render a viewport `grid` to an RGBA8 buffer (premultiplied).
    ///
    /// The returned buffer length is `width_px * height_px * 4`.
    pub fn render_rgba(
        &mut self,
        _grid: &HeadlessGrid,
        _caret: Option<VisualCaret>,
        _selection: Option<VisualSelection>,
        config: RenderConfig,
        _theme: &RenderTheme,
    ) -> Result<Vec<u8>, RenderError> {
        if config.width_px == 0 || config.height_px == 0 {
            return Err(RenderError::InvalidSize {
                width_px: config.width_px,
                height_px: config.height_px,
            });
        }
        Err(RenderError::NotImplemented)
    }
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
                Some(VisualCaret { row: 0, x_cells: 0 }),
                None,
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
}

