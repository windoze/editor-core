use super::*;

pub(super) fn selection_segment_for_row(sel: &VisualSelection, row: u32) -> Option<(u32, u32)> {
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

fn normalize_sel(sel: &VisualSelection) -> (u32, u32, u32, u32) {
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
