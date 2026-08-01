mod derived_state;
mod on_type;
mod slot_results;

use super::super::super::*;
use derived_state::handle_lsp_derived_state_response;
use on_type::{apply_on_type_formatting_results, collect_on_type_formatting_result};
use slot_results::handle_lsp_result_slot_response;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum EventOutcome {
    Unhandled,
    Handled,
    Abort,
}

impl EditorUi {
    pub(crate) fn handle_lsp_events(&mut self, events: Vec<LspEvent>) -> Result<bool, UiError> {
        if events.is_empty() {
            return Ok(false);
        }

        let mut applied = false;
        // Avoid re-entrant locking: collect text edits while holding the doc lock and apply
        // them after releasing it.
        let mut on_type_formatting_results: Vec<serde_json::Value> = Vec::new();

        let mut doc = self.lock_doc();
        for ev in events {
            let LspEvent::Response(resp) = ev else {
                continue;
            };

            if let Some(slot) = LspResultSlot::from_response_method(resp.method.as_str()) {
                match handle_lsp_result_slot_response(&mut doc, &resp, slot, &mut applied)? {
                    EventOutcome::Handled => continue,
                    EventOutcome::Abort => return Ok(false),
                    EventOutcome::Unhandled => {}
                }
            }

            match handle_lsp_derived_state_response(&mut doc, &resp, &mut applied)? {
                EventOutcome::Handled => continue,
                EventOutcome::Abort => return Ok(false),
                EventOutcome::Unhandled => {}
            }

            match collect_on_type_formatting_result(
                &mut doc,
                &resp,
                &mut on_type_formatting_results,
            )? {
                EventOutcome::Handled => continue,
                EventOutcome::Abort => return Ok(false),
                EventOutcome::Unhandled => {}
            }
        }

        drop(doc);
        if !apply_on_type_formatting_results(self, on_type_formatting_results, &mut applied)? {
            return Ok(false);
        }

        Ok(applied)
    }
}
