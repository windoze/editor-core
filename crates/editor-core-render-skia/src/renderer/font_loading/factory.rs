use super::fallback::pick_reasonable_monospace_typeface_with_style;
use super::normalize_font_family_name;
use super::*;

pub(crate) fn make_configured_font(typeface: Option<skia_safe::Typeface>, size: f32) -> Font {
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

pub(in crate::renderer) fn load_fonts_from_families_with_style(
    families: &[String],
    size: f32,
    style: FontStyle,
) -> Vec<Font> {
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
