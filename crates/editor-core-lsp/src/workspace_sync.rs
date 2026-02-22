//! Multi-document LSP synchronization helpers.
//!
//! `editor-core-lsp` exposes a low-level [`crate::editor::LspSession`] that can track multiple
//! documents by URI. For full editors, it is useful to integrate that with the kernel's
//! multi-document [`editor_core::Workspace`] so:
//!
//! - local edits can be turned into `didChange` notifications per document
//! - server `publishDiagnostics` can be routed into the correct document's derived state
//! - `WorkspaceEdit` payloads can be applied across multiple open documents

use crate::editor::{LspContentChange, LspDocument, LspSession, LspSessionStartOptions};
use crate::lsp_events::LspNotification;
use crate::lsp_sync::{DeltaCalculator, TextChange};
use crate::lsp_text_edits::{
    LspTextEdit, apply_text_edits, char_offsets_for_lsp_range, workspace_edit_text_edits,
};
use editor_core::{DocumentId, EditorStateManager, TextDelta, Workspace};
use serde_json::Value;
use std::collections::HashMap;

/// Result of applying a `WorkspaceEdit` to a set of open documents.
#[derive(Debug, Clone)]
pub struct ApplyWorkspaceEditResult {
    /// Documents that were successfully edited.
    pub applied: Vec<AppliedWorkspaceEditDocument>,
    /// URIs that had edits but were not open in the workspace.
    pub skipped_uris: Vec<String>,
}

/// Per-document result for applying a `WorkspaceEdit`.
#[derive(Debug, Clone)]
pub struct AppliedWorkspaceEditDocument {
    /// Document URI.
    pub uri: String,
    /// Changed (start,end) ranges in pre-edit character offsets (useful for UI highlighting).
    pub changed_char_ranges: Vec<(usize, usize)>,
    /// Equivalent LSP `didChange` changes that were applied.
    pub lsp_changes: Vec<LspContentChange>,
}

/// A small helper that wires an [`LspSession`] to an [`editor_core::Workspace`].
pub struct LspWorkspaceSync {
    session: LspSession,
    calculators: HashMap<String, DeltaCalculator>,
}

impl LspWorkspaceSync {
    /// Start a new LSP session and initialize sync state for its initial document.
    pub fn start(opts: LspSessionStartOptions) -> std::io::Result<Self> {
        let initial_uri = opts.document.uri.clone();
        let initial_text = opts.initial_text.clone();
        let session = LspSession::start(opts)?;

        let mut calculators = HashMap::new();
        calculators.insert(initial_uri, DeltaCalculator::from_text(&initial_text));

        Ok(Self {
            session,
            calculators,
        })
    }

    /// Wrap an already-started session.
    ///
    /// Note: this does not automatically initialize per-document sync calculators; callers should
    /// populate them via [`LspWorkspaceSync::open_workspace_document`] (or by re-creating the sync
    /// wrapper with [`LspWorkspaceSync::start`]).
    pub fn new(session: LspSession) -> Self {
        Self {
            session,
            calculators: HashMap::new(),
        }
    }

    /// Get a reference to the underlying session.
    pub fn session(&self) -> &LspSession {
        &self.session
    }

    /// Get a mutable reference to the underlying session.
    pub fn session_mut(&mut self) -> &mut LspSession {
        &mut self.session
    }

    fn uri_for_workspace_document(workspace: &Workspace, id: DocumentId) -> Result<String, String> {
        workspace
            .document_metadata(id)
            .and_then(|m| m.uri.clone())
            .ok_or_else(|| format!("Workspace document has no uri (id={})", id.get()))
    }

    /// Ensure the given workspace document is open/tracked by the LSP session.
    pub fn open_workspace_document(
        &mut self,
        workspace: &Workspace,
        id: DocumentId,
        language_id: impl Into<String>,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_document(workspace, id)?;
        let Some(state) = workspace.document(id) else {
            return Err(format!("Workspace document not found (id={})", id.get()));
        };
        let text = state.editor().get_text();

        if self.session.document_for_uri(&uri).is_none() {
            self.session.open_document(
                LspDocument {
                    uri: uri.clone(),
                    language_id: language_id.into(),
                    version: 0,
                },
                text.clone(),
            )?;
        }

        self.calculators
            .insert(uri.clone(), DeltaCalculator::from_text(&text));

        Ok(())
    }

    /// Close a workspace document in the LSP session (if tracked).
    pub fn close_workspace_document(
        &mut self,
        workspace: &Workspace,
        id: DocumentId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_document(workspace, id)?;
        if self.session.document_for_uri(&uri).is_some() {
            self.session.close_document(&uri)?;
        }
        self.calculators.remove(&uri);
        Ok(())
    }

    /// Set the active document in the underlying LSP session based on workspace state.
    pub fn set_active_workspace_document(
        &mut self,
        workspace: &Workspace,
        id: DocumentId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_document(workspace, id)?;
        self.session.set_active_document(&uri)
    }

    /// Poll the LSP connection and apply derived-state updates into the workspace.
    ///
    /// - Applies semantic tokens / folding / diagnostics edits into the *active* document.
    /// - Routes `publishDiagnostics` for non-active documents by looking them up by uri.
    pub fn poll_workspace(&mut self, workspace: &mut Workspace) -> Result<(), String> {
        let Some(active_id) = workspace.active_document_id() else {
            // Still poll the connection to drain events, but we have no document to apply edits to.
            let _ = self
                .session
                .poll_edits_with_handler(&EditorStateManager::empty(1), |_| {});
            return Ok(());
        };

        let active_uri = Self::uri_for_workspace_document(workspace, active_id)?;
        if self.session.document().uri != active_uri {
            self.session.set_active_document(&active_uri)?;
        }

        let mut publish_diags = Vec::new();
        let edits = {
            let Some(active_state) = workspace.document(active_id) else {
                return Err(format!(
                    "Workspace active document not found (id={})",
                    active_id.get()
                ));
            };
            self.session.poll_edits_with_handlers(
                active_state,
                |_| {},
                |notification| {
                    if let LspNotification::PublishDiagnostics(diags) = notification {
                        publish_diags.push(diags.clone());
                    }
                },
            )?
        };

        if let Some(active_state) = workspace.document_mut(active_id) {
            active_state.apply_processing_edits(edits);
        }

        // Route diagnostics for other documents.
        for diags in publish_diags {
            if diags.uri == active_uri {
                continue;
            }
            let Some(id) = workspace.document_id_for_uri(&diags.uri) else {
                continue;
            };
            let Some(state) = workspace.document_mut(id) else {
                continue;
            };
            let line_index = &state.editor().line_index;
            let edits = crate::editor::lsp_diagnostics_to_processing_edits(line_index, &diags);
            state.apply_processing_edits(edits);
        }

        Ok(())
    }

    /// Send `textDocument/didChange` for a workspace document, based on its last `TextDelta`.
    pub fn did_change_from_text_delta(
        &mut self,
        workspace: &mut Workspace,
        id: DocumentId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_document(workspace, id)?;

        let Some(state) = workspace.document_mut(id) else {
            return Err(format!("Workspace document not found (id={})", id.get()));
        };

        let Some(delta) = state.take_last_text_delta() else {
            return Ok(());
        };

        let Some(calc) = self.calculators.get_mut(&uri) else {
            return Err(format!(
                "LSP delta calculator not initialized for uri={}",
                uri
            ));
        };

        let changes = text_changes_for_text_delta(calc, &delta);
        let content_changes = changes
            .into_iter()
            .map(|c| LspContentChange {
                range: c.range,
                text: c.text,
            })
            .collect::<Vec<_>>();

        self.session.did_change_for_uri_many(&uri, content_changes)
    }

    /// Apply an LSP `WorkspaceEdit` to all matching open documents in the workspace.
    ///
    /// This is a best-effort helper:
    /// - text edits are applied for any `uri` that is already open in the workspace
    /// - unknown URIs are reported in [`ApplyWorkspaceEditResult::skipped_uris`]
    pub fn apply_workspace_edit(
        &mut self,
        workspace: &mut Workspace,
        workspace_edit: &Value,
    ) -> Result<ApplyWorkspaceEditResult, String> {
        let by_uri = workspace_edit_text_edits(workspace_edit);

        let mut applied = Vec::<AppliedWorkspaceEditDocument>::new();
        let mut skipped = Vec::<String>::new();

        for (uri, edits) in by_uri {
            let Some(id) = workspace.document_id_for_uri(&uri) else {
                skipped.push(uri);
                continue;
            };
            let Some(state) = workspace.document_mut(id) else {
                skipped.push(uri);
                continue;
            };

            let lsp_changes = lsp_changes_for_text_edits(state, &edits);
            let changed_char_ranges = apply_text_edits(state, &edits)?;

            // Keep our incremental calculator in sync with the applied edit.
            if let Some(calc) = self.calculators.get_mut(&uri) {
                for change in &lsp_changes {
                    calc.apply_change(&TextChange {
                        range: change.range,
                        text: change.text.clone(),
                    });
                }
            }

            applied.push(AppliedWorkspaceEditDocument {
                uri,
                changed_char_ranges,
                lsp_changes,
            });
        }

        Ok(ApplyWorkspaceEditResult {
            applied,
            skipped_uris: skipped,
        })
    }
}

fn position_for_char_offset(calc: &DeltaCalculator, mut offset: usize) -> (usize, usize) {
    let line_count = calc.line_count().max(1);
    for line in 0..line_count {
        let text = calc.get_line(line).unwrap_or("");
        let len = text.chars().count();
        if offset <= len {
            return (line, offset);
        }
        offset = offset.saturating_sub(len + 1);
    }

    // Clamp to end-of-document.
    let last_line = line_count.saturating_sub(1);
    let last_len = calc.get_line(last_line).unwrap_or("").chars().count();
    (last_line, last_len)
}

fn text_changes_for_text_delta(calc: &mut DeltaCalculator, delta: &TextDelta) -> Vec<TextChange> {
    let mut out = Vec::<TextChange>::with_capacity(delta.edits.len());

    for edit in &delta.edits {
        let (start_line, start_char) = position_for_char_offset(calc, edit.start);
        let (end_line, end_char) = position_for_char_offset(calc, edit.end());
        let change = calc.calculate_replace_change(
            start_line,
            start_char,
            end_line,
            end_char,
            edit.inserted_text.as_str(),
        );
        calc.apply_change(&change);
        out.push(change);
    }

    out
}

fn lsp_changes_for_text_edits(
    state: &EditorStateManager,
    edits: &[LspTextEdit],
) -> Vec<LspContentChange> {
    let line_index = &state.editor().line_index;
    let mut resolved = edits
        .iter()
        .map(|edit| {
            let (start, _) = char_offsets_for_lsp_range(line_index, &edit.range);
            (start, edit)
        })
        .collect::<Vec<_>>();

    // Match the application order of `apply_text_edits` (descending start offsets).
    resolved.sort_by_key(|(start, _)| std::cmp::Reverse(*start));

    resolved
        .into_iter()
        .map(|(_, edit)| LspContentChange {
            range: edit.range,
            text: edit.new_text.clone(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{
        Command, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
    };

    fn calc_text(calc: &DeltaCalculator) -> String {
        let mut lines = Vec::new();
        for i in 0..calc.line_count() {
            lines.push(calc.get_line(i).unwrap_or("").to_string());
        }
        lines.join("\n")
    }

    #[test]
    fn test_text_delta_to_text_changes_multi_caret_insert() {
        let mut manager = EditorStateManager::new("a\nb\nc", 80);
        let before = manager.editor().get_text();

        let selections = vec![
            Selection {
                start: Position::new(0, 0),
                end: Position::new(0, 0),
                direction: SelectionDirection::Forward,
            },
            Selection {
                start: Position::new(1, 0),
                end: Position::new(1, 0),
                direction: SelectionDirection::Forward,
            },
            Selection {
                start: Position::new(2, 0),
                end: Position::new(2, 0),
                direction: SelectionDirection::Forward,
            },
        ];

        manager
            .execute(Command::Cursor(CursorCommand::SetSelections {
                selections,
                primary_index: 0,
            }))
            .unwrap();

        manager
            .execute(Command::Edit(EditCommand::InsertText {
                text: "X".to_string(),
            }))
            .unwrap();

        let after = manager.editor().get_text();
        let delta = manager.take_last_text_delta().expect("delta");

        let mut calc = DeltaCalculator::from_text(&before);
        let changes = text_changes_for_text_delta(&mut calc, &delta);
        assert_eq!(changes.len(), 3);

        // Delta ordering is descending offsets, so line numbers should also be descending here.
        let lines: Vec<u32> = changes.iter().map(|c| c.range.start.line).collect();
        assert_eq!(lines, vec![2, 1, 0]);

        assert_eq!(calc_text(&calc), after);
    }
}
