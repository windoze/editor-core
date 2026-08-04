mod apply;
mod clear;
mod range;

use super::*;

#[derive(Debug, Clone)]
pub(super) struct MarkedReplacement {
    pub(super) start: usize,
    pub(super) replace_len: usize,
    pub(super) original_text: String,
    pub(super) original_len: usize,
}

impl EditorUi {
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
        let replacement = self.resolve_marked_replacement(replace_range)?;

        // Empty marked text means "cancel/clear composition": restore original replaced text.
        if new_len == 0 {
            return self.clear_marked_text(replacement);
        }

        self.replace_marked_text(text, selected_start, selected_len, replacement, new_len)
    }
}
