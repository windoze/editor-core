use editor_core_render_skia::Rgba8;

/// UI chrome colors (gutter, fold markers, etc.) rendered outside the document text grid.
///
/// This is a convenience wrapper that maps named UI elements to reserved `StyleId`s in
/// `editor-core-render-skia` (e.g. `GUTTER_BACKGROUND_STYLE_ID`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChromeTheme {
    pub gutter_background: Rgba8,
    pub gutter_foreground: Rgba8,
    pub gutter_separator: Rgba8,
    pub fold_marker_collapsed: Rgba8,
    pub fold_marker_expanded: Rgba8,
}

impl Default for ChromeTheme {
    fn default() -> Self {
        Self {
            gutter_background: Rgba8::new(0xF5, 0xF5, 0xF5, 0xFF),
            gutter_foreground: Rgba8::new(0x88, 0x88, 0x88, 0xFF),
            gutter_separator: Rgba8::new(0xDD, 0xDD, 0xDD, 0xFF),
            fold_marker_collapsed: Rgba8::new(0x77, 0x77, 0x77, 0xFF),
            fold_marker_expanded: Rgba8::new(0xAA, 0xAA, 0xAA, 0xFF),
        }
    }
}

/// Pixel-space damage rectangle for incremental/partial redraw.
///
/// The coordinate space matches the RGBA buffer produced by `render_rgba_*` APIs:
/// - origin `(0, 0)` is the **top-left** corner of the buffer
/// - units are **physical pixels**
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DamageRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}
