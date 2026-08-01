use super::*;

impl EditorUi {
    /// Export current diagnostics for the active buffer.
    pub fn diagnostics_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let diagnostics = doc
            .ws
            .diagnostics_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "diagnostics": diagnostics.iter().map(value_diagnostic).collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode diagnostics: {err}")))
    }

    /// Export current decoration layers for the active buffer.
    pub fn decorations_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let decorations = doc
            .ws
            .buffer_decorations(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "layers": decorations
                .iter()
                .map(|(layer, decorations)| {
                    serde_json::json!({
                        "layer": layer.0,
                        "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
                    })
                })
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode decorations: {err}")))
    }

    /// Export current document symbols for the active buffer.
    pub fn document_symbols_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let outline = doc
            .ws
            .document_symbols_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "symbols": outline
                .symbols
                .iter()
                .map(value_document_symbol)
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode document symbols: {err}")))
    }

    /// Export current folding regions for the active buffer.
    pub fn folding_regions_json(&self) -> Result<String, UiError> {
        let doc = self.lock_doc();
        let regions = doc
            .ws
            .folding_regions_for_buffer(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "regions": regions.iter().map(value_fold_region).collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode folding regions: {err}")))
    }

    /// Export style intervals overlapping the given character-offset range.
    pub fn style_intervals_json(&self, start: usize, end: usize) -> Result<String, UiError> {
        let (start, end) = (start.min(end), start.max(end));
        let doc = self.lock_doc();
        let layers = doc
            .ws
            .style_intervals_for_buffer(self.buffer_id, start, end)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let value = serde_json::json!({
            "layers": layers
                .iter()
                .map(|(layer, intervals)| {
                    serde_json::json!({
                        "layer": layer.0,
                        "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
                    })
                })
                .collect::<Vec<_>>()
        });
        serde_json::to_string(&value)
            .map_err(|err| UiError::Processor(format!("failed to encode style intervals: {err}")))
    }
}
