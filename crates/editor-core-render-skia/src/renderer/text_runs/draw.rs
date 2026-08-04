use super::super::decoration::*;
use super::super::style::*;
use super::super::text_run_buffer::*;
use super::super::*;
use super::RenderTextCell;

mod runs;

use runs::append_cell_text_run;

#[allow(clippy::too_many_arguments)]
pub(in crate::renderer) fn draw_text_runs_for_cells<C: RenderTextCell>(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    cells: &[C],
    start_x_cells: u32,
    text_origin_x: f32,
    y_top: f32,
    baseline_y: f32,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    let mut pending: Option<PendingRun> = None;
    let mut decoration_runs: Vec<LineDecorationRun> = Vec::new();
    let mut underline_run: Option<LineDecorationRun> = None;
    let mut strike_run: Option<LineDecorationRun> = None;

    let mut x_cells = start_x_cells;
    for cell in cells {
        let (fg, _bg) = resolve_cell_colors(cell.styles(), theme);
        let font_variant = resolve_cell_font_variant(cell.styles(), theme);
        let decos = resolve_cell_line_decorations(cell.styles(), theme, fg);

        if let Some((kind, color)) = decos.underline {
            extend_decoration_run(
                &mut decoration_runs,
                &mut underline_run,
                kind,
                x_cells,
                cell.width() as u32,
                color,
            );
        } else {
            flush_decoration_run(&mut decoration_runs, &mut underline_run);
        }

        if let Some(color) = decos.strikethrough {
            extend_decoration_run(
                &mut decoration_runs,
                &mut strike_run,
                LineDecorationKind::Strikethrough,
                x_cells,
                cell.width() as u32,
                color,
            );
        } else {
            flush_decoration_run(&mut decoration_runs, &mut strike_run);
        }

        append_cell_text_run(
            renderer,
            canvas,
            &mut pending,
            cell,
            x_cells,
            fg,
            font_variant,
            text_origin_x,
            baseline_y,
            config,
        );

        x_cells = x_cells.saturating_add(cell.width() as u32);
    }

    flush_pending_run(
        renderer,
        canvas,
        &mut pending,
        text_origin_x,
        baseline_y,
        config,
    );
    flush_decoration_run(&mut decoration_runs, &mut underline_run);
    flush_decoration_run(&mut decoration_runs, &mut strike_run);

    // Text decorations last (underline/strikethrough), so they stay visible over glyphs.
    let (_spacing, metrics) = { renderer.normal_primary_font().metrics() };
    for run in decoration_runs {
        draw_decoration_run(
            canvas,
            run,
            text_origin_x,
            y_top,
            baseline_y,
            metrics,
            config,
        );
    }
}
