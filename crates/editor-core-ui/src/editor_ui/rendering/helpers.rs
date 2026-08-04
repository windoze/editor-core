use super::*;

impl EditorUi {
    pub(in crate::editor_ui) fn has_virtual_text_decorations(&self) -> bool {
        let doc = self.lock_doc();
        doc.ws
            .buffer_decorations(self.buffer_id)
            .ok()
            .map(|decorations| {
                decorations.values().any(|layer| {
                    layer
                        .iter()
                        .any(|d| d.text.as_ref().is_some_and(|t| !t.is_empty()))
                })
            })
            .unwrap_or(false)
    }

    pub(in crate::editor_ui::rendering) fn render_config_for_visible_viewport(
        &self,
        sub_row_offset: u16,
    ) -> RenderConfig {
        let mut render_config = self.render_config;
        render_config.scroll_y_px = self.sub_row_offset_to_scroll_y_px(sub_row_offset);
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };
        render_config
    }

    pub(in crate::editor_ui::rendering) fn collect_fold_markers(&self) -> Vec<FoldMarker> {
        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        let mut fold_markers = Vec::new();
        for region in fold_regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }
        fold_markers
    }

    pub(in crate::editor_ui::rendering) fn all_selections_visual(
        &mut self,
    ) -> Vec<VisualSelection> {
        let cursor = self.cursor_state();
        let mut out = Vec::new();
        let mut doc = self.lock_doc();

        for sel in cursor.selections {
            if sel.start == sel.end {
                continue;
            }
            let Some((a_row, a_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.start.line, sel.start.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            let Some((b_row, b_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            out.push(VisualSelection {
                start_row: a_row as u32,
                start_x_cells: a_x as u32,
                end_row: b_row as u32,
                end_x_cells: b_x as u32,
            });
        }

        out
    }

    pub(in crate::editor_ui::rendering) fn all_carets_visual(&mut self) -> Vec<VisualCaret> {
        let cursor = self.cursor_state();
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        let mut doc = self.lock_doc();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let Some((row, x_cells)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };

            // Draw primary caret last so it wins in overlaps.
            let caret = VisualCaret {
                row: row as u32,
                x_cells: x_cells as u32,
            };
            if idx == primary_idx {
                primary.push(caret);
            } else {
                secondary.push(caret);
            }
        }
        secondary.extend(primary);
        secondary
    }

    pub(in crate::editor_ui::rendering) fn all_caret_offsets(&self) -> Vec<usize> {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return Vec::new();
        };
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let offset = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if idx == primary_idx {
                primary.push(offset);
            } else {
                secondary.push(offset);
            }
        }
        secondary.extend(primary);
        secondary
    }
}
