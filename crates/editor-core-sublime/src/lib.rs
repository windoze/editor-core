#![warn(missing_docs)]
//! `editor-core-sublime` - Sublime Text `.sublime-syntax` support for `editor-core`.
//!
//! This crate contains a lightweight YAML-based syntax engine, plus optional helper APIs for
//! applying highlighting + folding results to an `editor_core::EditorStateManager`.

pub mod sublime_syntax;

mod processor;

pub use processor::SublimeProcessor;
pub use sublime_syntax::*;
