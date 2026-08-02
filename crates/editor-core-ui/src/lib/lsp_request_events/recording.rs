use super::{
    EditorLspRequestEvent, EditorLspRequestEventPhase, EditorLspRequestEventStatus,
    EditorLspRequestEventsSnapshot,
};
use crate::prelude::*;
use crate::{EditorUiDoc, LspClientRequest, LspResultSlot};

const MAX_LSP_REQUEST_EVENTS: usize = 256;

impl EditorUiDoc {
    pub(crate) fn track_lsp_result_request(
        &mut self,
        view_id: ViewId,
        slot: LspResultSlot,
        request_id: u64,
    ) {
        self.lsp_client_requests.insert(
            request_id,
            LspClientRequest::Result {
                view: view_id,
                slot,
            },
        );
        self.lsp_latest_result_request_id
            .insert((view_id, slot), request_id);
        self.lsp_last_result_json.remove(&(view_id, slot));
        self.record_lsp_request_started(view_id, slot, request_id);
    }

    pub(crate) fn clear_lsp_in_flight_for_slot(&mut self, slot: LspResultSlot) {
        match slot {
            LspResultSlot::CodeLens => self.lsp_code_lens_in_flight = false,
            LspResultSlot::InlayHints => self.lsp_inlay_in_flight = false,
            LspResultSlot::DocumentLinks => self.lsp_document_links_in_flight = false,
            _ => {}
        }
    }

    pub(crate) fn record_lsp_request_started(
        &mut self,
        view_id: ViewId,
        slot: LspResultSlot,
        request_id: u64,
    ) {
        self.record_lsp_request_event(
            view_id,
            slot,
            request_id,
            EditorLspRequestEventPhase::Started,
            EditorLspRequestEventStatus::Pending,
            None,
            None,
        );
    }

    pub(crate) fn record_lsp_request_completed(
        &mut self,
        view_id: ViewId,
        slot: LspResultSlot,
        request_id: u64,
        status: EditorLspRequestEventStatus,
        result_sequence: Option<u64>,
        error: Option<&LspResponseError>,
    ) {
        self.record_lsp_request_event(
            view_id,
            slot,
            request_id,
            EditorLspRequestEventPhase::Completed,
            status,
            result_sequence,
            error,
        );
    }

    pub(crate) fn record_lsp_request_finished_without_response(
        &mut self,
        request_id: u64,
        status: EditorLspRequestEventStatus,
    ) -> bool {
        let (view, slot) = match self.lsp_client_requests.remove(&request_id) {
            Some(LspClientRequest::Result { view, slot }) => (view, slot),
            Some(LspClientRequest::OnTypeFormatting { view, .. }) => {
                (view, LspResultSlot::OnTypeFormatting)
            }
            None => return false,
        };

        match slot {
            LspResultSlot::OnTypeFormatting => {
                if self.lsp_latest_on_type_formatting_request_id.get(&view) == Some(&request_id) {
                    self.lsp_latest_on_type_formatting_request_id.remove(&view);
                }
            }
            _ => {
                if self.lsp_latest_result_request_id.get(&(view, slot)) == Some(&request_id) {
                    self.lsp_latest_result_request_id.remove(&(view, slot));
                }
                self.clear_lsp_in_flight_for_slot(slot);
            }
        }

        self.record_lsp_request_completed(view, slot, request_id, status, None, None);
        true
    }

    fn record_lsp_request_event(
        &mut self,
        view_id: ViewId,
        slot: LspResultSlot,
        request_id: u64,
        phase: EditorLspRequestEventPhase,
        status: EditorLspRequestEventStatus,
        result_sequence: Option<u64>,
        error: Option<&LspResponseError>,
    ) {
        let sequence = self.next_lsp_request_event_sequence;
        self.next_lsp_request_event_sequence =
            self.next_lsp_request_event_sequence.saturating_add(1);

        let event = EditorLspRequestEvent {
            sequence,
            family: slot.family().to_string(),
            title: format!("{}: {}", slot.title(), status.as_str()),
            slot: slot.slot_name().to_string(),
            method: slot.method().to_string(),
            view_id: view_id.get(),
            request_id,
            phase: phase.as_str().to_string(),
            status: status.as_str().to_string(),
            result_sequence,
            error_code: error.map(|err| err.code),
            error_message: error.map(|err| err.message.clone()),
        };
        self.lsp_request_events.push_back(event.clone());
        self.record_state_event_from_lsp_request(event);

        while self.lsp_request_events.len() > MAX_LSP_REQUEST_EVENTS {
            self.lsp_request_events.pop_front();
        }
    }

    pub(crate) fn lsp_request_events_latest_sequence(&self) -> u64 {
        self.next_lsp_request_event_sequence.saturating_sub(1)
    }

    pub(crate) fn lsp_request_events_after(
        &self,
        after_sequence: u64,
    ) -> EditorLspRequestEventsSnapshot {
        EditorLspRequestEventsSnapshot {
            latest_sequence: self.lsp_request_events_latest_sequence(),
            events: self
                .lsp_request_events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }
}
