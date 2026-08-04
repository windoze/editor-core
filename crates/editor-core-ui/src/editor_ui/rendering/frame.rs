use super::*;

impl EditorUi {
    pub fn render_rgba_visible(&mut self) -> Result<Vec<u8>, UiError> {
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        let mut out = vec![0u8; required];
        self.render_rgba_visible_into(out.as_mut_slice())?;
        Ok(out)
    }

    pub fn required_rgba_len(&self) -> usize {
        (self.render_config.width_px as usize)
            .saturating_mul(self.render_config.height_px as usize)
            .saturating_mul(4)
    }

    pub fn render_rgba_visible_into(&mut self, out_rgba: &mut [u8]) -> Result<usize, UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let render_config = self.render_config_for_visible_viewport(viewport.sub_row_offset);
        let fold_markers = self.collect_fold_markers();
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_rgba_into(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        } else {
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();
            self.renderer.render_rgba_into(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        }
        Ok(required)
    }
}
