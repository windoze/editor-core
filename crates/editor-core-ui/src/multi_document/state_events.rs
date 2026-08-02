use super::{TabEntry, TabId};
use crate::EditorUiStateEvent;
use std::collections::{BTreeMap, VecDeque};

const MAX_MULTI_DOCUMENT_STATE_EVENTS: usize = 1024;

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct MultiDocumentStateEvent {
    pub sequence: u64,
    pub tab_id: u64,
    pub view_index: usize,
    pub view_id: u64,
    pub source_sequence: u64,
    pub kind: String,
    pub family: String,
    pub title: String,
    pub state_event: EditorUiStateEvent,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct MultiDocumentStateEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<MultiDocumentStateEvent>,
}

#[derive(Default)]
pub(crate) struct MultiDocumentStateEventStore {
    next_sequence: u64,
    latest_source_sequence_by_tab_and_view: BTreeMap<(u64, u64), u64>,
    events: VecDeque<MultiDocumentStateEvent>,
}

impl MultiDocumentStateEventStore {
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
                let source_snapshot = view.state_events_after(after_sequence);

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

    pub(crate) fn events_after(&self, after_sequence: u64) -> MultiDocumentStateEventsSnapshot {
        MultiDocumentStateEventsSnapshot {
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

    fn push_event(&mut self, tab_id: TabId, view_index: usize, source: EditorUiStateEvent) {
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.events.push_back(MultiDocumentStateEvent {
            sequence,
            tab_id: tab_id.get(),
            view_index,
            view_id: source.view_id,
            source_sequence: source.sequence,
            kind: source.kind.clone(),
            family: source.family.clone(),
            title: source.title.clone(),
            state_event: source,
        });

        while self.events.len() > MAX_MULTI_DOCUMENT_STATE_EVENTS {
            self.events.pop_front();
        }
    }
}
