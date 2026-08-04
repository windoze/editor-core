use super::*;

impl EditorUi {
    pub fn treesitter_last_update_mode(&self) -> Option<TreeSitterUpdateMode> {
        let doc = self.lock_doc();
        doc.treesitter.as_ref().and_then(|w| w.last_update_mode)
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .capture_for_style_id(style_id)
            .map(|s| s.to_string())
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        let mut doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .style_id_for_capture(capture_name)
    }
}
