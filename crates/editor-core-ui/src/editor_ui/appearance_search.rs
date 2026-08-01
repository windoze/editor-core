use super::*;

impl EditorUi {
    pub fn set_theme(&mut self, theme: RenderTheme) {
        self.theme = theme;
    }

    pub fn set_style_colors(&mut self, styles: BTreeMap<u32, StyleColors>) {
        self.theme.styles = styles;
    }

    pub fn clear_style_colors(&mut self) {
        self.theme.styles.clear();
    }

    pub fn set_style_fonts(&mut self, fonts: BTreeMap<u32, StyleFont>) {
        self.theme.style_fonts = fonts;
    }

    pub fn clear_style_fonts(&mut self) {
        self.theme.style_fonts.clear();
    }

    pub fn set_chrome_theme(&mut self, chrome: ChromeTheme) {
        self.theme.styles.insert(
            GUTTER_BACKGROUND_STYLE_ID,
            StyleColors::new(None, Some(chrome.gutter_background)),
        );
        self.theme.styles.insert(
            GUTTER_FOREGROUND_STYLE_ID,
            StyleColors::new(Some(chrome.gutter_foreground), None),
        );
        self.theme.styles.insert(
            GUTTER_SEPARATOR_STYLE_ID,
            StyleColors::new(Some(chrome.gutter_separator), None),
        );
        self.theme.styles.insert(
            FOLD_MARKER_COLLAPSED_STYLE_ID,
            StyleColors::new(None, Some(chrome.fold_marker_collapsed)),
        );
        self.theme.styles.insert(
            FOLD_MARKER_EXPANDED_STYLE_ID,
            StyleColors::new(None, Some(chrome.fold_marker_expanded)),
        );
    }

    /// Replace the per-style text decoration mapping used by the renderer.
    ///
    /// This controls purely visual line effects (underline, double underline, squiggly underline,
    /// strikethrough). It does not affect document text, hit-testing, or selections.
    pub fn set_style_text_decorations(&mut self, decorations: BTreeMap<u32, TextDecorations>) {
        self.theme.text_decorations = decorations;
    }

    pub fn clear_style_text_decorations(&mut self) {
        self.theme.text_decorations.clear();
    }

    /// Replace match highlight ranges (e.g. search matches) as a dedicated overlay style layer.
    ///
    /// Notes:
    /// - Ranges are character offsets (Unicode scalar indices), half-open `[start, end)`.
    /// - Passing an empty slice clears the layer.
    pub fn set_match_highlights_offsets(&mut self, ranges: &[(usize, usize)]) {
        if ranges.is_empty() {
            let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::MATCH_HIGHLIGHTS,
            }]);
            return;
        }

        let doc_len = {
            let doc = self.lock_doc();
            doc.ws.buffer_char_count(self.buffer_id).unwrap_or(0)
        };
        let mut intervals: Vec<Interval> = Vec::with_capacity(ranges.len());
        for (start, end) in ranges {
            let s = (*start).min(doc_len);
            let e = (*end).min(doc_len);
            let (s, e) = if s <= e { (s, e) } else { (e, s) };
            if s < e {
                intervals.push(Interval::new(s, e, MATCH_HIGHLIGHT_STYLE_ID));
            }
        }
        let _ = self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::MATCH_HIGHLIGHTS,
            intervals,
        }]);
    }

    /// Set an active search query and update match highlights accordingly.
    ///
    /// Returns the number of matches found.
    ///
    /// Notes:
    /// - This is intentionally a "UI-level convenience" API. It does not affect the core cursor
    ///   find/replace commands; it only updates the `MATCH_HIGHLIGHTS` style layer for rendering.
    /// - Passing an empty query clears match highlights.
    pub fn search_set_query(
        &mut self,
        query: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        if query.is_empty() {
            self.search_query = None;
            self.set_match_highlights_offsets(&[]);
            return Ok(0);
        }

        self.search_query = Some(SearchQueryState {
            query: query.to_string(),
            options,
        });
        self.search_refresh_matches()
    }

    /// Clear active search query and match highlights.
    pub fn search_clear(&mut self) {
        self.search_query = None;
        self.set_match_highlights_offsets(&[]);
    }

    /// Refresh match highlights for the current search query (if any).
    ///
    /// Returns the number of matches found.
    pub fn search_refresh_matches(&mut self) -> Result<usize, UiError> {
        let Some(q) = self.search_query.as_ref() else {
            self.set_match_highlights_offsets(&[]);
            return Ok(0);
        };

        let text = {
            let doc = self.lock_doc();
            doc.ws
                .buffer_text(self.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        let matches = editor_core::search::find_all(&text, q.query.as_str(), q.options)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        let ranges: Vec<(usize, usize)> = matches.iter().map(|m| (m.start, m.end)).collect();
        self.set_match_highlights_offsets(&ranges);
        Ok(matches.len())
    }

    /// Find next match and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    pub fn find_next(&mut self, query: &str, options: SearchOptions) -> Result<bool, UiError> {
        let result = self.exec_core(Command::Cursor(CursorCommand::FindNext {
            query: query.to_string(),
            options,
        }))?;
        Ok(matches!(result, CommandResult::SearchMatch { .. }))
    }

    /// Find previous match and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    pub fn find_prev(&mut self, query: &str, options: SearchOptions) -> Result<bool, UiError> {
        let result = self.exec_core(Command::Cursor(CursorCommand::FindPrev {
            query: query.to_string(),
            options,
        }))?;
        Ok(matches!(result, CommandResult::SearchMatch { .. }))
    }

    /// Replace the current match (based on selection/caret) and return the number of replacements performed.
    pub fn replace_current(
        &mut self,
        query: &str,
        replacement: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        let result = self.exec_core(Command::Edit(EditCommand::ReplaceCurrent {
            query: query.to_string(),
            replacement: replacement.to_string(),
            options,
        }))?;
        self.refresh_processing()?;
        match result {
            CommandResult::ReplaceResult { replaced } => Ok(replaced),
            _ => Ok(0),
        }
    }

    /// Replace all matches and return the number of replacements performed.
    pub fn replace_all(
        &mut self,
        query: &str,
        replacement: &str,
        options: SearchOptions,
    ) -> Result<usize, UiError> {
        let result = self.exec_core(Command::Edit(EditCommand::ReplaceAll {
            query: query.to_string(),
            replacement: replacement.to_string(),
            options,
        }))?;
        self.refresh_processing()?;
        match result {
            CommandResult::ReplaceResult { replaced } => Ok(replaced),
            _ => Ok(0),
        }
    }
}
