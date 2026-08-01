use super::*;

pub(super) fn with_alpha(c: Rgba8, a: u8) -> Rgba8 {
    Rgba8::new(c.r, c.g, c.b, a)
}

pub(super) fn resolve_style_foreground_or_background(
    style_id: u32,
    theme: &RenderTheme,
    fallback: Rgba8,
) -> Rgba8 {
    theme
        .styles
        .get(&style_id)
        .and_then(|c| c.foreground.or(c.background))
        .unwrap_or(fallback)
}

pub(super) fn default_indent_guide_color(theme: &RenderTheme) -> Rgba8 {
    // VSCode-like subtle guide color (theme-controlled via `INDENT_GUIDE_STYLE_ID`).
    with_alpha(theme.foreground, 0x33)
}

pub(super) fn default_whitespace_marker_color(theme: &RenderTheme) -> Rgba8 {
    // Visible enough over selection, but still subtle.
    with_alpha(theme.foreground, 0x88)
}

pub(super) fn resolve_style_foreground(
    style_id: u32,
    theme: &RenderTheme,
    fallback: Rgba8,
) -> Rgba8 {
    let semantic_base = semantic_token_base_style_id(style_id);
    theme
        .styles
        .get(&style_id)
        .or_else(|| semantic_base.and_then(|id| theme.styles.get(&id)))
        .and_then(|c| c.foreground)
        .unwrap_or(fallback)
}

pub(super) fn resolve_style_background(
    style_id: u32,
    theme: &RenderTheme,
    fallback: Rgba8,
) -> Rgba8 {
    let semantic_base = semantic_token_base_style_id(style_id);
    theme
        .styles
        .get(&style_id)
        .or_else(|| semantic_base.and_then(|id| theme.styles.get(&id)))
        .and_then(|c| c.background)
        .unwrap_or(fallback)
}

/// Semantic tokens encode modifiers in the low 16 bits of the style id.
///
/// Most themes want token modifiers (e.g. `declaration`, `definition`, `static`) to *inherit*
/// the base token type color unless explicitly overridden. This helper enables a cheap
/// "fallback to base token style" lookup when the exact `(token_type, modifiers)` style id
/// is not present in the theme.
#[inline]
pub(super) fn semantic_token_base_style_id(style_id: u32) -> Option<u32> {
    // All currently reserved/builtin style id ranges are >= 0x0300_0000.
    // The default LSP semantic encoding is: (token_type << 16) | (modifier_bits & 0xFFFF),
    // which lives in a low range (token_type is small).
    if style_id >= 0x0300_0000 {
        return None;
    }
    if (style_id & 0xFFFF) == 0 {
        return None;
    }
    Some(style_id & 0xFFFF_0000)
}

pub(super) fn resolve_cell_colors(style_ids: &[u32], theme: &RenderTheme) -> (Rgba8, Rgba8) {
    let mut fg = theme.foreground;
    let mut bg = theme.background;
    for id in style_ids {
        let colors = theme
            .styles
            .get(id)
            .or_else(|| semantic_token_base_style_id(*id).and_then(|base| theme.styles.get(&base)));
        if let Some(colors) = colors {
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

pub(super) fn resolve_cell_font_variant(style_ids: &[u32], theme: &RenderTheme) -> FontVariant {
    let mut bold: bool = false;
    let mut italic: bool = false;
    for id in style_ids {
        let spec = theme.style_fonts.get(id).or_else(|| {
            semantic_token_base_style_id(*id).and_then(|base| theme.style_fonts.get(&base))
        });
        let Some(spec) = spec else { continue };
        if let Some(v) = spec.bold {
            bold = v;
        }
        if let Some(v) = spec.italic {
            italic = v;
        }
    }
    FontVariant::from_flags(bold, italic)
}

pub(super) fn is_lsp_diagnostics_style_id(style_id: u32) -> bool {
    // Matches `editor-core-lsp` encoding: 0x0400_0100 | severity(1..=4).
    const BASE: u32 = 0x0400_0100;
    if (style_id & 0xFFFF_FF00) != BASE {
        return false;
    }
    let sev = style_id & 0xFF;
    (1..=4).contains(&sev)
}

pub(super) fn resolve_underline_color(
    style_id: u32,
    theme: &RenderTheme,
    fallback: Rgba8,
) -> Rgba8 {
    // Prefer explicit foreground; fall back to background; then to theme foreground.
    let semantic_base = semantic_token_base_style_id(style_id);
    if let Some(colors) = theme
        .styles
        .get(&style_id)
        .or_else(|| semantic_base.and_then(|id| theme.styles.get(&id)))
    {
        if let Some(fg) = colors.foreground {
            return fg;
        }
        if let Some(bg) = colors.background {
            return bg;
        }
    }
    fallback
}
