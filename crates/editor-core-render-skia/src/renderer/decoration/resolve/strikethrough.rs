use super::*;

pub(super) fn resolve_strikethrough_decoration(
    style_ids: &[u32],
    theme: &RenderTheme,
    resolved_cell_fg: Rgba8,
) -> Option<Rgba8> {
    // "last wins" by style-id order (independent of underline priority).
    let mut strike_enabled: bool = false;
    let mut strike_color: Option<Rgba8> = None;
    for &id in style_ids {
        let spec = theme.text_decorations.get(&id).copied().or_else(|| {
            semantic_token_base_style_id(id)
                .and_then(|base| theme.text_decorations.get(&base).copied())
        });
        let Some(spec) = spec else { continue };
        if let Some(v) = spec.strikethrough {
            strike_enabled = v;
        }
        if let Some(c) = spec.strikethrough_color {
            strike_color = Some(c);
        }
    }

    strike_enabled.then(|| strike_color.unwrap_or(resolved_cell_fg))
}
