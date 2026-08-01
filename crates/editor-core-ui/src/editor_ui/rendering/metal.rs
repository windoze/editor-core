use super::*;

impl EditorUi {
    /// Enable the Skia Metal backend (macOS only).
    ///
    /// This is a rendering backend switch only; it does not affect editor state.
    pub fn enable_metal(
        &mut self,
        metal_device: *mut c_void,
        metal_command_queue: *mut c_void,
    ) -> Result<(), UiError> {
        self.renderer
            .enable_metal(metal_device, metal_command_queue)?;
        Ok(())
    }

    /// Disable the Metal backend and revert to CPU raster output.
    pub fn disable_metal(&mut self) {
        self.renderer.disable_metal();
    }

    /// Render the current visible viewport into a Metal texture (macOS only).
    ///
    /// The host is responsible for presenting the texture (e.g. `CAMetalDrawable`).
    pub fn render_metal_visible_into_texture(
        &mut self,
        metal_texture: *mut c_void,
    ) -> Result<(), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let render_config = self.render_config_for_visible_viewport(viewport.sub_row_offset);
        let fold_markers = self.collect_fold_markers();

        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_into_metal_texture(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
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
            self.renderer.render_rgba_into_metal_texture(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
            )?;
        }

        Ok(())
    }
}
