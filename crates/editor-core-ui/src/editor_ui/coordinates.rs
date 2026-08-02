use super::*;

impl EditorUi {
    pub fn char_offset_to_logical_position(&self, char_offset: usize) -> (usize, usize) {
        let doc = self.lock_doc();
        let doc_len = doc.ws.buffer_char_count(self.buffer_id).unwrap_or(0);
        let off = char_offset.min(doc_len);
        doc.ws
            .buffer_line_index(self.buffer_id)
            .ok()
            .map(|idx| idx.char_offset_to_position(off))
            .unwrap_or((0, 0))
    }

    /// Map a character offset (Unicode scalar index) to visual `(row, x_cells)`.
    pub fn char_offset_to_visual(&mut self, char_offset: usize) -> Option<(usize, usize)> {
        let (line, column) = self.char_offset_to_logical_position(char_offset);
        let mut doc = self.lock_doc();
        doc.ws
            .logical_to_visual_for_view(self.view_id, line, column)
            .ok()
            .flatten()
    }

    /// Map a visual `(row, x_cells)` position to a character offset.
    pub fn visual_to_char_offset(&mut self, row: usize, x_cells: usize) -> Option<usize> {
        let mut doc = self.lock_doc();
        let pos = doc
            .ws
            .visual_position_to_logical_for_view(self.view_id, row, x_cells)
            .ok()??;
        doc.ws
            .buffer_line_index(self.buffer_id)
            .ok()
            .map(|idx| idx.position_to_char_offset(pos.line, pos.column))
    }

    /// Map a character offset to a point in the view coordinate space (pixels).
    ///
    /// - `x_px` is left-to-right (in pixels)
    /// - `y_px` is top-to-bottom (in pixels), aligned to the top of the visual row
    pub fn char_offset_to_view_point_px(&mut self, char_offset: usize) -> Option<(f32, f32)> {
        let viewport = self.viewport_state();
        let scroll_y_px = self.sub_row_offset_to_scroll_y_px(viewport.sub_row_offset);
        if self.has_virtual_text_decorations() {
            let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
            let local_row = composed_line_index_for_offset(&grid, char_offset)?;
            let x_cells = caret_x_cells_in_composed_line(&grid.lines[local_row], char_offset);

            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let x_px = self.render_config.padding_x_px
                + gutter_px
                + x_cells as f32 * self.render_config.cell_width_px;
            let y_px = self.render_config.padding_y_px
                + local_row as f32 * self.render_config.line_height_px
                - scroll_y_px;
            return Some((x_px, y_px));
        }

        let (row, x_cells) = self.char_offset_to_visual(char_offset)?;
        let local_row = row.saturating_sub(viewport.scroll_top);

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x_px = self.render_config.padding_x_px
            + gutter_px
            + x_cells as f32 * self.render_config.cell_width_px;
        let y_px = self.render_config.padding_y_px
            + local_row as f32 * self.render_config.line_height_px
            - scroll_y_px;
        Some((x_px, y_px))
    }

    /// Hit-test a point in the view coordinate space (pixels, top-left origin) and return the
    /// corresponding character offset (Unicode scalar index).
    pub fn view_point_to_char_offset(&mut self, x_px: f32, y_px: f32) -> Option<usize> {
        if self.has_virtual_text_decorations() {
            let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
            if grid.lines.is_empty() {
                return Some(0);
            }

            let (local_row, x_cells) = self.pixel_to_local_row_col(x_px, y_px);
            let local_row = local_row.min(grid.lines.len().saturating_sub(1));
            let line = &grid.lines[local_row];
            return Some(hit_test_composed_line_char_offset(line, x_cells));
        }

        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        self.visual_to_char_offset(row, x_cells)
    }

    /// Hit-test and return the raw LSP `DocumentLink` JSON (if any) at the given character offset.
    ///
    /// Notes:
    /// - Offsets are Unicode scalar indices.
    /// - Uses `DecorationLayerId::DOCUMENT_LINKS` and returns the `data_json` payload embedded by
    ///   `editor-core-lsp`.
    pub fn document_link_json_at_char_offset(&self, char_offset: usize) -> Option<String> {
        let doc = self.lock_doc();
        let layer = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .ok()?
            .get(&DecorationLayerId::DOCUMENT_LINKS)?;

        let mut best: Option<&editor_core::Decoration> = None;
        let mut best_len: usize = usize::MAX;

        for d in layer {
            if d.kind != DecorationKind::DocumentLink {
                continue;
            }
            let contains = if d.range.start == d.range.end {
                char_offset == d.range.start
            } else {
                char_offset >= d.range.start && char_offset < d.range.end
            };
            if !contains {
                continue;
            }

            let len = d.range.end.saturating_sub(d.range.start);
            if len < best_len {
                best = Some(d);
                best_len = len;
            }
        }

        best.and_then(|d| d.data_json.clone())
    }

    /// Hit-test and return the raw LSP `DocumentLink` JSON (if any) at the given view point.
    pub fn document_link_json_at_view_point_px(&mut self, x_px: f32, y_px: f32) -> Option<String> {
        let off = self.view_point_to_char_offset(x_px, y_px)?;
        self.document_link_json_at_char_offset(off)
    }

    /// Hit-test and return the raw LSP `InlayHint` JSON (if any) at the given view point.
    ///
    /// Inlay hints are inline virtual text. This intentionally checks the composed virtual cells
    /// first so clicking an inlay hint anchored at a document offset does not fall through to the
    /// document character at that same offset.
    pub fn inlay_hint_json_at_view_point_px(&mut self, x_px: f32, y_px: f32) -> Option<String> {
        if !self.has_virtual_text_decorations() {
            return None;
        }

        let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
        if grid.lines.is_empty() {
            return None;
        }

        let (local_row, x_cells) = self.pixel_to_local_row_col(x_px, y_px);
        let line = grid.lines.get(local_row)?;
        if !matches!(line.kind, ComposedLineKind::Document { .. }) {
            return None;
        }

        let mut x = 0usize;
        let mut hit: Option<(usize, usize)> = None;
        for (idx, cell) in line.cells.iter().enumerate() {
            let w = cell.width.max(1);
            if x_cells < x.saturating_add(w) {
                if let ComposedCellSource::Virtual { anchor_offset } = cell.source
                    && cell.styles.contains(&INLAY_HINT_STYLE_ID)
                {
                    hit = Some((idx, anchor_offset));
                }
                break;
            }
            x = x.saturating_add(w);
        }

        let (hit_idx, anchor_offset) = hit?;
        let run_text: String = line
            .cells
            .iter()
            .skip(hit_idx)
            .take_while(|cell| {
                matches!(
                    cell.source,
                    ComposedCellSource::Virtual { anchor_offset: off } if off == anchor_offset
                ) && cell.styles.contains(&INLAY_HINT_STYLE_ID)
            })
            .map(|cell| cell.ch)
            .collect();

        let doc = self.lock_doc();
        let layer = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .ok()?
            .get(&DecorationLayerId::INLAY_HINTS)?;

        layer
            .iter()
            .filter(|d| {
                d.kind == DecorationKind::InlayHint
                    && d.placement != DecorationPlacement::AboveLine
                    && d.range.start == anchor_offset
                    && d.range.end == anchor_offset
            })
            .find(|d| d.text.as_deref() == Some(run_text.as_str()))
            .or_else(|| {
                layer.iter().find(|d| {
                    d.kind == DecorationKind::InlayHint
                        && d.placement != DecorationPlacement::AboveLine
                        && d.range.start == anchor_offset
                        && d.range.end == anchor_offset
                })
            })
            .and_then(|d| d.data_json.clone())
    }

    /// Hit-test and return the raw LSP `CodeLens` JSON (if any) at the given view point.
    ///
    /// Code lens is rendered as above-line virtual text. Unlike document-link hit-testing, this
    /// intentionally checks the composed virtual cells first so clicking the corresponding document
    /// line start does not accidentally trigger a code lens anchored at the same offset.
    pub fn code_lens_json_at_view_point_px(&mut self, x_px: f32, y_px: f32) -> Option<String> {
        if !self.has_virtual_text_decorations() {
            return None;
        }

        let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
        if grid.lines.is_empty() {
            return None;
        }

        let (local_row, x_cells) = self.pixel_to_local_row_col(x_px, y_px);
        let line = grid.lines.get(local_row)?;
        if !matches!(line.kind, ComposedLineKind::VirtualAboveLine { .. }) {
            return None;
        }

        let mut x = 0usize;
        let mut anchor_offset: Option<usize> = None;
        for cell in &line.cells {
            let w = cell.width.max(1);
            if x_cells < x.saturating_add(w) {
                if let ComposedCellSource::Virtual { anchor_offset: off } = cell.source {
                    anchor_offset = Some(off);
                }
                break;
            }
            x = x.saturating_add(w);
        }
        let anchor_offset = anchor_offset?;
        let text: String = line.cells.iter().map(|cell| cell.ch).collect();

        let doc = self.lock_doc();
        let layer = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .ok()?
            .get(&DecorationLayerId::CODE_LENS)?;

        layer
            .iter()
            .filter(|d| {
                d.kind == DecorationKind::CodeLens
                    && d.placement == DecorationPlacement::AboveLine
                    && d.range.start == anchor_offset
            })
            .find(|d| d.text.as_deref() == Some(text.as_str()))
            .or_else(|| {
                layer.iter().find(|d| {
                    d.kind == DecorationKind::CodeLens
                        && d.placement == DecorationPlacement::AboveLine
                        && d.range.start == anchor_offset
                })
            })
            .and_then(|d| d.data_json.clone())
    }

    pub fn line_height_px(&self) -> f32 {
        self.render_config.line_height_px
    }
}
