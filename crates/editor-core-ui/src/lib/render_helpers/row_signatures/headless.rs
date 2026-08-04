use super::selection::selection_segment_for_row;
use super::*;

pub(crate) fn headless_row_signatures(
    grid: &HeadlessGrid,
    row_count: usize,
    carets: &[VisualCaret],
    selections: &[VisualSelection],
    fold_markers: &[FoldMarker],
    config: RenderConfig,
) -> Vec<u64> {
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

        hash_headless_selections(&mut hasher, selections, row_idx);
        hash_headless_carets(&mut hasher, carets, row_idx, config);
        out.push(hasher.finish());
    }
    out
}

fn hash_headless_selections(
    hasher: &mut DefaultHasher,
    selections: &[VisualSelection],
    row_idx: usize,
) {
    let mut sel_segs: Vec<(u32, u32)> = Vec::new();
    for sel in selections {
        if let Some(seg) = selection_segment_for_row(sel, row_idx as u32) {
            sel_segs.push(seg);
        }
    }
    sel_segs.sort_unstable();
    for seg in sel_segs {
        seg.hash(hasher);
    }
}

fn hash_headless_carets(
    hasher: &mut DefaultHasher,
    carets: &[VisualCaret],
    row_idx: usize,
    config: RenderConfig,
) {
    if !config.show_caret {
        return;
    }

    let mut xs: Vec<u32> = carets
        .iter()
        .filter(|c| c.row as usize == row_idx)
        .map(|c| c.x_cells)
        .collect();
    xs.sort_unstable();
    for x in xs {
        x.hash(hasher);
    }
}
