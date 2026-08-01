use super::super::*;

impl EditorUi {
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
}
