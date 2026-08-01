use super::super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::renderer) enum LineDecorationKind {
    UnderlineSingle,
    UnderlineDouble,
    UnderlineSquiggly,
    Strikethrough,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::renderer) struct LineDecorationRun {
    pub(in crate::renderer) kind: LineDecorationKind,
    pub(in crate::renderer) start_x_cells: u32,
    pub(in crate::renderer) width_cells: u32,
    pub(in crate::renderer) color: Rgba8,
}

pub(in crate::renderer) fn flush_decoration_run(
    out: &mut Vec<LineDecorationRun>,
    run: &mut Option<LineDecorationRun>,
) {
    if let Some(r) = run.take()
        && r.width_cells > 0
    {
        out.push(r);
    }
}

pub(in crate::renderer) fn extend_decoration_run(
    out: &mut Vec<LineDecorationRun>,
    run: &mut Option<LineDecorationRun>,
    kind: LineDecorationKind,
    x_cells: u32,
    width_cells: u32,
    color: Rgba8,
) {
    if width_cells == 0 {
        return;
    }

    if let Some(r) = run.as_mut() {
        let is_contiguous = r.start_x_cells.saturating_add(r.width_cells) == x_cells;
        if is_contiguous && r.kind == kind && r.color == color {
            r.width_cells = r.width_cells.saturating_add(width_cells);
            return;
        }
        flush_decoration_run(out, run);
    }

    *run = Some(LineDecorationRun {
        kind,
        start_x_cells: x_cells,
        width_cells,
        color,
    });
}
