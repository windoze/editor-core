use super::*;

impl SkiaRenderer {
    /// Render a decoration-aware composed viewport `grid` into a caller-provided RGBA8 buffer.
    ///
    /// Differences from [`Self::render_rgba_into`]:
    /// - Accepts carets and selections in **character offsets** (Unicode scalar indices), so the
    ///   renderer can position them correctly even when virtual text (inlay hints, fold
    ///   placeholders, wrap indent) is present.
    /// - Selection highlight is applied only to document cells (`ComposedCellSource::Document`);
    ///   virtual text is not considered part of the selection.
    #[allow(clippy::too_many_arguments)]
    pub fn render_composed_rgba_into(
        &mut self,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        out_rgba: &mut [u8],
    ) -> Result<(), RenderError> {
        let required = Self::required_rgba_len(config)?;
        if out_rgba.len() < required {
            return Err(RenderError::BufferTooSmall {
                required,
                provided: out_rgba.len(),
            });
        }

        self.ensure_font_size(config.font_size);

        let width = config.width_px as i32;
        let height = config.height_px as i32;

        let bytes_per_row = config.width_px as usize * 4;
        let pixels = &mut out_rgba[..required];

        let info = ImageInfo::new(
            (width, height),
            ColorType::RGBA8888,
            AlphaType::Premul,
            Some(ColorSpace::new_srgb()),
        );

        let mut surface = surfaces::wrap_pixels(&info, pixels, bytes_per_row, None)
            .ok_or(RenderError::SurfaceCreateFailed)?;

        let canvas = surface.canvas();
        self.draw_composed_grid_to_canvas(
            canvas,
            grid,
            caret_offsets,
            selection_ranges,
            fold_markers,
            config,
            theme,
            None,
        )
    }
}
