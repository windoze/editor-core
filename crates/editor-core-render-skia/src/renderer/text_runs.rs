use super::decoration::*;
use super::style::*;
use super::text_run_buffer::*;
use super::*;

pub(super) trait RenderTextCell {
    fn ch(&self) -> char;
    fn width(&self) -> usize;
    fn styles(&self) -> &[u32];
}

impl RenderTextCell for editor_core::snapshot::Cell {
    fn ch(&self) -> char {
        self.ch
    }

    fn width(&self) -> usize {
        self.width
    }

    fn styles(&self) -> &[u32] {
        self.styles.as_slice()
    }
}

impl RenderTextCell for ComposedCell {
    fn ch(&self) -> char {
        self.ch
    }

    fn width(&self) -> usize {
        self.width
    }

    fn styles(&self) -> &[u32] {
        self.styles.as_slice()
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn draw_text_runs_for_cells<C: RenderTextCell>(
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

        let ch = cell.ch();
        let eligible_for_ligatures = config.enable_ligatures && cell.width() == 1 && ch.is_ascii();
        if eligible_for_ligatures {
            let font_index = renderer.font_index_for_char(ch, font_variant);
            let can_extend = pending.as_ref().is_some_and(|r| {
                r.font_variant == font_variant
                    && r.font_index == font_index
                    && r.fg == fg
                    && matches!(r.kind, PendingRunKind::LigatureText { .. })
            });
            if !can_extend {
                flush_pending_run(
                    renderer,
                    canvas,
                    &mut pending,
                    text_origin_x,
                    baseline_y,
                    config,
                );
                pending = Some(PendingRun {
                    start_x_cells: x_cells,
                    font_variant,
                    font_index,
                    fg,
                    kind: PendingRunKind::LigatureText {
                        text: String::new(),
                    },
                });
            }

            if let Some(r) = pending.as_mut()
                && let PendingRunKind::LigatureText { text } = &mut r.kind
            {
                text.push(ch);
            }
        } else {
            let font_index = renderer.font_index_for_char(ch, font_variant);
            let can_extend = pending.as_ref().is_some_and(|r| {
                r.font_variant == font_variant
                    && r.font_index == font_index
                    && r.fg == fg
                    && matches!(r.kind, PendingRunKind::Glyphs { .. })
            });
            if !can_extend {
                flush_pending_run(
                    renderer,
                    canvas,
                    &mut pending,
                    text_origin_x,
                    baseline_y,
                    config,
                );
                pending = Some(PendingRun {
                    start_x_cells: x_cells,
                    font_variant,
                    font_index,
                    fg,
                    kind: PendingRunKind::Glyphs {
                        glyphs: Vec::new(),
                        positions: Vec::new(),
                    },
                });
            }

            if let Some(r) = pending.as_mut()
                && let PendingRunKind::Glyphs { glyphs, positions } = &mut r.kind
            {
                let font = renderer.font_for_variant_index(font_variant, font_index);
                let glyph = font.unichar_to_glyph(ch as u32 as i32);
                let rel_x_px =
                    (x_cells.saturating_sub(r.start_x_cells) as f32) * config.cell_width_px;
                glyphs.push(glyph);
                positions.push(Point::new(rel_x_px, 0.0));
            }
        }

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
