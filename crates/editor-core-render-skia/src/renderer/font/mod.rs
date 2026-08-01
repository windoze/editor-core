mod cache;
mod set;
mod shaping;

use super::font_loading::*;
use super::*;

pub(super) use cache::ShapedRunCache;
pub(super) use set::FontSet;
pub(crate) use set::FontVariant;

/// A renderer instance (Skia backend in later steps).
///
/// For MVP0 we keep this as a placeholder; implementation will be added
/// incrementally with deterministic tests.
impl Default for SkiaRenderer {
    fn default() -> Self {
        Self::new()
    }
}

impl SkiaRenderer {
    pub fn new() -> Self {
        let font_size = RenderConfig::default().font_size;
        let families: Vec<String> = default_font_families()
            .into_iter()
            .map(|s| s.to_string())
            .collect();
        let fonts_normal = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::normal(),
        ));
        let fonts_bold = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::bold(),
        ));
        let fonts_italic = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::italic(),
        ));
        let fonts_bold_italic = FontSet::new(load_fonts_from_families_with_style(
            families.as_slice(),
            font_size,
            FontStyle::bold_italic(),
        ));
        Self {
            fonts_normal,
            fonts_bold,
            fonts_italic,
            fonts_bold_italic,
            font_families: families,
            font_size,
            shaper: Shaper::new(None),
            shaped_run_cache: ShapedRunCache::new(4096),
            #[cfg(target_os = "macos")]
            metal: None,
        }
    }

    pub(super) fn baseline_offset_px(&self, config: RenderConfig) -> f32 {
        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );

        let (_spacing, metrics) = { self.fonts_normal.fonts[0].metrics() };
        let ascent = metrics.ascent;
        let descent = metrics.descent;

        let line_h = config.line_height_px.max(1.0);
        let mut baseline_offset = match config.text_vertical_align {
            TextVerticalAlign::Top => -ascent,
            TextVerticalAlign::Center => (line_h - (descent - ascent)) * 0.5 - ascent,
            TextVerticalAlign::Bottom => line_h - descent,
        };
        if !baseline_offset.is_finite() {
            baseline_offset = line_h * 0.8;
        }
        baseline_offset.clamp(0.0, line_h)
    }

    /// Configure the font fallback chain (first match wins).
    ///
    /// Notes:
    /// - This keeps the renderer "monospace-grid" layout model: glyph shaping/advance does not affect
    ///   cell metrics; only glyph rasterization uses fallbacks.
    /// - If no provided family can be loaded, we fall back to a reasonable monospace default.
    pub fn set_font_families(&mut self, families: Vec<String>) {
        let normalized: Vec<String> = families
            .into_iter()
            .map(|s| normalize_font_family_name(s.as_str()))
            .filter(|s| !s.is_empty())
            .collect();

        let families_to_load: Vec<String> = if normalized.is_empty() {
            default_font_families()
                .into_iter()
                .map(|s| s.to_string())
                .collect()
        } else {
            normalized.clone()
        };

        self.font_families = normalized;
        self.fonts_normal = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::normal(),
        ));
        self.fonts_bold = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::bold(),
        ));
        self.fonts_italic = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::italic(),
        ));
        self.fonts_bold_italic = FontSet::new(load_fonts_from_families_with_style(
            families_to_load.as_slice(),
            self.font_size,
            FontStyle::bold_italic(),
        ));

        // Typeface chain changed; cached shaping results are no longer reliable.
        self.shaped_run_cache.clear();
    }

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

    pub(super) fn font_for_variant_index(&self, variant: FontVariant, idx: usize) -> &Font {
        self.font_set(variant).font_for_index(idx)
    }

    pub(super) fn normal_primary_font(&self) -> &Font {
        self.fonts_normal.font_for_index(0)
    }

    pub(super) fn ensure_font_size(&mut self, size: f32) {
        if (self.font_size - size).abs() <= f32::EPSILON {
            return;
        }
        self.font_size = size;
        self.fonts_normal.ensure_size(size);
        self.fonts_bold.ensure_size(size);
        self.fonts_italic.ensure_size(size);
        self.fonts_bold_italic.ensure_size(size);

        // Font size affects shaping; drop cached results.
        self.shaped_run_cache.clear();
    }
}
