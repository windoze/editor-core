use super::super::super::*;

pub(in crate::renderer) fn cell_overlaps_selection_for_row(
    row: i64,
    cell_start_x: i64,
    cell_end_x: i64,
    line_total_cells: i64,
    selections: &[VisualSelection],
) -> bool {
    for sel in selections {
        let (mut a_row, mut a_x) = (sel.start_row as i64, sel.start_x_cells as i64);
        let (mut b_row, mut b_x) = (sel.end_row as i64, sel.end_x_cells as i64);
        if (b_row, b_x) < (a_row, a_x) {
            std::mem::swap(&mut a_row, &mut b_row);
            std::mem::swap(&mut a_x, &mut b_x);
        }

        if row < a_row || row > b_row {
            continue;
        }

        let start_x = if row == a_row { a_x } else { 0 };
        let end_x = if row == b_row { b_x } else { line_total_cells };
        if end_x <= start_x {
            continue;
        }

        if cell_start_x < end_x && cell_end_x > start_x {
            return true;
        }
    }

    false
}
