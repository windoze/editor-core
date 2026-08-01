mod lsp;

use super::*;

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
    pub(crate) fn lock_doc(&self) -> std::sync::MutexGuard<'_, EditorUiDoc> {
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

    /// Hit-test and return the raw LSP `CodeLens` JSON (if any) at the given view point.
    ///
    /// Code lens is rendered as above-line virtual text. Unlike document-link hit-testing, this
    /// intentionally checks the composed virtual cells first so clicking the corresponding document
    /// line start does not accidentally trigger a code lens anchored at the same offset.
    pub fn code_lens_json_at_view_point_px(&mut self, x_px: f32, y_px: f32) -> Option<String> {
        if !self.has_virtual_text_decorations() {
            return None;
        }

        let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
        if grid.lines.is_empty() {
            return None;
        }

        let (local_row, x_cells) = self.pixel_to_local_row_col(x_px, y_px);
        let line = grid.lines.get(local_row)?;
        if !matches!(line.kind, ComposedLineKind::VirtualAboveLine { .. }) {
            return None;
        }

        let mut x = 0usize;
        let mut anchor_offset: Option<usize> = None;
        for cell in &line.cells {
            let w = cell.width.max(1);
            if x_cells < x.saturating_add(w) {
                if let ComposedCellSource::Virtual { anchor_offset: off } = cell.source {
                    anchor_offset = Some(off);
                }
                break;
            }
            x = x.saturating_add(w);
        }
        let anchor_offset = anchor_offset?;
        let text: String = line.cells.iter().map(|cell| cell.ch).collect();

        let doc = self.lock_doc();
        let layer = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .ok()?
            .get(&DecorationLayerId::CODE_LENS)?;

        layer
            .iter()
            .filter(|d| {
                d.kind == DecorationKind::CodeLens
                    && d.placement == DecorationPlacement::AboveLine
                    && d.range.start == anchor_offset
            })
            .find(|d| d.text.as_deref() == Some(text.as_str()))
            .or_else(|| {
                layer.iter().find(|d| {
                    d.kind == DecorationKind::CodeLens
                        && d.placement == DecorationPlacement::AboveLine
                        && d.range.start == anchor_offset
                })
            })
            .and_then(|d| d.data_json.clone())
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

    pub(crate) fn viewport_row_count_for_render(
        &self,
        viewport: &editor_core::ViewportState,
    ) -> usize {
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
