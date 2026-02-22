#![warn(missing_docs)]
//! `editor-core-lang` - data-driven language configuration helpers for `editor-core`.
//!
//! This crate intentionally stays lightweight and does **not** depend on `lsp-types` or any
//! parsing/highlighting systems. It provides small structs that hosts can use to configure
//! editor-kernel features in a language-aware way.

/// Comment tokens/config for a given language.
///
/// The editor kernel can use this to implement comment toggling in a UI-agnostic way.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CommentConfig {
    /// Line comment token (e.g. `//`, `#`).
    pub line: Option<String>,
    /// Block comment start token (e.g. `/*`).
    pub block_start: Option<String>,
    /// Block comment end token (e.g. `*/`).
    pub block_end: Option<String>,
}

impl CommentConfig {
    /// Create a config that supports only line comments.
    pub fn line(token: impl Into<String>) -> Self {
        Self {
            line: Some(token.into()),
            block_start: None,
            block_end: None,
        }
    }

    /// Create a config that supports only block comments.
    pub fn block(start: impl Into<String>, end: impl Into<String>) -> Self {
        Self {
            line: None,
            block_start: Some(start.into()),
            block_end: Some(end.into()),
        }
    }

    /// Create a config that supports both line and block comments.
    pub fn line_and_block(
        line: impl Into<String>,
        block_start: impl Into<String>,
        block_end: impl Into<String>,
    ) -> Self {
        Self {
            line: Some(line.into()),
            block_start: Some(block_start.into()),
            block_end: Some(block_end.into()),
        }
    }

    /// Returns `true` if a line comment token is configured.
    pub fn has_line(&self) -> bool {
        self.line.as_deref().is_some_and(|s| !s.is_empty())
    }

    /// Returns `true` if both block comment tokens are configured.
    pub fn has_block(&self) -> bool {
        self.block_start.as_deref().is_some_and(|s| !s.is_empty())
            && self.block_end.as_deref().is_some_and(|s| !s.is_empty())
    }
}
