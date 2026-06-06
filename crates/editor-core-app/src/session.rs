use editor_core::UndoHistorySnapshot;
use editor_core::commands::{Selection, SelectionDirection};
use editor_core::workspace::{BufferId, ViewId, Workspace};
use editor_core::{Command, CursorCommand, LineEnding, ViewCommand, WrapIndent, WrapMode};
use serde::{Deserialize, Serialize};
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppSessionError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("workspace error: {0}")]
    Workspace(String),
    #[error("snapshot version not supported: {0}")]
    UnsupportedVersion(u32),
    #[error("invalid snapshot: {0}")]
    InvalidSnapshot(String),
}

impl From<editor_core::workspace::WorkspaceError> for AppSessionError {
    fn from(err: editor_core::workspace::WorkspaceError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

impl From<editor_core::workspace::WorkspaceUndoHistoryRestoreError> for AppSessionError {
    fn from(err: editor_core::workspace::WorkspaceUndoHistoryRestoreError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LineEndingSnapshot {
    Lf,
    Crlf,
}

impl From<LineEnding> for LineEndingSnapshot {
    fn from(v: LineEnding) -> Self {
        match v {
            LineEnding::Lf => Self::Lf,
            LineEnding::Crlf => Self::Crlf,
        }
    }
}

impl From<LineEndingSnapshot> for LineEnding {
    fn from(v: LineEndingSnapshot) -> Self {
        match v {
            LineEndingSnapshot::Lf => Self::Lf,
            LineEndingSnapshot::Crlf => Self::Crlf,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WrapModeSnapshot {
    None,
    Char,
    Word,
}

impl From<WrapMode> for WrapModeSnapshot {
    fn from(v: WrapMode) -> Self {
        match v {
            WrapMode::None => Self::None,
            WrapMode::Char => Self::Char,
            WrapMode::Word => Self::Word,
        }
    }
}

impl From<WrapModeSnapshot> for WrapMode {
    fn from(v: WrapModeSnapshot) -> Self {
        match v {
            WrapModeSnapshot::None => Self::None,
            WrapModeSnapshot::Char => Self::Char,
            WrapModeSnapshot::Word => Self::Word,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum WrapIndentSnapshot {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<WrapIndent> for WrapIndentSnapshot {
    fn from(v: WrapIndent) -> Self {
        match v {
            WrapIndent::None => Self::None,
            WrapIndent::SameAsLineIndent => Self::SameAsLineIndent,
            WrapIndent::FixedCells(cells) => Self::FixedCells { cells },
        }
    }
}

impl From<WrapIndentSnapshot> for WrapIndent {
    fn from(v: WrapIndentSnapshot) -> Self {
        match v {
            WrapIndentSnapshot::None => Self::None,
            WrapIndentSnapshot::SameAsLineIndent => Self::SameAsLineIndent,
            WrapIndentSnapshot::FixedCells { cells } => Self::FixedCells(cells),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BufferSnapshot {
    pub uri: Option<String>,
    pub text_lf: String,
    pub line_ending: LineEndingSnapshot,
    pub undo: UndoHistorySnapshot,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ViewSnapshot {
    /// Index into `HotExitSnapshot.buffers`.
    pub buffer_index: usize,
    pub viewport_width: usize,
    pub wrap_mode: WrapModeSnapshot,
    pub wrap_indent: WrapIndentSnapshot,
    pub tab_width: usize,
    pub scroll_top: usize,
    pub scroll_sub_row_offset: u16,
    pub overscan_rows: usize,
    pub selections: Vec<Selection>,
    pub primary_selection_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HotExitSnapshot {
    pub format_version: u32,
    pub buffers: Vec<BufferSnapshot>,
    pub views: Vec<ViewSnapshot>,
    pub active_view_index: Option<usize>,
}

impl HotExitSnapshot {
    pub const VERSION: u32 = 1;

    pub fn capture(ws: &mut Workspace) -> Result<Self, AppSessionError> {
        let mut buffers: Vec<BufferSnapshot> = Vec::new();
        let mut buffer_id_to_index = std::collections::HashMap::<BufferId, usize>::new();

        for buffer_id in ws.buffer_ids() {
            let meta = ws.buffer_metadata(buffer_id).ok_or_else(|| {
                AppSessionError::InvalidSnapshot(format!("missing buffer {:?}", buffer_id.get()))
            })?;

            let text_lf = ws.buffer_text(buffer_id)?;
            let line_ending = ws.line_ending_for_buffer(buffer_id)?;
            let undo = ws.undo_history_snapshot_for_buffer(buffer_id)?;

            let idx = buffers.len();
            buffers.push(BufferSnapshot {
                uri: meta.uri.clone(),
                text_lf,
                line_ending: line_ending.into(),
                undo,
            });
            buffer_id_to_index.insert(buffer_id, idx);
        }

        let mut views: Vec<ViewSnapshot> = Vec::new();
        for view_id in ws.view_ids() {
            let buffer_id = ws.buffer_id_for_view(view_id)?;
            let Some(&buffer_index) = buffer_id_to_index.get(&buffer_id) else {
                return Err(AppSessionError::InvalidSnapshot(format!(
                    "view {:?} refers to unknown buffer {:?}",
                    view_id.get(),
                    buffer_id.get()
                )));
            };

            let viewport_width = ws.viewport_width_for_view(view_id)?;
            let wrap_mode = ws.wrap_mode_for_view(view_id)?;
            let wrap_indent = ws.wrap_indent_for_view(view_id)?;
            let tab_width = ws.tab_width_for_view(view_id)?;
            let scroll_top = ws.scroll_top_for_view(view_id)?;
            let scroll_sub_row_offset = ws.scroll_sub_row_offset_for_view(view_id)?;
            let overscan_rows = ws.overscan_rows_for_view(view_id)?;

            let cursor = ws.cursor_state_for_view(view_id)?;
            let selections = cursor.selections;
            let primary_selection_index = cursor.primary_selection_index;

            views.push(ViewSnapshot {
                buffer_index,
                viewport_width,
                wrap_mode: wrap_mode.into(),
                wrap_indent: wrap_indent.into(),
                tab_width,
                scroll_top,
                scroll_sub_row_offset,
                overscan_rows,
                selections,
                primary_selection_index,
            });
        }

        let active_view_id = ws.active_view_id();
        let active_view_index =
            active_view_id.and_then(|id| ws.view_ids().iter().position(|v| *v == id));

        Ok(Self {
            format_version: Self::VERSION,
            buffers,
            views,
            active_view_index,
        })
    }

    pub fn restore(&self) -> Result<Workspace, AppSessionError> {
        if self.format_version != Self::VERSION {
            return Err(AppSessionError::UnsupportedVersion(self.format_version));
        }

        let mut ws = Workspace::new();

        // Restore buffers first.
        let mut buffer_index_to_id: Vec<BufferId> = Vec::with_capacity(self.buffers.len());
        let mut first_view_for_buffer: Vec<Option<ViewId>> = vec![None; self.buffers.len()];

        for (idx, buf) in self.buffers.iter().enumerate() {
            let opened = ws.open_buffer(buf.uri.clone(), &buf.text_lf, 80)?;
            ws.set_line_ending_for_buffer(opened.buffer_id, buf.line_ending.into())?;
            ws.restore_undo_history_for_buffer(opened.buffer_id, buf.undo.clone())?;

            buffer_index_to_id.push(opened.buffer_id);
            first_view_for_buffer[idx] = Some(opened.view_id);
        }

        // Restore views: reuse the first view per buffer, then create additional ones.
        let mut restored_view_ids: Vec<ViewId> = Vec::with_capacity(self.views.len());
        let mut used_first_view: Vec<bool> = vec![false; self.buffers.len()];

        for view in &self.views {
            let buffer_index = view.buffer_index;
            let buffer_id = *buffer_index_to_id.get(buffer_index).ok_or_else(|| {
                AppSessionError::InvalidSnapshot("invalid buffer_index".to_string())
            })?;
            let used_first_view_for_buffer =
                used_first_view.get_mut(buffer_index).ok_or_else(|| {
                    AppSessionError::InvalidSnapshot("invalid buffer_index".to_string())
                })?;

            let view_id = if !*used_first_view_for_buffer {
                *used_first_view_for_buffer = true;
                first_view_for_buffer
                    .get(buffer_index)
                    .copied()
                    .flatten()
                    .ok_or_else(|| {
                        AppSessionError::InvalidSnapshot(
                            "missing first view for buffer".to_string(),
                        )
                    })?
            } else {
                ws.create_view(buffer_id, view.viewport_width)?
            };

            // Restore per-view config.
            ws.execute(
                view_id,
                Command::View(ViewCommand::SetViewportWidth {
                    width: view.viewport_width,
                }),
            )?;
            ws.execute(
                view_id,
                Command::View(ViewCommand::SetWrapMode {
                    mode: view.wrap_mode.into(),
                }),
            )?;
            ws.execute(
                view_id,
                Command::View(ViewCommand::SetWrapIndent {
                    indent: view.wrap_indent.into(),
                }),
            )?;
            ws.execute(
                view_id,
                Command::View(ViewCommand::SetTabWidth {
                    width: view.tab_width,
                }),
            )?;

            ws.set_scroll_top(view_id, view.scroll_top)?;
            ws.set_scroll_sub_row_offset(view_id, view.scroll_sub_row_offset)?;
            ws.set_overscan_rows(view_id, view.overscan_rows)?;

            // Restore selections/carets.
            let selections = if view.selections.is_empty() {
                // Ensure at least one caret exists.
                vec![Selection {
                    start: editor_core::Position::new(0, 0),
                    end: editor_core::Position::new(0, 0),
                    direction: SelectionDirection::Forward,
                }]
            } else {
                view.selections.clone()
            };

            ws.execute(
                view_id,
                Command::Cursor(CursorCommand::SetSelections {
                    primary_index: view
                        .primary_selection_index
                        .min(selections.len().saturating_sub(1)),
                    selections,
                }),
            )?;

            restored_view_ids.push(view_id);
        }

        if let Some(active_idx) = self.active_view_index
            && let Some(&active_view_id) = restored_view_ids.get(active_idx)
        {
            let _ = ws.set_active_view(active_view_id);
        }

        Ok(ws)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppSession {
    pub format_version: u32,
    pub workspace_root: Option<String>,
    pub recent_folders: Vec<String>,
    pub recent_files: Vec<String>,
    pub hot_exit: Option<HotExitSnapshot>,
}

impl Default for AppSession {
    fn default() -> Self {
        Self::new()
    }
}

impl AppSession {
    pub const VERSION: u32 = 1;

    pub fn new() -> Self {
        Self {
            format_version: Self::VERSION,
            workspace_root: None,
            recent_folders: Vec::new(),
            recent_files: Vec::new(),
            hot_exit: None,
        }
    }

    pub fn set_workspace_root(&mut self, root: Option<&Path>) {
        self.workspace_root = root.map(|p| p.to_string_lossy().to_string());
    }

    pub fn push_recent_folder(&mut self, path: &Path) {
        let s = path.to_string_lossy().to_string();
        self.recent_folders.retain(|v| v != &s);
        self.recent_folders.insert(0, s);
        self.recent_folders.truncate(32);
    }

    pub fn push_recent_file(&mut self, path: &Path) {
        let s = path.to_string_lossy().to_string();
        self.recent_files.retain(|v| v != &s);
        self.recent_files.insert(0, s);
        self.recent_files.truncate(64);
    }

    pub fn capture_hot_exit(&mut self, ws: &mut Workspace) -> Result<(), AppSessionError> {
        self.hot_exit = Some(HotExitSnapshot::capture(ws)?);
        Ok(())
    }
}

pub fn save_session_json(path: &Path, session: &AppSession) -> Result<(), AppSessionError> {
    if session.format_version != AppSession::VERSION {
        return Err(AppSessionError::UnsupportedVersion(session.format_version));
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(session)?;
    std::fs::write(path, json)?;
    Ok(())
}

pub fn load_session_json(path: &Path) -> Result<AppSession, AppSessionError> {
    let text = std::fs::read_to_string(path)?;
    let session: AppSession = serde_json::from_str(&text)?;
    if session.format_version != AppSession::VERSION {
        return Err(AppSessionError::UnsupportedVersion(session.format_version));
    }
    Ok(session)
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{Command, EditCommand};
    use pretty_assertions::assert_eq;
    use tempfile::tempdir;

    #[test]
    fn hot_exit_snapshot_roundtrip_restores_text_undo_and_views() {
        let mut ws = Workspace::new();
        let opened = ws
            .open_buffer(Some("file:///a.txt".to_string()), "a\r\nb\r\n", 80)
            .unwrap();

        // Make it dirty + create an undo step.
        ws.execute(
            opened.view_id,
            Command::Edit(EditCommand::InsertText {
                text: "X".to_string(),
            }),
        )
        .unwrap();
        assert!(ws.buffer_is_modified(opened.buffer_id).unwrap());

        // Create a second view to simulate a split pane.
        let view2 = ws.create_view(opened.buffer_id, 40).unwrap();
        ws.set_scroll_top(view2, 5).unwrap();

        let snap = HotExitSnapshot::capture(&mut ws).unwrap();
        let restored = snap.restore().unwrap();

        // Buffer text should match internal LF representation.
        let b0 = restored.buffer_id_for_uri("file:///a.txt").unwrap();
        assert_eq!(restored.buffer_text(b0).unwrap(), "Xa\nb\n");

        // Line ending preference should still be CRLF for saving.
        assert_eq!(
            restored.line_ending_for_buffer(b0).unwrap(),
            LineEnding::Crlf
        );

        // Undo should work after restore.
        let v0 = restored.active_view_id().unwrap();
        let mut restored = restored;
        restored
            .execute(v0, Command::Edit(EditCommand::Undo))
            .unwrap();
        assert_eq!(restored.buffer_text(b0).unwrap(), "a\nb\n");
    }

    #[test]
    fn hot_exit_restore_rejects_invalid_view_buffer_index_without_panicking() {
        let mut ws = Workspace::new();
        ws.open_buffer(Some("file:///a.txt".to_string()), "a\n", 80)
            .unwrap();

        let mut snap = HotExitSnapshot::capture(&mut ws).unwrap();
        snap.views[0].buffer_index = snap.buffers.len();

        let err = snap.restore().unwrap_err();
        assert!(
            matches!(err, AppSessionError::InvalidSnapshot(msg) if msg == "invalid buffer_index")
        );
    }

    #[test]
    fn hot_exit_restore_clamps_primary_selection_for_empty_selection_snapshot() {
        let mut ws = Workspace::new();
        ws.open_buffer(Some("file:///a.txt".to_string()), "a\n", 80)
            .unwrap();

        let mut snap = HotExitSnapshot::capture(&mut ws).unwrap();
        snap.views[0].selections.clear();
        snap.views[0].primary_selection_index = usize::MAX;

        let restored = snap.restore().unwrap();
        let view_id = restored.active_view_id().unwrap();
        let cursor = restored.cursor_state_for_view(view_id).unwrap();
        assert_eq!(cursor.selections.len(), 1);
        assert_eq!(cursor.primary_selection_index, 0);
    }

    #[test]
    fn session_json_roundtrip() {
        let temp = tempdir().unwrap();
        let path = temp.path().join("session.json");

        let mut s = AppSession::new();
        s.set_workspace_root(Some(Path::new("/tmp/proj")));
        s.push_recent_file(Path::new("/tmp/proj/a.txt"));
        s.push_recent_folder(Path::new("/tmp/proj"));

        save_session_json(&path, &s).unwrap();
        let loaded = load_session_json(&path).unwrap();

        assert_eq!(loaded.workspace_root, Some("/tmp/proj".to_string()));
        assert_eq!(loaded.recent_files, vec!["/tmp/proj/a.txt".to_string()]);
        assert_eq!(loaded.recent_folders, vec!["/tmp/proj".to_string()]);
    }
}
