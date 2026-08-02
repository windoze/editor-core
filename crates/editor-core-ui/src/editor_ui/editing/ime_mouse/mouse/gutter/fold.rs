use super::*;

impl EditorUi {
    pub(in crate::editor_ui::editing::ime_mouse::mouse) fn toggle_fold_from_gutter_click(
        &mut self,
        x_px: f32,
        y_px: f32,
    ) -> Result<bool, UiError> {
        if self.render_config.gutter_width_cells == 0 {
            return Ok(false);
        }

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let gutter_end_x = self.render_config.padding_x_px + gutter_px;
        if x_px >= gutter_end_x {
            return Ok(false);
        }

        if self.has_virtual_text_decorations() {
            return self.toggle_composed_fold_from_gutter_click(x_px, y_px);
        }

        self.toggle_headless_fold_from_gutter_click(x_px, y_px)
    }

    fn toggle_composed_fold_from_gutter_click(
        &mut self,
        x_px: f32,
        y_px: f32,
    ) -> Result<bool, UiError> {
        let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
        let (local_row, _x_cells) = self.pixel_to_local_row_col(x_px, y_px);
        let Some(line) = grid.lines.get(local_row) else {
            return Ok(false);
        };
        let editor_core::ComposedLineKind::Document { logical_line, .. } = line.kind else {
            return Ok(false);
        };

        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        let Some(region) = fold_regions
            .iter()
            .filter(|r| r.start_line == logical_line)
            .min_by_key(|r| r.end_line)
            .cloned()
        else {
            return Ok(false);
        };

        self.toggle_fold_region(region.start_line, region.end_line, region.is_collapsed)?;
        Ok(true)
    }

    fn toggle_headless_fold_from_gutter_click(
        &mut self,
        x_px: f32,
        y_px: f32,
    ) -> Result<bool, UiError> {
        let (row, _x_cells) = self.pixel_to_visual(x_px, y_px);
        let pos = {
            let mut doc = self.lock_doc();
            doc.ws
                .visual_position_to_logical_for_view(self.view_id, row, 0)
                .ok()
                .flatten()
        };
        let Some(pos) = pos else {
            return Ok(false);
        };

        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        let Some(region) = fold_regions
            .iter()
            .filter(|r| r.start_line == pos.line)
            .min_by_key(|r| r.end_line)
            .cloned()
        else {
            return Ok(false);
        };

        self.toggle_fold_region(region.start_line, region.end_line, region.is_collapsed)?;
        Ok(true)
    }

    fn toggle_fold_region(
        &mut self,
        start_line: usize,
        end_line: usize,
        is_collapsed: bool,
    ) -> Result<(), UiError> {
        if is_collapsed {
            self.exec_core(Command::Style(StyleCommand::Unfold { start_line }))
                .map(|_| ())
        } else {
            self.exec_core(Command::Style(StyleCommand::Fold {
                start_line,
                end_line,
            }))
            .map(|_| ())
        }
    }
}
