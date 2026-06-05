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
use crate::lsp_events::{LspEvent, LspNotification, LspServerRequestMode, LspServerRequestPolicy};
use crate::lsp_sync::{DeltaCalculator, LspCoordinateConverter, LspPosition, LspRange, TextChange};
use crate::lsp_text_edits::{LspTextEdit, char_offsets_for_lsp_range, workspace_edit_text_edits};
use editor_core::{BufferId, LineIndex, TextDelta, TextEditSpec, Workspace};
use serde_json::Value;
use std::collections::HashMap;

const WORKSPACE_APPLY_EDIT_METHOD: &str = "workspace/applyEdit";

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
    queued_events: Vec<LspEvent>,
    auto_apply_workspace_edits: bool,
}

impl LspWorkspaceSync {
    /// Start a new LSP session and initialize sync state for its initial document.
    pub fn start(opts: LspSessionStartOptions) -> std::io::Result<Self> {
        let initial_uri = opts.document.uri.clone();
        let initial_text = opts.initial_text.clone();
        let mut session = LspSession::start(opts)?;
        ensure_workspace_apply_edit_is_deferred(&mut session);

        let mut calculators = HashMap::new();
        calculators.insert(initial_uri, DeltaCalculator::from_text(&initial_text));

        Ok(Self {
            session,
            calculators,
            queued_events: Vec::new(),
            auto_apply_workspace_edits: true,
        })
    }

    /// Wrap an already-started session.
    ///
    /// Note: this does not automatically initialize per-document sync calculators; callers should
    /// populate them via [`LspWorkspaceSync::open_workspace_document`] (or by re-creating the sync
    /// wrapper with [`LspWorkspaceSync::start`]).
    pub fn new(session: LspSession) -> Self {
        let mut session = session;
        ensure_workspace_apply_edit_is_deferred(&mut session);
        Self {
            session,
            calculators: HashMap::new(),
            queued_events: Vec::new(),
            auto_apply_workspace_edits: true,
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

    /// Drain queued LSP events that were not handled by this sync wrapper.
    pub fn drain_events(&mut self) -> Vec<LspEvent> {
        std::mem::take(&mut self.queued_events)
    }

    /// Enable/disable automatic application of server->client `workspace/applyEdit` requests.
    ///
    /// - When enabled (default), `poll_workspace()` will apply the edit into the workspace and
    ///   respond `applied: true/false`.
    /// - When disabled, `workspace/applyEdit` requests are forwarded into [`Self::drain_events`]
    ///   and must be responded to by the host.
    pub fn set_auto_apply_workspace_edits(&mut self, enabled: bool) {
        self.auto_apply_workspace_edits = enabled;
    }

    fn uri_for_workspace_buffer(workspace: &Workspace, id: BufferId) -> Result<String, String> {
        workspace
            .buffer_metadata(id)
            .and_then(|m| m.uri.clone())
            .ok_or_else(|| format!("Workspace buffer has no uri (id={})", id.get()))
    }

    /// Ensure the given workspace buffer is open/tracked by the LSP session.
    pub fn open_workspace_document(
        &mut self,
        workspace: &Workspace,
        id: BufferId,
        language_id: impl Into<String>,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_buffer(workspace, id)?;
        let text = workspace
            .buffer_text(id)
            .map_err(|err| format!("Workspace buffer not found (id={}): {:?}", id.get(), err))?;

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

    /// Close a workspace buffer in the LSP session (if tracked).
    pub fn close_workspace_document(
        &mut self,
        workspace: &Workspace,
        id: BufferId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_buffer(workspace, id)?;
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
        id: BufferId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_buffer(workspace, id)?;
        self.session.set_active_document(&uri)
    }

    /// Poll the LSP connection and apply derived-state updates into the workspace.
    ///
    /// - Applies semantic tokens / folding / diagnostics edits into the *active* document.
    /// - Routes `publishDiagnostics` for non-active documents by looking them up by uri.
    pub fn poll_workspace(&mut self, workspace: &mut Workspace) -> Result<(), String> {
        let Some(active_id) = workspace.active_buffer_id() else {
            // Still poll the connection to drain events, but we have no document to apply edits to.
            let dummy = LineIndex::from_text("");
            let _ = self
                .session
                .poll_edits_with_line_index_and_handler(&dummy, |_| {});
            self.drain_and_handle_session_events(workspace)?;
            return Ok(());
        };

        let active_uri = Self::uri_for_workspace_buffer(workspace, active_id)?;
        if self.session.document().uri != active_uri {
            self.session.set_active_document(&active_uri)?;
        }

        let mut publish_diags = Vec::new();
        let active_text = workspace.buffer_text(active_id).map_err(|err| {
            format!(
                "Workspace active buffer not found (id={}): {:?}",
                active_id.get(),
                err
            )
        })?;
        let active_line_index = LineIndex::from_text(&active_text);

        let edits = self.session.poll_edits_with_line_index_and_handlers(
            &active_line_index,
            |_| {},
            |notification| {
                if let LspNotification::PublishDiagnostics(diags) = notification {
                    publish_diags.push(diags.clone());
                }
            },
        )?;

        workspace
            .apply_processing_edits(active_id, edits)
            .map_err(|err| format!("apply processing edits 失败: {:?}", err))?;

        // Route diagnostics for other documents.
        for diags in publish_diags {
            if diags.uri == active_uri {
                continue;
            }
            if !self.session.diagnostics_version_matches(&diags) {
                continue;
            }
            let Some(id) = workspace.buffer_id_for_uri(&diags.uri) else {
                continue;
            };

            let text = workspace.buffer_text(id).map_err(|err| {
                format!("Workspace buffer not found (id={}): {:?}", id.get(), err)
            })?;
            let line_index = LineIndex::from_text(&text);
            let edits = crate::editor::lsp_diagnostics_to_processing_edits(&line_index, &diags);
            workspace
                .apply_processing_edits(id, edits)
                .map_err(|err| format!("apply diagnostics edits 失败: {:?}", err))?;
        }

        self.drain_and_handle_session_events(workspace)?;
        Ok(())
    }

    fn drain_and_handle_session_events(&mut self, workspace: &mut Workspace) -> Result<(), String> {
        let events = self.session.drain_events();
        for event in events {
            match event {
                LspEvent::DeferredRequest(request)
                    if request.method.as_str() == WORKSPACE_APPLY_EDIT_METHOD =>
                {
                    if !self.auto_apply_workspace_edits {
                        self.queued_events.push(LspEvent::DeferredRequest(request));
                        continue;
                    }

                    let workspace_edit = request.params.get("edit").cloned().unwrap_or(Value::Null);
                    let response = match self.apply_workspace_edit(workspace, &workspace_edit) {
                        Ok(result) => workspace_apply_edit_response(&result),
                        Err(err) => serde_json::json!({
                            "applied": false,
                            "failureReason": err,
                        }),
                    };

                    self.session
                        .respond_to_server_request(request.id, response)?;
                }
                other => self.queued_events.push(other),
            }
        }
        Ok(())
    }

    /// Send `textDocument/didChange` for a workspace document, based on its last `TextDelta`.
    pub fn did_change_from_text_delta(
        &mut self,
        workspace: &mut Workspace,
        id: BufferId,
    ) -> Result<(), String> {
        let uri = Self::uri_for_workspace_buffer(workspace, id)?;

        let Some(delta) = workspace
            .take_last_text_delta_for_buffer(id)
            .map_err(|err| format!("Workspace buffer not found (id={}): {:?}", id.get(), err))?
        else {
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
        let result = apply_workspace_edit_to_workspace(workspace, workspace_edit)?;

        // Keep our incremental calculators in sync with the applied edit.
        for doc in &result.applied {
            if let Some(calc) = self.calculators.get_mut(&doc.uri) {
                for change in &doc.lsp_changes {
                    calc.apply_change(&TextChange {
                        range: change.range,
                        text: change.text.clone(),
                    });
                }
            }
        }

        Ok(result)
    }
}

/// Apply an LSP `WorkspaceEdit` to all matching open documents in the workspace.
///
/// This is a best-effort helper:
/// - text edits are applied for any `uri` that is already open in the workspace
/// - unknown URIs are reported in [`ApplyWorkspaceEditResult::skipped_uris`]
pub fn apply_workspace_edit_to_workspace(
    workspace: &mut Workspace,
    workspace_edit: &Value,
) -> Result<ApplyWorkspaceEditResult, String> {
    let by_uri = workspace_edit_text_edits(workspace_edit);
    let mut entries = by_uri.into_iter().collect::<Vec<_>>();
    entries.sort_by(|(a, _), (b, _)| a.cmp(b));

    let mut applied = Vec::<AppliedWorkspaceEditDocument>::new();
    let mut skipped = Vec::<String>::new();

    for (uri, edits) in entries {
        let Some(id) = workspace.buffer_id_for_uri(&uri) else {
            skipped.push(uri);
            continue;
        };
        let text = workspace
            .buffer_text(id)
            .map_err(|err| format!("Workspace buffer not found (id={}): {:?}", id.get(), err))?;
        let line_index = LineIndex::from_text(&text);

        let lsp_changes = lsp_changes_for_text_edits(&line_index, &edits);

        let mut specs: Vec<TextEditSpec> = edits
            .iter()
            .map(|edit| {
                let (start, end) = char_offsets_for_lsp_range(&line_index, &edit.range);
                TextEditSpec {
                    start,
                    end,
                    text: edit.new_text.clone(),
                }
            })
            .collect();
        let mut changed_char_ranges: Vec<(usize, usize)> =
            specs.iter().map(|e| (e.start, e.end)).collect();

        // Match the application order (descending start offsets) for highlighting stability.
        changed_char_ranges.sort_by_key(|(start, _)| std::cmp::Reverse(*start));
        specs.sort_by_key(|e| std::cmp::Reverse(e.start));

        workspace
            .apply_text_edits(vec![(id, specs)])
            .map_err(|err| format!("apply workspace edit 失败: {:?}", err))?;

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

fn ensure_workspace_apply_edit_is_deferred(session: &mut LspSession) {
    let mut policy = session.server_request_policy().clone();

    match policy.mode {
        LspServerRequestMode::AutoReply => {
            policy = LspServerRequestPolicy::defer_listed([WORKSPACE_APPLY_EDIT_METHOD]);
        }
        LspServerRequestMode::DeferAll => {}
        LspServerRequestMode::DeferListed => {
            if !policy
                .deferred_methods
                .iter()
                .any(|m| m == WORKSPACE_APPLY_EDIT_METHOD)
            {
                policy
                    .deferred_methods
                    .push(WORKSPACE_APPLY_EDIT_METHOD.to_string());
            }
        }
    }

    session.set_server_request_policy(policy);
}

/// Build a JSON result payload for responding to server->client `workspace/applyEdit`.
pub fn workspace_apply_edit_response(result: &ApplyWorkspaceEditResult) -> Value {
    if result.skipped_uris.is_empty() {
        serde_json::json!({ "applied": true })
    } else {
        let reason = format!(
            "Skipped edits for {} unopened document(s): {}",
            result.skipped_uris.len(),
            result.skipped_uris.join(", ")
        );
        serde_json::json!({
            "applied": false,
            "failureReason": reason,
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
    line_index: &LineIndex,
    edits: &[LspTextEdit],
) -> Vec<LspContentChange> {
    let mut resolved = edits
        .iter()
        .map(|edit| {
            let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
            (start, end, edit)
        })
        .collect::<Vec<_>>();

    // Match the application order of `apply_text_edits` (descending start offsets).
    resolved.sort_by_key(|(start, _, _)| std::cmp::Reverse(*start));

    resolved
        .into_iter()
        .map(|(start, end, edit)| LspContentChange {
            range: lsp_range_for_char_offsets(line_index, start, end),
            text: edit.new_text.clone(),
        })
        .collect()
}

fn lsp_range_for_char_offsets(line_index: &LineIndex, start: usize, end: usize) -> LspRange {
    fn position_for_offset(line_index: &LineIndex, offset: usize) -> LspPosition {
        let (line, char_in_line) = line_index.char_offset_to_position(offset);
        let line_text = line_index.get_line_text(line).unwrap_or_default();
        LspCoordinateConverter::position_to_lsp(&line_text, line, char_in_line)
    }

    LspRange::new(
        position_for_offset(line_index, start),
        position_for_offset(line_index, end),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{
        Command, CursorCommand, EditCommand, EditorStateManager, Position, Selection,
        SelectionDirection, Workspace,
    };
    use serde_json::Value;

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

    #[test]
    fn test_apply_workspace_edit_to_workspace_and_build_apply_edit_response() {
        let mut ws = Workspace::new();

        let opened_a = ws
            .open_buffer(Some("file:///a".to_string()), "abc\n", 80)
            .unwrap();
        let opened_b = ws
            .open_buffer(Some("file:///b".to_string()), "xyz\n", 80)
            .unwrap();

        let edit_json = include_str!("../tests/fixtures/workspace_apply_edit_params_v1.json");
        let workspace_edit: Value = serde_json::from_str(edit_json).expect("fixture parse");

        let result = apply_workspace_edit_to_workspace(&mut ws, &workspace_edit).unwrap();

        assert_eq!(ws.buffer_text(opened_a.buffer_id).unwrap(), "ABc\n");
        assert_eq!(ws.buffer_text(opened_b.buffer_id).unwrap(), "xyz!\n");
        assert_eq!(result.skipped_uris, vec!["file:///c".to_string()]);

        // Changed ranges are returned in descending start-offset order for UI stability.
        let a_doc = result
            .applied
            .iter()
            .find(|d| d.uri == "file:///a")
            .expect("a doc");
        assert_eq!(a_doc.changed_char_ranges, vec![(1, 2), (0, 1)]);
        assert_eq!(a_doc.lsp_changes.len(), 2);

        let response = workspace_apply_edit_response(&result);
        assert_eq!(
            response.get("applied").and_then(Value::as_bool),
            Some(false)
        );
        assert!(
            response
                .get("failureReason")
                .and_then(Value::as_str)
                .unwrap_or("")
                .contains("file:///c")
        );
    }

    #[test]
    fn test_workspace_apply_edit_response_when_nothing_is_skipped() {
        let result = ApplyWorkspaceEditResult {
            applied: Vec::new(),
            skipped_uris: Vec::new(),
        };
        let response = workspace_apply_edit_response(&result);
        assert_eq!(response.get("applied").and_then(Value::as_bool), Some(true));
        assert!(response.get("failureReason").is_none());
    }
}
