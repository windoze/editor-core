use super::*;

impl SkiaRenderer {
    /// Render only the specified (local) visual row ranges into an existing RGBA buffer.
    ///
    /// Notes:
    /// - This is intended for incremental/partial redraw: the caller must keep `out_rgba`
    ///   containing the *previous* frame and provide correct dirty ranges.
    /// - The renderer will clear and redraw only the pixels covered by the provided row ranges.
    /// - Smooth scrolling (`config.scroll_y_px`) and viewport shape changes should typically
    ///   fall back to a full redraw, because prior pixels are no longer valid.
    #[allow(clippy::too_many_arguments)]
    pub fn render_rgba_into_partial_rows(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        out_rgba: &mut [u8],
        dirty_row_ranges: &[(usize, usize)],
    ) -> Result<(), RenderError> {
        if dirty_row_ranges.is_empty() {
            return Ok(());
        }

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

        let total_rows = grid.count.max(grid.lines.len());
        for &(start, end) in dirty_row_ranges {
            let start = start.min(total_rows);
            let end = end.min(total_rows);
            if start >= end {
                continue;
            }

            let y_top =
                config.padding_y_px + start as f32 * config.line_height_px - config.scroll_y_px;
            let h_px = (end - start) as f32 * config.line_height_px;
            if !h_px.is_finite() || h_px <= 0.0 {
                continue;
            }

            let rect = Rect::from_xywh(0.0, y_top, config.width_px as f32, h_px);
            canvas.save();
            canvas.clip_rect(rect, skia_safe::ClipOp::Intersect, false);
            self.draw_headless_grid_to_canvas(
                canvas,
                grid,
                carets,
                selections,
                fold_markers,
                config,
                theme,
                Some((start, end)),
            )?;
            canvas.restore();
        }

        Ok(())
    }
}
