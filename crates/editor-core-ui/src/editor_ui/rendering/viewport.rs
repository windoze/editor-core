use super::*;

impl EditorUi {
    pub(in crate::editor_ui) fn pixel_to_visual(&mut self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let global_row = viewport.scroll_top + local_row;
        (global_row, col)
    }

    pub(in crate::editor_ui) fn pixel_to_local_row_col(
        &mut self,
        x_px: f32,
        y_px: f32,
    ) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        (local_row, col)
    }

    pub(in crate::editor_ui) fn composed_viewport_grid(
        &mut self,
    ) -> (usize, usize, editor_core::ComposedGrid) {
        let viewport = self.viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let start_composed = self.composed_start_row_for_doc_row(start_doc_row);
        let grid = {
            let mut doc = self.lock_doc();
            doc.ws
                .get_viewport_content_composed(self.view_id, start_composed, row_count)
                .unwrap_or_else(|_| editor_core::ComposedGrid::new(start_composed, row_count))
        };
        (start_composed, row_count, grid)
    }

    pub(crate) fn viewport_row_count_for_render(
        &self,
        viewport: &editor_core::ViewportState,
    ) -> usize {
        let start_row = viewport.scroll_top;
        let base = viewport
            .height
            .unwrap_or(viewport.total_visual_lines.saturating_sub(start_row));

        // When the pixel viewport height does not fit an integer number of rows (or when a
        // sub-row scroll offset is present), the bottom of the viewport can reveal part of the
        // next visual row. We still render it and rely on the host to clip.
        //
        // We compute the required row count from pixel geometry to avoid artifacts such as:
        // - the last partially visible row being fully hidden
        // - blank strips when `sub_row_offset` is close to a full row
        if viewport.height.is_none() {
            return base;
        }

        let line_h = self.render_config.line_height_px.max(1.0);
        // See `set_viewport_px`: vertical padding is a top inset, not top+bottom.
        let usable_h =
            (self.render_config.height_px as f32 - self.render_config.padding_y_px).max(1.0);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let desired_rows = ((usable_h + scroll_y_px) / line_h).ceil().max(1.0) as usize;
        let max_rows = viewport.total_visual_lines.saturating_sub(start_row);
        base.max(desired_rows).min(max_rows.max(1))
    }

    pub(in crate::editor_ui) fn sub_row_offset_to_scroll_y_px(&self, sub_row_offset: u16) -> f32 {
        // Interpret `sub_row_offset` as a fraction of a row using a 65536 denominator.
        // This keeps the invariant that 65535 corresponds to "almost a full row", not exactly one.
        let line_h = self.render_config.line_height_px.max(1.0);
        (sub_row_offset as f32 / 65536.0) * line_h
    }

    pub(super) fn composed_start_row_for_doc_row(&mut self, doc_row: usize) -> usize {
        // Fast path: no above-line virtual text => composed rows are identical to doc visual rows.
        let mut doc = self.lock_doc();
        let has_above_line =
            doc.ws
                .buffer_decorations(self.buffer_id)
                .ok()
                .is_some_and(|decorations| {
                    decorations.values().any(|layer| {
                        layer.iter().any(|d| {
                            d.placement == editor_core::DecorationPlacement::AboveLine
                                && d.text.as_ref().is_some_and(|t| !t.is_empty())
                        })
                    })
                });
        if !has_above_line {
            return doc_row;
        }

        let Ok((top_logical_line, _visual_in_logical)) =
            doc.ws.visual_to_logical_for_view(self.view_id, doc_row)
        else {
            return doc_row;
        };

        // Count above-line decorations per logical line.
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return doc_row;
        };
        let Ok(decorations) = doc.ws.buffer_decorations(self.buffer_id) else {
            return doc_row;
        };
        let mut above_count: HashMap<usize, usize> = HashMap::new();
        for layer in decorations.values() {
            for d in layer {
                if d.placement != editor_core::DecorationPlacement::AboveLine {
                    continue;
                }
                let Some(text) = d.text.as_ref() else {
                    continue;
                };
                if text.is_empty() {
                    continue;
                }
                let line = line_index.char_offset_to_position(d.range.start).0;
                *above_count.entry(line).or_insert(0) += 1;
            }
        }

        let mut prefix = 0usize;
        if !above_count.is_empty() {
            let regions = doc
                .ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default();
            for (line, count) in above_count {
                if line >= top_logical_line || is_logical_line_hidden(regions.as_slice(), line) {
                    continue;
                }
                prefix = prefix.saturating_add(count);
            }
        }
        doc_row.saturating_add(prefix)
    }
}
