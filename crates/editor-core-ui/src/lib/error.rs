use editor_core_render_skia::RenderError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
    #[error("processor error: {0}")]
    Processor(String),
}
