use super::*;

impl EditorUi {
    pub(super) fn resolve_marked_replacement(
        &mut self,
        replace_range: Option<(usize, usize)>,
    ) -> Result<MarkedReplacement, UiError> {
        if let Some((start, len)) = replace_range {
            let original = {
                let doc = self.lock_doc();
                doc.ws
                    .buffer_text_range(self.buffer_id, start, len)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            return Ok(MarkedReplacement {
                start,
                replace_len: len,
                original_text: original,
                original_len: len,
            });
        }

        if let Some(marked) = self.marked.as_ref() {
            return Ok(MarkedReplacement {
                start: marked.start,
                replace_len: marked.len,
                original_text: marked.original_text.clone(),
                original_len: marked.original_len,
            });
        }

        let cursor = self.cursor_state();
        let Some(sel) = cursor.selection else {
            return Ok(MarkedReplacement {
                start: cursor.offset,
                replace_len: 0,
                original_text: String::new(),
                original_len: 0,
            });
        };

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
        Ok(MarkedReplacement {
            start,
            replace_len: len,
            original_text: original,
            original_len: len,
        })
    }
}
