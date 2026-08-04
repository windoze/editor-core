use super::super::font_loading::*;
use super::super::*;
use super::*;

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

    pub(in crate::renderer) fn ensure_font_size(&mut self, size: f32) {
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
