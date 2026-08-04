use super::super::*;

impl SkiaRenderer {
    pub(in crate::renderer) fn baseline_offset_px(&self, config: RenderConfig) -> f32 {
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
}
