use super::*;

mod tree_sitter;

use tree_sitter::poll_treesitter_worker;

impl EditorUi {
    pub fn poll_processing(&mut self) -> Result<ProcessingPollResult, UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let (treesitter_pending, latest_to_apply) = {
            let mut doc = self.lock_doc();
            if doc.treesitter.is_none() {
                drop(doc);
                let lsp_applied = self.poll_lsp_best_effort()?;
                return Ok(ProcessingPollResult {
                    applied: lsp_applied,
                    pending: self.lsp_is_enabled(),
                });
            }

            let poll = poll_treesitter_worker(&mut doc, prefetch_char_range)?;
            (poll.pending, poll.latest_to_apply)
        };

        let mut treesitter_applied = false;
        if let Some((version, edits, update_mode)) = latest_to_apply {
            {
                let mut doc = self.lock_doc();
                doc.apply_processing_edits(edits)?;
                if let Some(worker) = doc.treesitter.as_mut() {
                    worker.applied_version = Some(version);
                    worker.last_update_mode = Some(update_mode);
                }
            }
            treesitter_applied = true;
        }

        let lsp_applied = self.poll_lsp_best_effort()?;

        Ok(ProcessingPollResult {
            applied: treesitter_applied || lsp_applied,
            pending: treesitter_pending || self.lsp_is_enabled(),
        })
    }
}
