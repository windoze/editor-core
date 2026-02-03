use crate::sublime_syntax::{
    SublimeHighlightResult, SublimeScopeMapper, SublimeSyntax, SublimeSyntaxError,
    SublimeSyntaxSet, highlight_document,
};
use editor_core::EditorStateManager;
use editor_core::intervals::StyleLayerId;
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use std::sync::Arc;

/// A stateful `.sublime-syntax` document processor.
///
/// This owns a [`SublimeScopeMapper`] so callers can map `StyleId -> scope` for theming.
#[derive(Debug)]
pub struct SublimeProcessor {
    syntax: Arc<SublimeSyntax>,
    syntax_set: SublimeSyntaxSet,
    /// Maps Sublime scopes to `StyleId` values (and back) for theming.
    pub scope_mapper: SublimeScopeMapper,
    preserve_collapsed_folds: bool,
}

impl SublimeProcessor {
    /// Create a new processor for a given syntax definition.
    pub fn new(syntax: Arc<SublimeSyntax>, syntax_set: SublimeSyntaxSet) -> Self {
        Self {
            syntax,
            syntax_set,
            scope_mapper: SublimeScopeMapper::new(),
            preserve_collapsed_folds: true,
        }
    }

    /// Get the active syntax definition.
    pub fn syntax(&self) -> &Arc<SublimeSyntax> {
        &self.syntax
    }

    /// Get the current syntax set (used to resolve `include` references).
    pub fn syntax_set(&self) -> &SublimeSyntaxSet {
        &self.syntax_set
    }

    /// Mutably access the current syntax set (used to add/update syntaxes).
    pub fn syntax_set_mut(&mut self) -> &mut SublimeSyntaxSet {
        &mut self.syntax_set
    }

    /// Returns whether fold replacement preserves the collapsed state for existing regions.
    pub fn preserve_collapsed_folds(&self) -> bool {
        self.preserve_collapsed_folds
    }

    /// Control whether fold replacement preserves the collapsed state for existing regions.
    pub fn set_preserve_collapsed_folds(&mut self, preserve: bool) {
        self.preserve_collapsed_folds = preserve;
    }

    fn highlight(
        &mut self,
        state: &EditorStateManager,
    ) -> Result<SublimeHighlightResult, SublimeSyntaxError> {
        let line_index = &state.editor().line_index;
        highlight_document(
            self.syntax.clone(),
            line_index,
            Some(&mut self.syntax_set),
            &mut self.scope_mapper,
        )
    }
}

impl DocumentProcessor for SublimeProcessor {
    type Error = SublimeSyntaxError;

    fn process(&mut self, state: &EditorStateManager) -> Result<Vec<ProcessingEdit>, Self::Error> {
        let result = self.highlight(state)?;
        Ok(vec![
            ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::SUBLIME_SYNTAX,
                intervals: result.intervals,
            },
            ProcessingEdit::ReplaceFoldingRegions {
                regions: result.fold_regions,
                preserve_collapsed: self.preserve_collapsed_folds,
            },
        ])
    }
}
