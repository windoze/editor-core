use super::super::*;

impl EditorUi {
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
}
