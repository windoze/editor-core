use crate::{
    EditorLspRequestEvent, EditorLspResultEvent, EditorUi, EditorUiDoc, ProcessingEdit, UiError,
    ViewId,
};

const MAX_EDITOR_UI_STATE_EVENTS: usize = 512;
const DERIVED_STATE_FAMILIES: [&str; 5] = [
    "style_intervals",
    "folding_regions",
    "diagnostics",
    "decorations",
    "document_symbols",
];

fn lsp_failed_status_value(command: Option<&str>, detail: String) -> serde_json::Value {
    let server = command.map(|cmd| serde_json::json!({ "command": cmd }));
    serde_json::json!({
        "availability": "failed",
        "state": "failed",
        "server": server,
        "activity": Option::<serde_json::Value>::None,
        "detail": detail,
        "capabilities": Option::<serde_json::Value>::None,
        "workspace_folders": Vec::<serde_json::Value>::new(),
    })
}

fn lsp_status_event_signature(status: &serde_json::Value) -> String {
    status.to_string()
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct EditorUiStateEvent {
    pub sequence: u64,
    pub kind: String,
    pub family: String,
    pub title: String,
    pub view_id: u64,
    pub source_sequence: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lsp_request: Option<EditorLspRequestEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lsp_result: Option<EditorLspResultEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lsp_status: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<EditorUiTextStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dirty: Option<EditorUiDirtyStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selection: Option<EditorUiSelectionStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub viewport: Option<EditorUiViewportStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub layout: Option<EditorUiLayoutStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub derived_state: Option<EditorUiDerivedStateEvent>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct EditorUiStateEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<EditorUiStateEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiTextStateEvent {
    pub text_version: u64,
    pub char_len: usize,
    pub is_modified: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiDirtyStateEvent {
    pub is_modified: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiPositionStateEvent {
    pub line: usize,
    pub column: usize,
    pub offset: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiSelectionRangeStateEvent {
    pub start: usize,
    pub end: usize,
    pub anchor: usize,
    pub active: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiSelectionStateEvent {
    pub view_version: u64,
    pub primary: EditorUiPositionStateEvent,
    pub primary_selection_index: usize,
    pub selection_count: usize,
    pub has_selection: bool,
    pub selections: Vec<EditorUiSelectionRangeStateEvent>,
}

impl EditorUiSelectionStateEvent {
    pub(crate) fn same_selection_as(&self, other: &Self) -> bool {
        self.primary == other.primary
            && self.primary_selection_index == other.primary_selection_index
            && self.selection_count == other.selection_count
            && self.has_selection == other.has_selection
            && self.selections == other.selections
    }
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiViewportRangeStateEvent {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiViewportStateEvent {
    pub view_version: u64,
    pub width: usize,
    pub height: Option<usize>,
    pub scroll_top: usize,
    pub sub_row_offset: u16,
    pub overscan_rows: usize,
    pub visible_lines: EditorUiViewportRangeStateEvent,
    pub prefetch_lines: EditorUiViewportRangeStateEvent,
    pub total_visual_lines: usize,
}

impl EditorUiViewportStateEvent {
    pub(crate) fn same_viewport_as(&self, other: &Self) -> bool {
        self.width == other.width
            && self.height == other.height
            && self.scroll_top == other.scroll_top
            && self.sub_row_offset == other.sub_row_offset
            && self.overscan_rows == other.overscan_rows
            && self.visible_lines == other.visible_lines
            && self.prefetch_lines == other.prefetch_lines
            && self.total_visual_lines == other.total_visual_lines
    }
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct EditorUiLayoutStateEvent {
    pub width_px: u32,
    pub height_px: u32,
    pub scale: f32,
    pub font_size: f32,
    pub line_height_px: f32,
    pub cell_width_px: f32,
    pub padding_x_px: f32,
    pub padding_y_px: f32,
    pub gutter_width_cells: u32,
    pub tab_width_cells: u32,
    pub text_vertical_align: String,
}

impl EditorUiLayoutStateEvent {
    pub(crate) fn same_layout_as(&self, other: &Self) -> bool {
        self == other
    }
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiDerivedStateEvent {
    pub status: String,
    pub reason: String,
    pub text_version: u64,
    pub edit_count: usize,
    pub families: Vec<String>,
}

impl EditorUiDerivedStateEvent {
    pub(crate) fn changed_from_processing_edits(
        text_version: u64,
        edits: &[ProcessingEdit],
    ) -> Option<Self> {
        let mut families = Vec::new();
        let mut edit_count = 0;
        for edit in edits {
            let family = match edit {
                ProcessingEdit::ReplaceStyleLayer { .. }
                | ProcessingEdit::ClearStyleLayer { .. } => "style_intervals",
                ProcessingEdit::ReplaceFoldingRegions { .. }
                | ProcessingEdit::ClearFoldingRegions => "folding_regions",
                ProcessingEdit::ReplaceDiagnostics { .. } | ProcessingEdit::ClearDiagnostics => {
                    "diagnostics"
                }
                ProcessingEdit::ReplaceDecorations { .. }
                | ProcessingEdit::ClearDecorations { .. } => "decorations",
                ProcessingEdit::ReplaceDocumentSymbols { .. }
                | ProcessingEdit::ClearDocumentSymbols => "document_symbols",
            };
            edit_count += 1;
            if !families.iter().any(|existing| existing == family) {
                families.push(family.to_string());
            }
        }

        if families.is_empty() {
            return None;
        }

        Some(Self {
            status: "changed".to_string(),
            reason: "processing_edits".to_string(),
            text_version,
            edit_count,
            families,
        })
    }

    pub(crate) fn stale(text_version: u64, reason: impl Into<String>) -> Self {
        Self {
            status: "stale".to_string(),
            reason: reason.into(),
            text_version,
            edit_count: 0,
            families: DERIVED_STATE_FAMILIES
                .iter()
                .map(|family| (*family).to_string())
                .collect(),
        }
    }
}

impl EditorUiDoc {
    pub(crate) fn record_state_event_from_lsp_request(
        &mut self,
        source: EditorLspRequestEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "lsp_request".to_string(),
            family: source.family.clone(),
            title: source.title.clone(),
            view_id: source.view_id,
            source_sequence: source.sequence,
            lsp_request: Some(source),
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn record_state_event_from_lsp_result(
        &mut self,
        source: EditorLspResultEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "lsp_result".to_string(),
            family: source.family.clone(),
            title: source.title.clone(),
            view_id: source.view_id,
            source_sequence: source.sequence,
            lsp_request: None,
            lsp_result: Some(source),
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn record_state_event_from_lsp_status_changed(
        &mut self,
        view_id: ViewId,
        status: serde_json::Value,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "lsp_status_changed".to_string(),
            family: "lsp".to_string(),
            title: "LSP status changed".to_string(),
            view_id: view_id.get(),
            source_sequence: 0,
            lsp_request: None,
            lsp_result: None,
            lsp_status: Some(status),
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn fail_lsp_and_record_status(
        &mut self,
        view_id: ViewId,
        reason: impl Into<String>,
    ) -> u64 {
        let reason = reason.into();
        self.lsp_fail(reason.clone());
        let status = lsp_failed_status_value(self.lsp_last_cmd.as_deref(), reason);
        self.lsp_last_status_event_signature = Some(lsp_status_event_signature(&status));
        self.record_state_event_from_lsp_status_changed(view_id, status)
    }

    pub(crate) fn record_state_event_from_text_changed(&mut self, view_id: ViewId) -> u64 {
        let char_len = self
            .ws
            .buffer_text(self.buffer_id)
            .map(|text| text.chars().count())
            .unwrap_or(0);
        let is_modified = self.ws.is_modified_for_view(view_id).unwrap_or(false);

        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "text_changed".to_string(),
            family: "document".to_string(),
            title: "Text changed".to_string(),
            view_id: view_id.get(),
            source_sequence: self.text_version,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: Some(EditorUiTextStateEvent {
                text_version: self.text_version,
                char_len,
                is_modified,
            }),
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn record_state_event_from_dirty_changed(
        &mut self,
        view_id: ViewId,
        is_modified: bool,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "dirty_changed".to_string(),
            family: "document".to_string(),
            title: "Dirty state changed".to_string(),
            view_id: view_id.get(),
            source_sequence: 0,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: Some(EditorUiDirtyStateEvent { is_modified }),
            selection: None,
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn selection_state_for_view(
        &self,
        view_id: ViewId,
    ) -> Option<EditorUiSelectionStateEvent> {
        let cursor = self.ws.cursor_state_for_view(view_id).ok()?;
        let line_index = self.ws.buffer_line_index(self.buffer_id).ok()?;
        let selections = cursor
            .selections
            .iter()
            .map(|selection| {
                let start_offset = line_index
                    .position_to_char_offset(selection.start.line, selection.start.column);
                let end_offset =
                    line_index.position_to_char_offset(selection.end.line, selection.end.column);
                let (start, end) = if start_offset <= end_offset {
                    (start_offset, end_offset)
                } else {
                    (end_offset, start_offset)
                };
                EditorUiSelectionRangeStateEvent {
                    start,
                    end,
                    anchor: start_offset,
                    active: end_offset,
                }
            })
            .collect::<Vec<_>>();
        let view_version = self.ws.view_version(view_id).unwrap_or(0);

        Some(EditorUiSelectionStateEvent {
            view_version,
            primary: EditorUiPositionStateEvent {
                line: cursor.position.line,
                column: cursor.position.column,
                offset: cursor.offset,
            },
            primary_selection_index: cursor.primary_selection_index,
            selection_count: selections.len(),
            has_selection: cursor.selection.is_some(),
            selections,
        })
    }

    pub(crate) fn record_state_event_from_selection_changed(
        &mut self,
        view_id: ViewId,
        selection: EditorUiSelectionStateEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "selection_changed".to_string(),
            family: "document".to_string(),
            title: "Selection changed".to_string(),
            view_id: view_id.get(),
            source_sequence: selection.view_version,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: Some(selection),
            viewport: None,
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn viewport_state_for_view(
        &mut self,
        view_id: ViewId,
    ) -> Option<EditorUiViewportStateEvent> {
        let viewport = self.ws.viewport_state_for_view(view_id).ok()?;
        let view_version = self.ws.view_version(view_id).unwrap_or(0);
        Some(EditorUiViewportStateEvent {
            view_version,
            width: viewport.width,
            height: viewport.height,
            scroll_top: viewport.scroll_top,
            sub_row_offset: viewport.smooth_scroll.sub_row_offset,
            overscan_rows: viewport.smooth_scroll.overscan_rows,
            visible_lines: EditorUiViewportRangeStateEvent {
                start: viewport.visible_lines.start,
                end: viewport.visible_lines.end,
            },
            prefetch_lines: EditorUiViewportRangeStateEvent {
                start: viewport.prefetch_lines.start,
                end: viewport.prefetch_lines.end,
            },
            total_visual_lines: viewport.total_visual_lines,
        })
    }

    pub(crate) fn record_state_event_from_viewport_changed(
        &mut self,
        view_id: ViewId,
        viewport: EditorUiViewportStateEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "viewport_changed".to_string(),
            family: "document".to_string(),
            title: "Viewport changed".to_string(),
            view_id: view_id.get(),
            source_sequence: viewport.view_version,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: Some(viewport),
            layout: None,
            derived_state: None,
        })
    }

    pub(crate) fn record_state_event_from_layout_changed(
        &mut self,
        view_id: ViewId,
        layout: EditorUiLayoutStateEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "layout_changed".to_string(),
            family: "document".to_string(),
            title: "Layout changed".to_string(),
            view_id: view_id.get(),
            source_sequence: 0,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: Some(layout),
            derived_state: None,
        })
    }

    pub(crate) fn record_state_event_from_derived_state_changed(
        &mut self,
        view_id: ViewId,
        derived_state: EditorUiDerivedStateEvent,
    ) -> u64 {
        self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "derived_state_changed".to_string(),
            family: "derived_state".to_string(),
            title: "Derived state changed".to_string(),
            view_id: view_id.get(),
            source_sequence: derived_state.text_version,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: Some(derived_state),
        })
    }

    pub(crate) fn record_state_event_from_derived_state_stale_if_needed(
        &mut self,
        view_id: ViewId,
        reason: impl Into<String>,
    ) -> Option<u64> {
        let last_changed_text_version = self.derived_state_last_changed_text_version?;
        if last_changed_text_version >= self.text_version {
            return None;
        }
        if self.derived_state_last_stale_text_version == Some(self.text_version) {
            return None;
        }

        self.derived_state_last_stale_text_version = Some(self.text_version);
        let derived_state = EditorUiDerivedStateEvent::stale(self.text_version, reason);
        Some(self.record_state_event(EditorUiStateEvent {
            sequence: 0,
            kind: "derived_state_stale".to_string(),
            family: "derived_state".to_string(),
            title: "Derived state stale".to_string(),
            view_id: view_id.get(),
            source_sequence: derived_state.text_version,
            lsp_request: None,
            lsp_result: None,
            lsp_status: None,
            text: None,
            dirty: None,
            selection: None,
            viewport: None,
            layout: None,
            derived_state: Some(derived_state),
        }))
    }

    fn record_state_event(&mut self, mut event: EditorUiStateEvent) -> u64 {
        let sequence = self.next_state_event_sequence;
        self.next_state_event_sequence = self.next_state_event_sequence.saturating_add(1);
        event.sequence = sequence;
        if event.source_sequence == 0 {
            event.source_sequence = sequence;
        }
        self.state_events.push_back(event);

        while self.state_events.len() > MAX_EDITOR_UI_STATE_EVENTS {
            self.state_events.pop_front();
        }

        sequence
    }

    pub(crate) fn state_events_latest_sequence(&self) -> u64 {
        self.next_state_event_sequence.saturating_sub(1)
    }

    pub(crate) fn state_events_after(&self, after_sequence: u64) -> EditorUiStateEventsSnapshot {
        EditorUiStateEventsSnapshot {
            latest_sequence: self.state_events_latest_sequence(),
            events: self
                .state_events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }
}

impl EditorUi {
    pub(crate) fn layout_state(&self) -> EditorUiLayoutStateEvent {
        let tab_width_cells = {
            let doc = self.lock_doc();
            doc.ws.tab_width_for_view(self.view_id).unwrap_or(4)
        };
        EditorUiLayoutStateEvent {
            width_px: self.render_config.width_px,
            height_px: self.render_config.height_px,
            scale: self.render_config.scale,
            font_size: self.render_config.font_size,
            line_height_px: self.render_config.line_height_px,
            cell_width_px: self.render_config.cell_width_px,
            padding_x_px: self.render_config.padding_x_px,
            padding_y_px: self.render_config.padding_y_px,
            gutter_width_cells: self.render_config.gutter_width_cells,
            tab_width_cells: tab_width_cells.min(u32::MAX as usize) as u32,
            text_vertical_align: match self.render_config.text_vertical_align {
                crate::prelude::TextVerticalAlign::Top => "top",
                crate::prelude::TextVerticalAlign::Center => "center",
                crate::prelude::TextVerticalAlign::Bottom => "bottom",
            }
            .to_string(),
        }
    }

    pub(crate) fn record_layout_state_event_if_changed(
        &self,
        before_layout: EditorUiLayoutStateEvent,
    ) {
        let after_layout = self.layout_state();
        if before_layout.same_layout_as(&after_layout) {
            return;
        }
        let mut doc = self.lock_doc();
        doc.record_state_event_from_layout_changed(self.view_id, after_layout);
    }

    pub fn state_events_latest_sequence(&self) -> u64 {
        let doc = self.lock_doc();
        doc.state_events_latest_sequence()
    }

    pub fn state_events_after(&self, after_sequence: u64) -> EditorUiStateEventsSnapshot {
        let doc = self.lock_doc();
        doc.state_events_after(after_sequence)
    }

    pub fn state_events_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.state_events_after(after_sequence))
            .map_err(|e| UiError::Processor(e.to_string()))
    }

    pub(crate) fn record_lsp_status_state_event(&self) -> u64 {
        let status = self.lsp_status_value();
        let signature = lsp_status_event_signature(&status);
        let mut doc = self.lock_doc();
        doc.lsp_last_status_event_signature = Some(signature);
        doc.record_state_event_from_lsp_status_changed(self.view_id, status)
    }

    pub(crate) fn record_lsp_status_state_event_if_changed(&self) -> Option<u64> {
        let status = self.lsp_status_value();
        let signature = lsp_status_event_signature(&status);
        let mut doc = self.lock_doc();
        if doc.lsp_last_status_event_signature.as_deref() == Some(signature.as_str()) {
            return None;
        }
        doc.lsp_last_status_event_signature = Some(signature);
        Some(doc.record_state_event_from_lsp_status_changed(self.view_id, status))
    }

    pub(crate) fn fail_lsp_and_record_status(&self, reason: impl Into<String>) -> u64 {
        {
            let mut doc = self.lock_doc();
            doc.lsp_fail(reason.into());
        }
        self.record_lsp_status_state_event()
    }
}
