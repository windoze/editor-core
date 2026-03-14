use editor_core::{DecorationPlacement, EditorCore, FoldRegion};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
struct LogicalLineSpan {
    logical_line: usize,
    above_count: usize,
    doc_visual_count: usize,
    doc_row_start: usize,
    composed_row_start: usize,
    composed_row_end: usize,
}

/// 一个按 view 当前状态（wrap/fold/decoration）计算出的 composed-row 索引。
///
/// composed rows = doc visual rows + `DecorationPlacement::AboveLine` 虚拟行。
///
/// 说明：
/// - `editor-core` 的 `visual_*` API 以 **doc visual rows** 为坐标空间；
/// - `ComposedGrid` 的 `start_visual_row/count` 以 **composed rows** 为坐标空间；
/// - UI（滚动高度/虚拟化）为了支持 code lens / view zones，需要统一使用 composed rows。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ComposedRowIndex {
    total_rows: usize,
    spans: Vec<LogicalLineSpan>,
    logical_line_to_span: Vec<Option<usize>>,
}

impl ComposedRowIndex {
    pub fn build(editor: &EditorCore) -> Self {
        let above_count_by_line = above_line_virtual_row_count_by_logical_line(editor);
        let regions = editor.folding_manager.regions();

        let logical_count = editor.layout_engine.logical_line_count();
        let mut spans = Vec::new();
        let mut logical_line_to_span = vec![None; logical_count];

        let mut doc_acc = 0usize;
        let mut composed_acc = 0usize;

        for logical_line in 0..logical_count {
            if is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            let above_count = above_count_by_line.get(&logical_line).copied().unwrap_or(0);
            let doc_visual_count = editor
                .layout_engine
                .get_line_layout(logical_line)
                .map(|l| l.visual_line_count)
                .unwrap_or(1);

            let composed_row_start = composed_acc;
            let doc_row_start = doc_acc;
            let composed_row_end = composed_row_start
                .saturating_add(above_count)
                .saturating_add(doc_visual_count);

            let span_idx = spans.len();
            spans.push(LogicalLineSpan {
                logical_line,
                above_count,
                doc_visual_count,
                doc_row_start,
                composed_row_start,
                composed_row_end,
            });
            logical_line_to_span[logical_line] = Some(span_idx);

            doc_acc = doc_acc.saturating_add(doc_visual_count);
            composed_acc = composed_row_end;
        }

        Self {
            total_rows: composed_acc,
            spans,
            logical_line_to_span,
        }
    }

    /// composed rows 总数。
    pub fn total_rows(&self) -> usize {
        self.total_rows
    }

    /// 把 doc visual row 映射到 composed row（用于 cursor overlay 等）。
    ///
    /// 如果映射失败，会回退为 `doc_row`（在“暂无 above-line 行”时这两者相等）。
    pub fn doc_row_to_composed_row(&self, editor: &EditorCore, doc_row: usize) -> usize {
        let (logical_line, visual_in_logical) = editor.visual_to_logical_line(doc_row);
        let Some(span_idx) = self.logical_line_to_span.get(logical_line).and_then(|v| *v) else {
            return doc_row;
        };

        let span = &self.spans[span_idx];
        span.composed_row_start
            .saturating_add(span.above_count)
            .saturating_add(visual_in_logical)
    }

    /// 把 composed row 映射回 doc visual row。
    ///
    /// - 返回 `Some(doc_row)`：该 composed row 对应可编辑的文档行段
    /// - 返回 `None`：该 composed row 位于 above-line 虚拟行区域（不应映射到文档 caret）
    pub fn composed_row_to_doc_row(&self, composed_row: usize) -> Option<usize> {
        let span_idx = self
            .spans
            .partition_point(|s| s.composed_row_end <= composed_row);
        let span = self.spans.get(span_idx)?;

        if composed_row < span.composed_row_start.saturating_add(span.above_count) {
            return None;
        }

        let doc_start_in_composed = span.composed_row_start.saturating_add(span.above_count);
        let in_line_doc_row = composed_row.saturating_sub(doc_start_in_composed);
        if in_line_doc_row >= span.doc_visual_count {
            return None;
        }

        Some(span.doc_row_start.saturating_add(in_line_doc_row))
    }
}

fn above_line_virtual_row_count_by_logical_line(editor: &EditorCore) -> BTreeMap<usize, usize> {
    let mut out: BTreeMap<usize, usize> = BTreeMap::new();

    for decorations in editor.decorations.values() {
        for deco in decorations {
            if deco.placement != DecorationPlacement::AboveLine {
                continue;
            }

            let Some(text) = deco.text.as_ref() else {
                continue;
            };
            if text.is_empty() {
                continue;
            }

            // `AboveLine` 的 anchor 语义：使用 range.start（见 editor-core 的 composed snapshot 实现）。
            let anchor = deco.range.start;
            let (logical_line, _) = editor.line_index.char_offset_to_position(anchor);

            *out.entry(logical_line).or_insert(0) += 1;
        }
    }

    out
}

fn is_logical_line_hidden(regions: &[FoldRegion], logical_line: usize) -> bool {
    for region in regions {
        if !region.is_collapsed {
            continue;
        }
        if logical_line > region.start_line && logical_line <= region.end_line {
            return true;
        }
    }
    false
}
