use super::drawing::*;
use super::style::*;
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LineDecorationKind {
    UnderlineSingle,
    UnderlineDouble,
    UnderlineSquiggly,
    Strikethrough,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct LineDecorationRun {
    kind: LineDecorationKind,
    start_x_cells: u32,
    width_cells: u32,
    color: Rgba8,
}

pub(super) fn flush_decoration_run(
    out: &mut Vec<LineDecorationRun>,
    run: &mut Option<LineDecorationRun>,
) {
    if let Some(r) = run.take()
        && r.width_cells > 0
    {
        out.push(r);
    }
}

pub(super) fn extend_decoration_run(
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

#[derive(Debug, Clone, Copy, Default)]
pub(super) struct ResolvedCellLineDecorations {
    /// Underline-like decoration (single/double/squiggly) and its resolved color.
    pub(super) underline: Option<(LineDecorationKind, Rgba8)>,
    /// Strikethrough color (if enabled).
    pub(super) strikethrough: Option<Rgba8>,
}

pub(super) fn resolve_cell_line_decorations(
    style_ids: &[u32],
    theme: &RenderTheme,
    resolved_cell_fg: Rgba8,
) -> ResolvedCellLineDecorations {
    let diag_id = style_ids
        .iter()
        .copied()
        .find(|&id| is_lsp_diagnostics_style_id(id));

    // Underline candidate resolution:
    // - diagnostics > IME > document links > theme-defined underline on arbitrary style ids
    // - within the same priority bucket, later style ids win (to match color layering semantics)
    let mut best_underline: Option<(i32, usize, LineDecorationKind, Rgba8)> = None;

    let consider = |best: &mut Option<(i32, usize, LineDecorationKind, Rgba8)>,
                    priority: i32,
                    tie: usize,
                    kind: LineDecorationKind,
                    color: Rgba8| {
        let replace = match best {
            None => true,
            Some((p, t, _, _)) => priority > *p || (priority == *p && tie >= *t),
        };
        if replace {
            *best = Some((priority, tie, kind, color));
        }
    };

    if let Some(diag_id) = diag_id {
        let spec = theme
            .text_decorations
            .get(&diag_id)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec
            .underline_color
            .unwrap_or_else(|| resolve_underline_color(diag_id, theme, resolved_cell_fg));
        consider(&mut best_underline, 400, usize::MAX, kind, color);
    }

    if style_ids.contains(&IME_MARKED_TEXT_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&IME_MARKED_TEXT_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 300, usize::MAX, kind, color);
    }

    if style_ids.contains(&DOCUMENT_LINK_STYLE_ID) {
        let spec = theme
            .text_decorations
            .get(&DOCUMENT_LINK_STYLE_ID)
            .copied()
            .unwrap_or_default();
        let underline_style = spec.underline.unwrap_or(UnderlineStyle::Single);
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or_else(|| {
            resolve_underline_color(DOCUMENT_LINK_STYLE_ID, theme, resolved_cell_fg)
        });
        consider(&mut best_underline, 200, usize::MAX, kind, color);
    }

    for (idx, &id) in style_ids.iter().enumerate() {
        if id == IME_MARKED_TEXT_STYLE_ID || id == DOCUMENT_LINK_STYLE_ID || diag_id == Some(id) {
            continue;
        }
        let spec = theme.text_decorations.get(&id).copied().or_else(|| {
            semantic_token_base_style_id(id)
                .and_then(|base| theme.text_decorations.get(&base).copied())
        });
        let Some(spec) = spec else { continue };
        let Some(underline_style) = spec.underline else {
            continue;
        };
        let kind = match underline_style {
            UnderlineStyle::Single => LineDecorationKind::UnderlineSingle,
            UnderlineStyle::Double => LineDecorationKind::UnderlineDouble,
            UnderlineStyle::Squiggly => LineDecorationKind::UnderlineSquiggly,
        };
        let color = spec.underline_color.unwrap_or(resolved_cell_fg);
        consider(&mut best_underline, 100, idx, kind, color);
    }

    let underline = best_underline.map(|(_p, _t, kind, color)| (kind, color));

    // Strikethrough: "last wins" by style-id order (independent of underline priority).
    let mut strike_enabled: bool = false;
    let mut strike_color: Option<Rgba8> = None;
    for &id in style_ids {
        let spec = theme.text_decorations.get(&id).copied().or_else(|| {
            semantic_token_base_style_id(id)
                .and_then(|base| theme.text_decorations.get(&base).copied())
        });
        let Some(spec) = spec else { continue };
        if let Some(v) = spec.strikethrough {
            strike_enabled = v;
        }
        if let Some(c) = spec.strikethrough_color {
            strike_color = Some(c);
        }
    }

    ResolvedCellLineDecorations {
        underline,
        strikethrough: strike_enabled.then(|| strike_color.unwrap_or(resolved_cell_fg)),
    }
}

pub(super) fn decoration_thickness_px(config: RenderConfig) -> f32 {
    config.scale.clamp(1.0, 2.0)
}

pub(super) fn draw_decoration_run(
    canvas: &skia_safe::Canvas,
    run: LineDecorationRun,
    text_origin_x: f32,
    y_top: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
) {
    let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;
    let w_px = run.width_cells as f32 * config.cell_width_px;
    if w_px <= 0.0 {
        return;
    }

    match run.kind {
        LineDecorationKind::UnderlineSingle => {
            draw_single_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineDouble => {
            draw_double_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineSquiggly => {
            draw_squiggly_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::Strikethrough => {
            draw_strikethrough(
                canvas, x_px, y_top, w_px, baseline_y, metrics, config, run.color,
            );
        }
    }
}

pub(super) fn draw_single_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y = (y_top + config.line_height_px - h).max(y_top);
    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

pub(super) fn draw_double_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y1 = (y_top + config.line_height_px - h).max(y_top);
    let y2 = (y1 - h * 2.0).max(y_top);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let rect1 = Rect::from_xywh(x_px, y1, w_px, h);
    canvas.draw_rect(rect1, &paint);

    let rect2 = Rect::from_xywh(x_px, y2, w_px, h);
    canvas.draw_rect(rect2, &paint);
}

pub(super) fn draw_squiggly_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    // Deterministic, non-antialiased "zig-zag" made of small rectangles.
    //
    // This avoids diagonal AA differences across backends while still looking squiggly at typical
    // editor sizes.
    let h = decoration_thickness_px(config);
    let y_bottom = (y_top + config.line_height_px - h).max(y_top);
    let y_upper = (y_bottom - h).max(y_top);
    let seg_w = (h * 2.0).max(2.0);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let mut x = x_px;
    let x_end = x_px + w_px;
    let mut upper = false;
    while x < x_end {
        let w = (x_end - x).min(seg_w);
        let y = if upper { y_upper } else { y_bottom };
        let rect = Rect::from_xywh(x, y, w, h);
        canvas.draw_rect(rect, &paint);
        upper = !upper;
        x += seg_w;
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn draw_strikethrough(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
    color: Rgba8,
) {
    // Keep strikethrough thickness consistent with underline thickness for crisp, deterministic
    // rendering across fonts/backends.
    let h = decoration_thickness_px(config);

    let strike_pos = metrics.strikeout_position().unwrap_or_else(|| {
        // `x_height` is a positive distance from baseline up; convert to y-down.
        if metrics.x_height.is_finite() && metrics.x_height > 0.0 {
            -metrics.x_height * 0.5
        } else if metrics.ascent.is_finite() {
            metrics.ascent * 0.3
        } else {
            -config.line_height_px * 0.3
        }
    });

    let center_y = baseline_y + strike_pos;
    let mut y = center_y - h * 0.5;
    let max_y = (y_top + config.line_height_px - h).max(y_top);
    if !y.is_finite() {
        y = y_top + config.line_height_px * 0.5;
    }
    y = y.clamp(y_top, max_y).round().clamp(y_top, max_y);

    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}
