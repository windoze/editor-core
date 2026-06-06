//! Width-independent diff-view model placeholders.

/// A side document participating in a diff view.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SideDoc;

/// Width-independent diff model placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DiffModel;

/// Logical-line alignment unit placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlignUnit {}
