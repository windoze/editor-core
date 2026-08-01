use super::*;

pub(crate) fn normalize_font_family_name(name: &str) -> String {
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

pub(super) fn default_font_families() -> Vec<&'static str> {
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

pub(super) fn load_fonts_from_families_with_style(
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

pub(super) fn pick_reasonable_monospace_typeface_with_style(
    style: FontStyle,
) -> Option<skia_safe::Typeface> {
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

pub(super) fn make_shaper_feature(tag: FourByteTag, value: u32) -> Feature {
    Feature {
        tag: *tag,
        value,
        start: 0,
        end: usize::MAX,
    }
}
