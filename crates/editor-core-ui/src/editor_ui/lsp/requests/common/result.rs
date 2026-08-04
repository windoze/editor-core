use super::*;

impl EditorUi {
    pub(crate) fn lsp_take_last_result_json(&mut self, slot: LspResultSlot) -> Option<String> {
        let mut doc = self.lock_doc();
        doc.lsp_last_result_json.remove(&(self.view_id, slot))
    }
}
