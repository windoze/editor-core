use crate::composed_row_index::ComposedRowIndex;
use crate::render_model::{RenderModelError, build_viewport_snapshot};
use crate::snapshot::ViewportSnapshot;
use editor_core::{Command, CursorCommand, Position, ViewCommand, Workspace, WorkspaceError};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, thiserror::Error)]
pub enum EditorBackendError {
    #[error("I/O 失败：{0}")]
    Io(#[from] std::io::Error),
    #[error("Workspace 错误：{0:?}")]
    Workspace(WorkspaceError),
    #[error("RenderModel 错误：{0}")]
    RenderModel(#[from] RenderModelError),
    #[error("无激活 view")]
    NoActiveView,
    #[error("光标无法映射到 visual 坐标（可能在折叠区域内）")]
    CursorNotMappable,
}

impl From<WorkspaceError> for EditorBackendError {
    fn from(value: WorkspaceError) -> Self {
        Self::Workspace(value)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct KeyModifiers {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub meta: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EditorKey {
    ArrowLeft,
    ArrowRight,
    ArrowUp,
    ArrowDown,
    Home,
    End,
    PageUp,
    PageDown,
}

/// 一个纯 Rust 的 editor 后端封装：
/// - 管理一个 `editor_core::Workspace` + 单一 active view（MVP）
/// - 提供 viewport snapshot 与基础光标移动
#[derive(Debug)]
pub struct EditorBackend {
    workspace: Workspace,
    view_id: editor_core::ViewId,
}

impl EditorBackend {
    /// 打开一段文本（用于测试或无文件模式）。
    pub fn open_text(
        uri: Option<String>,
        text: &str,
        viewport_width_cells: usize,
    ) -> Result<Self, EditorBackendError> {
        let mut workspace = Workspace::new();
        let open = workspace.open_buffer(uri, text, viewport_width_cells)?;

        workspace.execute(
            open.view_id,
            Command::View(ViewCommand::SetWrapMode {
                mode: editor_core::WrapMode::Char,
            }),
        )?;
        workspace.execute(
            open.view_id,
            Command::View(ViewCommand::SetWrapIndent {
                indent: editor_core::WrapIndent::SameAsLineIndent,
            }),
        )?;

        Ok(Self {
            workspace,
            view_id: open.view_id,
        })
    }

    /// 从磁盘打开一个文件并创建一个初始 view。
    pub fn open_file(path: &Path, viewport_width_cells: usize) -> Result<Self, EditorBackendError> {
        let text = std::fs::read_to_string(path)?;
        Self::open_text(
            Some(path.to_string_lossy().to_string()),
            &text,
            viewport_width_cells,
        )
    }

    pub fn view_id(&self) -> editor_core::ViewId {
        self.view_id
    }

    pub fn workspace(&self) -> &Workspace {
        &self.workspace
    }

    pub fn workspace_mut(&mut self) -> &mut Workspace {
        &mut self.workspace
    }

    pub fn set_viewport_width(&mut self, width_cells: usize) -> Result<(), EditorBackendError> {
        self.workspace.execute(
            self.view_id,
            Command::View(ViewCommand::SetViewportWidth {
                width: width_cells.max(1),
            }),
        )?;
        Ok(())
    }

    pub fn set_viewport_height(&mut self, height_rows: usize) -> Result<(), EditorBackendError> {
        self.workspace
            .set_viewport_height(self.view_id, height_rows.max(1))?;
        Ok(())
    }

    /// 获取一个 viewport 快照（按 composed rows 切片）。
    pub fn viewport_snapshot(
        &mut self,
        start_row: usize,
        count: usize,
    ) -> Result<ViewportSnapshot, EditorBackendError> {
        let width_cells = self.workspace.viewport_width_for_view(self.view_id)?;
        let tab_width = self.workspace.tab_width_for_view(self.view_id)?;

        // 计算 composed total_rows（用于 scrollHeight/spacerTop/spacerBottom）。
        // MVP：每次请求重建索引；后续再做增量缓存与失效策略。
        let index = self
            .workspace
            .with_editor_for_view(self.view_id, |editor| ComposedRowIndex::build(editor))?;
        let total_rows = index.total_rows();

        let grid = self
            .workspace
            .get_viewport_content_composed(self.view_id, start_row, count)?;

        Ok(build_viewport_snapshot(
            &grid,
            total_rows,
            width_cells,
            tab_width,
        )?)
    }

    /// 当前光标的 overlay 坐标（composed rows 空间）。
    pub fn cursor_overlay(&mut self) -> Result<(u32, u32), EditorBackendError> {
        let Position { line, column } = self.workspace.cursor_position_for_view(self.view_id)?;

        let Some((doc_row, x_cells)) =
            self.workspace
                .logical_to_visual_for_view(self.view_id, line, column)?
        else {
            return Err(EditorBackendError::CursorNotMappable);
        };

        let (composed_row, x_cells_u32) =
            self.workspace.with_editor_for_view(self.view_id, |ed| {
                let index = ComposedRowIndex::build(ed);
                (index.doc_row_to_composed_row(ed, doc_row), x_cells as u32)
            })?;

        Ok((composed_row as u32, x_cells_u32))
    }

    pub fn handle_key_down(
        &mut self,
        key: EditorKey,
        _mods: KeyModifiers,
    ) -> Result<(), EditorBackendError> {
        let cmd = match key {
            EditorKey::ArrowLeft => Command::Cursor(CursorCommand::MoveGraphemeLeft),
            EditorKey::ArrowRight => Command::Cursor(CursorCommand::MoveGraphemeRight),
            EditorKey::ArrowUp => Command::Cursor(CursorCommand::MoveVisualBy { delta_rows: -1 }),
            EditorKey::ArrowDown => Command::Cursor(CursorCommand::MoveVisualBy { delta_rows: 1 }),
            EditorKey::Home => Command::Cursor(CursorCommand::MoveToVisualLineStart),
            EditorKey::End => Command::Cursor(CursorCommand::MoveToVisualLineEnd),
            EditorKey::PageUp => Command::Cursor(CursorCommand::MoveVisualBy { delta_rows: -20 }),
            EditorKey::PageDown => Command::Cursor(CursorCommand::MoveVisualBy { delta_rows: 20 }),
        };

        self.workspace.execute(self.view_id, cmd)?;
        Ok(())
    }
}
