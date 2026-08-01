use crate::*;

impl EditorUi {
    pub(crate) fn treesitter_prefetch_char_range(&mut self) -> Option<(usize, usize)> {
        let viewport = self.viewport_state();
        let lines = viewport.prefetch_lines;
        if lines.is_empty() {
            return None;
        }

        let start_visual = lines.start;
        let end_visual = lines.end.saturating_sub(1);

        let mut doc = self.lock_doc();
        let (start_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, start_visual)
            .ok()?;
        let (end_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, end_visual)
            .ok()?;
        let end_line_excl = end_line.saturating_add(1);

        let line_index = doc.ws.buffer_line_index(self.buffer_id).ok()?;
        let start = line_index.position_to_char_offset(start_line, 0);
        let end = line_index.position_to_char_offset(end_line_excl, 0);
        if end > start {
            Some((start, end))
        } else {
            None
        }
    }
}
