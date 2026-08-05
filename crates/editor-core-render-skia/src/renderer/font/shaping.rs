mod collect;

use super::super::SkiaRenderer;
use super::super::font_loading::make_shaper_feature;
use super::FontVariant;
use super::cache::{ShapedRun, ShapedRunKey};
use collect::CollectGlyphsRunHandler;
use skia_safe::shaper::Feature;
use skia_safe::{FourByteTag, Paint, Point, Shaper};

impl SkiaRenderer {
    pub(crate) fn ligature_features(enabled: bool) -> [Feature; 3] {
        let v = if enabled { 1 } else { 0 };
        [
            make_shaper_feature(FourByteTag::from_chars('l', 'i', 'g', 'a'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'a', 'l', 't'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'l', 'i', 'g'), v),
        ]
    }

    /// Resolve the shaper features for the font that will render a run.
    ///
    /// - Ligatures disabled: the default ligature features are explicitly turned off.
    /// - Enabled + the font's resolved family has an entry in `font_feature_map`: the parsed
    ///   feature list from the map is used as-is (the string is the full specification).
    /// - Enabled + no map entry: the default ligature features are turned on.
    pub(crate) fn shaping_features_for_font(
        &self,
        font: &skia_safe::Font,
        enable_ligatures: bool,
    ) -> Vec<Feature> {
        if !enable_ligatures {
            return Self::ligature_features(false).to_vec();
        }
        if !self.font_feature_map.is_empty() {
            let family = super::super::font_loading::normalize_font_family_name(
                font.typeface().family_name().as_str(),
            );
            if let Some(features) = self.font_feature_map.get(family.as_str()) {
                return features.clone();
            }
        }
        Self::ligature_features(true).to_vec()
    }

    #[allow(clippy::too_many_arguments)]
    pub(in crate::renderer) fn draw_shaped_run_cached(
        &mut self,
        canvas: &skia_safe::Canvas,
        run_text: &str,
        font_variant: FontVariant,
        font_index: usize,
        x_px: f32,
        baseline_y: f32,
        cell_width_px: f32,
        paint: &Paint,
        enable_ligatures: bool,
    ) {
        if run_text.is_empty() {
            return;
        }

        let key = ShapedRunKey {
            text: run_text.to_string(),
            font_variant,
            font_index,
            cell_width_bits: cell_width_px.to_bits(),
            enable_ligatures,
        };

        let font = self.font_for_variant_index(font_variant, font_index);

        if let Some(run) = self.shaped_run_cache.get(&key) {
            canvas.draw_glyphs_at(
                run.glyphs.as_slice(),
                run.positions.as_slice(),
                Point::new(x_px, baseline_y),
                font,
                paint,
            );
            return;
        }

        let width = 1_000_000.0;
        let features = self.shaping_features_for_font(font, enable_ligatures);
        let utf8_len = run_text.len();

        let mut font_it = Shaper::new_trivial_font_run_iterator(font, utf8_len);
        let mut bidi_it = skia_safe::shapers::primitive::trivial_bidi_run_iterator(0, utf8_len);
        let mut script_it = skia_safe::shapers::primitive::trivial_script_run_iterator(0, utf8_len);
        let mut lang_it = Shaper::new_trivial_language_run_iterator("en", utf8_len);

        let mut handler = CollectGlyphsRunHandler::default();
        self.shaper.shape_with_iterators_and_features(
            run_text,
            &mut font_it,
            &mut bidi_it,
            &mut script_it,
            &mut lang_it,
            features.as_slice(),
            width,
            &mut handler,
        );

        if handler.out_glyphs.is_empty() || handler.out_glyphs.len() != handler.out_clusters.len() {
            // Fallback: draw without shaping (no ligatures), but avoid dropping text.
            canvas.draw_str(run_text, Point::new(x_px, baseline_y), font, paint);
            return;
        }

        // The editor layout is a fixed cell grid; place shaped glyphs on cell boundaries so
        // kerning does not drift away from the grid while ligature glyphs still span cells.
        let mut positions = Vec::<Point>::with_capacity(handler.out_glyphs.len());
        for &cluster in &handler.out_clusters {
            let x_cells = cluster as f32; // ASCII => utf8 byte offset == char index == cell index
            positions.push(Point::new(x_cells * cell_width_px, 0.0));
        }

        canvas.draw_glyphs_at(
            handler.out_glyphs.as_slice(),
            positions.as_slice(),
            Point::new(x_px, baseline_y),
            font,
            paint,
        );

        self.shaped_run_cache.insert(
            key,
            ShapedRun {
                glyphs: handler.out_glyphs,
                positions,
            },
        );
    }
}
