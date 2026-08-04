use super::*;

impl EditorUi {
    pub fn lsp_request_formatting(
        &mut self,
        formatting_options_json: &str,
    ) -> Result<u64, UiError> {
        let options = parse_lsp_formatting_options(formatting_options_json)?;
        self.lsp_request_document_result(LspResultSlot::Formatting, |lsp| {
            lsp.request_formatting(options)
        })
    }

    pub fn lsp_take_last_formatting_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Formatting)
    }

    pub fn lsp_request_range_formatting(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        formatting_options_json: &str,
    ) -> Result<u64, UiError> {
        let options = parse_lsp_formatting_options(formatting_options_json)?;
        let (start_offset, end_offset) = if start_offset <= end_offset {
            (start_offset, end_offset)
        } else {
            (end_offset, start_offset)
        };

        self.lsp_request_with_line_index_result(
            LspResultSlot::RangeFormatting,
            |lsp, line_index| {
                lsp.request_range_formatting(line_index, start_offset, end_offset, options)
            },
        )
    }

    pub fn lsp_take_last_range_formatting_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::RangeFormatting)
    }
}
