mod appearance_search;
mod coordinates;
mod editing;
mod lsp;
mod rendering;
mod selection;
mod syntax;
mod viewport;

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
}
