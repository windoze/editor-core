use super::*;

impl SkiaRenderer {
    /// Enable Skia GPU rendering via Metal (macOS only).
    ///
    /// The host is responsible for providing valid, long-lived Metal objects:
    /// - `device`: `id<MTLDevice>`
    /// - `command_queue`: `id<MTLCommandQueue>`
    ///
    /// Safety note:
    /// - We only store the raw handles inside Skia's Metal backend context.
    /// - The caller must ensure the Objective-C objects outlive this `SkiaRenderer`
    ///   (or call `disable_metal()` before releasing them).
    pub fn enable_metal(
        &mut self,
        device: *mut c_void,
        command_queue: *mut c_void,
    ) -> Result<(), RenderError> {
        #[cfg(target_os = "macos")]
        {
            if device.is_null() || command_queue.is_null() {
                return Err(RenderError::MetalInvalidHandle);
            }

            // SAFETY:
            // - The caller guarantees `device` and `command_queue` are valid Metal objects and
            //   outlive the created backend context.
            let backend = unsafe {
                gpu::mtl::BackendContext::new(
                    device as gpu::mtl::Handle,
                    command_queue as gpu::mtl::Handle,
                )
            };

            let context = gpu::direct_contexts::make_metal(&backend, None)
                .ok_or(RenderError::MetalContextCreateFailed)?;

            self.metal = Some(SkiaMetalState {
                _backend_context: backend,
                context,
            });
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (device, command_queue);
            Err(RenderError::MetalUnsupported)
        }
    }

    /// Disable the Metal backend (if enabled), reverting to CPU raster output.
    pub fn disable_metal(&mut self) {
        #[cfg(target_os = "macos")]
        {
            self.metal = None;
        }
    }

    pub fn is_metal_enabled(&self) -> bool {
        #[cfg(target_os = "macos")]
        {
            self.metal.is_some()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }
}
