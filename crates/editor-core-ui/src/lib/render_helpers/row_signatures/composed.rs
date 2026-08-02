use super::*;

pub(crate) fn composed_row_signatures(
    grid: &ComposedGrid,
    row_count: usize,
    caret_offsets: &[usize],
    selection_ranges: &[(usize, usize)],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
    let sel_ranges = normalized_selection_ranges(selection_ranges);
    let carets = composed_caret_cells(grid, caret_offsets, config);

    let mut out: Vec<u64> = Vec::with_capacity(row_count);
    for row_idx in 0..row_count {
        let mut hasher = DefaultHasher::new();

        if let Some(line) = grid.lines.get(row_idx) {
            hash_composed_line_header(&mut hasher, line, fold_markers, config);
            hash_composed_line_cells(&mut hasher, line, &sel_ranges);
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

fn normalized_selection_ranges(selection_ranges: &[(usize, usize)]) -> Vec<(usize, usize)> {
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
    sel_ranges
}

fn composed_caret_cells(
    grid: &ComposedGrid,
    caret_offsets: &[usize],
    config: RenderConfig,
) -> Vec<(usize, u32)> {
    let mut carets: Vec<(usize, u32)> = Vec::new();
    if !config.show_caret {
        return carets;
    }

    for &caret_offset in caret_offsets {
        let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
            continue;
        };
        let line = &grid.lines[local_row];
        let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
        carets.push((local_row, x_cells));
    }
    carets.sort_unstable();
    carets
}

fn hash_composed_line_header(
    hasher: &mut DefaultHasher,
    line: &editor_core::ComposedLine,
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) {
    match line.kind {
        ComposedLineKind::Document {
            logical_line,
            visual_in_logical,
        } => {
            1u8.hash(hasher);
            logical_line.hash(hasher);
            visual_in_logical.hash(hasher);
            if config.gutter_width_cells > 0 && visual_in_logical == 0 {
                let state = fold_marker_state_for_line(logical_line as u32, fold_markers);
                state.hash(hasher);
            }
        }
        ComposedLineKind::VirtualAboveLine { logical_line } => {
            2u8.hash(hasher);
            logical_line.hash(hasher);
        }
    }

    line.char_offset_start.hash(hasher);
    line.char_offset_end.hash(hasher);
}

fn hash_composed_line_cells(
    hasher: &mut DefaultHasher,
    line: &editor_core::ComposedLine,
    sel_ranges: &[(usize, usize)],
) {
    for cell in &line.cells {
        (cell.ch as u32).hash(hasher);
        cell.width.hash(hasher);
        cell.styles.len().hash(hasher);
        for style_id in &cell.styles {
            style_id.hash(hasher);
        }

        match cell.source {
            ComposedCellSource::Document { offset } => {
                1u8.hash(hasher);
                offset.hash(hasher);
                let selected = sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e);
                selected.hash(hasher);
            }
            ComposedCellSource::Virtual { anchor_offset } => {
                2u8.hash(hasher);
                anchor_offset.hash(hasher);
            }
        }
    }
}
