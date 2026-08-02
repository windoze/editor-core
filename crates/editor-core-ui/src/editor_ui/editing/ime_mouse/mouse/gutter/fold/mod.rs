mod composed;
mod headless;
mod region;

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
            return composed::toggle_composed_fold_from_gutter_click(self, x_px, y_px);
        }

        headless::toggle_headless_fold_from_gutter_click(self, x_px, y_px)
    }
}
