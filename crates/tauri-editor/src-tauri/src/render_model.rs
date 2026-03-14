use crate::snapshot::{
    LINE_KIND_DOCUMENT, LINE_KIND_VIRTUAL_ABOVE_LINE, LineSnapshot, RunSnapshot,
    SOURCE_KIND_DOCUMENT, SOURCE_KIND_VIRTUAL, ViewportSnapshot,
};
use editor_core::intervals::StyleId;
use editor_core::{ComposedCellSource, ComposedGrid, ComposedLineKind};
use std::collections::HashMap;

#[derive(Debug, thiserror::Error)]
pub enum RenderModelError {
    #[error("offset 超出 u32 范围（offset={offset}）")]
    OffsetTooLarge { offset: usize },
    #[error("logical_line 超出 u32 范围（logical_line={logical_line}）")]
    LogicalLineTooLarge { logical_line: usize },
    #[error("visual_in_logical 超出 u16 范围（visual_in_logical={visual_in_logical}）")]
    VisualInLogicalTooLarge { visual_in_logical: usize },
    #[error("cells count 超出 u32 范围（cells={cells}）")]
    CellsTooLarge { cells: usize },
    #[error("tab_width 超出 u16 范围（tab_width={tab_width}）")]
    TabWidthTooLarge { tab_width: usize },
    #[error("ComposedGrid.start_visual_row 超出 u32 范围（start_row={start_row}）")]
    StartRowTooLarge { start_row: usize },
    #[error("total_rows 超出 u32 范围（total_rows={total_rows}）")]
    TotalRowsTooLarge { total_rows: usize },
    #[error("logical_line_count 超出 u32 范围（logical_line_count={logical_line_count}）")]
    LogicalLineCountTooLarge { logical_line_count: usize },
    #[error("style-set 数量超出 u32 范围（len={len}）")]
    StyleSetTableTooLarge { len: usize },
    #[error("Run cells 超出 u16 范围（cells={cells}）")]
    RunCellsTooLarge { cells: usize },
}

#[derive(Debug, Default)]
struct StyleSetInterner {
    map: HashMap<Vec<StyleId>, u32>,
    sets: Vec<Vec<StyleId>>,
}

impl StyleSetInterner {
    fn new() -> Self {
        // 约定：0 号 style-set 为“无样式”（空数组）。
        let mut out = Self {
            map: HashMap::new(),
            sets: vec![Vec::new()],
        };
        out.map.insert(Vec::new(), 0);
        out
    }

    fn intern(&mut self, styles: &[StyleId]) -> Result<u32, RenderModelError> {
        if styles.is_empty() {
            return Ok(0);
        }

        let mut key: Vec<StyleId> = styles.to_vec();
        key.sort_unstable();
        key.dedup();

        if let Some(id) = self.map.get(&key) {
            return Ok(*id);
        }

        let id = u32::try_from(self.sets.len()).map_err(|_| {
            RenderModelError::StyleSetTableTooLarge {
                len: self.sets.len(),
            }
        })?;
        self.sets.push(key.clone());
        self.map.insert(key, id);
        Ok(id)
    }

    fn into_sets_u32(self) -> Vec<Vec<u32>> {
        self.sets
            .into_iter()
            .map(|set| set.into_iter().map(|id| id as u32).collect::<Vec<u32>>())
            .collect()
    }
}

/// 把 `editor_core::ComposedGrid` 压缩为 Web 友好的 `ViewportSnapshot`。
///
/// 注意：这里的 `total_rows` 必须是 **composed rows 总数**（doc rows + above-line 虚拟行）。
pub fn build_viewport_snapshot(
    grid: &ComposedGrid,
    total_rows: usize,
    logical_line_count: usize,
    width_cells: usize,
    tab_width: usize,
) -> Result<ViewportSnapshot, RenderModelError> {
    let start_row_u32 =
        u32::try_from(grid.start_visual_row).map_err(|_| RenderModelError::StartRowTooLarge {
            start_row: grid.start_visual_row,
        })?;
    let total_rows_u32 = u32::try_from(total_rows)
        .map_err(|_| RenderModelError::TotalRowsTooLarge { total_rows })?;
    let logical_line_count_u32 = u32::try_from(logical_line_count).map_err(|_| {
        RenderModelError::LogicalLineCountTooLarge {
            logical_line_count,
        }
    })?;
    let width_cells_u32 = u32::try_from(width_cells)
        .map_err(|_| RenderModelError::CellsTooLarge { cells: width_cells })?;
    let tab_width_u16 =
        u16::try_from(tab_width).map_err(|_| RenderModelError::TabWidthTooLarge { tab_width })?;

    let mut style_sets = StyleSetInterner::new();
    let mut lines = Vec::with_capacity(grid.lines.len());

    for (idx, line) in grid.lines.iter().enumerate() {
        let row = grid.start_visual_row.saturating_add(idx);
        let row_u32 = u32::try_from(row)
            .map_err(|_| RenderModelError::StartRowTooLarge { start_row: row })?;

        let (kind, logical_line, visual_in_logical) = match line.kind {
            ComposedLineKind::Document {
                logical_line,
                visual_in_logical,
            } => (
                LINE_KIND_DOCUMENT,
                Some(u32::try_from(logical_line).map_err(|_| {
                    RenderModelError::LogicalLineTooLarge { logical_line }
                })?),
                Some(u16::try_from(visual_in_logical).map_err(|_| {
                    RenderModelError::VisualInLogicalTooLarge { visual_in_logical }
                })?),
            ),
            ComposedLineKind::VirtualAboveLine { logical_line } => (
                LINE_KIND_VIRTUAL_ABOVE_LINE,
                Some(u32::try_from(logical_line).map_err(|_| {
                    RenderModelError::LogicalLineTooLarge { logical_line }
                })?),
                None,
            ),
        };

        #[derive(Debug)]
        struct RunBuild {
            style_set_id: u32,
            source_kind: u8,
            source_offset: u32,
            doc_char_len: u32,
            cells: usize,
            allow_merge_base_cells: bool,
            text: String,
        }

        let mut runs: Vec<RunSnapshot> = Vec::new();
        let mut current: Option<RunBuild> = None;

        let flush = |current: Option<RunBuild>, runs: &mut Vec<RunSnapshot>| {
            if let Some(run) = current {
                if !run.text.is_empty() {
                    let cells_u16 = u16::try_from(run.cells)
                        .map_err(|_| RenderModelError::RunCellsTooLarge { cells: run.cells })?;
                    runs.push(RunSnapshot::new(
                        run.style_set_id,
                        run.source_kind,
                        run.source_offset,
                        cells_u16,
                        run.text,
                    ));
                }
            }
            Ok::<(), RenderModelError>(())
        };

        for cell in &line.cells {
            let style_set_id = style_sets.intern(&cell.styles)?;

            let (source_kind, cell_source_offset) = match cell.source {
                ComposedCellSource::Document { offset } => {
                    let off_u32 = u32::try_from(offset)
                        .map_err(|_| RenderModelError::OffsetTooLarge { offset })?;
                    (SOURCE_KIND_DOCUMENT, off_u32)
                }
                ComposedCellSource::Virtual { anchor_offset } => {
                    let off_u32 = u32::try_from(anchor_offset).map_err(|_| {
                        RenderModelError::OffsetTooLarge {
                            offset: anchor_offset,
                        }
                    })?;
                    (SOURCE_KIND_VIRTUAL, off_u32)
                }
            };

            let cell_width_cells = cell.width;

            // 关键：为了保证 caret 与宽字符（例如 CJK=2 cells）的边界一致，
            // - 宽字符（width!=1，且 width>0）必须单独成段（不能与左右邻居合并），否则 caret 可能落进 glyph 中间。
            // - width==0（combining marks）必须跟随在其 base 字符之后，否则会破坏字形组合。
            let can_merge = if cell_width_cells == 0 {
                current.is_some()
            } else if let Some(ref run) = current {
                if !run.allow_merge_base_cells || cell_width_cells != 1 {
                    false
                } else if run.style_set_id != style_set_id || run.source_kind != source_kind {
                    false
                } else if source_kind == SOURCE_KIND_VIRTUAL {
                    run.source_offset == cell_source_offset
                } else {
                    // Document：要求 `char offset` 连续，便于 JS 侧 `source_offset + char_index` 映射。
                    run.source_offset
                        .saturating_add(run.doc_char_len)
                        .eq(&cell_source_offset)
                }
            } else {
                false
            };

            if !can_merge {
                flush(current.take(), &mut runs)?;
                current = Some(RunBuild {
                    style_set_id,
                    source_kind,
                    source_offset: cell_source_offset,
                    doc_char_len: 0,
                    cells: 0,
                    allow_merge_base_cells: cell_width_cells == 1,
                    text: String::new(),
                });
            }

            let run = current.as_mut().expect("run must exist");

            if cell.ch == '\t' && cell_width_cells > 0 {
                // 在 DOM text-grid 中，将 `\t` 展开为固定宽度的空格，避免不同 WebView 的 tab 渲染差异。
                run.text.extend(std::iter::repeat_n(' ', cell_width_cells));
            } else {
                run.text.push(cell.ch);
            }

            // width==0（combining marks）不占用 cells，但仍是一个 document char offset。
            run.cells = run.cells.saturating_add(cell_width_cells);
            if run.source_kind == SOURCE_KIND_DOCUMENT {
                run.doc_char_len = run.doc_char_len.saturating_add(1);
            }

            // 一旦遇到宽字符/Tab（width!=1 且 >0），该段必须锁死为“不可继续合并 base cells”。
            if cell_width_cells > 0 && cell_width_cells != 1 {
                run.allow_merge_base_cells = false;
            }
        }

        flush(current.take(), &mut runs)?;

        lines.push(LineSnapshot {
            row: row_u32,
            kind,
            logical_line,
            visual_in_logical,
            fold: None,
            runs,
        });
    }

    Ok(ViewportSnapshot {
        start_row: start_row_u32,
        total_rows: total_rows_u32,
        logical_line_count: logical_line_count_u32,
        width_cells: width_cells_u32,
        tab_width: tab_width_u16,
        lines,
        style_sets: style_sets.into_sets_u32(),
    })
}
