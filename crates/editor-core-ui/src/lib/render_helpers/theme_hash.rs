use super::*;

pub(crate) fn hash_render_theme(theme: &RenderTheme) -> u64 {
    pub(crate) fn hash_rgba8(hasher: &mut DefaultHasher, c: Rgba8) {
        c.r.hash(hasher);
        c.g.hash(hasher);
        c.b.hash(hasher);
        c.a.hash(hasher);
    }

    pub(crate) fn hash_opt_rgba8(hasher: &mut DefaultHasher, c: Option<Rgba8>) {
        match c {
            None => 0u8.hash(hasher),
            Some(v) => {
                1u8.hash(hasher);
                hash_rgba8(hasher, v);
            }
        }
    }

    pub(crate) fn hash_style_colors(hasher: &mut DefaultHasher, c: StyleColors) {
        hash_opt_rgba8(hasher, c.foreground);
        hash_opt_rgba8(hasher, c.background);
    }

    pub(crate) fn hash_style_font(hasher: &mut DefaultHasher, f: StyleFont) {
        f.bold.hash(hasher);
        f.italic.hash(hasher);
    }

    pub(crate) fn hash_text_decorations(hasher: &mut DefaultHasher, d: TextDecorations) {
        let underline_tag: u8 = match d.underline {
            None => 0,
            Some(UnderlineStyle::Single) => 1,
            Some(UnderlineStyle::Double) => 2,
            Some(UnderlineStyle::Squiggly) => 3,
        };
        underline_tag.hash(hasher);
        hash_opt_rgba8(hasher, d.underline_color);

        d.strikethrough.hash(hasher);
        hash_opt_rgba8(hasher, d.strikethrough_color);
    }

    let mut hasher = DefaultHasher::new();

    hash_rgba8(&mut hasher, theme.background);
    hash_rgba8(&mut hasher, theme.foreground);
    hash_rgba8(&mut hasher, theme.selection_background);
    hash_rgba8(&mut hasher, theme.caret);

    for (style_id, colors) in &theme.styles {
        style_id.hash(&mut hasher);
        hash_style_colors(&mut hasher, *colors);
    }
    for (style_id, font) in &theme.style_fonts {
        style_id.hash(&mut hasher);
        hash_style_font(&mut hasher, *font);
    }
    for (style_id, deco) in &theme.text_decorations {
        style_id.hash(&mut hasher);
        hash_text_decorations(&mut hasher, *deco);
    }

    hasher.finish()
}
