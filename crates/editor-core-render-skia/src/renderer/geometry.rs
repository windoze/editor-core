use super::*;

pub(super) fn composed_line_index_for_offset(
    grid: &ComposedGrid,
    char_offset: usize,
) -> Option<usize> {
    for (idx, line) in grid.lines.iter().enumerate() {
        if !matches!(line.kind, ComposedLineKind::Document { .. }) {
            continue;
        }

        let start = line.char_offset_start;
        let end = line.char_offset_end;

        if char_offset < start {
            // Monotonic by construction; safe early break.
            break;
        }
        if char_offset > end {
            continue;
        }
        if char_offset < end {
            return Some(idx);
        }
        // char_offset == end
        //
        // Prefer the next document line if it starts at the same offset (wrap boundary).
        if let Some(next) = grid.lines.get(idx + 1)
            && matches!(next.kind, ComposedLineKind::Document { .. })
            && next.char_offset_start == char_offset
        {
            continue;
        }
        return Some(idx);
    }
    None
}

pub(super) fn indent_prefix_cell_count(line: &ComposedLine) -> usize {
    let mut count = 0usize;
    for cell in &line.cells {
        match cell.source {
            ComposedCellSource::Virtual { .. } => {
                if !cell.styles.is_empty() || !cell.ch.is_whitespace() {
                    break;
                }
                count = count.saturating_add(1);
            }
            ComposedCellSource::Document { .. } => break,
        }
    }
    count
}

pub(super) fn caret_x_cells_in_composed_line(line: &ComposedLine, char_offset: usize) -> u32 {
    let indent_prefix = indent_prefix_cell_count(line);
    let mut x_cells: u32 = 0;
    for (idx, cell) in line.cells.iter().enumerate() {
        let anchor = match cell.source {
            ComposedCellSource::Document { offset } => offset,
            ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
        };

        if anchor < char_offset {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        if anchor > char_offset {
            break;
        }

        // anchor == char_offset
        //
        // Wrap-indent virtual spaces should appear *before* the caret at the segment start.
        let is_indent_prefix = idx < indent_prefix;
        if is_indent_prefix {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        break;
    }
    x_cells
}
