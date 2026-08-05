use super::{FontSet, ShapedRunCache};
use skia_safe::Shaper;
use skia_safe::shaper::Feature;
use std::collections::HashMap;

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
    /// Per-family OpenType features applied while shaping when ligatures are enabled.
    ///
    /// Keys are normalized font family names matched against the resolved typeface of the
    /// font that actually renders a run (so fallback fonts are covered naturally). Families
    /// absent from the map use the default ligature features (`liga`, `calt`, `clig`).
    pub(super) font_feature_map: HashMap<String, Vec<Feature>>,
    pub(super) font_size: f32,
    pub(super) shaper: Shaper,
    pub(super) shaped_run_cache: ShapedRunCache,
    #[cfg(target_os = "macos")]
    pub(super) metal: Option<SkiaMetalState>,
}
