//! Sublime Text `.sublime-syntax` support.
//!
//! This module implements a lightweight syntax-highlighting + folding engine
//! based on Sublime Text's YAML-based syntax definitions.

mod compiler;
mod definition;
mod engine;
mod error;
mod scope;
mod set;

pub use compiler::{
    CompiledContext, CompiledIncludePattern, CompiledMatchPattern, CompiledPattern, ContextPush,
    ContextSpec, MatchAction, SublimeSyntax,
};
pub use definition::{
    CaptureSpec, ClearScopes, ContextReference, Extends, MatchPattern, MetaPattern, PopAction,
    RawContextPattern, SyntaxDefinition,
};
pub use engine::{SublimeHighlightResult, highlight_document};
pub use error::SublimeSyntaxError;
pub use scope::SublimeScopeMapper;
pub use set::SublimeSyntaxSet;
