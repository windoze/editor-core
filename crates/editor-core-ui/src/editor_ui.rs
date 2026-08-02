mod appearance_search;
mod commands;
mod coordinates;
mod document;
mod editing;
mod exports;
mod lifecycle;
mod lsp;
mod markers;
mod processing;
mod rendering;
mod selection;
mod syntax;
mod viewport;

use super::*;

impl EditorUi {
    pub(crate) fn lock_doc(&self) -> std::sync::MutexGuard<'_, EditorUiDoc> {
        self.doc.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn with_line_index<R>(
        &self,
        f: impl FnOnce(&editor_core::LineIndex) -> R,
    ) -> Result<R, UiError> {
        let doc = self.lock_doc();
        let line_index = doc
            .ws
            .buffer_line_index(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        Ok(f(line_index))
    }

    fn exec_core(&mut self, command: Command) -> Result<CommandResult, UiError> {
        let mut doc = self.lock_doc();
        let is_edit = matches!(command, Command::Edit(_));
        let tracks_selection = matches!(command, Command::Edit(_) | Command::Cursor(_));
        let tracks_viewport = matches!(
            command,
            Command::Edit(_)
                | Command::View(
                    ViewCommand::SetViewportWidth { .. }
                        | ViewCommand::SetWrapMode { .. }
                        | ViewCommand::SetWrapIndent { .. }
                        | ViewCommand::SetTabWidth { .. }
                        | ViewCommand::ScrollTo { .. },
                )
                | Command::Style(
                    StyleCommand::Fold { .. }
                        | StyleCommand::Unfold { .. }
                        | StyleCommand::UnfoldAll,
                )
        );
        let before_modified = is_edit
            .then(|| doc.ws.is_modified_for_view(self.view_id).unwrap_or(false))
            .unwrap_or(false);
        let before_selection = tracks_selection
            .then(|| doc.selection_state_for_view(self.view_id))
            .flatten();
        let before_viewport = tracks_viewport
            .then(|| doc.viewport_state_for_view(self.view_id))
            .flatten();
        let result = doc.exec_core(self.view_id, command.clone())?;
        if is_edit {
            let after_modified = doc.ws.is_modified_for_view(self.view_id).unwrap_or(false);
            if before_modified != after_modified {
                doc.record_state_event_from_dirty_changed(self.view_id, after_modified);
            }
        }
        if tracks_selection {
            let after_selection = doc.selection_state_for_view(self.view_id);
            let selection_changed = match (&before_selection, &after_selection) {
                (Some(before), Some(after)) => !before.same_selection_as(after),
                (None, None) => false,
                _ => true,
            };
            if selection_changed && let Some(selection) = after_selection {
                doc.record_state_event_from_selection_changed(self.view_id, selection);
            }
        }
        if tracks_viewport {
            let after_viewport = doc.viewport_state_for_view(self.view_id);
            let viewport_changed = match (&before_viewport, &after_viewport) {
                (Some(before), Some(after)) => !before.same_viewport_as(after),
                (None, None) => false,
                _ => true,
            };
            if viewport_changed && let Some(viewport) = after_viewport {
                doc.record_state_event_from_viewport_changed(self.view_id, viewport);
            }
        }

        if self.bracket_match_highlights_enabled {
            match command {
                Command::Edit(_) | Command::Cursor(_) => {
                    let _ = doc.exec_core(
                        self.view_id,
                        Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                    );
                }
                Command::View(_) | Command::Style(_) => {}
            }
        }

        Ok(result)
    }

    fn apply_processing_edits<I>(&mut self, edits: I) -> Result<(), UiError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        let mut doc = self.lock_doc();
        doc.apply_processing_edits(edits)
    }
}
