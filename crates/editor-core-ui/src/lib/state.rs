use crate::prelude::*;
use crate::{
    LspClientRequest, LspResultSlot, SharedLspSession, TreeSitterAsyncWorker,
    TreeSitterCaptureMapper, TreeSitterProcessingConfig, UiError,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MarkedRange {
    pub(crate) start: usize,
    pub(crate) len: usize,
    /// Text that was replaced when the IME composition started.
    ///
    /// Needed to support "cancel composition" without losing the original selection.
    pub(crate) original_text: String,
    pub(crate) original_len: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SearchQueryState {
    pub(crate) query: String,
    pub(crate) options: SearchOptions,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MouseSelectionMode {
    Char,
    Word,
    Line,
    Paragraph,
    Rect,
}

#[derive(Debug, Clone)]
pub(crate) struct MouseDragState {
    pub(crate) mode: MouseSelectionMode,
    pub(crate) anchor_pos: Position,
    pub(crate) anchor_offset: usize,
    /// For unit-based selections (word), store the initial selected unit range.
    pub(crate) anchor_unit_range: Option<(usize, usize)>,
}

pub(crate) struct EditorUiDoc {
    pub(crate) ws: Workspace,
    pub(crate) buffer_id: BufferId,
    pub(crate) sublime: Option<SublimeProcessor>,
    pub(crate) treesitter: Option<TreeSitterAsyncWorker>,
    pub(crate) treesitter_indenter: Option<TreeSitterIndenter>,
    pub(crate) treesitter_capture_mapper: TreeSitterCaptureMapper,
    pub(crate) treesitter_processing_config: TreeSitterProcessingConfig,
    pub(crate) treesitter_registry: TreeSitterRegistry,
    pub(crate) treesitter_doc_version: u64,
    pub(crate) lsp: Option<Arc<SharedLspSession>>,
    pub(crate) lsp_document_uri: Option<String>,
    pub(crate) lsp_last_cmd: Option<String>,
    pub(crate) lsp_last_error: Option<String>,
    pub(crate) lsp_delta_calc: Option<DeltaCalculator>,
    pub(crate) lsp_aux_refresh_due: Option<Instant>,
    pub(crate) lsp_inlay_in_flight: bool,
    pub(crate) lsp_code_lens_in_flight: bool,
    pub(crate) lsp_document_links_in_flight: bool,
    pub(crate) lsp_client_requests: HashMap<u64, LspClientRequest>,
    pub(crate) lsp_latest_result_request_id: HashMap<(ViewId, LspResultSlot), u64>,
    pub(crate) lsp_latest_on_type_formatting_request_id: HashMap<ViewId, u64>,
    pub(crate) lsp_last_result_json: HashMap<(ViewId, LspResultSlot), String>,
    pub(crate) text_version: u64,
}

impl EditorUiDoc {
    pub(crate) fn exec_core(
        &mut self,
        view_id: ViewId,
        command: Command,
    ) -> Result<CommandResult, UiError> {
        self.ws.execute(view_id, command).map_err(|e| match e {
            editor_core::WorkspaceError::CommandFailed { message, .. } => {
                UiError::Processor(message)
            }
            editor_core::WorkspaceError::ApplyEditsFailed { message, .. } => {
                UiError::Processor(message)
            }
            other => UiError::Processor(format!("{other:?}")),
        })
    }

    pub(crate) fn apply_processing_edits<I>(&mut self, edits: I) -> Result<(), UiError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        self.ws
            .apply_processing_edits(self.buffer_id, edits)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    pub(crate) fn apply_lsp_processing_edits<I>(&mut self, edits: I) -> Result<bool, UiError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        let edits = edits.into_iter().collect::<Vec<_>>();
        if edits.is_empty() {
            return Ok(false);
        }

        if let Err(err) = self.apply_processing_edits(edits) {
            let reason = format!("failed to apply LSP processing edits: {err}");
            self.lsp_fail(reason.clone());
            return Err(UiError::Processor(reason));
        }

        Ok(true)
    }

    pub(crate) fn lsp_is_enabled(&self) -> bool {
        let Some(shared) = self.lsp.as_ref() else {
            return false;
        };
        let Ok(guard) = shared.session.lock() else {
            return false;
        };
        guard.is_some()
    }

    pub(crate) fn lsp_disable(&mut self) {
        self.lsp_last_error = None;
        self.lsp_reset();
    }

    pub(crate) fn lsp_fail(&mut self, reason: impl Into<String>) {
        self.lsp_last_error = Some(reason.into());
        self.lsp_reset();
    }

    pub(crate) fn lsp_clear_result_state(&mut self) {
        self.lsp_latest_result_request_id.clear();
        self.lsp_last_result_json.clear();
    }

    pub(crate) fn lsp_clear_result_state_for_view(&mut self, view: ViewId) {
        self.lsp_latest_result_request_id
            .retain(|key, _| key.0 != view);
        self.lsp_last_result_json.retain(|key, _| key.0 != view);
    }

    pub(crate) fn lsp_reset(&mut self) {
        if let (Some(shared), Some(uri)) = (self.lsp.as_ref(), self.lsp_document_uri.as_deref()) {
            let uri = uri.to_string();
            let _ = shared.with_session_mut(|session| session.close_document(uri.as_str()));
        }

        self.lsp = None;
        self.lsp_document_uri = None;
        self.lsp_delta_calc = None;
        self.lsp_aux_refresh_due = None;
        self.lsp_inlay_in_flight = false;
        self.lsp_code_lens_in_flight = false;
        self.lsp_document_links_in_flight = false;
        self.lsp_client_requests.clear();
        self.lsp_clear_result_state();
        self.lsp_latest_on_type_formatting_request_id.clear();

        let _ = self.apply_processing_edits(editor_core_lsp::lsp_clear_edits());
    }
}

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
    pub(crate) render_cache: Option<RenderFrameCache>,
    pub(crate) minimap_cache: Option<MinimapCache>,
}
