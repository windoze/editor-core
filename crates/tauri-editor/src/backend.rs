use crate::composed_row_index::ComposedRowIndex;
use crate::render_model::{RenderModelError, build_viewport_snapshot};
use crate::snapshot::ViewportSnapshot;
use editor_core::{
    BufferId, Command, CursorCommand, EditCommand, Position, Selection, ViewCommand, Workspace,
    WorkspaceError,
};
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
    #[error("无法把 composed row 映射到 doc row（可能点在 above-line 虚拟行上）")]
    ComposedRowNotMappable,
    #[error("无法把 visual(row,x_cells) 映射到逻辑位置（row={row}, x_cells={x_cells}）")]
    VisualPositionNotMappable { row: usize, x_cells: usize },
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
    fn buffer_id(&self) -> Result<BufferId, EditorBackendError> {
        self.workspace
            .buffer_id_for_view(self.view_id)
            .map_err(EditorBackendError::from)
    }

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

    fn move_cursor_to(
        &mut self,
        new_pos: Position,
        selecting: bool,
    ) -> Result<(), EditorBackendError> {
        let old_pos = self.workspace.cursor_position_for_view(self.view_id)?;

        if selecting {
            if self.workspace.selection_for_view(self.view_id)?.is_some() {
                self.workspace.execute(
                    self.view_id,
                    Command::Cursor(CursorCommand::ExtendSelection { to: new_pos }),
                )?;
            } else {
                self.workspace.execute(
                    self.view_id,
                    Command::Cursor(CursorCommand::SetSelection {
                        start: old_pos,
                        end: new_pos,
                    }),
                )?;
            }
        } else if self.workspace.selection_for_view(self.view_id)?.is_some() {
            self.workspace
                .execute(self.view_id, Command::Cursor(CursorCommand::ClearSelection))?;
        }

        self.workspace.execute(
            self.view_id,
            Command::Cursor(CursorCommand::MoveTo {
                line: new_pos.line,
                column: new_pos.column,
            }),
        )?;
        Ok(())
    }

    fn move_by_command(
        &mut self,
        cmd: CursorCommand,
        selecting: bool,
    ) -> Result<(), EditorBackendError> {
        let old_pos = self.workspace.cursor_position_for_view(self.view_id)?;

        if !selecting {
            if self.workspace.selection_for_view(self.view_id)?.is_some() {
                self.workspace
                    .execute(self.view_id, Command::Cursor(CursorCommand::ClearSelection))?;
            }
            self.workspace.execute(
                self.view_id,
                Command::Cursor(CursorCommand::ClearSecondarySelections),
            )?;
            self.workspace.execute(self.view_id, Command::Cursor(cmd))?;
            return Ok(());
        }

        self.workspace.execute(
            self.view_id,
            Command::Cursor(CursorCommand::ClearSecondarySelections),
        )?;
        self.workspace.execute(self.view_id, Command::Cursor(cmd))?;
        let new_pos = self.workspace.cursor_position_for_view(self.view_id)?;

        if self.workspace.selection_for_view(self.view_id)?.is_some() {
            self.workspace.execute(
                self.view_id,
                Command::Cursor(CursorCommand::ExtendSelection { to: new_pos }),
            )?;
        } else {
            self.workspace.execute(
                self.view_id,
                Command::Cursor(CursorCommand::SetSelection {
                    start: old_pos,
                    end: new_pos,
                }),
            )?;
        }

        Ok(())
    }

    pub fn handle_key_down(
        &mut self,
        key: EditorKey,
        mods: KeyModifiers,
    ) -> Result<(), EditorBackendError> {
        let selecting = mods.shift;
        let cmd = match key {
            EditorKey::ArrowLeft => CursorCommand::MoveGraphemeLeft,
            EditorKey::ArrowRight => CursorCommand::MoveGraphemeRight,
            EditorKey::ArrowUp => CursorCommand::MoveVisualBy { delta_rows: -1 },
            EditorKey::ArrowDown => CursorCommand::MoveVisualBy { delta_rows: 1 },
            EditorKey::Home => CursorCommand::MoveToVisualLineStart,
            EditorKey::End => CursorCommand::MoveToVisualLineEnd,
            EditorKey::PageUp => CursorCommand::MoveVisualBy { delta_rows: -20 },
            EditorKey::PageDown => CursorCommand::MoveVisualBy { delta_rows: 20 },
        };

        self.move_by_command(cmd, selecting)
    }

    pub fn insert_text(&mut self, text: String) -> Result<(), EditorBackendError> {
        if text.is_empty() {
            return Ok(());
        }
        self.workspace.execute(
            self.view_id,
            Command::Edit(EditCommand::InsertText { text }),
        )?;
        Ok(())
    }

    pub fn insert_newline(&mut self, auto_indent: bool) -> Result<(), EditorBackendError> {
        self.workspace.execute(
            self.view_id,
            Command::Edit(EditCommand::InsertNewline { auto_indent }),
        )?;
        Ok(())
    }

    pub fn insert_tab(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::InsertTab))?;
        Ok(())
    }

    pub fn backspace(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Backspace))?;
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::DeleteForward))?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Undo))?;
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Redo))?;
        Ok(())
    }

    pub fn move_cursor_to_composed_row(
        &mut self,
        composed_row: usize,
        x_cells: usize,
        selecting: bool,
    ) -> Result<(), EditorBackendError> {
        let doc_row = self
            .workspace
            .with_editor_for_view(self.view_id, |ed| {
                let index = ComposedRowIndex::build(ed);
                index.composed_row_to_doc_row(composed_row)
            })?
            .ok_or(EditorBackendError::ComposedRowNotMappable)?;

        let Some(pos) =
            self.workspace
                .visual_position_to_logical_for_view(self.view_id, doc_row, x_cells)?
        else {
            return Err(EditorBackendError::VisualPositionNotMappable {
                row: doc_row,
                x_cells,
            });
        };

        self.move_cursor_to(pos, selecting)
    }

    pub fn select_all(&mut self) -> Result<(), EditorBackendError> {
        let buffer_id = self.buffer_id()?;
        let line_index = self.workspace.buffer_line_index(buffer_id)?;
        let last_line = line_index.line_count().saturating_sub(1);
        let last_col = line_index
            .get_line_text(last_line)
            .unwrap_or_default()
            .chars()
            .count();
        let start = Position::new(0, 0);
        let end = Position::new(last_line, last_col);

        self.workspace.execute(
            self.view_id,
            Command::Cursor(CursorCommand::SetSelection { start, end }),
        )?;
        self.workspace.execute(
            self.view_id,
            Command::Cursor(CursorCommand::MoveTo {
                line: end.line,
                column: end.column,
            }),
        )?;
        Ok(())
    }

    fn selection_char_range(
        &self,
        selection: &Selection,
    ) -> Result<(usize, usize), EditorBackendError> {
        let buffer_id = self.buffer_id()?;
        let index = self.workspace.buffer_line_index(buffer_id)?;

        let a = index.position_to_char_offset(selection.start.line, selection.start.column);
        let b = index.position_to_char_offset(selection.end.line, selection.end.column);
        Ok(if a <= b { (a, b) } else { (b, a) })
    }

    pub fn selection_text(&self) -> Result<String, EditorBackendError> {
        let Some(selection) = self.workspace.selection_for_view(self.view_id)? else {
            return Ok(String::new());
        };
        let (start, end) = self.selection_char_range(&selection)?;
        if start >= end {
            return Ok(String::new());
        }

        let buffer_id = self.buffer_id()?;
        Ok(self
            .workspace
            .buffer_text_range(buffer_id, start, end.saturating_sub(start))?)
    }

    pub fn cut_selection_text(&mut self) -> Result<String, EditorBackendError> {
        let text = self.selection_text()?;
        if text.is_empty() {
            return Ok(text);
        }
        self.backspace()?;
        Ok(text)
    }

    /// 当前 selection 的 overlay 坐标（composed rows 空间）。
    ///
    /// 返回值语义：
    /// - `None`：无 selection（caret only）
    /// - `Some(((start_row, start_x), (end_row, end_x)))`：按文档顺序排序后的 selection 边界
    pub fn selection_overlay(
        &mut self,
    ) -> Result<Option<((u32, u32), (u32, u32))>, EditorBackendError> {
        let Some(mut sel) = self.workspace.selection_for_view(self.view_id)? else {
            return Ok(None);
        };

        // 统一成文档顺序（start <= end），便于前端渲染矩形。
        if sel.start > sel.end {
            std::mem::swap(&mut sel.start, &mut sel.end);
        }

        let Some((start_doc_row, start_x)) = self.workspace.logical_to_visual_for_view(
            self.view_id,
            sel.start.line,
            sel.start.column,
        )?
        else {
            return Ok(None);
        };
        let Some((end_doc_row, end_x)) = self.workspace.logical_to_visual_for_view(
            self.view_id,
            sel.end.line,
            sel.end.column,
        )?
        else {
            return Ok(None);
        };

        let (start_row, end_row) = self.workspace.with_editor_for_view(self.view_id, |ed| {
            let index = ComposedRowIndex::build(ed);
            (
                index.doc_row_to_composed_row(ed, start_doc_row),
                index.doc_row_to_composed_row(ed, end_doc_row),
            )
        })?;

        Ok(Some((
            (start_row as u32, start_x as u32),
            (end_row as u32, end_x as u32),
        )))
    }
}
