//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

mod command_json;
mod ime;
mod keybindings;
mod multi_document;
mod windowing;

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
    DeltaCalculator, LspContentChange, LspDocument, LspEvent, LspNotification, LspSession,
    LspSessionStartOptions, LspTextEdit, char_offsets_for_lsp_range, encode_semantic_style_id,
    folding_ranges_result_to_processing_edit, lsp_code_lens_to_processing_edit,
    lsp_diagnostics_to_processing_edits, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edits, lsp_document_symbols_to_processing_edit,
    lsp_inlay_hints_to_processing_edit, semantic_tokens_to_intervals, summarize_workspace_edit,
    text_edits_from_value, workspace_edit_text_edits,
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

fn value_offset_range(start: usize, end: usize) -> serde_json::Value {
    serde_json::json!({ "start": start, "end": end })
}

fn parse_lsp_formatting_options(
    formatting_options_json: &str,
) -> Result<serde_json::Value, UiError> {
    if formatting_options_json.trim().is_empty() {
        Ok(serde_json::json!({
            "tabSize": 4,
            "insertSpaces": true,
        }))
    } else {
        serde_json::from_str(formatting_options_json).map_err(|e| UiError::Processor(e.to_string()))
    }
}

fn parse_lsp_position_list_json(positions_json: &str) -> Result<Vec<(usize, usize)>, UiError> {
    let value: serde_json::Value =
        serde_json::from_str(positions_json).map_err(|e| UiError::Processor(e.to_string()))?;
    let positions = value.as_array().ok_or_else(|| {
        UiError::Processor("selection range positions must be an array".to_string())
    })?;

    positions
        .iter()
        .map(|position| {
            let line = position
                .get("line")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing line".to_string())
                })?;
            let column = position
                .get("column")
                .and_then(serde_json::Value::as_u64)
                .ok_or_else(|| {
                    UiError::Processor("selection range position missing column".to_string())
                })?;
            let line = usize::try_from(line)
                .map_err(|_| UiError::Processor("selection range line is too large".to_string()))?;
            let column = usize::try_from(column).map_err(|_| {
                UiError::Processor("selection range column is too large".to_string())
            })?;
            Ok((line, column))
        })
        .collect()
}

fn parse_lsp_json_array(value_json: &str, name: &str) -> Result<Vec<serde_json::Value>, UiError> {
    if value_json.trim().is_empty() {
        return Ok(Vec::new());
    }

    let value: serde_json::Value =
        serde_json::from_str(value_json).map_err(|e| UiError::Processor(e.to_string()))?;
    value
        .as_array()
        .cloned()
        .ok_or_else(|| UiError::Processor(format!("{name} must be a JSON array")))
}

fn diagnostic_severity_to_str(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Information => "information",
        DiagnosticSeverity::Hint => "hint",
    }
}

fn value_diagnostic(diagnostic: &editor_core::Diagnostic) -> serde_json::Value {
    serde_json::json!({
        "range": value_offset_range(diagnostic.range.start, diagnostic.range.end),
        "severity": diagnostic.severity.map(diagnostic_severity_to_str),
        "code": diagnostic.code,
        "source": diagnostic.source,
        "message": diagnostic.message,
        "related_information_json": diagnostic.related_information_json,
        "data_json": diagnostic.data_json
    })
}

fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

fn decoration_kind_to_json(value: DecorationKind) -> serde_json::Value {
    match value {
        DecorationKind::InlayHint => serde_json::json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => serde_json::json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => serde_json::json!({ "kind": "document_link" }),
        DecorationKind::Highlight => serde_json::json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

fn value_decoration(decoration: &editor_core::Decoration) -> serde_json::Value {
    serde_json::json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

fn value_fold_region(region: &FoldRegion) -> serde_json::Value {
    serde_json::json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

fn value_interval(interval: &Interval) -> serde_json::Value {
    serde_json::json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}

fn symbol_kind_to_json(value: SymbolKind) -> serde_json::Value {
    match value {
        SymbolKind::File => serde_json::json!({ "kind": "file" }),
        SymbolKind::Module => serde_json::json!({ "kind": "module" }),
        SymbolKind::Namespace => serde_json::json!({ "kind": "namespace" }),
        SymbolKind::Package => serde_json::json!({ "kind": "package" }),
        SymbolKind::Class => serde_json::json!({ "kind": "class" }),
        SymbolKind::Method => serde_json::json!({ "kind": "method" }),
        SymbolKind::Property => serde_json::json!({ "kind": "property" }),
        SymbolKind::Field => serde_json::json!({ "kind": "field" }),
        SymbolKind::Constructor => serde_json::json!({ "kind": "constructor" }),
        SymbolKind::Enum => serde_json::json!({ "kind": "enum" }),
        SymbolKind::Interface => serde_json::json!({ "kind": "interface" }),
        SymbolKind::Function => serde_json::json!({ "kind": "function" }),
        SymbolKind::Variable => serde_json::json!({ "kind": "variable" }),
        SymbolKind::Constant => serde_json::json!({ "kind": "constant" }),
        SymbolKind::String => serde_json::json!({ "kind": "string" }),
        SymbolKind::Number => serde_json::json!({ "kind": "number" }),
        SymbolKind::Boolean => serde_json::json!({ "kind": "boolean" }),
        SymbolKind::Array => serde_json::json!({ "kind": "array" }),
        SymbolKind::Object => serde_json::json!({ "kind": "object" }),
        SymbolKind::Key => serde_json::json!({ "kind": "key" }),
        SymbolKind::Null => serde_json::json!({ "kind": "null" }),
        SymbolKind::EnumMember => serde_json::json!({ "kind": "enum_member" }),
        SymbolKind::Struct => serde_json::json!({ "kind": "struct" }),
        SymbolKind::Event => serde_json::json!({ "kind": "event" }),
        SymbolKind::Operator => serde_json::json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => serde_json::json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

fn value_document_symbol(symbol: &DocumentSymbol) -> serde_json::Value {
    serde_json::json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
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

#[derive(Debug, Default)]
struct TreeSitterCaptureMapper {
    capture_to_id: HashMap<String, u32>,
    id_to_capture: Vec<String>,
}

impl TreeSitterCaptureMapper {
    /// Base prefix for Tree-sitter highlight capture `StyleId`s.
    pub const BASE: u32 = 0x0500_0000;

    pub fn style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        if let Some(&id) = self.capture_to_id.get(capture_name) {
            return id;
        }
        let idx = self.id_to_capture.len() as u32 + 1;
        let id = Self::BASE | idx;
        self.id_to_capture.push(capture_name.to_string());
        self.capture_to_id.insert(capture_name.to_string(), id);
        id
    }

    pub fn capture_for_style_id(&self, style_id: u32) -> Option<&str> {
        if style_id & 0xFF00_0000 != Self::BASE {
            return None;
        }
        let raw = style_id & 0x00FF_FFFF;
        if raw == 0 {
            return None;
        }
        let idx = raw.saturating_sub(1) as usize;
        self.id_to_capture.get(idx).map(|s| s.as_str())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessingPollResult {
    pub applied: bool,
    pub pending: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreeSitterProcessingConfig {
    /// Debounce window for running Tree-sitter queries (highlighting/folding).
    pub debounce_ms: u32,
    /// Soft budget for a single query pass; when exceeded, the worker enters a cooldown window
    /// and prefers visible-range queries.
    pub query_budget_ms: u32,
    /// Cooldown window after an over-budget query pass.
    pub cooldown_ms: u32,
    /// When the document exceeds this many Unicode scalar values, prefer visible-range queries.
    pub large_doc_char_threshold: u32,
    /// If true, large documents use visible/prefetch-range queries by default.
    pub prefer_visible_range_on_large_docs: bool,
}

impl Default for TreeSitterProcessingConfig {
    fn default() -> Self {
        Self {
            // One-frame debounce: coalesce bursts without making highlighting feel "late".
            debounce_ms: 16,
            // Anything above ~1 frame is already noticeable for CPU/battery; degrade when exceeded.
            query_budget_ms: 30,
            cooldown_ms: 200,
            large_doc_char_threshold: 200_000,
            prefer_visible_range_on_large_docs: true,
        }
    }
}

enum TreeSitterWorkerMsg {
    Init {
        config: TreeSitterProcessorConfig,
        runtime: TreeSitterProcessingConfig,
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    ApplyDelta {
        version: u64,
        delta: editor_core::delta::TextDelta,
        prefetch_char_range: Option<(usize, usize)>,
    },
    FullSync {
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    UpdateRuntimeConfig {
        runtime: TreeSitterProcessingConfig,
    },
    Shutdown,
}

enum TreeSitterWorkerEvent {
    Processed {
        version: u64,
        edits: Vec<ProcessingEdit>,
        update_mode: TreeSitterUpdateMode,
    },
    NeedFullSync,
    Error(String),
}

fn set_current_thread_qos_for_treesitter_worker() {
    // Best effort: lower priority than the UI thread to avoid input jank / CPU spikes.
    //
    // Escape hatch: on some machines the UTILITY QoS class starves this worker badly enough that a
    // single WASM grammar load + parse does not finish within a test's bounded wait window, making
    // the async tree-sitter tests time out. Tests set `EDITOR_CORE_DISABLE_TS_WORKER_QOS=1` to keep
    // the worker at normal priority. This is honored across crates (the env var is read at runtime),
    // unlike a `cfg(test)` gate which only applies to the crate under test.
    #[cfg(target_os = "macos")]
    {
        if std::env::var_os("EDITOR_CORE_DISABLE_TS_WORKER_QOS").is_some() {
            return;
        }
        unsafe {
            let _ = libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_UTILITY, 0);
        }
    }
}

struct TreeSitterAsyncWorker {
    tx: mpsc::Sender<TreeSitterWorkerMsg>,
    rx: mpsc::Receiver<TreeSitterWorkerEvent>,
    join: Option<thread::JoinHandle<()>>,
    requested_version: Option<u64>,
    applied_version: Option<u64>,
    last_update_mode: Option<TreeSitterUpdateMode>,
}

impl TreeSitterAsyncWorker {
    fn spawn() -> Self {
        let (tx, rx_worker) = mpsc::channel::<TreeSitterWorkerMsg>();
        let (tx_events, rx) = mpsc::channel::<TreeSitterWorkerEvent>();

        let join = thread::Builder::new()
            .name("editor-core-treesitter-worker".to_string())
            .spawn(move || {
                set_current_thread_qos_for_treesitter_worker();

                let mut processor: Option<TreeSitterProcessor> = None;
                let mut runtime = TreeSitterProcessingConfig::default();

                let mut latest_prefetch_char_range: Option<(usize, usize)> = None;
                let mut latest_doc_char_count: usize = 0;
                let mut latest_version: u64 = 0;
                let mut dirty_for_query: bool = false;
                let mut awaiting_full_sync: bool = false;
                let mut sent_need_full_sync: bool = false;

                let mut debounce_deadline: Option<std::time::Instant> = None;
                let mut cooldown_until: Option<std::time::Instant> = None;
                let mut degraded: bool = false;
                let mut degraded_fast_streak: u32 = 0;

                loop {
                    let now = std::time::Instant::now();
                    let debounce_at = debounce_deadline.unwrap_or(now);
                    let next_action_at = if dirty_for_query {
                        match cooldown_until {
                            Some(cooldown) if cooldown > debounce_at => cooldown,
                            _ => debounce_at,
                        }
                    } else {
                        // No pending query work; block until the next message.
                        std::time::Instant::now()
                    };

                    let msg = if dirty_for_query {
                        let timeout = next_action_at.saturating_duration_since(now);
                        rx_worker.recv_timeout(timeout)
                    } else {
                        rx_worker
                            .recv()
                            .map_err(|_| mpsc::RecvTimeoutError::Disconnected)
                    };

                    match msg {
                        Ok(TreeSitterWorkerMsg::Shutdown) => break,
                        Ok(TreeSitterWorkerMsg::UpdateRuntimeConfig { runtime: next }) => {
                            runtime = next;
                        }
                        Ok(TreeSitterWorkerMsg::Init {
                            config,
                            runtime: next_runtime,
                            version,
                            text,
                            prefetch_char_range,
                        }) => {
                            runtime = next_runtime;
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = text.chars().count();
                            dirty_for_query = false;
                            awaiting_full_sync = false;
                            sent_need_full_sync = false;

                            match TreeSitterProcessor::new(config) {
                                Ok(mut p) => match p.sync_to(version, None, Some(&text)) {
                                    Ok(_) => {
                                        processor = Some(p);
                                        latest_version = version;
                                        dirty_for_query = true;
                                        debounce_deadline = Some(
                                            std::time::Instant::now()
                                                + std::time::Duration::from_millis(
                                                    runtime.debounce_ms as u64,
                                                ),
                                        );
                                    }
                                    Err(e) => {
                                        let _ = tx_events
                                            .send(TreeSitterWorkerEvent::Error(e.to_string()));
                                        processor = Some(p);
                                    }
                                },
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Ok(TreeSitterWorkerMsg::ApplyDelta {
                            version,
                            delta,
                            prefetch_char_range,
                        }) => {
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = delta.after_char_count;

                            if awaiting_full_sync {
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            }

                            let Some(p) = processor.as_mut() else {
                                awaiting_full_sync = true;
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            };

                            match p.sync_to(version, Some(&delta), None) {
                                Ok(_) => {
                                    latest_version = version;
                                    dirty_for_query = true;
                                    debounce_deadline = Some(
                                        std::time::Instant::now()
                                            + std::time::Duration::from_millis(
                                                runtime.debounce_ms as u64,
                                            ),
                                    );
                                }
                                Err(editor_core_treesitter::TreeSitterError::DeltaMismatch) => {
                                    awaiting_full_sync = true;
                                    if !sent_need_full_sync {
                                        let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                        sent_need_full_sync = true;
                                    }
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Ok(TreeSitterWorkerMsg::FullSync {
                            version,
                            text,
                            prefetch_char_range,
                        }) => {
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = text.chars().count();

                            let Some(p) = processor.as_mut() else {
                                awaiting_full_sync = true;
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            };

                            match p.sync_to(version, None, Some(&text)) {
                                Ok(_) => {
                                    latest_version = version;
                                    awaiting_full_sync = false;
                                    sent_need_full_sync = false;
                                    dirty_for_query = true;
                                    debounce_deadline = Some(
                                        std::time::Instant::now()
                                            + std::time::Duration::from_millis(
                                                runtime.debounce_ms as u64,
                                            ),
                                    );
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            // We reached the debounce/cooldown boundary; run queries if needed.
                            if !dirty_for_query {
                                continue;
                            }
                            if awaiting_full_sync {
                                continue;
                            }
                            if let Some(cooldown) = cooldown_until
                                && std::time::Instant::now() < cooldown
                            {
                                continue;
                            }

                            let Some(p) = processor.as_mut() else {
                                continue;
                            };

                            let large_doc = runtime.prefer_visible_range_on_large_docs
                                && latest_doc_char_count
                                    >= runtime.large_doc_char_threshold as usize;
                            let use_range = if degraded || large_doc {
                                latest_prefetch_char_range
                            } else {
                                None
                            };

                            let t0 = std::time::Instant::now();
                            match p.compute_processing_edits(use_range) {
                                Ok(edits) => {
                                    let dt = t0.elapsed();
                                    let dt_ms = dt.as_secs_f64() * 1000.0;

                                    if dt_ms > runtime.query_budget_ms as f64 {
                                        degraded = true;
                                        degraded_fast_streak = 0;
                                        cooldown_until = Some(
                                            std::time::Instant::now()
                                                + std::time::Duration::from_millis(
                                                    runtime.cooldown_ms as u64,
                                                ),
                                        );
                                    } else if degraded {
                                        degraded_fast_streak =
                                            degraded_fast_streak.saturating_add(1);
                                        if degraded_fast_streak >= 5 {
                                            degraded = false;
                                            degraded_fast_streak = 0;
                                        }
                                    }

                                    let _ = tx_events.send(TreeSitterWorkerEvent::Processed {
                                        version: latest_version,
                                        edits,
                                        update_mode: p.last_update_mode(),
                                    });
                                    dirty_for_query = false;
                                }
                                Err(editor_core_treesitter::TreeSitterError::DeltaMismatch) => {
                                    awaiting_full_sync = true;
                                    if !sent_need_full_sync {
                                        let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                        sent_need_full_sync = true;
                                    }
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    }
                }
            })
            .ok();

        Self {
            tx,
            rx,
            join,
            requested_version: None,
            applied_version: None,
            last_update_mode: None,
        }
    }

    fn is_pending(&self) -> bool {
        match (self.requested_version, self.applied_version) {
            (Some(req), Some(applied)) => applied < req,
            (Some(_), None) => true,
            _ => false,
        }
    }
}

impl Drop for TreeSitterAsyncWorker {
    fn drop(&mut self) {
        let _ = self.tx.send(TreeSitterWorkerMsg::Shutdown);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct SharedLspKey {
    cmd: String,
    args: Vec<String>,
    root_uri: String,
}

struct SharedLspSession {
    session: Mutex<Option<LspSession>>,
}

impl SharedLspSession {
    fn with_session_mut<R>(
        &self,
        f: impl FnOnce(&mut LspSession) -> Result<R, String>,
    ) -> Result<R, String> {
        let mut guard = self
            .session
            .lock()
            .map_err(|_| "LSP session lock poisoned".to_string())?;

        let Some(session) = guard.as_mut() else {
            return Err("LSP session is not available".to_string());
        };

        match f(session) {
            Ok(v) => Ok(v),
            Err(err) => {
                // Mark the shared session as dead so other users can fail fast.
                *guard = None;
                Err(err)
            }
        }
    }
}

static SHARED_LSP_POOL: OnceLock<Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>>> =
    OnceLock::new();

fn shared_lsp_pool() -> &'static Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>> {
    SHARED_LSP_POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

fn get_or_start_shared_lsp_session(
    key: SharedLspKey,
    start: LspSessionStartOptions,
) -> Result<Arc<SharedLspSession>, UiError> {
    // Fast path: try an existing session.
    if let Ok(mut pool) = shared_lsp_pool().lock() {
        if let Some(existing) = pool.get(&key).and_then(|w| w.upgrade()) {
            return Ok(existing);
        }
        // Drop stale weak entries.
        pool.remove(&key);
    }

    // Start outside the pool lock.
    let session = LspSession::start(start).map_err(|e| UiError::Processor(e.to_string()))?;
    let shared = Arc::new(SharedLspSession {
        session: Mutex::new(Some(session)),
    });

    if let Ok(mut pool) = shared_lsp_pool().lock() {
        pool.insert(key, Arc::downgrade(&shared));
    }

    Ok(shared)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum LspResultSlot {
    Hover,
    Definition,
    Declaration,
    TypeDefinition,
    Implementation,
    References,
    Completion,
    CompletionResolve,
    SignatureHelp,
    PrepareRename,
    Rename,
    CodeAction,
    CodeActionResolve,
    ExecuteCommand,
    CodeLensResolve,
    DocumentSymbols,
    WorkspaceSymbols,
    FoldingRanges,
    SelectionRange,
    LinkedEditingRange,
    DocumentDiagnostic,
    WorkspaceDiagnostic,
    DocumentColor,
    ColorPresentation,
    PrepareCallHierarchy,
    CallHierarchyIncoming,
    CallHierarchyOutgoing,
    PrepareTypeHierarchy,
    TypeHierarchySupertypes,
    TypeHierarchySubtypes,
}

impl LspResultSlot {
    fn from_response_method(method: &str) -> Option<Self> {
        match method {
            "textDocument/hover" => Some(Self::Hover),
            "textDocument/definition" => Some(Self::Definition),
            "textDocument/declaration" => Some(Self::Declaration),
            "textDocument/typeDefinition" => Some(Self::TypeDefinition),
            "textDocument/implementation" => Some(Self::Implementation),
            "textDocument/references" => Some(Self::References),
            "textDocument/completion" => Some(Self::Completion),
            "completionItem/resolve" => Some(Self::CompletionResolve),
            "textDocument/signatureHelp" => Some(Self::SignatureHelp),
            "textDocument/prepareRename" => Some(Self::PrepareRename),
            "textDocument/rename" => Some(Self::Rename),
            "textDocument/codeAction" => Some(Self::CodeAction),
            "codeAction/resolve" => Some(Self::CodeActionResolve),
            "workspace/executeCommand" => Some(Self::ExecuteCommand),
            "codeLens/resolve" => Some(Self::CodeLensResolve),
            "textDocument/documentSymbol" => Some(Self::DocumentSymbols),
            "workspace/symbol" => Some(Self::WorkspaceSymbols),
            "textDocument/foldingRange" => Some(Self::FoldingRanges),
            "textDocument/selectionRange" => Some(Self::SelectionRange),
            "textDocument/linkedEditingRange" => Some(Self::LinkedEditingRange),
            "textDocument/diagnostic" => Some(Self::DocumentDiagnostic),
            "workspace/diagnostic" => Some(Self::WorkspaceDiagnostic),
            "textDocument/documentColor" => Some(Self::DocumentColor),
            "textDocument/colorPresentation" => Some(Self::ColorPresentation),
            "textDocument/prepareCallHierarchy" => Some(Self::PrepareCallHierarchy),
            "callHierarchy/incomingCalls" => Some(Self::CallHierarchyIncoming),
            "callHierarchy/outgoingCalls" => Some(Self::CallHierarchyOutgoing),
            "textDocument/prepareTypeHierarchy" => Some(Self::PrepareTypeHierarchy),
            "typeHierarchy/supertypes" => Some(Self::TypeHierarchySupertypes),
            "typeHierarchy/subtypes" => Some(Self::TypeHierarchySubtypes),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LspClientRequest {
    Result { view: ViewId, slot: LspResultSlot },
    OnTypeFormatting { view: ViewId, version: u64 },
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

impl Drop for EditorUi {
    fn drop(&mut self) {
        let is_last_handle = Arc::strong_count(&self.doc) == 1;
        let mut doc = self.doc.lock().unwrap_or_else(|e| e.into_inner());

        if is_last_handle {
            if doc.lsp.is_some() {
                doc.lsp_disable();
            }
        } else {
            doc.lsp_clear_result_state_for_view(self.view_id);
            doc.lsp_latest_on_type_formatting_request_id
                .remove(&self.view_id);
        }

        let _ = doc.ws.close_view(self.view_id);
    }
}

impl EditorUi {
    fn lock_doc(&self) -> std::sync::MutexGuard<'_, EditorUiDoc> {
        self.doc.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn with_line_index<R>(
        &self,
        f: impl FnOnce(&editor_core::LineIndex) -> R,
    ) -> Result<R, UiError> {
        let doc = self.lock_doc();
        let line_index = doc
            .ws
            .buffer_line_index(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        Ok(f(line_index))
    }

    fn exec_core(&mut self, command: Command) -> Result<CommandResult, UiError> {
        let mut doc = self.lock_doc();
        let result = doc.exec_core(self.view_id, command.clone())?;

        if self.bracket_match_highlights_enabled {
            match command {
                Command::Edit(_) | Command::Cursor(_) => {
                    let _ = doc.exec_core(
                        self.view_id,
                        Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                    );
                }
                Command::View(_) | Command::Style(_) => {}
            }
        }

        Ok(result)
    }

    /// Execute a core editor command encoded as JSON, using the same schema as the headless FFI
    /// command plane plus UI-specific additions such as snippets, auto-pairs config, and bracket
    /// highlight maintenance commands.
    pub fn execute_command_json(&mut self, command_json: &str) -> Result<String, UiError> {
        let command =
            command_json::parse_command_from_json(command_json).map_err(UiError::Processor)?;
        let is_edit = matches!(command, Command::Edit(_));
        let is_cursor = matches!(command, Command::Cursor(_));

        match &command {
            Command::View(ViewCommand::SetAutoPairsConfig { config }) => {
                self.auto_pairs = config.clone();
            }
            Command::View(ViewCommand::SetAutoPairsEnabled { enabled }) => {
                self.auto_pairs.enabled = *enabled;
            }
            _ => {}
        }

        let result = self.exec_core(command)?;

        if is_edit {
            self.refresh_processing()?;
            self.ensure_primary_caret_visible_after_edit();
        } else if is_cursor {
            self.ensure_primary_caret_visible_after_navigation();
        }

        serde_json::to_string(&command_json::command_result_to_value(result))
            .map_err(|err| UiError::Processor(format!("failed to encode command result: {err}")))
    }

    /// Export current diagnostics for the active buffer.
    pub fn diagnostics_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let diagnostics = doc
            .ws
            .diagnostics_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "diagnostics": diagnostics.iter().map(value_diagnostic).collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode diagnostics: {err}")))
    }

    /// Export current decoration layers for the active buffer.
    pub fn decorations_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let decorations = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "layers": decorations
                .iter()
                .map(|(layer, decorations)| {
                    serde_json::json!({
                        "layer": layer.0,
                        "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
                    })
                })
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode decorations: {err}")))
    }

    /// Export current document symbols for the active buffer.
    pub fn document_symbols_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let outline = doc
            .ws
            .document_symbols_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "symbols": outline
                .symbols
                .iter()
                .map(value_document_symbol)
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode document symbols: {err}")))
    }

    /// Export current folding regions for the active buffer.
    pub fn folding_regions_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let regions = doc
            .ws
            .folding_regions_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "regions": regions.iter().map(value_fold_region).collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode folding regions: {err}")))
    }

    /// Export style intervals overlapping the given character-offset range.
    pub fn style_intervals_json(&self, start: usize, end: usize) -> Result<String, UiError> {
        let (start, end) = (start.min(end), start.max(end));
        let doc = self.lock_doc();
        let layers = doc
            .ws
            .style_intervals_for_buffer(self.buffer_id, start, end)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "layers": layers
                .iter()
                .map(|(layer, intervals)| {
                    serde_json::json!({
                        "layer": layer.0,
                        "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
                    })
                })
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode style intervals: {err}")))
    }

    fn apply_processing_edits<I>(&mut self, edits: I) -> Result<(), UiError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        let mut doc = self.lock_doc();
        doc.apply_processing_edits(edits)
    }

    pub fn new(initial_text: &str, viewport_width_cells: usize) -> Self {
        let mut ws = Workspace::new();
        let opened = ws
            .open_buffer(None, initial_text, viewport_width_cells.max(1))
            .expect("open initial workspace buffer");
        let buffer_id = opened.buffer_id;
        let doc = Arc::new(Mutex::new(EditorUiDoc {
            ws,
            buffer_id,
            sublime: None,
            treesitter: None,
            treesitter_indenter: None,
            treesitter_capture_mapper: TreeSitterCaptureMapper::default(),
            treesitter_processing_config: TreeSitterProcessingConfig::default(),
            treesitter_registry: TreeSitterRegistry::default(),
            treesitter_doc_version: 0,
            lsp: None,
            lsp_document_uri: None,
            lsp_last_cmd: None,
            lsp_last_error: None,
            lsp_delta_calc: None,
            lsp_aux_refresh_due: None,
            lsp_inlay_in_flight: false,
            lsp_code_lens_in_flight: false,
            lsp_document_links_in_flight: false,
            lsp_client_requests: HashMap::new(),
            lsp_latest_result_request_id: HashMap::new(),
            lsp_latest_on_type_formatting_request_id: HashMap::new(),
            lsp_last_result_json: HashMap::new(),
            text_version: 0,
        }));
        Self {
            doc,
            buffer_id,
            view_id: opened.view_id,
            renderer: SkiaRenderer::new(),
            theme: RenderTheme::default(),
            render_config: RenderConfig::default(),
            marked: None,
            search_query: None,
            mouse_drag: None,
            auto_pairs: AutoPairsConfig::default(),
            bracket_match_highlights_enabled: false,
            render_cache: None,
            minimap_cache: None,
        }
    }

    /// 为同一文档创建一个新的 view（光标/滚动独立，文本共享）。
    pub fn clone_view(&self, viewport_width_cells: usize) -> Result<Self, UiError> {
        let parent_view = self.view_id;
        let view_id = {
            let mut doc = self.lock_doc();
            // Clone should mirror the current view's config; derive from it explicitly rather than
            // relying on shared-executor scratch state.
            doc.ws
                .create_view_from(parent_view, viewport_width_cells.max(1))
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        let mut ui = Self {
            doc: Arc::clone(&self.doc),
            buffer_id: self.buffer_id,
            view_id,
            renderer: SkiaRenderer::new(),
            theme: self.theme.clone(),
            render_config: self.render_config,
            marked: None,
            search_query: None,
            mouse_drag: None,
            auto_pairs: self.auto_pairs.clone(),
            bracket_match_highlights_enabled: self.bracket_match_highlights_enabled,
            render_cache: None,
            minimap_cache: None,
        };

        // Clone should preserve view-local UX settings (auto-pairs, bracket matching highlights, ...),
        // not just copy the wrapper's fields.
        ui.exec_core(Command::View(ViewCommand::SetAutoPairsConfig {
            config: ui.auto_pairs.clone(),
        }))?;
        if ui.bracket_match_highlights_enabled {
            let _ = ui.exec_core(Command::Style(StyleCommand::UpdateBracketMatchHighlights));
        }

        Ok(ui)
    }

    /// Enable/disable auto-pairs behavior for typed characters (`EditCommand::TypeChar`).
    ///
    /// Notes:
    /// - This is view-local (each `EditorUi` handle corresponds to one `Workspace` view).
    pub fn set_auto_pairs_enabled(&mut self, enabled: bool) -> Result<(), UiError> {
        self.auto_pairs.enabled = enabled;
        self.exec_core(Command::View(ViewCommand::SetAutoPairsConfig {
            config: self.auto_pairs.clone(),
        }))?;
        Ok(())
    }

    /// Enable/disable bracket-match highlighting.
    ///
    /// When enabled, the UI wrapper updates `StyleLayerId::BRACKET_MATCHES` after cursor moves and
    /// edits, so renderers can highlight the matching pair (if any).
    pub fn set_bracket_match_highlights_enabled(&mut self, enabled: bool) -> Result<(), UiError> {
        self.bracket_match_highlights_enabled = enabled;
        if enabled {
            let _ = self.exec_core(Command::Style(StyleCommand::UpdateBracketMatchHighlights));
        } else {
            let _ = self.exec_core(Command::Style(StyleCommand::ClearBracketMatchHighlights));
        }
        Ok(())
    }

    /// Jump the primary caret to the matching bracket (if any).
    pub fn move_to_matching_bracket(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveToMatchingBracket))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    /// Toggle a bookmark at the current cursor line.
    ///
    /// Returns `true` if a bookmark was added, or `false` if an existing bookmark on that line was
    /// removed.
    pub fn toggle_bookmark_at_cursor_line(&mut self) -> Result<bool, UiError> {
        let added = {
            let mut doc = self.lock_doc();
            doc.ws
                .toggle_bookmark_at_cursor_line(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        Ok(added)
    }

    /// Return all bookmark line numbers (0-based) for the current document buffer.
    pub fn bookmark_lines(&self) -> Result<Vec<usize>, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .bookmark_lines(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    /// Clear all bookmarks for the current document buffer.
    pub fn clear_bookmarks(&mut self) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .clear_bookmarks(self.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Move the cursor to the next bookmark (wrapping to the first bookmark).
    ///
    /// Returns the new cursor position, or `None` if there are no bookmarks.
    pub fn goto_next_bookmark(&mut self) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_next_bookmark(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Move the cursor to the previous bookmark (wrapping to the last bookmark).
    ///
    /// Returns the new cursor position, or `None` if there are no bookmarks.
    pub fn goto_prev_bookmark(&mut self) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_prev_bookmark(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Set (or replace) a named mark at the current cursor position.
    pub fn set_mark_at_cursor(&mut self, name: String) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .set_mark_at_cursor(self.view_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Move the cursor to a named mark (if present).
    ///
    /// Returns the new cursor position, or `None` if the mark does not exist.
    pub fn goto_mark(&mut self, name: &str) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_mark(self.view_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Remove a named mark from the current document buffer.
    ///
    /// Returns `true` if the mark existed.
    pub fn clear_mark(&mut self, name: &str) -> Result<bool, UiError> {
        let existed = {
            let mut doc = self.lock_doc();
            doc.ws
                .clear_mark(self.buffer_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        Ok(existed)
    }

    /// Return all mark names for the current document buffer (deterministic order).
    pub fn mark_names(&self) -> Result<Vec<String>, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .mark_names(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    /// Record the current cursor position as a jump-list location.
    pub fn push_jump_location(&mut self) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .push_jump_location(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Jump back in the view's jump list.
    ///
    /// Returns the navigation target (including buffer id). In the single-buffer UI wrapper,
    /// this always also moves the caret.
    pub fn jump_back(&mut self) -> Result<Option<editor_core::JumpTarget>, UiError> {
        let target = {
            let mut doc = self.lock_doc();
            let target = doc
                .ws
                .jump_back(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if target.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            target
        };
        if target.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(target)
    }

    /// Jump forward in the view's jump list.
    ///
    /// Returns the navigation target (including buffer id). In the single-buffer UI wrapper,
    /// this always also moves the caret.
    pub fn jump_forward(&mut self) -> Result<Option<editor_core::JumpTarget>, UiError> {
        let target = {
            let mut doc = self.lock_doc();
            let target = doc
                .ws
                .jump_forward(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if target.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            target
        };
        if target.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(target)
    }

    pub fn text(&self) -> String {
        let doc = self.lock_doc();
        doc.ws
            .buffer_text(doc.buffer_id)
            .unwrap_or_else(|_| "".to_string())
    }

    pub fn is_modified(&self) -> bool {
        let doc = self.lock_doc();
        doc.ws.is_modified_for_view(self.view_id).unwrap_or(false)
    }

    pub fn mark_saved(&mut self) {
        let mut doc = self.lock_doc();
        let _ = doc.ws.mark_saved_for_view(self.view_id);
    }

    pub fn reveal_primary_caret(&mut self) {
        self.ensure_primary_caret_visible_after_navigation();
    }

    pub fn cursor_state(&self) -> editor_core::CursorState {
        let doc = self.lock_doc();
        doc.ws
            .cursor_state_for_view(self.view_id)
            .unwrap_or(editor_core::CursorState {
                position: Position::new(0, 0),
                offset: 0,
                multi_cursors: Vec::new(),
                selection: None,
                selections: Vec::new(),
                primary_selection_index: 0,
            })
    }

    pub fn set_treesitter_processing_config(
        &mut self,
        runtime: TreeSitterProcessingConfig,
    ) -> Result<(), UiError> {
        let mut doc = self.lock_doc();
        doc.treesitter_processing_config = runtime;
        if let Some(worker) = doc.treesitter.as_mut() {
            worker
                .tx
                .send(TreeSitterWorkerMsg::UpdateRuntimeConfig { runtime })
                .map_err(|_| {
                    UiError::Processor("failed to update tree-sitter runtime config".to_string())
                })?;
        }
        Ok(())
    }

    /// Return the primary selection range as `(start_offset, end_offset)` in character offsets.
    ///
    /// If there is no selection, `start == end == caret_offset`.
    pub fn primary_selection_offsets(&self) -> (usize, usize) {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return (cursor.offset, cursor.offset);
        };
        if let Some(sel) = cursor.selection {
            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if a <= b { (a, b) } else { (b, a) }
        } else {
            (cursor.offset, cursor.offset)
        }
    }

    /// Get the selected text (primary + secondary selections), joined with `'\n'`.
    ///
    /// Notes:
    /// - Empty selections (carets) are ignored.
    /// - The primary selection is placed first, followed by secondary selections in their
    ///   current order.
    pub fn selected_text(&self) -> String {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return String::new();
        };

        let mut order: Vec<usize> = Vec::with_capacity(cursor.selections.len());
        if cursor.primary_selection_index < cursor.selections.len() {
            order.push(cursor.primary_selection_index);
        }
        for idx in 0..cursor.selections.len() {
            if idx != cursor.primary_selection_index {
                order.push(idx);
            }
        }

        let mut parts: Vec<String> = Vec::new();
        for idx in order {
            let sel = match cursor.selections.get(idx) {
                Some(s) => s,
                None => continue,
            };
            if sel.start == sel.end {
                continue;
            }

            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            let (start, end) = if a <= b { (a, b) } else { (b, a) };
            let len = end.saturating_sub(start);
            if len == 0 {
                continue;
            }
            if let Ok(text) = doc.ws.buffer_text_range(doc.buffer_id, start, len) {
                parts.push(text);
            }
        }

        if parts.len() == 1 {
            parts.remove(0)
        } else {
            parts.join("\n")
        }
    }

    /// Get lightweight minimap snapshot as JSON.
    ///
    /// This mirrors the JSON shape from `editor-core-ffi` (`value_minimap_grid`) so hosts can reuse
    /// the same decoding logic.
    pub fn minimap_json(&mut self, start_visual_row: usize, count: usize) -> String {
        let view_version = {
            let doc = self.lock_doc();
            doc.ws.view_version(self.view_id).unwrap_or(0)
        };
        if let Some(cache) = self.minimap_cache.as_ref()
            && cache.view_version == view_version
            && cache.start_visual_row == start_visual_row
            && cache.count == count
        {
            return cache.json.clone();
        }

        let grid = {
            let mut doc = self.lock_doc();
            doc.ws
                .get_minimap_content(self.view_id, start_visual_row, count)
                .ok()
        };
        let Some(grid) = grid else {
            self.minimap_cache = None;
            return "{}".to_string();
        };
        let value = serde_json::json!({
            "start_visual_row": grid.start_visual_row,
            "count": grid.count,
            "actual_line_count": grid.actual_line_count(),
            "lines": grid.lines.iter().map(|line| {
                serde_json::json!({
                    "logical_line_index": line.logical_line_index,
                    "visual_in_logical": line.visual_in_logical,
                    "char_offset_start": line.char_offset_start,
                    "char_offset_end": line.char_offset_end,
                    "total_cells": line.total_cells,
                    "non_whitespace_cells": line.non_whitespace_cells,
                    "dominant_style": line.dominant_style,
                    "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
                })
            }).collect::<Vec<_>>(),
        });
        let json = serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string());
        self.minimap_cache = Some(MinimapCache {
            view_version,
            start_visual_row,
            count,
            json: json.clone(),
        });
        json
    }

    /// Return all selections (including primary) as character-offset ranges, plus the primary index.
    ///
    /// Each range is inclusive-exclusive in Unicode scalar indices.
    pub fn selections_offsets(&self) -> (Vec<(usize, usize)>, usize) {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return (Vec::new(), 0);
        };

        let mut out = Vec::with_capacity(cursor.selections.len());
        for sel in cursor.selections {
            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if a <= b {
                out.push((a, b));
            } else {
                out.push((b, a));
            }
        }
        (out, cursor.primary_selection_index)
    }

    /// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
    ///
    /// This is intended for clipboard "cut" behavior.
    pub fn delete_selections_only(&mut self) -> Result<(), UiError> {
        // 复用 core 的 `InsertText` 逻辑：用空字符串替换各个 selection，
        // 对空 caret 则是 no-op，从而实现“只删选区不动 caret”的 cut 语义。
        self.exec_core(Command::Edit(EditCommand::InsertText {
            text: String::new(),
        }))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    /// Replace the current selection set (including primary) from character-offset ranges.
    ///
    /// Notes:
    /// - Ranges are inclusive-exclusive, in Unicode scalar indices.
    /// - Empty ranges represent carets.
    pub fn set_selections_offsets(
        &mut self,
        ranges: &[(usize, usize)],
        primary_index: usize,
    ) -> Result<(), UiError> {
        if ranges.is_empty() {
            return Err(UiError::Processor(
                "set_selections_offsets requires a non-empty selection list".to_string(),
            ));
        }

        let selections = self.with_line_index(|line_index| {
            let mut selections: Vec<Selection> = Vec::with_capacity(ranges.len());
            for (start, end) in ranges {
                let (start_line, start_col) = line_index.char_offset_to_position(*start);
                let (end_line, end_col) = line_index.char_offset_to_position(*end);
                let start_pos = Position::new(start_line, start_col);
                let end_pos = Position::new(end_line, end_col);
                selections.push(Selection {
                    start: start_pos,
                    end: end_pos,
                    direction: SelectionDirection::Forward,
                });
            }
            selections
        })?;

        self.exec_core(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    pub fn clear_secondary_selections(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ClearSecondarySelections))?;
        Ok(())
    }

    pub fn add_cursor_above(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddCursorAbove))?;
        Ok(())
    }

    pub fn add_cursor_below(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddCursorBelow))?;
        Ok(())
    }

    pub fn add_next_occurrence(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddNextOccurrence {
            options,
        }))?;
        Ok(())
    }

    pub fn add_all_occurrences(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddAllOccurrences {
            options,
        }))?;
        Ok(())
    }

    pub fn select_word(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::SelectWord))?;
        Ok(())
    }

    fn word_unit_range_at_char_offset(
        &mut self,
        char_offset: usize,
    ) -> Result<(usize, usize), UiError> {
        let (line, column) = self.char_offset_to_logical_position(char_offset);
        self.exec_core(Command::Cursor(CursorCommand::MoveTo { line, column }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.select_word()?;
        Ok(self.primary_selection_offsets())
    }

    pub fn select_line(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::SelectLine))?;
        Ok(())
    }

    /// 按行扩展选择：给定 anchor/active 两个 char offset，选择覆盖它们所在行的并集。
    ///
    /// 语义类似 “三击选中行后拖拽按行扩展”：
    /// - start 为最上面一行的行首
    /// - end 尽量包含最下面一行的换行（若存在下一行）
    pub fn set_line_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (line_count, a_line, b_line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);
            (line_count, a_line, b_line)
        })?;
        if line_count == 0 {
            return Ok(());
        }

        let start_line = a_line.min(b_line);
        let end_line = a_line.max(b_line);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    /// 选择一个“段落”（以空行分隔的连续行块）。
    ///
    /// - 段落定义：连续的“空行”或连续的“非空行”构成一个段落。
    /// - 选区行为：类似 `SelectLine`，会尽量包含段落末尾的换行（若存在下一行）。
    pub fn select_paragraph_at_char_offset(&mut self, char_offset: usize) -> Result<(), UiError> {
        let (line_count, line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (line, _col) = line_index.char_offset_to_position(char_offset);
            (line_count, line)
        })?;
        if line_count == 0 {
            return Ok(());
        }
        let (start_line, end_line) = self.paragraph_line_range_for_line(line);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    /// 按段落扩展选择：给定 anchor/active 两个 char offset，选择覆盖它们所在段落的并集。
    pub fn set_paragraph_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (line_count, a_line, b_line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);
            (line_count, a_line, b_line)
        })?;
        if line_count == 0 {
            return Ok(());
        }

        let (a_start, a_end) = self.paragraph_line_range_for_line(a_line);
        let (b_start, b_end) = self.paragraph_line_range_for_line(b_line);

        let start_line = a_start.min(b_start);
        let end_line = a_end.max(b_end);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    pub fn expand_selection(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ExpandSelection))?;
        Ok(())
    }

    pub fn expand_selection_by(
        &mut self,
        unit: ExpandSelectionUnit,
        count: usize,
        direction: ExpandSelectionDirection,
    ) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit,
            count,
            direction,
        }))?;
        Ok(())
    }

    pub fn set_rect_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (a_line, a_col, b_line, b_col) = self.with_line_index(|line_index| {
            let (a_line, a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, b_col) = line_index.char_offset_to_position(active_offset);
            (a_line, a_col, b_line, b_col)
        })?;
        self.exec_core(Command::Cursor(CursorCommand::SetRectSelection {
            anchor: Position::new(a_line, a_col),
            active: Position::new(b_line, b_col),
        }))?;
        Ok(())
    }

    pub fn add_caret_at_char_offset(
        &mut self,
        char_offset: usize,
        make_primary: bool,
    ) -> Result<(), UiError> {
        let (line, column) =
            self.with_line_index(|line_index| line_index.char_offset_to_position(char_offset))?;
        let pos = Position::new(line, column);

        let cursor = self.cursor_state();
        let mut selections = cursor.selections;
        selections.push(Selection {
            start: pos,
            end: pos,
            direction: SelectionDirection::Forward,
        });

        let primary_index = if make_primary {
            selections.len().saturating_sub(1)
        } else {
            cursor.primary_selection_index
        };

        self.exec_core(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    #[allow(dead_code)]
    fn is_blank_line(&self, line: usize) -> bool {
        self.with_line_index(|idx| {
            idx.get_line_text(line)
                .unwrap_or_default()
                .trim()
                .is_empty()
        })
        .unwrap_or(true)
    }

    fn paragraph_line_range_for_line(&self, line: usize) -> (usize, usize) {
        self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return (0, 0);
            }

            let mut start = line.min(line_count.saturating_sub(1));
            let mut end = start;

            let want_blank = line_index
                .get_line_text(start)
                .unwrap_or_default()
                .trim()
                .is_empty();

            while start > 0
                && line_index
                    .get_line_text(start - 1)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                    == want_blank
            {
                start -= 1;
            }

            while end + 1 < line_count
                && line_index
                    .get_line_text(end + 1)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                    == want_blank
            {
                end += 1;
            }

            (start, end)
        })
        .unwrap_or((0, 0))
    }

    fn paragraph_offsets_for_line_range(
        &self,
        start_line: usize,
        end_line: usize,
    ) -> (usize, usize) {
        self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return (0, 0);
            }

            let start_line = start_line.min(line_count.saturating_sub(1));
            let end_line = end_line.min(line_count.saturating_sub(1));

            let start = line_index.position_to_char_offset(start_line, 0);
            let end = if end_line + 1 < line_count {
                line_index.position_to_char_offset(end_line + 1, 0)
            } else {
                let line_text = line_index.get_line_text(end_line).unwrap_or_default();
                line_index.position_to_char_offset(end_line, line_text.chars().count())
            };

            (start, end)
        })
        .unwrap_or((0, 0))
    }

    /// Return the current IME marked text range as `(start, len)` in character offsets.
    pub fn marked_range(&self) -> Option<(usize, usize)> {
        self.marked.as_ref().map(|m| (m.start, m.len))
    }

    /// Map a character offset (Unicode scalar index) to logical `(line, column)`.
    ///
    /// Notes:
    /// - `line` and `column` are also counted in Unicode scalar values (Rust `char`s).
    /// - `char_offset` is clamped to the document length.
    pub fn char_offset_to_logical_position(&self, char_offset: usize) -> (usize, usize) {
        let doc = self.lock_doc();
        let doc_len = doc.ws.buffer_char_count(self.buffer_id).unwrap_or(0);
        let off = char_offset.min(doc_len);
        doc.ws
            .buffer_line_index(self.buffer_id)
            .ok()
            .map(|idx| idx.char_offset_to_position(off))
            .unwrap_or((0, 0))
    }

    /// Map a character offset (Unicode scalar index) to visual `(row, x_cells)`.
    pub fn char_offset_to_visual(&mut self, char_offset: usize) -> Option<(usize, usize)> {
        let (line, column) = self.char_offset_to_logical_position(char_offset);
        let mut doc = self.lock_doc();
        doc.ws
            .logical_to_visual_for_view(self.view_id, line, column)
            .ok()
            .flatten()
    }

    /// Map a visual `(row, x_cells)` position to a character offset.
    pub fn visual_to_char_offset(&mut self, row: usize, x_cells: usize) -> Option<usize> {
        let mut doc = self.lock_doc();
        let pos = doc
            .ws
            .visual_position_to_logical_for_view(self.view_id, row, x_cells)
            .ok()??;
        doc.ws
            .buffer_line_index(self.buffer_id)
            .ok()
            .map(|idx| idx.position_to_char_offset(pos.line, pos.column))
    }

    /// Map a character offset to a point in the view coordinate space (pixels).
    ///
    /// - `x_px` is left-to-right (in pixels)
    /// - `y_px` is top-to-bottom (in pixels), aligned to the top of the visual row
    pub fn char_offset_to_view_point_px(&mut self, char_offset: usize) -> Option<(f32, f32)> {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        if self.has_virtual_text_decorations() {
            let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
            let local_row = composed_line_index_for_offset(&grid, char_offset)?;
            let x_cells = caret_x_cells_in_composed_line(&grid.lines[local_row], char_offset);

            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let x_px = self.render_config.padding_x_px
                + gutter_px
                + x_cells as f32 * self.render_config.cell_width_px;
            let y_px = self.render_config.padding_y_px
                + local_row as f32 * self.render_config.line_height_px
                - scroll_y_px;
            return Some((x_px, y_px));
        }

        let (row, x_cells) = self.char_offset_to_visual(char_offset)?;
        let local_row = row.saturating_sub(viewport.scroll_top);

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x_px = self.render_config.padding_x_px
            + gutter_px
            + x_cells as f32 * self.render_config.cell_width_px;
        let y_px = self.render_config.padding_y_px
            + local_row as f32 * self.render_config.line_height_px
            - scroll_y_px;
        Some((x_px, y_px))
    }

    /// Hit-test a point in the view coordinate space (pixels, top-left origin) and return the
    /// corresponding character offset (Unicode scalar index).
    pub fn view_point_to_char_offset(&mut self, x_px: f32, y_px: f32) -> Option<usize> {
        if self.has_virtual_text_decorations() {
            let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
            if grid.lines.is_empty() {
                return Some(0);
            }

            let (local_row, x_cells) = self.pixel_to_local_row_col(x_px, y_px);
            let local_row = local_row.min(grid.lines.len().saturating_sub(1));
            let line = &grid.lines[local_row];
            return Some(hit_test_composed_line_char_offset(line, x_cells));
        }

        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        self.visual_to_char_offset(row, x_cells)
    }

    /// Hit-test and return the raw LSP `DocumentLink` JSON (if any) at the given character offset.
    ///
    /// Notes:
    /// - Offsets are Unicode scalar indices.
    /// - Uses `DecorationLayerId::DOCUMENT_LINKS` and returns the `data_json` payload embedded by
    ///   `editor-core-lsp`.
    pub fn document_link_json_at_char_offset(&self, char_offset: usize) -> Option<String> {
        let doc = self.lock_doc();
        let layer = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .ok()?
            .get(&DecorationLayerId::DOCUMENT_LINKS)?;

        let mut best: Option<&editor_core::Decoration> = None;
        let mut best_len: usize = usize::MAX;

        for d in layer {
            if d.kind != DecorationKind::DocumentLink {
                continue;
            }
            let contains = if d.range.start == d.range.end {
                char_offset == d.range.start
            } else {
                char_offset >= d.range.start && char_offset < d.range.end
            };
            if !contains {
                continue;
            }

            let len = d.range.end.saturating_sub(d.range.start);
            if len < best_len {
                best = Some(d);
                best_len = len;
            }
        }

        best.and_then(|d| d.data_json.clone())
    }

    /// Hit-test and return the raw LSP `DocumentLink` JSON (if any) at the given view point.
    pub fn document_link_json_at_view_point_px(&mut self, x_px: f32, y_px: f32) -> Option<String> {
        let off = self.view_point_to_char_offset(x_px, y_px)?;
        self.document_link_json_at_char_offset(off)
    }

    pub fn line_height_px(&self) -> f32 {
        self.render_config.line_height_px
    }

    pub fn set_theme(&mut self, theme: RenderTheme) {
        self.theme = theme;
    }

    pub fn set_style_colors(&mut self, styles: BTreeMap<u32, StyleColors>) {
        self.theme.styles = styles;
    }

    pub fn clear_style_colors(&mut self) {
        self.theme.styles.clear();
    }

    pub fn set_style_fonts(&mut self, fonts: BTreeMap<u32, StyleFont>) {
        self.theme.style_fonts = fonts;
    }

    pub fn clear_style_fonts(&mut self) {
        self.theme.style_fonts.clear();
    }

    pub fn set_chrome_theme(&mut self, chrome: ChromeTheme) {
        self.theme.styles.insert(
            GUTTER_BACKGROUND_STYLE_ID,
            StyleColors::new(None, Some(chrome.gutter_background)),
        );
        self.theme.styles.insert(
            GUTTER_FOREGROUND_STYLE_ID,
            StyleColors::new(Some(chrome.gutter_foreground), None),
        );
        self.theme.styles.insert(
            GUTTER_SEPARATOR_STYLE_ID,
            StyleColors::new(Some(chrome.gutter_separator), None),
        );
        self.theme.styles.insert(
            FOLD_MARKER_COLLAPSED_STYLE_ID,
            StyleColors::new(None, Some(chrome.fold_marker_collapsed)),
        );
        self.theme.styles.insert(
            FOLD_MARKER_EXPANDED_STYLE_ID,
            StyleColors::new(None, Some(chrome.fold_marker_expanded)),
        );
    }

    /// Replace the per-style text decoration mapping used by the renderer.
    ///
    /// This controls purely visual line effects (underline, double underline, squiggly underline,
    /// strikethrough). It does not affect document text, hit-testing, or selections.
    pub fn set_style_text_decorations(&mut self, decorations: BTreeMap<u32, TextDecorations>) {
        self.theme.text_decorations = decorations;
    }

    pub fn clear_style_text_decorations(&mut self) {
        self.theme.text_decorations.clear();
    }

    /// Replace match highlight ranges (e.g. search matches) as a dedicated overlay style layer.
    ///
    /// Notes:
    /// - Ranges are character offsets (Unicode scalar indices), half-open `[start, end)`.
    /// - Passing an empty slice clears the layer.
    pub fn set_match_highlights_offsets(&mut self, ranges: &[(usize, usize)]) {
        if ranges.is_empty() {
            let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::MATCH_HIGHLIGHTS,
            }]);
            return;
        }

        let doc_len = {
            let doc = self.lock_doc();
            doc.ws.buffer_char_count(self.buffer_id).unwrap_or(0)
        };
        let mut intervals: Vec<Interval> = Vec::with_capacity(ranges.len());
        for (start, end) in ranges {
            let s = (*start).min(doc_len);
            let e = (*end).min(doc_len);
            let (s, e) = if s <= e { (s, e) } else { (e, s) };
            if s < e {
                intervals.push(Interval::new(s, e, MATCH_HIGHLIGHT_STYLE_ID));
            }
        }
        let _ = self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::MATCH_HIGHLIGHTS,
            intervals,
        }]);
    }

    /// Set an active search query and update match highlights accordingly.
    ///
    /// Returns the number of matches found.
    ///
    /// Notes:
    /// - This is intentionally a "UI-level convenience" API. It does not affect the core cursor
    ///   find/replace commands; it only updates the `MATCH_HIGHLIGHTS` style layer for rendering.
    /// - Passing an empty query clears match highlights.
    pub fn search_set_query(
        &mut self,
        query: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        if query.is_empty() {
            self.search_query = None;
            self.set_match_highlights_offsets(&[]);
            return Ok(0);
        }

        self.search_query = Some(SearchQueryState {
            query: query.to_string(),
            options,
        });
        self.search_refresh_matches()
    }

    /// Clear active search query and match highlights.
    pub fn search_clear(&mut self) {
        self.search_query = None;
        self.set_match_highlights_offsets(&[]);
    }

    /// Refresh match highlights for the current search query (if any).
    ///
    /// Returns the number of matches found.
    pub fn search_refresh_matches(&mut self) -> Result<usize, UiError> {
        let Some(q) = self.search_query.as_ref() else {
            self.set_match_highlights_offsets(&[]);
            return Ok(0);
        };

        let text = {
            let doc = self.lock_doc();
            doc.ws
                .buffer_text(self.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        let matches = editor_core::search::find_all(&text, q.query.as_str(), q.options)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        let ranges: Vec<(usize, usize)> = matches.iter().map(|m| (m.start, m.end)).collect();
        self.set_match_highlights_offsets(&ranges);
        Ok(matches.len())
    }

    /// Find next match and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    pub fn find_next(&mut self, query: &str, options: SearchOptions) -> Result<bool, UiError> {
        let result = self.exec_core(Command::Cursor(CursorCommand::FindNext {
            query: query.to_string(),
            options,
        }))?;
        Ok(matches!(result, CommandResult::SearchMatch { .. }))
    }

    /// Find previous match and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    pub fn find_prev(&mut self, query: &str, options: SearchOptions) -> Result<bool, UiError> {
        let result = self.exec_core(Command::Cursor(CursorCommand::FindPrev {
            query: query.to_string(),
            options,
        }))?;
        Ok(matches!(result, CommandResult::SearchMatch { .. }))
    }

    /// Replace the current match (based on selection/caret) and return the number of replacements performed.
    pub fn replace_current(
        &mut self,
        query: &str,
        replacement: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        let result = self.exec_core(Command::Edit(EditCommand::ReplaceCurrent {
            query: query.to_string(),
            replacement: replacement.to_string(),
            options,
        }))?;
        self.refresh_processing()?;
        match result {
            CommandResult::ReplaceResult { replaced } => Ok(replaced),
            _ => Ok(0),
        }
    }

    /// Replace all matches and return the number of replacements performed.
    pub fn replace_all(
        &mut self,
        query: &str,
        replacement: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        let result = self.exec_core(Command::Edit(EditCommand::ReplaceAll {
            query: query.to_string(),
            replacement: replacement.to_string(),
            options,
        }))?;
        self.refresh_processing()?;
        match result {
            CommandResult::ReplaceResult { replaced } => Ok(replaced),
            _ => Ok(0),
        }
    }

    pub fn set_sublime_syntax_yaml(&mut self, yaml: &str) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_str(yaml)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.sublime = Some(SublimeProcessor::new(syntax, set));
        }
        self.refresh_processing()
    }

    pub fn set_sublime_syntax_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_path(path)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.sublime = Some(SublimeProcessor::new(syntax, set));
        }
        self.refresh_processing()
    }

    pub fn disable_sublime_syntax(&mut self) {
        let mut doc = self.lock_doc();
        doc.sublime = None;
    }

    pub fn sublime_scope_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.sublime
            .as_ref()
            .and_then(|p| p.scope_mapper.scope_for_style_id(style_id))
            .map(|s| s.to_string())
    }

    pub fn sublime_style_id_for_scope(&mut self, scope: &str) -> Result<u32, UiError> {
        let mut doc = self.lock_doc();
        let Some(proc) = doc.sublime.as_mut() else {
            return Err(UiError::Processor(
                "sublime syntax processor is not enabled".to_string(),
            ));
        };
        Ok(proc.scope_mapper.style_id_for_scope(scope))
    }

    /// Replace the Tree-sitter registry for this document with a schema-versioned JSON string.
    ///
    /// This is designed for Swift ↔ Rust FFI where passing maps directly is inconvenient.
    pub fn set_treesitter_registry_json(&mut self, registry_json: &str) -> Result<(), UiError> {
        let registry = TreeSitterRegistry::from_json_str(registry_json)
            .map_err(|e: TreeSitterRegistryError| UiError::Processor(e.to_string()))?;
        let mut doc = self.lock_doc();
        doc.treesitter_registry = registry;
        Ok(())
    }

    /// Enable Tree-sitter highlighting/folding using the current registry and a Tree-sitter
    /// `language_id` (e.g. `"rust"`).
    pub fn set_treesitter_language(&mut self, language_id: &str) -> Result<(), UiError> {
        let language_config = {
            let doc = self.lock_doc();
            doc.treesitter_registry
                .languages
                .get(language_id)
                .cloned()
                .ok_or_else(|| {
                    UiError::Processor(format!(
                        "unknown tree-sitter language_id (not in registry): {language_id}"
                    ))
                })?
        };

        let indenter = load_indenter_config_from_config(language_id, &language_config)
            .ok()
            .flatten()
            .and_then(|cfg| {
                if cfg.indents_query.trim().is_empty() {
                    None
                } else {
                    TreeSitterIndenter::new(cfg).ok()
                }
            });

        let mut config = load_processor_config_from_config(language_id, &language_config)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        let capture_names = config
            .highlights_capture_names()
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let (capture_styles, runtime, text, version) = {
            let mut doc = self.lock_doc();
            let mut capture_styles = BTreeMap::<String, u32>::new();
            for name in &capture_names {
                let style_id = doc.treesitter_capture_mapper.style_id_for_capture(name);
                capture_styles.insert(name.to_string(), style_id);
            }

            doc.treesitter = None;
            doc.treesitter_indenter = None;
            doc.apply_processing_edits([
                ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::TREE_SITTER,
                },
                ProcessingEdit::ClearFoldingRegions,
            ])?;

            let text = doc
                .ws
                .buffer_text(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
            let version = doc.treesitter_doc_version;
            let runtime = doc.treesitter_processing_config;
            (capture_styles, runtime, text, version)
        };

        config.capture_styles = capture_styles;

        let mut worker = TreeSitterAsyncWorker::spawn();
        worker.requested_version = Some(version);
        worker
            .tx
            .send(TreeSitterWorkerMsg::Init {
                config,
                runtime,
                version,
                text,
                prefetch_char_range,
            })
            .map_err(|_| UiError::Processor("failed to start tree-sitter worker".to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.treesitter = Some(worker);
            doc.treesitter_indenter = indenter;
        }
        Ok(())
    }

    /// Enable Tree-sitter highlighting/folding for a file path by resolving the extension via
    /// the current registry.
    pub fn set_treesitter_for_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let language_id = {
            let doc = self.lock_doc();
            doc.treesitter_registry
                .language_id_for_path(path)
                .map(|s| s.to_string())
        }
        .ok_or_else(|| {
            UiError::Processor(format!(
                "no tree-sitter language_id mapped for path: {}",
                path.display()
            ))
        })?;

        self.set_treesitter_language(language_id.as_str())
    }

    /// Backwards-compatible alias: treat `pack_id` as `language_id`.
    pub fn set_treesitter_query_pack(&mut self, pack_id: &str) -> Result<(), UiError> {
        self.set_treesitter_language(pack_id)
    }

    /// Backwards-compatible alias: `rust` language id.
    pub fn set_treesitter_rust_default(&mut self) -> Result<(), UiError> {
        self.set_treesitter_language("rust")
    }

    pub fn disable_treesitter(&mut self) {
        let mut doc = self.lock_doc();
        doc.treesitter = None;
        doc.treesitter_indenter = None;
    }

    /// Enable an LSP session (stdio) for the current document.
    ///
    /// This is primarily intended for demos and simple hosts. It:
    /// - runs `initialize` / `initialized`
    /// - sends `textDocument/didOpen` with the current document text
    /// - keeps the server in sync via incremental `didChange` (based on `TextDelta`)
    /// - polls and applies derived state (semantic tokens, folding ranges, diagnostics)
    /// - additionally requests inlay hints / code lens / document links (demo UX)
    pub fn lsp_enable_stdio(
        &mut self,
        cmd: &str,
        args: &[String],
        root_uri: &str,
        doc_uri: &str,
        language_id: &str,
    ) -> Result<(), UiError> {
        // Clear any existing LSP-derived state first so a failed start doesn't leave stale
        // semantic tokens / diagnostics around.
        let initial_text = {
            let mut doc = self.lock_doc();
            doc.lsp_last_cmd = Some(cmd.to_string());
            doc.lsp_last_error = None;
            if doc.lsp.is_some() {
                doc.lsp_disable();
            }
            let _ = doc.apply_processing_edits(editor_core_lsp::lsp_clear_edits());
            doc.ws
                .buffer_text(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        let token_types = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_TYPES;
        let token_modifiers = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_MODIFIERS;

        // Build initialize params in the demo (caller-controlled). Consumers may override or
        // replace this entirely.
        let init_params = serde_json::json!({
            "processId": std::process::id(),
            "rootUri": root_uri,
            "capabilities": {
                "textDocument": {
                    "semanticTokens": {
                        "dynamicRegistration": false,
                        "requests": { "range": false, "full": { "delta": false } },
                        "tokenTypes": token_types,
                        "tokenModifiers": token_modifiers,
                        "formats": ["relative"],
                        "multilineTokenSupport": true,
                        "overlappingTokenSupport": false,
                    },
                    "foldingRange": {
                        "dynamicRegistration": false,
                        "lineFoldingOnly": true,
                    },
                    // Some servers gate these behind explicit capabilities.
                    "inlayHint": { "dynamicRegistration": false },
                    "codeLens": { "dynamicRegistration": false },
                    "documentLink": { "dynamicRegistration": false },
                },
            },
            "clientInfo": { "name": "editor-core ui" },
        });

        let mut cmd_proc = std::process::Command::new(cmd);
        cmd_proc.args(args);
        cmd_proc.stderr(Stdio::null());

        let start = LspSessionStartOptions {
            cmd: cmd_proc,
            // Single-document demo: keep workspace folder features disabled.
            workspace_folders: Vec::new(),
            initialize_params: init_params,
            initialize_timeout: Duration::from_secs(6),
            document: LspDocument {
                uri: doc_uri.to_string(),
                language_id: language_id.to_string(),
                version: 1,
            },
            initial_text: initial_text.clone(),
        };

        let key = SharedLspKey {
            cmd: cmd.to_string(),
            args: args.to_vec(),
            root_uri: root_uri.trim_end_matches('/').to_string(),
        };
        let shared = match get_or_start_shared_lsp_session(key, start) {
            Ok(shared) => shared,
            Err(err) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(err.to_string());
                return Err(err);
            }
        };

        // If this is not the first document in the shared session, open it explicitly.
        //
        // Note: for the very first document, `LspSession::start(...)` already didOpen'd it.
        let doc_uri = doc_uri.to_string();
        let language_id = language_id.to_string();
        let initial_text_clone = initial_text.clone();
        if let Err(err) = shared.with_session_mut(|session| {
            if session.document_for_uri(doc_uri.as_str()).is_some() {
                return Ok(());
            }
            session.open_document(
                LspDocument {
                    uri: doc_uri.clone(),
                    language_id,
                    version: 1,
                },
                initial_text_clone,
            )
        }) {
            let mut doc = self.lock_doc();
            doc.lsp_fail(err.clone());
            return Err(UiError::Processor(err));
        }

        {
            let mut doc = self.lock_doc();
            let buffer_id = doc.buffer_id;
            // Ensure the buffer is addressable by URI so workspace-wide LSP edits (formatting,
            // rename, code actions, workspace/applyEdit, ...) can be routed correctly.
            doc.ws
                .set_buffer_uri(buffer_id, Some(doc_uri.clone()))
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            doc.lsp = Some(shared);
            doc.lsp_document_uri = Some(doc_uri);
            doc.lsp_delta_calc = Some(DeltaCalculator::from_text(&initial_text));
            doc.lsp_aux_refresh_due = Some(Instant::now());
            doc.lsp_inlay_in_flight = false;
            doc.lsp_code_lens_in_flight = false;
            doc.lsp_document_links_in_flight = false;
            doc.lsp_client_requests.clear();
            doc.lsp_clear_result_state();
            doc.lsp_latest_on_type_formatting_request_id.clear();
        }
        Ok(())
    }

    pub fn lsp_disable(&mut self) {
        let mut doc = self.lock_doc();
        doc.lsp_disable();
    }

    pub fn lsp_is_enabled(&self) -> bool {
        let doc = self.lock_doc();
        doc.lsp_is_enabled()
    }

    /// Return a best-effort LSP status snapshot as a JSON string.
    ///
    /// This is intended for UI status bars and debugging overlays. The schema is stable-ish but
    /// not yet versioned; callers should treat unknown fields as optional.
    pub fn lsp_status_json(&self) -> String {
        let (shared, last_cmd, last_error) = {
            let doc = self.lock_doc();
            (
                doc.lsp.clone(),
                doc.lsp_last_cmd.clone(),
                doc.lsp_last_error.clone(),
            )
        };

        let mut availability = "disabled";
        let mut state = "disabled";
        let mut detail: Option<String> = None;
        let mut server: Option<serde_json::Value> = None;
        let mut activity: Option<serde_json::Value> = None;
        let mut capabilities: Option<serde_json::Value> = None;

        if let Some(shared) = shared {
            match shared.session.lock() {
                Ok(guard) => {
                    if let Some(session) = guard.as_ref() {
                        let s = session.status();
                        availability = "enabled";
                        state = match s.state {
                            editor_core_lsp::LspWorkState::Ready => "ready",
                            editor_core_lsp::LspWorkState::Indexing => "indexing",
                            editor_core_lsp::LspWorkState::Busy => "busy",
                        };

                        server = Some(serde_json::json!({
                            "name": s.server.name,
                            "version": s.server.version,
                            "command": s.server.command,
                            "args": s.server.args,
                        }));

                        activity = s.activity.map(|a| {
                            serde_json::json!({
                                "title": a.title,
                                "message": a.message,
                                "percentage": a.percentage,
                            })
                        });

                        capabilities = Some(serde_json::json!({
                            "semantic_tokens": s.capabilities.semantic_tokens,
                            "semantic_tokens_delta": s.capabilities.semantic_tokens_delta,
                            "completion_item_resolve": s.capabilities.completion_item_resolve,
                            "folding_ranges": s.capabilities.folding_ranges,
                            "on_type_formatting": s.capabilities.on_type_formatting,
                        }));
                    } else {
                        availability = "failed";
                        state = "failed";
                        detail = last_error
                            .clone()
                            .or_else(|| Some("LSP session is not available".to_string()));
                        if let Some(cmd) = last_cmd.as_deref() {
                            server = Some(serde_json::json!({ "command": cmd }));
                        }
                    }
                }
                Err(_) => {
                    availability = "failed";
                    state = "failed";
                    detail = Some("LSP session lock poisoned".to_string());
                    if let Some(cmd) = last_cmd.as_deref() {
                        server = Some(serde_json::json!({ "command": cmd }));
                    }
                }
            }
        } else if let Some(err) = last_error.clone() {
            availability = "failed";
            state = "failed";
            detail = Some(err);
            if let Some(cmd) = last_cmd.as_deref() {
                server = Some(serde_json::json!({ "command": cmd }));
            }
        } else if let Some(cmd) = last_cmd.as_deref() {
            server = Some(serde_json::json!({ "command": cmd }));
        }

        serde_json::json!({
            "availability": availability,
            "state": state,
            "server": server,
            "activity": activity,
            "detail": detail,
            "capabilities": capabilities,
        })
        .to_string()
    }

    fn lsp_request_position_result(
        &mut self,
        slot: LspResultSlot,
        line: usize,
        column: usize,
        request: impl FnOnce(
            &mut LspSession,
            &editor_core::LineIndex,
            usize,
            usize,
        ) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp, line_index, line, column)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_request_document_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_request_with_line_index_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession, &editor_core::LineIndex) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp, line_index)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_take_last_result_json(&mut self, slot: LspResultSlot) -> Option<String> {
        let mut doc = self.lock_doc();
        doc.lsp_last_result_json.remove(&(self.view_id, slot))
    }

    /// Request LSP hover information for a given logical position (0-based line/column in Unicode scalars).
    ///
    /// The result is delivered asynchronously via `poll_processing` and can be read by calling
    /// [`Self::lsp_take_last_hover_result_json`].
    pub fn lsp_request_hover(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Hover,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_hover(line_index, line, column),
        )
    }

    pub fn lsp_take_last_hover_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Hover)
    }

    /// Request LSP go-to-definition for a given logical position (0-based line/column in Unicode scalars).
    ///
    /// The result is delivered asynchronously via `poll_processing` and can be read by calling
    /// [`Self::lsp_take_last_definition_result_json`].
    pub fn lsp_request_definition(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Definition,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_definition(line_index, line, column),
        )
    }

    pub fn lsp_take_last_definition_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Definition)
    }

    pub fn lsp_request_declaration(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Declaration,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_declaration(line_index, line, column),
        )
    }

    pub fn lsp_take_last_declaration_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Declaration)
    }

    pub fn lsp_request_type_definition(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::TypeDefinition,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_type_definition(line_index, line, column),
        )
    }

    pub fn lsp_take_last_type_definition_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeDefinition)
    }

    pub fn lsp_request_implementation(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Implementation,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_implementation(line_index, line, column),
        )
    }

    pub fn lsp_take_last_implementation_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Implementation)
    }

    pub fn lsp_request_references(
        &mut self,
        line: usize,
        column: usize,
        include_declaration: bool,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::References,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_references(line_index, line, column, include_declaration)
            },
        )
    }

    pub fn lsp_take_last_references_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::References)
    }

    pub fn lsp_request_completion(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Completion,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_completion(line_index, line, column),
        )
    }

    pub fn lsp_take_last_completion_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Completion)
    }

    pub fn lsp_request_completion_item_resolve(&mut self, item_json: &str) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CompletionResolve, |lsp| {
            lsp.request_completion_item_resolve(item)
        })
    }

    pub fn lsp_take_last_completion_item_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CompletionResolve)
    }

    pub fn lsp_request_signature_help(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::SignatureHelp,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_signature_help(line_index, line, column),
        )
    }

    pub fn lsp_take_last_signature_help_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SignatureHelp)
    }

    pub fn lsp_request_prepare_rename(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareRename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_prepare_rename(line_index, line, column),
        )
    }

    pub fn lsp_take_last_prepare_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareRename)
    }

    pub fn lsp_request_rename(
        &mut self,
        line: usize,
        column: usize,
        new_name: &str,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Rename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_rename(line_index, line, column, new_name),
        )
    }

    pub fn lsp_take_last_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Rename)
    }

    pub fn lsp_request_code_action(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        context_json: &str,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let context: serde_json::Value = if context_json.trim().is_empty() {
            serde_json::json!({ "diagnostics": [] })
        } else {
            serde_json::from_str(context_json).map_err(|e| UiError::Processor(e.to_string()))?
        };

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let start = start_offset.min(end_offset);
        let end = start_offset.max(end_offset);
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                lsp.request_code_action(line_index, start, end, context)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, LspResultSlot::CodeAction), id);
        doc.lsp_last_result_json
            .remove(&(self.view_id, LspResultSlot::CodeAction));
        Ok(id)
    }

    pub fn lsp_take_last_code_action_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeAction)
    }

    pub fn lsp_request_code_action_resolve(&mut self, action_json: &str) -> Result<u64, UiError> {
        let action: serde_json::Value =
            serde_json::from_str(action_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeActionResolve, |lsp| {
            lsp.request_code_action_resolve(action)
        })
    }

    pub fn lsp_take_last_code_action_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeActionResolve)
    }

    pub fn lsp_request_execute_command(&mut self, command_json: &str) -> Result<u64, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(command_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let command = value
            .get("command")
            .and_then(serde_json::Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| UiError::Processor("workspace command missing".to_string()))?;
        let arguments = value
            .get("arguments")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();
        let command = command.to_string();

        self.lsp_request_document_result(LspResultSlot::ExecuteCommand, |lsp| {
            lsp.request_execute_command(command, arguments)
        })
    }

    pub fn lsp_take_last_execute_command_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ExecuteCommand)
    }

    pub fn lsp_request_code_lens_resolve(&mut self, lens_json: &str) -> Result<u64, UiError> {
        let lens: serde_json::Value =
            serde_json::from_str(lens_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeLensResolve, |lsp| {
            lsp.request_code_lens_resolve(lens)
        })
    }

    pub fn lsp_take_last_code_lens_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeLensResolve)
    }

    pub fn lsp_request_document_symbols(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentSymbols, |lsp| {
            lsp.request_document_symbols()
        })
    }

    pub fn lsp_take_last_document_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentSymbols)
    }

    pub fn lsp_request_workspace_symbols(&mut self, query: &str) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::WorkspaceSymbols, |lsp| {
            lsp.request_workspace_symbol(query)
        })
    }

    pub fn lsp_take_last_workspace_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceSymbols)
    }

    pub fn lsp_request_folding_ranges(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::FoldingRanges, |lsp| {
            lsp.request_folding_ranges()
        })
    }

    pub fn lsp_take_last_folding_ranges_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::FoldingRanges)
    }

    pub fn lsp_request_selection_range(&mut self, positions_json: &str) -> Result<u64, UiError> {
        let positions = parse_lsp_position_list_json(positions_json)?;
        self.lsp_request_with_line_index_result(LspResultSlot::SelectionRange, |lsp, line_index| {
            lsp.request_selection_range(line_index, &positions)
        })
    }

    pub fn lsp_take_last_selection_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SelectionRange)
    }

    pub fn lsp_request_linked_editing_range(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::LinkedEditingRange,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_linked_editing_range(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_linked_editing_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::LinkedEditingRange)
    }

    pub fn lsp_request_document_diagnostic(
        &mut self,
        previous_result_id: Option<&str>,
    ) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentDiagnostic, |lsp| {
            lsp.request_document_diagnostic(previous_result_id.map(str::to_string))
        })
    }

    pub fn lsp_take_last_document_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentDiagnostic)
    }

    pub fn lsp_request_workspace_diagnostic(
        &mut self,
        previous_result_ids_json: &str,
    ) -> Result<u64, UiError> {
        let previous_result_ids = parse_lsp_json_array(
            previous_result_ids_json,
            "workspace diagnostic previousResultIds",
        )?;
        self.lsp_request_document_result(LspResultSlot::WorkspaceDiagnostic, |lsp| {
            lsp.request_workspace_diagnostic(previous_result_ids)
        })
    }

    pub fn lsp_take_last_workspace_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceDiagnostic)
    }

    pub fn lsp_request_document_color(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentColor, |lsp| {
            lsp.request_document_color()
        })
    }

    pub fn lsp_take_last_document_color_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentColor)
    }

    pub fn lsp_request_color_presentation(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        color_json: &str,
    ) -> Result<u64, UiError> {
        let color: serde_json::Value =
            serde_json::from_str(color_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_with_line_index_result(
            LspResultSlot::ColorPresentation,
            |lsp, line_index| {
                let range = lsp.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
                lsp.request_color_presentation(&range, color)
            },
        )
    }

    pub fn lsp_take_last_color_presentation_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ColorPresentation)
    }

    pub fn lsp_request_prepare_call_hierarchy(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareCallHierarchy,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_prepare_call_hierarchy(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_prepare_call_hierarchy_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareCallHierarchy)
    }

    pub fn lsp_request_call_hierarchy_incoming_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyIncoming, |lsp| {
            lsp.request_call_hierarchy_incoming_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_incoming_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyIncoming)
    }

    pub fn lsp_request_call_hierarchy_outgoing_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyOutgoing, |lsp| {
            lsp.request_call_hierarchy_outgoing_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_outgoing_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyOutgoing)
    }

    pub fn lsp_request_prepare_type_hierarchy(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareTypeHierarchy,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_prepare_type_hierarchy(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_prepare_type_hierarchy_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareTypeHierarchy)
    }

    pub fn lsp_request_type_hierarchy_supertypes(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::TypeHierarchySupertypes, |lsp| {
            lsp.request_type_hierarchy_supertypes(item)
        })
    }

    pub fn lsp_take_last_type_hierarchy_supertypes_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeHierarchySupertypes)
    }

    pub fn lsp_request_type_hierarchy_subtypes(&mut self, item_json: &str) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::TypeHierarchySubtypes, |lsp| {
            lsp.request_type_hierarchy_subtypes(item)
        })
    }

    pub fn lsp_take_last_type_hierarchy_subtypes_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeHierarchySubtypes)
    }

    fn maybe_request_lsp_on_type_formatting(&mut self, ch: &str) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();

        let (shared, doc_uri, line_index, line, column, options, request_version) = {
            let mut doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Ok(false);
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(false);
            };

            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();

            let pos = doc
                .ws
                .cursor_position_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let indent_config = doc
                .ws
                .indentation_config_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let tab_width = doc.ws.tab_width_for_view(self.view_id).unwrap_or(4);
            let options = editor_core_lsp::lsp_formatting_options_for_indentation_config(
                &indent_config,
                tab_width,
            );

            (
                shared,
                doc_uri,
                line_index,
                pos.line,
                pos.column,
                options,
                doc.text_version,
            )
        };

        let supports =
            match shared.with_session_mut(|lsp| Ok(lsp.supports_on_type_formatting_trigger(ch))) {
                Ok(v) => v,
                Err(reason) => {
                    let mut doc = self.lock_doc();
                    doc.lsp_fail(reason);
                    return Ok(false);
                }
            };
        if !supports {
            return Ok(false);
        }

        let request_id = match shared.with_session_mut(|lsp| {
            lsp.set_active_document(doc_uri.as_str())?;
            lsp.request_on_type_formatting(&line_index, line, column, ch.to_string(), options)
        }) {
            Ok(id) => id,
            Err(reason) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(reason);
                return Ok(false);
            }
        };

        let mut doc = self.lock_doc();
        doc.lsp_client_requests.insert(
            request_id,
            LspClientRequest::OnTypeFormatting {
                view: self.view_id,
                version: request_version,
            },
        );
        doc.lsp_latest_on_type_formatting_request_id
            .insert(self.view_id, request_id);

        Ok(true)
    }

    fn maybe_apply_treesitter_indent_for_primary_caret_line(&mut self) -> Result<bool, UiError> {
        let applied = {
            let mut doc = self.lock_doc();
            if doc.treesitter_indenter.is_none() {
                return Ok(false);
            }

            let buffer_id = doc.buffer_id;
            let version = doc.text_version;
            let text = doc
                .ws
                .buffer_text(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let pos = doc
                .ws
                .cursor_position_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_config = doc
                .ws
                .indentation_config_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_style = indent_config.style;

            let Some(indenter) = doc.treesitter_indenter.as_mut() else {
                return Ok(false);
            };

            indenter
                .sync_to_text(version, text.as_str())
                .map_err(|e| UiError::Processor(e.to_string()))?;

            let Some(edit) = indenter.reindent_text_edit_for_line(pos.line, indent_style) else {
                return Ok(false);
            };

            doc.ws
                .apply_text_edits(vec![(buffer_id, vec![edit])])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            true
        };

        if applied {
            self.refresh_processing()?;
        }
        Ok(applied)
    }

    fn wait_lsp_text_edit_response_and_apply(
        &mut self,
        shared: &Arc<SharedLspSession>,
        request_id: u64,
        timeout_ms: u32,
        error_context: &str,
        buffer_id: BufferId,
    ) -> Result<bool, UiError> {
        let resp = shared
            .with_session_mut(|lsp| {
                lsp.wait_for_response(request_id, Duration::from_millis(timeout_ms as u64))
            })
            .map_err(UiError::Processor)?;

        if let Some(err) = resp.get("error") {
            return Err(UiError::Processor(format!("{error_context} failed: {err}")));
        }

        let result = resp
            .get("result")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        self.lsp_apply_text_edits_value(buffer_id, &result)
    }

    /// Format the active document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// This is a "turnkey" helper intended for editor commands (explicit user actions).
    /// It blocks for up to `timeout_ms` while waiting for the response.
    ///
    /// Returns `true` if any text edits were applied.
    pub fn lsp_format_document(
        &mut self,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            (shared, doc_uri, doc.buffer_id)
        };

        // 1) Issue request.
        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_formatting(options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP formatting",
            buffer_id,
        )
    }

    /// Format a range in the active document via LSP (`textDocument/rangeFormatting`).
    ///
    /// Offsets are editor-core char offsets. The response is applied to the current buffer.
    pub fn lsp_format_range(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;
        let (start_offset, end_offset) = if start_offset <= end_offset {
            (start_offset, end_offset)
        } else {
            (end_offset, start_offset)
        };

        let (shared, doc_uri, buffer_id, line_index) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            (shared, doc_uri, doc.buffer_id, line_index)
        };

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_range_formatting(&line_index, start_offset, end_offset, options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP range formatting",
            buffer_id,
        )
    }

    /// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits.
    ///
    /// `line` and `column` are logical editor positions after the trigger character was inserted.
    pub fn lsp_format_on_type(
        &mut self,
        line: usize,
        column: usize,
        ch: &str,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        if ch.is_empty() {
            return Err(UiError::Processor(
                "LSP on-type formatting trigger is empty".to_string(),
            ));
        }

        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id, line_index) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            (shared, doc_uri, doc.buffer_id, line_index)
        };

        let supports = shared
            .with_session_mut(|lsp| Ok(lsp.supports_on_type_formatting_trigger(ch)))
            .map_err(UiError::Processor)?;
        if !supports {
            return Ok(false);
        }

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_on_type_formatting(&line_index, line, column, ch.to_string(), options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP on-type formatting",
            buffer_id,
        )
    }

    pub fn poll_processing(&mut self) -> Result<ProcessingPollResult, UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let (treesitter_pending, latest_to_apply) = {
            let mut doc = self.lock_doc();
            if doc.treesitter.is_none() {
                drop(doc);
                let lsp_applied = self.poll_lsp_best_effort()?;
                return Ok(ProcessingPollResult {
                    applied: lsp_applied,
                    pending: self.lsp_is_enabled(),
                });
            }

            let mut latest: Option<(u64, Vec<ProcessingEdit>, TreeSitterUpdateMode)> = None;
            let mut need_full_sync = false;

            loop {
                let ev = {
                    let Some(worker) = doc.treesitter.as_mut() else {
                        return Err(UiError::Processor(
                            "tree-sitter worker missing during processing poll".to_string(),
                        ));
                    };
                    worker.rx.try_recv()
                };
                match ev {
                    Ok(TreeSitterWorkerEvent::Processed {
                        version,
                        edits,
                        update_mode,
                    }) => {
                        latest = Some((version, edits, update_mode));
                    }
                    Ok(TreeSitterWorkerEvent::NeedFullSync) => {
                        need_full_sync = true;
                    }
                    Ok(TreeSitterWorkerEvent::Error(msg)) => {
                        return Err(UiError::Processor(format!(
                            "tree-sitter worker error: {msg}"
                        )));
                    }
                    Err(mpsc::TryRecvError::Empty) => break,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        return Err(UiError::Processor(
                            "tree-sitter worker disconnected".to_string(),
                        ));
                    }
                }
            }

            if need_full_sync {
                let text = doc
                    .ws
                    .buffer_text(doc.buffer_id)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?;
                doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
                let version = doc.treesitter_doc_version;
                let Some(worker) = doc.treesitter.as_mut() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing during full sync".to_string(),
                    ));
                };
                worker.requested_version = Some(version);
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::FullSync {
                        version,
                        text,
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to full-sync tree-sitter worker".to_string())
                    })?;
            }

            let (requested, pending) = {
                let Some(worker) = doc.treesitter.as_ref() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing after processing poll".to_string(),
                    ));
                };
                (worker.requested_version, worker.is_pending())
            };

            let to_apply = latest.and_then(|(version, edits, update_mode)| {
                if requested.is_some_and(|requested| version < requested) {
                    None
                } else {
                    Some((version, edits, update_mode))
                }
            });

            (pending, to_apply)
        };

        let mut treesitter_applied = false;
        if let Some((version, edits, update_mode)) = latest_to_apply {
            {
                let mut doc = self.lock_doc();
                doc.apply_processing_edits(edits)?;
                if let Some(worker) = doc.treesitter.as_mut() {
                    worker.applied_version = Some(version);
                    worker.last_update_mode = Some(update_mode);
                }
            }
            treesitter_applied = true;
        }

        let lsp_applied = self.poll_lsp_best_effort()?;

        Ok(ProcessingPollResult {
            applied: treesitter_applied || lsp_applied,
            pending: treesitter_pending || self.lsp_is_enabled(),
        })
    }

    pub fn treesitter_last_update_mode(&self) -> Option<TreeSitterUpdateMode> {
        let doc = self.lock_doc();
        doc.treesitter.as_ref().and_then(|w| w.last_update_mode)
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .capture_for_style_id(style_id)
            .map(|s| s.to_string())
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        let mut doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .style_id_for_capture(capture_name)
    }

    pub fn lsp_apply_publish_diagnostics_json(&mut self, params_json: &str) -> Result<(), UiError> {
        let params_value: serde_json::Value =
            serde_json::from_str(params_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let notif = LspNotification::from_method_and_params(
            "textDocument/publishDiagnostics",
            &params_value,
        )
        .ok_or_else(|| UiError::Processor("invalid publishDiagnostics params".to_string()))?;

        let LspNotification::PublishDiagnostics(params) = notif else {
            return Err(UiError::Processor(
                "failed to parse publishDiagnostics params".to_string(),
            ));
        };

        let edits = self.with_line_index(|line_index| {
            lsp_diagnostics_to_processing_edits(line_index, &params)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }

    pub fn lsp_apply_semantic_tokens(&mut self, data: &[u32]) -> Result<(), UiError> {
        let intervals = self.with_line_index(|line_index| {
            semantic_tokens_to_intervals(data, line_index, encode_semantic_style_id)
                .map_err(|e| UiError::Processor(e.to_string()))
        })??;
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::SEMANTIC_TOKENS,
            intervals,
        }])?;
        Ok(())
    }

    /// Apply an LSP `TextEdit[] | null` payload to the current buffer.
    ///
    /// This is primarily intended for applying LSP formatting results in a UI-friendly way.
    ///
    /// Returns `true` if any edits were applied.
    pub fn lsp_apply_text_edits_json(&mut self, text_edits_json: &str) -> Result<bool, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(text_edits_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let buffer_id = {
            let doc = self.lock_doc();
            doc.buffer_id
        };
        self.lsp_apply_text_edits_value(buffer_id, &value)
    }

    fn lsp_apply_text_edits_value(
        &mut self,
        buffer_id: BufferId,
        value: &serde_json::Value,
    ) -> Result<bool, UiError> {
        let edits = text_edits_from_value(value);
        self.lsp_apply_lsp_text_edits(buffer_id, &edits)
    }

    pub fn lsp_apply_workspace_edit_json(
        &mut self,
        workspace_edit_json: &str,
        document_uri: Option<&str>,
    ) -> Result<String, UiError> {
        let value: serde_json::Value = serde_json::from_str(workspace_edit_json)
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let (buffer_id, current_uri) = {
            let doc = self.lock_doc();
            let uri = document_uri
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .or_else(|| doc.lsp_document_uri.clone())
                .ok_or_else(|| UiError::Processor("document URI missing".to_string()))?;
            (doc.buffer_id, uri)
        };

        let by_uri = workspace_edit_text_edits(&value);
        let target_edits = by_uri
            .get(current_uri.as_str())
            .cloned()
            .unwrap_or_default();
        let applied = self.lsp_apply_lsp_text_edits(buffer_id, &target_edits)?;

        let mut skipped_uris = by_uri
            .keys()
            .filter(|uri| uri.as_str() != current_uri.as_str())
            .cloned()
            .collect::<Vec<_>>();
        skipped_uris.sort();

        let summary = summarize_workspace_edit(&value);
        let documents = summary
            .documents
            .into_iter()
            .map(|doc| {
                serde_json::json!({
                    "uri": doc.uri,
                    "edit_count": doc.edit_count,
                    "has_overlapping_edits": doc.has_overlapping_edits,
                })
            })
            .collect::<Vec<_>>();

        Ok(serde_json::json!({
            "applied": applied,
            "applied_uri": current_uri,
            "applied_edit_count": target_edits.len(),
            "skipped_uris": skipped_uris,
            "documents": documents,
        })
        .to_string())
    }

    fn lsp_apply_lsp_text_edits(
        &mut self,
        buffer_id: BufferId,
        edits: &[LspTextEdit],
    ) -> Result<bool, UiError> {
        if edits.is_empty() {
            return Ok(false);
        }

        {
            let mut doc = self.lock_doc();
            let line_index = doc
                .ws
                .buffer_line_index(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let mut specs = edits
                .iter()
                .map(|edit| {
                    let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
                    editor_core::TextEditSpec {
                        start,
                        end,
                        text: edit.new_text.clone(),
                    }
                })
                .collect::<Vec<_>>();

            // Match `Workspace::apply_text_edits` behavior (descending by start).
            specs.sort_by_key(|e| std::cmp::Reverse(e.start));

            doc.ws
                .apply_text_edits(vec![(buffer_id, specs)])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }

        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(true)
    }

    /// Apply LSP document highlight result payload (`DocumentHighlight[] | null`) as a style layer.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentHighlight`.
    pub fn lsp_apply_document_highlights_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_highlights_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP document symbol result payload (`DocumentSymbol[] | SymbolInformation[] | null`).
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentSymbol`.
    pub fn lsp_apply_document_symbols_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_symbols_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP folding range result payload (`FoldingRange[] | null`) to core fold regions.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/foldingRange`.
    pub fn lsp_apply_folding_ranges_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = folding_ranges_result_to_processing_edit(&result_value);
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP inlay hints result payload (`InlayHint[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/inlayHint`.
    pub fn lsp_apply_inlay_hints_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_inlay_hints_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP code lens result payload (`CodeLens[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/codeLens`.
    pub fn lsp_apply_code_lens_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_code_lens_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP document links result payload (`DocumentLink[] | null`) as:
    /// - decorations (payload / click targets)
    /// - style intervals (rendering underline)
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentLink`.
    pub fn lsp_apply_document_links_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edits = self.with_line_index(|line_index| {
            lsp_document_links_to_processing_edits(line_index, &result_value)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }

    pub fn set_render_config(&mut self, config: RenderConfig) {
        self.render_config = config;
    }

    pub fn set_render_metrics(
        &mut self,
        font_size: f32,
        line_height_px: f32,
        cell_width_px: f32,
        padding_x_px: f32,
        padding_y_px: f32,
    ) {
        self.render_config.font_size = font_size;
        self.render_config.line_height_px = line_height_px;
        self.render_config.cell_width_px = cell_width_px;
        self.render_config.padding_x_px = padding_x_px;
        self.render_config.padding_y_px = padding_y_px;
    }

    pub fn set_text_vertical_align(&mut self, align: TextVerticalAlign) {
        self.render_config.text_vertical_align = align;
    }

    /// Configure font fallback list for rendering (comma-separated family names).
    ///
    /// This mirrors how VS Code allows configuring `editor.fontFamily` as a list.
    ///
    /// Notes:
    /// - This does not affect layout metrics; the editor remains monospace-grid based.
    /// - The renderer will pick the first font that contains a glyph for each character.
    pub fn set_font_families_csv(&mut self, families_csv: &str) {
        let families: Vec<String> = families_csv
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();
        self.renderer.set_font_families(families);
    }

    /// Enable/disable font ligatures in the renderer (visual-only).
    pub fn set_font_ligatures_enabled(&mut self, enabled: bool) {
        self.render_config.enable_ligatures = enabled;
    }

    /// Set caret width in pixels (minimum 1px when visible).
    pub fn set_caret_width_px(&mut self, width_px: f32) {
        if width_px.is_finite() {
            self.render_config.caret_width_px = width_px.max(0.0);
        }
    }

    /// Show/hide carets during rendering (useful for UI-side blinking or focus handling).
    pub fn set_caret_visible(&mut self, visible: bool) {
        self.render_config.show_caret = visible;
    }

    /// Override the ASCII word-boundary character set used by editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    pub fn set_word_boundary_ascii_boundary_chars(
        &mut self,
        boundary_chars: &str,
    ) -> Result<(), UiError> {
        self.exec_core(Command::View(
            ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: boundary_chars.to_string(),
            },
        ))?;
        Ok(())
    }

    /// Configure how the Tab key behaves when using `EditCommand::InsertTab`.
    pub fn set_tab_key_behavior(
        &mut self,
        behavior: editor_core::TabKeyBehavior,
    ) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::SetTabKeyBehavior { behavior }))?;
        Ok(())
    }

    /// Configure the tab width (in monospace grid cells).
    ///
    /// This affects:
    /// - visual layout/rendering of `'\t'` characters
    /// - `EditCommand::InsertTab` in spaces mode (insert to the next tab stop)
    pub fn set_tab_width(&mut self, width_cells: usize) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::SetTabWidth {
            width: width_cells,
        }))?;
        Ok(())
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    pub fn reset_word_boundary_defaults(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::ResetWordBoundaryDefaults))?;
        Ok(())
    }

    pub fn set_gutter_width_cells(&mut self, width_cells: u32) -> Result<(), UiError> {
        self.render_config.gutter_width_cells = width_cells;
        // Keep wrap width in sync with the available text area.
        self.set_viewport_px(
            self.render_config.width_px,
            self.render_config.height_px,
            self.render_config.scale,
        )?;
        Ok(())
    }

    /// Enable/disable indentation guides (visual-only).
    pub fn set_indent_guides_enabled(&mut self, enabled: bool) {
        self.render_config.show_indent_guides = enabled;
    }

    /// Configure how whitespace markers are rendered (visual-only).
    pub fn set_whitespace_render_mode(&mut self, mode: WhitespaceRenderMode) {
        self.render_config.whitespace_render_mode = mode;
    }

    /// Configure how fold markers are rendered in the gutter (visual-only).
    pub fn set_fold_marker_style(&mut self, style: FoldMarkerStyle) {
        self.render_config.fold_marker_style = style;
    }

    /// Update pixel viewport size and keep editor-core's viewport width/height in sync.
    ///
    /// This is important for soft-wrapping: editor-core's layout uses "cells", while
    /// the renderer maps "cells" to pixel widths.
    pub fn set_viewport_px(
        &mut self,
        width_px: u32,
        height_px: u32,
        scale: f32,
    ) -> Result<(), UiError> {
        self.render_config.width_px = width_px;
        self.render_config.height_px = height_px;
        self.render_config.scale = scale;

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let usable_w =
            (width_px as f32 - self.render_config.padding_x_px * 2.0 - gutter_px).max(1.0);
        let cell_w = self.render_config.cell_width_px.max(1.0);
        let width_cells = (usable_w / cell_w).floor().max(1.0) as usize;
        self.exec_core(Command::View(ViewCommand::SetViewportWidth {
            width: width_cells,
        }))?;

        // `padding_y_px` is a top inset (like a "content inset"), not a symmetric top+bottom padding.
        //
        // If we subtract it twice, the bottom of the viewport can end up with a large blank area
        // (especially when the viewport height is not an exact multiple of `line_height_px`),
        // and partially visible lines would "pop in" only after crossing an arbitrary threshold.
        let usable_h = (height_px as f32 - self.render_config.padding_y_px).max(1.0);
        let line_h = self.render_config.line_height_px.max(1.0);
        let height_rows = (usable_h / line_h).floor().max(1.0) as usize;
        {
            let mut doc = self.lock_doc();
            doc.ws
                .set_viewport_height(self.view_id, height_rows)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    pub fn viewport_state(&mut self) -> editor_core::ViewportState {
        let v = {
            let mut doc = self.lock_doc();
            match doc.ws.viewport_state_for_view(self.view_id) {
                Ok(v) => v,
                Err(_) => {
                    return editor_core::ViewportState {
                        width: 0,
                        height: None,
                        scroll_top: 0,
                        sub_row_offset: 0,
                        overscan_rows: 0,
                        visible_lines: 0..0,
                        prefetch_lines: 0..0,
                        total_visual_lines: 0,
                    };
                }
            }
        };
        editor_core::ViewportState {
            width: v.width,
            height: v.height,
            scroll_top: v.scroll_top,
            sub_row_offset: v.smooth_scroll.sub_row_offset,
            overscan_rows: v.smooth_scroll.overscan_rows,
            visible_lines: v.visible_lines,
            prefetch_lines: v.prefetch_lines,
            total_visual_lines: v.total_visual_lines,
        }
    }

    /// Total logical line count (0-based lines, as seen by the editor model / line numbers).
    ///
    /// Note: this is independent of soft-wrapping/folding (which affect visual rows).
    pub fn logical_line_count(&self) -> u32 {
        let n = self.with_line_index(|idx| idx.line_count()).unwrap_or(0);
        (n.min(u32::MAX as usize)) as u32
    }

    pub fn gutter_width_cells(&self) -> u32 {
        self.render_config.gutter_width_cells
    }

    pub fn set_smooth_scroll_state(&mut self, top_visual_row: usize, sub_row_offset: u16) {
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_pos_rows = viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = self
            .lock_doc()
            .ws
            .smooth_scroll_state_for_view(self.view_id)
            .unwrap_or(editor_core::workspace::ViewSmoothScrollState {
                top_visual_row: viewport.scroll_top,
                sub_row_offset: viewport.sub_row_offset,
                overscan_rows: viewport.overscan_rows,
            });
        let pos_rows = top_visual_row as f32 + (sub_row_offset as f32 / 65536.0);
        let new_pos = pos_rows.clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    fn max_scroll_top(&self, viewport: &editor_core::ViewportState) -> usize {
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines)
    }

    fn ensure_primary_caret_visible_after_navigation(&mut self) {
        let viewport = self.viewport_state();
        let Some(height_rows) = viewport.height else {
            return;
        };
        if height_rows == 0 {
            return;
        }

        let cursor = self.cursor_state();
        let active = cursor
            .selections
            .get(cursor.primary_selection_index)
            .map(|s| s.end)
            .unwrap_or(cursor.position);

        let Some((caret_row, _caret_x)) = ({
            let mut doc = self.lock_doc();
            doc.ws
                .logical_to_visual_for_view(self.view_id, active.line, active.column)
                .ok()
                .flatten()
        }) else {
            return;
        };

        let mut new_top = viewport.scroll_top;
        if caret_row < viewport.scroll_top {
            new_top = caret_row;
        } else if caret_row >= viewport.scroll_top.saturating_add(height_rows) {
            new_top = caret_row.saturating_sub(height_rows.saturating_sub(1));
        }
        new_top = new_top.min(self.max_scroll_top(&viewport));

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            // Keyboard navigation should snap to full rows for a stable caret position.
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    /// Like [`Self::ensure_primary_caret_visible_after_navigation`], but used for text edits
    /// (typing/paste/undo) where we should not snap fractional smooth-scroll offsets unless the
    /// caret actually leaves the visible viewport.
    fn ensure_primary_caret_visible_after_edit(&mut self) {
        let viewport = self.viewport_state();
        let Some(height_rows) = viewport.height else {
            return;
        };
        if height_rows == 0 {
            return;
        }

        let cursor = self.cursor_state();
        let active = cursor
            .selections
            .get(cursor.primary_selection_index)
            .map(|s| s.end)
            .unwrap_or(cursor.position);

        let Some((caret_row, _caret_x)) = ({
            let mut doc = self.lock_doc();
            doc.ws
                .logical_to_visual_for_view(self.view_id, active.line, active.column)
                .ok()
                .flatten()
        }) else {
            return;
        };

        let mut new_top = viewport.scroll_top;
        let mut did_scroll = false;
        if caret_row < viewport.scroll_top {
            new_top = caret_row;
            did_scroll = true;
        } else if caret_row >= viewport.scroll_top.saturating_add(height_rows) {
            new_top = caret_row.saturating_sub(height_rows.saturating_sub(1));
            did_scroll = true;
        }

        if !did_scroll {
            return;
        }

        new_top = new_top.min(self.max_scroll_top(&viewport));

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            // When an edit forces us to scroll, snap to a full row so the caret lands predictably.
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    pub fn scroll_by_rows(&mut self, delta_rows: isize) {
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_top = viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines) as isize;

        let old = viewport.scroll_top as isize;
        let new_top = (old + delta_rows).clamp(0, max_top.max(0)) as usize;

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    /// Smooth-scroll the viewport by a pixel delta (positive = scroll down, reveal later lines).
    ///
    /// This updates editor-core's `(scroll_top, sub_row_offset)` smooth-scroll state:
    /// - `scroll_top` is the top visual row anchor.
    /// - `sub_row_offset` is a normalized 0..=65535 fraction within a row.
    ///
    /// Notes:
    /// - The UI layer interprets `sub_row_offset` as a pixel offset in the range
    ///   `0..line_height_px` (using a 65536 denominator).
    /// - The renderer and hit-testing paths must both use the same mapping.
    pub fn scroll_by_pixels(&mut self, delta_y_px: f32) {
        if !delta_y_px.is_finite() || delta_y_px.abs() <= f32::EPSILON {
            return;
        }

        let line_h = self.render_config.line_height_px.max(1.0);
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_pos_rows = viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let pos_rows = smooth.top_visual_row as f32 + (smooth.sub_row_offset as f32 / 65536.0);
        let delta_rows = delta_y_px / line_h;
        let new_pos = (pos_rows + delta_rows).clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        // UI typing entry point:
        // - For single-character typing, route through `TypeChar` so auto-pairs can engage.
        // - For multi-character commits (IME commits, etc), keep the bulk `InsertText` path.
        //
        // Notes:
        // - Keep `'\n'` out of the `TypeChar` path; newline indentation is handled explicitly
        //   via `EditCommand::InsertNewline` (with optional auto-indent).
        // - For clipboard paste (including single-character paste), prefer `paste_text` which
        //   always uses `InsertText` and does not trigger auto-pairs rules.
        if text == "\n" || text == "\r" {
            // Treat newline as a dedicated editor command so core auto-indent can run.
            self.exec_core(Command::Edit(EditCommand::InsertNewline {
                auto_indent: true,
            }))?;
            self.refresh_processing()?;
            // Best-effort: if the LSP server advertises `documentOnTypeFormattingProvider` on
            // newline, request it (async) to improve indentation.
            let requested_lsp = self
                .maybe_request_lsp_on_type_formatting("\n")
                .unwrap_or(false);
            if !requested_lsp {
                // Best-effort fallback: if a Tree-sitter `indents.scm` is available for the
                // current language, use it to compute the desired indentation.
                let _ = self.maybe_apply_treesitter_indent_for_primary_caret_line();
            }
            self.ensure_primary_caret_visible_after_edit();
            return Ok(());
        }
        let mut typed_trigger: Option<String> = None;
        if let Some(ch) = (text.chars().count() == 1)
            .then(|| text.chars().next())
            .flatten()
            && ch != '\t'
        {
            self.exec_core(Command::Edit(EditCommand::TypeChar { ch }))?;
            typed_trigger = Some(ch.to_string());
        } else {
            self.exec_core(Command::Edit(EditCommand::InsertText {
                text: text.to_string(),
            }))?;
        }
        self.refresh_processing()?;
        if let Some(trigger) = typed_trigger {
            let _ = self.maybe_request_lsp_on_type_formatting(trigger.as_str());
        }
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    /// Clipboard paste entry point (no auto-pairs).
    ///
    /// This always uses `EditCommand::InsertText`, even for a single character, so that
    /// auto-pairs rules don't engage for clipboard operations.
    pub fn paste_text(&mut self, text: &str) -> Result<(), UiError> {
        // If an IME marked range is active, treat paste as a commit that replaces the marked
        // text and ends the composition group.
        if self.marked.is_some() {
            return self.commit_text(text);
        }

        self.exec_core(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn insert_tab(&mut self) -> Result<(), UiError> {
        let has_snippet = {
            let doc = self.lock_doc();
            doc.ws
                .has_active_snippet_session(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        if has_snippet {
            self.exec_core(Command::Cursor(CursorCommand::SnippetNextPlaceholder))?;
        } else {
            self.exec_core(Command::Edit(EditCommand::InsertTab))?;
        }
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn insert_backtab(&mut self) -> Result<(), UiError> {
        let has_snippet = {
            let doc = self.lock_doc();
            doc.ws
                .has_active_snippet_session(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        if has_snippet {
            self.exec_core(Command::Cursor(CursorCommand::SnippetPrevPlaceholder))?;
        } else {
            self.exec_core(Command::Edit(EditCommand::Outdent))?;
        }
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn has_active_snippet_session(&self) -> Result<bool, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .has_active_snippet_session(self.view_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    pub fn backspace(&mut self) -> Result<(), UiError> {
        // UI-friendly default: delete the previous grapheme cluster (UAX #29).
        //
        // However, when auto-pairs are enabled, most editors prefer delete-pair behavior
        // when the caret is between matching delimiters.
        let cursor = self.cursor_state();
        let can_try_delete_pair =
            self.auto_pairs.enabled && self.auto_pairs.delete_pair && cursor.selection.is_none();
        if can_try_delete_pair && cursor.multi_cursors.is_empty() {
            let caret_off = cursor.offset;
            if caret_off > 0 {
                let pair = self
                    .with_line_index(|idx| (idx.char_at(caret_off - 1), idx.char_at(caret_off)))?;
                if let (Some(open), Some(close)) = pair
                    && self
                        .auto_pairs
                        .pairs
                        .iter()
                        .any(|p| p.open == open && p.close == close)
                {
                    self.exec_core(Command::Edit(EditCommand::Backspace))?;
                    self.refresh_processing()?;
                    self.ensure_primary_caret_visible_after_edit();
                    return Ok(());
                }
            }
        }

        self.exec_core(Command::Edit(EditCommand::DeleteGraphemeBack))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), UiError> {
        // Mirror `backspace`: keep grapheme-aware deletion, but prefer delete-pair when enabled.
        let cursor = self.cursor_state();
        let can_try_delete_pair =
            self.auto_pairs.enabled && self.auto_pairs.delete_pair && cursor.selection.is_none();
        if can_try_delete_pair && cursor.multi_cursors.is_empty() {
            let caret_off = cursor.offset;
            if caret_off > 0 {
                let pair = self
                    .with_line_index(|idx| (idx.char_at(caret_off - 1), idx.char_at(caret_off)))?;
                if let (Some(open), Some(close)) = pair
                    && self
                        .auto_pairs
                        .pairs
                        .iter()
                        .any(|p| p.open == open && p.close == close)
                {
                    self.exec_core(Command::Edit(EditCommand::DeleteForward))?;
                    self.refresh_processing()?;
                    self.ensure_primary_caret_visible_after_edit();
                    return Ok(());
                }
            }
        }

        self.exec_core(Command::Edit(EditCommand::DeleteGraphemeForward))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_word_back(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::DeleteWordBack))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_word_forward(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::DeleteWordForward))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn add_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::AddStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn remove_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::RemoveStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Undo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Redo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn end_undo_group(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::EndUndoGroup))?;
        Ok(())
    }

    pub fn move_visual_by_rows(&mut self, delta_rows: isize) -> Result<(), UiError> {
        // UI-friendly behavior: if there is an active selection, moving vertically should
        // collapse it to the current caret before moving (matches common editor behavior).
        //
        // Without this, some hosts may appear "stuck" because the selection remains visible
        // while the caret movement is not obvious (and some cursor movement strategies can
        // also depend on a clear selection).
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_grapheme_left(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;
        Ok(())
    }

    pub fn move_grapheme_right(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeRight))?;
        Ok(())
    }

    pub fn move_word_left(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveWordLeft))?;
        Ok(())
    }

    pub fn move_word_right(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveWordRight))?;
        Ok(())
    }

    pub fn move_to_visual_line_start(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }

        let pos = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return None;
            }
            let last_line = line_count.saturating_sub(1);
            let text = line_index.get_line_text(last_line).unwrap_or_default();
            Some((last_line, text.chars().count()))
        })?;
        let Some((last_line, col)) = pos else {
            return Ok(());
        };

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_visual_by_pages(&mut self, delta_pages: isize) -> Result<(), UiError> {
        let height_rows = self.viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_grapheme_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        // Move the internal caret to the active end, clear selection so movement applies, then restore.
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveWordLeft))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_grapheme_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeRight))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveWordRight))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_to_visual_line_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;

        let pos = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return None;
            }
            let last_line = line_count.saturating_sub(1);
            let text = line_index.get_line_text(last_line).unwrap_or_default();
            Some((last_line, text.chars().count()))
        })?;
        let Some((last_line, col)) = pos else {
            return Ok(());
        };

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_visual_by_pages_and_modify_selection(
        &mut self,
        delta_pages: isize,
    ) -> Result<(), UiError> {
        let height_rows = self.viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows_and_modify_selection(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_visual_by_rows_and_modify_selection(
        &mut self,
        delta_rows: isize,
    ) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    /// Set IME marked text (composition).
    ///
    /// This is UI-layer behavior (not editor-core kernel): we represent the marked string
    /// as a replaceable range in the document, tracking its `(start, len)` in char offsets.
    pub fn set_marked_text(&mut self, text: &str) -> Result<(), UiError> {
        let new_len = text.chars().count();
        self.set_marked_text_with_selection(text, new_len, 0, None)
    }

    /// Set IME marked text (composition) with an explicit selection inside the marked string.
    ///
    /// - `selected_start/selected_len` are **character offsets** (Unicode scalar count) within `text`.
    /// - `replace_range` (when provided) is a document range in **character offsets** to replace.
    ///
    /// This matches how `NSTextInputClient.setMarkedText` communicates selection and replacement.
    pub fn set_marked_text_with_selection(
        &mut self,
        text: &str,
        selected_start: usize,
        selected_len: usize,
        replace_range: Option<(usize, usize)>,
    ) -> Result<(), UiError> {
        let new_len = text.chars().count();

        // Determine which document range is being replaced, and the "original" text
        // (the selection at the moment composition starts) so we can restore it if
        // composition is cancelled (e.g. Escape / IME clears marked text).
        let (start, replace_len, original_text, original_len) = if let Some((start, len)) =
            replace_range
        {
            let original = {
                let doc = self.lock_doc();
                doc.ws
                    .buffer_text_range(self.buffer_id, start, len)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            (start, len, original, len)
        } else if let Some(marked) = self.marked.as_ref() {
            (
                marked.start,
                marked.len,
                marked.original_text.clone(),
                marked.original_len,
            )
        } else {
            let cursor = self.cursor_state();
            if let Some(sel) = cursor.selection {
                let (start, end) = self.with_line_index(|line_index| {
                    let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
                    let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
                    if a <= b { (a, b) } else { (b, a) }
                })?;
                let len = end.saturating_sub(start);
                let original = {
                    let doc = self.lock_doc();
                    doc.ws
                        .buffer_text_range(self.buffer_id, start, len)
                        .map_err(|e| UiError::Processor(format!("{e:?}")))?
                };
                (start, len, original, len)
            } else {
                (cursor.offset, 0, String::new(), 0)
            }
        };

        // Empty marked text means "cancel/clear composition": restore original replaced text.
        if new_len == 0 {
            if replace_len > 0 || !original_text.is_empty() {
                self.exec_core(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                    start,
                    length: replace_len,
                    text: original_text.clone(),
                }))?;
                self.refresh_processing()?;
            }

            self.marked = None;
            let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }]);
            // Do not let IME composition edits coalesce into subsequent typing.
            let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));

            // Restore selection to the original range (best-effort).
            let a_off = start;
            let b_off = start.saturating_add(original_len);
            let (a_line, a_col, b_line, b_col) = self.with_line_index(|line_index| {
                let (a_line, a_col) = line_index.char_offset_to_position(a_off);
                let (b_line, b_col) = line_index.char_offset_to_position(b_off);
                (a_line, a_col, b_line, b_col)
            })?;

            if original_len > 0 {
                self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                    start: Position::new(a_line, a_col),
                    end: Position::new(b_line, b_col),
                }))?;
            } else {
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: a_line,
                    column: a_col,
                }))?;
                let _ = self.exec_core(Command::Cursor(CursorCommand::ClearSelection));
            }
            return Ok(());
        }

        // Start of composition: do not merge with the current typing group.
        if self.marked.is_none() {
            let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));
        }

        // Honor selection inside marked text (preedit caret / selection).
        //
        // Important: this must happen *within* the same edit command so it doesn't break
        // undo grouping (CommandExecutor ends the coalescing group on non-edit commands).
        let sel_start = selected_start.min(new_len);
        let sel_end = selected_start.saturating_add(selected_len).min(new_len);
        let a_off = start.saturating_add(sel_start);
        let b_off = start.saturating_add(sel_end);

        self.exec_core(Command::Edit(
            EditCommand::ReplaceCoalescingUndoWithSelection {
                start,
                length: replace_len,
                text: text.to_string(),
                selection_start: a_off,
                selection_end: b_off,
            },
        ))?;
        self.refresh_processing()?;

        self.marked = Some(MarkedRange {
            start,
            len: new_len,
            original_text,
            original_len,
        });

        // Apply a dedicated style layer so the renderer can draw preedit (underline/background).
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
            intervals: vec![Interval::new(
                start,
                start.saturating_add(new_len),
                IME_MARKED_TEXT_STYLE_ID,
            )],
        }])?;
        Ok(())
    }

    pub fn unmark_text(&mut self) {
        self.marked = None;
        let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
        }]);
    }

    pub fn commit_text(&mut self, text: &str) -> Result<(), UiError> {
        if let Some(marked) = self.marked.take() {
            self.exec_core(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                start: marked.start,
                length: marked.len,
                text: text.to_string(),
            }))?;
            self.refresh_processing()?;

            let end = marked.start + text.chars().count();
            let (line, column) = self.char_offset_to_logical_position(end);
            self.exec_core(Command::Cursor(CursorCommand::MoveTo { line, column }))?;

            let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }]);
            // Commit ends the composition undo group.
            let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));
            self.ensure_primary_caret_visible_after_edit();
            Ok(())
        } else {
            self.insert_text(text)
        }
    }

    pub fn mouse_down(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        self.mouse_down_with_modifiers_and_click_count(x_px, y_px, Modifiers::NONE, 1)
    }

    /// 鼠标按下（扩展版）：支持 modifiers + click count。
    ///
    /// 约定（尽量对齐主流编辑器的“鼠标策略”）：
    /// - `click_count == 1`：放置 caret；拖拽为字符级选择
    /// - `click_count == 2`：选中单词；拖拽按“单词”扩展
    /// - `click_count == 3`：选中整行；拖拽按“行”扩展
    /// - `click_count >= 4`：选中段落；拖拽按“段落”扩展
    /// - `ALT`：开始矩形选择（box/column selection），拖拽为矩形扩展
    /// - `SHIFT`：单击时从现有 selection anchor 扩展到点击位置
    /// - `CTRL`/`META`：单击添加一个额外 caret（multi-cursor）
    ///
    /// 注意：
    /// - 这是 UI 层行为（`editor-core-ui`），不会影响内核命令语义。
    pub fn mouse_down_with_modifiers_and_click_count(
        &mut self,
        x_px: f32,
        y_px: f32,
        modifiers: Modifiers,
        click_count: u8,
    ) -> Result<(), UiError> {
        // Gutter interaction: click-to-toggle fold state for a fold start line.
        if self.render_config.gutter_width_cells > 0 {
            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let gutter_end_x = self.render_config.padding_x_px + gutter_px;
            if x_px < gutter_end_x {
                if self.has_virtual_text_decorations() {
                    let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
                    let (local_row, _x_cells) = self.pixel_to_local_row_col(x_px, y_px);
                    if let Some(line) = grid.lines.get(local_row)
                        && let editor_core::ComposedLineKind::Document { logical_line, .. } =
                            line.kind
                    {
                        let fold_regions = {
                            let doc = self.lock_doc();
                            doc.ws
                                .folding_regions_for_buffer(self.buffer_id)
                                .unwrap_or_default()
                        };
                        if let Some(region) = fold_regions
                            .iter()
                            .filter(|r| r.start_line == logical_line)
                            .min_by_key(|r| r.end_line)
                            .cloned()
                        {
                            if region.is_collapsed {
                                self.exec_core(Command::Style(StyleCommand::Unfold {
                                    start_line: region.start_line,
                                }))?;
                            } else {
                                self.exec_core(Command::Style(StyleCommand::Fold {
                                    start_line: region.start_line,
                                    end_line: region.end_line,
                                }))?;
                            }
                            self.mouse_drag = None;
                            return Ok(());
                        }
                    }
                } else {
                    let (row, _x_cells) = self.pixel_to_visual(x_px, y_px);
                    let pos = {
                        let mut doc = self.lock_doc();
                        doc.ws
                            .visual_position_to_logical_for_view(self.view_id, row, 0)
                            .ok()
                            .flatten()
                    };
                    if let Some(pos) = pos {
                        let fold_regions = {
                            let doc = self.lock_doc();
                            doc.ws
                                .folding_regions_for_buffer(self.buffer_id)
                                .unwrap_or_default()
                        };
                        if let Some(region) = fold_regions
                            .iter()
                            .filter(|r| r.start_line == pos.line)
                            .min_by_key(|r| r.end_line)
                            .cloned()
                        {
                            if region.is_collapsed {
                                self.exec_core(Command::Style(StyleCommand::Unfold {
                                    start_line: region.start_line,
                                }))?;
                            } else {
                                self.exec_core(Command::Style(StyleCommand::Fold {
                                    start_line: region.start_line,
                                    end_line: region.end_line,
                                }))?;
                            }
                            self.mouse_drag = None;
                            return Ok(());
                        }
                    }
                }
            }
        }

        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };
        let (line, column) = self.char_offset_to_logical_position(off);
        let pos = Position::new(line, column);

        let click_count = click_count.max(1) as usize;

        // Single-click + Ctrl/Cmd: multi-cursor add caret.
        let wants_add_caret = click_count == 1
            && !modifiers.contains(Modifiers::SHIFT)
            && (modifiers.contains(Modifiers::CTRL) || modifiers.contains(Modifiers::META));
        if wants_add_caret {
            self.add_caret_at_char_offset(off, true)?;
            self.mouse_drag = None;
            return Ok(());
        }

        let mode = if modifiers.contains(Modifiers::ALT) {
            MouseSelectionMode::Rect
        } else {
            match click_count {
                1 => MouseSelectionMode::Char,
                2 => MouseSelectionMode::Word,
                3 => MouseSelectionMode::Line,
                _ => MouseSelectionMode::Paragraph,
            }
        };

        match mode {
            MouseSelectionMode::Char => {
                if modifiers.contains(Modifiers::SHIFT) {
                    let cursor = self.cursor_state();
                    let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);

                    self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                        start: anchor,
                        end: pos,
                    }))?;
                    // 让 caret 跟随 active end。
                    self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                        line: pos.line,
                        column: pos.column,
                    }))?;

                    let anchor_offset = self.with_line_index(|idx| {
                        idx.position_to_char_offset(anchor.line, anchor.column)
                    })?;
                    self.mouse_drag = Some(MouseDragState {
                        mode,
                        anchor_pos: anchor,
                        anchor_offset,
                        anchor_unit_range: None,
                    });
                } else {
                    self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                        line: pos.line,
                        column: pos.column,
                    }))?;
                    self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                    self.mouse_drag = Some(MouseDragState {
                        mode,
                        anchor_pos: pos,
                        anchor_offset: off,
                        anchor_unit_range: None,
                    });
                }
            }
            MouseSelectionMode::Rect => {
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: pos.line,
                    column: pos.column,
                }))?;
                self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                self.set_rect_selection_offsets(off, off)?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
            MouseSelectionMode::Word => {
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: pos.line,
                    column: pos.column,
                }))?;
                self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                self.select_word()?;
                let (start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: Some((start, end)),
                });
            }
            MouseSelectionMode::Line => {
                self.set_line_selection_offsets(off, off)?;
                let (_start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
            MouseSelectionMode::Paragraph => {
                self.select_paragraph_at_char_offset(off)?;
                let (_start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
        }
        Ok(())
    }

    pub fn mouse_dragged(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        let Some(state) = self.mouse_drag.clone() else {
            return Ok(());
        };
        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };

        match state.mode {
            MouseSelectionMode::Char => {
                let (to_line, to_col) = self.char_offset_to_logical_position(off);
                let to = Position::new(to_line, to_col);

                self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                    start: state.anchor_pos,
                    end: to,
                }))?;
                // Keep cursor_position synced to active end.
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: to.line,
                    column: to.column,
                }))?;
            }
            MouseSelectionMode::Word => {
                let (a_start, a_end) = state
                    .anchor_unit_range
                    .unwrap_or((state.anchor_offset, state.anchor_offset));
                let (b_start, b_end) = self.word_unit_range_at_char_offset(off)?;
                let start = a_start.min(b_start);
                let end = a_end.max(b_end);
                self.set_selections_offsets(&[(start, end)], 0)?;

                // caret 位于 active 方向的边界（尽量贴近常见编辑器体验）。
                let caret_off = if off >= state.anchor_offset {
                    end
                } else {
                    start
                };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Line => {
                self.set_line_selection_offsets(state.anchor_offset, off)?;
                let (start, end) = self.primary_selection_offsets();
                let (a_line, _a_col, b_line, _b_col) = self.with_line_index(|idx| {
                    let (a_line, a_col) = idx.char_offset_to_position(state.anchor_offset);
                    let (b_line, b_col) = idx.char_offset_to_position(off);
                    (a_line, a_col, b_line, b_col)
                })?;
                let caret_off = if b_line >= a_line { end } else { start };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Paragraph => {
                self.set_paragraph_selection_offsets(state.anchor_offset, off)?;
                let (start, end) = self.primary_selection_offsets();
                let caret_off = if off >= state.anchor_offset {
                    end
                } else {
                    start
                };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Rect => {
                self.set_rect_selection_offsets(state.anchor_offset, off)?;
                // 注意：这里不要再执行 `MoveTo`。
                //
                // `SetRectSelection` 会产生多选区（multi-cursor）。某些 `MoveTo` 变体会把多选区
                // 折叠成单 caret，导致矩形选择在拖拽时“丢行”。
            }
        }
        Ok(())
    }

    pub fn mouse_up(&mut self) {
        self.mouse_drag = None;
    }

    pub fn execute(&mut self, command: Command) -> Result<CommandResult, UiError> {
        let is_edit = matches!(command, Command::Edit(_));
        let result = self.exec_core(command)?;
        if is_edit {
            self.refresh_processing()?;
            self.ensure_primary_caret_visible_after_edit();
        }
        Ok(result)
    }

    pub fn render_rgba_visible(&mut self) -> Result<Vec<u8>, UiError> {
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        let mut out = vec![0u8; required];
        self.render_rgba_visible_into(out.as_mut_slice())?;
        Ok(out)
    }

    pub fn required_rgba_len(&self) -> usize {
        (self.render_config.width_px as usize)
            .saturating_mul(self.render_config.height_px as usize)
            .saturating_mul(4)
    }

    pub fn render_rgba_visible_into(&mut self, out_rgba: &mut [u8]) -> Result<usize, UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let mut fold_markers = Vec::<FoldMarker>::new();
        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        for region in fold_regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_rgba_into(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        } else {
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();
            self.renderer.render_rgba_into(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        }
        Ok(required)
    }

    /// 增量渲染：只重绘脏行（尽量小的像素区域），并返回需要 present 的 damage rect 列表。
    ///
    /// 约定：
    /// - 调用方需要复用 `out_rgba` 缓冲区，并保证其内容仍然是**上一帧**的像素结果；
    ///   本方法只会更新 dirty rect 覆盖的像素区域。
    /// - 若 viewport/config/theme 发生变化，本方法会自动退化为全量渲染（damage 为整屏）。
    pub fn render_rgba_visible_into_with_damage(
        &mut self,
        out_rgba: &mut [u8],
    ) -> Result<(usize, Vec<DamageRect>), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        if out_rgba.len() < required {
            return Err(RenderError::BufferTooSmall {
                required,
                provided: out_rgba.len(),
            }
            .into());
        }

        let has_virtual_text = self.has_virtual_text_decorations();
        let start_visual_row = if has_virtual_text {
            self.composed_start_row_for_doc_row(start_doc_row)
        } else {
            start_doc_row
        };

        let theme_hash = hash_render_theme(&self.theme);
        let view_version = {
            let doc = self.lock_doc();
            doc.ws.view_version(self.view_id).unwrap_or(0)
        };

        // Fold markers affect gutter rendering; treat them as part of the row signature.
        let fold_markers = {
            let fold_regions = {
                let doc = self.lock_doc();
                doc.ws
                    .folding_regions_for_buffer(self.buffer_id)
                    .unwrap_or_default()
            };
            let mut out = Vec::<FoldMarker>::new();
            for region in fold_regions {
                if region.end_line <= region.start_line {
                    continue;
                }
                out.push(FoldMarker {
                    logical_line: region.start_line as u32,
                    is_collapsed: region.is_collapsed,
                });
            }
            out
        };

        // Fast-path: nothing changed since the last frame.
        if let Some(cache) = self.render_cache.as_ref()
            && cache.view_version == view_version
            && cache.render_config == render_config
            && cache.theme_hash == theme_hash
            && cache.start_visual_row == start_visual_row
            && cache.row_count == row_count
            && cache.has_virtual_text == has_virtual_text
        {
            return Ok((required, Vec::new()));
        }

        if has_virtual_text {
            let (selection_ranges, _primary_idx) = self.selections_offsets();
            let caret_offsets = self.all_caret_offsets();

            let grid: ComposedGrid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_visual_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };

            let row_signatures = composed_row_signatures(
                &grid,
                row_count,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
            );

            let cache_ok = self.render_cache.as_ref().is_some_and(|c| {
                c.render_config == render_config
                    && c.theme_hash == theme_hash
                    && c.start_visual_row == start_visual_row
                    && c.row_count == row_count
                    && c.has_virtual_text == has_virtual_text
                    && c.row_signatures.len() == row_signatures.len()
            });

            if !cache_ok {
                self.renderer.render_composed_rgba_into(
                    &grid,
                    caret_offsets.as_slice(),
                    selection_ranges.as_slice(),
                    fold_markers.as_slice(),
                    render_config,
                    &self.theme,
                    out_rgba,
                )?;
                self.render_cache = Some(RenderFrameCache {
                    view_version,
                    render_config,
                    theme_hash,
                    start_visual_row,
                    row_count,
                    has_virtual_text,
                    row_signatures,
                });
                return Ok((
                    required,
                    vec![DamageRect {
                        x: 0,
                        y: 0,
                        width: render_config.width_px,
                        height: render_config.height_px,
                    }],
                ));
            }

            let prev = self
                .render_cache
                .as_ref()
                .map(|c| c.row_signatures.as_slice())
                .unwrap_or(&[]);
            let dirty_ranges = dirty_row_ranges(prev, row_signatures.as_slice());

            if dirty_ranges.is_empty() {
                if let Some(cache) = self.render_cache.as_mut() {
                    cache.view_version = view_version;
                    cache.row_signatures = row_signatures;
                }
                return Ok((required, Vec::new()));
            }

            self.renderer.render_composed_rgba_into_partial_rows(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
                dirty_ranges.as_slice(),
            )?;

            let mut damage: Vec<DamageRect> = Vec::new();
            for (start, end) in &dirty_ranges {
                if let Some(rect) = damage_rect_for_row_range(*start, *end, render_config) {
                    damage.push(rect);
                }
            }

            if let Some(cache) = self.render_cache.as_mut() {
                cache.view_version = view_version;
                cache.row_signatures = row_signatures;
            }

            Ok((required, damage))
        } else {
            let grid: HeadlessGrid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_visual_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();

            let row_signatures = headless_row_signatures(
                &grid,
                row_count,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
            );

            let cache_ok = self.render_cache.as_ref().is_some_and(|c| {
                c.render_config == render_config
                    && c.theme_hash == theme_hash
                    && c.start_visual_row == start_visual_row
                    && c.row_count == row_count
                    && c.has_virtual_text == has_virtual_text
                    && c.row_signatures.len() == row_signatures.len()
            });

            if !cache_ok {
                self.renderer.render_rgba_into(
                    &grid,
                    carets.as_slice(),
                    selections.as_slice(),
                    fold_markers.as_slice(),
                    render_config,
                    &self.theme,
                    out_rgba,
                )?;
                self.render_cache = Some(RenderFrameCache {
                    view_version,
                    render_config,
                    theme_hash,
                    start_visual_row,
                    row_count,
                    has_virtual_text,
                    row_signatures,
                });
                return Ok((
                    required,
                    vec![DamageRect {
                        x: 0,
                        y: 0,
                        width: render_config.width_px,
                        height: render_config.height_px,
                    }],
                ));
            }

            let prev = self
                .render_cache
                .as_ref()
                .map(|c| c.row_signatures.as_slice())
                .unwrap_or(&[]);
            let dirty_ranges = dirty_row_ranges(prev, row_signatures.as_slice());

            if dirty_ranges.is_empty() {
                if let Some(cache) = self.render_cache.as_mut() {
                    cache.view_version = view_version;
                    cache.row_signatures = row_signatures;
                }
                return Ok((required, Vec::new()));
            }

            self.renderer.render_rgba_into_partial_rows(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
                dirty_ranges.as_slice(),
            )?;

            let mut damage: Vec<DamageRect> = Vec::new();
            for (start, end) in &dirty_ranges {
                if let Some(rect) = damage_rect_for_row_range(*start, *end, render_config) {
                    damage.push(rect);
                }
            }

            if let Some(cache) = self.render_cache.as_mut() {
                cache.view_version = view_version;
                cache.row_signatures = row_signatures;
            }

            Ok((required, damage))
        }
    }

    /// Enable the Skia Metal backend (macOS only).
    ///
    /// This is a rendering backend switch only; it does not affect editor state.
    pub fn enable_metal(
        &mut self,
        metal_device: *mut c_void,
        metal_command_queue: *mut c_void,
    ) -> Result<(), UiError> {
        self.renderer
            .enable_metal(metal_device, metal_command_queue)?;
        Ok(())
    }

    /// Disable the Metal backend and revert to CPU raster output.
    pub fn disable_metal(&mut self) {
        self.renderer.disable_metal();
    }

    /// Render the current visible viewport into a Metal texture (macOS only).
    ///
    /// The host is responsible for presenting the texture (e.g. `CAMetalDrawable`).
    pub fn render_metal_visible_into_texture(
        &mut self,
        metal_texture: *mut c_void,
    ) -> Result<(), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let mut fold_markers = Vec::<FoldMarker>::new();
        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        for region in fold_regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }

        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_into_metal_texture(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
            )?;
        } else {
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();
            self.renderer.render_rgba_into_metal_texture(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
            )?;
        }

        Ok(())
    }

    fn has_virtual_text_decorations(&self) -> bool {
        let doc = self.lock_doc();
        doc.ws
            .buffer_decorations(self.buffer_id)
            .ok()
            .map(|decorations| {
                decorations.values().any(|layer| {
                    layer
                        .iter()
                        .any(|d| d.text.as_ref().is_some_and(|t| !t.is_empty()))
                })
            })
            .unwrap_or(false)
    }

    fn treesitter_prefetch_char_range(&mut self) -> Option<(usize, usize)> {
        let viewport = self.viewport_state();
        let lines = viewport.prefetch_lines;
        if lines.is_empty() {
            return None;
        }

        let start_visual = lines.start;
        let end_visual = lines.end.saturating_sub(1);

        let mut doc = self.lock_doc();
        let (start_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, start_visual)
            .ok()?;
        let (end_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, end_visual)
            .ok()?;
        let end_line_excl = end_line.saturating_add(1);

        let line_index = doc.ws.buffer_line_index(self.buffer_id).ok()?;
        let start = line_index.position_to_char_offset(start_line, 0);
        let end = line_index.position_to_char_offset(end_line_excl, 0);
        if end > start {
            Some((start, end))
        } else {
            None
        }
    }

    fn refresh_processing(&mut self) -> Result<(), UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let mut doc = self.lock_doc();
        let buffer_id = doc.buffer_id;

        if doc.sublime.is_some() {
            // Clone the line index to avoid keeping an immutable borrow of `doc.ws` alive while we
            // mutably borrow the processor.
            let line_index = doc
                .ws
                .buffer_line_index(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            let proc = doc
                .sublime
                .as_mut()
                .ok_or_else(|| UiError::Processor("sublime processor missing".to_string()))?;
            let edits = proc
                .compute_processing_edits(&line_index)
                .map_err(|e| UiError::Processor(e.to_string()))?;
            doc.apply_processing_edits(edits)?;
        }

        let delta = doc
            .ws
            .take_last_text_delta_for_buffer(buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let Some(delta) = delta else {
            return Ok(());
        };
        if delta.is_empty() {
            return Ok(());
        }

        // Monotonic version for "text has changed" events (used to drop stale async results).
        doc.text_version = doc.text_version.saturating_add(1);

        if doc.treesitter.is_some() {
            doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
            let version = doc.treesitter_doc_version;
            if let Some(worker) = doc.treesitter.as_mut() {
                worker.requested_version = Some(version);
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::ApplyDelta {
                        version,
                        delta: (*delta).clone(),
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to send delta to tree-sitter worker".to_string())
                    })?;
            }
        }

        // Keep LSP (if enabled) in sync with incremental edits.
        if doc.lsp.is_some() {
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(());
            };
            let Some(shared) = doc.lsp.clone() else {
                return Ok(());
            };

            let changes = {
                let Some(calc) = doc.lsp_delta_calc.as_mut() else {
                    doc.lsp_fail("LSP incremental sync state missing");
                    return Ok(());
                };
                Self::lsp_changes_for_text_delta(calc, delta.as_ref())
            };
            if changes.is_empty() {
                return Ok(());
            }

            if let Err(err) = shared.with_session_mut(|session| {
                session.set_active_document(doc_uri.as_str())?;
                session.did_change_many(changes)
            }) {
                doc.lsp_fail(err);
                return Ok(());
            }

            // Defer inlay hints / code lens refresh slightly to avoid spamming on rapid typing.
            doc.lsp_aux_refresh_due = Some(Instant::now() + Duration::from_millis(250));
        }
        Ok(())
    }

    fn flush_lsp_did_change_from_delta(&mut self) {
        let mut doc = self.lock_doc();
        let buffer_id = doc.buffer_id;
        let delta = doc
            .ws
            .take_last_text_delta_for_buffer(buffer_id)
            .unwrap_or_default();
        let Some(delta) = delta else {
            return;
        };
        if delta.is_empty() {
            return;
        }

        // Keep the UI-side monotonic text version consistent with `refresh_processing`.
        doc.text_version = doc.text_version.saturating_add(1);

        let Some(shared) = doc.lsp.clone() else {
            return;
        };
        let Some(doc_uri) = doc.lsp_document_uri.clone() else {
            doc.lsp_fail("LSP document URI missing");
            return;
        };

        let Some(calc) = doc.lsp_delta_calc.as_mut() else {
            doc.lsp_fail("LSP incremental sync state missing");
            return;
        };

        let changes = Self::lsp_changes_for_text_delta(calc, delta.as_ref());
        if changes.is_empty() {
            return;
        }

        if let Err(err) = shared.with_session_mut(|session| {
            session.set_active_document(doc_uri.as_str())?;
            session.did_change_many(changes)
        }) {
            doc.lsp_fail(err);
            return;
        }

        // Defer inlay hints / code lens refresh slightly to avoid spamming on rapid typing.
        doc.lsp_aux_refresh_due = Some(Instant::now() + Duration::from_millis(250));
    }

    fn lsp_changes_for_text_delta(
        calc: &mut DeltaCalculator,
        delta: &editor_core::delta::TextDelta,
    ) -> Vec<LspContentChange> {
        fn position_for_char_offset(calc: &DeltaCalculator, mut offset: usize) -> (usize, usize) {
            let line_count = calc.line_count().max(1);
            for line in 0..line_count {
                let text = calc.get_line(line).unwrap_or("");
                let len = text.chars().count();
                if offset <= len {
                    return (line, offset);
                }
                offset = offset.saturating_sub(len + 1);
            }

            let last_line = line_count.saturating_sub(1);
            let last_len = calc.get_line(last_line).unwrap_or("").chars().count();
            (last_line, last_len)
        }

        let mut out = Vec::<LspContentChange>::with_capacity(delta.edits.len());
        for edit in &delta.edits {
            let (start_line, start_char) = position_for_char_offset(calc, edit.start);
            let (end_line, end_char) = position_for_char_offset(calc, edit.end());
            let change = calc.calculate_replace_change(
                start_line,
                start_char,
                end_line,
                end_char,
                edit.inserted_text.as_str(),
            );
            calc.apply_change(&change);
            out.push(LspContentChange {
                range: change.range,
                text: change.text,
            });
        }
        out
    }

    fn poll_lsp_best_effort(&mut self) -> Result<bool, UiError> {
        let (shared, doc_uri) = {
            let mut doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Ok(false);
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(false);
            };
            (shared, doc_uri)
        };

        let mut applied = false;
        {
            let mut doc = self.lock_doc();
            let line_index = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(idx) => idx,
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(false);
                }
            };
            let edits = match shared.with_session_mut(|session| {
                session.set_active_document(doc_uri.as_str())?;
                session.poll_edits_with_line_index(line_index)
            }) {
                Ok(edits) => edits,
                Err(reason) => {
                    doc.lsp_fail(reason);
                    return Ok(false);
                }
            };
            applied |= doc.apply_lsp_processing_edits(edits)?;
        }

        if let Err(err) = self.maybe_request_lsp_aux() {
            let mut doc = self.lock_doc();
            doc.lsp_fail(err.to_string());
            return Ok(false);
        }

        let events = match shared.with_session_mut(|session| Ok(session.drain_events())) {
            Ok(events) => events,
            Err(reason) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(reason);
                return Ok(false);
            }
        };
        if events.is_empty() {
            return Ok(applied);
        }

        // Avoid re-entrant locking: collect text edits while holding the doc lock and apply
        // them after releasing it.
        let mut on_type_formatting_results: Vec<serde_json::Value> = Vec::new();

        let mut doc = self.lock_doc();
        for ev in events {
            let LspEvent::Response(resp) = ev else {
                continue;
            };

            if let Some(slot) = LspResultSlot::from_response_method(resp.method.as_str()) {
                if let Some(LspClientRequest::Result {
                    view,
                    slot: request_slot,
                }) = doc.lsp_client_requests.remove(&resp.id)
                {
                    if request_slot != slot {
                        continue;
                    }
                    if doc.lsp_latest_result_request_id.get(&(view, slot)) != Some(&resp.id) {
                        continue;
                    }

                    if resp.error.is_some() {
                        doc.lsp_last_result_json.remove(&(view, slot));
                        continue;
                    }

                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    match slot {
                        LspResultSlot::DocumentSymbols => {
                            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                                Ok(line_index) => {
                                    lsp_document_symbols_to_processing_edit(line_index, &result)
                                }
                                Err(_) => {
                                    doc.lsp_fail("LSP buffer line index unavailable");
                                    return Ok(false);
                                }
                            };
                            applied |= doc.apply_lsp_processing_edits([edit])?;
                        }
                        LspResultSlot::FoldingRanges => {
                            let edit = folding_ranges_result_to_processing_edit(&result);
                            applied |= doc.apply_lsp_processing_edits([edit])?;
                        }
                        _ => {}
                    }

                    if result.is_null() {
                        doc.lsp_last_result_json.remove(&(view, slot));
                    } else {
                        doc.lsp_last_result_json
                            .insert((view, slot), result.to_string());
                    }
                }
                continue;
            }

            match resp.method.as_str() {
                "textDocument/inlayHint" => {
                    doc.lsp_inlay_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => lsp_inlay_hints_to_processing_edit(line_index, &result),
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits([edit])?;
                }
                "textDocument/codeLens" => {
                    doc.lsp_code_lens_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, &result),
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits([edit])?;
                }
                "textDocument/documentLink" => {
                    doc.lsp_document_links_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edits = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => {
                            lsp_document_links_to_processing_edits(line_index, &result)
                        }
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits(edits)?;
                }
                "textDocument/onTypeFormatting" => {
                    if let Some(LspClientRequest::OnTypeFormatting { view, version }) =
                        doc.lsp_client_requests.remove(&resp.id)
                    {
                        if doc.lsp_latest_on_type_formatting_request_id.get(&view) != Some(&resp.id)
                        {
                            continue;
                        }
                        if doc.text_version != version {
                            continue;
                        }
                        if resp.error.is_some() {
                            continue;
                        }

                        let result = resp.result.unwrap_or(serde_json::Value::Null);
                        if !result.is_null() {
                            on_type_formatting_results.push(result);
                        }
                    }
                }
                _ => {}
            }
        }

        drop(doc);
        for result in on_type_formatting_results {
            match self.lsp_apply_text_edits_value(self.buffer_id, &result) {
                Ok(did_apply) => {
                    if did_apply {
                        applied = true;
                    }
                }
                Err(_err) => {
                    let mut doc = self.lock_doc();
                    doc.lsp_fail(_err.to_string());
                    return Ok(false);
                }
            }
        }

        Ok(applied)
    }

    fn maybe_request_lsp_aux(&mut self) -> Result<(), UiError> {
        let (shared, doc_uri, allow_inlay, request_code_lens, request_document_links) = {
            let mut doc = self.lock_doc();
            let Some(due) = doc.lsp_aux_refresh_due else {
                return Ok(());
            };
            if Instant::now() < due {
                return Ok(());
            }
            doc.lsp_aux_refresh_due = None;

            let Some(shared) = doc.lsp.clone() else {
                return Ok(());
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Ok(());
            };

            let allow_inlay = !doc.lsp_inlay_in_flight;
            let request_code_lens = !doc.lsp_code_lens_in_flight;
            let request_document_links = !doc.lsp_document_links_in_flight;
            (
                shared,
                doc_uri,
                allow_inlay,
                request_code_lens,
                request_document_links,
            )
        };

        let inlay_range = if allow_inlay {
            self.treesitter_prefetch_char_range()
        } else {
            None
        };
        let request_inlay_range = inlay_range.and_then(|(start, end)| {
            if end > start {
                Some((start, end))
            } else {
                None
            }
        });

        let mut doc = self.lock_doc();
        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;

        shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;

                // Inlay hints: prefer the viewport prefetch range (good UX + avoids huge payloads).
                if let Some((start, end)) = request_inlay_range {
                    lsp.request_inlay_hints(line_index, start, end)?;
                }

                if request_code_lens {
                    lsp.request_code_lens()?;
                }

                if request_document_links {
                    lsp.request_document_links()?;
                }

                Ok(())
            })
            .map_err(UiError::Processor)?;

        if request_inlay_range.is_some() {
            doc.lsp_inlay_in_flight = true;
        }
        if request_code_lens {
            doc.lsp_code_lens_in_flight = true;
        }
        if request_document_links {
            doc.lsp_document_links_in_flight = true;
        }

        Ok(())
    }

    fn all_selections_visual(&mut self) -> Vec<VisualSelection> {
        let cursor = self.cursor_state();
        let mut out = Vec::new();
        let mut doc = self.lock_doc();

        for sel in cursor.selections {
            if sel.start == sel.end {
                continue;
            }
            let Some((a_row, a_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.start.line, sel.start.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            let Some((b_row, b_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            out.push(VisualSelection {
                start_row: a_row as u32,
                start_x_cells: a_x as u32,
                end_row: b_row as u32,
                end_x_cells: b_x as u32,
            });
        }

        out
    }

    fn all_carets_visual(&mut self) -> Vec<VisualCaret> {
        let cursor = self.cursor_state();
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        let mut doc = self.lock_doc();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let Some((row, x_cells)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };

            // Draw primary caret last so it wins in overlaps.
            let caret = VisualCaret {
                row: row as u32,
                x_cells: x_cells as u32,
            };
            if idx == primary_idx {
                primary.push(caret);
            } else {
                secondary.push(caret);
            }
        }
        secondary.extend(primary);
        secondary
    }

    fn all_caret_offsets(&self) -> Vec<usize> {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return Vec::new();
        };
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let offset = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if idx == primary_idx {
                primary.push(offset);
            } else {
                secondary.push(offset);
            }
        }
        secondary.extend(primary);
        secondary
    }

    fn pixel_to_visual(&mut self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let global_row = viewport.scroll_top + local_row;
        (global_row, col)
    }

    fn pixel_to_local_row_col(&mut self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        (local_row, col)
    }

    fn composed_viewport_grid(&mut self) -> (usize, usize, editor_core::ComposedGrid) {
        let viewport = self.viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let start_composed = self.composed_start_row_for_doc_row(start_doc_row);
        let grid = {
            let mut doc = self.lock_doc();
            doc.ws
                .get_viewport_content_composed(self.view_id, start_composed, row_count)
                .unwrap_or_else(|_| editor_core::ComposedGrid::new(start_composed, row_count))
        };
        (start_composed, row_count, grid)
    }

    fn viewport_row_count_for_render(&self, viewport: &editor_core::ViewportState) -> usize {
        let start_row = viewport.scroll_top;
        let base = viewport
            .height
            .unwrap_or(viewport.total_visual_lines.saturating_sub(start_row));

        // When the pixel viewport height does not fit an integer number of rows (or when a
        // sub-row scroll offset is present), the bottom of the viewport can reveal part of the
        // next visual row. We still render it and rely on the host to clip.
        //
        // We compute the required row count from pixel geometry to avoid artifacts such as:
        // - the last partially visible row being fully hidden
        // - blank strips when `sub_row_offset` is close to a full row
        if viewport.height.is_none() {
            return base;
        }

        let line_h = self.render_config.line_height_px.max(1.0);
        // See `set_viewport_px`: vertical padding is a top inset, not top+bottom.
        let usable_h =
            (self.render_config.height_px as f32 - self.render_config.padding_y_px).max(1.0);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let desired_rows = ((usable_h + scroll_y_px) / line_h).ceil().max(1.0) as usize;
        let max_rows = viewport.total_visual_lines.saturating_sub(start_row);
        base.max(desired_rows).min(max_rows.max(1))
    }

    fn sub_row_offset_to_scroll_y_px(&self, sub_row_offset: u16) -> f32 {
        // Interpret `sub_row_offset` as a fraction of a row using a 65536 denominator.
        // This keeps the invariant that 65535 corresponds to "almost a full row", not exactly one.
        let line_h = self.render_config.line_height_px.max(1.0);
        (sub_row_offset as f32 / 65536.0) * line_h
    }

    fn composed_start_row_for_doc_row(&mut self, doc_row: usize) -> usize {
        // Fast path: no above-line virtual text => composed rows are identical to doc visual rows.
        let mut doc = self.lock_doc();
        let has_above_line =
            doc.ws
                .buffer_decorations(self.buffer_id)
                .ok()
                .is_some_and(|decorations| {
                    decorations.values().any(|layer| {
                        layer.iter().any(|d| {
                            d.placement == editor_core::DecorationPlacement::AboveLine
                                && d.text.as_ref().is_some_and(|t| !t.is_empty())
                        })
                    })
                });
        if !has_above_line {
            return doc_row;
        }

        let Ok((top_logical_line, _visual_in_logical)) =
            doc.ws.visual_to_logical_for_view(self.view_id, doc_row)
        else {
            return doc_row;
        };

        // Count above-line decorations per logical line.
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return doc_row;
        };
        let Ok(decorations) = doc.ws.buffer_decorations(self.buffer_id) else {
            return doc_row;
        };
        let mut above_count: HashMap<usize, usize> = HashMap::new();
        for layer in decorations.values() {
            for d in layer {
                if d.placement != editor_core::DecorationPlacement::AboveLine {
                    continue;
                }
                let Some(text) = d.text.as_ref() else {
                    continue;
                };
                if text.is_empty() {
                    continue;
                }
                let line = line_index.char_offset_to_position(d.range.start).0;
                *above_count.entry(line).or_insert(0) += 1;
            }
        }

        let mut prefix = 0usize;
        if !above_count.is_empty() {
            let regions = doc
                .ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default();
            for (line, count) in above_count {
                if line >= top_logical_line || is_logical_line_hidden(regions.as_slice(), line) {
                    continue;
                }
                prefix = prefix.saturating_add(count);
            }
        }
        doc_row.saturating_add(prefix)
    }
}

fn hash_render_theme(theme: &RenderTheme) -> u64 {
    fn hash_rgba8(hasher: &mut DefaultHasher, c: Rgba8) {
        c.r.hash(hasher);
        c.g.hash(hasher);
        c.b.hash(hasher);
        c.a.hash(hasher);
    }

    fn hash_opt_rgba8(hasher: &mut DefaultHasher, c: Option<Rgba8>) {
        match c {
            None => 0u8.hash(hasher),
            Some(v) => {
                1u8.hash(hasher);
                hash_rgba8(hasher, v);
            }
        }
    }

    fn hash_style_colors(hasher: &mut DefaultHasher, c: StyleColors) {
        hash_opt_rgba8(hasher, c.foreground);
        hash_opt_rgba8(hasher, c.background);
    }

    fn hash_style_font(hasher: &mut DefaultHasher, f: StyleFont) {
        f.bold.hash(hasher);
        f.italic.hash(hasher);
    }

    fn hash_text_decorations(hasher: &mut DefaultHasher, d: TextDecorations) {
        let underline_tag: u8 = match d.underline {
            None => 0,
            Some(UnderlineStyle::Single) => 1,
            Some(UnderlineStyle::Double) => 2,
            Some(UnderlineStyle::Squiggly) => 3,
        };
        underline_tag.hash(hasher);
        hash_opt_rgba8(hasher, d.underline_color);

        d.strikethrough.hash(hasher);
        hash_opt_rgba8(hasher, d.strikethrough_color);
    }

    let mut hasher = DefaultHasher::new();

    hash_rgba8(&mut hasher, theme.background);
    hash_rgba8(&mut hasher, theme.foreground);
    hash_rgba8(&mut hasher, theme.selection_background);
    hash_rgba8(&mut hasher, theme.caret);

    for (style_id, colors) in &theme.styles {
        style_id.hash(&mut hasher);
        hash_style_colors(&mut hasher, *colors);
    }
    for (style_id, font) in &theme.style_fonts {
        style_id.hash(&mut hasher);
        hash_style_font(&mut hasher, *font);
    }
    for (style_id, deco) in &theme.text_decorations {
        style_id.hash(&mut hasher);
        hash_text_decorations(&mut hasher, *deco);
    }

    hasher.finish()
}

fn damage_rect_for_row_range(
    start_row: usize,
    end_row: usize,
    config: RenderConfig,
) -> Option<DamageRect> {
    if start_row >= end_row {
        return None;
    }

    let y0 = config.padding_y_px + start_row as f32 * config.line_height_px - config.scroll_y_px;
    let y1 = config.padding_y_px + end_row as f32 * config.line_height_px - config.scroll_y_px;
    if !y0.is_finite() || !y1.is_finite() {
        return None;
    }

    let mut y0i = y0.floor() as i64;
    let mut y1i = y1.ceil() as i64;

    let h_total = config.height_px as i64;
    y0i = y0i.clamp(0, h_total);
    y1i = y1i.clamp(0, h_total);
    if y1i <= y0i {
        return None;
    }

    Some(DamageRect {
        x: 0,
        y: y0i as u32,
        width: config.width_px,
        height: (y1i - y0i) as u32,
    })
}

fn dirty_row_ranges(prev: &[u64], next: &[u64]) -> Vec<(usize, usize)> {
    if prev.len() != next.len() {
        if next.is_empty() {
            return Vec::new();
        }
        return vec![(0, next.len())];
    }

    let mut ranges: Vec<(usize, usize)> = Vec::new();
    let mut start: Option<usize> = None;

    for i in 0..next.len() {
        let dirty = prev[i] != next[i];
        match (dirty, start) {
            (true, None) => start = Some(i),
            (false, Some(s)) => {
                ranges.push((s, i));
                start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = start {
        ranges.push((s, next.len()));
    }
    ranges
}

fn headless_row_signatures(
    grid: &HeadlessGrid,
    row_count: usize,
    carets: &[VisualCaret],
    selections: &[VisualSelection],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
    fn fold_marker_state_for_line(logical_line: u32, fold_markers: &[FoldMarker]) -> Option<bool> {
        fold_markers
            .iter()
            .find(|m| m.logical_line == logical_line)
            .map(|m| m.is_collapsed)
    }

    fn normalize_sel(sel: &VisualSelection) -> (u32, u32, u32, u32) {
        let a = (sel.start_row, sel.start_x_cells);
        let b = (sel.end_row, sel.end_x_cells);
        if a <= b {
            (
                sel.start_row,
                sel.start_x_cells,
                sel.end_row,
                sel.end_x_cells,
            )
        } else {
            (
                sel.end_row,
                sel.end_x_cells,
                sel.start_row,
                sel.start_x_cells,
            )
        }
    }

    fn selection_segment_for_row(sel: &VisualSelection, row: u32) -> Option<(u32, u32)> {
        let (sr, sx, er, ex) = normalize_sel(sel);
        if row < sr || row > er {
            return None;
        }
        if sr == er {
            return Some((sx.min(ex), sx.max(ex)));
        }
        if row == sr {
            return Some((sx, u32::MAX));
        }
        if row == er {
            return Some((0, ex));
        }
        Some((0, u32::MAX))
    }

    let mut out: Vec<u64> = Vec::with_capacity(row_count);
    for row_idx in 0..row_count {
        let mut hasher = DefaultHasher::new();

        if let Some(line) = grid.lines.get(row_idx) {
            line.logical_line_index.hash(&mut hasher);
            line.visual_in_logical.hash(&mut hasher);
            line.char_offset_start.hash(&mut hasher);
            line.char_offset_end.hash(&mut hasher);
            line.segment_x_start_cells.hash(&mut hasher);
            line.is_fold_placeholder_appended.hash(&mut hasher);

            for cell in &line.cells {
                (cell.ch as u32).hash(&mut hasher);
                cell.width.hash(&mut hasher);
                cell.styles.len().hash(&mut hasher);
                for style_id in &cell.styles {
                    style_id.hash(&mut hasher);
                }
            }

            if config.gutter_width_cells > 0 && line.visual_in_logical == 0 {
                let state =
                    fold_marker_state_for_line(line.logical_line_index as u32, fold_markers);
                state.hash(&mut hasher);
            }
        } else {
            // Beyond `actual_line_count`: background only.
            0u8.hash(&mut hasher);
        }

        // Selection overlay affects selection background and whitespace markers (Selection mode).
        let mut sel_segs: Vec<(u32, u32)> = Vec::new();
        for sel in selections {
            if let Some(seg) = selection_segment_for_row(sel, row_idx as u32) {
                sel_segs.push(seg);
            }
        }
        sel_segs.sort_unstable();
        for seg in sel_segs {
            seg.hash(&mut hasher);
        }

        // Carets are drawn on top only when enabled.
        if config.show_caret {
            let mut xs: Vec<u32> = carets
                .iter()
                .filter(|c| c.row as usize == row_idx)
                .map(|c| c.x_cells)
                .collect();
            xs.sort_unstable();
            for x in xs {
                x.hash(&mut hasher);
            }
        }

        out.push(hasher.finish());
    }
    out
}

fn composed_row_signatures(
    grid: &ComposedGrid,
    row_count: usize,
    caret_offsets: &[usize],
    selection_ranges: &[(usize, usize)],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
    fn fold_marker_state_for_line(logical_line: u32, fold_markers: &[FoldMarker]) -> Option<bool> {
        fold_markers
            .iter()
            .find(|m| m.logical_line == logical_line)
            .map(|m| m.is_collapsed)
    }

    let mut sel_ranges: Vec<(usize, usize)> = Vec::new();
    for (a, b) in selection_ranges {
        if *a == *b {
            continue;
        }
        if *a <= *b {
            sel_ranges.push((*a, *b));
        } else {
            sel_ranges.push((*b, *a));
        }
    }

    let mut carets: Vec<(usize, u32)> = Vec::new();
    if config.show_caret {
        for &caret_offset in caret_offsets {
            let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
                continue;
            };
            let line = &grid.lines[local_row];
            let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
            carets.push((local_row, x_cells));
        }
        carets.sort_unstable();
    }

    let mut out: Vec<u64> = Vec::with_capacity(row_count);
    for row_idx in 0..row_count {
        let mut hasher = DefaultHasher::new();

        if let Some(line) = grid.lines.get(row_idx) {
            match line.kind {
                ComposedLineKind::Document {
                    logical_line,
                    visual_in_logical,
                } => {
                    1u8.hash(&mut hasher);
                    logical_line.hash(&mut hasher);
                    visual_in_logical.hash(&mut hasher);
                    if config.gutter_width_cells > 0 && visual_in_logical == 0 {
                        let state = fold_marker_state_for_line(logical_line as u32, fold_markers);
                        state.hash(&mut hasher);
                    }
                }
                ComposedLineKind::VirtualAboveLine { logical_line } => {
                    2u8.hash(&mut hasher);
                    logical_line.hash(&mut hasher);
                }
            }

            line.char_offset_start.hash(&mut hasher);
            line.char_offset_end.hash(&mut hasher);

            for cell in &line.cells {
                (cell.ch as u32).hash(&mut hasher);
                cell.width.hash(&mut hasher);
                cell.styles.len().hash(&mut hasher);
                for style_id in &cell.styles {
                    style_id.hash(&mut hasher);
                }

                match cell.source {
                    ComposedCellSource::Document { offset } => {
                        1u8.hash(&mut hasher);
                        offset.hash(&mut hasher);
                        let selected = sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e);
                        selected.hash(&mut hasher);
                    }
                    ComposedCellSource::Virtual { anchor_offset } => {
                        2u8.hash(&mut hasher);
                        anchor_offset.hash(&mut hasher);
                    }
                }
            }
        } else {
            0u8.hash(&mut hasher);
        }

        if config.show_caret {
            for (r, x) in carets.iter().filter(|(r, _x)| *r == row_idx) {
                r.hash(&mut hasher);
                x.hash(&mut hasher);
            }
        }

        out.push(hasher.finish());
    }
    out
}

fn is_logical_line_hidden(regions: &[editor_core::FoldRegion], logical_line: usize) -> bool {
    regions.iter().any(|region| {
        region.is_collapsed && logical_line > region.start_line && logical_line <= region.end_line
    })
}

fn composed_line_index_for_offset(
    grid: &editor_core::ComposedGrid,
    char_offset: usize,
) -> Option<usize> {
    for (idx, line) in grid.lines.iter().enumerate() {
        if !matches!(line.kind, editor_core::ComposedLineKind::Document { .. }) {
            continue;
        }

        let start = line.char_offset_start;
        let end = line.char_offset_end;

        if char_offset < start {
            break;
        }
        if char_offset > end {
            continue;
        }
        if char_offset < end {
            return Some(idx);
        }

        if let Some(next) = grid.lines.get(idx + 1)
            && matches!(next.kind, editor_core::ComposedLineKind::Document { .. })
            && next.char_offset_start == char_offset
        {
            continue;
        }
        return Some(idx);
    }
    None
}

fn indent_prefix_cell_count(line: &editor_core::ComposedLine) -> usize {
    let mut count = 0usize;
    for cell in &line.cells {
        match cell.source {
            editor_core::ComposedCellSource::Virtual { .. } => {
                if !cell.styles.is_empty() || !cell.ch.is_whitespace() {
                    break;
                }
                count = count.saturating_add(1);
            }
            editor_core::ComposedCellSource::Document { .. } => break,
        }
    }
    count
}

fn caret_x_cells_in_composed_line(line: &editor_core::ComposedLine, char_offset: usize) -> u32 {
    let indent_prefix = indent_prefix_cell_count(line);
    let mut x_cells: u32 = 0;
    for (idx, cell) in line.cells.iter().enumerate() {
        let anchor = match cell.source {
            editor_core::ComposedCellSource::Document { offset } => offset,
            editor_core::ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
        };

        if anchor < char_offset {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        if anchor > char_offset {
            break;
        }

        let is_indent_prefix = idx < indent_prefix;
        if is_indent_prefix {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        break;
    }
    x_cells
}

fn hit_test_composed_line_char_offset(line: &editor_core::ComposedLine, x_cells: usize) -> usize {
    let mut x = 0usize;
    for cell in &line.cells {
        let w = cell.width.max(1);
        if x_cells < x.saturating_add(w) {
            return match cell.source {
                editor_core::ComposedCellSource::Document { offset } => offset,
                editor_core::ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
            };
        }
        x = x.saturating_add(w);
    }
    line.char_offset_end
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wait_for_async_processing(ui: &mut EditorUi) {
        let start = std::time::Instant::now();
        loop {
            let polled = ui.poll_processing().unwrap();
            if !polled.pending {
                break;
            }
            if start.elapsed() > std::time::Duration::from_secs(2) {
                panic!("timeout waiting for async processing");
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    fn set_test_treesitter_registry(ui: &mut EditorUi) {
        // Keep the tree-sitter worker at normal priority in tests so a single grammar load/parse
        // finishes within the bounded wait window (see set_current_thread_qos_for_treesitter_worker).
        // Set here, before any worker is spawned by set_treesitter_* below.
        // SAFETY: test-only; called on the main test thread before spawning the worker.
        unsafe { std::env::set_var("EDITOR_CORE_DISABLE_TS_WORKER_QOS", "1") };

        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../editor-core-treesitter/tests/fixtures/treesitter");

        let json = serde_json::json!({
            "schema_version": 1,
            "root_dir": root.to_string_lossy(),
            "extension_map": {
                "rs": "rust"
            },
            "languages": {
                "rust": {
                    "wasm": "rust/language.wasm",
                    "highlights": "rust/highlights.scm",
                    "folds": "rust/folds.scm"
                }
            }
        })
        .to_string();

        ui.set_treesitter_registry_json(&json).unwrap();
    }

    fn shell_quote(raw: &str) -> String {
        format!("'{}'", raw.replace('\'', "'\\''"))
    }

    fn unique_temp_path(label: &str) -> std::path::PathBuf {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "editor-core-ui-{label}-{}-{stamp}.log",
            std::process::id()
        ))
    }

    fn lsp_capture_server_script(
        capture_path: &std::path::Path,
        capabilities: serde_json::Value,
    ) -> String {
        let body = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "result": { "capabilities": capabilities },
        })
        .to_string();
        format!(
            "body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; cat > {}",
            shell_quote(&body),
            shell_quote(capture_path.to_string_lossy().as_ref())
        )
    }

    fn captured_lsp_stdin(path: &std::path::Path) -> String {
        std::fs::read_to_string(path).unwrap_or_default()
    }

    fn wait_for_captured_lsp_stdin(path: &std::path::Path, needle: &str) -> String {
        for _ in 0..100 {
            let captured = captured_lsp_stdin(path);
            if captured.contains(needle) {
                return captured;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        panic!(
            "timed out waiting for LSP stdin to contain {needle:?}; captured: {}",
            captured_lsp_stdin(path)
        );
    }

    use editor_core::CursorCommand;
    use editor_core_treesitter::TreeSitterUpdateMode;

    #[test]
    fn lsp_processing_edit_apply_failure_records_status_and_returns_error() {
        let ui = EditorUi::new("abc", 80);

        let err = {
            let mut doc = ui.lock_doc();
            doc.lsp_last_cmd = Some("fake-lsp".to_string());
            let buffer_id = doc.buffer_id;
            doc.ws.close_buffer(buffer_id).unwrap();
            doc.apply_lsp_processing_edits([ProcessingEdit::ClearDiagnostics])
                .unwrap_err()
        };

        let UiError::Processor(message) = err else {
            panic!("expected processor error");
        };
        assert!(
            message.contains("failed to apply LSP processing edits"),
            "unexpected error message: {message}"
        );

        let status: serde_json::Value =
            serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
        assert_eq!(status["availability"], "failed");
        assert_eq!(status["state"], "failed");
        assert!(
            status["detail"]
                .as_str()
                .is_some_and(|detail| detail.contains("failed to apply LSP processing edits")),
            "unexpected LSP status: {status}"
        );
    }

    #[test]
    fn poll_processing_reports_lsp_failure_without_applied_success() {
        let mut ui = EditorUi::new("abc", 80);
        {
            let mut doc = ui.lock_doc();
            doc.lsp_last_cmd = Some("fake-lsp".to_string());
            doc.lsp_document_uri = Some("file:///test.rs".to_string());
            doc.lsp = Some(Arc::new(SharedLspSession {
                session: Mutex::new(None),
            }));
        }

        let result = ui.poll_processing().unwrap();
        assert!(!result.applied);
        assert!(!result.pending);

        let status: serde_json::Value =
            serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
        assert_eq!(status["availability"], "failed");
        assert!(
            status["detail"]
                .as_str()
                .is_some_and(|detail| detail.contains("LSP session is not available")),
            "unexpected LSP status: {status}"
        );
    }

    #[test]
    fn ui_lsp_on_type_formatting_triggers_for_server_declared_single_chars() {
        let capture_path = unique_temp_path("on-type-formatting");
        let capabilities = serde_json::json!({
            "documentOnTypeFormattingProvider": {
                "firstTriggerCharacter": ";",
                "moreTriggerCharacter": ["}"]
            }
        });
        let script = lsp_capture_server_script(&capture_path, capabilities);
        let args = vec!["-c".to_string(), script];
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root_uri = format!("file:///tmp/editor-core-ui-on-type-{stamp}");
        let doc_uri = format!("{root_uri}/main.rs");

        let mut ui = EditorUi::new("let value = 1", 80);
        ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
            .unwrap();

        ui.paste_text(";").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(80));
        let captured_after_paste = captured_lsp_stdin(&capture_path);
        assert!(
            !captured_after_paste.contains("textDocument/onTypeFormatting"),
            "paste_text must not trigger on-type formatting; captured: {captured_after_paste}"
        );

        ui.insert_text("a").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(80));
        let captured_after_non_trigger = captured_lsp_stdin(&capture_path);
        assert!(
            !captured_after_non_trigger.contains("textDocument/onTypeFormatting"),
            "non-trigger typing must not request on-type formatting; captured: {captured_after_non_trigger}"
        );

        ui.insert_text(";").unwrap();
        let captured = wait_for_captured_lsp_stdin(&capture_path, "textDocument/onTypeFormatting");
        assert!(
            captured.contains("\"ch\":\";\""),
            "on-type formatting request should carry trigger ';'; captured: {captured}"
        );

        ui.lsp_disable();
        let _ = std::fs::remove_file(capture_path);
    }

    #[test]
    fn poll_processing_reports_treesitter_worker_disconnected() {
        let mut ui = EditorUi::new("fn main() {}", 80);
        let (tx_worker, rx_worker) = mpsc::channel::<TreeSitterWorkerMsg>();
        drop(rx_worker);
        let (tx_events, rx_events) = mpsc::channel::<TreeSitterWorkerEvent>();
        drop(tx_events);

        {
            let mut doc = ui.lock_doc();
            doc.treesitter = Some(TreeSitterAsyncWorker {
                tx: tx_worker,
                rx: rx_events,
                join: None,
                requested_version: Some(1),
                applied_version: None,
                last_update_mode: None,
            });
        }

        let err = ui.poll_processing().unwrap_err();
        let UiError::Processor(message) = err else {
            panic!("expected processor error");
        };
        assert!(
            message.contains("tree-sitter worker disconnected"),
            "unexpected error message: {message}"
        );
    }

    #[test]
    fn ui_text_roundtrip() {
        let ui = EditorUi::new("hello", 80);
        assert_eq!(ui.text(), "hello");
    }

    #[test]
    fn ui_clone_view_shares_text_but_keeps_view_state_independent() {
        let mut ui1 = EditorUi::new("abc\ndef\n", 80);
        let mut ui2 = ui1.clone_view(80).unwrap();

        ui1.set_selections_offsets(&[(0, 0)], 0).unwrap();
        ui2.set_selections_offsets(&[(4, 4)], 0).unwrap();
        assert_eq!(ui1.primary_selection_offsets(), (0, 0));
        assert_eq!(ui2.primary_selection_offsets(), (4, 4));

        // Text edits are shared across views.
        ui1.insert_text("X").unwrap();
        assert_eq!(ui1.text(), "Xabc\ndef\n");
        assert_eq!(ui2.text(), "Xabc\ndef\n");

        // Each view tracks its own caret/selection, but receives the same text delta.
        assert_eq!(ui1.primary_selection_offsets(), (1, 1));
        assert_eq!(ui2.primary_selection_offsets(), (5, 5));

        // Cursor moves in one view do not affect the other view.
        ui1.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
        assert_eq!(ui1.cursor_state().offset, 0);
        assert_eq!(ui2.cursor_state().offset, 5);
    }

    #[test]
    fn ui_clone_view_has_independent_scroll_state() {
        let text = (0..200)
            .map(|i| format!("line {i}"))
            .collect::<Vec<_>>()
            .join("\n");
        let mut ui1 = EditorUi::new(text.as_str(), 80);
        let mut ui2 = ui1.clone_view(80).unwrap();

        ui1.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
        ui2.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
        ui1.set_viewport_px(800, 50, 1.0).unwrap(); // 5 rows visible
        ui2.set_viewport_px(800, 50, 1.0).unwrap();

        ui1.set_smooth_scroll_state(10, 0);
        ui2.set_smooth_scroll_state(20, 0);

        assert_eq!(ui1.viewport_state().scroll_top, 10);
        assert_eq!(ui2.viewport_state().scroll_top, 20);
    }

    #[test]
    fn ui_insert_and_delete() {
        let mut ui = EditorUi::new("", 80);
        ui.insert_text("abc").unwrap();
        assert_eq!(ui.text(), "abc");
        ui.backspace().unwrap();
        assert_eq!(ui.text(), "ab");
        ui.delete_forward().unwrap(); // no-op at end
        assert_eq!(ui.text(), "ab");
    }

    #[test]
    fn ui_move_visual_by_rows_collapses_selection_to_caret() {
        let mut ui = EditorUi::new("aaa\nbbb\nccc", 80);

        // Select "bbb" (offset 4..7). This also places the caret at the active end (offset 7).
        ui.set_selections_offsets(&[(4, 7)], 0).unwrap();
        assert!(ui.cursor_state().selection.is_some());
        assert_eq!(ui.cursor_state().offset, 7);

        // Move up: should first clear selection (caret stays at 7), then move to line 0 col 3 => offset 3.
        ui.move_visual_by_rows(-1).unwrap();
        assert!(ui.cursor_state().selection.is_none());
        assert_eq!(ui.primary_selection_offsets(), (3, 3));

        // Re-create selection and move down: should clear selection, then move to line 2 col 3 => offset 11.
        ui.set_selections_offsets(&[(4, 7)], 0).unwrap();
        ui.move_visual_by_rows(1).unwrap();
        assert!(ui.cursor_state().selection.is_none());
        assert_eq!(ui.primary_selection_offsets(), (11, 11));
    }

    #[test]
    fn ui_keyboard_navigation_scrolls_to_keep_caret_visible() {
        let mut ui = EditorUi::new("0\n1\n2\n3\n4\n5\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20, // 2 rows at 10px line height
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        let vp0 = ui.viewport_state();
        assert_eq!(vp0.height, Some(2));
        assert_eq!(vp0.scroll_top, 0);

        // Move down within the viewport: no scroll.
        ui.move_visual_by_rows(1).unwrap();
        let vp1 = ui.viewport_state();
        assert_eq!(vp1.scroll_top, 0);

        // Move down out of the viewport: scroll should advance.
        ui.move_visual_by_rows(1).unwrap();
        let vp2 = ui.viewport_state();
        assert_eq!(vp2.scroll_top, 1);
        assert_eq!(vp2.sub_row_offset, 0);

        // Jump to end: viewport should scroll so caret stays visible.
        ui.move_to_document_end().unwrap();
        let vp3 = ui.viewport_state();
        let caret_off = ui.cursor_state().offset;
        let (caret_row, _caret_x) = ui.char_offset_to_visual(caret_off).unwrap();
        let h = vp3.height.unwrap_or(1);
        assert!(
            caret_row >= vp3.scroll_top && caret_row < vp3.scroll_top.saturating_add(h),
            "expected caret row to be within visible lines after navigation"
        );
    }

    #[test]
    fn ui_insert_text_scrolls_to_keep_caret_visible() {
        let mut ui = EditorUi::new("", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20, // 2 rows at 10px line height
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        // Pasting multi-line text should scroll so the caret stays visible.
        let mut s = String::new();
        for _ in 0..200 {
            s.push_str("x\n");
        }
        ui.insert_text(&s).unwrap();

        let vp = ui.viewport_state();
        let caret_off = ui.cursor_state().offset;
        let (caret_row, _caret_x) = ui.char_offset_to_visual(caret_off).unwrap();
        let h = vp.height.unwrap_or(1);
        assert!(
            caret_row >= vp.scroll_top && caret_row < vp.scroll_top.saturating_add(h),
            "expected caret row to be within visible lines after paste/insert"
        );
        assert!(
            vp.scroll_top > 0,
            "expected viewport to scroll for multi-line insert"
        );
    }

    #[test]
    fn ui_insert_text_does_not_snap_smooth_scroll_when_caret_visible() {
        let mut ui = EditorUi::new("", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        ui.set_smooth_scroll_state(0, 12345);
        ui.insert_text("a").unwrap();

        let vp = ui.viewport_state();
        assert_eq!(vp.scroll_top, 0);
    }

    #[test]
    fn ui_undo_redo_scrolls_to_keep_caret_visible() {
        // Long document so `scroll_top` can remain > 0 after undo/redo (i.e. not clamped away).
        let doc = (0..200)
            .map(|i| i.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        let mut ui = EditorUi::new(&doc, 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20, // 2 rows at 10px line height
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        // Make a small edit near the top so undo/redo moves the caret to row 0.
        ui.insert_text("!").unwrap();

        // Manually scroll away from the caret (simulates the user having scrolled elsewhere).
        let vp = ui.viewport_state();
        let total = vp.total_visual_lines.max(1);
        let visible = vp.height.unwrap_or(total).max(1);
        let bottom = total.saturating_sub(visible);
        ui.set_smooth_scroll_state(bottom, 0);
        assert!(
            ui.viewport_state().scroll_top > 0,
            "expected manual scroll to move viewport away from caret"
        );

        // Undo should scroll back to keep caret visible.
        ui.undo().unwrap();
        assert_eq!(ui.viewport_state().scroll_top, 0);

        // Redo should also scroll back if we're scrolled away again.
        ui.set_smooth_scroll_state(bottom, 0);
        assert!(ui.viewport_state().scroll_top > 0);
        ui.redo().unwrap();
        assert_eq!(ui.viewport_state().scroll_top, 0);
    }

    #[test]
    fn ui_set_smooth_scroll_state_clamps_and_updates_viewport_state() {
        let mut ui = EditorUi::new("0\n1\n2\n3\n4\n5\n6\n7", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20, // 2 rows at 10px line height
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        let vp0 = ui.viewport_state();
        assert_eq!(vp0.height, Some(2));
        assert_eq!(vp0.total_visual_lines, 8);

        // Set a fractional scroll position (3 + 0.5 rows).
        ui.set_smooth_scroll_state(3, 32768);
        let vp1 = ui.viewport_state();
        assert_eq!(vp1.scroll_top, 3);
        assert_eq!(vp1.sub_row_offset, 32768);

        // Clamp to the maximum scroll position (total - height = 6).
        ui.set_smooth_scroll_state(999, 65535);
        let vp2 = ui.viewport_state();
        assert_eq!(vp2.scroll_top, 6);
        assert_eq!(vp2.sub_row_offset, 0);
    }

    #[test]
    fn ui_backspace_and_delete_forward_are_grapheme_aware() {
        // "á" = 'a' + COMBINING ACUTE ACCENT (2 Unicode scalar values, 1 grapheme cluster).
        let s = "a\u{0301}";

        // Backspace at end should delete the whole grapheme cluster.
        let mut ui = EditorUi::new(s, 80);
        ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // caret at end (scalar offset 2)
        ui.backspace().unwrap();
        assert_eq!(ui.text(), "");

        // Delete-forward at start should also delete the whole grapheme cluster.
        let mut ui2 = EditorUi::new(s, 80);
        ui2.set_selections_offsets(&[(0, 0)], 0).unwrap(); // caret at start
        ui2.delete_forward().unwrap();
        assert_eq!(ui2.text(), "");
    }

    #[test]
    fn ui_auto_pairs_auto_close_skip_over_and_delete_pair_work_when_enabled() {
        let mut ui = EditorUi::new("", 80);
        ui.set_auto_pairs_enabled(true).unwrap();

        ui.commit_text("(").unwrap();
        assert_eq!(ui.text(), "()");
        assert_eq!(ui.primary_selection_offsets(), (1, 1));

        // Skip-over closing delimiter.
        ui.commit_text(")").unwrap();
        assert_eq!(ui.text(), "()");
        assert_eq!(ui.primary_selection_offsets(), (2, 2));

        // Delete-pair via UI backspace (grapheme-aware fallback + pair special-case).
        ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
        ui.backspace().unwrap();
        assert_eq!(ui.text(), "");
        assert_eq!(ui.primary_selection_offsets(), (0, 0));
    }

    #[test]
    fn ui_paste_text_does_not_trigger_auto_pairs_rules() {
        let mut ui = EditorUi::new("", 80);
        ui.set_auto_pairs_enabled(true).unwrap();

        ui.paste_text("(").unwrap();
        assert_eq!(ui.text(), "(");
        assert_eq!(ui.primary_selection_offsets(), (1, 1));
    }

    #[test]
    fn ui_clone_view_preserves_auto_pairs_config() {
        let mut ui = EditorUi::new("", 80);
        ui.set_auto_pairs_enabled(true).unwrap();

        let mut cloned = ui.clone_view(80).unwrap();
        cloned.commit_text("(").unwrap();

        assert_eq!(cloned.text(), "()");
        assert_eq!(cloned.primary_selection_offsets(), (1, 1));
    }

    #[test]
    fn ui_clone_view_preserves_bracket_match_highlights_enabled() {
        let mut ui = EditorUi::new("(a)", 80);
        ui.set_bracket_match_highlights_enabled(true).unwrap();

        let mut cloned = ui.clone_view(80).unwrap();
        cloned.set_selections_offsets(&[(1, 1)], 0).unwrap();

        let grid = {
            let mut doc = cloned.lock_doc();
            doc.ws
                .get_viewport_content_styled(cloned.view_id, 0, 1)
                .unwrap()
        };
        let styles_at_open = grid
            .lines
            .first()
            .and_then(|l| l.cells.first())
            .map(|c| c.styles.clone())
            .unwrap_or_default();
        let styles_at_close = grid
            .lines
            .first()
            .and_then(|l| l.cells.get(2))
            .map(|c| c.styles.clone())
            .unwrap_or_default();

        assert!(
            styles_at_open.contains(&MATCH_HIGHLIGHT_STYLE_ID),
            "expected opening bracket to have MATCH_HIGHLIGHT_STYLE_ID"
        );
        assert!(
            styles_at_close.contains(&MATCH_HIGHLIGHT_STYLE_ID),
            "expected closing bracket to have MATCH_HIGHLIGHT_STYLE_ID"
        );
    }

    #[test]
    fn ui_bracket_match_highlights_apply_match_style_to_brackets() {
        let mut ui = EditorUi::new("(a)", 80);
        ui.set_bracket_match_highlights_enabled(true).unwrap();

        // Place caret between '(' and 'a' so the match is unambiguous.
        ui.set_selections_offsets(&[(1, 1)], 0).unwrap();

        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 1)
                .unwrap()
        };
        let styles_at_open = grid
            .lines
            .first()
            .and_then(|l| l.cells.first())
            .map(|c| c.styles.clone())
            .unwrap_or_default();
        let styles_at_close = grid
            .lines
            .first()
            .and_then(|l| l.cells.get(2))
            .map(|c| c.styles.clone())
            .unwrap_or_default();

        assert!(
            styles_at_open.contains(&MATCH_HIGHLIGHT_STYLE_ID),
            "expected opening bracket to have MATCH_HIGHLIGHT_STYLE_ID"
        );
        assert!(
            styles_at_close.contains(&MATCH_HIGHLIGHT_STYLE_ID),
            "expected closing bracket to have MATCH_HIGHLIGHT_STYLE_ID"
        );
    }

    #[test]
    fn ui_move_to_matching_bracket_jumps_to_pair() {
        let mut ui = EditorUi::new("(a[b]c)", 80);
        ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
        ui.move_to_matching_bracket().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (6, 6));
    }

    #[test]
    fn ui_selected_text_and_delete_selections_only() {
        let mut ui = EditorUi::new("one two three", 80);

        // Multi-selection: "one" and "three" (skip the caret between them).
        ui.set_selections_offsets(&[(0, 3), (4, 4), (8, 13)], 0)
            .unwrap();
        assert_eq!(ui.selected_text(), "one\nthree");

        // Cut should delete only the non-empty selections.
        ui.delete_selections_only().unwrap();
        assert_eq!(ui.text(), " two ");
        assert_eq!(ui.selected_text(), "");
        assert_eq!(ui.primary_selection_offsets(), (0, 0));

        // With no selection, delete_selections_only is a no-op.
        ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
        ui.delete_selections_only().unwrap();
        assert_eq!(ui.text(), " two ");
    }

    #[test]
    fn ui_word_movement_and_word_deletion() {
        let mut ui = EditorUi::new("one two", 80);

        // Move by word boundaries.
        assert_eq!(ui.primary_selection_offsets(), (0, 0));
        ui.move_word_right().unwrap(); // 0 -> 3 ("one| two")
        assert_eq!(ui.primary_selection_offsets(), (3, 3));
        ui.move_word_right().unwrap(); // 3 -> 4 ("one |two")
        assert_eq!(ui.primary_selection_offsets(), (4, 4));
        ui.move_word_left().unwrap(); // 4 -> 3
        assert_eq!(ui.primary_selection_offsets(), (3, 3));

        // Shift+Option behavior (modify selection).
        ui.set_selections_offsets(&[(0, 0)], 0).unwrap();
        ui.move_word_right_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3));
        ui.move_word_right_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 4));

        // Delete word back/forward.
        let mut ui2 = EditorUi::new("one two", 80);
        ui2.set_selections_offsets(&[(7, 7)], 0).unwrap();
        ui2.delete_word_back().unwrap();
        assert_eq!(ui2.text(), "one ");

        let mut ui3 = EditorUi::new("one two", 80);
        ui3.set_selections_offsets(&[(0, 0)], 0).unwrap();
        ui3.delete_word_forward().unwrap();
        assert_eq!(ui3.text(), " two");
    }

    #[test]
    fn ui_line_document_and_page_navigation() {
        let mut ui = EditorUi::new("abc\ndef", 80);

        // Visual line start/end.
        ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // "ab|c"
        ui.move_to_visual_line_start().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 0));
        ui.move_to_visual_line_end().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (3, 3)); // end of "abc"

        // Document start/end.
        ui.move_to_document_end().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (7, 7)); // end of "def"
        ui.move_to_document_start().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 0));

        // Page movement uses viewport height in rows.
        let mut ui2 = EditorUi::new("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n", 80);
        ui2.set_render_metrics(12.0, 10.0, 10.0, 0.0, 0.0);
        ui2.set_viewport_px(100, 30, 1.0).unwrap(); // 3 rows

        ui2.set_selections_offsets(&[(0, 0)], 0).unwrap();
        ui2.move_visual_by_pages(1).unwrap();
        assert_eq!(ui2.cursor_state().position.line, 3);

        ui2.move_visual_by_pages(-1).unwrap();
        assert_eq!(ui2.cursor_state().position.line, 0);

        // Shift+PageDown extends selection by pages.
        ui2.set_selections_offsets(&[(0, 0)], 0).unwrap();
        ui2.move_visual_by_pages_and_modify_selection(1).unwrap();
        assert_eq!(ui2.primary_selection_offsets(), (0, 6)); // line 3 start offset = 3 * 2
    }

    #[test]
    fn ui_undo_redo_roundtrip() {
        let mut ui = EditorUi::new("", 80);
        ui.insert_text("a").unwrap();
        ui.end_undo_group().unwrap();
        ui.insert_text("b").unwrap();
        assert_eq!(ui.text(), "ab");
        ui.undo().unwrap();
        assert_eq!(ui.text(), "a");
        ui.redo().unwrap();
        assert_eq!(ui.text(), "ab");
    }

    #[test]
    fn ui_expand_selection_by_word_is_expand_only() {
        let mut ui = EditorUi::new("one two three", 80);
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 4,
        }))
        .unwrap(); // at "two"

        ui.expand_selection_by(
            ExpandSelectionUnit::Word,
            1,
            ExpandSelectionDirection::Forward,
        )
        .unwrap();
        assert_eq!(ui.primary_selection_offsets(), (4, 7)); // "two"

        ui.expand_selection_by(
            ExpandSelectionUnit::Word,
            1,
            ExpandSelectionDirection::Forward,
        )
        .unwrap();
        assert_eq!(ui.primary_selection_offsets(), (4, 13)); // "two three"

        ui.expand_selection_by(
            ExpandSelectionUnit::Word,
            1,
            ExpandSelectionDirection::Backward,
        )
        .unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 13)); // "one two three"
    }

    #[test]
    fn ui_word_boundary_config_affects_select_word() {
        let mut ui = EditorUi::new("foo-bar", 80);
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"

        ui.set_word_boundary_ascii_boundary_chars(".").unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection))
            .unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 7)); // "foo-bar"

        ui.reset_word_boundary_defaults().unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection))
            .unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"
    }

    #[test]
    fn ui_marked_text_replace_and_commit() {
        let mut ui = EditorUi::new("", 80);
        ui.set_marked_text("你").unwrap();
        assert_eq!(ui.text(), "你");
        ui.set_marked_text("你好").unwrap();
        assert_eq!(ui.text(), "你好");
        ui.commit_text("你好!").unwrap();
        assert_eq!(ui.text(), "你好!");
    }

    #[test]
    fn ui_marked_text_empty_cancels_and_restores_original_text_and_selection() {
        // Start composition by replacing a selection, then cancel it by setting empty marked text.
        let mut ui = EditorUi::new("abcXYZdef", 80);
        ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
            .unwrap();
        assert_eq!(ui.text(), "abc你def");

        // Cancel: empty marked text should restore the original "XYZ" and selection.
        ui.set_marked_text_with_selection("", 0, 0, None).unwrap();
        assert_eq!(ui.text(), "abcXYZdef");
        assert_eq!(ui.primary_selection_offsets(), (3, 6));

        // Also cover the common case: composition started at a caret (no selection).
        let mut ui2 = EditorUi::new("abc", 80);
        ui2.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 3,
        }))
        .unwrap();
        ui2.set_marked_text("你").unwrap();
        assert_eq!(ui2.text(), "abc你");
        ui2.set_marked_text("").unwrap();
        assert_eq!(ui2.text(), "abc");
        assert_eq!(ui2.primary_selection_offsets(), (3, 3));
    }

    #[test]
    fn ui_marked_text_honors_selection_and_applies_style_layer() {
        let mut ui = EditorUi::new("", 80);

        // Marked text = "你好", caret inside composition after the first char.
        ui.set_marked_text_with_selection("你好", 1, 0, None)
            .unwrap();
        assert_eq!(ui.text(), "你好");

        // Cursor is at offset 1 => (line 0, column 1).
        assert_eq!(ui.cursor_state().position, Position::new(0, 1));

        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 1)
                .unwrap()
        };
        assert_eq!(grid.lines.len(), 1);
        assert_eq!(grid.lines[0].cells.len(), 2);
        assert!(
            grid.lines[0].cells[0]
                .styles
                .contains(&IME_MARKED_TEXT_STYLE_ID)
        );
        assert!(
            grid.lines[0].cells[1]
                .styles
                .contains(&IME_MARKED_TEXT_STYLE_ID)
        );

        // Committing clears the marked style layer.
        ui.commit_text("你好!").unwrap();
        let grid2 = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 1)
                .unwrap()
        };
        assert!(
            grid2.lines[0]
                .cells
                .iter()
                .all(|c| !c.styles.contains(&IME_MARKED_TEXT_STYLE_ID)),
            "expected IME marked text style to be cleared after commit"
        );
    }

    #[test]
    fn ui_marked_text_replacement_range_overrides_current_selection() {
        // Replacement range should allow host IME to replace an arbitrary document slice
        // (e.g. when the input method decides to replace a previously inserted segment).
        let mut ui = EditorUi::new("abcXYZdef", 80);

        // Replace "XYZ" with IME marked text "你" (selection at end of marked text).
        ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
            .unwrap();
        assert_eq!(ui.text(), "abc你def");

        let marked = ui.marked_range().unwrap();
        assert_eq!(marked, (3, 1));

        // Commit should replace the marked range (not insert).
        ui.commit_text("你好").unwrap();
        assert_eq!(ui.text(), "abc你好def");
        assert!(ui.marked_range().is_none());
    }

    #[test]
    fn ui_mouse_sets_cursor_and_selection() {
        let mut ui = EditorUi::new("abcd\nefgh\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 60,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 60, 1.0).unwrap();

        // Click near column 2 on first line.
        ui.mouse_down(25.0, 10.0).unwrap();
        assert_eq!(ui.cursor_state().position, Position::new(0, 2));

        // Drag to second line column 1.
        ui.mouse_dragged(15.0, 30.0).unwrap();
        let cursor = ui.cursor_state();
        assert!(cursor.selection.is_some());
        ui.mouse_up();
    }

    #[test]
    fn ui_mouse_drag_selection_keeps_cursor_at_active_end_for_keyboard_moves() {
        let mut ui = EditorUi::new("aaaa\nbbbb\ncccc", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 60,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 60, 1.0).unwrap();

        // Drag-select within the first line: anchor at col 0, active end at col 3.
        ui.mouse_down(5.0, 10.0).unwrap();
        ui.mouse_dragged(35.0, 10.0).unwrap();

        let s0 = ui.primary_selection_offsets();
        assert_eq!(s0, (0, 3));

        // Now a vertical move should collapse selection to the active end (col 3), not the anchor.
        ui.move_visual_by_rows(1).unwrap();
        let s1 = ui.primary_selection_offsets();
        assert_eq!(s1, (8, 8));
    }

    #[test]
    fn ui_render_includes_caret_overlay() {
        let mut ui = EditorUi::new("abc", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: std::collections::BTreeMap::new(),
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(80, 40, 1.0).unwrap();

        // Put caret after 'c' (x=3).
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 3,
        }))
        .unwrap();
        let rgba = ui.render_rgba_visible().unwrap();
        assert_eq!(pixel(&rgba, 80, 30, 10), [0, 0, 200, 255]);
        assert_eq!(pixel(&rgba, 80, 70, 30), [10, 20, 30, 255]);
    }

    #[test]
    fn ui_caret_width_and_visibility_affect_render_rgba() {
        let mut ui = EditorUi::new("", 80);
        ui.set_render_config(RenderConfig {
            width_px: 20,
            height_px: 10,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(0xFF, 0xFF, 0xFF, 0xFF),
            foreground: editor_core_render_skia::Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            selection_background: editor_core_render_skia::Rgba8::new(0xC7, 0xDD, 0xFF, 0xFF),
            caret: editor_core_render_skia::Rgba8::new(0x00, 0x00, 0x00, 0xFF),
            styles: std::collections::BTreeMap::new(),
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(20, 10, 1.0).unwrap();

        ui.set_caret_width_px(4.0);
        ui.set_caret_visible(true);
        let rgba0 = ui.render_rgba_visible().unwrap();
        let caret_px = [0x00, 0x00, 0x00, 0xFF];
        let caret_count0 = rgba0.chunks_exact(4).filter(|p| *p == caret_px).count();
        assert_eq!(
            caret_count0,
            4 * 10,
            "expected caret to fill a 4x10 rectangle"
        );

        ui.set_caret_visible(false);
        let rgba1 = ui.render_rgba_visible().unwrap();
        let caret_count1 = rgba1.chunks_exact(4).filter(|p| *p == caret_px).count();
        assert_eq!(
            caret_count1, 0,
            "expected caret pixels to disappear when hidden"
        );
    }

    #[test]
    fn ui_render_includes_partially_visible_bottom_row_even_without_sub_row_offset() {
        // Height is not a multiple of line height: the bottom 5px should still show the next row.
        let mut ui = EditorUi::new("0\n1\n \n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 40,
            height_px: 25,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(40, 25, 1.0).unwrap();

        // Theme background fills the whole buffer; a style background lets us detect if the row was rendered.
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: std::collections::BTreeMap::new(),
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });

        let style_id = 0xDEAD_BEEFu32;
        let mut styles = std::collections::BTreeMap::new();
        styles.insert(
            style_id,
            editor_core_render_skia::StyleColors::new(
                None,
                Some(editor_core_render_skia::Rgba8::new(200, 0, 0, 255)),
            ),
        );
        ui.set_style_colors(styles);

        // Style the space in the 3rd line (" \n") so glyph rasterization does not affect the sample.
        // "0\n1\n \n" => the space is at char offset 4.
        ui.add_style(4, 5, style_id).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        // The bottom pixel is inside the partially visible 3rd row (y=20..25).
        assert_eq!(pixel(&rgba, 40, 1, 24), [200, 0, 0, 255]);
    }

    #[test]
    fn ui_render_includes_partially_visible_bottom_row_with_top_padding() {
        // Same as the previous test, but with a top inset (padding_y_px) to match the AppKit demo.
        //
        // Regression guard: if we treat `padding_y_px` as top+bottom padding, the bottom row can
        // disappear until it crosses a threshold (the "bottom padding" area).
        let mut ui = EditorUi::new("0\n1\n \n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 40,
            height_px: 35,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 8.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(40, 35, 1.0).unwrap();

        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: std::collections::BTreeMap::new(),
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });

        let style_id = 0xBEEF_CAFEu32;
        let mut styles = std::collections::BTreeMap::new();
        styles.insert(
            style_id,
            editor_core_render_skia::StyleColors::new(
                None,
                Some(editor_core_render_skia::Rgba8::new(200, 0, 0, 255)),
            ),
        );
        ui.set_style_colors(styles);

        // Style the space in the 3rd line (" \n") so glyph rasterization does not affect the sample.
        // "0\n1\n \n" => the space is at char offset 4.
        ui.add_style(4, 5, style_id).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        // The bottom pixel is inside the partially visible 3rd row (y=28..35).
        assert_eq!(pixel(&rgba, 40, 1, 34), [200, 0, 0, 255]);
    }

    #[test]
    fn ui_exposes_selection_offsets_and_offset_mapping() {
        let mut ui = EditorUi::new("abcd\nefgh\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 60,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 60, 1.0).unwrap();

        // Select "bc" in first line (offsets 1..3).
        ui.execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 1),
            end: Position::new(0, 3),
        }))
        .unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 3));

        // Offset -> visual mapping.
        let (row, x) = ui.char_offset_to_visual(2).unwrap();
        assert_eq!((row, x), (0, 2));
        assert_eq!(ui.visual_to_char_offset(0, 2).unwrap(), 2);

        // Offset -> view point mapping (top-left origin).
        let (x_px, y_px) = ui.char_offset_to_view_point_px(2).unwrap();
        assert_eq!((x_px, y_px), (20.0, 0.0));
        assert_eq!(ui.line_height_px(), 20.0);

        // View hit-test.
        assert_eq!(ui.view_point_to_char_offset(25.0, 10.0).unwrap(), 2);
    }

    #[test]
    fn ui_char_offset_to_logical_position_maps_offsets() {
        let ui = EditorUi::new("ab\ncde\nf", 80);
        // "ab\ncde\nf"
        // 0:a 1:b 2:\n 3:c 4:d 5:e 6:\n 7:f
        assert_eq!(ui.char_offset_to_logical_position(0), (0, 0));
        assert_eq!(ui.char_offset_to_logical_position(1), (0, 1));
        assert_eq!(ui.char_offset_to_logical_position(3), (1, 0)); // 'c'
        assert_eq!(ui.char_offset_to_logical_position(4), (1, 1)); // 'd'
        assert_eq!(ui.char_offset_to_logical_position(7), (2, 0)); // 'f'

        // Clamp: beyond end maps to the last valid position.
        assert_eq!(ui.char_offset_to_logical_position(999), (2, 1));
    }

    #[test]
    fn ui_minimap_json_roundtrip_has_lines() {
        let mut ui = EditorUi::new("a\nb\nc", 80);
        let json = ui.minimap_json(0, 20);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert!(v.get("lines").is_some());
        assert_eq!(v.get("start_visual_row").and_then(|n| n.as_u64()), Some(0));
        assert_eq!(v.get("count").and_then(|n| n.as_u64()), Some(20));
        assert!(
            v.get("actual_line_count")
                .and_then(|n| n.as_u64())
                .unwrap_or(0)
                > 0
        );
    }

    #[test]
    fn ui_smooth_scroll_by_pixels_updates_sub_row_offset_and_hit_testing() {
        let mut ui = EditorUi::new("a\nb\nc\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 20,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(80, 20, 1.0).unwrap();

        let vp0 = ui.viewport_state();
        assert_eq!(vp0.scroll_top, 0);
        assert_eq!(vp0.sub_row_offset, 0);
        assert_eq!(ui.viewport_row_count_for_render(&vp0), 2);

        // Scrolling up at the top should clamp to 0 (no wrap-around / shake).
        ui.scroll_by_pixels(-5.0);
        let vp0b = ui.viewport_state();
        assert_eq!(vp0b.scroll_top, 0);
        assert_eq!(vp0b.sub_row_offset, 0);

        // Scroll down by half a row.
        ui.scroll_by_pixels(5.0);

        let vp = ui.viewport_state();
        assert_eq!(vp.scroll_top, 0);
        assert_eq!(vp.sub_row_offset, 32768); // 0.5 * 65536
        assert_eq!(ui.viewport_row_count_for_render(&vp), 3);

        // The start of the 2nd line should now map to y=5 (10 - 5).
        let b_off = 2usize; // "b" in "a\nb\nc\n"
        let (_x, y) = ui.char_offset_to_view_point_px(b_off).unwrap();
        assert_eq!(y, 5.0);

        // Hit-test should take the scroll offset into account:
        // - top 5px still belong to line 0
        // - y>=5 moves into line 1
        assert_eq!(ui.view_point_to_char_offset(0.0, 4.0).unwrap(), 0);
        assert_eq!(ui.view_point_to_char_offset(0.0, 5.0).unwrap(), 2);
        assert_eq!(ui.view_point_to_char_offset(0.0, 9.0).unwrap(), 2);

        // Scrolling back up by the same amount resets the sub-row offset.
        ui.scroll_by_pixels(-5.0);
        let vp2 = ui.viewport_state();
        assert_eq!(vp2.scroll_top, 0);
        assert_eq!(vp2.sub_row_offset, 0);
    }

    #[test]
    fn ui_gutter_shifts_view_point_mapping() {
        let mut ui = EditorUi::new("abc\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap(); // gutter = 20px

        let (x_px, y_px) = ui.char_offset_to_view_point_px(0).unwrap();
        assert_eq!((x_px, y_px), (20.0, 0.0));

        // Hit-testing inside gutter should clamp to column 0.
        assert_eq!(ui.view_point_to_char_offset(5.0, 10.0).unwrap(), 0);
    }

    #[test]
    fn ui_inlay_hints_affect_hit_testing_and_view_point_mapping() {
        let mut ui = EditorUi::new("ab\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        // Insert an inlay hint at position (line=0, character=1), with a single space label so
        // renderer tests can sample background deterministically.
        ui.lsp_apply_inlay_hints_json(
            r#"[
              { "position": { "line": 0, "character": 1 }, "label": " " }
            ]"#,
        )
        .unwrap();

        // With the inlay hint inserted between 'a' and 'b', the 'b' glyph shifts right by 1 cell.
        // So x=25 (col=2) should still map to char offset 1 (before 'b'), not to end-of-line.
        assert_eq!(ui.view_point_to_char_offset(25.0, 10.0).unwrap(), 1);

        // Caret at end-of-line should include the inlay hint width: x = 3 cells * 10px.
        assert_eq!(ui.char_offset_to_view_point_px(2).unwrap(), (30.0, 0.0));
    }

    #[test]
    fn ui_gutter_click_toggles_fold_state() {
        let text = "fn main() {\n  let x = 1;\n}\n";
        let mut ui = EditorUi::new(text, 80);
        set_test_treesitter_registry(&mut ui);
        ui.set_treesitter_rust_default().unwrap();
        wait_for_async_processing(&mut ui);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 80,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 80, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap();

        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected a fold region starting at line 0"
        );

        // Click in gutter at visual row 0.
        ui.mouse_down(5.0, 10.0).unwrap();
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| r.start_line == 0 && r.is_collapsed),
            "expected fold region to become collapsed after gutter click"
        );

        ui.mouse_down(5.0, 10.0).unwrap();
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected fold region to expand after second gutter click"
        );
    }

    #[test]
    fn ui_nested_fold_unfold_sequence_keeps_inner_toggleable() {
        // Regression for: fold inner -> fold outer -> unfold outer -> inner must still unfold.
        let text =
            "fn main() {\n  if true {\n    if true {\n      println!(\"hi\");\n    }\n  }\n}\n";
        let mut ui = EditorUi::new(text, 80);
        set_test_treesitter_registry(&mut ui);
        ui.set_treesitter_rust_default().unwrap();
        wait_for_async_processing(&mut ui);
        ui.set_render_config(RenderConfig {
            width_px: 260,
            height_px: 200,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(260, 200, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap();

        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.len() >= 2,
            "expected nested fold regions from Tree-sitter"
        );

        // Pick an innermost region and its closest outer region.
        let inner = regions
            .iter()
            .filter(|r| r.end_line > r.start_line)
            .min_by_key(|r| r.end_line - r.start_line)
            .cloned()
            .expect("expected at least one fold region");
        let outer = regions
            .iter()
            .filter(|r| r.start_line < inner.start_line && r.end_line >= inner.end_line)
            .min_by_key(|r| r.end_line - r.start_line)
            .cloned()
            .expect("expected an outer region containing inner");

        let click_gutter_at_start_line = |ui: &mut EditorUi, start_line: usize| {
            let (row, _x_cells) = {
                let mut doc = ui.lock_doc();
                doc.ws
                    .logical_to_visual_for_view(ui.view_id, start_line, 0)
                    .unwrap()
                    .expect("start line should be visible")
            };
            let y = row as f32 * ui.render_config.line_height_px
                + ui.render_config.line_height_px * 0.5;
            ui.mouse_down(5.0, y).unwrap();
            ui.mouse_up();
        };

        // 1) Fold inner.
        click_gutter_at_start_line(&mut ui, inner.start_line);
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| {
                r.start_line == inner.start_line && r.end_line == inner.end_line && r.is_collapsed
            }),
            "expected inner region to be collapsed"
        );

        // 2) Fold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| {
                r.start_line == outer.start_line && r.end_line == outer.end_line && r.is_collapsed
            }),
            "expected outer region to be collapsed"
        );

        // 3) Unfold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| {
                r.start_line == outer.start_line && r.end_line == outer.end_line && !r.is_collapsed
            }),
            "expected outer region to be expanded"
        );

        // 4) Unfold inner (must still be toggleable).
        click_gutter_at_start_line(&mut ui, inner.start_line);
        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| {
                r.start_line == inner.start_line && r.end_line == inner.end_line && !r.is_collapsed
            }),
            "expected inner region to be expanded after outer unfolded"
        );
    }

    #[test]
    fn ui_set_selections_offsets_and_insert_text_applies_to_all_carets() {
        let mut ui = EditorUi::new("abc\ndef\n", 80);

        // Two carets: start of line 0 (offset 0) and start of line 1 (offset 4).
        ui.set_selections_offsets(&[(0, 0), (4, 4)], 0).unwrap();
        let (ranges, primary) = ui.selections_offsets();
        assert_eq!(ranges, vec![(0, 0), (4, 4)]);
        assert_eq!(primary, 0);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "Xabc\nXdef\n");
    }

    #[test]
    fn ui_rect_selection_replaces_each_line_range() {
        let mut ui = EditorUi::new("abc\ndef\nghi\n", 80);

        // Box select column 1..2 across lines 0..2.
        // anchor: line0 col1 => offset 1 ('b')
        // active:  line2 col2 => offset 10 ('i')
        ui.set_rect_selection_offsets(1, 10).unwrap();

        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 3);
        assert_eq!(ranges[0], (1, 2));
        assert_eq!(ranges[1], (5, 6));
        assert_eq!(ranges[2], (9, 10));

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "aXc\ndXf\ngXi\n");
    }

    #[test]
    fn ui_add_all_occurrences_selects_all_matches() {
        let mut ui = EditorUi::new("foo foo foo\n", 80);

        // Put caret at start.
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
        ui.select_word().unwrap();
        ui.add_all_occurrences(SearchOptions::default()).unwrap();

        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 3);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "X X X\n");
    }

    #[test]
    fn ui_add_cursor_above_and_clear_secondary() {
        let mut ui = EditorUi::new("aa\naa\naa\n", 80);
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 1,
        }))
        .unwrap();

        ui.add_cursor_above().unwrap();
        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 2);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "aXa\naXa\naa\n");

        ui.clear_secondary_selections().unwrap();
        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 1);
    }

    #[test]
    fn ui_move_and_modify_selection_extends_from_anchor() {
        let mut ui = EditorUi::new("abc\n", 80);
        ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // caret at offset 2

        ui.move_grapheme_left_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 2));

        ui.move_grapheme_left_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 2));

        ui.move_grapheme_right_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 2));
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }

    #[test]
    fn ui_sublime_highlight_and_folding_roundtrip() {
        let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
        let text = r#"title = "TOML Example" # comment
numbers = [
  1,
  2,
  3,
]
multiline = """
hello
world
"""
"#;

        let mut ui = EditorUi::new(text, 80);
        ui.set_sublime_syntax_yaml(yaml).unwrap();

        let comment_style = ui
            .sublime_style_id_for_scope("comment.line.number-sign.toml")
            .unwrap();
        assert_eq!(
            ui.sublime_scope_for_style_id(comment_style).as_deref(),
            Some("comment.line.number-sign.toml")
        );

        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 8)
                .unwrap()
        };
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected at least one comment-styled cell"
        );

        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| r.start_line == 1 && r.end_line == 5),
            "expected fold region for multi-line array (lines 1..=5)"
        );
        assert!(
            regions.iter().any(|r| r.start_line == 6 && r.end_line == 9),
            "expected fold region for multi-line basic string (lines 6..=9)"
        );
    }

    #[test]
    fn ui_sublime_refreshes_after_edit() {
        let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
        let mut ui = EditorUi::new("title = 1\n", 80);
        ui.set_sublime_syntax_yaml(yaml).unwrap();

        // Insert a comment; `insert_text` should auto-refresh processors.
        ui.insert_text("# comment\n").unwrap();

        let comment_style = ui
            .sublime_style_id_for_scope("comment.line.number-sign.toml")
            .unwrap();
        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 2)
                .unwrap()
        };
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected comment style after edit"
        );
    }

    #[test]
    fn ui_treesitter_highlight_and_folding_roundtrip() {
        let text = r#"// hi
fn main() {
  let s = "x";
}
"#;

        let mut ui = EditorUi::new(text, 80);
        set_test_treesitter_registry(&mut ui);
        ui.set_treesitter_language("rust").unwrap();
        wait_for_async_processing(&mut ui);

        let comment_style = ui.treesitter_style_id_for_capture("comment");
        let string_style = ui.treesitter_style_id_for_capture("string");
        assert_eq!(
            ui.treesitter_capture_for_style_id(comment_style).as_deref(),
            Some("comment")
        );
        assert_eq!(
            ui.treesitter_capture_for_style_id(string_style).as_deref(),
            Some("string")
        );

        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 4)
                .unwrap()
        };
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected at least one comment-styled cell"
        );
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&string_style)),
            "expected at least one string-styled cell"
        );

        let regions = {
            let doc = ui.lock_doc();
            doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
        };
        assert!(
            regions.iter().any(|r| r.start_line == 1 && r.end_line == 3),
            "expected fold region for multi-line function"
        );
    }

    #[test]
    fn ui_treesitter_uses_incremental_updates_when_deltas_available() {
        let mut ui = EditorUi::new("// a\n", 80);
        set_test_treesitter_registry(&mut ui);
        ui.set_treesitter_language("rust").unwrap();
        wait_for_async_processing(&mut ui);
        assert_eq!(
            ui.treesitter_last_update_mode(),
            Some(TreeSitterUpdateMode::Initial)
        );

        ui.insert_text("// b\n").unwrap();
        wait_for_async_processing(&mut ui);
        assert_eq!(
            ui.treesitter_last_update_mode(),
            Some(TreeSitterUpdateMode::Incremental)
        );
    }

    #[test]
    fn ui_treesitter_runtime_config_can_be_updated_while_running() {
        let mut ui = EditorUi::new("// a\n", 80);

        // Use a zero-debounce config to keep the test fast and deterministic.
        ui.set_treesitter_processing_config(TreeSitterProcessingConfig {
            debounce_ms: 0,
            ..TreeSitterProcessingConfig::default()
        })
        .unwrap();

        set_test_treesitter_registry(&mut ui);
        ui.set_treesitter_language("rust").unwrap();
        wait_for_async_processing(&mut ui);

        // Updating the config should send a message to the worker and not break processing.
        ui.set_treesitter_processing_config(TreeSitterProcessingConfig {
            debounce_ms: 0,
            query_budget_ms: 1,
            cooldown_ms: 1,
            large_doc_char_threshold: 1,
            prefer_visible_range_on_large_docs: true,
        })
        .unwrap();

        ui.insert_text("// b\n").unwrap();
        wait_for_async_processing(&mut ui);
        assert!(
            ui.treesitter_last_update_mode().is_some(),
            "expected Tree-sitter processing to remain functional after runtime config update"
        );
    }

    #[test]
    fn ui_lsp_diagnostics_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: {
                let mut m = std::collections::BTreeMap::new();
                // LSP diagnostics style id encoding: 0x0400_0100 | severity
                m.insert(
                    0x0400_0100 | 1,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        let params_json = r#"{
          "uri": "file:///test",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }"#;
        ui.lsp_apply_publish_diagnostics_json(params_json).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        // Highlighted cell at col=1 => x in [10..20]
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_lsp_semantic_tokens_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        let style_id = 7u32 << 16;
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    style_id,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        // Highlight the 'b' as a semantic token:
        // (deltaLine=0, deltaStart=1, length=1, tokenType=7, tokenModifiers=0)
        ui.lsp_apply_semantic_tokens(&[0, 1, 1, 7, 0]).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_lsp_document_links_apply_decorations_and_underline_style_layer() {
        // Use a space inside the link range so glyph rasterization does not affect pixel samples.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 20,
            cell_width_px: 10.0,
            line_height_px: 10.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    editor_core::DOCUMENT_LINK_STYLE_ID,
                    editor_core_render_skia::StyleColors::new(
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                        None,
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 20, 1.0).unwrap();

        let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "target": "https://example.com"
          }
        ]"#;
        ui.lsp_apply_document_links_json(result_json).unwrap();

        let decorations = {
            let doc = ui.lock_doc();
            doc.ws
                .buffer_decorations(ui.buffer_id)
                .unwrap()
                .get(&editor_core::DecorationLayerId::DOCUMENT_LINKS)
                .cloned()
                .unwrap_or_default()
        };
        assert_eq!(
            decorations.len(),
            1,
            "expected one document link decoration"
        );

        let grid = {
            let mut doc = ui.lock_doc();
            doc.ws
                .get_viewport_content_styled(ui.view_id, 0, 1)
                .unwrap()
        };
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&editor_core::DOCUMENT_LINK_STYLE_ID)),
            "expected at least one cell to carry DOCUMENT_LINK_STYLE_ID"
        );

        let rgba = ui.render_rgba_visible().unwrap();
        // Underline is drawn at y = line_height_px - 1 (scale=1), i.e. y=9.
        assert_eq!(pixel(&rgba, 200, 15, 9), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_document_link_hit_test_returns_payload_json() {
        let mut ui = EditorUi::new("abc\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 1 }
            },
            "target": "https://example.com"
          }
        ]"#;
        ui.lsp_apply_document_links_json(result_json).unwrap();

        let (x, y) = ui.char_offset_to_view_point_px(0).unwrap();
        let json = ui
            .document_link_json_at_view_point_px(x + 1.0, y + 1.0)
            .expect("expected document link json at point");
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            v.get("target").and_then(|t| t.as_str()),
            Some("https://example.com")
        );
    }

    #[test]
    fn ui_lsp_document_highlights_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    editor_core::DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "kind": 1
          }
        ]"#;
        ui.lsp_apply_document_highlights_json(result_json).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        // Highlighted cell at col=1 => x in [10..20]
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_match_highlights_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect pixel samples.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    editor_core::MATCH_HIGHLIGHT_STYLE_ID,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        // Highlight the space at offset 1..2.
        ui.set_match_highlights_offsets(&[(1, 2)]);

        let rgba = ui.render_rgba_visible().unwrap();
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_search_set_query_finds_matches_and_sets_match_highlights() {
        // Use spaces as matches so glyph rasterization does not affect pixel samples.
        let mut ui = EditorUi::new("a c a\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    editor_core::MATCH_HIGHLIGHT_STYLE_ID,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
            style_fonts: std::collections::BTreeMap::new(),
            text_decorations: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        let count = ui
            .search_set_query(" ", editor_core::SearchOptions::default())
            .unwrap();
        assert_eq!(count, 2);

        let rgba = ui.render_rgba_visible().unwrap();
        // First space at col=1 => x in [10..20]
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
        // Second space at col=3 => x in [30..40]
        assert_eq!(pixel(&rgba, 200, 35, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_find_next_and_replace_current_and_all() {
        let mut ui = EditorUi::new("foo foo foo\n", 80);
        ui.set_selections_offsets(&[(0, 0)], 0).unwrap();

        let found = ui
            .find_next("foo", editor_core::SearchOptions::default())
            .unwrap();
        assert!(found);
        assert_eq!(
            ui.primary_selection_offsets(),
            (0, 3),
            "first find_next should select first 'foo'"
        );

        let found = ui
            .find_next("foo", editor_core::SearchOptions::default())
            .unwrap();
        assert!(found);
        assert_eq!(
            ui.primary_selection_offsets(),
            (4, 7),
            "second find_next should select second 'foo'"
        );

        let replaced = ui
            .replace_current("foo", "bar", editor_core::SearchOptions::default())
            .unwrap();
        assert_eq!(replaced, 1);
        assert_eq!(ui.text(), "foo bar foo\n");

        let replaced_all = ui
            .replace_all("foo", "baz", editor_core::SearchOptions::default())
            .unwrap();
        assert_eq!(replaced_all, 2);
        assert_eq!(ui.text(), "baz bar baz\n");
    }

    #[test]
    fn ui_reveal_primary_caret_scrolls_to_make_caret_visible() {
        // 100 lines, no wrapping: visual rows == logical lines.
        let text = (0..100).map(|_| "x").collect::<Vec<_>>().join("\n");
        let mut ui = EditorUi::new(text.as_str(), 80);
        ui.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
        // 5 visible rows.
        ui.set_viewport_px(800, 50, 1.0).unwrap();
        ui.set_smooth_scroll_state(0, 0);
        assert_eq!(ui.viewport_state().scroll_top, 0);

        // Place caret at line 50 (0-based).
        let offset = {
            let doc = ui.lock_doc();
            let line_index = doc.ws.buffer_line_index(ui.buffer_id).unwrap();
            line_index.position_to_char_offset(50, 0)
        };
        ui.set_selections_offsets(&[(offset, offset)], 0).unwrap();

        ui.reveal_primary_caret();
        // Expected: caret row 50 must be visible within 5 rows -> top should be 46.
        assert_eq!(ui.viewport_state().scroll_top, 46);
    }

    #[test]
    fn ui_lsp_request_definition_errors_when_lsp_disabled() {
        let mut ui = EditorUi::new("hello", 80);
        let err = ui.lsp_request_definition(0, 0).unwrap_err();
        match err {
            UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
            other => panic!("expected UiError::Processor, got: {other:?}"),
        }

        let err = ui
            .lsp_request_completion_item_resolve(r#"{"label":"hello"}"#)
            .unwrap_err();
        match err {
            UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
            other => panic!("expected UiError::Processor, got: {other:?}"),
        }

        let err = ui.lsp_format_document("", 50).unwrap_err();
        match err {
            UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
            other => panic!("expected UiError::Processor, got: {other:?}"),
        }

        let err = ui.lsp_format_range(0, 1, "", 50).unwrap_err();
        match err {
            UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
            other => panic!("expected UiError::Processor, got: {other:?}"),
        }

        let err = ui.lsp_format_on_type(0, 1, "\n", "", 50).unwrap_err();
        match err {
            UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
            other => panic!("expected UiError::Processor, got: {other:?}"),
        }
    }

    #[test]
    fn ui_lsp_apply_text_edits_json_converts_utf16_ranges_with_emoji() {
        let mut ui = EditorUi::new("a😀b\nc\n", 80);

        // Replace the 😀 (UTF-16 length 2) with "Z".
        let edits = r#"[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}},"newText":"Z"}]"#;
        let applied = ui.lsp_apply_text_edits_json(edits).unwrap();
        assert!(applied);
        assert_eq!(ui.text(), "aZb\nc\n");
    }

    #[test]
    fn ui_lsp_apply_text_edits_json_applies_multiple_edits_in_one_call() {
        let mut ui = EditorUi::new("abc\n", 80);

        // Two non-overlapping edits expressed in pre-edit coordinates:
        // - replace "b" with "B"
        // - insert "X" at the start
        let edits = r#"[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":2}},"newText":"B"},{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"X"}]"#;
        let applied = ui.lsp_apply_text_edits_json(edits).unwrap();
        assert!(applied);
        assert_eq!(ui.text(), "XaBc\n");
    }

    #[test]
    fn ui_lsp_apply_workspace_edit_json_applies_current_uri_and_reports_skips() {
        let mut ui = EditorUi::new("abc\n", 80);

        let edit = r#"{
            "changes": {
                "file:///test.rs": [
                    { "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } }, "newText": "B" }
                ],
                "file:///other.rs": [
                    { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "X" }
                ]
            }
        }"#;

        let result_json = ui
            .lsp_apply_workspace_edit_json(edit, Some("file:///test.rs"))
            .unwrap();
        assert_eq!(ui.text(), "aBc\n");

        let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
        assert_eq!(result["applied"], true);
        assert_eq!(result["applied_uri"], "file:///test.rs");
        assert_eq!(result["applied_edit_count"], 1);
        assert_eq!(
            result["skipped_uris"],
            serde_json::json!(["file:///other.rs"])
        );
        assert_eq!(result["documents"].as_array().unwrap().len(), 2);
    }
}
