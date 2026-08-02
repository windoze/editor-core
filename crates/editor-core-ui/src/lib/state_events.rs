use crate::{EditorLspRequestEvent, EditorLspResultEvent, EditorUi, EditorUiDoc, UiError, ViewId};

const MAX_EDITOR_UI_STATE_EVENTS: usize = 512;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
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
    pub text: Option<EditorUiTextStateEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dirty: Option<EditorUiDirtyStateEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
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
            text: None,
            dirty: None,
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
            text: None,
            dirty: None,
        })
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
            text: Some(EditorUiTextStateEvent {
                text_version: self.text_version,
                char_len,
                is_modified,
            }),
            dirty: None,
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
            text: None,
            dirty: Some(EditorUiDirtyStateEvent { is_modified }),
        })
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
}
