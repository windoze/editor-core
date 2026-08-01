use super::{FontSet, ShapedRunCache};
use skia_safe::Shaper;

#[cfg(target_os = "macos")]
use skia_safe::gpu;

#[cfg(target_os = "macos")]
#[derive(Debug)]
pub(super) struct SkiaMetalState {
    pub(super) _backend_context: gpu::mtl::BackendContext,
    pub(super) context: gpu::DirectContext,
}

#[derive(Debug)]
pub struct SkiaRenderer {
    pub(crate) fonts_normal: FontSet,
    pub(super) fonts_bold: FontSet,
    pub(super) fonts_italic: FontSet,
    pub(super) fonts_bold_italic: FontSet,
    pub(super) font_families: Vec<String>,
    pub(super) font_size: f32,
    pub(super) shaper: Shaper,
    pub(super) shaped_run_cache: ShapedRunCache,
    #[cfg(target_os = "macos")]
    pub(super) metal: Option<SkiaMetalState>,
}
