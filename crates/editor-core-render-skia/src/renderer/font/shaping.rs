use super::super::SkiaRenderer;
use super::super::font_loading::make_shaper_feature;
use super::FontVariant;
use super::cache::{ShapedRun, ShapedRunKey};
use skia_safe::shaper::run_handler::{Buffer, RunInfo};
use skia_safe::shaper::{Feature, RunHandler};
use skia_safe::{FourByteTag, GlyphId, Paint, Point, Shaper};

impl SkiaRenderer {
    pub(crate) fn ligature_features(enabled: bool) -> [Feature; 3] {
        let v = if enabled { 1 } else { 0 };
        [
            make_shaper_feature(FourByteTag::from_chars('l', 'i', 'g', 'a'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'a', 'l', 't'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'l', 'i', 'g'), v),
        ]
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

        #[derive(Default)]
        struct CollectGlyphsRunHandler {
            glyphs: Vec<GlyphId>,
            positions: Vec<Point>,
            clusters: Vec<u32>,
            out_glyphs: Vec<GlyphId>,
            out_clusters: Vec<u32>,
        }

        impl RunHandler for CollectGlyphsRunHandler {
            fn begin_line(&mut self) {}
            fn run_info(&mut self, _info: &RunInfo) {}
            fn commit_run_info(&mut self) {}
            fn run_buffer(&mut self, info: &RunInfo) -> Buffer<'_> {
                let count = info.glyph_count;
                self.glyphs.resize(count, GlyphId::default());
                self.positions.resize(count, Point::default());
                self.clusters.resize(count, 0);
                Buffer {
                    glyphs: self.glyphs.as_mut_slice(),
                    positions: self.positions.as_mut_slice(),
                    offsets: None,
                    clusters: Some(self.clusters.as_mut_slice()),
                    point: Point::default(),
                }
            }
            fn commit_run_buffer(&mut self, _info: &RunInfo) {
                self.out_glyphs.extend_from_slice(&self.glyphs);
                self.out_clusters.extend_from_slice(&self.clusters);
            }
            fn commit_line(&mut self) {}
        }

        let width = 1_000_000.0;
        let features = Self::ligature_features(enable_ligatures);
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
