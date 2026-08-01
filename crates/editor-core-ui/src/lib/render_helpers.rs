use super::*;

pub(crate) fn hash_render_theme(theme: &RenderTheme) -> u64 {
    pub(crate) fn hash_rgba8(hasher: &mut DefaultHasher, c: Rgba8) {
        c.r.hash(hasher);
        c.g.hash(hasher);
        c.b.hash(hasher);
        c.a.hash(hasher);
    }

    pub(crate) fn hash_opt_rgba8(hasher: &mut DefaultHasher, c: Option<Rgba8>) {
        match c {
            None => 0u8.hash(hasher),
            Some(v) => {
                1u8.hash(hasher);
                hash_rgba8(hasher, v);
            }
        }
    }

    pub(crate) fn hash_style_colors(hasher: &mut DefaultHasher, c: StyleColors) {
        hash_opt_rgba8(hasher, c.foreground);
        hash_opt_rgba8(hasher, c.background);
    }

    pub(crate) fn hash_style_font(hasher: &mut DefaultHasher, f: StyleFont) {
        f.bold.hash(hasher);
        f.italic.hash(hasher);
    }

    pub(crate) fn hash_text_decorations(hasher: &mut DefaultHasher, d: TextDecorations) {
        let underline_tag: u8 = match d.underline {
            None => 0,
            Some(UnderlineStyle::Single) => 1,
            Some(UnderlineStyle::Double) => 2,
            Some(UnderlineStyle::Squiggly) => 3,
        };
        underline_tag.hash(hasher);
        hash_opt_rgba8(hasher, d.underline_color);

        d.strikethrough.hash(hasher);
        hash_opt_rgba8(hasher, d.strikethrough_color);
    }

    let mut hasher = DefaultHasher::new();

    hash_rgba8(&mut hasher, theme.background);
    hash_rgba8(&mut hasher, theme.foreground);
    hash_rgba8(&mut hasher, theme.selection_background);
    hash_rgba8(&mut hasher, theme.caret);

    for (style_id, colors) in &theme.styles {
        style_id.hash(&mut hasher);
        hash_style_colors(&mut hasher, *colors);
    }
    for (style_id, font) in &theme.style_fonts {
        style_id.hash(&mut hasher);
        hash_style_font(&mut hasher, *font);
    }
    for (style_id, deco) in &theme.text_decorations {
        style_id.hash(&mut hasher);
        hash_text_decorations(&mut hasher, *deco);
    }

    hasher.finish()
}

pub(crate) fn damage_rect_for_row_range(
    start_row: usize,
    end_row: usize,
    config: RenderConfig,
) -> Option<DamageRect> {
    if start_row >= end_row {
        return None;
    }

    let y0 = config.padding_y_px + start_row as f32 * config.line_height_px - config.scroll_y_px;
    let y1 = config.padding_y_px + end_row as f32 * config.line_height_px - config.scroll_y_px;
    if !y0.is_finite() || !y1.is_finite() {
        return None;
    }

    let mut y0i = y0.floor() as i64;
    let mut y1i = y1.ceil() as i64;

    let h_total = config.height_px as i64;
    y0i = y0i.clamp(0, h_total);
    y1i = y1i.clamp(0, h_total);
    if y1i <= y0i {
        return None;
    }

    Some(DamageRect {
        x: 0,
        y: y0i as u32,
        width: config.width_px,
        height: (y1i - y0i) as u32,
    })
}

pub(crate) fn dirty_row_ranges(prev: &[u64], next: &[u64]) -> Vec<(usize, usize)> {
    if prev.len() != next.len() {
        if next.is_empty() {
            return Vec::new();
        }
        return vec![(0, next.len())];
    }

    let mut ranges: Vec<(usize, usize)> = Vec::new();
    let mut start: Option<usize> = None;

    for i in 0..next.len() {
        let dirty = prev[i] != next[i];
        match (dirty, start) {
            (true, None) => start = Some(i),
            (false, Some(s)) => {
                ranges.push((s, i));
                start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = start {
        ranges.push((s, next.len()));
    }
    ranges
}

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
            // Beyond `actual_line_count`: background only.
            0u8.hash(&mut hasher);
        }

        // Selection overlay affects selection background and whitespace markers (Selection mode).
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

        // Carets are drawn on top only when enabled.
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
