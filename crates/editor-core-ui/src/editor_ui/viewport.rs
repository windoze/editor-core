use super::*;

impl EditorUi {
    pub fn set_render_config(&mut self, config: RenderConfig) {
        self.render_config = config;
    }

    pub fn set_render_metrics(
        &mut self,
        font_size: f32,
        line_height_px: f32,
        cell_width_px: f32,
        padding_x_px: f32,
        padding_y_px: f32,
    ) {
        self.render_config.font_size = font_size;
        self.render_config.line_height_px = line_height_px;
        self.render_config.cell_width_px = cell_width_px;
        self.render_config.padding_x_px = padding_x_px;
        self.render_config.padding_y_px = padding_y_px;
    }

    pub fn set_text_vertical_align(&mut self, align: TextVerticalAlign) {
        self.render_config.text_vertical_align = align;
    }

    /// Configure font fallback list for rendering (comma-separated family names).
    ///
    /// This mirrors how VS Code allows configuring `editor.fontFamily` as a list.
    ///
    /// Notes:
    /// - This does not affect layout metrics; the editor remains monospace-grid based.
    /// - The renderer will pick the first font that contains a glyph for each character.
    pub fn set_font_families_csv(&mut self, families_csv: &str) {
        let families: Vec<String> = families_csv
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();
        self.renderer.set_font_families(families);
    }

    /// Enable/disable font ligatures in the renderer (visual-only).
    pub fn set_font_ligatures_enabled(&mut self, enabled: bool) {
        self.render_config.enable_ligatures = enabled;
    }

    /// Set caret width in pixels (minimum 1px when visible).
    pub fn set_caret_width_px(&mut self, width_px: f32) {
        if width_px.is_finite() {
            self.render_config.caret_width_px = width_px.max(0.0);
        }
    }

    /// Show/hide carets during rendering (useful for UI-side blinking or focus handling).
    pub fn set_caret_visible(&mut self, visible: bool) {
        self.render_config.show_caret = visible;
    }

    /// Override the ASCII word-boundary character set used by editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    pub fn set_word_boundary_ascii_boundary_chars(
        &mut self,
        boundary_chars: &str,
    ) -> Result<(), UiError> {
        self.exec_core(Command::View(
            ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: boundary_chars.to_string(),
            },
        ))?;
        Ok(())
    }

    /// Configure how the Tab key behaves when using `EditCommand::InsertTab`.
    pub fn set_tab_key_behavior(
        &mut self,
        behavior: editor_core::TabKeyBehavior,
    ) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::SetTabKeyBehavior { behavior }))?;
        Ok(())
    }

    /// Configure the tab width (in monospace grid cells).
    ///
    /// This affects:
    /// - visual layout/rendering of `'\t'` characters
    /// - `EditCommand::InsertTab` in spaces mode (insert to the next tab stop)
    pub fn set_tab_width(&mut self, width_cells: usize) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::SetTabWidth {
            width: width_cells,
        }))?;
        Ok(())
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    pub fn reset_word_boundary_defaults(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::View(ViewCommand::ResetWordBoundaryDefaults))?;
        Ok(())
    }

    pub fn set_gutter_width_cells(&mut self, width_cells: u32) -> Result<(), UiError> {
        self.render_config.gutter_width_cells = width_cells;
        // Keep wrap width in sync with the available text area.
        self.set_viewport_px(
            self.render_config.width_px,
            self.render_config.height_px,
            self.render_config.scale,
        )?;
        Ok(())
    }

    /// Enable/disable indentation guides (visual-only).
    pub fn set_indent_guides_enabled(&mut self, enabled: bool) {
        self.render_config.show_indent_guides = enabled;
    }

    /// Configure how whitespace markers are rendered (visual-only).
    pub fn set_whitespace_render_mode(&mut self, mode: WhitespaceRenderMode) {
        self.render_config.whitespace_render_mode = mode;
    }

    /// Configure how fold markers are rendered in the gutter (visual-only).
    pub fn set_fold_marker_style(&mut self, style: FoldMarkerStyle) {
        self.render_config.fold_marker_style = style;
    }

    /// Update pixel viewport size and keep editor-core's viewport width/height in sync.
    ///
    /// This is important for soft-wrapping: editor-core's layout uses "cells", while
    /// the renderer maps "cells" to pixel widths.
    pub fn set_viewport_px(
        &mut self,
        width_px: u32,
        height_px: u32,
        scale: f32,
    ) -> Result<(), UiError> {
        self.render_config.width_px = width_px;
        self.render_config.height_px = height_px;
        self.render_config.scale = scale;

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let usable_w =
            (width_px as f32 - self.render_config.padding_x_px * 2.0 - gutter_px).max(1.0);
        let cell_w = self.render_config.cell_width_px.max(1.0);
        let width_cells = (usable_w / cell_w).floor().max(1.0) as usize;
        self.exec_core(Command::View(ViewCommand::SetViewportWidth {
            width: width_cells,
        }))?;

        // `padding_y_px` is a top inset (like a "content inset"), not a symmetric top+bottom padding.
        //
        // If we subtract it twice, the bottom of the viewport can end up with a large blank area
        // (especially when the viewport height is not an exact multiple of `line_height_px`),
        // and partially visible lines would "pop in" only after crossing an arbitrary threshold.
        let usable_h = (height_px as f32 - self.render_config.padding_y_px).max(1.0);
        let line_h = self.render_config.line_height_px.max(1.0);
        let height_rows = (usable_h / line_h).floor().max(1.0) as usize;
        {
            let mut doc = self.lock_doc();
            doc.ws
                .set_viewport_height(self.view_id, height_rows)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    pub fn viewport_state(&mut self) -> editor_core::ViewportState {
        let v = {
            let mut doc = self.lock_doc();
            match doc.ws.viewport_state_for_view(self.view_id) {
                Ok(v) => v,
                Err(_) => {
                    return editor_core::ViewportState {
                        width: 0,
                        height: None,
                        scroll_top: 0,
                        sub_row_offset: 0,
                        overscan_rows: 0,
                        visible_lines: 0..0,
                        prefetch_lines: 0..0,
                        total_visual_lines: 0,
                    };
                }
            }
        };
        editor_core::ViewportState {
            width: v.width,
            height: v.height,
            scroll_top: v.scroll_top,
            sub_row_offset: v.smooth_scroll.sub_row_offset,
            overscan_rows: v.smooth_scroll.overscan_rows,
            visible_lines: v.visible_lines,
            prefetch_lines: v.prefetch_lines,
            total_visual_lines: v.total_visual_lines,
        }
    }

    /// Total logical line count (0-based lines, as seen by the editor model / line numbers).
    ///
    /// Note: this is independent of soft-wrapping/folding (which affect visual rows).
    pub fn logical_line_count(&self) -> u32 {
        let n = self.with_line_index(|idx| idx.line_count()).unwrap_or(0);
        (n.min(u32::MAX as usize)) as u32
    }

    pub fn gutter_width_cells(&self) -> u32 {
        self.render_config.gutter_width_cells
    }

    pub fn set_smooth_scroll_state(&mut self, top_visual_row: usize, sub_row_offset: u16) {
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_pos_rows = viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = self
            .lock_doc()
            .ws
            .smooth_scroll_state_for_view(self.view_id)
            .unwrap_or(editor_core::workspace::ViewSmoothScrollState {
                top_visual_row: viewport.scroll_top,
                sub_row_offset: viewport.sub_row_offset,
                overscan_rows: viewport.overscan_rows,
            });
        let pos_rows = top_visual_row as f32 + (sub_row_offset as f32 / 65536.0);
        let new_pos = pos_rows.clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    fn max_scroll_top(&self, viewport: &editor_core::ViewportState) -> usize {
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines)
    }

    pub(super) fn ensure_primary_caret_visible_after_navigation(&mut self) {
        let viewport = self.viewport_state();
        let Some(height_rows) = viewport.height else {
            return;
        };
        if height_rows == 0 {
            return;
        }

        let cursor = self.cursor_state();
        let active = cursor
            .selections
            .get(cursor.primary_selection_index)
            .map(|s| s.end)
            .unwrap_or(cursor.position);

        let Some((caret_row, _caret_x)) = ({
            let mut doc = self.lock_doc();
            doc.ws
                .logical_to_visual_for_view(self.view_id, active.line, active.column)
                .ok()
                .flatten()
        }) else {
            return;
        };

        let mut new_top = viewport.scroll_top;
        if caret_row < viewport.scroll_top {
            new_top = caret_row;
        } else if caret_row >= viewport.scroll_top.saturating_add(height_rows) {
            new_top = caret_row.saturating_sub(height_rows.saturating_sub(1));
        }
        new_top = new_top.min(self.max_scroll_top(&viewport));

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            // Keyboard navigation should snap to full rows for a stable caret position.
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    /// Like [`Self::ensure_primary_caret_visible_after_navigation`], but used for text edits
    /// (typing/paste/undo) where we should not snap fractional smooth-scroll offsets unless the
    /// caret actually leaves the visible viewport.
    pub(super) fn ensure_primary_caret_visible_after_edit(&mut self) {
        let viewport = self.viewport_state();
        let Some(height_rows) = viewport.height else {
            return;
        };
        if height_rows == 0 {
            return;
        }

        let cursor = self.cursor_state();
        let active = cursor
            .selections
            .get(cursor.primary_selection_index)
            .map(|s| s.end)
            .unwrap_or(cursor.position);

        let Some((caret_row, _caret_x)) = ({
            let mut doc = self.lock_doc();
            doc.ws
                .logical_to_visual_for_view(self.view_id, active.line, active.column)
                .ok()
                .flatten()
        }) else {
            return;
        };

        let mut new_top = viewport.scroll_top;
        let mut did_scroll = false;
        if caret_row < viewport.scroll_top {
            new_top = caret_row;
            did_scroll = true;
        } else if caret_row >= viewport.scroll_top.saturating_add(height_rows) {
            new_top = caret_row.saturating_sub(height_rows.saturating_sub(1));
            did_scroll = true;
        }

        if !did_scroll {
            return;
        }

        new_top = new_top.min(self.max_scroll_top(&viewport));

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            // When an edit forces us to scroll, snap to a full row so the caret lands predictably.
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    pub fn scroll_by_rows(&mut self, delta_rows: isize) {
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_top = viewport
            .total_visual_lines
            .saturating_sub(height_rows)
            .min(viewport.total_visual_lines) as isize;

        let old = viewport.scroll_top as isize;
        let new_top = (old + delta_rows).clamp(0, max_top.max(0)) as usize;

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: 0,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }

    /// Smooth-scroll the viewport by a pixel delta (positive = scroll down, reveal later lines).
    ///
    /// This updates editor-core's `(scroll_top, sub_row_offset)` smooth-scroll state:
    /// - `scroll_top` is the top visual row anchor.
    /// - `sub_row_offset` is a normalized 0..=65535 fraction within a row.
    ///
    /// Notes:
    /// - The UI layer interprets `sub_row_offset` as a pixel offset in the range
    ///   `0..line_height_px` (using a 65536 denominator).
    /// - The renderer and hit-testing paths must both use the same mapping.
    pub fn scroll_by_pixels(&mut self, delta_y_px: f32) {
        if !delta_y_px.is_finite() || delta_y_px.abs() <= f32::EPSILON {
            return;
        }

        let line_h = self.render_config.line_height_px.max(1.0);
        let viewport = self.viewport_state();
        let height_rows = viewport
            .height
            .unwrap_or(viewport.total_visual_lines)
            .max(1);
        let max_pos_rows = viewport.total_visual_lines.saturating_sub(height_rows) as f32;

        let smooth = {
            let doc = self.lock_doc();
            doc.ws.smooth_scroll_state_for_view(self.view_id).unwrap_or(
                editor_core::workspace::ViewSmoothScrollState {
                    top_visual_row: viewport.scroll_top,
                    sub_row_offset: viewport.sub_row_offset,
                    overscan_rows: viewport.overscan_rows,
                },
            )
        };
        let pos_rows = smooth.top_visual_row as f32 + (smooth.sub_row_offset as f32 / 65536.0);
        let delta_rows = delta_y_px / line_h;
        let new_pos = (pos_rows + delta_rows).clamp(0.0, max_pos_rows.max(0.0));

        let new_top = new_pos.floor().max(0.0) as usize;
        let frac = (new_pos - new_top as f32).clamp(0.0, 0.999_999);
        let sub = ((frac * 65536.0).floor() as u32).min(u16::MAX as u32) as u16;

        let next = editor_core::workspace::ViewSmoothScrollState {
            top_visual_row: new_top,
            sub_row_offset: sub,
            overscan_rows: smooth.overscan_rows,
        };
        if next != smooth {
            let mut doc = self.lock_doc();
            let _ = doc.ws.set_smooth_scroll_state(self.view_id, next);
        }
    }
}
