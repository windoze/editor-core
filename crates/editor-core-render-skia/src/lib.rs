//! Skia-based renderer for `editor-core`.
//!
//! This crate is intentionally focused on rendering only.
//! It does **not** own editor state. See `editor-core-ui` for the UI-facing
//! composition layer (editor state + input mapping + rendering).

use std::collections::BTreeMap;
use thiserror::Error;

#[cfg(test)]
use editor_core::{DOCUMENT_LINK_STYLE_ID, IME_MARKED_TEXT_STYLE_ID};
#[cfg(test)]
use skia_safe::{Font, FontMgr, FontStyle, Point, Shaper};

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
    /// Optional per-style font styling overrides (`StyleId -> font style`).
    ///
    /// Notes:
    /// - This controls purely visual glyph styling (bold / italic). It does not affect layout
    ///   (cell widths, wrapping, hit-testing).
    /// - Font fallback is still best-effort; if a bold/italic variant cannot be loaded for a given
    ///   family, Skia will fall back to the closest available style.
    pub style_fonts: BTreeMap<u32, StyleFont>,
    /// Optional per-style text decorations (`StyleId -> decorations`).
    ///
    /// This is distinct from `editor-core` "decorations" (virtual text). These are purely visual
    /// line effects applied while rendering a cell (underline, strikethrough, etc.).
    pub text_decorations: BTreeMap<u32, TextDecorations>,
}

/// Reserved StyleIds for UI chrome rendered outside the document text grid (gutter, fold markers, ...).
///
/// These are rendered by the Skia renderer itself (not by `editor-core`), but can still be themed via
/// `RenderTheme.styles`.
pub const UI_OVERLAY_BASE_STYLE_ID: u32 = 0x0600_0000;
pub const GUTTER_BACKGROUND_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 1;
pub const GUTTER_FOREGROUND_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 2;
pub const GUTTER_SEPARATOR_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 3;
pub const FOLD_MARKER_COLLAPSED_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 4;
pub const FOLD_MARKER_EXPANDED_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 5;
pub const INDENT_GUIDE_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 6;
pub const WHITESPACE_STYLE_ID: u32 = UI_OVERLAY_BASE_STYLE_ID | 7;

/// How to render fold markers in the gutter.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum FoldMarkerStyle {
    /// Do not draw fold markers (folding can still exist, but the gutter indicator is hidden).
    Hidden,
    /// Fill the whole fold-marker cell with the configured color (legacy behavior).
    Block,
    /// Draw a VSCode-like arrow indicator.
    #[default]
    Triangle,
}

/// How to render whitespace characters (spaces + tabs).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WhitespaceRenderMode {
    /// Do not render whitespace markers.
    #[default]
    None,
    /// Render whitespace markers only inside the current selection range(s).
    Selection,
    /// Render whitespace markers everywhere (global "show whitespace" mode).
    All,
}

impl Default for RenderTheme {
    fn default() -> Self {
        Self {
            background: Rgba8::new(0xFF, 0xFF, 0xFF, 0xFF),
            foreground: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            selection_background: Rgba8::new(0xC7, 0xDD, 0xFF, 0xFF),
            caret: Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
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

/// Per-style font styling overrides (bold / italic).
///
/// Notes:
/// - Fields are optional so `StyleId`s can be layered; "last wins" per field.
/// - This is intentionally small and renderer-focused; if the UI needs richer typography later
///   (weights, slants, custom typefaces), we can extend the ABI with a v1 struct.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct StyleFont {
    /// Whether to render bold text.
    pub bold: Option<bool>,
    /// Whether to render italic text.
    pub italic: Option<bool>,
}

/// Underline style.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnderlineStyle {
    /// A single straight underline.
    Single,
    /// Two straight underlines.
    Double,
    /// A "squiggly" underline (typically used for diagnostics).
    Squiggly,
}

/// Per-style text decorations.
///
/// Notes:
/// - This is intentionally separate from color styling (`StyleColors`) so hosts can choose
///   underline/strikethrough without changing text fg/bg.
/// - All fields are optional so multiple `StyleId`s can be layered; "last wins" per field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TextDecorations {
    /// Underline style (if any).
    pub underline: Option<UnderlineStyle>,
    /// Underline color override (defaults to the resolved cell foreground).
    pub underline_color: Option<Rgba8>,
    /// Whether to render strikethrough.
    ///
    /// - `None`: do not override
    /// - `Some(true)`: enable
    /// - `Some(false)`: disable
    pub strikethrough: Option<bool>,
    /// Strikethrough color override (defaults to the resolved cell foreground).
    pub strikethrough_color: Option<Rgba8>,
}

/// Vertical alignment of glyphs within a single line box (`line_height_px`).
///
/// This controls how the font's baseline is positioned between the line's top and bottom edges.
/// It does **not** change hit-testing or selection/caret rectangles, which remain based on
/// the monospace cell grid + `line_height_px`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TextVerticalAlign {
    /// Keep glyphs flush to the top of the line box (baseline at `-ascent`).
    Top,
    /// Center glyphs within the line box (distribute extra leading equally).
    #[default]
    Center,
    /// Keep glyphs flush to the bottom of the line box (baseline at `line_height_px - descent`).
    Bottom,
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
    /// How to vertically align text within `line_height_px`.
    pub text_vertical_align: TextVerticalAlign,
    /// Cell width in pixels (monospace column width).
    pub cell_width_px: f32,
    /// Left padding in pixels.
    pub padding_x_px: f32,
    /// Top padding in pixels.
    pub padding_y_px: f32,
    /// Smooth-scroll sub-row offset in pixels.
    ///
    /// Positive values scroll the content **up** (revealing later lines), i.e. the same direction
    /// as increasing `scroll_top` in visual rows.
    ///
    /// The UI layer is expected to keep this in the range `0..line_height_px`.
    pub scroll_y_px: f32,
    /// Gutter width in "cells" (monospace columns).
    ///
    /// When non-zero, the renderer draws a gutter (line numbers + fold markers) and shifts the
    /// document text by `gutter_width_cells * cell_width_px`.
    pub gutter_width_cells: u32,

    /// Tab width (in cells) used for rendering tab-related UI (indent guides, etc).
    ///
    /// Notes:
    /// - This does not affect layout. Tab expansion for the actual text grid is performed by
    ///   `editor-core` when building the viewport snapshot (cell widths).
    pub tab_width_cells: u32,

    /// Whether to draw indentation guides (VSCode-like).
    pub show_indent_guides: bool,

    /// How to render fold markers in the gutter.
    pub fold_marker_style: FoldMarkerStyle,

    /// How to render whitespace markers (spaces + tabs).
    pub whitespace_render_mode: WhitespaceRenderMode,

    /// Enable font ligatures (e.g. Fira Code) for ASCII runs.
    ///
    /// Notes:
    /// - The editor still uses a monospace "cell grid" model; ligature shaping is purely visual.
    /// - Cursor/selection hit-testing remains cell-based.
    pub enable_ligatures: bool,

    /// Caret width in pixels.
    ///
    /// Notes:
    /// - This is an absolute pixel width (already includes `scale` if the UI operates in points).
    /// - The renderer will clamp it to a minimum of 1px when the caret is visible.
    pub caret_width_px: f32,

    /// Whether to draw carets at all.
    ///
    /// This is intended for UI-side caret blinking and focus handling.
    pub show_caret: bool,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            width_px: 800,
            height_px: 600,
            scale: 1.0,
            font_size: 13.0,
            line_height_px: 18.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 8.0,
            padding_x_px: 8.0,
            padding_y_px: 8.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            tab_width_cells: 4,
            show_indent_guides: false,
            fold_marker_style: FoldMarkerStyle::default(),
            whitespace_render_mode: WhitespaceRenderMode::default(),
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
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

/// Fold marker metadata for gutter rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FoldMarker {
    pub logical_line: u32,
    pub is_collapsed: bool,
}

#[derive(Debug, Error)]
pub enum RenderError {
    #[error("invalid render size {width_px}x{height_px}")]
    InvalidSize { width_px: u32, height_px: u32 },
    #[error("render size overflows buffer length: {width_px}x{height_px}")]
    SizeOverflow { width_px: u32, height_px: u32 },
    #[error("output buffer too small: required {required} bytes, provided {provided} bytes")]
    BufferTooSmall { required: usize, provided: usize },
    #[error("failed to create Skia surface")]
    SurfaceCreateFailed,
    #[error("metal is not supported on this platform")]
    MetalUnsupported,
    #[error("metal device or command queue is null")]
    MetalInvalidHandle,
    #[error("failed to create Skia Metal GPU context")]
    MetalContextCreateFailed,
    #[error("metal renderer is not enabled")]
    MetalNotEnabled,
    #[error("metal texture handle is null")]
    MetalTextureNull,
}

mod renderer;

pub use renderer::SkiaRenderer;
#[cfg(test)]
pub(crate) use renderer::{FontVariant, make_configured_font, normalize_font_family_name};

#[cfg(test)]
mod tests;
