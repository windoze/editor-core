use super::super::drawing::*;
use super::super::style::*;
use super::super::text_runs::*;
use super::super::*;

impl SkiaRenderer {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn draw_headless_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        row_range: Option<(usize, usize)>,
    ) -> Result<(), RenderError> {
        let mut bg_paint = Paint::default();
        bg_paint.set_anti_alias(false);
        bg_paint.set_color(rgba_to_skia_color(theme.background));
        canvas.draw_paint(&bg_paint);

        let gutter_x = config.padding_x_px;
        let gutter_w_px = config.gutter_width_cells as f32 * config.cell_width_px;
        let text_origin_x = gutter_x + gutter_w_px;

        if config.gutter_width_cells > 0 && gutter_w_px > 0.0 {
            let gutter_bg =
                resolve_style_background(GUTTER_BACKGROUND_STYLE_ID, theme, theme.background);
            let rect = Rect::from_xywh(gutter_x, 0.0, gutter_w_px, config.height_px as f32);
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(gutter_bg));
            canvas.draw_rect(rect, &paint);

            let sep = resolve_style_foreground(GUTTER_SEPARATOR_STYLE_ID, theme, theme.foreground);
            let sep_rect = Rect::from_xywh(text_origin_x, 0.0, 1.0, config.height_px as f32);
            let mut sep_paint = Paint::default();
            sep_paint.set_anti_alias(false);
            sep_paint.set_color(rgba_to_skia_color(sep));
            canvas.draw_rect(sep_rect, &sep_paint);
        }

        let total_rows = grid.lines.len();
        let (row_start, row_end) = row_range.unwrap_or((0, total_rows));
        let row_start = row_start.min(total_rows);
        let row_end = row_end.min(total_rows);

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        //
        // Selection is an overlay and must win over style backgrounds, so we draw it in a
        // separate pass *after* this.
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let mut x_cells = line.segment_x_start_cells as u32;
            for cell in &line.cells {
                let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                if bg != theme.background {
                    let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                    let w_px = cell.width as f32 * config.cell_width_px;
                    let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                    let mut bg_paint = Paint::default();
                    bg_paint.set_anti_alias(false);
                    bg_paint.set_color(rgba_to_skia_color(bg));
                    canvas.draw_rect(rect, &bg_paint);
                }
                x_cells = x_cells.saturating_add(cell.width as u32);
            }
        }

        // 2) Selection overlay (under text, over backgrounds).
        for sel in selections.iter().filter(|sel| {
            if row_range.is_none() {
                return true;
            }
            let min_row = sel.start_row.min(sel.end_row) as usize;
            let max_row = sel.start_row.max(sel.end_row) as usize;
            min_row < row_end && max_row >= row_start
        }) {
            draw_selection(
                canvas,
                grid,
                *sel,
                text_origin_x,
                config,
                theme.selection_background,
            );
        }

        // Text.
        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // Text + underlines.
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            if config.gutter_width_cells > 0 && line.visual_in_logical == 0 {
                let marker_state =
                    fold_marker_state_for_line(line.logical_line_index as u32, fold_markers);
                if let Some(is_collapsed) = marker_state {
                    let style_id = if is_collapsed {
                        FOLD_MARKER_COLLAPSED_STYLE_ID
                    } else {
                        FOLD_MARKER_EXPANDED_STYLE_ID
                    };
                    let marker_cells = fold_marker_column_cells(&config);
                    let rect = Rect::from_xywh(
                        gutter_x,
                        y_top,
                        config.cell_width_px * marker_cells as f32,
                        config.line_height_px,
                    );
                    draw_fold_marker(
                        canvas,
                        rect,
                        is_collapsed,
                        config.fold_marker_style,
                        theme,
                        style_id,
                    );
                }

                // Line number text (best-effort; tests should not depend on glyph rasterization).
                let gutter_fg =
                    resolve_style_foreground(GUTTER_FOREGROUND_STYLE_ID, theme, theme.foreground);
                let mut paint = Paint::default();
                paint.set_anti_alias(false);
                paint.set_color(rgba_to_skia_color(gutter_fg));

                let line_no = (line.logical_line_index + 1).to_string();
                let marker_cells = fold_marker_column_cells(&config);
                let x_px = gutter_x + config.cell_width_px * marker_cells as f32; // leave cells for fold marker
                canvas.draw_str(
                    line_no,
                    Point::new(x_px, baseline_y),
                    self.normal_primary_font(),
                    &paint,
                );
            }

            // Indent guides + whitespace markers are drawn after selection but before text.
            if config.show_indent_guides
                || config.whitespace_render_mode != WhitespaceRenderMode::None
            {
                let row_abs = grid.start_visual_row as i64 + row_idx as i64;
                let line_total_cells: i64 = line.cells.iter().map(|c| c.width as i64).sum::<i64>()
                    + line.segment_x_start_cells as i64;

                if config.show_indent_guides {
                    let mut indent_cells: u32 = line.segment_x_start_cells as u32;
                    for cell in &line.cells {
                        if cell.ch == ' ' || cell.ch == '\t' {
                            indent_cells = indent_cells.saturating_add(cell.width as u32);
                        } else {
                            break;
                        }
                    }

                    let tab_w = config.tab_width_cells.max(1);
                    let levels = indent_cells / tab_w;
                    if levels > 0 {
                        let guide_color = resolve_style_foreground_or_background(
                            INDENT_GUIDE_STYLE_ID,
                            theme,
                            default_indent_guide_color(theme),
                        );
                        let mut paint = Paint::default();
                        paint.set_anti_alias(false);
                        paint.set_color(rgba_to_skia_color(guide_color));

                        for level in 1..=levels {
                            // Place the guide on the boundary *between* indentation levels,
                            // i.e. right after a tabstop width.
                            let boundary_cells = level.saturating_mul(tab_w);
                            let x_px = (text_origin_x
                                + boundary_cells as f32 * config.cell_width_px)
                                .round();
                            let rect = Rect::from_xywh(x_px, y_top, 1.0, config.line_height_px);
                            canvas.draw_rect(rect, &paint);
                        }
                    }
                }

                let whitespace_mode = config.whitespace_render_mode;
                let draw_whitespace = match whitespace_mode {
                    WhitespaceRenderMode::None => false,
                    WhitespaceRenderMode::Selection => !selections.is_empty(),
                    WhitespaceRenderMode::All => true,
                };
                if draw_whitespace {
                    let marker_color = resolve_style_foreground_or_background(
                        WHITESPACE_STYLE_ID,
                        theme,
                        default_whitespace_marker_color(theme),
                    );

                    let mut dot_paint = Paint::default();
                    dot_paint.set_anti_alias(true);
                    dot_paint.set_color(rgba_to_skia_color(marker_color));

                    let mut stroke_paint = Paint::default();
                    stroke_paint.set_anti_alias(true);
                    stroke_paint.set_color(rgba_to_skia_color(marker_color));
                    stroke_paint.set_style(skia_safe::paint::Style::Stroke);
                    stroke_paint.set_stroke_width(1.0);

                    let mut x_cells = line.segment_x_start_cells as u32;
                    for cell in &line.cells {
                        let w_cells = cell.width as u32;
                        let cell_start = x_cells as i64;
                        let cell_end = x_cells.saturating_add(w_cells) as i64;

                        let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
                        let selected = match whitespace_mode {
                            WhitespaceRenderMode::None => false,
                            WhitespaceRenderMode::Selection => {
                                is_whitespace
                                    && cell_overlaps_selection_for_row(
                                        row_abs,
                                        cell_start,
                                        cell_end,
                                        line_total_cells,
                                        selections,
                                    )
                            }
                            WhitespaceRenderMode::All => is_whitespace,
                        };

                        if selected {
                            let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                            let w_px = w_cells as f32 * config.cell_width_px;
                            let cy = y_top + config.line_height_px * 0.5;

                            if cell.ch == ' ' {
                                let cx = x_px + w_px * 0.5;
                                let r = (config.cell_width_px.min(config.line_height_px) * 0.10)
                                    .max(1.0);
                                canvas.draw_circle(Point::new(cx, cy), r, &dot_paint);
                            } else if cell.ch == '\t' {
                                let pad = (config.cell_width_px * 0.15).min(w_px * 0.25);
                                let x0 = x_px + pad;
                                let x1 = (x_px + w_px - pad).max(x0 + 1.0);
                                let head = (config.cell_width_px.min(config.line_height_px) * 0.20)
                                    .max(2.0);
                                let shaft_end = (x1 - head).max(x0);

                                canvas.draw_line(
                                    Point::new(x0, cy),
                                    Point::new(shaft_end, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(shaft_end, cy),
                                    Point::new(x1, cy),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy - head * 0.6),
                                    &stroke_paint,
                                );
                                canvas.draw_line(
                                    Point::new(x1, cy),
                                    Point::new(x1 - head, cy + head * 0.6),
                                    &stroke_paint,
                                );
                            }
                        }

                        x_cells = x_cells.saturating_add(w_cells);
                    }
                }
            }

            draw_text_runs_for_cells(
                self,
                canvas,
                line.cells.as_slice(),
                line.segment_x_start_cells as u32,
                text_origin_x,
                y_top,
                baseline_y,
                config,
                theme,
            );
        }

        // Carets on top.
        if config.show_caret {
            for caret in carets.iter().filter(|caret| {
                if row_range.is_none() {
                    return true;
                }
                let r = caret.row as usize;
                r >= row_start && r < row_end
            }) {
                draw_caret(canvas, grid, *caret, text_origin_x, config, theme.caret);
            }
        }

        Ok(())
    }
}
