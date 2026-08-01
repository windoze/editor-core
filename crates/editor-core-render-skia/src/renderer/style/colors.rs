use super::super::*;
use super::semantic_token_base_style_id;

pub(in crate::renderer) fn resolve_style_foreground_or_background(
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

pub(in crate::renderer) fn resolve_style_foreground(
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

pub(in crate::renderer) fn resolve_style_background(
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

pub(in crate::renderer) fn resolve_cell_colors(
    style_ids: &[u32],
    theme: &RenderTheme,
) -> (Rgba8, Rgba8) {
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

pub(in crate::renderer) fn resolve_underline_color(
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
