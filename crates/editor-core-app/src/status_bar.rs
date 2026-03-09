use editor_core::workspace::{BufferId, ViewId, Workspace};
use editor_core_lang::LanguageRegistry;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusBarInfo {
    pub path_display: Option<String>,
    pub line_1_based: usize,
    pub column_1_based: usize,
    pub selection_len_chars: usize,
    pub file_size_bytes: usize,
    pub language_name: Option<String>,
    pub indentation_display: String,
}

#[derive(Debug, Error)]
pub enum StatusBarError {
    #[error("workspace error: {0}")]
    Workspace(String),
}

impl From<editor_core::workspace::WorkspaceError> for StatusBarError {
    fn from(err: editor_core::workspace::WorkspaceError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

fn path_display(path: &Path, workspace_root: Option<&Path>) -> String {
    if let Some(root) = workspace_root {
        if let Ok(rel) = path.strip_prefix(root) {
            let rel = rel.to_string_lossy().replace('\\', "/");
            return if rel.is_empty() { ".".to_string() } else { rel };
        }

        if let (Ok(root), Ok(path)) = (root.canonicalize(), path.canonicalize())
            && path.starts_with(&root)
        {
            let rel = path.strip_prefix(&root).unwrap_or(&path);
            let rel = rel.to_string_lossy().replace('\\', "/");
            return if rel.is_empty() { ".".to_string() } else { rel };
        }
    }
    path.to_string_lossy().to_string()
}

fn language_name_for_path(reg: Option<&LanguageRegistry>, path: &Path) -> Option<String> {
    if let Some(reg) = reg {
        if let Some(lang) = reg.language_for_path(path) {
            return Some(lang.display_name.clone());
        }
    }
    path.extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_ascii_uppercase())
}

fn buffer_path(ws: &Workspace, buffer_id: BufferId) -> Option<PathBuf> {
    let uri = ws.buffer_metadata(buffer_id)?.uri.as_deref()?;
    editor_core_lsp::file_uri_to_path(uri)
}

pub fn status_bar_info(
    ws: &Workspace,
    view_id: ViewId,
    workspace_root: Option<&Path>,
    languages: Option<&LanguageRegistry>,
) -> Result<StatusBarInfo, StatusBarError> {
    let buffer_id = ws.buffer_id_for_view(view_id)?;

    let cursor = ws.cursor_state_for_view(view_id)?;
    let line = cursor.position.line.saturating_add(1);
    let column = cursor.position.column.saturating_add(1);

    let selection_len_chars = if let Some(sel) = cursor.selection {
        let line_index = ws.buffer_line_index(buffer_id)?;
        let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
        let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
        a.max(b).saturating_sub(a.min(b))
    } else {
        0
    };

    let text = ws.buffer_text(buffer_id)?;
    let file_size_bytes = text.as_bytes().len();

    let (path_display, language_name) = if let Some(path) = buffer_path(ws, buffer_id) {
        (
            Some(path_display(&path, workspace_root)),
            language_name_for_path(languages, &path),
        )
    } else {
        (None, None)
    };

    let indent_cfg = ws.indentation_config_for_view(view_id)?;
    let indentation_display = match indent_cfg.style {
        editor_core_lang::IndentStyle::Tabs => "Tabs".to_string(),
        editor_core_lang::IndentStyle::Spaces(w) => format!("Spaces: {}", w),
    };

    Ok(StatusBarInfo {
        path_display,
        line_1_based: line,
        column_1_based: column,
        selection_len_chars,
        file_size_bytes,
        language_name,
        indentation_display,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{Command, CursorCommand, Workspace};
    use pretty_assertions::assert_eq;

    #[test]
    fn status_bar_includes_relative_path_and_position() {
        let mut ws = Workspace::new();
        let opened = ws
            .open_buffer(Some("file:///tmp/proj/src/main.rs".to_string()), "abc\n", 80)
            .unwrap();
        ws.execute(
            opened.view_id,
            Command::Cursor(CursorCommand::MoveTo { line: 0, column: 2 }),
        )
        .unwrap();

        let reg = LanguageRegistry::default();
        let info = status_bar_info(
            &ws,
            opened.view_id,
            Some(Path::new("/tmp/proj")),
            Some(&reg),
        )
        .unwrap();
        assert_eq!(info.line_1_based, 1);
        assert_eq!(info.column_1_based, 3);
        assert_eq!(info.path_display.as_deref(), Some("src/main.rs"));
    }
}
