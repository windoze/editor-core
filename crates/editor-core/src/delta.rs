//! Structured text change deltas.
//!
//! `editor-core` historically exposed state changes as a coarse event
//! ([`crate::StateChangeType::DocumentModified`]) plus a best-effort affected region.
//! For a full-featured editor, incremental consumers (LSP sync, incremental parsing, indexing,
//! match highlighting, etc.) typically need **structured edits** without diffing old/new text.
//!
//! This module defines a small, UI-agnostic delta format expressed in **character offsets**
//! (Unicode scalar values).

/// A single text edit expressed in character offsets.
///
/// Semantics:
/// - `start` is a character offset in the document **at the time this edit is applied**.
/// - The deleted range is defined by the length (in `char`s) of `deleted_text`.
/// - Edits inside a [`TextDelta`] must be applied **in order** to transform the "before" document
///   into the "after" document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextDeltaEdit {
    /// Start character offset of the edit.
    pub start: usize,
    /// Exact deleted text (may be empty).
    pub deleted_text: String,
    /// Exact inserted text (may be empty).
    pub inserted_text: String,
}

impl TextDeltaEdit {
    /// Length of `deleted_text` in characters.
    pub fn deleted_len(&self) -> usize {
        self.deleted_text.chars().count()
    }

    /// Length of `inserted_text` in characters.
    pub fn inserted_len(&self) -> usize {
        self.inserted_text.chars().count()
    }

    /// Exclusive end character offset in the pre-edit document.
    pub fn end(&self) -> usize {
        self.start.saturating_add(self.deleted_len())
    }
}

/// A structured description of a document text change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextDelta {
    /// Character count before applying `edits`.
    pub before_char_count: usize,
    /// Character count after applying `edits`.
    pub after_char_count: usize,
    /// Ordered list of edits that transforms the "before" document into the "after" document.
    pub edits: Vec<TextDeltaEdit>,
    /// If known, the undo group id associated with this change.
    pub undo_group_id: Option<usize>,
}

impl TextDelta {
    /// Returns `true` if this delta contains no edits.
    pub fn is_empty(&self) -> bool {
        self.edits.is_empty()
    }
}
