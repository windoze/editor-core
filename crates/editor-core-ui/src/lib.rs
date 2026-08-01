//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

mod command_json;
mod editor_ui;
mod ime;
#[path = "lib/json_helpers.rs"]
mod json_helpers;
mod keybindings;
#[path = "lib/lsp_shared.rs"]
mod lsp_shared;
mod multi_document;
#[path = "lib/render_helpers.rs"]
mod render_helpers;
#[path = "lib/treesitter_worker.rs"]
mod treesitter_worker;
mod windowing;

pub(crate) use json_helpers::*;
pub(crate) use lsp_shared::*;
pub(crate) use render_helpers::*;
pub(crate) use treesitter_worker::*;

use editor_core::snapshot::{ComposedCellSource, ComposedGrid, ComposedLineKind, HeadlessGrid};
use editor_core::workspace::{BufferId, ViewId, Workspace};
use editor_core::{
    AutoPairsConfig, Command, CommandResult, CursorCommand, DecorationKind, DecorationLayerId,
    DecorationPlacement, DiagnosticSeverity, DocumentSymbol, EditCommand, ExpandSelectionDirection,
    ExpandSelectionUnit, FoldRegion, IME_MARKED_TEXT_STYLE_ID, Interval, MATCH_HIGHLIGHT_STYLE_ID,
    Position, ProcessingEdit, SearchOptions, Selection, SelectionDirection, StyleCommand,
    StyleLayerId, SymbolKind, ViewCommand,
};
use editor_core_lsp::{
    DeltaCalculator, LspContentChange, LspDocument, LspEvent, LspNotification, LspResponseError,
    LspSession, LspSessionStartOptions, LspTextEdit, char_offsets_for_lsp_range,
    encode_semantic_style_id, folding_ranges_result_to_processing_edit,
    lsp_code_lens_to_processing_edit, lsp_diagnostics_to_processing_edits,
    lsp_document_highlights_to_processing_edit, lsp_document_links_to_processing_edits,
    lsp_document_symbols_to_processing_edit, lsp_inlay_hints_to_processing_edit,
    semantic_tokens_to_intervals, summarize_workspace_edit, text_edits_from_value,
    workspace_edit_text_edits,
};
use editor_core_render_skia::{
    FOLD_MARKER_COLLAPSED_STYLE_ID, FOLD_MARKER_EXPANDED_STYLE_ID, FoldMarker, FoldMarkerStyle,
    GUTTER_BACKGROUND_STYLE_ID, GUTTER_FOREGROUND_STYLE_ID, GUTTER_SEPARATOR_STYLE_ID,
    RenderConfig, RenderError, RenderTheme, Rgba8, SkiaRenderer, StyleColors, StyleFont,
    TextDecorations, TextVerticalAlign, UnderlineStyle, VisualCaret, VisualSelection,
    WhitespaceRenderMode,
};
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};
use editor_core_treesitter::{
    TreeSitterIndenter, TreeSitterProcessor, TreeSitterProcessorConfig, TreeSitterRegistry,
    TreeSitterRegistryError, TreeSitterUpdateMode, load_indenter_config_from_config,
    load_processor_config_from_config,
};
use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeMap, HashMap};
use std::ffi::c_void;
use std::hash::{Hash, Hasher};
use std::process::Stdio;
use std::sync::{Arc, Mutex, OnceLock, Weak, mpsc};
use std::thread;
use std::time::{Duration, Instant};
use thiserror::Error;

pub use ime::{utf8_byte_offset_to_char_offset, utf8_byte_range_to_char_range};
pub use keybindings::{
    Key, KeyStroke, Keybinding, KeybindingContext, KeybindingResolver, KeybindingResolverResult,
    KeybindingWhen, Keymap, Modifiers, Platform, ResolvedCommand, dispatch_command_to_editor_ui,
};
pub use multi_document::{MultiDocumentEditorUi, TabId, TabSearchResult};
pub use windowing::{WindowingError, rgba8_to_argb_u32};

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
    #[error("processor error: {0}")]
    Processor(String),
}

/// UI chrome colors (gutter, fold markers, etc.) rendered outside the document text grid.
///
/// This is a convenience wrapper that maps named UI elements to reserved `StyleId`s in
/// `editor-core-render-skia` (e.g. `GUTTER_BACKGROUND_STYLE_ID`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChromeTheme {
    pub gutter_background: Rgba8,
    pub gutter_foreground: Rgba8,
    pub gutter_separator: Rgba8,
    pub fold_marker_collapsed: Rgba8,
    pub fold_marker_expanded: Rgba8,
}

impl Default for ChromeTheme {
    fn default() -> Self {
        Self {
            gutter_background: Rgba8::new(0xF5, 0xF5, 0xF5, 0xFF),
            gutter_foreground: Rgba8::new(0x88, 0x88, 0x88, 0xFF),
            gutter_separator: Rgba8::new(0xDD, 0xDD, 0xDD, 0xFF),
            fold_marker_collapsed: Rgba8::new(0x77, 0x77, 0x77, 0xFF),
            fold_marker_expanded: Rgba8::new(0xAA, 0xAA, 0xAA, 0xFF),
        }
    }
}

/// Pixel-space damage rectangle for incremental/partial redraw.
///
/// The coordinate space matches the RGBA buffer produced by `render_rgba_*` APIs:
/// - origin `(0, 0)` is the **top-left** corner of the buffer
/// - units are **physical pixels**
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DamageRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MarkedRange {
    start: usize,
    len: usize,
    /// Text that was replaced when the IME composition started.
    ///
    /// Needed to support "cancel composition" without losing the original selection.
    original_text: String,
    original_len: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SearchQueryState {
    query: String,
    options: SearchOptions,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MouseSelectionMode {
    Char,
    Word,
    Line,
    Paragraph,
    Rect,
}

#[derive(Debug, Clone)]
struct MouseDragState {
    mode: MouseSelectionMode,
    anchor_pos: Position,
    anchor_offset: usize,
    /// For unit-based selections (word), store the initial selected unit range.
    anchor_unit_range: Option<(usize, usize)>,
}

struct EditorUiDoc {
    ws: Workspace,
    buffer_id: BufferId,
    sublime: Option<SublimeProcessor>,
    treesitter: Option<TreeSitterAsyncWorker>,
    treesitter_indenter: Option<TreeSitterIndenter>,
    treesitter_capture_mapper: TreeSitterCaptureMapper,
    treesitter_processing_config: TreeSitterProcessingConfig,
    treesitter_registry: TreeSitterRegistry,
    treesitter_doc_version: u64,
    lsp: Option<Arc<SharedLspSession>>,
    lsp_document_uri: Option<String>,
    lsp_last_cmd: Option<String>,
    lsp_last_error: Option<String>,
    lsp_delta_calc: Option<DeltaCalculator>,
    lsp_aux_refresh_due: Option<Instant>,
    lsp_inlay_in_flight: bool,
    lsp_code_lens_in_flight: bool,
    lsp_document_links_in_flight: bool,
    lsp_client_requests: HashMap<u64, LspClientRequest>,
    lsp_latest_result_request_id: HashMap<(ViewId, LspResultSlot), u64>,
    lsp_latest_on_type_formatting_request_id: HashMap<ViewId, u64>,
    lsp_last_result_json: HashMap<(ViewId, LspResultSlot), String>,
    text_version: u64,
}

impl EditorUiDoc {
    fn exec_core(&mut self, view_id: ViewId, command: Command) -> Result<CommandResult, UiError> {
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

    fn apply_processing_edits<I>(&mut self, edits: I) -> Result<(), UiError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        self.ws
            .apply_processing_edits(self.buffer_id, edits)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    fn apply_lsp_processing_edits<I>(&mut self, edits: I) -> Result<bool, UiError>
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

    fn lsp_is_enabled(&self) -> bool {
        let Some(shared) = self.lsp.as_ref() else {
            return false;
        };
        let Ok(guard) = shared.session.lock() else {
            return false;
        };
        guard.is_some()
    }

    fn lsp_disable(&mut self) {
        self.lsp_last_error = None;
        self.lsp_reset();
    }

    fn lsp_fail(&mut self, reason: impl Into<String>) {
        self.lsp_last_error = Some(reason.into());
        self.lsp_reset();
    }

    fn lsp_clear_result_state(&mut self) {
        self.lsp_latest_result_request_id.clear();
        self.lsp_last_result_json.clear();
    }

    fn lsp_clear_result_state_for_view(&mut self, view: ViewId) {
        self.lsp_latest_result_request_id
            .retain(|key, _| key.0 != view);
        self.lsp_last_result_json.retain(|key, _| key.0 != view);
    }

    fn lsp_reset(&mut self) {
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
struct RenderFrameCache {
    view_version: u64,
    render_config: RenderConfig,
    theme_hash: u64,
    start_visual_row: usize,
    row_count: usize,
    has_virtual_text: bool,
    row_signatures: Vec<u64>,
}

#[derive(Debug, Clone)]
struct MinimapCache {
    view_version: u64,
    start_visual_row: usize,
    count: usize,
    json: String,
}

/// 单 buffer UI 句柄（每个实例对应一个 `Workspace` view）。
///
/// - 通过 [`Self::clone_view`] 可为同一文档创建额外 view（用于 split panes / 多视图）。
/// - 文本与派生状态（Sublime/Tree-sitter/LSP）在同一 buffer 内共享；光标/选择/滚动等是 view 级别。
pub struct EditorUi {
    doc: Arc<Mutex<EditorUiDoc>>,
    buffer_id: BufferId,
    view_id: ViewId,
    renderer: SkiaRenderer,
    theme: RenderTheme,
    render_config: RenderConfig,
    marked: Option<MarkedRange>,
    search_query: Option<SearchQueryState>,
    mouse_drag: Option<MouseDragState>,
    auto_pairs: AutoPairsConfig,
    bracket_match_highlights_enabled: bool,
    render_cache: Option<RenderFrameCache>,
    minimap_cache: Option<MinimapCache>,
}

#[cfg(test)]
mod tests;
