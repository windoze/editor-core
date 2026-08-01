use super::*;

impl EditorUi {
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

        let render_config = self.render_config_for_visible_viewport(viewport.sub_row_offset);

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
        let fold_markers = self.collect_fold_markers();

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
}
