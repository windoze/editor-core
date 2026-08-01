use super::super::*;

impl SkiaRenderer {
    /// Render a viewport `grid` into a Metal texture (macOS only).
    ///
    /// This is intended for native host UI toolkits that already own the presentation layer
    /// (e.g. `CAMetalLayer` / `MTKView`). The host provides:
    /// - a valid `MTLTexture*` (`metal_texture`)
    /// - dimensions that match `config.width_px/height_px`
    ///
    /// The renderer will:
    /// - wrap the texture as a Skia GPU render target
    /// - draw into it
    /// - flush and submit the work for the created surface
    #[allow(clippy::too_many_arguments)]
    pub fn render_rgba_into_metal_texture(
        &mut self,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
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
                    // MTKView/CAMetalLayer defaults to BGRA8.
                    ColorType::BGRA8888,
                    None,
                    None,
                )
                .ok_or(RenderError::SurfaceCreateFailed)?
            };

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
            )?;

            // Submit GPU work after drawing.
            //
            // Important:
            // - We flush this specific surface (not just the whole context) and mark it as
            //   "Present" access. This matches Skia's recommended pattern for swapchain-like
            //   targets (e.g. CAMetalDrawable textures).
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
                carets,
                selections,
                fold_markers,
                config,
                theme,
                metal_texture,
            );
            Err(RenderError::MetalUnsupported)
        }
    }
}
