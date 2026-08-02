use super::super::super::text_run_buffer::*;
use super::super::super::*;
use super::super::RenderTextCell;

#[allow(clippy::too_many_arguments)]
pub(super) fn append_cell_text_run<C: RenderTextCell>(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    pending: &mut Option<PendingRun>,
    cell: &C,
    x_cells: u32,
    fg: Rgba8,
    font_variant: FontVariant,
    text_origin_x: f32,
    baseline_y: f32,
    config: RenderConfig,
) {
    let ch = cell.ch();
    let eligible_for_ligatures = config.enable_ligatures && cell.width() == 1 && ch.is_ascii();
    if eligible_for_ligatures {
        append_ligature_text_run(
            renderer,
            canvas,
            pending,
            ch,
            x_cells,
            fg,
            font_variant,
            text_origin_x,
            baseline_y,
            config,
        );
    } else {
        append_glyph_text_run(
            renderer,
            canvas,
            pending,
            ch,
            x_cells,
            fg,
            font_variant,
            text_origin_x,
            baseline_y,
            config,
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn append_ligature_text_run(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    pending: &mut Option<PendingRun>,
    ch: char,
    x_cells: u32,
    fg: Rgba8,
    font_variant: FontVariant,
    text_origin_x: f32,
    baseline_y: f32,
    config: RenderConfig,
) {
    let font_index = renderer.font_index_for_char(ch, font_variant);
    let can_extend = pending.as_ref().is_some_and(|r| {
        r.font_variant == font_variant
            && r.font_index == font_index
            && r.fg == fg
            && matches!(r.kind, PendingRunKind::LigatureText { .. })
    });
    if !can_extend {
        flush_pending_run(renderer, canvas, pending, text_origin_x, baseline_y, config);
        *pending = Some(PendingRun {
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
}

#[allow(clippy::too_many_arguments)]
fn append_glyph_text_run(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    pending: &mut Option<PendingRun>,
    ch: char,
    x_cells: u32,
    fg: Rgba8,
    font_variant: FontVariant,
    text_origin_x: f32,
    baseline_y: f32,
    config: RenderConfig,
) {
    let font_index = renderer.font_index_for_char(ch, font_variant);
    let can_extend = pending.as_ref().is_some_and(|r| {
        r.font_variant == font_variant
            && r.font_index == font_index
            && r.fg == fg
            && matches!(r.kind, PendingRunKind::Glyphs { .. })
    });
    if !can_extend {
        flush_pending_run(renderer, canvas, pending, text_origin_x, baseline_y, config);
        *pending = Some(PendingRun {
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
        let rel_x_px = (x_cells.saturating_sub(r.start_x_cells) as f32) * config.cell_width_px;
        glyphs.push(glyph);
        positions.push(Point::new(rel_x_px, 0.0));
    }
}
