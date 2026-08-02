use super::*;

impl EditorUi {
    pub(crate) fn maybe_request_lsp_on_type_formatting(
        &mut self,
        ch: &str,
    ) -> Result<bool, UiError> {
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
}
