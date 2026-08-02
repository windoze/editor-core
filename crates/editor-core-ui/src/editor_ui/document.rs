use super::*;

impl EditorUi {
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
            lsp_result_events: std::collections::VecDeque::new(),
            next_lsp_result_event_sequence: 1,
            lsp_request_events: std::collections::VecDeque::new(),
            next_lsp_request_event_sequence: 1,
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
}
