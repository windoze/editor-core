use super::super::geometry::*;
use super::super::*;

#[derive(Debug, Clone, Copy)]
pub(super) struct PendingCaret {
    pub(super) local_row: usize,
    pub(super) x_cells: u32,
}

pub(super) fn pending_carets_for_composed_grid(
    grid: &ComposedGrid,
    caret_offsets: &[usize],
) -> Vec<PendingCaret> {
    let mut pending_carets = Vec::new();
    for &caret_offset in caret_offsets {
        let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
            continue;
        };
        let line = &grid.lines[local_row];
        let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
        pending_carets.push(PendingCaret { local_row, x_cells });
    }
    pending_carets
}
