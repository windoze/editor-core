//! Skia-based renderer for `editor-core`.
//!
//! This crate is intentionally focused on rendering only.
//! It does **not** own editor state. See `editor-core-ui` for the UI-facing
//! composition layer (editor state + input mapping + rendering).

use editor_core::{
    DOCUMENT_LINK_STYLE_ID, IME_MARKED_TEXT_STYLE_ID,
    snapshot::{ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind, HeadlessGrid},
};
use skia_safe::Shaper;
use skia_safe::shaper::run_handler::{Buffer, RunInfo};
use skia_safe::shaper::{Feature, RunHandler};
use skia_safe::{
    AlphaType, Color, Color4f, ColorSpace, ColorType, Font, FontHinting, FontMgr, FontStyle,
    FourByteTag, GlyphId, ImageInfo, Paint, Path, PathBuilder, Point, Rect, surfaces,
};
use std::collections::{BTreeMap, HashMap};
use std::ffi::c_void;
use thiserror::Error;

#[cfg(target_os = "macos")]
use skia_safe::gpu;

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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FoldMarkerStyle {
    /// Do not draw fold markers (folding can still exist, but the gutter indicator is hidden).
    Hidden,
    /// Fill the whole fold-marker cell with the configured color (legacy behavior).
    Block,
    /// Draw a VSCode-like triangle indicator.
    Triangle,
}

impl Default for FoldMarkerStyle {
    fn default() -> Self {
        Self::Block
    }
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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextVerticalAlign {
    /// Keep glyphs flush to the top of the line box (baseline at `-ascent`).
    Top,
    /// Center glyphs within the line box (distribute extra leading equally).
    Center,
    /// Keep glyphs flush to the bottom of the line box (baseline at `line_height_px - descent`).
    Bottom,
}

impl Default for TextVerticalAlign {
    fn default() -> Self {
        Self::Center
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

#[cfg(target_os = "macos")]
#[derive(Debug)]
struct SkiaMetalState {
    _backend_context: gpu::mtl::BackendContext,
    context: gpu::DirectContext,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FontVariant {
    Normal,
    Bold,
    Italic,
    BoldItalic,
}

impl FontVariant {
    fn from_flags(bold: bool, italic: bool) -> Self {
        match (bold, italic) {
            (false, false) => Self::Normal,
            (true, false) => Self::Bold,
            (false, true) => Self::Italic,
            (true, true) => Self::BoldItalic,
        }
    }
}

#[derive(Debug)]
struct FontSet {
    fonts: Vec<Font>,
    glyph_font_cache: HashMap<char, usize>,
}

impl FontSet {
    fn new(fonts: Vec<Font>) -> Self {
        Self {
            fonts,
            glyph_font_cache: HashMap::new(),
        }
    }

    fn ensure_size(&mut self, size: f32) {
        for f in &mut self.fonts {
            f.set_size(size);
        }
    }

    fn font_index_for_char(&mut self, ch: char) -> usize {
        if self.fonts.len() <= 1 {
            return 0;
        }
        if let Some(&idx) = self.glyph_font_cache.get(&ch) {
            return idx;
        }

        let mut idx = 0usize;
        for (i, f) in self.fonts.iter().enumerate() {
            let tf = f.typeface();
            // Skia returns glyph id 0 for missing glyphs / .notdef.
            if tf.unichar_to_glyph(ch as i32) != 0 {
                idx = i;
                break;
            }
        }

        self.glyph_font_cache.insert(ch, idx);
        idx
    }

    fn font_for_index(&self, idx: usize) -> &Font {
        // Safety: index always comes from `fonts` indices or defaults to 0.
        &self.fonts[idx.min(self.fonts.len().saturating_sub(1))]
    }
}

/// A renderer instance (Skia backend in later steps).
///
/// For MVP0 we keep this as a placeholder; implementation will be added
/// incrementally with deterministic tests.
#[derive(Debug)]
pub struct SkiaRenderer {
    fonts_normal: FontSet,
    fonts_bold: FontSet,
    fonts_italic: FontSet,
    fonts_bold_italic: FontSet,
    font_families: Vec<String>,
    font_size: f32,
    shaper: Shaper,
    #[cfg(target_os = "macos")]
    metal: Option<SkiaMetalState>,
}

impl SkiaRenderer {
    pub fn new() -> Self {
        let font_size = RenderConfig::default().font_size;
        let families: Vec<String> = default_font_families()
            .into_iter()
            .map(|s| s.to_string())
            .collect();
        let fonts_normal = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::normal(),
        ));
        let fonts_bold = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::bold(),
        ));
        let fonts_italic = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::italic(),
        ));
        let fonts_bold_italic = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::bold_italic(),
        ));
        Self {
            fonts_normal,
            fonts_bold,
            fonts_italic,
            fonts_bold_italic,
            font_families: families,
            font_size,
            shaper: Shaper::new(None),
            #[cfg(target_os = "macos")]
            metal: None,
        }
    }

    fn baseline_offset_px(&self, config: RenderConfig) -> f32 {
        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );

        let (_spacing, metrics) = { self.fonts_normal.fonts[0].metrics() };
        let ascent = metrics.ascent;
        let descent = metrics.descent;

        let line_h = config.line_height_px.max(1.0);
        let mut baseline_offset = match config.text_vertical_align {
            TextVerticalAlign::Top => -ascent,
            TextVerticalAlign::Center => (line_h - (descent - ascent)) * 0.5 - ascent,
            TextVerticalAlign::Bottom => line_h - descent,
        };
        if !baseline_offset.is_finite() {
            baseline_offset = line_h * 0.8;
        }
        baseline_offset.clamp(0.0, line_h)
    }

    /// Configure the font fallback chain (first match wins).
    ///
    /// Notes:
    /// - This keeps the renderer "monospace-grid" layout model: glyph shaping/advance does not affect
    ///   cell metrics; only glyph rasterization uses fallbacks.
    /// - If no provided family can be loaded, we fall back to a reasonable monospace default.
    pub fn set_font_families(&mut self, families: Vec<String>) {
        let normalized: Vec<String> = families
            .into_iter()
            .map(|s| normalize_font_family_name(s.as_str()))
            .filter(|s| !s.is_empty())
            .collect();

        let families_to_load: Vec<String> = if normalized.is_empty() {
            default_font_families()
                .into_iter()
                .map(|s| s.to_string())
                .collect()
        } else {
            normalized.clone()
        };

        self.font_families = normalized;
        self.fonts_normal = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::normal(),
        ));
        self.fonts_bold = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::bold(),
        ));
        self.fonts_italic = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::italic(),
        ));
        self.fonts_bold_italic = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::bold_italic(),
        ));
    }

    fn font_set(&self, variant: FontVariant) -> &FontSet {
        match variant {
            FontVariant::Normal => &self.fonts_normal,
            FontVariant::Bold => &self.fonts_bold,
            FontVariant::Italic => &self.fonts_italic,
            FontVariant::BoldItalic => &self.fonts_bold_italic,
        }
    }

    fn font_set_mut(&mut self, variant: FontVariant) -> &mut FontSet {
        match variant {
            FontVariant::Normal => &mut self.fonts_normal,
            FontVariant::Bold => &mut self.fonts_bold,
            FontVariant::Italic => &mut self.fonts_italic,
            FontVariant::BoldItalic => &mut self.fonts_bold_italic,
        }
    }

    fn font_index_for_char(&mut self, ch: char, variant: FontVariant) -> usize {
        self.font_set_mut(variant).font_index_for_char(ch)
    }

    fn font_for_variant_index(&self, variant: FontVariant, idx: usize) -> &Font {
        self.font_set(variant).font_for_index(idx)
    }

    fn normal_primary_font(&self) -> &Font {
        self.fonts_normal.font_for_index(0)
    }

    /// Enable Skia GPU rendering via Metal (macOS only).
    ///
    /// The host is responsible for providing valid, long-lived Metal objects:
    /// - `device`: `id<MTLDevice>`
    /// - `command_queue`: `id<MTLCommandQueue>`
    ///
    /// Safety note:
    /// - We only store the raw handles inside Skia's Metal backend context.
    /// - The caller must ensure the Objective-C objects outlive this `SkiaRenderer`
    ///   (or call `disable_metal()` before releasing them).
    pub fn enable_metal(
        &mut self,
        device: *mut c_void,
        command_queue: *mut c_void,
    ) -> Result<(), RenderError> {
        #[cfg(target_os = "macos")]
        {
            if device.is_null() || command_queue.is_null() {
                return Err(RenderError::MetalInvalidHandle);
            }

            // SAFETY:
            // - The caller guarantees `device` and `command_queue` are valid Metal objects and
            //   outlive the created backend context.
            let backend = unsafe {
                gpu::mtl::BackendContext::new(
                    device as gpu::mtl::Handle,
                    command_queue as gpu::mtl::Handle,
                )
            };

            let context = gpu::direct_contexts::make_metal(&backend, None)
                .ok_or(RenderError::MetalContextCreateFailed)?;

            self.metal = Some(SkiaMetalState {
                _backend_context: backend,
                context,
            });
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (device, command_queue);
            Err(RenderError::MetalUnsupported)
        }
    }

    /// Disable the Metal backend (if enabled), reverting to CPU raster output.
    pub fn disable_metal(&mut self) {
        #[cfg(target_os = "macos")]
        {
            self.metal = None;
        }
    }

    pub fn is_metal_enabled(&self) -> bool {
        #[cfg(target_os = "macos")]
        {
            self.metal.is_some()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    fn ensure_font_size(&mut self, size: f32) {
        if (self.font_size - size).abs() <= f32::EPSILON {
            return;
        }
        self.font_size = size;
        self.fonts_normal.ensure_size(size);
        self.fonts_bold.ensure_size(size);
        self.fonts_italic.ensure_size(size);
        self.fonts_bold_italic.ensure_size(size);
    }

    fn ligature_features(enabled: bool) -> [Feature; 3] {
        let v = if enabled { 1 } else { 0 };
        [
            make_shaper_feature(FourByteTag::from_chars('l', 'i', 'g', 'a'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'a', 'l', 't'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'l', 'i', 'g'), v),
        ]
    }

    fn draw_shaped_run(
        &self,
        canvas: &skia_safe::Canvas,
        run_text: &str,
        font: &Font,
        x_px: f32,
        baseline_y: f32,
        cell_width_px: f32,
        paint: &Paint,
        enable_ligatures: bool,
    ) {
        if run_text.is_empty() {
            return;
        }

        #[derive(Default)]
        struct CollectGlyphsRunHandler {
            glyphs: Vec<GlyphId>,
            positions: Vec<Point>,
            clusters: Vec<u32>,
            out_glyphs: Vec<GlyphId>,
            out_clusters: Vec<u32>,
        }

        impl RunHandler for CollectGlyphsRunHandler {
            fn begin_line(&mut self) {}
            fn run_info(&mut self, _info: &RunInfo) {}
            fn commit_run_info(&mut self) {}
            fn run_buffer(&mut self, info: &RunInfo) -> Buffer<'_> {
                let count = info.glyph_count;
                self.glyphs.resize(count, GlyphId::default());
                self.positions.resize(count, Point::default());
                self.clusters.resize(count, 0);
                Buffer {
                    glyphs: self.glyphs.as_mut_slice(),
                    positions: self.positions.as_mut_slice(),
                    offsets: None,
                    clusters: Some(self.clusters.as_mut_slice()),
                    point: Point::default(),
                }
            }
            fn commit_run_buffer(&mut self, _info: &RunInfo) {
                self.out_glyphs.extend_from_slice(&self.glyphs);
                self.out_clusters.extend_from_slice(&self.clusters);
            }
            fn commit_line(&mut self) {}
        }

        let width = 1_000_000.0;
        let features = Self::ligature_features(enable_ligatures);
        let utf8_len = run_text.as_bytes().len();

        let mut font_it = Shaper::new_trivial_font_run_iterator(font, utf8_len);
        let mut bidi_it = skia_safe::shapers::primitive::trivial_bidi_run_iterator(0, utf8_len);
        let mut script_it = skia_safe::shapers::primitive::trivial_script_run_iterator(0, utf8_len);
        let mut lang_it = Shaper::new_trivial_language_run_iterator("en", utf8_len);

        let mut handler = CollectGlyphsRunHandler::default();
        self.shaper.shape_with_iterators_and_features(
            run_text,
            &mut font_it,
            &mut bidi_it,
            &mut script_it,
            &mut lang_it,
            features.as_slice(),
            width,
            &mut handler,
        );

        if handler.out_glyphs.is_empty() || handler.out_glyphs.len() != handler.out_clusters.len() {
            // Fallback: draw without shaping (no ligatures), but avoid dropping text.
            canvas.draw_str(run_text, Point::new(x_px, baseline_y), font, paint);
            return;
        }

        // IMPORTANT:
        // We do *not* use the shaper-provided glyph positions here.
        // The editor's layout model is a fixed-width "cell grid", so we place glyphs on cell
        // boundaries to avoid kerning/positioning drifting away from the grid.
        //
        // Ligature fonts like Fira Code encode ligature glyphs whose advance spans multiple cells,
        // so drawing the ligature glyph at the cluster-start cell produces the expected effect.
        let mut positions = Vec::<Point>::with_capacity(handler.out_glyphs.len());
        for &cluster in &handler.out_clusters {
            let x_cells = cluster as f32; // ASCII => utf8 byte offset == char index == cell index
            positions.push(Point::new(x_cells * cell_width_px, 0.0));
        }

        canvas.draw_glyphs_at(
            handler.out_glyphs.as_slice(),
            positions.as_slice(),
            Point::new(x_px, baseline_y),
            font,
            paint,
        );
    }

    pub fn required_rgba_len(config: RenderConfig) -> Result<usize, RenderError> {
        if config.width_px == 0 || config.height_px == 0 {
            return Err(RenderError::InvalidSize {
                width_px: config.width_px,
                height_px: config.height_px,
            });
        }
        (config.width_px as usize)
            .checked_mul(config.height_px as usize)
            .and_then(|v| v.checked_mul(4))
            .ok_or(RenderError::SizeOverflow {
                width_px: config.width_px,
                height_px: config.height_px,
            })
    }

    /// Render a viewport `grid` to an RGBA8 buffer (premultiplied).
    ///
    /// The returned buffer length is `width_px * height_px * 4`.
    pub fn render_rgba(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
    ) -> Result<Vec<u8>, RenderError> {
        let required = Self::required_rgba_len(config)?;

        let mut pixels = vec![0u8; required];
        self.render_rgba_into(
            grid,
            carets,
            selections,
            fold_markers,
            config,
            theme,
            pixels.as_mut_slice(),
        )?;
        Ok(pixels)
    }

    /// Render a viewport `grid` into a caller-provided RGBA8 buffer (premultiplied).
    ///
    /// Only the first `width_px * height_px * 4` bytes are written.
    pub fn render_rgba_into(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        out_rgba: &mut [u8],
    ) -> Result<(), RenderError> {
        let required = Self::required_rgba_len(config)?;
        if out_rgba.len() < required {
            return Err(RenderError::BufferTooSmall {
                required,
                provided: out_rgba.len(),
            });
        }

        self.ensure_font_size(config.font_size);

        let width = config.width_px as i32;
        let height = config.height_px as i32;

        let bytes_per_row = config.width_px as usize * 4;
        let pixels = &mut out_rgba[..required];

        let info = ImageInfo::new(
            (width, height),
            ColorType::RGBA8888,
            AlphaType::Premul,
            Some(ColorSpace::new_srgb()),
        );

        let mut surface = surfaces::wrap_pixels(&info, pixels, bytes_per_row, None)
            .ok_or(RenderError::SurfaceCreateFailed)?;

        let canvas = surface.canvas();
        self.draw_headless_grid_to_canvas(
            canvas,
            grid,
            carets,
            selections,
            fold_markers,
            config,
            theme,
        )
    }

    fn draw_headless_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
    ) -> Result<(), RenderError> {
        canvas.clear(rgba_to_skia_color4f(theme.background));

        let gutter_x = config.padding_x_px;
        let gutter_w_px = config.gutter_width_cells as f32 * config.cell_width_px;
        let text_origin_x = gutter_x + gutter_w_px;

        if config.gutter_width_cells > 0 && gutter_w_px > 0.0 {
            let gutter_bg =
                resolve_style_background(GUTTER_BACKGROUND_STYLE_ID, theme, theme.background);
            let rect = Rect::from_xywh(gutter_x, 0.0, gutter_w_px, config.height_px as f32);
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(gutter_bg));
            canvas.draw_rect(rect, &paint);

            let sep = resolve_style_foreground(GUTTER_SEPARATOR_STYLE_ID, theme, theme.foreground);
            let sep_rect = Rect::from_xywh(text_origin_x, 0.0, 1.0, config.height_px as f32);
            let mut sep_paint = Paint::default();
            sep_paint.set_anti_alias(false);
            sep_paint.set_color(rgba_to_skia_color(sep));
            canvas.draw_rect(sep_rect, &sep_paint);
        }

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        //
        // Selection is an overlay and must win over style backgrounds, so we draw it in a
        // separate pass *after* this.
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let mut x_cells = line.segment_x_start_cells as u32;
            for cell in &line.cells {
                let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                if bg != theme.background {
                    let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                    let w_px = cell.width as f32 * config.cell_width_px;
                    let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                    let mut bg_paint = Paint::default();
                    bg_paint.set_anti_alias(false);
                    bg_paint.set_color(rgba_to_skia_color(bg));
                    canvas.draw_rect(rect, &bg_paint);
                }
                x_cells = x_cells.saturating_add(cell.width as u32);
            }
        }

        // 2) Selection overlay (under text, over backgrounds).
        for sel in selections {
            draw_selection(
                canvas,
                grid,
                *sel,
                text_origin_x,
                config,
                theme.selection_background,
            );
        }

        // Text.
        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // Text + underlines.
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            if config.gutter_width_cells > 0 && line.visual_in_logical == 0 {
                let marker_state =
                    fold_marker_state_for_line(line.logical_line_index as u32, fold_markers);
                if let Some(is_collapsed) = marker_state {
                    let style_id = if is_collapsed {
                        FOLD_MARKER_COLLAPSED_STYLE_ID
                    } else {
                        FOLD_MARKER_EXPANDED_STYLE_ID
                    };
                    let rect = Rect::from_xywh(
                        gutter_x,
                        y_top,
                        config.cell_width_px,
                        config.line_height_px,
                    );
                    draw_fold_marker(
                        canvas,
                        rect,
                        is_collapsed,
                        config.fold_marker_style,
                        theme,
                        style_id,
                    );
                }

                // Line number text (best-effort; tests should not depend on glyph rasterization).
                let gutter_fg =
                    resolve_style_foreground(GUTTER_FOREGROUND_STYLE_ID, theme, theme.foreground);
                let mut paint = Paint::default();
                paint.set_anti_alias(false);
                paint.set_color(rgba_to_skia_color(gutter_fg));

                let line_no = (line.logical_line_index + 1).to_string();
                let x_px = gutter_x + config.cell_width_px; // leave first cell for fold marker
                canvas.draw_str(
                    line_no,
                    Point::new(x_px, baseline_y),
                    self.normal_primary_font(),
                    &paint,
                );
            }

            // Indent guides + whitespace markers are drawn after selection but before text.
            if config.show_indent_guides || config.whitespace_render_mode != WhitespaceRenderMode::None {
                let row_abs = grid.start_visual_row as i64 + row_idx as i64;
                let line_total_cells: i64 = line.cells.iter().map(|c| c.width as i64).sum::<i64>()
                    + line.segment_x_start_cells as i64;

                if config.show_indent_guides {
                    let mut indent_cells: u32 = line.segment_x_start_cells as u32;
                    for cell in &line.cells {
                        if cell.ch == ' ' || cell.ch == '\t' {
                            indent_cells = indent_cells.saturating_add(cell.width as u32);
                        } else {
                            break;
                        }
                    }

                    let tab_w = config.tab_width_cells.max(1);
                    let levels = indent_cells / tab_w;
                    if levels > 0 {
                        let guide_color = resolve_style_foreground_or_background(
                            INDENT_GUIDE_STYLE_ID,
                            theme,
                            default_indent_guide_color(theme),
                        );
                        let mut paint = Paint::default();
                        paint.set_anti_alias(false);
                        paint.set_color(rgba_to_skia_color(guide_color));

                        for level in 1..=levels {
                            // Place the guide on the boundary *between* indentation levels,
                            // i.e. right after a tabstop width.
                            let boundary_cells = level.saturating_mul(tab_w);
                            let x_px = (text_origin_x + boundary_cells as f32 * config.cell_width_px)
                                .round();
                            let rect = Rect::from_xywh(
                                x_px,
                                y_top,
                                1.0,
                                config.line_height_px,
                            );
                            canvas.draw_rect(rect, &paint);
                        }
                    }
                }

                let whitespace_mode = config.whitespace_render_mode;
                let draw_whitespace = match whitespace_mode {
                    WhitespaceRenderMode::None => false,
                    WhitespaceRenderMode::Selection => selections.is_empty() == false,
                    WhitespaceRenderMode::All => true,
                };
                if draw_whitespace {
                    let marker_color = resolve_style_foreground_or_background(
                        WHITESPACE_STYLE_ID,
                        theme,
                        default_whitespace_marker_color(theme),
                    );

                    let mut dot_paint = Paint::default();
                    dot_paint.set_anti_alias(true);
                    dot_paint.set_color(rgba_to_skia_color(marker_color));

                    let mut stroke_paint = Paint::default();
                    stroke_paint.set_anti_alias(true);
                    stroke_paint.set_color(rgba_to_skia_color(marker_color));
                    stroke_paint.set_style(skia_safe::paint::Style::Stroke);
                    stroke_paint.set_stroke_width(1.0);

                    let mut x_cells = line.segment_x_start_cells as u32;
                    for cell in &line.cells {
                        let w_cells = cell.width as u32;
                        let cell_start = x_cells as i64;
                        let cell_end = x_cells.saturating_add(w_cells) as i64;

                        let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
                        let selected = match whitespace_mode {
                            WhitespaceRenderMode::None => false,
                            WhitespaceRenderMode::Selection => {
                                is_whitespace
                                    && cell_overlaps_selection_for_row(
                                        row_abs,
                                        cell_start,
                                        cell_end,
                                        line_total_cells,
                                        selections,
                                    )
                            }
                            WhitespaceRenderMode::All => is_whitespace,
                        };

                        if selected {
                            let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                            let w_px = w_cells as f32 * config.cell_width_px;
                            let cy = y_top + config.line_height_px * 0.5;

                            if cell.ch == ' ' {
                                let cx = x_px + w_px * 0.5;
                                let r = (config.cell_width_px.min(config.line_height_px) * 0.10)
                                    .max(1.0);
                                canvas.draw_circle(Point::new(cx, cy), r, &dot_paint);
                            } else if cell.ch == '\t' {
                                let pad = (config.cell_width_px * 0.15).min(w_px * 0.25);
                                let x0 = x_px + pad;
                                let x1 = (x_px + w_px - pad).max(x0 + 1.0);
                                let head = (config.cell_width_px.min(config.line_height_px) * 0.20)
                                    .max(2.0);
                                let shaft_end = (x1 - head).max(x0);

                                canvas.draw_line(
                                    Point::new(x0, cy),
                                    Point::new(shaft_end, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(shaft_end, cy),
                                    Point::new(x1, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy - head * 0.6),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy + head * 0.6),
                                    &stroke_paint,
                                );
                            }
                        }

                        x_cells = x_cells.saturating_add(w_cells);
                    }
                }
            }

            #[derive(Debug)]
            enum PendingRunKind {
                LigatureText {
                    text: String,
                },
                Glyphs {
                    glyphs: Vec<GlyphId>,
                    positions: Vec<Point>,
                },
            }

            #[derive(Debug)]
            struct PendingRun {
                start_x_cells: u32,
                font_variant: FontVariant,
                font_index: usize,
                fg: Rgba8,
                kind: PendingRunKind,
            }

            let mut pending: Option<PendingRun> = None;
            let mut decoration_runs: Vec<LineDecorationRun> = Vec::new();
            let mut underline_run: Option<LineDecorationRun> = None;
            let mut strike_run: Option<LineDecorationRun> = None;

            let mut x_cells = line.segment_x_start_cells as u32;

            let flush = |renderer: &mut SkiaRenderer, pending: &mut Option<PendingRun>| {
                let Some(run) = pending.take() else {
                    return;
                };
                let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;

                let mut paint = Paint::default();
                paint.set_anti_alias(true);
                paint.set_color(rgba_to_skia_color(run.fg));

                let font = renderer.font_for_variant_index(run.font_variant, run.font_index);
                match run.kind {
                    PendingRunKind::LigatureText { text } => {
                        if text.is_empty() {
                            return;
                        }
                        renderer.draw_shaped_run(
                            canvas,
                            text.as_str(),
                            font,
                            x_px,
                            baseline_y,
                            config.cell_width_px,
                            &paint,
                            config.enable_ligatures,
                        );
                    }
                    PendingRunKind::Glyphs { glyphs, positions } => {
                        if glyphs.is_empty() || glyphs.len() != positions.len() {
                            return;
                        }
                        canvas.draw_glyphs_at(
                            glyphs.as_slice(),
                            positions.as_slice(),
                            Point::new(x_px, baseline_y),
                            font,
                            &paint,
                        );
                    }
                }
            };

            for cell in &line.cells {
                let (fg, _bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                let font_variant = resolve_cell_font_variant(cell.styles.as_slice(), theme);
                let decos = resolve_cell_line_decorations(cell.styles.as_slice(), theme, fg);

                if let Some((kind, color)) = decos.underline {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut underline_run,
                        kind,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut underline_run);
                }

                if let Some(color) = decos.strikethrough {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut strike_run,
                        LineDecorationKind::Strikethrough,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut strike_run);
                }

                let eligible_for_ligatures =
                    config.enable_ligatures && cell.width == 1 && cell.ch.is_ascii();
                if eligible_for_ligatures {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);

                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::LigatureText { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
                        pending = Some(PendingRun {
                            start_x_cells: x_cells,
                            font_variant,
                            font_index,
                            fg,
                            kind: PendingRunKind::LigatureText {
                                text: String::new(),
                            },
                        });
                    }

                    if let Some(r) = pending.as_mut() {
                        if let PendingRunKind::LigatureText { text } = &mut r.kind {
                            text.push(cell.ch);
                        }
                    }
                } else {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);
                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::Glyphs { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
                        pending = Some(PendingRun {
                            start_x_cells: x_cells,
                            font_variant,
                            font_index,
                            fg,
                            kind: PendingRunKind::Glyphs {
                                glyphs: Vec::new(),
                                positions: Vec::new(),
                            },
                        });
                    }

                    if let Some(r) = pending.as_mut() {
                        if let PendingRunKind::Glyphs { glyphs, positions } = &mut r.kind {
                            let font = self.font_for_variant_index(font_variant, font_index);
                            let glyph = font.unichar_to_glyph(cell.ch as u32 as i32);
                            let rel_x_px = (x_cells.saturating_sub(r.start_x_cells) as f32)
                                * config.cell_width_px;
                            glyphs.push(glyph);
                            positions.push(Point::new(rel_x_px, 0.0));
                        }
                    }
                }

                x_cells = x_cells.saturating_add(cell.width as u32);
            }

            flush(self, &mut pending);

            flush_decoration_run(&mut decoration_runs, &mut underline_run);
            flush_decoration_run(&mut decoration_runs, &mut strike_run);

            // Text decorations last (underline/strikethrough), so they stay visible over glyphs.
            let (_spacing, metrics) = { self.normal_primary_font().metrics() };
            for run in decoration_runs {
                draw_decoration_run(
                    canvas,
                    run,
                    text_origin_x,
                    y_top,
                    baseline_y,
                    metrics,
                    config,
                );
            }
        }

        // Carets on top.
        if config.show_caret {
            for caret in carets {
                draw_caret(canvas, grid, *caret, text_origin_x, config, theme.caret);
            }
        }

        Ok(())
    }

    /// Render a viewport `grid` into a Metal texture (macOS only).
    ///
    /// This is intended for native host UI toolkits that already own the presentation layer
    /// (e.g. `CAMetalLayer` / `MTKView`). The host provides:
    /// - a valid `MTLTexture*` (`metal_texture`)
    /// - dimensions that match `config.width_px/height_px`
    ///
    /// The renderer will:
    /// - wrap the texture as a Skia GPU render target
    /// - draw into it
    /// - flush and submit the work for the created surface
    pub fn render_rgba_into_metal_texture(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        metal_texture: *mut c_void,
    ) -> Result<(), RenderError> {
        #[cfg(target_os = "macos")]
        {
            if metal_texture.is_null() {
                return Err(RenderError::MetalTextureNull);
            }
            self.ensure_font_size(config.font_size);

            let mut surface = {
                let metal = self.metal.as_mut().ok_or(RenderError::MetalNotEnabled)?;

                // SAFETY: caller guarantees `metal_texture` is a valid `id<MTLTexture>`.
                let texture_info =
                    unsafe { gpu::mtl::TextureInfo::new(metal_texture as gpu::mtl::Handle) };
                let backend_rt = gpu::backend_render_targets::make_mtl(
                    (config.width_px as i32, config.height_px as i32),
                    &texture_info,
                );

                gpu::surfaces::wrap_backend_render_target(
                    &mut metal.context,
                    &backend_rt,
                    gpu::SurfaceOrigin::TopLeft,
                    // MTKView/CAMetalLayer defaults to BGRA8.
                    ColorType::BGRA8888,
                    None,
                    None,
                )
                .ok_or(RenderError::SurfaceCreateFailed)?
            };

            let canvas = surface.canvas();
            self.draw_headless_grid_to_canvas(
                canvas,
                grid,
                carets,
                selections,
                fold_markers,
                config,
                theme,
            )?;

            // Submit GPU work after drawing.
            //
            // Important:
            // - We flush this specific surface (not just the whole context) and mark it as
            //   "Present" access. This matches Skia's recommended pattern for swapchain-like
            //   targets (e.g. CAMetalDrawable textures).
            if let Some(metal) = self.metal.as_mut() {
                let info = gpu::FlushInfo::default();
                metal.context.flush_surface_with_access(
                    &mut surface,
                    surfaces::BackendSurfaceAccess::Present,
                    &info,
                );
                metal.context.submit(gpu::SyncCpu::No);
            }
            drop(surface);
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (
                grid,
                carets,
                selections,
                fold_markers,
                config,
                theme,
                metal_texture,
            );
            Err(RenderError::MetalUnsupported)
        }
    }

    fn draw_composed_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
    ) -> Result<(), RenderError> {
        canvas.clear(rgba_to_skia_color4f(theme.background));

        let gutter_x = config.padding_x_px;
        let gutter_w_px = config.gutter_width_cells as f32 * config.cell_width_px;
        let text_origin_x = gutter_x + gutter_w_px;

        if config.gutter_width_cells > 0 && gutter_w_px > 0.0 {
            let gutter_bg =
                resolve_style_background(GUTTER_BACKGROUND_STYLE_ID, theme, theme.background);
            let rect = Rect::from_xywh(gutter_x, 0.0, gutter_w_px, config.height_px as f32);
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(gutter_bg));
            canvas.draw_rect(rect, &paint);

            let sep = resolve_style_foreground(GUTTER_SEPARATOR_STYLE_ID, theme, theme.foreground);
            let sep_rect = Rect::from_xywh(text_origin_x, 0.0, 1.0, config.height_px as f32);
            let mut sep_paint = Paint::default();
            sep_paint.set_anti_alias(false);
            sep_paint.set_color(rgba_to_skia_color(sep));
            canvas.draw_rect(sep_rect, &sep_paint);
        }

        // Resolve caret positions in the composed grid (visible subset only).
        #[derive(Debug, Clone, Copy)]
        struct PendingCaret {
            local_row: usize,
            x_cells: u32,
        }
        let mut pending_carets: Vec<PendingCaret> = Vec::new();
        for &caret_offset in caret_offsets {
            let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
                continue;
            };
            let line = &grid.lines[local_row];
            let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
            pending_carets.push(PendingCaret { local_row, x_cells });
        }

        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let mut x_cells: u32 = 0;
            for cell in &line.cells {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                if bg != theme.background {
                    let w_px = cell.width as f32 * config.cell_width_px;
                    let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                    let mut bg_paint = Paint::default();
                    bg_paint.set_anti_alias(false);
                    bg_paint.set_color(rgba_to_skia_color(bg));
                    canvas.draw_rect(rect, &bg_paint);
                }
                x_cells = x_cells.saturating_add(cell.width as u32);
            }
        }

        // 2) Selection overlay (under text, over backgrounds).
        //
        // Note: selection highlight is applied only to document cells. Virtual text is not
        // considered part of the selection.
        let mut sel_ranges: Vec<(usize, usize)> = Vec::new();
        for (a, b) in selection_ranges {
            if *a == *b {
                continue;
            }
            if *a <= *b {
                sel_ranges.push((*a, *b));
            } else {
                sel_ranges.push((*b, *a));
            }
        }

        if !sel_ranges.is_empty() {
            for (row_idx, line) in grid.lines.iter().enumerate() {
                if !matches!(line.kind, ComposedLineKind::Document { .. }) {
                    continue;
                }
                let y_top = config.padding_y_px + row_idx as f32 * config.line_height_px
                    - config.scroll_y_px;
                let mut x_cells: u32 = 0;
                for cell in &line.cells {
                    let selected = match cell.source {
                        ComposedCellSource::Document { offset } => {
                            sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e)
                        }
                        _ => false,
                    };
                    if selected {
                        let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                        let w_px = cell.width as f32 * config.cell_width_px;
                        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                        let mut sel_paint = Paint::default();
                        sel_paint.set_anti_alias(false);
                        sel_paint.set_color(rgba_to_skia_color(theme.selection_background));
                        canvas.draw_rect(rect, &sel_paint);
                    }
                    x_cells = x_cells.saturating_add(cell.width as u32);
                }
            }
        }

        // 3) Text + underlines.
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            // Gutter: fold markers + line numbers for document lines (first visual segment only).
            if config.gutter_width_cells > 0 {
                if let ComposedLineKind::Document {
                    logical_line,
                    visual_in_logical,
                } = line.kind
                {
                    if visual_in_logical == 0 {
                        let marker_state =
                            fold_marker_state_for_line(logical_line as u32, fold_markers);
                        if let Some(is_collapsed) = marker_state {
                            let style_id = if is_collapsed {
                                FOLD_MARKER_COLLAPSED_STYLE_ID
                            } else {
                                FOLD_MARKER_EXPANDED_STYLE_ID
                            };
                            let rect = Rect::from_xywh(
                                gutter_x,
                                y_top,
                                config.cell_width_px,
                                config.line_height_px,
                            );
                            draw_fold_marker(
                                canvas,
                                rect,
                                is_collapsed,
                                config.fold_marker_style,
                                theme,
                                style_id,
                            );
                        }

                        // Line number text (best-effort; tests should not depend on glyph rasterization).
                        let gutter_fg = resolve_style_foreground(
                            GUTTER_FOREGROUND_STYLE_ID,
                            theme,
                            theme.foreground,
                        );
                        let mut paint = Paint::default();
                        paint.set_anti_alias(false);
                        paint.set_color(rgba_to_skia_color(gutter_fg));

                        let line_no = (logical_line + 1).to_string();
                        let x_px = gutter_x + config.cell_width_px; // leave first cell for fold marker
                        canvas.draw_str(
                            line_no,
                            Point::new(x_px, baseline_y),
                            self.normal_primary_font(),
                            &paint,
                        );
                    }
                }
            }

            // Indent guides + whitespace markers are drawn after selection but before text.
            if config.show_indent_guides || config.whitespace_render_mode != WhitespaceRenderMode::None {
                if config.show_indent_guides {
                    let mut indent_cells: u32 = 0;
                    for cell in &line.cells {
                        if cell.ch == ' ' || cell.ch == '\t' {
                            indent_cells = indent_cells.saturating_add(cell.width as u32);
                        } else {
                            break;
                        }
                    }

                    let tab_w = config.tab_width_cells.max(1);
                    let levels = indent_cells / tab_w;
                    if levels > 0 {
                        let guide_color = resolve_style_foreground_or_background(
                            INDENT_GUIDE_STYLE_ID,
                            theme,
                            default_indent_guide_color(theme),
                        );
                        let mut paint = Paint::default();
                        paint.set_anti_alias(false);
                        paint.set_color(rgba_to_skia_color(guide_color));

                        for level in 1..=levels {
                            // Place the guide on the boundary *between* indentation levels,
                            // i.e. right after a tabstop width.
                            let boundary_cells = level.saturating_mul(tab_w);
                            let x_px = (text_origin_x + boundary_cells as f32 * config.cell_width_px)
                                .round();
                            let rect = Rect::from_xywh(
                                x_px,
                                y_top,
                                1.0,
                                config.line_height_px,
                            );
                            canvas.draw_rect(rect, &paint);
                        }
                    }
                }

                let whitespace_mode = config.whitespace_render_mode;
                let draw_whitespace = match whitespace_mode {
                    WhitespaceRenderMode::None => false,
                    WhitespaceRenderMode::Selection => sel_ranges.is_empty() == false,
                    WhitespaceRenderMode::All => true,
                };
                if draw_whitespace {
                    let marker_color = resolve_style_foreground_or_background(
                        WHITESPACE_STYLE_ID,
                        theme,
                        default_whitespace_marker_color(theme),
                    );

                    let mut dot_paint = Paint::default();
                    dot_paint.set_anti_alias(true);
                    dot_paint.set_color(rgba_to_skia_color(marker_color));

                    let mut stroke_paint = Paint::default();
                    stroke_paint.set_anti_alias(true);
                    stroke_paint.set_color(rgba_to_skia_color(marker_color));
                    stroke_paint.set_style(skia_safe::paint::Style::Stroke);
                    stroke_paint.set_stroke_width(1.0);

                    let mut marker_x_cells: u32 = 0;
                    for cell in &line.cells {
                        let w_cells = cell.width as u32;
                        let selected = match cell.source {
                            ComposedCellSource::Document { offset } => {
                                let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
                                match whitespace_mode {
                                    WhitespaceRenderMode::None => false,
                                    WhitespaceRenderMode::Selection => {
                                        is_whitespace
                                            && sel_ranges
                                                .iter()
                                                .any(|(s, e)| offset >= *s && offset < *e)
                                    }
                                    WhitespaceRenderMode::All => is_whitespace,
                                }
                            }
                            _ => false,
                        };

                        if selected {
                            let x_px = text_origin_x + marker_x_cells as f32 * config.cell_width_px;
                            let w_px = w_cells as f32 * config.cell_width_px;
                            let cy = y_top + config.line_height_px * 0.5;

                            if cell.ch == ' ' {
                                let cx = x_px + w_px * 0.5;
                                let r = (config.cell_width_px.min(config.line_height_px) * 0.10)
                                    .max(1.0);
                                canvas.draw_circle(Point::new(cx, cy), r, &dot_paint);
                            } else if cell.ch == '\t' {
                                let pad = (config.cell_width_px * 0.15).min(w_px * 0.25);
                                let x0 = x_px + pad;
                                let x1 = (x_px + w_px - pad).max(x0 + 1.0);
                                let head = (config.cell_width_px.min(config.line_height_px) * 0.20)
                                    .max(2.0);
                                let shaft_end = (x1 - head).max(x0);

                                canvas.draw_line(
                                    Point::new(x0, cy),
                                    Point::new(shaft_end, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(shaft_end, cy),
                                    Point::new(x1, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy - head * 0.6),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy + head * 0.6),
                                    &stroke_paint,
                                );
                            }
                        }

                        marker_x_cells = marker_x_cells.saturating_add(w_cells);
                    }
                }
            }

            #[derive(Debug)]
            enum PendingRunKind {
                LigatureText {
                    text: String,
                },
                Glyphs {
                    glyphs: Vec<GlyphId>,
                    positions: Vec<Point>,
                },
            }

            #[derive(Debug)]
            struct PendingRun {
                start_x_cells: u32,
                font_variant: FontVariant,
                font_index: usize,
                fg: Rgba8,
                kind: PendingRunKind,
            }

            let mut pending: Option<PendingRun> = None;
            let mut decoration_runs: Vec<LineDecorationRun> = Vec::new();
            let mut underline_run: Option<LineDecorationRun> = None;
            let mut strike_run: Option<LineDecorationRun> = None;

            let mut x_cells: u32 = 0;

            let flush = |renderer: &mut SkiaRenderer, pending: &mut Option<PendingRun>| {
                let Some(run) = pending.take() else {
                    return;
                };
                let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;

                let mut paint = Paint::default();
                paint.set_anti_alias(true);
                paint.set_color(rgba_to_skia_color(run.fg));

                let font = renderer.font_for_variant_index(run.font_variant, run.font_index);
                match run.kind {
                    PendingRunKind::LigatureText { text } => {
                        if text.is_empty() {
                            return;
                        }
                        renderer.draw_shaped_run(
                            canvas,
                            text.as_str(),
                            font,
                            x_px,
                            baseline_y,
                            config.cell_width_px,
                            &paint,
                            config.enable_ligatures,
                        );
                    }
                    PendingRunKind::Glyphs { glyphs, positions } => {
                        if glyphs.is_empty() || glyphs.len() != positions.len() {
                            return;
                        }
                        canvas.draw_glyphs_at(
                            glyphs.as_slice(),
                            positions.as_slice(),
                            Point::new(x_px, baseline_y),
                            font,
                            &paint,
                        );
                    }
                }
            };

            for cell in &line.cells {
                let (fg, _bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                let font_variant = resolve_cell_font_variant(cell.styles.as_slice(), theme);
                let decos = resolve_cell_line_decorations(cell.styles.as_slice(), theme, fg);

                if let Some((kind, color)) = decos.underline {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut underline_run,
                        kind,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut underline_run);
                }

                if let Some(color) = decos.strikethrough {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut strike_run,
                        LineDecorationKind::Strikethrough,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut strike_run);
                }

                let eligible_for_ligatures =
                    config.enable_ligatures && cell.width == 1 && cell.ch.is_ascii();
                if eligible_for_ligatures {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);

                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::LigatureText { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
                        pending = Some(PendingRun {
                            start_x_cells: x_cells,
                            font_variant,
                            font_index,
                            fg,
                            kind: PendingRunKind::LigatureText {
                                text: String::new(),
                            },
                        });
                    }

                    if let Some(r) = pending.as_mut() {
                        if let PendingRunKind::LigatureText { text } = &mut r.kind {
                            text.push(cell.ch);
                        }
                    }
                } else {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);
                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::Glyphs { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
                        pending = Some(PendingRun {
                            start_x_cells: x_cells,
                            font_variant,
                            font_index,
                            fg,
                            kind: PendingRunKind::Glyphs {
                                glyphs: Vec::new(),
                                positions: Vec::new(),
                            },
                        });
                    }

                    if let Some(r) = pending.as_mut() {
                        if let PendingRunKind::Glyphs { glyphs, positions } = &mut r.kind {
                            let font = self.font_for_variant_index(font_variant, font_index);
                            let glyph = font.unichar_to_glyph(cell.ch as u32 as i32);
                            let rel_x_px = (x_cells.saturating_sub(r.start_x_cells) as f32)
                                * config.cell_width_px;
                            glyphs.push(glyph);
                            positions.push(Point::new(rel_x_px, 0.0));
                        }
                    }
                }

                x_cells = x_cells.saturating_add(cell.width as u32);
            }

            flush(self, &mut pending);

            flush_decoration_run(&mut decoration_runs, &mut underline_run);
            flush_decoration_run(&mut decoration_runs, &mut strike_run);

            // Text decorations last (underline/strikethrough), so they stay visible over glyphs.
            let (_spacing, metrics) = { self.normal_primary_font().metrics() };
            for run in decoration_runs {
                draw_decoration_run(
                    canvas,
                    run,
                    text_origin_x,
                    y_top,
                    baseline_y,
                    metrics,
                    config,
                );
            }
        }

        // Carets on top.
        if config.show_caret {
            let caret_width = config.caret_width_px.max(1.0);
            for caret in pending_carets {
                let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
                let y_top = config.padding_y_px + caret.local_row as f32 * config.line_height_px
                    - config.scroll_y_px;

                let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

                let mut paint = Paint::default();
                paint.set_anti_alias(false);
                paint.set_color(rgba_to_skia_color(theme.caret));
                canvas.draw_rect(rect, &paint);
            }
        }

        Ok(())
    }

    /// Render a composed viewport into a Metal texture (macOS only).
    ///
    /// See [`Self::render_rgba_into_metal_texture`] for the host-side expectations.
    pub fn render_composed_into_metal_texture(
        &mut self,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        metal_texture: *mut c_void,
    ) -> Result<(), RenderError> {
        #[cfg(target_os = "macos")]
        {
            if metal_texture.is_null() {
                return Err(RenderError::MetalTextureNull);
            }
            self.ensure_font_size(config.font_size);

            let mut surface = {
                let metal = self.metal.as_mut().ok_or(RenderError::MetalNotEnabled)?;

                // SAFETY: caller guarantees `metal_texture` is a valid `id<MTLTexture>`.
                let texture_info =
                    unsafe { gpu::mtl::TextureInfo::new(metal_texture as gpu::mtl::Handle) };
                let backend_rt = gpu::backend_render_targets::make_mtl(
                    (config.width_px as i32, config.height_px as i32),
                    &texture_info,
                );

                gpu::surfaces::wrap_backend_render_target(
                    &mut metal.context,
                    &backend_rt,
                    gpu::SurfaceOrigin::TopLeft,
                    ColorType::BGRA8888,
                    None,
                    None,
                )
                .ok_or(RenderError::SurfaceCreateFailed)?
            };

            let canvas = surface.canvas();
            self.draw_composed_grid_to_canvas(
                canvas,
                grid,
                caret_offsets,
                selection_ranges,
                fold_markers,
                config,
                theme,
            )?;

            if let Some(metal) = self.metal.as_mut() {
                let info = gpu::FlushInfo::default();
                metal.context.flush_surface_with_access(
                    &mut surface,
                    surfaces::BackendSurfaceAccess::Present,
                    &info,
                );
                metal.context.submit(gpu::SyncCpu::No);
            }
            drop(surface);
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (
                grid,
                caret_offsets,
                selection_ranges,
                fold_markers,
                config,
                theme,
                metal_texture,
            );
            Err(RenderError::MetalUnsupported)
        }
    }

    /// Render a decoration-aware composed viewport `grid` into a caller-provided RGBA8 buffer.
    ///
    /// Differences from [`Self::render_rgba_into`]:
    /// - Accepts carets and selections in **character offsets** (Unicode scalar indices), so the
    ///   renderer can position them correctly even when virtual text (inlay hints, fold
    ///   placeholders, wrap indent) is present.
    /// - Selection highlight is applied only to document cells (`ComposedCellSource::Document`);
    ///   virtual text is not considered part of the selection.
    pub fn render_composed_rgba_into(
        &mut self,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        out_rgba: &mut [u8],
    ) -> Result<(), RenderError> {
        let required = Self::required_rgba_len(config)?;
        if out_rgba.len() < required {
            return Err(RenderError::BufferTooSmall {
                required,
                provided: out_rgba.len(),
            });
        }

        self.ensure_font_size(config.font_size);

        let width = config.width_px as i32;
        let height = config.height_px as i32;

        let bytes_per_row = config.width_px as usize * 4;
        let pixels = &mut out_rgba[..required];

        let info = ImageInfo::new(
            (width, height),
            ColorType::RGBA8888,
            AlphaType::Premul,
            Some(ColorSpace::new_srgb()),
        );

        let mut surface = surfaces::wrap_pixels(&info, pixels, bytes_per_row, None)
            .ok_or(RenderError::SurfaceCreateFailed)?;

        let canvas = surface.canvas();
        canvas.clear(rgba_to_skia_color4f(theme.background));

        let gutter_x = config.padding_x_px;
        let gutter_w_px = config.gutter_width_cells as f32 * config.cell_width_px;
        let text_origin_x = gutter_x + gutter_w_px;

        if config.gutter_width_cells > 0 && gutter_w_px > 0.0 {
            let gutter_bg =
                resolve_style_background(GUTTER_BACKGROUND_STYLE_ID, theme, theme.background);
            let rect = Rect::from_xywh(gutter_x, 0.0, gutter_w_px, config.height_px as f32);
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(gutter_bg));
            canvas.draw_rect(rect, &paint);

            let sep = resolve_style_foreground(GUTTER_SEPARATOR_STYLE_ID, theme, theme.foreground);
            let sep_rect = Rect::from_xywh(text_origin_x, 0.0, 1.0, config.height_px as f32);
            let mut sep_paint = Paint::default();
            sep_paint.set_anti_alias(false);
            sep_paint.set_color(rgba_to_skia_color(sep));
            canvas.draw_rect(sep_rect, &sep_paint);
        }

        // Resolve caret positions in the composed grid (visible subset only).
        #[derive(Debug, Clone, Copy)]
        struct PendingCaret {
            local_row: usize,
            x_cells: u32,
        }
        let mut pending_carets: Vec<PendingCaret> = Vec::new();
        for &caret_offset in caret_offsets {
            let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
                continue;
            };
            let line = &grid.lines[local_row];
            let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
            pending_carets.push(PendingCaret { local_row, x_cells });
        }

        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let mut x_cells: u32 = 0;
            for cell in &line.cells {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                if bg != theme.background {
                    let w_px = cell.width as f32 * config.cell_width_px;
                    let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                    let mut bg_paint = Paint::default();
                    bg_paint.set_anti_alias(false);
                    bg_paint.set_color(rgba_to_skia_color(bg));
                    canvas.draw_rect(rect, &bg_paint);
                }
                x_cells = x_cells.saturating_add(cell.width as u32);
            }
        }

        // 2) Selection overlay (under text, over backgrounds).
        //
        // Note: selection highlight is applied only to document cells. Virtual text is not
        // considered part of the selection.
        let mut sel_ranges: Vec<(usize, usize)> = Vec::new();
        for (a, b) in selection_ranges {
            if *a == *b {
                continue;
            }
            if *a <= *b {
                sel_ranges.push((*a, *b));
            } else {
                sel_ranges.push((*b, *a));
            }
        }

        if !sel_ranges.is_empty() {
            for (row_idx, line) in grid.lines.iter().enumerate() {
                if !matches!(line.kind, ComposedLineKind::Document { .. }) {
                    continue;
                }
                let y_top = config.padding_y_px + row_idx as f32 * config.line_height_px
                    - config.scroll_y_px;
                let mut x_cells: u32 = 0;
                for cell in &line.cells {
                    let selected = match cell.source {
                        ComposedCellSource::Document { offset } => {
                            sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e)
                        }
                        _ => false,
                    };
                    if selected {
                        let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                        let w_px = cell.width as f32 * config.cell_width_px;
                        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                        let mut sel_paint = Paint::default();
                        sel_paint.set_anti_alias(false);
                        sel_paint.set_color(rgba_to_skia_color(theme.selection_background));
                        canvas.draw_rect(rect, &sel_paint);
                    }
                    x_cells = x_cells.saturating_add(cell.width as u32);
                }
            }
        }

        // 3) Text + underlines.
        for (row_idx, line) in grid.lines.iter().enumerate() {
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            // Gutter: fold markers + line numbers for document lines (first visual segment only).
            if config.gutter_width_cells > 0 {
                if let ComposedLineKind::Document {
                    logical_line,
                    visual_in_logical,
                } = line.kind
                {
                    if visual_in_logical == 0 {
                        let marker_state =
                            fold_marker_state_for_line(logical_line as u32, fold_markers);
                        if let Some(is_collapsed) = marker_state {
                            let style_id = if is_collapsed {
                                FOLD_MARKER_COLLAPSED_STYLE_ID
                            } else {
                                FOLD_MARKER_EXPANDED_STYLE_ID
                            };
                            let marker_color =
                                resolve_style_background(style_id, theme, theme.foreground);
                            let rect = Rect::from_xywh(
                                gutter_x,
                                y_top,
                                config.cell_width_px,
                                config.line_height_px,
                            );
                            let mut paint = Paint::default();
                            paint.set_anti_alias(false);
                            paint.set_color(rgba_to_skia_color(marker_color));
                            canvas.draw_rect(rect, &paint);
                        }

                        // Line number text (best-effort; tests should not depend on glyph rasterization).
                        let gutter_fg = resolve_style_foreground(
                            GUTTER_FOREGROUND_STYLE_ID,
                            theme,
                            theme.foreground,
                        );
                        let mut paint = Paint::default();
                        paint.set_anti_alias(false);
                        paint.set_color(rgba_to_skia_color(gutter_fg));

                        let line_no = (logical_line + 1).to_string();
                        let x_px = gutter_x + config.cell_width_px; // leave first cell for fold marker
                        canvas.draw_str(
                            line_no,
                            Point::new(x_px, baseline_y),
                            self.normal_primary_font(),
                            &paint,
                        );
                    }
                }
            }

            #[derive(Debug)]
            struct PendingRun {
                start_x_cells: u32,
                font_variant: FontVariant,
                font_index: usize,
                fg: Rgba8,
                text: String,
            }

            let mut pending: Option<PendingRun> = None;
            let mut decoration_runs: Vec<LineDecorationRun> = Vec::new();
            let mut underline_run: Option<LineDecorationRun> = None;
            let mut strike_run: Option<LineDecorationRun> = None;

            let mut x_cells: u32 = 0;

            let flush = |renderer: &mut SkiaRenderer, pending: &mut Option<PendingRun>| {
                let Some(run) = pending.take() else {
                    return;
                };
                if run.text.is_empty() {
                    return;
                }
                let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;

                let mut paint = Paint::default();
                paint.set_anti_alias(true);
                paint.set_color(rgba_to_skia_color(run.fg));

                let font = renderer.font_for_variant_index(run.font_variant, run.font_index);
                renderer.draw_shaped_run(
                    canvas,
                    run.text.as_str(),
                    font,
                    x_px,
                    baseline_y,
                    config.cell_width_px,
                    &paint,
                    config.enable_ligatures,
                );
            };

            for cell in &line.cells {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let (fg, _bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                let font_variant = resolve_cell_font_variant(cell.styles.as_slice(), theme);
                let decos = resolve_cell_line_decorations(cell.styles.as_slice(), theme, fg);

                if let Some((kind, color)) = decos.underline {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut underline_run,
                        kind,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut underline_run);
                }

                if let Some(color) = decos.strikethrough {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut strike_run,
                        LineDecorationKind::Strikethrough,
                        x_cells,
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut strike_run);
                }

                let eligible_for_ligatures =
                    config.enable_ligatures && cell.width == 1 && cell.ch.is_ascii();
                if eligible_for_ligatures {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);

                    let can_extend = pending
                        .as_ref()
                        .is_some_and(|r| r.font_variant == font_variant && r.font_index == font_index && r.fg == fg);
                    if !can_extend {
                        flush(self, &mut pending);
                        pending = Some(PendingRun {
                            start_x_cells: x_cells,
                            font_variant,
                            font_index,
                            fg,
                            text: String::new(),
                        });
                    }

                    if let Some(r) = pending.as_mut() {
                        r.text.push(cell.ch);
                    }
                } else {
                    flush(self, &mut pending);

                    let mut paint = Paint::default();
                    paint.set_anti_alias(true);
                    paint.set_color(rgba_to_skia_color(fg));
                    let font_index = self.font_index_for_char(cell.ch, font_variant);
                    let font = self.font_for_variant_index(font_variant, font_index);
                    canvas.draw_str(
                        cell.ch.to_string(),
                        Point::new(x_px, baseline_y),
                        font,
                        &paint,
                    );
                }

                x_cells = x_cells.saturating_add(cell.width as u32);
            }

            flush(self, &mut pending);

            flush_decoration_run(&mut decoration_runs, &mut underline_run);
            flush_decoration_run(&mut decoration_runs, &mut strike_run);

            // Text decorations last (underline/strikethrough), so they stay visible over glyphs.
            let (_spacing, metrics) = { self.normal_primary_font().metrics() };
            for run in decoration_runs {
                draw_decoration_run(
                    canvas,
                    run,
                    text_origin_x,
                    y_top,
                    baseline_y,
                    metrics,
                    config,
                );
            }
        }

        // Carets on top.
        if config.show_caret {
            let caret_width = config.caret_width_px.max(1.0);
            for caret in pending_carets {
                let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
                let y_top = config.padding_y_px + caret.local_row as f32 * config.line_height_px
                    - config.scroll_y_px;

                let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

                let mut paint = Paint::default();
                paint.set_anti_alias(false);
                paint.set_color(rgba_to_skia_color(theme.caret));
                canvas.draw_rect(rect, &paint);
            }
        }

        Ok(())
    }
}

fn composed_line_index_for_offset(grid: &ComposedGrid, char_offset: usize) -> Option<usize> {
    for (idx, line) in grid.lines.iter().enumerate() {
        if !matches!(line.kind, ComposedLineKind::Document { .. }) {
            continue;
        }

        let start = line.char_offset_start;
        let end = line.char_offset_end;

        if char_offset < start {
            // Monotonic by construction; safe early break.
            break;
        }
        if char_offset > end {
            continue;
        }
        if char_offset < end {
            return Some(idx);
        }
        // char_offset == end
        //
        // Prefer the next document line if it starts at the same offset (wrap boundary).
        if let Some(next) = grid.lines.get(idx + 1) {
            if matches!(next.kind, ComposedLineKind::Document { .. })
                && next.char_offset_start == char_offset
            {
                continue;
            }
        }
        return Some(idx);
    }
    None
}

fn indent_prefix_cell_count(line: &ComposedLine) -> usize {
    let mut count = 0usize;
    for cell in &line.cells {
        match cell.source {
            ComposedCellSource::Virtual { .. } => {
                if !cell.styles.is_empty() || !cell.ch.is_whitespace() {
                    break;
                }
                count = count.saturating_add(1);
            }
            ComposedCellSource::Document { .. } => break,
        }
    }
    count
}

fn caret_x_cells_in_composed_line(line: &ComposedLine, char_offset: usize) -> u32 {
    let indent_prefix = indent_prefix_cell_count(line);
    let mut x_cells: u32 = 0;
    for (idx, cell) in line.cells.iter().enumerate() {
        let anchor = match cell.source {
            ComposedCellSource::Document { offset } => offset,
            ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
        };

        if anchor < char_offset {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        if anchor > char_offset {
            break;
        }

        // anchor == char_offset
        //
        // Wrap-indent virtual spaces should appear *before* the caret at the segment start.
        let is_indent_prefix = idx < indent_prefix;
        if is_indent_prefix {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        break;
    }
    x_cells
}

fn normalize_font_family_name(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.len() >= 2 {
        let bytes = trimmed.as_bytes();
        let first = bytes[0] as char;
        let last = bytes[bytes.len() - 1] as char;
        if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
            return trimmed[1..trimmed.len() - 1].trim().to_string();
        }
    }
    trimmed.to_string()
}

fn default_font_families() -> Vec<&'static str> {
    // Keep the list fairly small and ordered by preference.
    //
    // For CJK + emoji correctness we include explicit fallbacks after the primary monospace.
    if cfg!(target_os = "macos") {
        vec![
            // Primary monospace candidates.
            "Menlo",
            "SF Mono",
            "Monaco",
            "Courier New",
            "Courier",
            // CJK fallbacks.
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            // Emoji fallback.
            "Apple Color Emoji",
        ]
    } else if cfg!(target_os = "windows") {
        vec![
            "Consolas",
            "Cascadia Mono",
            "Courier New",
            // CJK + emoji best-effort.
            "Microsoft YaHei",
            "Segoe UI Emoji",
            "Segoe UI Symbol",
        ]
    } else {
        vec![
            "DejaVu Sans Mono",
            "Noto Sans Mono",
            "Liberation Mono",
            "Monospace",
            // CJK + emoji best-effort.
            "Noto Sans CJK SC",
            "Noto Color Emoji",
            "Noto Emoji",
        ]
    }
}

fn make_configured_font(typeface: Option<skia_safe::Typeface>, size: f32) -> Font {
    let mut font = Font::default();
    if let Some(tf) = typeface {
        font.set_typeface(tf);
    }

    // Prefer grayscale AA: it produces consistent RGBA output and avoids LCD/subpixel quirks.
    font.set_subpixel(false);
    font.set_hinting(FontHinting::Normal);
    font.set_edging(skia_safe::font::Edging::AntiAlias);

    font.set_size(size);
    font
}

fn load_fonts_from_families_with_style(families: &[String], size: f32, style: FontStyle) -> Vec<Font> {
    let mgr = FontMgr::new();
    let mut out = Vec::<Font>::new();

    for raw in families {
        let name = normalize_font_family_name(raw.as_str());
        if name.is_empty() {
            continue;
        }
        if let Some(tf) = mgr.match_family_style(name.as_str(), style) {
            out.push(make_configured_font(Some(tf), size));
        }
    }

    if out.is_empty() {
        out.push(make_configured_font(
            pick_reasonable_monospace_typeface_with_style(style),
            size,
        ));
    }

    out
}

fn pick_reasonable_monospace_typeface_with_style(style: FontStyle) -> Option<skia_safe::Typeface> {
    let mgr = FontMgr::new();

    // Keep the list small; we just need *something* that exists on the platform.
    // If none match, fall back to the system default.
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["Menlo", "SF Mono", "Monaco", "Courier New", "Courier"]
    } else if cfg!(target_os = "windows") {
        &["Consolas", "Cascadia Mono", "Courier New"]
    } else {
        &[
            "DejaVu Sans Mono",
            "Noto Sans Mono",
            "Liberation Mono",
            "Monospace",
        ]
    };

    for name in candidates {
        if let Some(tf) = mgr.match_family_style(name, style) {
            return Some(tf);
        }
    }

    mgr.legacy_make_typeface(None, style)
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

fn make_shaper_feature(tag: FourByteTag, value: u32) -> Feature {
    Feature {
        tag: *tag,
        value,
        start: 0,
        end: usize::MAX,
    }
}

fn draw_caret(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    caret: VisualCaret,
    text_origin_x: f32,
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

    let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
    let y_top = config.padding_y_px + local_row as f32 * config.line_height_px - config.scroll_y_px;

    let caret_width = config.caret_width_px.max(1.0);
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
    text_origin_x: f32,
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

        let x_px = text_origin_x + start_x as f32 * config.cell_width_px;
        let w_px = (end_x - start_x) as f32 * config.cell_width_px;
        let y_top =
            config.padding_y_px + local_row as f32 * config.line_height_px - config.scroll_y_px;
        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
        canvas.draw_rect(rect, &paint);
    }
}

fn fold_marker_state_for_line(logical_line: u32, fold_markers: &[FoldMarker]) -> Option<bool> {
    fold_markers
        .iter()
        .find(|m| m.logical_line == logical_line)
        .map(|m| m.is_collapsed)
}

fn with_alpha(c: Rgba8, a: u8) -> Rgba8 {
    Rgba8::new(c.r, c.g, c.b, a)
}

fn resolve_style_foreground_or_background(style_id: u32, theme: &RenderTheme, fallback: Rgba8) -> Rgba8 {
    theme
        .styles
        .get(&style_id)
        .and_then(|c| c.foreground.or(c.background))
        .unwrap_or(fallback)
}

fn default_indent_guide_color(theme: &RenderTheme) -> Rgba8 {
    // VSCode-like subtle guide color (theme-controlled via `INDENT_GUIDE_STYLE_ID`).
    with_alpha(theme.foreground, 0x33)
}

fn default_whitespace_marker_color(theme: &RenderTheme) -> Rgba8 {
    // Visible enough over selection, but still subtle.
    with_alpha(theme.foreground, 0x88)
}

fn draw_fold_marker(
    canvas: &skia_safe::Canvas,
    rect: Rect,
    is_collapsed: bool,
    style: FoldMarkerStyle,
    theme: &RenderTheme,
    style_id: u32,
) {
    if matches!(style, FoldMarkerStyle::Hidden) {
        return;
    }

    let color = resolve_style_foreground_or_background(style_id, theme, theme.foreground);

    match style {
        FoldMarkerStyle::Hidden => {}
        FoldMarkerStyle::Block => {
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(color));
            canvas.draw_rect(rect, &paint);
        }
        FoldMarkerStyle::Triangle => {
            let cx = rect.left + rect.width() * 0.5;
            let cy = rect.top + rect.height() * 0.5;
            let size = rect.width().min(rect.height()) * 0.60;
            let half = size * 0.5;

            let mut pb = PathBuilder::new();
            if is_collapsed {
                // ▶
                pb.move_to(Point::new(cx - half * 0.75, cy - half));
                pb.line_to(Point::new(cx - half * 0.75, cy + half));
                pb.line_to(Point::new(cx + half * 0.85, cy));
            } else {
                // ▼
                pb.move_to(Point::new(cx - half, cy - half * 0.70));
                pb.line_to(Point::new(cx + half, cy - half * 0.70));
                pb.line_to(Point::new(cx, cy + half * 0.85));
            }
            pb.close();
            let path: Path = pb.into();

            let mut paint = Paint::default();
            paint.set_anti_alias(true);
            paint.set_color(rgba_to_skia_color(color));
            canvas.draw_path(&path, &paint);
        }
    }
}

fn cell_overlaps_selection_for_row(
    row: i64,
    cell_start_x: i64,
    cell_end_x: i64,
    line_total_cells: i64,
    selections: &[VisualSelection],
) -> bool {
    for sel in selections {
        let (mut a_row, mut a_x) = (sel.start_row as i64, sel.start_x_cells as i64);
        let (mut b_row, mut b_x) = (sel.end_row as i64, sel.end_x_cells as i64);
        if (b_row, b_x) < (a_row, a_x) {
            std::mem::swap(&mut a_row, &mut b_row);
            std::mem::swap(&mut a_x, &mut b_x);
        }

        if row < a_row || row > b_row {
            continue;
        }

        let start_x = if row == a_row { a_x } else { 0 };
        let end_x = if row == b_row { b_x } else { line_total_cells };
        if end_x <= start_x {
            continue;
        }

        // Overlap between [cell_start_x, cell_end_x) and [start_x, end_x)
        if cell_start_x < end_x && cell_end_x > start_x {
            return true;
        }
    }

    false
}

fn resolve_style_foreground(style_id: u32, theme: &RenderTheme, fallback: Rgba8) -> Rgba8 {
    theme
        .styles
        .get(&style_id)
        .and_then(|c| c.foreground)
        .unwrap_or(fallback)
}

fn resolve_style_background(style_id: u32, theme: &RenderTheme, fallback: Rgba8) -> Rgba8 {
    theme
        .styles
        .get(&style_id)
        .and_then(|c| c.background)
        .unwrap_or(fallback)
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

fn resolve_cell_font_variant(style_ids: &[u32], theme: &RenderTheme) -> FontVariant {
    let mut bold: bool = false;
    let mut italic: bool = false;
    for id in style_ids {
        let Some(spec) = theme.style_fonts.get(id) else {
            continue;
        };
        if let Some(v) = spec.bold {
            bold = v;
        }
        if let Some(v) = spec.italic {
            italic = v;
        }
    }
    FontVariant::from_flags(bold, italic)
}

fn is_lsp_diagnostics_style_id(style_id: u32) -> bool {
    // Matches `editor-core-lsp` encoding: 0x0400_0100 | severity(1..=4).
    const BASE: u32 = 0x0400_0100;
    if (style_id & 0xFFFF_FF00) != BASE {
        return false;
    }
    let sev = style_id & 0xFF;
    (1..=4).contains(&sev)
}

fn resolve_underline_color(style_id: u32, theme: &RenderTheme, fallback: Rgba8) -> Rgba8 {
    // Prefer explicit foreground; fall back to background; then to theme foreground.
    if let Some(colors) = theme.styles.get(&style_id) {
        if let Some(fg) = colors.foreground {
            return fg;
        }
        if let Some(bg) = colors.background {
            return bg;
        }
    }
    fallback
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LineDecorationKind {
    UnderlineSingle,
    UnderlineDouble,
    UnderlineSquiggly,
    Strikethrough,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct LineDecorationRun {
    kind: LineDecorationKind,
    start_x_cells: u32,
    width_cells: u32,
    color: Rgba8,
}

fn flush_decoration_run(out: &mut Vec<LineDecorationRun>, run: &mut Option<LineDecorationRun>) {
    if let Some(r) = run.take() {
        if r.width_cells > 0 {
            out.push(r);
        }
    }
}

fn extend_decoration_run(
    out: &mut Vec<LineDecorationRun>,
    run: &mut Option<LineDecorationRun>,
    kind: LineDecorationKind,
    x_cells: u32,
    width_cells: u32,
    color: Rgba8,
) {
    if width_cells == 0 {
        return;
    }

    if let Some(r) = run.as_mut() {
        let is_contiguous = r.start_x_cells.saturating_add(r.width_cells) == x_cells;
        if is_contiguous && r.kind == kind && r.color == color {
            r.width_cells = r.width_cells.saturating_add(width_cells);
            return;
        }
        flush_decoration_run(out, run);
    }

    *run = Some(LineDecorationRun {
        kind,
        start_x_cells: x_cells,
        width_cells,
        color,
    });
}

#[derive(Debug, Clone, Copy, Default)]
struct ResolvedCellLineDecorations {
    /// Underline-like decoration (single/double/squiggly) and its resolved color.
    underline: Option<(LineDecorationKind, Rgba8)>,
    /// Strikethrough color (if enabled).
    strikethrough: Option<Rgba8>,
}

fn resolve_cell_line_decorations(
    style_ids: &[u32],
    theme: &RenderTheme,
    resolved_cell_fg: Rgba8,
) -> ResolvedCellLineDecorations {
    let diag_id = style_ids
        .iter()
        .copied()
        .find(|&id| is_lsp_diagnostics_style_id(id));

    // Underline candidate resolution:
    // - diagnostics > IME > document links > theme-defined underline on arbitrary style ids
    // - within the same priority bucket, later style ids win (to match color layering semantics)
    let mut best_underline: Option<(i32, usize, LineDecorationKind, Rgba8)> = None;

    let consider = |best: &mut Option<(i32, usize, LineDecorationKind, Rgba8)>,
                    priority: i32,
                    tie: usize,
                    kind: LineDecorationKind,
                    color: Rgba8| {
        let replace = match best {
            None => true,
            Some((p, t, _, _)) => priority > *p || (priority == *p && tie >= *t),
        };
        if replace {
            *best = Some((priority, tie, kind, color));
        }
    };

    if let Some(diag_id) = diag_id {
        let spec = theme
            .text_decorations
            .get(&diag_id)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec
            .underline_color
            .unwrap_or_else(|| resolve_underline_color(diag_id, theme, resolved_cell_fg));
        consider(&mut best_underline, 400, usize::MAX, kind, color);
    }

    if style_ids.iter().any(|&id| id == IME_MARKED_TEXT_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&IME_MARKED_TEXT_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 300, usize::MAX, kind, color);
    }

    if style_ids.iter().any(|&id| id == DOCUMENT_LINK_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&DOCUMENT_LINK_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or_else(|| {
            resolve_underline_color(DOCUMENT_LINK_STYLE_ID, theme, resolved_cell_fg)
        });
        consider(&mut best_underline, 200, usize::MAX, kind, color);
    }

    for (idx, &id) in style_ids.iter().enumerate() {
        if id == IME_MARKED_TEXT_STYLE_ID || id == DOCUMENT_LINK_STYLE_ID || diag_id == Some(id) {
            continue;
        }
        let Some(spec) = theme.text_decorations.get(&id).copied() else {
            continue;
        };
        let Some(underline_style) = spec.underline else {
            continue;
        };
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 100, idx, kind, color);
    }

    let underline = best_underline.map(|(_p, _t, kind, color)| (kind, color));

    // Strikethrough: "last wins" by style-id order (independent of underline priority).
    let mut strike_enabled: bool = false;
    let mut strike_color: Option<Rgba8> = None;
    for &id in style_ids {
        let Some(spec) = theme.text_decorations.get(&id).copied() else {
            continue;
        };
        if let Some(v) = spec.strikethrough {
            strike_enabled = v;
        }
        if let Some(c) = spec.strikethrough_color {
            strike_color = Some(c);
        }
    }

    ResolvedCellLineDecorations {
        underline,
        strikethrough: strike_enabled.then(|| strike_color.unwrap_or(resolved_cell_fg)),
    }
}

fn decoration_thickness_px(config: RenderConfig) -> f32 {
    config.scale.clamp(1.0, 2.0)
}

fn draw_decoration_run(
    canvas: &skia_safe::Canvas,
    run: LineDecorationRun,
    text_origin_x: f32,
    y_top: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
) {
    let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;
    let w_px = run.width_cells as f32 * config.cell_width_px;
    if w_px <= 0.0 {
        return;
    }

    match run.kind {
        LineDecorationKind::UnderlineSingle => {
            draw_single_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineDouble => {
            draw_double_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineSquiggly => {
            draw_squiggly_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::Strikethrough => {
            draw_strikethrough(
                canvas, x_px, y_top, w_px, baseline_y, metrics, config, run.color,
            );
        }
    }
}

fn draw_single_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y = (y_top + config.line_height_px - h).max(y_top);
    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

fn draw_double_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y1 = (y_top + config.line_height_px - h).max(y_top);
    let y2 = (y1 - h * 2.0).max(y_top);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let rect1 = Rect::from_xywh(x_px, y1, w_px, h);
    canvas.draw_rect(rect1, &paint);

    let rect2 = Rect::from_xywh(x_px, y2, w_px, h);
    canvas.draw_rect(rect2, &paint);
}

fn draw_squiggly_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    // Deterministic, non-antialiased "zig-zag" made of small rectangles.
    //
    // This avoids diagonal AA differences across backends while still looking squiggly at typical
    // editor sizes.
    let h = decoration_thickness_px(config);
    let y_bottom = (y_top + config.line_height_px - h).max(y_top);
    let y_upper = (y_bottom - h).max(y_top);
    let seg_w = (h * 2.0).max(2.0);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let mut x = x_px;
    let x_end = x_px + w_px;
    let mut upper = false;
    while x < x_end {
        let w = (x_end - x).min(seg_w);
        let y = if upper { y_upper } else { y_bottom };
        let rect = Rect::from_xywh(x, y, w, h);
        canvas.draw_rect(rect, &paint);
        upper = !upper;
        x += seg_w;
    }
}

fn draw_strikethrough(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
    color: Rgba8,
) {
    // Keep strikethrough thickness consistent with underline thickness for crisp, deterministic
    // rendering across fonts/backends.
    let h = decoration_thickness_px(config);

    let strike_pos = metrics.strikeout_position().unwrap_or_else(|| {
        // `x_height` is a positive distance from baseline up; convert to y-down.
        if metrics.x_height.is_finite() && metrics.x_height > 0.0 {
            -metrics.x_height * 0.5
        } else if metrics.ascent.is_finite() {
            metrics.ascent * 0.3
        } else {
            -config.line_height_px * 0.3
        }
    });

    let center_y = baseline_y + strike_pos;
    let mut y = center_y - h * 0.5;
    let max_y = (y_top + config.line_height_px - h).max(y_top);
    if !y.is_finite() {
        y = y_top + config.line_height_px * 0.5;
    }
    y = y.clamp(y_top, max_y).round().clamp(y_top, max_y);

    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::snapshot::{
        Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
        HeadlessGrid, HeadlessLine,
    };
    use skia_safe::TextBlobIter;
    use skia_safe::shaper::TextBlobBuilderRunHandler;

    #[test]
    fn normalize_font_family_name_strips_quotes() {
        assert_eq!(normalize_font_family_name("Menlo"), "Menlo");
        assert_eq!(normalize_font_family_name(" \"Menlo\" "), "Menlo");
        assert_eq!(normalize_font_family_name("'Menlo'"), "Menlo");
    }

    #[test]
    fn set_font_families_unknown_still_renders_via_fallback() {
        let mut renderer = SkiaRenderer::new();
        renderer.set_font_families(vec!["ThisFontShouldNotExist-xyz".to_string()]);

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('a', 1));
        grid.add_line(line);

        let cfg = RenderConfig {
            width_px: 40,
            height_px: 40,
            scale: 1.0,
            font_size: 20.0,
            line_height_px: 40.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let _ = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &RenderTheme::default())
            .unwrap();
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn font_fallback_picks_second_family_for_cjk_when_first_missing() {
        let mgr = FontMgr::new();
        let style = FontStyle::normal();

        if mgr.match_family_style("Menlo", style).is_none()
            || mgr.match_family_style("PingFang SC", style).is_none()
        {
            // Some minimal macOS environments might not ship all fonts.
            return;
        }

        let mut renderer = SkiaRenderer::new();
        renderer.set_font_families(vec!["Menlo".to_string(), "PingFang SC".to_string()]);
        assert!(renderer.fonts_normal.fonts.len() >= 2);

        // Menlo should not have glyph for '你', so the renderer must fall back to PingFang.
        assert_eq!(renderer.font_index_for_char('你', FontVariant::Normal), 1);
    }

    #[test]
    fn render_draws_some_text_pixels() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('M', 1));
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: Rgba8::new(250, 250, 250, 255),
            // Make selection/caret invisible so only text can affect pixels.
            selection_background: bg,
            caret: bg,
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 40,
            height_px: 40,
            scale: 1.0,
            font_size: 20.0,
            line_height_px: 40.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();

        let bg_px = [bg.r, bg.g, bg.b, bg.a];
        assert!(
            rgba.chunks_exact(4).any(|p| p != bg_px),
            "expected at least one non-background pixel from glyph rendering"
        );
    }

    #[test]
    fn metal_enable_rejects_null_handles() {
        let mut renderer = SkiaRenderer::new();
        let result = renderer.enable_metal(std::ptr::null_mut(), std::ptr::null_mut());

        if cfg!(target_os = "macos") {
            assert!(matches!(result, Err(RenderError::MetalInvalidHandle)));
        } else {
            assert!(matches!(result, Err(RenderError::MetalUnsupported)));
        }
    }

    #[test]
    fn render_draws_ime_marked_underline_even_for_space() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        cell.styles.push(IME_MARKED_TEXT_STYLE_ID);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let fg = Rgba8::new(250, 250, 250, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: fg,
            selection_background: bg,
            caret: bg,
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let bytes_per_row = cfg.width_px as usize * 4;
        let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
        assert_eq!(&rgba[idx..idx + 4], &[fg.r, fg.g, fg.b, fg.a]);
    }

    #[test]
    fn render_draws_lsp_diagnostics_underline_even_for_space() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        // LSP diagnostics style id encoding: 0x0400_0100 | severity.
        cell.styles.push(0x0400_0100 | 1);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let diag = Rgba8::new(1, 200, 2, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: bg,
            caret: bg,
            styles: {
                let mut m = BTreeMap::new();
                m.insert(0x0400_0100 | 1, StyleColors::new(Some(diag), None));
                m
            },
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let bytes_per_row = cfg.width_px as usize * 4;
        let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
        assert_eq!(&rgba[idx..idx + 4], &[diag.r, diag.g, diag.b, diag.a]);
    }

    #[test]
    fn render_draws_document_link_underline_even_for_space() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        cell.styles.push(DOCUMENT_LINK_STYLE_ID);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let link = Rgba8::new(1, 200, 2, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: bg,
            caret: bg,
            styles: {
                let mut m = BTreeMap::new();
                m.insert(DOCUMENT_LINK_STYLE_ID, StyleColors::new(Some(link), None));
                m
            },
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let bytes_per_row = cfg.width_px as usize * 4;
        let idx = 9 * bytes_per_row + 5 * 4; // y=9 (underline), x=5
        assert_eq!(&rgba[idx..idx + 4], &[link.r, link.g, link.b, link.a]);
    }

    #[test]
    fn render_draws_double_underline_from_theme_text_decorations() {
        let mut renderer = SkiaRenderer::new();

        let style_id = 42u32;

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        cell.styles.push(style_id);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let deco = Rgba8::new(1, 200, 2, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: bg, // keep glyphs invisible (space anyway)
            selection_background: bg,
            caret: bg,
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: {
                let mut m = BTreeMap::new();
                m.insert(
                    style_id,
                    TextDecorations {
                        underline: Some(UnderlineStyle::Double),
                        underline_color: Some(deco),
                        ..TextDecorations::default()
                    },
                );
                m
            },
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let bytes_per_row = cfg.width_px as usize * 4;

        let idx_bottom = 9 * bytes_per_row + 5 * 4; // y=9 (bottom underline), x=5
        assert_eq!(
            &rgba[idx_bottom..idx_bottom + 4],
            &[deco.r, deco.g, deco.b, deco.a]
        );

        let idx_top = 7 * bytes_per_row + 5 * 4; // y=7 (second underline), x=5
        assert_eq!(
            &rgba[idx_top..idx_top + 4],
            &[deco.r, deco.g, deco.b, deco.a]
        );
    }

    #[test]
    fn render_draws_squiggly_underline_from_theme_text_decorations() {
        let mut renderer = SkiaRenderer::new();

        let style_id = 42u32;

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        cell.styles.push(style_id);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let deco = Rgba8::new(1, 200, 2, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: bg,
            selection_background: bg,
            caret: bg,
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: {
                let mut m = BTreeMap::new();
                m.insert(
                    style_id,
                    TextDecorations {
                        underline: Some(UnderlineStyle::Squiggly),
                        underline_color: Some(deco),
                        ..TextDecorations::default()
                    },
                );
                m
            },
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let bytes_per_row = cfg.width_px as usize * 4;

        // Squiggle alternates between y=9 and y=8 with a 2px segment width (scale=1).
        let idx_bottom = 9 * bytes_per_row + 1 * 4; // x=1 inside first bottom segment
        assert_eq!(
            &rgba[idx_bottom..idx_bottom + 4],
            &[deco.r, deco.g, deco.b, deco.a]
        );

        let idx_upper = 8 * bytes_per_row + 3 * 4; // x=3 inside the second (upper) segment
        assert_eq!(
            &rgba[idx_upper..idx_upper + 4],
            &[deco.r, deco.g, deco.b, deco.a]
        );
    }

    #[test]
    fn render_draws_strikethrough_from_theme_text_decorations() {
        let mut renderer = SkiaRenderer::new();

        let style_id = 42u32;

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        let mut cell = Cell::new(' ', 1);
        cell.styles.push(style_id);
        line.add_cell(cell);
        grid.add_line(line);

        let bg = Rgba8::new(10, 20, 30, 255);
        let deco = Rgba8::new(1, 200, 2, 255);
        let theme = RenderTheme {
            background: bg,
            foreground: bg,
            selection_background: bg,
            caret: bg,
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: {
                let mut m = BTreeMap::new();
                m.insert(
                    style_id,
                    TextDecorations {
                        strikethrough: Some(true),
                        strikethrough_color: Some(deco),
                        ..TextDecorations::default()
                    },
                );
                m
            },
        };

        let cfg = RenderConfig {
            width_px: 20,
            height_px: 10,
            scale: 1.0,
            font_size: 10.0,
            line_height_px: 10.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();
        let deco_px = [deco.r, deco.g, deco.b, deco.a];
        assert!(
            rgba.chunks_exact(4).any(|p| p == deco_px),
            "expected at least one strikethrough pixel"
        );
    }

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
        // Use spaces so text glyph rasterization does not affect selection/caret pixel assertions.
        line.add_cell(Cell::new(' ', 1));
        line.add_cell(Cell::new(' ', 1));
        line.add_cell(Cell::new(' ', 1));
        grid.add_line(line);

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 80,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
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
                &[],
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
        // Use a space so glyph rasterization does not affect the background override pixel sample.
        line.add_cell(Cell::new('a', 1));
        line.add_cell(Cell::with_styles(' ', 1, vec![42]));
        line.add_cell(Cell::new('c', 1));
        grid.add_line(line);

        let mut theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
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
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &theme)
            .unwrap();

        // Cell 'b' is at x in [10..20], pick center pixel.
        assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn render_selection_overrides_style_background() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        // Use a styled space so glyph rasterization does not affect the background pixel sample.
        line.add_cell(Cell::new('a', 1));
        line.add_cell(Cell::with_styles(' ', 1, vec![42]));
        line.add_cell(Cell::new('c', 1));
        grid.add_line(line);

        let mut theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(10, 20, 30, 255), // invisible
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
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
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let rgba = renderer
            .render_rgba(
                &grid,
                &[],
                &[VisualSelection {
                    start_row: 0,
                    start_x_cells: 1,
                    end_row: 0,
                    end_x_cells: 2,
                }],
                &[],
                cfg,
                &theme,
            )
            .unwrap();

        // The styled cell would normally be green-ish, but selection must win.
        assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [200, 0, 0, 255]);
    }

    #[test]
    fn render_composed_selection_overrides_style_background() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = ComposedGrid::new(0, 1);
        grid.lines.push(ComposedLine {
            kind: ComposedLineKind::Document {
                logical_line: 0,
                visual_in_logical: 0,
            },
            char_offset_start: 0,
            char_offset_end: 3,
            cells: vec![
                ComposedCell {
                    ch: 'a',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Document { offset: 0 },
                },
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: vec![42],
                    source: ComposedCellSource::Document { offset: 1 },
                },
                ComposedCell {
                    ch: 'c',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Document { offset: 2 },
                },
            ],
        });

        let mut theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(10, 20, 30, 255), // invisible
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
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
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
        renderer
            .render_composed_rgba_into(&grid, &[], &[(1, 2)], &[], cfg, &theme, &mut out)
            .unwrap();

        // Selected styled cell: x in [10..20], pick center pixel.
        assert_eq!(pixel(&out, cfg.width_px, 15, 10), [200, 0, 0, 255]);
    }

    #[test]
    fn render_composed_selection_ignores_virtual_cells() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = ComposedGrid::new(0, 1);
        grid.lines.push(ComposedLine {
            kind: ComposedLineKind::Document {
                logical_line: 0,
                visual_in_logical: 0,
            },
            char_offset_start: 0,
            char_offset_end: 1,
            cells: vec![
                // Virtual cell at offset 0 (e.g. inlay hint) - should NOT be selected.
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Virtual { anchor_offset: 0 },
                },
                // Document cell at offset 0 - should be selected for range 0..1.
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Document { offset: 0 },
                },
            ],
        });

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(10, 20, 30, 255), // invisible
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 40,
            height_px: 20,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
        renderer
            .render_composed_rgba_into(
                &grid,
                &[],
                &[(0, 1)], // select the single document char
                &[],
                cfg,
                &theme,
                out.as_mut_slice(),
            )
            .unwrap();

        // Virtual cell area (x in [0..20]) stays background.
        assert_eq!(pixel(&out, cfg.width_px, 10, 10), [10, 20, 30, 255]);

        // Document cell area (x in [20..40]) is selection color.
        assert_eq!(pixel(&out, cfg.width_px, 30, 10), [200, 0, 0, 255]);
    }

    #[test]
    fn render_composed_caret_skips_wrap_indent_prefix() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = ComposedGrid::new(0, 1);
        grid.lines.push(ComposedLine {
            kind: ComposedLineKind::Document {
                logical_line: 0,
                visual_in_logical: 1, // wrapped segment
            },
            char_offset_start: 0,
            char_offset_end: 1,
            cells: vec![
                // Wrap indent (virtual, whitespace, no styles) - should be before caret.
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Virtual { anchor_offset: 0 },
                },
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Virtual { anchor_offset: 0 },
                },
                // First document char at offset 0.
                ComposedCell {
                    ch: ' ',
                    width: 1,
                    styles: Vec::new(),
                    source: ComposedCellSource::Document { offset: 0 },
                },
            ],
        });

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(10, 20, 30, 255), // invisible
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 60,
            height_px: 20,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let mut out = vec![0u8; (cfg.width_px * cfg.height_px * 4) as usize];
        renderer
            .render_composed_rgba_into(
                &grid,
                &[0], // caret at the segment start
                &[],
                &[],
                cfg,
                &theme,
                out.as_mut_slice(),
            )
            .unwrap();

        // Caret should be at x=40 (2 indent cells * 20px), y=10.
        assert_eq!(pixel(&out, cfg.width_px, 40, 10), [0, 0, 200, 255]);
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
        // Use spaces so glyph rasterization does not affect selection/caret pixel assertions.
        for ch in [' ', ' ', ' ', ' ', ' '] {
            line.add_cell(Cell::new(ch, 1));
        }
        grid.add_line(line);

        let theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };

        let cfg = RenderConfig {
            width_px: 120,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
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
            .render_rgba(&grid, &carets, &selections, &[], cfg, &theme)
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

    #[test]
    fn render_draws_gutter_and_fold_marker_and_offsets_text_overlays() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        // Use spaces so glyph rasterization does not affect selection/caret pixel assertions.
        for ch in [' ', ' ', ' '] {
            line.add_cell(Cell::new(ch, 1));
        }
        grid.add_line(line);

        let mut theme = RenderTheme {
            background: Rgba8::new(10, 20, 30, 255),
            foreground: Rgba8::new(250, 250, 250, 255),
            selection_background: Rgba8::new(200, 0, 0, 255),
            caret: Rgba8::new(0, 0, 200, 255),
            styles: BTreeMap::new(),
            style_fonts: BTreeMap::new(),
            text_decorations: BTreeMap::new(),
        };
        theme.styles.insert(
            GUTTER_BACKGROUND_STYLE_ID,
            StyleColors::new(None, Some(Rgba8::new(1, 2, 3, 255))),
        );
        // Hide line number glyphs by matching the gutter background color.
        theme.styles.insert(
            GUTTER_FOREGROUND_STYLE_ID,
            StyleColors::new(Some(Rgba8::new(1, 2, 3, 255)), None),
        );
        theme.styles.insert(
            FOLD_MARKER_EXPANDED_STYLE_ID,
            StyleColors::new(None, Some(Rgba8::new(9, 9, 9, 255))),
        );

        let cfg = RenderConfig {
            width_px: 80,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 2,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let carets = [VisualCaret { row: 0, x_cells: 2 }];
        let selections = [VisualSelection {
            start_row: 0,
            start_x_cells: 0,
            end_row: 0,
            end_x_cells: 1,
        }];
        let fold_markers = [FoldMarker {
            logical_line: 0,
            is_collapsed: false,
        }];

        let rgba = renderer
            .render_rgba(&grid, &carets, &selections, &fold_markers, cfg, &theme)
            .unwrap();

        // Fold marker fills first cell of the gutter (x in [0..10]).
        assert_eq!(pixel(&rgba, cfg.width_px, 5, 10), [9, 9, 9, 255]);
        // Gutter background fills remaining gutter area (x in [10..20]).
        assert_eq!(pixel(&rgba, cfg.width_px, 15, 10), [1, 2, 3, 255]);

        // Selection should be offset by the gutter (text starts at x=20).
        assert_eq!(pixel(&rgba, cfg.width_px, 25, 10), [200, 0, 0, 255]);

        // Caret at x_cells=2 => x = 20 + 2*10 = 40.
        assert_eq!(pixel(&rgba, cfg.width_px, 40, 10), [0, 0, 200, 255]);
    }

    #[test]
    fn render_rgba_into_rejects_too_small_output_buffer() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('a', 1));
        grid.add_line(line);

        let cfg = RenderConfig {
            width_px: 80,
            height_px: 40,
            scale: 1.0,
            font_size: 12.0,
            line_height_px: 20.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: false,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let required = SkiaRenderer::required_rgba_len(cfg).unwrap();
        let mut out = vec![0u8; required.saturating_sub(1)];
        let err = renderer
            .render_rgba_into(
                &grid,
                &[],
                &[],
                &[],
                cfg,
                &RenderTheme::default(),
                out.as_mut_slice(),
            )
            .unwrap_err();
        assert!(matches!(err, RenderError::BufferTooSmall { .. }));
    }

    fn shape_glyph_count(
        shaper: &Shaper,
        text: &str,
        font: &Font,
        enable_ligatures: bool,
    ) -> usize {
        let features = SkiaRenderer::ligature_features(enable_ligatures);
        let width = 1_000_000.0;
        let utf8_len = text.as_bytes().len();

        let mut font_it = Shaper::new_trivial_font_run_iterator(font, utf8_len);
        let mut bidi_it = skia_safe::shapers::primitive::trivial_bidi_run_iterator(0, utf8_len);
        let mut script_it = skia_safe::shapers::primitive::trivial_script_run_iterator(0, utf8_len);
        let mut lang_it = Shaper::new_trivial_language_run_iterator("en", utf8_len);

        let mut builder = TextBlobBuilderRunHandler::new(text, Point::new(0.0, 0.0));
        shaper.shape_with_iterators_and_features(
            text,
            &mut font_it,
            &mut bidi_it,
            &mut script_it,
            &mut lang_it,
            features.as_ref(),
            width,
            &mut builder,
        );

        let Some(blob) = builder.make_blob() else {
            return 0;
        };

        TextBlobIter::new(&blob)
            .map(|run| run.glyph_indices.len())
            .sum()
    }

    #[test]
    fn ligature_shaping_can_reduce_glyph_count_for_fi_in_some_system_font() {
        let mgr = FontMgr::new();
        let style = FontStyle::normal();

        // On macOS, at least one of these should exist and support `fi` ligatures.
        // We keep the list short to avoid enumerating all families.
        let candidates: &[&str] = if cfg!(target_os = "macos") {
            &["Times New Roman", "Times", "Georgia", "Helvetica", "Arial"]
        } else if cfg!(target_os = "windows") {
            &["Times New Roman", "Georgia", "Arial"]
        } else {
            &["DejaVu Serif", "Liberation Serif", "Noto Serif"]
        };

        let shaper = Shaper::new(None);
        let mut found = false;
        for name in candidates {
            let Some(tf) = mgr.match_family_style(name, style) else {
                continue;
            };

            let font = make_configured_font(Some(tf), 32.0);
            let off = shape_glyph_count(&shaper, "fi", &font, false);
            let on = shape_glyph_count(&shaper, "fi", &font, true);

            if off > 0 && on > 0 && on < off {
                found = true;
                break;
            }
        }

        if cfg!(target_os = "macos") {
            // On macOS we expect at least one of the common serif fonts to exist and expose `fi`.
            assert!(
                found,
                "expected a system font where `fi` forms a ligature when enabled"
            );
        } else if !found {
            // Some minimal environments may not ship serif fonts with classic ligatures.
            // Keep this as a soft assertion so CI can still run headless.
            eprintln!(
                "no candidate font produced a detectable 'fi' ligature; skipping hard assertion"
            );
        }
    }

    #[test]
    fn render_with_ligatures_enabled_smoke() {
        let mut renderer = SkiaRenderer::new();

        let mut grid = HeadlessGrid::new(0, 1);
        let mut line = HeadlessLine::new(0, false);
        for ch in "a->b != c".chars() {
            line.add_cell(Cell::new(ch, 1));
        }
        grid.add_line(line);

        let cfg = RenderConfig {
            width_px: 200,
            height_px: 40,
            scale: 1.0,
            font_size: 20.0,
            line_height_px: 40.0,
            text_vertical_align: TextVerticalAlign::Center,
            cell_width_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            scroll_y_px: 0.0,
            gutter_width_cells: 0,
            enable_ligatures: true,
            caret_width_px: 2.0,
            show_caret: true,
            ..RenderConfig::default()
        };

        let _ = renderer
            .render_rgba(&grid, &[], &[], &[], cfg, &RenderTheme::default())
            .unwrap();
    }
}
