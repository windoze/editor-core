#![warn(missing_docs)]
//! `editor-core-lang` - data-driven language configuration helpers for `editor-core`.
//!
//! This crate intentionally stays lightweight and does **not** depend on `lsp-types` or any
//! parsing/highlighting systems. It provides small structs that hosts can use to configure
//! editor-kernel features in a language-aware way.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

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

/// A single auto-pair entry (opening + closing delimiter).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AutoPair {
    /// Opening delimiter.
    pub open: char,
    /// Closing delimiter.
    pub close: char,
}

impl AutoPair {
    /// Create a new auto-pair entry.
    pub const fn new(open: char, close: char) -> Self {
        Self { open, close }
    }
}

/// Auto-pairs configuration (auto-close, wrap selection, skip-over, delete-pair).
///
/// Notes:
/// - This mirrors `editor-core`'s auto-pairs behavior, but stays in this crate to avoid a cyclic
///   dependency (`editor-core` depends on `editor-core-lang`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AutoPairsConfig {
    /// Master enable switch for auto-pairs behaviors.
    pub enabled: bool,
    /// Configured delimiter pairs (order matters when overlapping; first match wins).
    pub pairs: Vec<AutoPair>,
    /// When typing an opening delimiter over a non-empty selection, wrap the selection.
    pub wrap_selection: bool,
    /// When typing a closing delimiter and the next character matches, skip over it instead of inserting.
    pub skip_over_closing: bool,
    /// When backspacing/deleting adjacent matching delimiters, delete both.
    pub delete_pair: bool,
}

impl Default for AutoPairsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            pairs: vec![
                AutoPair::new('(', ')'),
                AutoPair::new('[', ']'),
                AutoPair::new('{', '}'),
                AutoPair::new('"', '"'),
                AutoPair::new('\'', '\''),
                AutoPair::new('`', '`'),
            ],
            wrap_selection: true,
            skip_over_closing: true,
            delete_pair: true,
        }
    }
}

/// Identifier for a language configuration entry (e.g. `"rust"`, `"python"`).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct LanguageId(String);

impl LanguageId {
    /// Create a new language id.
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    /// Borrow the id as `&str`.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for LanguageId {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for LanguageId {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

/// How the language prefers indentation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IndentStyle {
    /// Use literal `\t` characters.
    Tabs,
    /// Use spaces, with the given per-indent width (e.g. 2 or 4).
    Spaces(u8),
}

impl Default for IndentStyle {
    fn default() -> Self {
        Self::Spaces(4)
    }
}

/// Indentation configuration for a language.
///
/// Notes:
/// - This is **configuration only**; applying language-aware indentation still depends on the
///   host/editor policy layer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IndentationConfig {
    /// Preferred indent style for this language.
    pub style: IndentStyle,

    /// Characters that typically introduce a new indentation level when they appear before an
    /// inserted newline (e.g. `{`, `:` in Python, etc.).
    pub indent_triggers: Vec<char>,

    /// Characters that typically decrease indentation (e.g. `}`, `]`, `)`).
    pub outdent_triggers: Vec<char>,
}

impl Default for IndentationConfig {
    fn default() -> Self {
        Self {
            style: IndentStyle::default(),
            indent_triggers: vec!['{', '[', '(', ':'],
            outdent_triggers: vec!['}', ']', ')'],
        }
    }
}

/// Word-boundary configuration for editor-friendly "word" operations.
///
/// This corresponds to `editor_core::WordBoundaryConfig::set_ascii_boundary_chars` (similar in
/// spirit to VSCode's `wordSeparators`).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WordBoundaryLanguageConfig {
    /// Override ASCII boundary characters (whitespace is always boundary).
    ///
    /// When `None`, hosts should keep editor-core defaults (identifier-like words).
    pub ascii_boundary_chars: Option<String>,
}

/// Tree-sitter configuration for a language.
///
/// This crate keeps this as **data only**:
/// - It does not depend on tree-sitter libraries.
/// - Hosts (or integration crates) decide how to resolve `query_pack_id` into actual `.scm` text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeSitterLanguageConfig {
    /// Tree-sitter grammar name (e.g. `"rust"`).
    pub grammar: String,

    /// Query pack id used to resolve highlights/folds queries (e.g. `"rust"`).
    pub query_pack_id: String,

    /// Whether the host should enable Tree-sitter for this language by default.
    pub enabled_by_default: bool,
}

/// LSP launch configuration for a language.
///
/// This is intentionally lightweight and does not embed `lsp-types` models.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspLanguageConfig {
    /// LSP `languageId` string (e.g. `"rust"`, `"python"`).
    pub language_id: String,
    /// LSP server command (e.g. `"rust-analyzer"`).
    pub command: String,
    /// Arguments passed to the LSP server (no shell quoting).
    pub args: Vec<String>,

    /// Workspace root detection markers. When any marker exists in an ancestor directory of the
    /// opened file, that directory becomes the LSP root.
    ///
    /// Markers can be files or directories (e.g. `"Cargo.toml"`, `".git"`).
    pub root_markers: Vec<String>,
}

impl LspLanguageConfig {
    /// Try to detect a workspace root directory for a given file path.
    ///
    /// Returns `None` when no configured markers were found.
    pub fn detect_root_dir(&self, file_path: &Path) -> Option<PathBuf> {
        let start_dir = if file_path.is_dir() {
            file_path
        } else {
            file_path.parent()?
        };
        self.detect_root_dir_from_dir(start_dir)
    }

    /// Try to detect a workspace root directory starting from a directory.
    ///
    /// Returns `None` when no configured markers were found.
    pub fn detect_root_dir_from_dir(&self, start_dir: &Path) -> Option<PathBuf> {
        let mut dir = start_dir.to_path_buf();
        loop {
            for marker in &self.root_markers {
                if dir.join(marker).exists() {
                    return Some(dir);
                }
            }
            if !dir.pop() {
                break;
            }
        }
        None
    }
}

/// Unified per-language configuration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LanguageConfig {
    /// Stable language id (e.g. `"rust"`).
    pub id: LanguageId,
    /// Human-friendly name (e.g. `"Rust"`).
    pub display_name: String,

    /// File extensions matched by this language (lowercase, without the leading dot).
    pub file_extensions: Vec<String>,
    /// Exact file names matched by this language (case-sensitive).
    pub file_names: Vec<String>,

    /// Comment tokens.
    pub comments: CommentConfig,
    /// Auto-pairs rules (typically applied via `EditCommand::TypeChar`).
    pub auto_pairs: AutoPairsConfig,
    /// Indentation preferences and trigger chars.
    pub indentation: IndentationConfig,
    /// Word boundary override (for word movement/selection).
    pub word_boundary: WordBoundaryLanguageConfig,

    /// Optional Tree-sitter config.
    pub treesitter: Option<TreeSitterLanguageConfig>,
    /// Optional LSP config.
    pub lsp: Option<LspLanguageConfig>,

    /// Free-form extra settings for hosts (UI-specific knobs, etc).
    ///
    /// This is intentionally not interpreted by the workspace crates.
    pub extra: BTreeMap<String, String>,
}

impl LanguageConfig {
    /// Create a minimal language config.
    pub fn new(id: impl Into<LanguageId>, display_name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            display_name: display_name.into(),
            file_extensions: Vec::new(),
            file_names: Vec::new(),
            comments: CommentConfig::default(),
            auto_pairs: AutoPairsConfig::default(),
            indentation: IndentationConfig::default(),
            word_boundary: WordBoundaryLanguageConfig::default(),
            treesitter: None,
            lsp: None,
            extra: BTreeMap::new(),
        }
    }

    /// Add a file extension match (without the leading dot).
    pub fn with_extension(mut self, ext: impl Into<String>) -> Self {
        self.file_extensions.push(ext.into());
        self
    }

    /// Add an exact file name match.
    pub fn with_file_name(mut self, name: impl Into<String>) -> Self {
        self.file_names.push(name.into());
        self
    }

    /// Returns `true` if this language config matches the given path (file name or extension).
    pub fn matches_path(&self, path: &Path) -> bool {
        if let Some(name) = path.file_name().and_then(|n| n.to_str())
            && self.file_names.iter().any(|x| x == name)
        {
            return true;
        }

        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            let ext = ext.to_ascii_lowercase();
            if self
                .file_extensions
                .iter()
                .any(|x| x.to_ascii_lowercase() == ext)
            {
                return true;
            }
        }

        false
    }
}

/// Error returned by [`LanguageRegistry::register`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LanguageRegistryError {
    /// A language with the same id is already registered.
    DuplicateLanguageId(String),
}

impl std::fmt::Display for LanguageRegistryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DuplicateLanguageId(id) => write!(f, "duplicate language id: {id}"),
        }
    }
}

impl std::error::Error for LanguageRegistryError {}

/// A lightweight in-memory registry of language configurations.
#[derive(Debug, Clone)]
pub struct LanguageRegistry {
    languages: Vec<LanguageConfig>,
}

impl LanguageRegistry {
    /// Create an empty registry.
    pub fn new() -> Self {
        Self {
            languages: Vec::new(),
        }
    }

    /// Register a language config.
    pub fn register(&mut self, lang: LanguageConfig) -> Result<(), LanguageRegistryError> {
        if self
            .languages
            .iter()
            .any(|l| l.id.as_str() == lang.id.as_str())
        {
            return Err(LanguageRegistryError::DuplicateLanguageId(
                lang.id.as_str().to_string(),
            ));
        }
        self.languages.push(lang);
        Ok(())
    }

    /// Return all registered languages.
    pub fn languages(&self) -> &[LanguageConfig] {
        &self.languages
    }

    /// Find a language config by its id.
    pub fn by_id(&self, id: &str) -> Option<&LanguageConfig> {
        self.languages.iter().find(|l| l.id.as_str() == id)
    }

    /// Find a language config for a file path.
    pub fn language_for_path(&self, path: &Path) -> Option<&LanguageConfig> {
        self.languages.iter().find(|l| l.matches_path(path))
    }
}

impl Default for LanguageConfig {
    fn default() -> Self {
        Self::new("plain-text", "Plain Text")
    }
}

impl Default for LanguageRegistry {
    fn default() -> Self {
        let mut reg = Self::new();

        // Rust.
        let mut rust = LanguageConfig::new("rust", "Rust").with_extension("rs");
        rust.comments = CommentConfig::line_and_block("//", "/*", "*/");
        rust.lsp = Some(LspLanguageConfig {
            language_id: "rust".to_string(),
            command: "rust-analyzer".to_string(),
            args: Vec::new(),
            root_markers: vec!["Cargo.toml".to_string(), ".git".to_string()],
        });
        rust.treesitter = Some(TreeSitterLanguageConfig {
            grammar: "rust".to_string(),
            query_pack_id: "rust".to_string(),
            enabled_by_default: true,
        });
        // Enable auto-pairs by default for code-like languages, but keep it disabled at the
        // kernel boundary unless the host chooses to enable it.
        rust.auto_pairs.enabled = true;
        let _ = reg.register(rust);

        // TOML.
        let mut toml = LanguageConfig::new("toml", "TOML").with_extension("toml");
        toml.file_names.push("Cargo.toml".to_string());
        toml.comments = CommentConfig::line("#");
        toml.auto_pairs.enabled = true;
        let _ = reg.register(toml);

        // Markdown.
        let mut md = LanguageConfig::new("markdown", "Markdown")
            .with_extension("md")
            .with_extension("markdown");
        md.comments = CommentConfig::block("<!--", "-->");
        md.auto_pairs.enabled = true;
        let _ = reg.register(md);

        // JSON (no native comments).
        let mut json = LanguageConfig::new("json", "JSON").with_extension("json");
        json.comments = CommentConfig::default();
        json.auto_pairs.enabled = true;
        let _ = reg.register(json);

        reg
    }
}
