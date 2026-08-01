use super::super::*;

impl SkiaRenderer {
    /// Render a composed viewport into a Metal texture (macOS only).
    ///
    /// See [`Self::render_rgba_into_metal_texture`] for the host-side expectations.
    #[allow(clippy::too_many_arguments)]
    pub fn render_composed_into_metal_texture(
        &mut self,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        metal_texture: *mut c_void,
    ) -> Result<(), RenderError> {
        #[cfg(target_os = "macos")]
        {
            if metal_texture.is_null() {
                return Err(RenderError::MetalTextureNull);
            }
            self.ensure_font_size(config.font_size);

            let mut surface = {
                let metal = self.metal.as_mut().ok_or(RenderError::MetalNotEnabled)?;

                // SAFETY: caller guarantees `metal_texture` is a valid `id<MTLTexture>`.
                let texture_info =
                    unsafe { gpu::mtl::TextureInfo::new(metal_texture as gpu::mtl::Handle) };
                let backend_rt = gpu::backend_render_targets::make_mtl(
                    (config.width_px as i32, config.height_px as i32),
                    &texture_info,
                );

                gpu::surfaces::wrap_backend_render_target(
                    &mut metal.context,
                    &backend_rt,
                    gpu::SurfaceOrigin::TopLeft,
                    ColorType::BGRA8888,
                    None,
                    None,
                )
                .ok_or(RenderError::SurfaceCreateFailed)?
            };

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
            )?;

            if let Some(metal) = self.metal.as_mut() {
                let info = gpu::FlushInfo::default();
                metal.context.flush_surface_with_access(
                    &mut surface,
                    surfaces::BackendSurfaceAccess::Present,
                    &info,
                );
                metal.context.submit(gpu::SyncCpu::No);
            }
            drop(surface);
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (
                grid,
                caret_offsets,
                selection_ranges,
                fold_markers,
                config,
                theme,
                metal_texture,
            );
            Err(RenderError::MetalUnsupported)
        }
    }
}
