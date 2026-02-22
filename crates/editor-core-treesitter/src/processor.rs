use editor_core::delta::TextDelta;
use editor_core::intervals::{FoldRegion, Interval, StyleId, StyleLayerId};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::{EditorStateManager, LineIndex};
use std::collections::BTreeMap;
use streaming_iterator::StreamingIterator;
use tree_sitter::{InputEdit, Parser, Point, Query, QueryCursor, Tree};

/// Errors produced by [`TreeSitterProcessor`].
#[derive(Debug)]
pub enum TreeSitterError {
    /// Setting the Tree-sitter language failed.
    Language(String),
    /// Compiling a Tree-sitter query failed.
    Query(String),
    /// Internal text synchronization failed (the delta did not match the expected text).
    DeltaMismatch,
}

impl std::fmt::Display for TreeSitterError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Language(msg) => write!(f, "tree-sitter language error: {msg}"),
            Self::Query(msg) => write!(f, "tree-sitter query error: {msg}"),
            Self::DeltaMismatch => write!(f, "tree-sitter delta mismatch"),
        }
    }
}

impl std::error::Error for TreeSitterError {}

/// How the processor updated its parse tree for the last `process()` call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TreeSitterUpdateMode {
    /// First parse for this processor instance.
    Initial,
    /// Updated by applying `TextDelta` edits and re-parsing incrementally.
    Incremental,
    /// Fell back to re-syncing from full text and re-parsing.
    FullReparse,
    /// No work was performed (the processor already handled this editor version).
    Skipped,
}

/// Configuration for [`TreeSitterProcessor`].
#[derive(Debug, Clone)]
pub struct TreeSitterProcessorConfig {
    /// Tree-sitter language.
    pub language: tree_sitter::Language,
    /// Syntax highlighting query (`.scm`).
    pub highlights_query: String,
    /// Optional folding query (`.scm`). Each capture becomes a fold candidate.
    pub folds_query: Option<String>,
    /// Mapping from capture name (e.g. `"comment"`) to an `editor-core` `StyleId`.
    pub capture_styles: BTreeMap<String, StyleId>,
    /// Target style layer id to replace.
    pub style_layer: StyleLayerId,
    /// Whether to preserve the collapsed state for existing fold regions on replacement.
    pub preserve_collapsed_folds: bool,
}

impl TreeSitterProcessorConfig {
    /// Create a config with a language + highlights query.
    ///
    /// By default:
    /// - `style_layer` is [`StyleLayerId::TREE_SITTER`]
    /// - `preserve_collapsed_folds` is `true`
    pub fn new(language: tree_sitter::Language, highlights_query: impl Into<String>) -> Self {
        Self {
            language,
            highlights_query: highlights_query.into(),
            folds_query: None,
            capture_styles: BTreeMap::new(),
            style_layer: StyleLayerId::TREE_SITTER,
            preserve_collapsed_folds: true,
        }
    }

    /// Set a folding query.
    pub fn with_folds_query(mut self, folds_query: impl Into<String>) -> Self {
        self.folds_query = Some(folds_query.into());
        self
    }

    /// A small fold query that works well for Rust-like curly-brace languages.
    pub fn with_default_rust_folds(self) -> Self {
        self.with_folds_query(
            r#"
            (function_item) @fold
            (impl_item) @fold
            (struct_item) @fold
            (enum_item) @fold
            (mod_item) @fold
            (block) @fold
            "#,
        )
    }

    /// Add a set of capture name → style id mappings.
    pub fn with_simple_capture_styles<const N: usize>(
        mut self,
        styles: [(&'static str, StyleId); N],
    ) -> Self {
        for (name, style_id) in styles {
            self.capture_styles.insert(name.to_string(), style_id);
        }
        self
    }

    /// Control whether fold replacement preserves collapsed state.
    pub fn set_preserve_collapsed_folds(&mut self, preserve: bool) {
        self.preserve_collapsed_folds = preserve;
    }
}

/// An incremental Tree-sitter based document processor.
///
/// This processor tracks a parse tree and updates it based on `TextDelta` edits when available.
/// It then produces highlighting and folding edits in `editor-core`'s derived-state format.
pub struct TreeSitterProcessor {
    config: TreeSitterProcessorConfig,
    parser: Parser,
    highlight_query: Query,
    highlight_capture_styles: Vec<Option<StyleId>>,
    fold_query: Option<Query>,
    tree: Option<Tree>,
    text: String,
    line_index: LineIndex,
    last_processed_version: Option<u64>,
    last_update_mode: TreeSitterUpdateMode,
}

impl TreeSitterProcessor {
    /// Create a new processor from the given config.
    pub fn new(config: TreeSitterProcessorConfig) -> Result<Self, TreeSitterError> {
        let mut parser = Parser::new();
        parser
            .set_language(&config.language)
            .map_err(|e| TreeSitterError::Language(e.to_string()))?;

        let highlight_query = Query::new(&config.language, &config.highlights_query)
            .map_err(|e| TreeSitterError::Query(e.to_string()))?;
        let highlight_capture_styles = highlight_query
            .capture_names()
            .iter()
            .map(|name| config.capture_styles.get(*name).copied())
            .collect::<Vec<_>>();

        let fold_query = match config.folds_query.as_deref() {
            Some(q) if !q.trim().is_empty() => Some(
                Query::new(&config.language, q)
                    .map_err(|e| TreeSitterError::Query(e.to_string()))?,
            ),
            _ => None,
        };

        Ok(Self {
            config,
            parser,
            highlight_query,
            highlight_capture_styles,
            fold_query,
            tree: None,
            text: String::new(),
            line_index: LineIndex::new(),
            last_processed_version: None,
            last_update_mode: TreeSitterUpdateMode::FullReparse,
        })
    }

    /// Get the last update mode (useful for tests and instrumentation).
    pub fn last_update_mode(&self) -> TreeSitterUpdateMode {
        self.last_update_mode
    }

    fn sync_from_state_full(&mut self, state: &EditorStateManager) {
        self.text = state.editor().get_text();
        self.line_index = LineIndex::from_text(&self.text);
    }

    fn point_for_char_offset(&self, char_offset: usize) -> Point {
        let (row, col) = self.line_index.char_offset_to_line_byte_column(char_offset);
        Point { row, column: col }
    }

    fn advance_point(mut point: Point, text: &str) -> Point {
        let mut parts = text.split('\n');
        let Some(first) = parts.next() else {
            return point;
        };

        point.column = point.column.saturating_add(first.len());
        for part in parts {
            point.row = point.row.saturating_add(1);
            point.column = part.len();
        }

        point
    }

    fn apply_text_delta_incremental(&mut self, delta: &TextDelta) -> Result<(), TreeSitterError> {
        if self.line_index.char_count() != delta.before_char_count {
            return Err(TreeSitterError::DeltaMismatch);
        }
        if self.tree.is_none() {
            return Err(TreeSitterError::DeltaMismatch);
        }

        for edit in &delta.edits {
            let start_char = edit.start;
            let deleted_chars = edit.deleted_text.chars().count();

            let start_byte = self.line_index.char_offset_to_byte_offset(start_char);
            let old_end_byte = start_byte.saturating_add(edit.deleted_text.len());
            let new_end_byte = start_byte.saturating_add(edit.inserted_text.len());

            let Some(old_slice) = self.text.get(start_byte..old_end_byte) else {
                return Err(TreeSitterError::DeltaMismatch);
            };
            if old_slice != edit.deleted_text {
                return Err(TreeSitterError::DeltaMismatch);
            }

            let start_position = self.point_for_char_offset(start_char);
            let old_end_position = Self::advance_point(start_position, &edit.deleted_text);
            let new_end_position = Self::advance_point(start_position, &edit.inserted_text);

            if let Some(tree) = self.tree.as_mut() {
                tree.edit(&InputEdit {
                    start_byte,
                    old_end_byte,
                    new_end_byte,
                    start_position,
                    old_end_position,
                    new_end_position,
                });
            }

            self.text
                .replace_range(start_byte..old_end_byte, &edit.inserted_text);
            self.line_index.delete(start_char, deleted_chars);
            self.line_index.insert(start_char, &edit.inserted_text);
        }

        if self.line_index.char_count() != delta.after_char_count {
            return Err(TreeSitterError::DeltaMismatch);
        }

        Ok(())
    }

    fn parse(&mut self) -> Option<Tree> {
        self.parser.parse(&self.text, self.tree.as_ref())
    }

    fn collect_highlight_intervals(&self, tree: &Tree) -> Vec<Interval> {
        let mut cursor = QueryCursor::new();
        let root = tree.root_node();
        let mut out = Vec::<Interval>::new();

        let mut matches = cursor.matches(&self.highlight_query, root, self.text.as_bytes());
        while let Some(m) = matches.next() {
            for capture in m.captures {
                let idx = capture.index as usize;
                let Some(style_id) = self.highlight_capture_styles.get(idx).and_then(|x| *x) else {
                    continue;
                };

                let node = capture.node;
                let start_byte = node.start_byte();
                let end_byte = node.end_byte();
                if end_byte <= start_byte {
                    continue;
                }

                let start = self.line_index.byte_offset_to_char_offset(start_byte);
                let end = self.line_index.byte_offset_to_char_offset(end_byte);
                if end <= start {
                    continue;
                }

                out.push(Interval::new(start, end, style_id));
            }
        }

        out.sort_by_key(|i| (i.start, i.end, i.style_id));
        out.dedup_by(|a, b| a.start == b.start && a.end == b.end && a.style_id == b.style_id);
        out
    }

    fn collect_fold_regions(&self, tree: &Tree) -> Vec<FoldRegion> {
        let Some(query) = self.fold_query.as_ref() else {
            return Vec::new();
        };

        let mut cursor = QueryCursor::new();
        let root = tree.root_node();
        let mut regions = Vec::<FoldRegion>::new();

        let mut matches = cursor.matches(query, root, self.text.as_bytes());
        while let Some(m) = matches.next() {
            for capture in m.captures {
                let node = capture.node;
                let start_line = node.start_position().row;
                let end_line = node.end_position().row;
                if end_line > start_line {
                    regions.push(FoldRegion::new(start_line, end_line));
                }
            }
        }

        regions.sort_by_key(|r| (r.start_line, r.end_line));
        regions.dedup_by(|a, b| a.start_line == b.start_line && a.end_line == b.end_line);
        regions
    }
}

impl DocumentProcessor for TreeSitterProcessor {
    type Error = TreeSitterError;

    fn process(&mut self, state: &EditorStateManager) -> Result<Vec<ProcessingEdit>, Self::Error> {
        let version = state.version();
        if self.last_processed_version == Some(version) {
            self.last_update_mode = TreeSitterUpdateMode::Skipped;
            return Ok(Vec::new());
        }

        let update_mode = if self.tree.is_none() {
            self.sync_from_state_full(state);
            self.tree = self.parse();
            TreeSitterUpdateMode::Initial
        } else if let Some(delta) = state.last_text_delta() {
            match self.apply_text_delta_incremental(delta) {
                Ok(()) => {
                    self.tree = self.parse();
                    TreeSitterUpdateMode::Incremental
                }
                Err(_) => {
                    self.sync_from_state_full(state);
                    self.tree = self.parser.parse(&self.text, None);
                    TreeSitterUpdateMode::FullReparse
                }
            }
        } else {
            self.sync_from_state_full(state);
            self.tree = self.parser.parse(&self.text, None);
            TreeSitterUpdateMode::FullReparse
        };

        let Some(tree) = self.tree.as_ref() else {
            self.last_processed_version = Some(version);
            self.last_update_mode = update_mode;
            return Ok(Vec::new());
        };

        let intervals = self.collect_highlight_intervals(tree);
        let fold_regions = self.collect_fold_regions(tree);

        let mut edits = vec![ProcessingEdit::ReplaceStyleLayer {
            layer: self.config.style_layer,
            intervals,
        }];

        if self.fold_query.is_some() {
            edits.push(ProcessingEdit::ReplaceFoldingRegions {
                regions: fold_regions,
                preserve_collapsed: self.config.preserve_collapsed_folds,
            });
        }

        self.last_processed_version = Some(version);
        self.last_update_mode = update_mode;
        Ok(edits)
    }
}
