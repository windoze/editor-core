//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

use editor_core::{Command, EditCommand, EditorStateManager};
use editor_core_render_skia::{RenderConfig, RenderError, RenderTheme, SkiaRenderer};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
}

/// A minimal "single buffer, single view" UI wrapper.
///
/// Later we can add a `Workspace`-backed version for tabs/splits.
pub struct EditorUi {
    state: EditorStateManager,
    renderer: SkiaRenderer,
    theme: RenderTheme,
    render_config: RenderConfig,
}

impl EditorUi {
    pub fn new(initial_text: &str, viewport_width_cells: usize) -> Self {
        Self {
            state: EditorStateManager::new(initial_text, viewport_width_cells),
            renderer: SkiaRenderer::new(),
            theme: RenderTheme::default(),
            render_config: RenderConfig::default(),
        }
    }

    pub fn text(&self) -> String {
        self.state.editor().get_text()
    }

    pub fn set_theme(&mut self, theme: RenderTheme) {
        self.theme = theme;
    }

    pub fn set_render_config(&mut self, config: RenderConfig) {
        self.render_config = config;
    }

    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))?;
        Ok(())
    }

    pub fn render_rgba(&mut self, start_row: usize, row_count: usize) -> Result<Vec<u8>, UiError> {
        let grid = self.state.get_viewport_content_styled(start_row, row_count);
        let rgba = self
            .renderer
            .render_rgba(&grid, None, None, self.render_config, &self.theme)?;
        Ok(rgba)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ui_text_roundtrip() {
        let ui = EditorUi::new("hello", 80);
        assert_eq!(ui.text(), "hello");
    }
}
