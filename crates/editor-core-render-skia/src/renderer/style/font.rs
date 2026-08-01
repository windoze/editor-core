use super::super::*;
use super::semantic_token_base_style_id;

pub(in crate::renderer) fn resolve_cell_font_variant(
    style_ids: &[u32],
    theme: &RenderTheme,
) -> FontVariant {
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
