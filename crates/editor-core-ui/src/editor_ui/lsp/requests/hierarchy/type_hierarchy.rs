use super::super::super::*;

impl EditorUi {
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
}
