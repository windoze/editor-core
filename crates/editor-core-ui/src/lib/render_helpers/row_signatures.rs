use super::*;

pub(crate) fn headless_row_signatures(
    grid: &HeadlessGrid,
    row_count: usize,
    carets: &[VisualCaret],
    selections: &[VisualSelection],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
    pub(crate) fn fold_marker_state_for_line(
        logical_line: u32,
        fold_markers: &[FoldMarker],
    ) -> Option<bool> {
        fold_markers
            .iter()
            .find(|m| m.logical_line == logical_line)
            .map(|m| m.is_collapsed)
    }

    pub(crate) fn normalize_sel(sel: &VisualSelection) -> (u32, u32, u32, u32) {
        let a = (sel.start_row, sel.start_x_cells);
        let b = (sel.end_row, sel.end_x_cells);
        if a <= b {
            (
                sel.start_row,
                sel.start_x_cells,
                sel.end_row,
                sel.end_x_cells,
            )
        } else {
            (
                sel.end_row,
                sel.end_x_cells,
                sel.start_row,
                sel.start_x_cells,
            )
        }
    }

    pub(crate) fn selection_segment_for_row(sel: &VisualSelection, row: u32) -> Option<(u32, u32)> {
        let (sr, sx, er, ex) = normalize_sel(sel);
        if row < sr || row > er {
            return None;
        }
        if sr == er {
            return Some((sx.min(ex), sx.max(ex)));
        }
        if row == sr {
            return Some((sx, u32::MAX));
        }
        if row == er {
            return Some((0, ex));
        }
        Some((0, u32::MAX))
    }

    let mut out: Vec<u64> = Vec::with_capacity(row_count);
    for row_idx in 0..row_count {
        let mut hasher = DefaultHasher::new();

        if let Some(line) = grid.lines.get(row_idx) {
            line.logical_line_index.hash(&mut hasher);
            line.visual_in_logical.hash(&mut hasher);
            line.char_offset_start.hash(&mut hasher);
            line.char_offset_end.hash(&mut hasher);
            line.segment_x_start_cells.hash(&mut hasher);
            line.is_fold_placeholder_appended.hash(&mut hasher);

            for cell in &line.cells {
                (cell.ch as u32).hash(&mut hasher);
                cell.width.hash(&mut hasher);
                cell.styles.len().hash(&mut hasher);
                for style_id in &cell.styles {
                    style_id.hash(&mut hasher);
                }
            }

            if config.gutter_width_cells > 0 && line.visual_in_logical == 0 {
                let state =
                    fold_marker_state_for_line(line.logical_line_index as u32, fold_markers);
                state.hash(&mut hasher);
            }
        } else {
            0u8.hash(&mut hasher);
        }

        let mut sel_segs: Vec<(u32, u32)> = Vec::new();
        for sel in selections {
            if let Some(seg) = selection_segment_for_row(sel, row_idx as u32) {
                sel_segs.push(seg);
            }
        }
        sel_segs.sort_unstable();
        for seg in sel_segs {
            seg.hash(&mut hasher);
        }

        if config.show_caret {
            let mut xs: Vec<u32> = carets
                .iter()
                .filter(|c| c.row as usize == row_idx)
                .map(|c| c.x_cells)
                .collect();
            xs.sort_unstable();
            for x in xs {
                x.hash(&mut hasher);
            }
        }

        out.push(hasher.finish());
    }
    out
}

pub(crate) fn composed_row_signatures(
    grid: &ComposedGrid,
    row_count: usize,
    caret_offsets: &[usize],
    selection_ranges: &[(usize, usize)],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
    pub(crate) fn fold_marker_state_for_line(
        logical_line: u32,
        fold_markers: &[FoldMarker],
    ) -> Option<bool> {
        fold_markers
            .iter()
            .find(|m| m.logical_line == logical_line)
            .map(|m| m.is_collapsed)
    }

    let mut sel_ranges: Vec<(usize, usize)> = Vec::new();
    for (a, b) in selection_ranges {
        if *a == *b {
            continue;
        }
        if *a <= *b {
            sel_ranges.push((*a, *b));
        } else {
            sel_ranges.push((*b, *a));
        }
    }

    let mut carets: Vec<(usize, u32)> = Vec::new();
    if config.show_caret {
        for &caret_offset in caret_offsets {
            let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
                continue;
            };
            let line = &grid.lines[local_row];
            let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
            carets.push((local_row, x_cells));
        }
        carets.sort_unstable();
    }

    let mut out: Vec<u64> = Vec::with_capacity(row_count);
    for row_idx in 0..row_count {
        let mut hasher = DefaultHasher::new();

        if let Some(line) = grid.lines.get(row_idx) {
            match line.kind {
                ComposedLineKind::Document {
                    logical_line,
                    visual_in_logical,
                } => {
                    1u8.hash(&mut hasher);
                    logical_line.hash(&mut hasher);
                    visual_in_logical.hash(&mut hasher);
                    if config.gutter_width_cells > 0 && visual_in_logical == 0 {
                        let state = fold_marker_state_for_line(logical_line as u32, fold_markers);
                        state.hash(&mut hasher);
                    }
                }
                ComposedLineKind::VirtualAboveLine { logical_line } => {
                    2u8.hash(&mut hasher);
                    logical_line.hash(&mut hasher);
                }
            }

            line.char_offset_start.hash(&mut hasher);
            line.char_offset_end.hash(&mut hasher);

            for cell in &line.cells {
                (cell.ch as u32).hash(&mut hasher);
                cell.width.hash(&mut hasher);
                cell.styles.len().hash(&mut hasher);
                for style_id in &cell.styles {
                    style_id.hash(&mut hasher);
                }

                match cell.source {
                    ComposedCellSource::Document { offset } => {
                        1u8.hash(&mut hasher);
                        offset.hash(&mut hasher);
                        let selected = sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e);
                        selected.hash(&mut hasher);
                    }
                    ComposedCellSource::Virtual { anchor_offset } => {
                        2u8.hash(&mut hasher);
                        anchor_offset.hash(&mut hasher);
                    }
                }
            }
        } else {
            0u8.hash(&mut hasher);
        }

        if config.show_caret {
            for (r, x) in carets.iter().filter(|(r, _x)| *r == row_idx) {
                r.hash(&mut hasher);
                x.hash(&mut hasher);
            }
        }

        out.push(hasher.finish());
    }
    out
}
