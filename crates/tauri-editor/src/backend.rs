use crate::composed_row_index::ComposedRowIndex;
use crate::render_model::{build_viewport_snapshot, RenderModelError};
use crate::snapshot::ViewportSnapshot;
use editor_core::intervals::{Interval, StyleId, StyleLayerId, IME_MARKED_TEXT_STYLE_ID};
use editor_core::ProcessingEdit;
use editor_core::{
    BufferId, Command, CursorCommand, EditCommand, Position, Selection, StyleCommand, ViewCommand,
    Workspace, WorkspaceError,
};
use editor_core_highlight_simple::{RegexHighlighter, RegexRule};
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
    #[error("IME composition 未开始")]
    CompositionNotActive,
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
    composition: Option<CompositionState>,
    highlighter: Option<RegexHighlighter>,
}

impl EditorBackend {
    fn buffer_id(&self) -> Result<BufferId, EditorBackendError> {
        self.workspace
            .buffer_id_for_view(self.view_id)
            .map_err(EditorBackendError::from)
    }

    fn refresh_syntax_highlighting(&mut self) -> Result<(), EditorBackendError> {
        let buffer_id = self.buffer_id()?;

        if let Some(highlighter) = self.highlighter.clone() {
            let intervals = self
                .workspace
                .with_editor_for_view(self.view_id, |ed| highlighter.highlight(&ed.line_index))?;
            self.workspace.apply_processing_edits(
                buffer_id,
                [ProcessingEdit::ReplaceStyleLayer {
                    layer: StyleLayerId::SIMPLE_SYNTAX,
                    intervals,
                }],
            )?;
            return Ok(());
        }

        self.workspace.apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::SIMPLE_SYNTAX,
            }],
        )?;
        Ok(())
    }

    /// 打开一段文本（用于测试或无文件模式）。
    pub fn open_text(
        uri: Option<String>,
        text: &str,
        viewport_width_cells: usize,
    ) -> Result<Self, EditorBackendError> {
        let highlighter = choose_highlighter(uri.as_deref());

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

        let mut backend = Self {
            workspace,
            view_id: open.view_id,
            composition: None,
            highlighter,
        };

        backend.refresh_syntax_highlighting()?;
        Ok(backend)
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
        let (total_rows, logical_line_count, fold_map) =
            self.workspace.with_editor_for_view(self.view_id, |editor| {
                let index = ComposedRowIndex::build(editor);
                let total_rows = index.total_rows();
                let logical_line_count = editor.line_index.line_count();

                let mut fold_map = std::collections::BTreeMap::<usize, (usize, bool)>::new();
                for region in editor.folding_manager.regions() {
                    fold_map
                        .entry(region.start_line)
                        .or_insert((region.end_line, region.is_collapsed));
                }

                (total_rows, logical_line_count, fold_map)
            })?;

        let grid = self
            .workspace
            .get_viewport_content_composed(self.view_id, start_row, count)?;

        let mut snapshot = build_viewport_snapshot(
            &grid,
            total_rows,
            logical_line_count,
            width_cells,
            tab_width,
        )?;

        // 仅在 logical line 的首个 visual 段上显示 fold toggle。
        for line in &mut snapshot.lines {
            if line.kind != crate::snapshot::LINE_KIND_DOCUMENT {
                continue;
            }
            if line.visual_in_logical != Some(0) {
                continue;
            }
            let Some(logical_line) = line.logical_line.map(|v| v as usize) else {
                continue;
            };
            let Some((end_line, collapsed)) = fold_map.get(&logical_line).copied() else {
                continue;
            };

            line.fold = Some(crate::snapshot::FoldSnapshot {
                end_line: end_line as u32,
                collapsed,
            });
        }

        Ok(snapshot)
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
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn insert_newline(&mut self, auto_indent: bool) -> Result<(), EditorBackendError> {
        self.workspace.execute(
            self.view_id,
            Command::Edit(EditCommand::InsertNewline { auto_indent }),
        )?;
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn insert_tab(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::InsertTab))?;
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn backspace(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Backspace))?;
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::DeleteForward))?;
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Undo))?;
        self.refresh_syntax_highlighting()?;
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), EditorBackendError> {
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::Redo))?;
        self.refresh_syntax_highlighting()?;
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

    pub fn toggle_fold(
        &mut self,
        start_line: usize,
        end_line: usize,
        collapsed: bool,
    ) -> Result<(), EditorBackendError> {
        if end_line <= start_line {
            return Ok(());
        }

        let cmd = if collapsed {
            Command::Style(StyleCommand::Unfold { start_line })
        } else {
            Command::Style(StyleCommand::Fold {
                start_line,
                end_line,
            })
        };

        self.workspace.execute(self.view_id, cmd)?;
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

    /// IME composition 开始：记录替换范围与原始文本，并隔离 undo group。
    pub fn composition_start(&mut self) -> Result<(), EditorBackendError> {
        let buffer_id = self.buffer_id()?;
        let line_index = self.workspace.buffer_line_index(buffer_id)?;

        let (start, len, original_selection) =
            if let Some(selection) = self.workspace.selection_for_view(self.view_id)? {
                let (start, end) = self.selection_char_range(&selection)?;
                (start, end.saturating_sub(start), (start, end))
            } else {
                let Position { line, column } =
                    self.workspace.cursor_position_for_view(self.view_id)?;
                let offset = line_index.position_to_char_offset(line, column);
                (offset, 0, (offset, offset))
            };

        let original_text = if len == 0 {
            String::new()
        } else {
            self.workspace.buffer_text_range(buffer_id, start, len)?
        };

        // 隔离 composition undo 分组：避免与普通输入/粘贴合并。
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::EndUndoGroup))?;

        // 清理上一次残留（防御式；正常情况不会有）。
        self.workspace.apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }],
        )?;

        self.composition = Some(CompositionState {
            start,
            len,
            original_text,
            original_selection,
        });
        Ok(())
    }

    /// IME composition 更新（preedit）：按 ReplaceCoalescingUndo 合并为单步 undo。
    pub fn composition_update(&mut self, text: String) -> Result<(), EditorBackendError> {
        let buffer_id = self.buffer_id()?;
        let Some((start, current_len)) = self.composition.as_ref().map(|s| (s.start, s.len)) else {
            return Err(EditorBackendError::CompositionNotActive);
        };

        let next_len = text.chars().count();
        let caret = start.saturating_add(next_len);

        self.workspace.execute(
            self.view_id,
            Command::Edit(EditCommand::ReplaceCoalescingUndoWithSelection {
                start,
                length: current_len,
                text,
                selection_start: caret,
                selection_end: caret,
            }),
        )?;

        if let Some(state) = self.composition.as_mut() {
            state.len = next_len;
        }

        if next_len == 0 {
            self.workspace.apply_processing_edits(
                buffer_id,
                [ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::IME_MARKED_TEXT,
                }],
            )?;
            return Ok(());
        }

        self.workspace.apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
                intervals: vec![Interval::new(
                    start,
                    start.saturating_add(next_len),
                    IME_MARKED_TEXT_STYLE_ID,
                )],
            }],
        )?;

        Ok(())
    }

    /// IME composition 结束（commit 或 cancel）。
    ///
    /// - `committed_text` 非空：提交该文本（替换当前 preedit）。
    /// - `committed_text` 为空：视为 cancel，恢复 composition 开始时的原始文本与 selection。
    pub fn composition_end(&mut self, committed_text: String) -> Result<(), EditorBackendError> {
        let Some(state) = self.composition.take() else {
            return Err(EditorBackendError::CompositionNotActive);
        };

        let buffer_id = self.buffer_id()?;
        let (replacement, selection_start, selection_end) = if committed_text.is_empty() {
            (
                state.original_text,
                state.original_selection.0,
                state.original_selection.1,
            )
        } else {
            let len = committed_text.chars().count();
            let caret = state.start.saturating_add(len);
            (committed_text, caret, caret)
        };

        self.workspace.execute(
            self.view_id,
            Command::Edit(EditCommand::ReplaceCoalescingUndoWithSelection {
                start: state.start,
                length: state.len,
                text: replacement,
                selection_start,
                selection_end,
            }),
        )?;

        // 清理 IME marked style layer。
        self.workspace.apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }],
        )?;

        // 结束 composition undo 分组，避免与后续普通输入合并。
        self.workspace
            .execute(self.view_id, Command::Edit(EditCommand::EndUndoGroup))?;

        self.refresh_syntax_highlighting()?;
        Ok(())
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

const MD_STYLE_HEADING: StyleId = 0x0200_0101;
const MD_STYLE_INLINE_CODE: StyleId = 0x0200_0102;
const MD_STYLE_LINK: StyleId = 0x0200_0103;

fn choose_highlighter(uri: Option<&str>) -> Option<RegexHighlighter> {
    let uri = uri?;
    let ext = Path::new(uri)
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.to_ascii_lowercase())?;

    match ext.as_str() {
        "json" => RegexHighlighter::json_default(Default::default()).ok(),
        "ini" => RegexHighlighter::ini_default(Default::default()).ok(),
        "md" | "markdown" => {
            let rules = vec![
                // Headings
                RegexRule::new(r#"^#{1,6} .*$"#, MD_STYLE_HEADING).ok()?,
                // Inline code
                RegexRule::new(r#"`[^`]+`"#, MD_STYLE_INLINE_CODE).ok()?,
                // Links: [text](url)
                RegexRule::new(r#"\[[^\]]+\]\([^\)]+\)"#, MD_STYLE_LINK).ok()?,
            ];
            Some(RegexHighlighter::new(rules))
        }
        _ => None,
    }
}

#[derive(Debug, Clone)]
struct CompositionState {
    start: usize,
    len: usize,
    original_text: String,
    original_selection: (usize, usize),
}
