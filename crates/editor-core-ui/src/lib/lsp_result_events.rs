use super::*;

const MAX_LSP_RESULT_EVENTS: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorLspResultEvent {
    pub sequence: u64,
    pub family: String,
    pub title: String,
    pub slot: String,
    pub method: String,
    pub view_id: u64,
    pub request_id: u64,
    pub status: String,
    pub has_result: bool,
    pub result_json_len: usize,
    pub error_code: Option<i64>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorLspResultEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<EditorLspResultEvent>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EditorLspResultEventStatus {
    Success,
    Empty,
    Error,
}

impl EditorLspResultEventStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::Empty => "empty",
            Self::Error => "error",
        }
    }
}

impl EditorUiDoc {
    pub(crate) fn record_lsp_result_event(
        &mut self,
        view_id: ViewId,
        slot: LspResultSlot,
        request_id: u64,
        status: EditorLspResultEventStatus,
        result_json_len: usize,
        error: Option<&LspResponseError>,
    ) {
        let sequence = self.next_lsp_result_event_sequence;
        self.next_lsp_result_event_sequence = self.next_lsp_result_event_sequence.saturating_add(1);

        self.lsp_result_events.push_back(EditorLspResultEvent {
            sequence,
            family: slot.family().to_string(),
            title: format!("{}: {}", slot.title(), status.as_str()),
            slot: slot.slot_name().to_string(),
            method: slot.method().to_string(),
            view_id: view_id.get(),
            request_id,
            status: status.as_str().to_string(),
            has_result: result_json_len > 0,
            result_json_len,
            error_code: error.map(|err| err.code),
            error_message: error.map(|err| err.message.clone()),
        });

        while self.lsp_result_events.len() > MAX_LSP_RESULT_EVENTS {
            self.lsp_result_events.pop_front();
        }
    }

    pub(crate) fn lsp_result_events_latest_sequence(&self) -> u64 {
        self.next_lsp_result_event_sequence.saturating_sub(1)
    }

    pub(crate) fn lsp_result_events_after(
        &self,
        after_sequence: u64,
    ) -> EditorLspResultEventsSnapshot {
        EditorLspResultEventsSnapshot {
            latest_sequence: self.lsp_result_events_latest_sequence(),
            events: self
                .lsp_result_events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }
}
