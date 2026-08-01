use super::*;

impl SkiaRenderer {
    /// Render a viewport `grid` to an RGBA8 buffer (premultiplied).
    ///
    /// The returned buffer length is `width_px * height_px * 4`.
    pub fn render_rgba(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
    ) -> Result<Vec<u8>, RenderError> {
        let required = Self::required_rgba_len(config)?;

        let mut pixels = vec![0u8; required];
        self.render_rgba_into(
            grid,
            carets,
            selections,
            fold_markers,
            config,
            theme,
            pixels.as_mut_slice(),
        )?;
        Ok(pixels)
    }

    /// Render a viewport `grid` into a caller-provided RGBA8 buffer (premultiplied).
    ///
    /// Only the first `width_px * height_px * 4` bytes are written.
    #[allow(clippy::too_many_arguments)]
    pub fn render_rgba_into(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
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
        self.draw_headless_grid_to_canvas(
            canvas,
            grid,
            carets,
            selections,
            fold_markers,
            config,
            theme,
            None,
        )
    }
}
