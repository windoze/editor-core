use crate::{EditorLspRequestEvent, EditorLspResultEvent, EditorUi, EditorUiDoc, UiError};

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
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorUiStateEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<EditorUiStateEvent>,
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
        })
    }

    fn record_state_event(&mut self, mut event: EditorUiStateEvent) -> u64 {
        let sequence = self.next_state_event_sequence;
        self.next_state_event_sequence = self.next_state_event_sequence.saturating_add(1);
        event.sequence = sequence;
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
