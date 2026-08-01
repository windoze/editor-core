//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

mod command_json;
mod editor_ui;
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

fn value_offset_range(start: usize, end: usize) -> serde_json::Value {
    serde_json::json!({ "start": start, "end": end })
}

fn lsp_signature_help_capability_json(capabilities: &serde_json::Value) -> serde_json::Value {
    let provider = capabilities.get("signatureHelpProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let retrigger_characters =
        lsp_string_array(provider.and_then(|p| p.get("retriggerCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "retrigger_characters": retrigger_characters,
    })
}

fn lsp_completion_capability_json(capabilities: &serde_json::Value) -> serde_json::Value {
    let provider = capabilities.get("completionProvider");
    let trigger_characters = lsp_string_array(provider.and_then(|p| p.get("triggerCharacters")));
    let all_commit_characters =
        lsp_string_array(provider.and_then(|p| p.get("allCommitCharacters")));

    serde_json::json!({
        "supported": provider.is_some(),
        "trigger_characters": trigger_characters,
        "all_commit_characters": all_commit_characters,
    })
}

fn lsp_string_array(value: Option<&serde_json::Value>) -> Vec<String> {
    value
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(ToString::to_string))
                .collect()
        })
        .unwrap_or_default()
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
    CodeLens,
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
            "textDocument/codeLens" => Some(Self::CodeLens),
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

fn stored_lsp_error_result_json(slot: LspResultSlot, error: LspResponseError) -> Option<String> {
    if slot != LspResultSlot::ExecuteCommand && slot != LspResultSlot::CodeLens {
        return None;
    }

    Some(
        serde_json::json!({
            "error": {
                "code": error.code,
                "message": error.message,
                "data": error.data,
            }
        })
        .to_string(),
    )
}

fn stored_lsp_success_result_json(
    slot: LspResultSlot,
    result: serde_json::Value,
) -> Option<String> {
    if slot == LspResultSlot::ExecuteCommand {
        return Some(serde_json::json!({ "result": result }).to_string());
    }
    if slot == LspResultSlot::CodeLens {
        return Some(result.to_string());
    }

    if result.is_null() {
        None
    } else {
        Some(result.to_string())
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
mod tests;
