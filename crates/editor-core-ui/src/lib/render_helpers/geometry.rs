pub(crate) fn is_logical_line_hidden(
    regions: &[editor_core::FoldRegion],
    logical_line: usize,
) -> bool {
    regions.iter().any(|region| {
        region.is_collapsed && logical_line > region.start_line && logical_line <= region.end_line
    })
}

pub(crate) fn composed_line_index_for_offset(
    grid: &editor_core::ComposedGrid,
    char_offset: usize,
) -> Option<usize> {
    for (idx, line) in grid.lines.iter().enumerate() {
        if !matches!(line.kind, editor_core::ComposedLineKind::Document { .. }) {
            continue;
        }

        let start = line.char_offset_start;
        let end = line.char_offset_end;

        if char_offset < start {
            break;
        }
        if char_offset > end {
            continue;
        }
        if char_offset < end {
            return Some(idx);
        }

        if let Some(next) = grid.lines.get(idx + 1)
            && matches!(next.kind, editor_core::ComposedLineKind::Document { .. })
            && next.char_offset_start == char_offset
        {
            continue;
        }
        return Some(idx);
    }
    None
}

pub(crate) fn indent_prefix_cell_count(line: &editor_core::ComposedLine) -> usize {
    let mut count = 0usize;
    for cell in &line.cells {
        match cell.source {
            editor_core::ComposedCellSource::Virtual { .. } => {
                if !cell.styles.is_empty() || !cell.ch.is_whitespace() {
                    break;
                }
                count = count.saturating_add(1);
            }
            editor_core::ComposedCellSource::Document { .. } => break,
        }
    }
    count
}

pub(crate) fn caret_x_cells_in_composed_line(
    line: &editor_core::ComposedLine,
    char_offset: usize,
) -> u32 {
    let indent_prefix = indent_prefix_cell_count(line);
    let mut x_cells: u32 = 0;
    for (idx, cell) in line.cells.iter().enumerate() {
        let anchor = match cell.source {
            editor_core::ComposedCellSource::Document { offset } => offset,
            editor_core::ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
        };

        if anchor < char_offset {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        if anchor > char_offset {
            break;
        }

        let is_indent_prefix = idx < indent_prefix;
        if is_indent_prefix {
            x_cells = x_cells.saturating_add(cell.width as u32);
            continue;
        }
        break;
    }
    x_cells
}

pub(crate) fn hit_test_composed_line_char_offset(
    line: &editor_core::ComposedLine,
    x_cells: usize,
) -> usize {
    let mut x = 0usize;
    for cell in &line.cells {
        let w = cell.width.max(1);
        if x_cells < x.saturating_add(w) {
            return match cell.source {
                editor_core::ComposedCellSource::Document { offset } => offset,
                editor_core::ComposedCellSource::Virtual { anchor_offset } => anchor_offset,
            };
        }
        x = x.saturating_add(w);
    }
    line.char_offset_end
}
