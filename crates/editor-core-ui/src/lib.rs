//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

use editor_core::{
    Command, CommandResult, CursorCommand, DecorationKind, DecorationLayerId, EditCommand,
    EditorStateManager,
    ExpandSelectionDirection, ExpandSelectionUnit, Position, IME_MARKED_TEXT_STYLE_ID,
    MATCH_HIGHLIGHT_STYLE_ID, ProcessingEdit, SearchOptions, Selection, SelectionDirection,
    SmoothScrollState, StyleCommand, StyleLayerId, ViewCommand,
};
use editor_core::intervals::Interval;
use editor_core_lsp::{
    LspNotification, encode_semantic_style_id, lsp_code_lens_to_processing_edit,
    lsp_diagnostics_to_processing_edits, lsp_document_links_to_processing_edits,
    lsp_document_highlights_to_processing_edit, lsp_inlay_hints_to_processing_edit,
    semantic_tokens_to_intervals,
};
use editor_core_render_skia::{
    FoldMarker, RenderConfig, RenderError, RenderTheme, SkiaRenderer, StyleColors, VisualCaret,
    VisualSelection,
};
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig, TreeSitterUpdateMode};
use std::collections::{BTreeMap, HashMap};
use std::ffi::c_void;
use std::sync::mpsc;
use std::thread;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
    #[error("processor error: {0}")]
    Processor(String),
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
    #[cfg(target_os = "macos")]
    unsafe {
        // Best effort: lower priority than UI thread to avoid input jank / CPU spikes.
        let _ = libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_UTILITY, 0);
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
                        rx_worker.recv().map_err(|_| mpsc::RecvTimeoutError::Disconnected)
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
                                Ok(mut p) => {
                                    match p.sync_to(version, None, Some(&text)) {
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
                                    }
                                }
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
                                    let _ = tx_events
                                        .send(TreeSitterWorkerEvent::Error(e.to_string()));
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
                                    let _ = tx_events
                                        .send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            // We reached the debounce/cooldown boundary; run queries if needed.
                            if dirty_for_query == false {
                                continue;
                            }
                            if awaiting_full_sync {
                                continue;
                            }
                            if let Some(cooldown) = cooldown_until {
                                if std::time::Instant::now() < cooldown {
                                    continue;
                                }
                            }

                            let Some(p) = processor.as_mut() else {
                                continue;
                            };

                            let large_doc = runtime.prefer_visible_range_on_large_docs
                                && latest_doc_char_count
                                    >= runtime.large_doc_char_threshold as usize;
                            let use_range =
                                if degraded || large_doc { latest_prefetch_char_range } else { None };

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
                                        degraded_fast_streak = degraded_fast_streak.saturating_add(1);
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
                                    let _ = tx_events
                                        .send(TreeSitterWorkerEvent::Error(e.to_string()));
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

/// A minimal "single buffer, single view" UI wrapper.
///
/// Later we can add a `Workspace`-backed version for tabs/splits.
pub struct EditorUi {
    state: EditorStateManager,
    renderer: SkiaRenderer,
    theme: RenderTheme,
    render_config: RenderConfig,
    sublime: Option<SublimeProcessor>,
    treesitter: Option<TreeSitterAsyncWorker>,
    treesitter_capture_mapper: TreeSitterCaptureMapper,
    treesitter_processing_config: TreeSitterProcessingConfig,
    marked: Option<MarkedRange>,
    search_query: Option<SearchQueryState>,
    mouse_anchor: Option<Position>,
}

impl EditorUi {
    pub fn new(initial_text: &str, viewport_width_cells: usize) -> Self {
        Self {
            state: EditorStateManager::new(initial_text, viewport_width_cells),
            renderer: SkiaRenderer::new(),
            theme: RenderTheme::default(),
            render_config: RenderConfig::default(),
            sublime: None,
            treesitter: None,
            treesitter_capture_mapper: TreeSitterCaptureMapper::default(),
            treesitter_processing_config: TreeSitterProcessingConfig::default(),
            marked: None,
            search_query: None,
            mouse_anchor: None,
        }
    }

    pub fn text(&self) -> String {
        self.state.editor().get_text()
    }

    pub fn cursor_state(&self) -> editor_core::CursorState {
        self.state.get_cursor_state()
    }

    pub fn set_treesitter_processing_config(
        &mut self,
        runtime: TreeSitterProcessingConfig,
    ) -> Result<(), UiError> {
        self.treesitter_processing_config = runtime;
        if let Some(worker) = self.treesitter.as_mut() {
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
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;
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
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;

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
            parts.push(self.state.editor().piece_table.get_range(start, len));
        }

        if parts.len() == 1 {
            parts.remove(0)
        } else {
            parts.join("\n")
        }
    }

    /// Return all selections (including primary) as character-offset ranges, plus the primary index.
    ///
    /// Each range is inclusive-exclusive in Unicode scalar indices.
    pub fn selections_offsets(&self) -> (Vec<(usize, usize)>, usize) {
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;

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
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;

        let mut edits: Vec<editor_core::TextEditSpec> = Vec::new();
        for sel in &cursor.selections {
            if sel.start == sel.end {
                continue;
            }

            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            let (start, end) = if a <= b { (a, b) } else { (b, a) };
            if start == end {
                continue;
            }
            edits.push(editor_core::TextEditSpec {
                start,
                end,
                text: String::new(),
            });
        }

        if edits.is_empty() {
            return Ok(());
        }

        self.state
            .execute(Command::Edit(EditCommand::ApplyTextEdits { edits }))?;
        self.refresh_processing()?;
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

        let line_index = &self.state.editor().line_index;
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

        self.state.execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    pub fn clear_secondary_selections(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSecondarySelections))?;
        Ok(())
    }

    pub fn add_cursor_above(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::AddCursorAbove))?;
        Ok(())
    }

    pub fn add_cursor_below(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::AddCursorBelow))?;
        Ok(())
    }

    pub fn add_next_occurrence(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::AddNextOccurrence {
            options,
        }))?;
        Ok(())
    }

    pub fn add_all_occurrences(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::AddAllOccurrences {
            options,
        }))?;
        Ok(())
    }

    pub fn select_word(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::SelectWord))?;
        Ok(())
    }

    pub fn select_line(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::SelectLine))?;
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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);

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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (line, _col) = line_index.char_offset_to_position(char_offset);
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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);

        let (a_start, a_end) = self.paragraph_line_range_for_line(a_line);
        let (b_start, b_end) = self.paragraph_line_range_for_line(b_line);

        let start_line = a_start.min(b_start);
        let end_line = a_end.max(b_end);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    pub fn expand_selection(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ExpandSelection))?;
        Ok(())
    }

    pub fn expand_selection_by(
        &mut self,
        unit: ExpandSelectionUnit,
        count: usize,
        direction: ExpandSelectionDirection,
    ) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
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
        let line_index = &self.state.editor().line_index;
        let (a_line, a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, b_col) = line_index.char_offset_to_position(active_offset);
        self.state.execute(Command::Cursor(CursorCommand::SetRectSelection {
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
        let line_index = &self.state.editor().line_index;
        let (line, column) = line_index.char_offset_to_position(char_offset);
        let pos = Position::new(line, column);

        let cursor = self.state.get_cursor_state();
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

        self.state.execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    fn is_blank_line(&self, line: usize) -> bool {
        self.state
            .editor()
            .line_index
            .get_line_text(line)
            .unwrap_or_default()
            .trim()
            .is_empty()
    }

    fn paragraph_line_range_for_line(&self, line: usize) -> (usize, usize) {
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return (0, 0);
        }

        let mut start = line.min(line_count.saturating_sub(1));
        let mut end = start;

        let want_blank = self.is_blank_line(start);

        while start > 0 && self.is_blank_line(start - 1) == want_blank {
            start -= 1;
        }
        while end + 1 < line_count && self.is_blank_line(end + 1) == want_blank {
            end += 1;
        }

        (start, end)
    }

    fn paragraph_offsets_for_line_range(&self, start_line: usize, end_line: usize) -> (usize, usize) {
        let line_index = &self.state.editor().line_index;
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
    }

    /// Return the current IME marked text range as `(start, len)` in character offsets.
    pub fn marked_range(&self) -> Option<(usize, usize)> {
        self.marked.as_ref().map(|m| (m.start, m.len))
    }

    /// Map a character offset (Unicode scalar index) to visual `(row, x_cells)`.
    pub fn char_offset_to_visual(&self, char_offset: usize) -> Option<(usize, usize)> {
        let (line, column) = self
            .state
            .editor()
            .line_index
            .char_offset_to_position(char_offset);
        self.state.logical_position_to_visual(line, column)
    }

    /// Map a visual `(row, x_cells)` position to a character offset.
    pub fn visual_to_char_offset(&self, row: usize, x_cells: usize) -> Option<usize> {
        let pos = self.state.visual_position_to_logical(row, x_cells)?;
        Some(
            self.state
                .editor()
                .line_index
                .position_to_char_offset(pos.line, pos.column),
        )
    }

    /// Map a character offset to a point in the view coordinate space (pixels).
    ///
    /// - `x_px` is left-to-right (in pixels)
    /// - `y_px` is top-to-bottom (in pixels), aligned to the top of the visual row
    pub fn char_offset_to_view_point_px(&self, char_offset: usize) -> Option<(f32, f32)> {
        let viewport = self.state.get_viewport_state();
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
    pub fn view_point_to_char_offset(&self, x_px: f32, y_px: f32) -> Option<usize> {
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
        let layer = self
            .state
            .editor()
            .decorations
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
    pub fn document_link_json_at_view_point_px(&self, x_px: f32, y_px: f32) -> Option<String> {
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

    /// Replace match highlight ranges (e.g. search matches) as a dedicated overlay style layer.
    ///
    /// Notes:
    /// - Ranges are character offsets (Unicode scalar indices), half-open `[start, end)`.
    /// - Passing an empty slice clears the layer.
    pub fn set_match_highlights_offsets(&mut self, ranges: &[(usize, usize)]) {
        if ranges.is_empty() {
            self.state.clear_style_layer(StyleLayerId::MATCH_HIGHLIGHTS);
            return;
        }

        let doc_len = self.state.editor().piece_table.char_count();
        let mut intervals: Vec<Interval> = Vec::with_capacity(ranges.len());
        for (start, end) in ranges {
            let s = (*start).min(doc_len);
            let e = (*end).min(doc_len);
            let (s, e) = if s <= e { (s, e) } else { (e, s) };
            if s < e {
                intervals.push(Interval::new(s, e, MATCH_HIGHLIGHT_STYLE_ID));
            }
        }
        self.state
            .replace_style_layer(StyleLayerId::MATCH_HIGHLIGHTS, intervals);
    }

    /// Set an active search query and update match highlights accordingly.
    ///
    /// Returns the number of matches found.
    ///
    /// Notes:
    /// - This is intentionally a "UI-level convenience" API. It does not affect the core cursor
    ///   find/replace commands; it only updates the `MATCH_HIGHLIGHTS` style layer for rendering.
    /// - Passing an empty query clears match highlights.
    pub fn search_set_query(&mut self, query: &str, options: SearchOptions) -> Result<usize, UiError> {
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

        let text = self.state.editor().piece_table.get_text();
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
        let result = self.state.execute(Command::Cursor(CursorCommand::FindNext {
            query: query.to_string(),
            options,
        }))?;
        Ok(matches!(result, CommandResult::SearchMatch { .. }))
    }

    /// Find previous match and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    pub fn find_prev(&mut self, query: &str, options: SearchOptions) -> Result<bool, UiError> {
        let result = self.state.execute(Command::Cursor(CursorCommand::FindPrev {
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
        let result = self.state.execute(Command::Edit(EditCommand::ReplaceCurrent {
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
        let result = self.state.execute(Command::Edit(EditCommand::ReplaceAll {
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
        self.sublime = Some(SublimeProcessor::new(syntax, set));
        self.refresh_processing()
    }

    pub fn set_sublime_syntax_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_path(path)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        self.sublime = Some(SublimeProcessor::new(syntax, set));
        self.refresh_processing()
    }

    pub fn disable_sublime_syntax(&mut self) {
        self.sublime = None;
    }

    pub fn sublime_scope_for_style_id(&self, style_id: u32) -> Option<&str> {
        self.sublime
            .as_ref()
            .and_then(|p| p.scope_mapper.scope_for_style_id(style_id))
    }

    pub fn sublime_style_id_for_scope(&mut self, scope: &str) -> Result<u32, UiError> {
        let Some(proc) = self.sublime.as_mut() else {
            return Err(UiError::Processor(
                "sublime syntax processor is not enabled".to_string(),
            ));
        };
        Ok(proc.scope_mapper.style_id_for_scope(scope))
    }

    pub fn set_treesitter_rust_default(&mut self) -> Result<(), UiError> {
        self.set_treesitter_rust_with_queries(
            tree_sitter_rust::HIGHLIGHTS_QUERY,
            Some(
                r#"
                (function_item) @fold
                (impl_item) @fold
                (struct_item) @fold
                (enum_item) @fold
                (mod_item) @fold
                (block) @fold
                "#,
            ),
        )
    }

    pub fn set_treesitter_rust_with_queries(
        &mut self,
        highlights_query: &str,
        folds_query: Option<&str>,
    ) -> Result<(), UiError> {
        let language: tree_sitter::Language = tree_sitter_rust::LANGUAGE.into();

        let query = tree_sitter::Query::new(&language, highlights_query)
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let mut capture_styles = BTreeMap::<String, u32>::new();
        for name in query.capture_names() {
            let style_id = self.treesitter_capture_mapper.style_id_for_capture(name);
            capture_styles.insert(name.to_string(), style_id);
        }

        let mut config = TreeSitterProcessorConfig::new(language, highlights_query.to_string());
        if let Some(folds_query) = folds_query {
            config = config.with_folds_query(folds_query.to_string());
        }
        config.capture_styles = capture_styles;

        self.treesitter = None;
        self.state.apply_processing_edits([
            ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::TREE_SITTER,
            },
            ProcessingEdit::ClearFoldingRegions,
        ]);

        let mut worker = TreeSitterAsyncWorker::spawn();
        let text = self.state.editor().get_text();
        let version = self.state.version();
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let runtime = self.treesitter_processing_config;
        worker.requested_version = Some(version);
        worker.tx
            .send(TreeSitterWorkerMsg::Init {
                config,
                runtime,
                version,
                text,
                prefetch_char_range,
            })
            .map_err(|_| UiError::Processor("failed to start tree-sitter worker".to_string()))?;
        self.treesitter = Some(worker);
        Ok(())
    }

    pub fn disable_treesitter(&mut self) {
        self.treesitter = None;
    }

    pub fn poll_processing(&mut self) -> Result<ProcessingPollResult, UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let Some(worker) = self.treesitter.as_mut() else {
            return Ok(ProcessingPollResult {
                applied: false,
                pending: false,
            });
        };

        let mut latest: Option<(u64, Vec<ProcessingEdit>, TreeSitterUpdateMode)> = None;
        let mut need_full_sync = false;

        loop {
            match worker.rx.try_recv() {
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
            let text = self.state.editor().get_text();
            let version = self.state.version();
            worker.requested_version = Some(version);
            worker
                .tx
                .send(TreeSitterWorkerMsg::FullSync {
                    version,
                    text,
                    prefetch_char_range,
                })
                .map_err(|_| UiError::Processor("failed to full-sync tree-sitter worker".to_string()))?;
        }

        let mut applied = false;
        if let Some((version, edits, update_mode)) = latest {
            if worker
                .requested_version
                .is_some_and(|requested| version < requested)
            {
                // Stale result: the UI already requested a newer document version.
            } else {
                self.state.apply_processing_edits(edits);
                worker.applied_version = Some(version);
                worker.last_update_mode = Some(update_mode);
                applied = true;
            }
        }

        Ok(ProcessingPollResult {
            applied,
            pending: worker.is_pending(),
        })
    }

    pub fn treesitter_last_update_mode(&self) -> Option<TreeSitterUpdateMode> {
        self.treesitter.as_ref().and_then(|w| w.last_update_mode)
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<&str> {
        self.treesitter_capture_mapper
            .capture_for_style_id(style_id)
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        self.treesitter_capture_mapper
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

        let line_index = &self.state.editor().line_index;
        let edits = lsp_diagnostics_to_processing_edits(line_index, &params);
        self.state.apply_processing_edits(edits);
        Ok(())
    }

    pub fn lsp_apply_semantic_tokens(&mut self, data: &[u32]) -> Result<(), UiError> {
        let line_index = &self.state.editor().line_index;
        let intervals = semantic_tokens_to_intervals(data, line_index, encode_semantic_style_id)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        self.state
            .apply_processing_edits(vec![ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::SEMANTIC_TOKENS,
                intervals,
            }]);
        Ok(())
    }

    /// Apply LSP document highlight result payload (`DocumentHighlight[] | null`) as a style layer.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentHighlight`.
    pub fn lsp_apply_document_highlights_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let line_index = &self.state.editor().line_index;
        let edit = lsp_document_highlights_to_processing_edit(line_index, &result_value);
        self.state.apply_processing_edits([edit]);
        Ok(())
    }

    /// Apply LSP inlay hints result payload (`InlayHint[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/inlayHint`.
    pub fn lsp_apply_inlay_hints_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let line_index = &self.state.editor().line_index;
        let edit = lsp_inlay_hints_to_processing_edit(line_index, &result_value);
        self.state.apply_processing_edits([edit]);
        Ok(())
    }

    /// Apply LSP code lens result payload (`CodeLens[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/codeLens`.
    pub fn lsp_apply_code_lens_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let line_index = &self.state.editor().line_index;
        let edit = lsp_code_lens_to_processing_edit(line_index, &result_value);
        self.state.apply_processing_edits([edit]);
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
        let line_index = &self.state.editor().line_index;
        let edits = lsp_document_links_to_processing_edits(line_index, &result_value);
        self.state.apply_processing_edits(edits);
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

    /// Override the ASCII word-boundary character set used by editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    pub fn set_word_boundary_ascii_boundary_chars(&mut self, boundary_chars: &str) -> Result<(), UiError> {
        self.state
            .execute(Command::View(ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: boundary_chars.to_string(),
            }))?;
        Ok(())
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    pub fn reset_word_boundary_defaults(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::View(ViewCommand::ResetWordBoundaryDefaults))?;
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
        self.state
            .execute(Command::View(ViewCommand::SetViewportWidth {
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
        self.state.set_viewport_height(height_rows);
        Ok(())
    }

    pub fn viewport_state(&self) -> editor_core::ViewportState {
        self.state.get_viewport_state()
    }

    pub fn set_smooth_scroll_state(&mut self, top_visual_row: usize, sub_row_offset: u16) {
        let viewport = self.state.get_viewport_state();
        let height_rows = viewport.height.unwrap_or(viewport.total_visual_lines).max(1);
        let max_pos_rows = viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = self.state.get_smooth_scroll_state();
        let pos_rows = top_visual_row as f32 + (sub_row_offset as f32 / 65536.0);
        let new_pos = pos_rows.clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = SmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            self.state.set_smooth_scroll_state(next);
        }
    }

    fn max_scroll_top(&self, viewport: &editor_core::ViewportState) -> usize {
        let height_rows = viewport.height.unwrap_or(viewport.total_visual_lines).max(1);
        viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines)
    }

    fn ensure_primary_caret_visible_after_navigation(&mut self) {
        let viewport = self.state.get_viewport_state();
        let Some(height_rows) = viewport.height else {
            return;
        };
        if height_rows == 0 {
            return;
        }

        let cursor = self.state.get_cursor_state();
        let active = cursor
            .selections
            .get(cursor.primary_selection_index)
            .map(|s| s.end)
            .unwrap_or(cursor.position);

        let Some((caret_row, _caret_x)) =
            self.state.logical_position_to_visual(active.line, active.column)
        else {
            return;
        };

        let mut new_top = viewport.scroll_top;
        if caret_row < viewport.scroll_top {
            new_top = caret_row;
        } else if caret_row >= viewport.scroll_top.saturating_add(height_rows) {
            new_top = caret_row.saturating_sub(height_rows.saturating_sub(1));
        }
        new_top = new_top.min(self.max_scroll_top(&viewport));

        let smooth = self.state.get_smooth_scroll_state();
        let next = SmoothScrollState {
            top_visual_row: new_top,
            // Keyboard navigation should snap to full rows for a stable caret position.
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            self.state.set_smooth_scroll_state(next);
        }
    }

    pub fn scroll_by_rows(&mut self, delta_rows: isize) {
        let viewport = self.state.get_viewport_state();
        let height_rows = viewport.height.unwrap_or(viewport.total_visual_lines).max(1);
        let max_top = viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines) as isize;

        let old = viewport.scroll_top as isize;
        let new_top = (old + delta_rows).clamp(0, max_top.max(0)) as usize;

        let smooth = self.state.get_smooth_scroll_state();
        let next = SmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            self.state.set_smooth_scroll_state(next);
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
        let viewport = self.state.get_viewport_state();
        let height_rows = viewport.height.unwrap_or(viewport.total_visual_lines).max(1);
        let max_pos_rows =
            viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = self.state.get_smooth_scroll_state();
        let pos_rows =
            smooth.top_visual_row as f32 + (smooth.sub_row_offset as f32 / 65536.0);
        let delta_rows = delta_y_px / line_h;
        let new_pos = (pos_rows + delta_rows).clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = SmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            self.state.set_smooth_scroll_state(next);
        }
    }

    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn backspace(&mut self) -> Result<(), UiError> {
        // UI-friendly default: delete the previous grapheme cluster (UAX #29).
        //
        // This matches typical native text behavior (e.g. emoji / combining marks) and
        // keeps deletion consistent with the grapheme-aware cursor movement APIs we expose.
        self.state
            .execute(Command::Edit(EditCommand::DeleteGraphemeBack))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Edit(EditCommand::DeleteGraphemeForward))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn delete_word_back(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::DeleteWordBack))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn delete_word_forward(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Edit(EditCommand::DeleteWordForward))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn add_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.state.execute(Command::Style(StyleCommand::AddStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn remove_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.state
            .execute(Command::Style(StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Undo))?;
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Redo))?;
        Ok(())
    }

    pub fn end_undo_group(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Edit(EditCommand::EndUndoGroup))?;
        Ok(())
    }

    pub fn move_visual_by_rows(&mut self, delta_rows: isize) -> Result<(), UiError> {
        // UI-friendly behavior: if there is an active selection, moving vertically should
        // collapse it to the current caret before moving (matches common editor behavior).
        //
        // Without this, some hosts may appear "stuck" because the selection remains visible
        // while the caret movement is not obvious (and some cursor movement strategies can
        // also depend on a clear selection).
        if self.state.get_cursor_state().selection.is_some() {
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.state
            .execute(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_grapheme_left(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;
        Ok(())
    }

    pub fn move_grapheme_right(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))?;
        Ok(())
    }

    pub fn move_word_left(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveWordLeft))?;
        Ok(())
    }

    pub fn move_word_right(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveWordRight))?;
        Ok(())
    }

    pub fn move_to_visual_line_start(&mut self) -> Result<(), UiError> {
        if self.state.get_cursor_state().selection.is_some() {
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.state
            .execute(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end(&mut self) -> Result<(), UiError> {
        if self.state.get_cursor_state().selection.is_some() {
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.state
            .execute(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start(&mut self) -> Result<(), UiError> {
        if self.state.get_cursor_state().selection.is_some() {
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end(&mut self) -> Result<(), UiError> {
        if self.state.get_cursor_state().selection.is_some() {
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }

        let line_count = self.state.editor().line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }
        let last_line = line_count.saturating_sub(1);
        let text = self
            .state
            .editor()
            .line_index
            .get_line_text(last_line)
            .unwrap_or_default();
        let col = text.chars().count();

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_visual_by_pages(&mut self, delta_pages: isize) -> Result<(), UiError> {
        let height_rows = self.state.get_viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_grapheme_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        // Move the internal caret to the active end, clear selection so movement applies, then restore.
        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveWordLeft))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_grapheme_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveWordRight))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_to_visual_line_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;

        let line_count = self.state.editor().line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }
        let last_line = line_count.saturating_sub(1);
        let text = self
            .state
            .editor()
            .line_index
            .get_line_text(last_line)
            .unwrap_or_default();
        let col = text.chars().count();

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
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
        let height_rows = self.state.get_viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows_and_modify_selection(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_visual_by_rows_and_modify_selection(
        &mut self,
        delta_rows: isize,
    ) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
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
        let (start, replace_len, original_text, original_len) =
            if let Some((start, len)) = replace_range {
                let original = self.state.editor().piece_table.get_range(start, len);
                (start, len, original, len)
            } else if let Some(marked) = self.marked.as_ref() {
                (
                    marked.start,
                    marked.len,
                    marked.original_text.clone(),
                    marked.original_len,
                )
            } else {
                let cursor = self.state.get_cursor_state();
                let line_index = &self.state.editor().line_index;
                if let Some(sel) = cursor.selection {
                    let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
                    let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
                    let (start, end) = if a <= b { (a, b) } else { (b, a) };
                    let len = end.saturating_sub(start);
                    let original = self.state.editor().piece_table.get_range(start, len);
                    (start, len, original, len)
                } else {
                    (cursor.offset, 0, String::new(), 0)
                }
            };

        // Empty marked text means "cancel/clear composition": restore original replaced text.
        if new_len == 0 {
            if replace_len > 0 || !original_text.is_empty() {
                self.state
                    .execute(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                    start,
                    length: replace_len,
                    text: original_text.clone(),
                }))?;
                self.refresh_processing()?;
            }

            self.marked = None;
            self.state
                .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::IME_MARKED_TEXT,
                }]);
            // Do not let IME composition edits coalesce into subsequent typing.
            self.state.execute(Command::Edit(EditCommand::EndUndoGroup))?;

            // Restore selection to the original range (best-effort).
            let a_off = start;
            let b_off = start.saturating_add(original_len);
            let line_index = &self.state.editor().line_index;
            let (a_line, a_col) = line_index.char_offset_to_position(a_off);
            let (b_line, b_col) = line_index.char_offset_to_position(b_off);

            if original_len > 0 {
                self.state.execute(Command::Cursor(CursorCommand::SetSelection {
                    start: Position::new(a_line, a_col),
                    end: Position::new(b_line, b_col),
                }))?;
            } else {
                self.state.execute(Command::Cursor(CursorCommand::MoveTo {
                    line: a_line,
                    column: a_col,
                }))?;
                self.state
                    .execute(Command::Cursor(CursorCommand::ClearSelection))?;
            }
            return Ok(());
        }

        // Start of composition: do not merge with the current typing group.
        if self.marked.is_none() {
            self.state.execute(Command::Edit(EditCommand::EndUndoGroup))?;
        }

        // Honor selection inside marked text (preedit caret / selection).
        //
        // Important: this must happen *within* the same edit command so it doesn't break
        // undo grouping (CommandExecutor ends the coalescing group on non-edit commands).
        let sel_start = selected_start.min(new_len);
        let sel_end = selected_start
            .saturating_add(selected_len)
            .min(new_len);
        let a_off = start.saturating_add(sel_start);
        let b_off = start.saturating_add(sel_end);

        self.state
            .execute(Command::Edit(EditCommand::ReplaceCoalescingUndoWithSelection {
            start,
            length: replace_len,
            text: text.to_string(),
            selection_start: a_off,
            selection_end: b_off,
        }))?;
        self.refresh_processing()?;

        self.marked = Some(MarkedRange {
            start,
            len: new_len,
            original_text,
            original_len,
        });

        // Apply a dedicated style layer so the renderer can draw preedit (underline/background).
        self.state
            .apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
                intervals: vec![Interval::new(
                    start,
                    start.saturating_add(new_len),
                    IME_MARKED_TEXT_STYLE_ID,
                )],
            }]);
        Ok(())
    }

    pub fn unmark_text(&mut self) {
        self.marked = None;
        self.state
            .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }]);
    }

    pub fn commit_text(&mut self, text: &str) -> Result<(), UiError> {
        if let Some(marked) = self.marked.take() {
            self.state
                .execute(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                start: marked.start,
                length: marked.len,
                text: text.to_string(),
            }))?;
            self.refresh_processing()?;

            let end = marked.start + text.chars().count();
            let (line, column) = self.state.editor().line_index.char_offset_to_position(end);
            self.state
                .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))?;

            self.state
                .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::IME_MARKED_TEXT,
                }]);
            // Commit ends the composition undo group.
            self.state.execute(Command::Edit(EditCommand::EndUndoGroup))?;
            Ok(())
        } else {
            self.insert_text(text)
        }
    }

    pub fn mouse_down(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        // Gutter interaction: click-to-toggle fold state for a fold start line.
        if self.render_config.gutter_width_cells > 0 {
            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let gutter_end_x = self.render_config.padding_x_px + gutter_px;
            if x_px < gutter_end_x {
                if self.has_virtual_text_decorations() {
                    let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
                    let (local_row, _x_cells) = self.pixel_to_local_row_col(x_px, y_px);
                    if let Some(line) = grid.lines.get(local_row) {
                        if let editor_core::ComposedLineKind::Document { logical_line, .. } =
                            line.kind
                        {
                            if let Some(region) = self
                                .state
                                .get_folding_state()
                                .regions
                                .iter()
                                .filter(|r| r.start_line == logical_line)
                                .min_by_key(|r| r.end_line)
                                .cloned()
                            {
                                if region.is_collapsed {
                                    self.state.execute(Command::Style(StyleCommand::Unfold {
                                        start_line: region.start_line,
                                    }))?;
                                } else {
                                    self.state.execute(Command::Style(StyleCommand::Fold {
                                        start_line: region.start_line,
                                        end_line: region.end_line,
                                    }))?;
                                }
                                self.mouse_anchor = None;
                                return Ok(());
                            }
                        }
                    }
                } else {
                    let (row, _x_cells) = self.pixel_to_visual(x_px, y_px);
                    if let Some(pos) = self.state.visual_position_to_logical(row, 0) {
                        if let Some(region) = self
                            .state
                            .get_folding_state()
                            .regions
                            .iter()
                            .filter(|r| r.start_line == pos.line)
                            .min_by_key(|r| r.end_line)
                            .cloned()
                        {
                            if region.is_collapsed {
                                self.state.execute(Command::Style(StyleCommand::Unfold {
                                    start_line: region.start_line,
                                }))?;
                            } else {
                                self.state.execute(Command::Style(StyleCommand::Fold {
                                    start_line: region.start_line,
                                    end_line: region.end_line,
                                }))?;
                            }
                            self.mouse_anchor = None;
                            return Ok(());
                        }
                    }
                }
            }
        }

        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };
        let (line, column) = self.state.editor().line_index.char_offset_to_position(off);
        let pos = Position::new(line, column);

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: pos.line,
            column: pos.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.mouse_anchor = Some(pos);
        Ok(())
    }

    pub fn mouse_dragged(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        let Some(anchor) = self.mouse_anchor else {
            return Ok(());
        };
        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };
        let (to_line, to_col) = self.state.editor().line_index.char_offset_to_position(off);
        let to = Position::new(to_line, to_col);
        self.state
            .execute(Command::Cursor(CursorCommand::SetSelection {
                start: anchor,
                end: to,
            }))?;
        // Keep the editor's internal `cursor_position` in sync with the active end of the selection.
        //
        // `CursorCommand::SetSelection` intentionally does not update `cursor_position`, but UI
        // frontends expect keyboard navigation to continue from the caret shown at the active end.
        self.state
            .execute(Command::Cursor(CursorCommand::MoveTo {
                line: to.line,
                column: to.column,
            }))?;
        Ok(())
    }

    pub fn mouse_up(&mut self) {
        self.mouse_anchor = None;
    }

    pub fn execute(&mut self, command: Command) -> Result<CommandResult, UiError> {
        Ok(self.state.execute(command)?)
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

        let viewport = self.state.get_viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;

        let mut fold_markers = Vec::<FoldMarker>::new();
        for region in &self.state.get_folding_state().regions {
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
            let grid = self
                .state
                .get_viewport_content_composed(start_composed, row_count);
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
            let grid = self.state.get_viewport_content_styled(start_row, row_count);
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

    /// Enable the Skia Metal backend (macOS only).
    ///
    /// This is a rendering backend switch only; it does not affect editor state.
    pub fn enable_metal(&mut self, metal_device: *mut c_void, metal_command_queue: *mut c_void) -> Result<(), UiError> {
        self.renderer.enable_metal(metal_device, metal_command_queue)?;
        Ok(())
    }

    /// Disable the Metal backend and revert to CPU raster output.
    pub fn disable_metal(&mut self) {
        self.renderer.disable_metal();
    }

    /// Render the current visible viewport into a Metal texture (macOS only).
    ///
    /// The host is responsible for presenting the texture (e.g. `CAMetalDrawable`).
    pub fn render_metal_visible_into_texture(&mut self, metal_texture: *mut c_void) -> Result<(), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.state.get_viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;

        let mut fold_markers = Vec::<FoldMarker>::new();
        for region in &self.state.get_folding_state().regions {
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
            let grid = self
                .state
                .get_viewport_content_composed(start_composed, row_count);
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
            let grid = self.state.get_viewport_content_styled(start_row, row_count);
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
        self.state
            .editor()
            .decorations
            .values()
            .any(|layer| layer.iter().any(|d| d.text.as_ref().is_some_and(|t| !t.is_empty())))
    }

    fn treesitter_prefetch_char_range(&self) -> Option<(usize, usize)> {
        let viewport = self.state.get_viewport_state();
        let lines = viewport.prefetch_lines;
        if lines.is_empty() {
            return None;
        }

        let start_visual = lines.start;
        let end_visual = lines.end.saturating_sub(1);

        let (start_line, _) = self.state.visual_to_logical_line(start_visual);
        let (end_line, _) = self.state.visual_to_logical_line(end_visual);
        let end_line_excl = end_line.saturating_add(1);

        let line_index = &self.state.editor().line_index;
        let start = line_index.position_to_char_offset(start_line, 0);
        let end = line_index.position_to_char_offset(end_line_excl, 0);
        if end > start {
            Some((start, end))
        } else {
            None
        }
    }

    fn refresh_processing(&mut self) -> Result<(), UiError> {
        if let Some(proc) = self.sublime.as_mut() {
            self.state
                .apply_processor(proc)
                .map_err(|e| UiError::Processor(e.to_string()))?;
        }
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        if let Some(worker) = self.treesitter.as_mut() {
            let version = self.state.version();
            worker.requested_version = Some(version);

            if let Some(delta) = self.state.last_text_delta().cloned() {
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::ApplyDelta {
                        version,
                        delta,
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to send delta to tree-sitter worker".to_string())
                    })?;
            } else {
                let text = self.state.editor().get_text();
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
        }
        Ok(())
    }

    fn all_selections_visual(&self) -> Vec<VisualSelection> {
        let cursor = self.state.get_cursor_state();
        let mut out = Vec::new();

        for sel in cursor.selections {
            if sel.start == sel.end {
                continue;
            }
            let Some((a_row, a_x)) = self
                .state
                .logical_position_to_visual(sel.start.line, sel.start.column)
            else {
                continue;
            };
            let Some((b_row, b_x)) = self
                .state
                .logical_position_to_visual(sel.end.line, sel.end.column)
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

    fn all_carets_visual(&self) -> Vec<VisualCaret> {
        let cursor = self.state.get_cursor_state();
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let Some((row, x_cells)) = self
                .state
                .logical_position_to_visual(sel.end.line, sel.end.column)
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
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;
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

    fn pixel_to_visual(&self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.state.get_viewport_state();
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

    fn pixel_to_local_row_col(&self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.state.get_viewport_state();
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

    fn composed_viewport_grid(&self) -> (usize, usize, editor_core::ComposedGrid) {
        let viewport = self.state.get_viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let start_composed = self.composed_start_row_for_doc_row(start_doc_row);
        let grid = self
            .state
            .get_viewport_content_composed(start_composed, row_count);
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
        let usable_h = (self.render_config.height_px as f32 - self.render_config.padding_y_px).max(1.0);
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

    fn composed_start_row_for_doc_row(&self, doc_row: usize) -> usize {
        // Fast path: no above-line virtual text => composed rows are identical to doc visual rows.
        let mut has_above_line = false;
        for layer in self.state.editor().decorations.values() {
            for d in layer {
                if d.placement == editor_core::DecorationPlacement::AboveLine
                    && d.text.as_ref().is_some_and(|t| !t.is_empty())
                {
                    has_above_line = true;
                    break;
                }
            }
            if has_above_line {
                break;
            }
        }
        if !has_above_line {
            return doc_row;
        }

        let (top_logical_line, _visual_in_logical) =
            self.state.editor().visual_to_logical_line(doc_row);

        // Count above-line decorations per logical line.
        let line_index = &self.state.editor().line_index;
        let mut above_count: HashMap<usize, usize> = HashMap::new();
        for layer in self.state.editor().decorations.values() {
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

        let regions = &self.state.get_folding_state().regions;
        let mut prefix = 0usize;
        for line in 0..top_logical_line {
            if is_logical_line_hidden(regions.as_slice(), line) {
                continue;
            }
            prefix = prefix.saturating_add(above_count.get(&line).copied().unwrap_or(0));
        }
        doc_row.saturating_add(prefix)
    }
}

fn is_logical_line_hidden(regions: &[editor_core::FoldRegion], logical_line: usize) -> bool {
    regions.iter().any(|region| {
        region.is_collapsed
            && logical_line > region.start_line
            && logical_line <= region.end_line
    })
}

fn composed_line_index_for_offset(grid: &editor_core::ComposedGrid, char_offset: usize) -> Option<usize> {
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

        if let Some(next) = grid.lines.get(idx + 1) {
            if matches!(next.kind, editor_core::ComposedLineKind::Document { .. })
                && next.char_offset_start == char_offset
            {
                continue;
            }
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
    use editor_core::CursorCommand;
    use editor_core_treesitter::TreeSitterUpdateMode;

    #[test]
    fn ui_text_roundtrip() {
        let ui = EditorUi::new("hello", 80);
        assert_eq!(ui.text(), "hello");
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

        let vp0 = ui.state.get_viewport_state();
        assert_eq!(vp0.height, Some(2));
        assert_eq!(vp0.scroll_top, 0);

        // Move down within the viewport: no scroll.
        ui.move_visual_by_rows(1).unwrap();
        let vp1 = ui.state.get_viewport_state();
        assert_eq!(vp1.scroll_top, 0);

        // Move down out of the viewport: scroll should advance.
        ui.move_visual_by_rows(1).unwrap();
        let vp2 = ui.state.get_viewport_state();
        assert_eq!(vp2.scroll_top, 1);
        assert_eq!(vp2.sub_row_offset, 0);

        // Jump to end: viewport should scroll so caret stays visible.
        ui.move_to_document_end().unwrap();
        let vp3 = ui.state.get_viewport_state();
        let caret_off = ui.cursor_state().offset;
        let (caret_row, _caret_x) = ui.char_offset_to_visual(caret_off).unwrap();
        let h = vp3.height.unwrap_or(1);
        assert!(
            caret_row >= vp3.scroll_top && caret_row < vp3.scroll_top.saturating_add(h),
            "expected caret row to be within visible lines after navigation"
        );
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
    fn ui_selected_text_and_delete_selections_only() {
        let mut ui = EditorUi::new("one two three", 80);

        // Multi-selection: "one" and "three" (skip the caret between them).
        ui.set_selections_offsets(&[(0, 3), (4, 4), (8, 13)], 0)
            .unwrap();
        assert_eq!(ui.selected_text(), "one\nthree");

        // Cut should delete only the non-empty selections.
        ui.delete_selections_only().unwrap();
        assert_eq!(ui.text(), " two ");

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
	        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 4 }))
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
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
            .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"

        ui.set_word_boundary_ascii_boundary_chars(".").unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection)).unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
            .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 7)); // "foo-bar"

        ui.reset_word_boundary_defaults().unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection)).unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
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
        ui2.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 3 }))
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
        ui.set_marked_text_with_selection("你好", 1, 0, None).unwrap();
        assert_eq!(ui.text(), "你好");

        // Cursor is at offset 1 => (line 0, column 1).
        assert_eq!(ui.cursor_state().position, Position::new(0, 1));

        let grid = ui.state.get_viewport_content_styled(0, 1);
        assert_eq!(grid.lines.len(), 1);
        assert_eq!(grid.lines[0].cells.len(), 2);
        assert!(grid.lines[0].cells[0]
            .styles
            .iter()
            .any(|&id| id == IME_MARKED_TEXT_STYLE_ID));
        assert!(grid.lines[0].cells[1]
            .styles
            .iter()
            .any(|&id| id == IME_MARKED_TEXT_STYLE_ID));

        // Committing clears the marked style layer.
        ui.commit_text("你好!").unwrap();
        let grid2 = ui.state.get_viewport_content_styled(0, 1);
        assert!(
            grid2.lines[0]
                .cells
                .iter()
                .all(|c| !c.styles.iter().any(|&id| id == IME_MARKED_TEXT_STYLE_ID)),
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

        let vp0 = ui.state.get_viewport_state();
        assert_eq!(vp0.scroll_top, 0);
        assert_eq!(vp0.sub_row_offset, 0);
        assert_eq!(ui.viewport_row_count_for_render(&vp0), 2);

        // Scrolling up at the top should clamp to 0 (no wrap-around / shake).
        ui.scroll_by_pixels(-5.0);
        let vp0b = ui.state.get_viewport_state();
        assert_eq!(vp0b.scroll_top, 0);
        assert_eq!(vp0b.sub_row_offset, 0);

        // Scroll down by half a row.
        ui.scroll_by_pixels(5.0);

        let vp = ui.state.get_viewport_state();
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
        let vp2 = ui.state.get_viewport_state();
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

        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected a fold region starting at line 0"
        );

        // Click in gutter at visual row 0.
        ui.mouse_down(5.0, 10.0).unwrap();
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && r.is_collapsed),
            "expected fold region to become collapsed after gutter click"
        );

        ui.mouse_down(5.0, 10.0).unwrap();
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected fold region to expand after second gutter click"
        );
    }

    #[test]
    fn ui_nested_fold_unfold_sequence_keeps_inner_toggleable() {
        // Regression for: fold inner -> fold outer -> unfold outer -> inner must still unfold.
        let text = "fn main() {\n  if true {\n    if true {\n      println!(\"hi\");\n    }\n  }\n}\n";
        let mut ui = EditorUi::new(text, 80);
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

        let regions = ui.state.get_folding_state().regions;
        assert!(regions.len() >= 2, "expected nested fold regions from Tree-sitter");

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
            let (row, _x_cells) = ui
                .state
                .logical_position_to_visual(start_line, 0)
                .expect("start line should be visible");
            let y = row as f32 * ui.render_config.line_height_px + ui.render_config.line_height_px * 0.5;
            ui.mouse_down(5.0, y).unwrap();
            ui.mouse_up();
        };

        // 1) Fold inner.
        click_gutter_at_start_line(&mut ui, inner.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == inner.start_line && r.end_line == inner.end_line && r.is_collapsed),
            "expected inner region to be collapsed"
        );

        // 2) Fold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == outer.start_line && r.end_line == outer.end_line && r.is_collapsed),
            "expected outer region to be collapsed"
        );

        // 3) Unfold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == outer.start_line && r.end_line == outer.end_line && !r.is_collapsed),
            "expected outer region to be expanded"
        );

        // 4) Unfold inner (must still be toggleable).
        click_gutter_at_start_line(&mut ui, inner.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == inner.start_line && r.end_line == inner.end_line && !r.is_collapsed),
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
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }))
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
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 1, column: 1 }))
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
            ui.sublime_scope_for_style_id(comment_style),
            Some("comment.line.number-sign.toml")
        );

        let grid = ui.state.get_viewport_content_styled(0, 8);
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected at least one comment-styled cell"
        );

        let regions = ui.state.get_folding_state().regions;
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
        let grid = ui.state.get_viewport_content_styled(0, 2);
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
        let highlights = r#"
        (line_comment) @comment
        (string_literal) @string
        "#;
        let folds = r#"
        (function_item) @fold
        "#;

        let text = r#"// hi
fn main() {
  let s = "x";
}
"#;

        let mut ui = EditorUi::new(text, 80);
        ui.set_treesitter_rust_with_queries(highlights, Some(folds))
            .unwrap();
        wait_for_async_processing(&mut ui);

        let comment_style = ui.treesitter_style_id_for_capture("comment");
        let string_style = ui.treesitter_style_id_for_capture("string");
        assert_eq!(
            ui.treesitter_capture_for_style_id(comment_style),
            Some("comment")
        );
        assert_eq!(
            ui.treesitter_capture_for_style_id(string_style),
            Some("string")
        );

        let grid = ui.state.get_viewport_content_styled(0, 4);
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

        let regions = ui.state.get_folding_state().regions;
        assert!(
            regions.iter().any(|r| r.start_line == 1 && r.end_line == 3),
            "expected fold region for multi-line function"
        );
    }

    #[test]
    fn ui_treesitter_uses_incremental_updates_when_deltas_available() {
        let highlights = r#"(line_comment) @comment"#;
        let mut ui = EditorUi::new("// a\n", 80);
        ui.set_treesitter_rust_with_queries(highlights, None)
            .unwrap();
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
        let highlights = r#"(line_comment) @comment"#;
        let mut ui = EditorUi::new("// a\n", 80);

        // Use a zero-debounce config to keep the test fast and deterministic.
        ui.set_treesitter_processing_config(TreeSitterProcessingConfig {
            debounce_ms: 0,
            ..TreeSitterProcessingConfig::default()
        })
        .unwrap();

        ui.set_treesitter_rust_with_queries(highlights, None).unwrap();
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
        let style_id = (7u32 << 16) | 0u32;
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

        let decorations = ui
            .state
            .editor()
            .decorations
            .get(&editor_core::DecorationLayerId::DOCUMENT_LINKS)
            .cloned()
            .unwrap_or_default();
        assert_eq!(decorations.len(), 1, "expected one document link decoration");

        let grid = ui.state.get_viewport_content_styled(0, 1);
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
}
