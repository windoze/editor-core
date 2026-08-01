use super::*;

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

            let mut latest: Option<(u64, Vec<ProcessingEdit>, TreeSitterUpdateMode)> = None;
            let mut need_full_sync = false;

            loop {
                let ev = {
                    let Some(worker) = doc.treesitter.as_mut() else {
                        return Err(UiError::Processor(
                            "tree-sitter worker missing during processing poll".to_string(),
                        ));
                    };
                    worker.rx.try_recv()
                };
                match ev {
                    Ok(TreeSitterWorkerEvent::Processed {
                        version,
                        edits,
                        update_mode,
                    }) => {
                        latest = Some((version, edits, update_mode));
                    }
                    Ok(TreeSitterWorkerEvent::NeedFullSync) => {
                        need_full_sync = true;
                    }
                    Ok(TreeSitterWorkerEvent::Error(msg)) => {
                        return Err(UiError::Processor(format!(
                            "tree-sitter worker error: {msg}"
                        )));
                    }
                    Err(mpsc::TryRecvError::Empty) => break,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        return Err(UiError::Processor(
                            "tree-sitter worker disconnected".to_string(),
                        ));
                    }
                }
            }

            if need_full_sync {
                let text = doc
                    .ws
                    .buffer_text(doc.buffer_id)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?;
                doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
                let version = doc.treesitter_doc_version;
                let Some(worker) = doc.treesitter.as_mut() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing during full sync".to_string(),
                    ));
                };
                worker.requested_version = Some(version);
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::FullSync {
                        version,
                        text,
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to full-sync tree-sitter worker".to_string())
                    })?;
            }

            let (requested, pending) = {
                let Some(worker) = doc.treesitter.as_ref() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing after processing poll".to_string(),
                    ));
                };
                (worker.requested_version, worker.is_pending())
            };

            let to_apply = latest.and_then(|(version, edits, update_mode)| {
                if requested.is_some_and(|requested| version < requested) {
                    None
                } else {
                    Some((version, edits, update_mode))
                }
            });

            (pending, to_apply)
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

    pub fn treesitter_last_update_mode(&self) -> Option<TreeSitterUpdateMode> {
        let doc = self.lock_doc();
        doc.treesitter.as_ref().and_then(|w| w.last_update_mode)
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .capture_for_style_id(style_id)
            .map(|s| s.to_string())
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        let mut doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .style_id_for_capture(capture_name)
    }
}
