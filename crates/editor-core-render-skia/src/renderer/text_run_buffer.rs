use super::drawing::rgba_to_skia_color;
use super::*;

#[derive(Debug)]
pub(super) enum PendingRunKind {
    LigatureText {
        text: String,
    },
    Glyphs {
        glyphs: Vec<GlyphId>,
        positions: Vec<Point>,
    },
}

#[derive(Debug)]
pub(super) struct PendingRun {
    pub(super) start_x_cells: u32,
    pub(super) font_variant: FontVariant,
    pub(super) font_index: usize,
    pub(super) fg: Rgba8,
    pub(super) kind: PendingRunKind,
}

#[allow(clippy::too_many_arguments)]
pub(super) fn flush_pending_run(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    pending: &mut Option<PendingRun>,
    text_origin_x: f32,
    baseline_y: f32,
    config: RenderConfig,
) {
    let Some(run) = pending.take() else {
        return;
    };
    let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;

    let mut paint = Paint::default();
    paint.set_anti_alias(true);
    paint.set_color(rgba_to_skia_color(run.fg));

    match run.kind {
        PendingRunKind::LigatureText { text } => {
            if text.is_empty() {
                return;
            }
            renderer.draw_shaped_run_cached(
                canvas,
                text.as_str(),
                run.font_variant,
                run.font_index,
                x_px,
                baseline_y,
                config.cell_width_px,
                &paint,
                config.enable_ligatures,
            );
        }
        PendingRunKind::Glyphs { glyphs, positions } => {
            if glyphs.is_empty() || glyphs.len() != positions.len() {
                return;
            }
            let font = renderer.font_for_variant_index(run.font_variant, run.font_index);
            canvas.draw_glyphs_at(
                glyphs.as_slice(),
                positions.as_slice(),
                Point::new(x_px, baseline_y),
                font,
                &paint,
            );
        }
    }
}
