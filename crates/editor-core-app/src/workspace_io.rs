use crate::{FileIoError, FileIoOptions, read_utf8_file, write_utf8_file_atomic};
use editor_core::LineEnding;
use editor_core::workspace::{BufferId, OpenBufferResult, Workspace};
use editor_core_lsp::{file_uri_to_path, path_to_file_uri};
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SaveAllResult {
    pub saved_buffers: Vec<BufferId>,
    pub skipped_unmodified: Vec<BufferId>,
    pub skipped_no_path: Vec<BufferId>,
}

#[derive(Debug, Error)]
pub enum WorkspaceIoError {
    #[error("file I/O error: {0}")]
    FileIo(#[from] FileIoError),
    #[error("workspace error: {0}")]
    Workspace(String),
    #[error("buffer has no file path/uri: buffer={0:?}")]
    BufferHasNoPath(BufferId),
    #[error("buffer uri is not a file:// uri: {0}")]
    UnsupportedUri(String),
    #[error("save failed: {0}")]
    SaveFailed(String),
}

impl From<editor_core::workspace::WorkspaceError> for WorkspaceIoError {
    fn from(err: editor_core::workspace::WorkspaceError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

/// Convenience helper for opening a file into an `editor_core::Workspace`.
pub fn open_file_into_workspace(
    ws: &mut Workspace,
    path: &Path,
    viewport_width_cells: usize,
) -> Result<OpenBufferResult, WorkspaceIoError> {
    let text = read_utf8_file(path)?;
    let uri = path_to_file_uri(path);
    Ok(ws.open_buffer(Some(uri), &text, viewport_width_cells)?)
}

/// A small I/O helper that wires filesystem reads/writes to `editor-core` workspace buffers.
#[derive(Debug, Clone, Copy, Default)]
pub struct WorkspaceIo {
    pub io_options: FileIoOptions,
}

impl WorkspaceIo {
    pub fn new(io_options: FileIoOptions) -> Self {
        Self { io_options }
    }

    pub fn buffer_file_path(
        ws: &Workspace,
        buffer_id: BufferId,
    ) -> Result<PathBuf, WorkspaceIoError> {
        let meta = ws.buffer_metadata(buffer_id).ok_or(
            editor_core::workspace::WorkspaceError::BufferNotFound(buffer_id),
        )?;
        let Some(uri) = meta.uri.as_deref() else {
            return Err(WorkspaceIoError::BufferHasNoPath(buffer_id));
        };
        file_uri_to_path(uri).ok_or_else(|| WorkspaceIoError::UnsupportedUri(uri.to_string()))
    }

    pub fn save_buffer(
        &self,
        ws: &mut Workspace,
        buffer_id: BufferId,
    ) -> Result<(), WorkspaceIoError> {
        let path = Self::buffer_file_path(ws, buffer_id)?;
        let text = ws.buffer_text_for_saving(buffer_id)?;
        write_utf8_file_atomic(&path, &text, self.io_options)?;
        ws.mark_saved_for_buffer(buffer_id)?;
        Ok(())
    }

    pub fn save_buffer_as(
        &self,
        ws: &mut Workspace,
        buffer_id: BufferId,
        new_path: &Path,
    ) -> Result<(), WorkspaceIoError> {
        let uri = path_to_file_uri(new_path);
        ws.set_buffer_uri(buffer_id, Some(uri))?;
        self.save_buffer(ws, buffer_id)?;
        Ok(())
    }

    pub fn save_all(&self, ws: &mut Workspace) -> Result<SaveAllResult, WorkspaceIoError> {
        let mut saved_buffers = Vec::new();
        let mut skipped_unmodified = Vec::new();
        let mut skipped_no_path = Vec::new();

        for buffer_id in ws.buffer_ids() {
            if !ws.buffer_is_modified(buffer_id)? {
                skipped_unmodified.push(buffer_id);
                continue;
            }

            let meta = ws.buffer_metadata(buffer_id).ok_or(
                editor_core::workspace::WorkspaceError::BufferNotFound(buffer_id),
            )?;
            if meta.uri.is_none() {
                skipped_no_path.push(buffer_id);
                continue;
            }

            self.save_buffer(ws, buffer_id)?;
            saved_buffers.push(buffer_id);
        }

        Ok(SaveAllResult {
            saved_buffers,
            skipped_unmodified,
            skipped_no_path,
        })
    }

    pub fn set_buffer_line_ending(
        &self,
        ws: &mut Workspace,
        buffer_id: BufferId,
        line_ending: LineEnding,
    ) -> Result<(), WorkspaceIoError> {
        ws.set_line_ending_for_buffer(buffer_id, line_ending)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{Command, EditCommand};
    use pretty_assertions::assert_eq;
    use tempfile::tempdir;

    #[test]
    fn open_and_save_preserves_crlf_by_default() {
        let temp = tempdir().unwrap();
        let path = temp.path().join("crlf.txt");
        std::fs::write(&path, "a\r\nb\r\n").unwrap();

        let mut ws = Workspace::new();
        let opened = open_file_into_workspace(&mut ws, &path, 80).unwrap();
        assert_eq!(ws.buffer_text(opened.buffer_id).unwrap(), "a\nb\n");
        assert_eq!(
            ws.line_ending_for_buffer(opened.buffer_id).unwrap(),
            LineEnding::Crlf
        );

        // Edit (so we can exercise mark_saved_for_buffer and is_modified).
        ws.execute(
            opened.view_id,
            Command::Edit(EditCommand::Insert {
                offset: 0,
                text: "X".to_string(),
            }),
        )
        .unwrap();
        assert!(ws.buffer_is_modified(opened.buffer_id).unwrap());

        let io = WorkspaceIo::default();
        io.save_buffer(&mut ws, opened.buffer_id).unwrap();
        assert!(!ws.buffer_is_modified(opened.buffer_id).unwrap());

        let saved = std::fs::read_to_string(&path).unwrap();
        assert_eq!(saved, "Xa\r\nb\r\n");
    }

    #[test]
    fn save_as_updates_uri_and_writes_new_path() {
        let temp = tempdir().unwrap();
        let path_a = temp.path().join("a.txt");
        std::fs::write(&path_a, "a\n").unwrap();

        let mut ws = Workspace::new();
        let opened = open_file_into_workspace(&mut ws, &path_a, 80).unwrap();

        let path_b = temp.path().join("b.txt");
        let io = WorkspaceIo::default();
        io.save_buffer_as(&mut ws, opened.buffer_id, &path_b)
            .unwrap();

        let saved = std::fs::read_to_string(&path_b).unwrap();
        assert_eq!(saved, "a\n");

        let meta = ws.buffer_metadata(opened.buffer_id).unwrap();
        assert!(meta.uri.as_deref().unwrap().starts_with("file://"));
        assert!(meta.uri.as_deref().unwrap().contains("b.txt"));
    }
}
