use super::{TabEntry, TabId};
use crate::EditorLspRequestEvent;
use std::collections::{BTreeMap, VecDeque};

const MAX_MULTI_DOCUMENT_LSP_REQUEST_EVENTS: usize = 512;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct MultiDocumentLspRequestEvent {
    pub sequence: u64,
    pub tab_id: u64,
    pub view_index: usize,
    pub view_id: u64,
    pub source_sequence: u64,
    pub source_result_sequence: Option<u64>,
    pub family: String,
    pub title: String,
    pub slot: String,
    pub method: String,
    pub request_id: u64,
    pub phase: String,
    pub status: String,
    pub error_code: Option<i64>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct MultiDocumentLspRequestEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<MultiDocumentLspRequestEvent>,
}

#[derive(Default)]
pub(crate) struct MultiDocumentLspRequestEventStore {
    next_sequence: u64,
    latest_source_sequence_by_tab_and_view: BTreeMap<(u64, u64), u64>,
    events: VecDeque<MultiDocumentLspRequestEvent>,
}

impl MultiDocumentLspRequestEventStore {
    pub(crate) fn refresh_from_tabs(
        &mut self,
        tabs: &BTreeMap<TabId, TabEntry>,
        tab_order: &[TabId],
    ) {
        if self.next_sequence == 0 {
            self.next_sequence = 1;
        }

        for tab_id in tab_order.iter().copied() {
            let Some(tab) = tabs.get(&tab_id) else {
                continue;
            };

            for (view_index, view) in tab.views.iter().enumerate() {
                let view_id = view.view_id.get();
                let source_key = (tab_id.get(), view_id);
                let after_sequence = self
                    .latest_source_sequence_by_tab_and_view
                    .get(&source_key)
                    .copied()
                    .unwrap_or(0);
                let source_snapshot = view.lsp_request_events_after(after_sequence);

                for event in source_snapshot
                    .events
                    .into_iter()
                    .filter(|event| event.view_id == view_id)
                {
                    self.push_event(tab_id, view_index, event);
                }

                self.latest_source_sequence_by_tab_and_view
                    .insert(source_key, source_snapshot.latest_sequence);
            }
        }
    }

    pub(crate) fn latest_sequence(&self) -> u64 {
        self.next_sequence.saturating_sub(1)
    }

    pub(crate) fn events_after(
        &self,
        after_sequence: u64,
    ) -> MultiDocumentLspRequestEventsSnapshot {
        MultiDocumentLspRequestEventsSnapshot {
            latest_sequence: self.latest_sequence(),
            events: self
                .events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }

    pub(crate) fn events_after_json(
        &self,
        after_sequence: u64,
    ) -> Result<String, serde_json::Error> {
        serde_json::to_string(&self.events_after(after_sequence))
    }

    fn push_event(&mut self, tab_id: TabId, view_index: usize, source: EditorLspRequestEvent) {
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.events.push_back(MultiDocumentLspRequestEvent {
            sequence,
            tab_id: tab_id.get(),
            view_index,
            view_id: source.view_id,
            source_sequence: source.sequence,
            source_result_sequence: source.result_sequence,
            family: source.family,
            title: source.title,
            slot: source.slot,
            method: source.method,
            request_id: source.request_id,
            phase: source.phase,
            status: source.status,
            error_code: source.error_code,
            error_message: source.error_message,
        });

        while self.events.len() > MAX_MULTI_DOCUMENT_LSP_REQUEST_EVENTS {
            self.events.pop_front();
        }
    }
}
