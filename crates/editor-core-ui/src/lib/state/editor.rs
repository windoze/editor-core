use super::{
    EditorUiDoc, MarkedRange, MinimapCache, MouseDragState, RenderFrameCache, SearchQueryState,
};
use crate::prelude::*;

/// 单 buffer UI 句柄（每个实例对应一个 `Workspace` view）。
///
/// - 通过 [`Self::clone_view`] 可为同一文档创建额外 view（用于 split panes / 多视图）。
/// - 文本与派生状态（Sublime/Tree-sitter/LSP）在同一 buffer 内共享；光标/选择/滚动等是 view 级别。
pub struct EditorUi {
    pub(crate) doc: Arc<Mutex<EditorUiDoc>>,
    pub(crate) buffer_id: BufferId,
    pub(crate) view_id: ViewId,
    pub(crate) renderer: SkiaRenderer,
    pub(crate) theme: RenderTheme,
    pub(crate) render_config: RenderConfig,
    pub(crate) marked: Option<MarkedRange>,
    pub(crate) search_query: Option<SearchQueryState>,
    pub(crate) mouse_drag: Option<MouseDragState>,
    pub(crate) auto_pairs: AutoPairsConfig,
    pub(crate) bracket_match_highlights_enabled: bool,
    pub(crate) lsp_on_type_formatting_enabled: bool,
    pub(crate) render_cache: Option<RenderFrameCache>,
    pub(crate) minimap_cache: Option<MinimapCache>,
}
