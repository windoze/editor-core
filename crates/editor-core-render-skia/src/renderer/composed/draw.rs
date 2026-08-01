use super::super::decoration::*;
use super::super::drawing::*;
use super::super::geometry::*;
use super::super::style::*;
use super::super::*;

impl SkiaRenderer {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn draw_composed_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
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

        // Resolve caret positions in the composed grid (visible subset only).
        #[derive(Debug, Clone, Copy)]
        struct PendingCaret {
            local_row: usize,
            x_cells: u32,
        }
        let mut pending_carets: Vec<PendingCaret> = Vec::new();
        for &caret_offset in caret_offsets {
            let Some(local_row) = composed_line_index_for_offset(grid, caret_offset) else {
                continue;
            };
            let line = &grid.lines[local_row];
            let x_cells = caret_x_cells_in_composed_line(line, caret_offset);
            pending_carets.push(PendingCaret { local_row, x_cells });
        }

        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let mut x_cells: u32 = 0;
            for cell in &line.cells {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                if bg != theme.background {
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
        //
        // Note: selection highlight is applied only to document cells. Virtual text is not
        // considered part of the selection.
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

        if !sel_ranges.is_empty() {
            for row_idx in row_start..row_end {
                let line = &grid.lines[row_idx];
                if !matches!(line.kind, ComposedLineKind::Document { .. }) {
                    continue;
                }
                let y_top = config.padding_y_px + row_idx as f32 * config.line_height_px
                    - config.scroll_y_px;
                let mut x_cells: u32 = 0;
                for cell in &line.cells {
                    let selected = match cell.source {
                        ComposedCellSource::Document { offset } => {
                            sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e)
                        }
                        _ => false,
                    };
                    if selected {
                        let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                        let w_px = cell.width as f32 * config.cell_width_px;
                        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                        let mut sel_paint = Paint::default();
                        sel_paint.set_anti_alias(false);
                        sel_paint.set_color(rgba_to_skia_color(theme.selection_background));
                        canvas.draw_rect(rect, &sel_paint);
                    }
                    x_cells = x_cells.saturating_add(cell.width as u32);
                }
            }
        }

        // 3) Text + underlines.
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            // Gutter: fold markers + line numbers for document lines (first visual segment only).
            if config.gutter_width_cells > 0
                && let ComposedLineKind::Document {
                    logical_line,
                    visual_in_logical,
                } = line.kind
                && visual_in_logical == 0
            {
                let marker_state = fold_marker_state_for_line(logical_line as u32, fold_markers);
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

                let line_no = (logical_line + 1).to_string();
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
                if config.show_indent_guides {
                    let mut indent_cells: u32 = 0;
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
                    WhitespaceRenderMode::Selection => !sel_ranges.is_empty(),
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

                    let mut marker_x_cells: u32 = 0;
                    for cell in &line.cells {
                        let w_cells = cell.width as u32;
                        let selected = match cell.source {
                            ComposedCellSource::Document { offset } => {
                                let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
                                match whitespace_mode {
                                    WhitespaceRenderMode::None => false,
                                    WhitespaceRenderMode::Selection => {
                                        is_whitespace
                                            && sel_ranges
                                                .iter()
                                                .any(|(s, e)| offset >= *s && offset < *e)
                                    }
                                    WhitespaceRenderMode::All => is_whitespace,
                                }
                            }
                            _ => false,
                        };

                        if selected {
                            let x_px = text_origin_x + marker_x_cells as f32 * config.cell_width_px;
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

                        marker_x_cells = marker_x_cells.saturating_add(w_cells);
                    }
                }
            }

            #[derive(Debug)]
            enum PendingRunKind {
                LigatureText {
                    text: String,
                },
                Glyphs {
                    glyphs: Vec<GlyphId>,
                    positions: Vec<Point>,
                },
            }

            #[derive(Debug)]
            struct PendingRun {
                start_x_cells: u32,
                font_variant: FontVariant,
                font_index: usize,
                fg: Rgba8,
                kind: PendingRunKind,
            }

            let mut pending: Option<PendingRun> = None;
            let mut decoration_runs: Vec<LineDecorationRun> = Vec::new();
            let mut underline_run: Option<LineDecorationRun> = None;
            let mut strike_run: Option<LineDecorationRun> = None;

            let mut x_cells: u32 = 0;

            let flush = |renderer: &mut SkiaRenderer, pending: &mut Option<PendingRun>| {
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
                        let font =
                            renderer.font_for_variant_index(run.font_variant, run.font_index);
                        canvas.draw_glyphs_at(
                            glyphs.as_slice(),
                            positions.as_slice(),
                            Point::new(x_px, baseline_y),
                            font,
                            &paint,
                        );
                    }
                }
            };

            for cell in &line.cells {
                let (fg, _bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
                let font_variant = resolve_cell_font_variant(cell.styles.as_slice(), theme);
                let decos = resolve_cell_line_decorations(cell.styles.as_slice(), theme, fg);

                if let Some((kind, color)) = decos.underline {
                    extend_decoration_run(
                        &mut decoration_runs,
                        &mut underline_run,
                        kind,
                        x_cells,
                        cell.width as u32,
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
                        cell.width as u32,
                        color,
                    );
                } else {
                    flush_decoration_run(&mut decoration_runs, &mut strike_run);
                }

                let eligible_for_ligatures =
                    config.enable_ligatures && cell.width == 1 && cell.ch.is_ascii();
                if eligible_for_ligatures {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);

                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::LigatureText { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
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
                        text.push(cell.ch);
                    }
                } else {
                    let font_index = self.font_index_for_char(cell.ch, font_variant);
                    let can_extend = pending.as_ref().is_some_and(|r| {
                        r.font_variant == font_variant
                            && r.font_index == font_index
                            && r.fg == fg
                            && matches!(r.kind, PendingRunKind::Glyphs { .. })
                    });
                    if !can_extend {
                        flush(self, &mut pending);
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
                        let font = self.font_for_variant_index(font_variant, font_index);
                        let glyph = font.unichar_to_glyph(cell.ch as u32 as i32);
                        let rel_x_px =
                            (x_cells.saturating_sub(r.start_x_cells) as f32) * config.cell_width_px;
                        glyphs.push(glyph);
                        positions.push(Point::new(rel_x_px, 0.0));
                    }
                }

                x_cells = x_cells.saturating_add(cell.width as u32);
            }

            flush(self, &mut pending);

            flush_decoration_run(&mut decoration_runs, &mut underline_run);
            flush_decoration_run(&mut decoration_runs, &mut strike_run);

            // Text decorations last (underline/strikethrough), so they stay visible over glyphs.
            let (_spacing, metrics) = { self.normal_primary_font().metrics() };
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

        // Carets on top.
        if config.show_caret {
            let caret_width = config.caret_width_px.max(1.0);
            for caret in pending_carets
                .into_iter()
                .filter(|c| c.local_row >= row_start && c.local_row < row_end)
            {
                let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
                let y_top = config.padding_y_px + caret.local_row as f32 * config.line_height_px
                    - config.scroll_y_px;

                let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

                let mut paint = Paint::default();
                paint.set_anti_alias(false);
                paint.set_color(rgba_to_skia_color(theme.caret));
                canvas.draw_rect(rect, &paint);
            }
        }

        Ok(())
    }
}
