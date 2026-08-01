use super::font_loading::*;
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum FontVariant {
    Normal,
    Bold,
    Italic,
    BoldItalic,
}

impl FontVariant {
    pub(super) fn from_flags(bold: bool, italic: bool) -> Self {
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
    fn new(fonts: Vec<Font>) -> Self {
        Self {
            fonts,
            glyph_font_cache: HashMap::new(),
        }
    }

    fn ensure_size(&mut self, size: f32) {
        for f in &mut self.fonts {
            f.set_size(size);
        }
    }

    fn font_index_for_char(&mut self, ch: char) -> usize {
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

    fn font_for_index(&self, idx: usize) -> &Font {
        // Safety: index always comes from `fonts` indices or defaults to 0.
        &self.fonts[idx.min(self.fonts.len().saturating_sub(1))]
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ShapedRunKey {
    text: String,
    font_variant: FontVariant,
    font_index: usize,
    cell_width_bits: u32,
    enable_ligatures: bool,
}

#[derive(Debug, Clone)]
struct ShapedRun {
    glyphs: Vec<GlyphId>,
    positions: Vec<Point>,
}

#[derive(Debug)]
pub(super) struct ShapedRunCache {
    entries: HashMap<ShapedRunKey, ShapedRun>,
    order: VecDeque<ShapedRunKey>,
    capacity: usize,
}

impl ShapedRunCache {
    fn new(capacity: usize) -> Self {
        Self {
            entries: HashMap::new(),
            order: VecDeque::new(),
            capacity: capacity.max(1),
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.order.clear();
    }

    fn get(&self, key: &ShapedRunKey) -> Option<&ShapedRun> {
        self.entries.get(key)
    }

    fn insert(&mut self, key: ShapedRunKey, run: ShapedRun) {
        if self.capacity == 0 {
            return;
        }

        match self.entries.entry(key) {
            std::collections::hash_map::Entry::Occupied(mut e) => {
                // Keep insertion idempotent; do not grow `order` with duplicates.
                e.insert(run);
                return;
            }
            std::collections::hash_map::Entry::Vacant(e) => {
                let key = e.key().clone();
                e.insert(run);
                self.order.push_back(key);
            }
        }

        while self.order.len() > self.capacity {
            if let Some(old) = self.order.pop_front() {
                self.entries.remove(&old);
            }
        }
    }
}

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

    pub(crate) fn ligature_features(enabled: bool) -> [Feature; 3] {
        let v = if enabled { 1 } else { 0 };
        [
            make_shaper_feature(FourByteTag::from_chars('l', 'i', 'g', 'a'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'a', 'l', 't'), v),
            make_shaper_feature(FourByteTag::from_chars('c', 'l', 'i', 'g'), v),
        ]
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn draw_shaped_run_cached(
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

        // IMPORTANT:
        // We do *not* use the shaper-provided glyph positions here.
        // The editor's layout model is a fixed-width "cell grid", so we place glyphs on cell
        // boundaries to avoid kerning/positioning drifting away from the grid.
        //
        // Ligature fonts like Fira Code encode ligature glyphs whose advance spans multiple cells,
        // so drawing the ligature glyph at the cluster-start cell produces the expected effect.
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
