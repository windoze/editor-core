use super::*;

impl EditorUi {
    pub fn execute(&mut self, command: Command) -> Result<CommandResult, UiError> {
        let is_edit = matches!(command, Command::Edit(_));
        let result = self.exec_core(command)?;
        if is_edit {
            self.refresh_processing()?;
            self.ensure_primary_caret_visible_after_edit();
        }
        Ok(result)
    }

    pub fn render_rgba_visible(&mut self) -> Result<Vec<u8>, UiError> {
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        let mut out = vec![0u8; required];
        self.render_rgba_visible_into(out.as_mut_slice())?;
        Ok(out)
    }

    pub fn required_rgba_len(&self) -> usize {
        (self.render_config.width_px as usize)
            .saturating_mul(self.render_config.height_px as usize)
            .saturating_mul(4)
    }

    pub fn render_rgba_visible_into(&mut self, out_rgba: &mut [u8]) -> Result<usize, UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let mut fold_markers = Vec::<FoldMarker>::new();
        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        for region in fold_regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_rgba_into(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        } else {
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();
            self.renderer.render_rgba_into(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
            )?;
        }
        Ok(required)
    }

    /// 增量渲染：只重绘脏行（尽量小的像素区域），并返回需要 present 的 damage rect 列表。
    ///
    /// 约定：
    /// - 调用方需要复用 `out_rgba` 缓冲区，并保证其内容仍然是**上一帧**的像素结果；
    ///   本方法只会更新 dirty rect 覆盖的像素区域。
    /// - 若 viewport/config/theme 发生变化，本方法会自动退化为全量渲染（damage 为整屏）。
    pub fn render_rgba_visible_into_with_damage(
        &mut self,
        out_rgba: &mut [u8],
    ) -> Result<(usize, Vec<DamageRect>), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        if out_rgba.len() < required {
            return Err(RenderError::BufferTooSmall {
                required,
                provided: out_rgba.len(),
            }
            .into());
        }

        let has_virtual_text = self.has_virtual_text_decorations();
        let start_visual_row = if has_virtual_text {
            self.composed_start_row_for_doc_row(start_doc_row)
        } else {
            start_doc_row
        };

        let theme_hash = hash_render_theme(&self.theme);
        let view_version = {
            let doc = self.lock_doc();
            doc.ws.view_version(self.view_id).unwrap_or(0)
        };

        // Fold markers affect gutter rendering; treat them as part of the row signature.
        let fold_markers = {
            let fold_regions = {
                let doc = self.lock_doc();
                doc.ws
                    .folding_regions_for_buffer(self.buffer_id)
                    .unwrap_or_default()
            };
            let mut out = Vec::<FoldMarker>::new();
            for region in fold_regions {
                if region.end_line <= region.start_line {
                    continue;
                }
                out.push(FoldMarker {
                    logical_line: region.start_line as u32,
                    is_collapsed: region.is_collapsed,
                });
            }
            out
        };

        // Fast-path: nothing changed since the last frame.
        if let Some(cache) = self.render_cache.as_ref()
            && cache.view_version == view_version
            && cache.render_config == render_config
            && cache.theme_hash == theme_hash
            && cache.start_visual_row == start_visual_row
            && cache.row_count == row_count
            && cache.has_virtual_text == has_virtual_text
        {
            return Ok((required, Vec::new()));
        }

        if has_virtual_text {
            let (selection_ranges, _primary_idx) = self.selections_offsets();
            let caret_offsets = self.all_caret_offsets();

            let grid: ComposedGrid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_visual_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };

            let row_signatures = composed_row_signatures(
                &grid,
                row_count,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
            );

            let cache_ok = self.render_cache.as_ref().is_some_and(|c| {
                c.render_config == render_config
                    && c.theme_hash == theme_hash
                    && c.start_visual_row == start_visual_row
                    && c.row_count == row_count
                    && c.has_virtual_text == has_virtual_text
                    && c.row_signatures.len() == row_signatures.len()
            });

            if !cache_ok {
                self.renderer.render_composed_rgba_into(
                    &grid,
                    caret_offsets.as_slice(),
                    selection_ranges.as_slice(),
                    fold_markers.as_slice(),
                    render_config,
                    &self.theme,
                    out_rgba,
                )?;
                self.render_cache = Some(RenderFrameCache {
                    view_version,
                    render_config,
                    theme_hash,
                    start_visual_row,
                    row_count,
                    has_virtual_text,
                    row_signatures,
                });
                return Ok((
                    required,
                    vec![DamageRect {
                        x: 0,
                        y: 0,
                        width: render_config.width_px,
                        height: render_config.height_px,
                    }],
                ));
            }

            let prev = self
                .render_cache
                .as_ref()
                .map(|c| c.row_signatures.as_slice())
                .unwrap_or(&[]);
            let dirty_ranges = dirty_row_ranges(prev, row_signatures.as_slice());

            if dirty_ranges.is_empty() {
                if let Some(cache) = self.render_cache.as_mut() {
                    cache.view_version = view_version;
                    cache.row_signatures = row_signatures;
                }
                return Ok((required, Vec::new()));
            }

            self.renderer.render_composed_rgba_into_partial_rows(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
                dirty_ranges.as_slice(),
            )?;

            let mut damage: Vec<DamageRect> = Vec::new();
            for (start, end) in &dirty_ranges {
                if let Some(rect) = damage_rect_for_row_range(*start, *end, render_config) {
                    damage.push(rect);
                }
            }

            if let Some(cache) = self.render_cache.as_mut() {
                cache.view_version = view_version;
                cache.row_signatures = row_signatures;
            }

            Ok((required, damage))
        } else {
            let grid: HeadlessGrid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_visual_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();

            let row_signatures = headless_row_signatures(
                &grid,
                row_count,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
            );

            let cache_ok = self.render_cache.as_ref().is_some_and(|c| {
                c.render_config == render_config
                    && c.theme_hash == theme_hash
                    && c.start_visual_row == start_visual_row
                    && c.row_count == row_count
                    && c.has_virtual_text == has_virtual_text
                    && c.row_signatures.len() == row_signatures.len()
            });

            if !cache_ok {
                self.renderer.render_rgba_into(
                    &grid,
                    carets.as_slice(),
                    selections.as_slice(),
                    fold_markers.as_slice(),
                    render_config,
                    &self.theme,
                    out_rgba,
                )?;
                self.render_cache = Some(RenderFrameCache {
                    view_version,
                    render_config,
                    theme_hash,
                    start_visual_row,
                    row_count,
                    has_virtual_text,
                    row_signatures,
                });
                return Ok((
                    required,
                    vec![DamageRect {
                        x: 0,
                        y: 0,
                        width: render_config.width_px,
                        height: render_config.height_px,
                    }],
                ));
            }

            let prev = self
                .render_cache
                .as_ref()
                .map(|c| c.row_signatures.as_slice())
                .unwrap_or(&[]);
            let dirty_ranges = dirty_row_ranges(prev, row_signatures.as_slice());

            if dirty_ranges.is_empty() {
                if let Some(cache) = self.render_cache.as_mut() {
                    cache.view_version = view_version;
                    cache.row_signatures = row_signatures;
                }
                return Ok((required, Vec::new()));
            }

            self.renderer.render_rgba_into_partial_rows(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                out_rgba,
                dirty_ranges.as_slice(),
            )?;

            let mut damage: Vec<DamageRect> = Vec::new();
            for (start, end) in &dirty_ranges {
                if let Some(rect) = damage_rect_for_row_range(*start, *end, render_config) {
                    damage.push(rect);
                }
            }

            if let Some(cache) = self.render_cache.as_mut() {
                cache.view_version = view_version;
                cache.row_signatures = row_signatures;
            }

            Ok((required, damage))
        }
    }

    /// Enable the Skia Metal backend (macOS only).
    ///
    /// This is a rendering backend switch only; it does not affect editor state.
    pub fn enable_metal(
        &mut self,
        metal_device: *mut c_void,
        metal_command_queue: *mut c_void,
    ) -> Result<(), UiError> {
        self.renderer
            .enable_metal(metal_device, metal_command_queue)?;
        Ok(())
    }

    /// Disable the Metal backend and revert to CPU raster output.
    pub fn disable_metal(&mut self) {
        self.renderer.disable_metal();
    }

    /// Render the current visible viewport into a Metal texture (macOS only).
    ///
    /// The host is responsible for presenting the texture (e.g. `CAMetalDrawable`).
    pub fn render_metal_visible_into_texture(
        &mut self,
        metal_texture: *mut c_void,
    ) -> Result<(), UiError> {
        // Non-blocking: apply any completed async processing (Tree-sitter highlighting/folding).
        let _ = self.poll_processing()?;

        let viewport = self.viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);

        let (selection_ranges, _primary_idx) = self.selections_offsets();
        let caret_offsets = self.all_caret_offsets();

        let mut render_config = self.render_config;
        render_config.scroll_y_px = scroll_y_px;
        render_config.tab_width_cells = {
            let doc = self.lock_doc();
            (doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)).min(u32::MAX as usize) as u32
        };

        let mut fold_markers = Vec::<FoldMarker>::new();
        let fold_regions = {
            let doc = self.lock_doc();
            doc.ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default()
        };
        for region in fold_regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }

        if self.has_virtual_text_decorations() {
            let start_composed = self.composed_start_row_for_doc_row(start_row);
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_composed(self.view_id, start_composed, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            self.renderer.render_composed_into_metal_texture(
                &grid,
                caret_offsets.as_slice(),
                selection_ranges.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
            )?;
        } else {
            let grid = {
                let mut doc = self.lock_doc();
                doc.ws
                    .get_viewport_content_styled(self.view_id, start_row, row_count)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            let selections = self.all_selections_visual();
            let carets = self.all_carets_visual();
            self.renderer.render_rgba_into_metal_texture(
                &grid,
                carets.as_slice(),
                selections.as_slice(),
                fold_markers.as_slice(),
                render_config,
                &self.theme,
                metal_texture,
            )?;
        }

        Ok(())
    }

    pub(super) fn has_virtual_text_decorations(&self) -> bool {
        let doc = self.lock_doc();
        doc.ws
            .buffer_decorations(self.buffer_id)
            .ok()
            .map(|decorations| {
                decorations.values().any(|layer| {
                    layer
                        .iter()
                        .any(|d| d.text.as_ref().is_some_and(|t| !t.is_empty()))
                })
            })
            .unwrap_or(false)
    }

    fn all_selections_visual(&mut self) -> Vec<VisualSelection> {
        let cursor = self.cursor_state();
        let mut out = Vec::new();
        let mut doc = self.lock_doc();

        for sel in cursor.selections {
            if sel.start == sel.end {
                continue;
            }
            let Some((a_row, a_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.start.line, sel.start.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            let Some((b_row, b_x)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };
            out.push(VisualSelection {
                start_row: a_row as u32,
                start_x_cells: a_x as u32,
                end_row: b_row as u32,
                end_x_cells: b_x as u32,
            });
        }

        out
    }

    fn all_carets_visual(&mut self) -> Vec<VisualCaret> {
        let cursor = self.cursor_state();
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        let mut doc = self.lock_doc();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let Some((row, x_cells)) = doc
                .ws
                .logical_to_visual_for_view(self.view_id, sel.end.line, sel.end.column)
                .ok()
                .flatten()
            else {
                continue;
            };

            // Draw primary caret last so it wins in overlaps.
            let caret = VisualCaret {
                row: row as u32,
                x_cells: x_cells as u32,
            };
            if idx == primary_idx {
                primary.push(caret);
            } else {
                secondary.push(caret);
            }
        }
        secondary.extend(primary);
        secondary
    }

    fn all_caret_offsets(&self) -> Vec<usize> {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return Vec::new();
        };
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let offset = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if idx == primary_idx {
                primary.push(offset);
            } else {
                secondary.push(offset);
            }
        }
        secondary.extend(primary);
        secondary
    }

    pub(super) fn pixel_to_visual(&mut self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let global_row = viewport.scroll_top + local_row;
        (global_row, col)
    }

    pub(super) fn pixel_to_local_row_col(&mut self, x_px: f32, y_px: f32) -> (usize, usize) {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px + scroll_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        (local_row, col)
    }

    pub(super) fn composed_viewport_grid(&mut self) -> (usize, usize, editor_core::ComposedGrid) {
        let viewport = self.viewport_state();
        let start_doc_row = viewport.scroll_top;
        let row_count = self.viewport_row_count_for_render(&viewport);
        let start_composed = self.composed_start_row_for_doc_row(start_doc_row);
        let grid = {
            let mut doc = self.lock_doc();
            doc.ws
                .get_viewport_content_composed(self.view_id, start_composed, row_count)
                .unwrap_or_else(|_| editor_core::ComposedGrid::new(start_composed, row_count))
        };
        (start_composed, row_count, grid)
    }

    pub(crate) fn viewport_row_count_for_render(
        &self,
        viewport: &editor_core::ViewportState,
    ) -> usize {
        let start_row = viewport.scroll_top;
        let base = viewport
            .height
            .unwrap_or(viewport.total_visual_lines.saturating_sub(start_row));

        // When the pixel viewport height does not fit an integer number of rows (or when a
        // sub-row scroll offset is present), the bottom of the viewport can reveal part of the
        // next visual row. We still render it and rely on the host to clip.
        //
        // We compute the required row count from pixel geometry to avoid artifacts such as:
        // - the last partially visible row being fully hidden
        // - blank strips when `sub_row_offset` is close to a full row
        if viewport.height.is_none() {
            return base;
        }

        let line_h = self.render_config.line_height_px.max(1.0);
        // See `set_viewport_px`: vertical padding is a top inset, not top+bottom.
        let usable_h =
            (self.render_config.height_px as f32 - self.render_config.padding_y_px).max(1.0);
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        let desired_rows = ((usable_h + scroll_y_px) / line_h).ceil().max(1.0) as usize;
        let max_rows = viewport.total_visual_lines.saturating_sub(start_row);
        base.max(desired_rows).min(max_rows.max(1))
    }

    pub(super) fn sub_row_offset_to_scroll_y_px(&self, sub_row_offset: u16) -> f32 {
        // Interpret `sub_row_offset` as a fraction of a row using a 65536 denominator.
        // This keeps the invariant that 65535 corresponds to "almost a full row", not exactly one.
        let line_h = self.render_config.line_height_px.max(1.0);
        (sub_row_offset as f32 / 65536.0) * line_h
    }

    pub(super) fn composed_start_row_for_doc_row(&mut self, doc_row: usize) -> usize {
        // Fast path: no above-line virtual text => composed rows are identical to doc visual rows.
        let mut doc = self.lock_doc();
        let has_above_line =
            doc.ws
                .buffer_decorations(self.buffer_id)
                .ok()
                .is_some_and(|decorations| {
                    decorations.values().any(|layer| {
                        layer.iter().any(|d| {
                            d.placement == editor_core::DecorationPlacement::AboveLine
                                && d.text.as_ref().is_some_and(|t| !t.is_empty())
                        })
                    })
                });
        if !has_above_line {
            return doc_row;
        }

        let Ok((top_logical_line, _visual_in_logical)) =
            doc.ws.visual_to_logical_for_view(self.view_id, doc_row)
        else {
            return doc_row;
        };

        // Count above-line decorations per logical line.
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return doc_row;
        };
        let Ok(decorations) = doc.ws.buffer_decorations(self.buffer_id) else {
            return doc_row;
        };
        let mut above_count: HashMap<usize, usize> = HashMap::new();
        for layer in decorations.values() {
            for d in layer {
                if d.placement != editor_core::DecorationPlacement::AboveLine {
                    continue;
                }
                let Some(text) = d.text.as_ref() else {
                    continue;
                };
                if text.is_empty() {
                    continue;
                }
                let line = line_index.char_offset_to_position(d.range.start).0;
                *above_count.entry(line).or_insert(0) += 1;
            }
        }

        let mut prefix = 0usize;
        if !above_count.is_empty() {
            let regions = doc
                .ws
                .folding_regions_for_buffer(self.buffer_id)
                .unwrap_or_default();
            for (line, count) in above_count {
                if line >= top_logical_line || is_logical_line_hidden(regions.as_slice(), line) {
                    continue;
                }
                prefix = prefix.saturating_add(count);
            }
        }
        doc_row.saturating_add(prefix)
    }
}
