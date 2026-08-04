use crate::state::EditorUiDoc;

use super::*;

pub(super) struct TreeSitterPoll {
    pub(super) pending: bool,
    pub(super) latest_to_apply: Option<(u64, Vec<ProcessingEdit>, TreeSitterUpdateMode)>,
}

pub(super) fn poll_treesitter_worker(
    doc: &mut EditorUiDoc,
    prefetch_char_range: Option<(usize, usize)>,
) -> Result<TreeSitterPoll, UiError> {
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
        request_treesitter_full_sync(doc, prefetch_char_range)?;
    }

    let (requested, pending) = {
        let Some(worker) = doc.treesitter.as_ref() else {
            return Err(UiError::Processor(
                "tree-sitter worker missing after processing poll".to_string(),
            ));
        };
        (worker.requested_version, worker.is_pending())
    };

    let latest_to_apply = latest.and_then(|(version, edits, update_mode)| {
        if requested.is_some_and(|requested| version < requested) {
            None
        } else {
            Some((version, edits, update_mode))
        }
    });

    Ok(TreeSitterPoll {
        pending,
        latest_to_apply,
    })
}

fn request_treesitter_full_sync(
    doc: &mut EditorUiDoc,
    prefetch_char_range: Option<(usize, usize)>,
) -> Result<(), UiError> {
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
        .map_err(|_| UiError::Processor("failed to full-sync tree-sitter worker".to_string()))
}
