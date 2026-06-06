//! Width-dependent diff projection placeholders.

/// Diff projection mode placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffMode {}

/// Diff projection placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DiffProjection;

/// Diff projection row placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Row;

/// Diff projection row slot placeholder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowSlot {}
