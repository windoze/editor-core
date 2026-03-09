//! `editor-core-app` — UI-agnostic “editor application shell” primitives.
//!
//! This crate is intentionally **not** a GUI framework. It provides shared logic and data models
//! that typical editor frontends need on top of the `editor-core` kernel:
//!
//! - workspace filesystem traversal (file index, explorer tree helpers)
//! - fuzzy matching (command palette / quick-open building block)
//! - session/recents persistence helpers (optional “hot exit” style snapshots)
//!
//! The goal is to implement as much as possible once in Rust and reuse across platforms.

mod fuzzy;
mod workspace_index;

pub use fuzzy::FuzzyMatcher;
pub use workspace_index::{FileIndexEntry, WorkspaceFileIndex, WorkspaceFileIndexError};

