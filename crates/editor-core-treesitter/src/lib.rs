#![warn(missing_docs)]
//! `editor-core-treesitter` - Tree-sitter integration for `editor-core`.
//!
//! This crate provides an offline incremental parsing pipeline that can produce:
//!
//! - highlight intervals (a style layer)
//! - fold regions (derived folding)
//!
//! Output is expressed as `editor_core::ProcessingEdit` values, so it composes with other derived
//! state producers like LSP or `.sublime-syntax`.

mod processor;

pub use processor::{TreeSitterProcessor, TreeSitterProcessorConfig, TreeSitterUpdateMode};
