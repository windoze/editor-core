use super::super::*;

pub(in crate::renderer) fn with_alpha(c: Rgba8, a: u8) -> Rgba8 {
    Rgba8::new(c.r, c.g, c.b, a)
}

pub(in crate::renderer) fn default_indent_guide_color(theme: &RenderTheme) -> Rgba8 {
    // VSCode-like subtle guide color (theme-controlled via `INDENT_GUIDE_STYLE_ID`).
    with_alpha(theme.foreground, 0x33)
}

pub(in crate::renderer) fn default_whitespace_marker_color(theme: &RenderTheme) -> Rgba8 {
    // Visible enough over selection, but still subtle.
    with_alpha(theme.foreground, 0x88)
}
