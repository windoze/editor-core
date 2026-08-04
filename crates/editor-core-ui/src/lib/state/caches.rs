use crate::prelude::*;

#[derive(Debug, Clone)]
pub(crate) struct RenderFrameCache {
    pub(crate) view_version: u64,
    pub(crate) render_config: RenderConfig,
    pub(crate) theme_hash: u64,
    pub(crate) start_visual_row: usize,
    pub(crate) row_count: usize,
    pub(crate) has_virtual_text: bool,
    pub(crate) row_signatures: Vec<u64>,
}

#[derive(Debug, Clone)]
pub(crate) struct MinimapCache {
    pub(crate) view_version: u64,
    pub(crate) start_visual_row: usize,
    pub(crate) count: usize,
    pub(crate) json: String,
}
