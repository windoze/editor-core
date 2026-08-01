use super::super::*;
use super::*;
use skia_safe::Font;

impl SkiaRenderer {
    fn font_set(&self, variant: FontVariant) -> &FontSet {
        match variant {
            FontVariant::Normal => &self.fonts_normal,
            FontVariant::Bold => &self.fonts_bold,
            FontVariant::Italic => &self.fonts_italic,
            FontVariant::BoldItalic => &self.fonts_bold_italic,
        }
    }

    fn font_set_mut(&mut self, variant: FontVariant) -> &mut FontSet {
        match variant {
            FontVariant::Normal => &mut self.fonts_normal,
            FontVariant::Bold => &mut self.fonts_bold,
            FontVariant::Italic => &mut self.fonts_italic,
            FontVariant::BoldItalic => &mut self.fonts_bold_italic,
        }
    }

    pub(crate) fn font_index_for_char(&mut self, ch: char, variant: FontVariant) -> usize {
        self.font_set_mut(variant).font_index_for_char(ch)
    }

    pub(in crate::renderer) fn font_for_variant_index(
        &self,
        variant: FontVariant,
        idx: usize,
    ) -> &Font {
        self.font_set(variant).font_for_index(idx)
    }

    pub(in crate::renderer) fn normal_primary_font(&self) -> &Font {
        self.fonts_normal.font_for_index(0)
    }
}
