use skia_safe::Font;
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum FontVariant {
    Normal,
    Bold,
    Italic,
    BoldItalic,
}

impl FontVariant {
    pub(crate) fn from_flags(bold: bool, italic: bool) -> Self {
        match (bold, italic) {
            (false, false) => Self::Normal,
            (true, false) => Self::Bold,
            (false, true) => Self::Italic,
            (true, true) => Self::BoldItalic,
        }
    }
}

#[derive(Debug)]
pub(crate) struct FontSet {
    pub(crate) fonts: Vec<Font>,
    glyph_font_cache: HashMap<char, usize>,
}

impl FontSet {
    pub(super) fn new(fonts: Vec<Font>) -> Self {
        Self {
            fonts,
            glyph_font_cache: HashMap::new(),
        }
    }

    pub(super) fn ensure_size(&mut self, size: f32) {
        for f in &mut self.fonts {
            f.set_size(size);
        }
    }

    pub(super) fn font_index_for_char(&mut self, ch: char) -> usize {
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

    pub(super) fn font_for_index(&self, idx: usize) -> &Font {
        // Safety: index always comes from `fonts` indices or defaults to 0.
        &self.fonts[idx.min(self.fonts.len().saturating_sub(1))]
    }
}
