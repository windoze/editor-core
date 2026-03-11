use crate::{TreeSitterError, TreeSitterLanguage};
use editor_core::{IndentStyle, LineIndex, TextEditSpec};
use std::collections::HashSet;
use streaming_iterator::StreamingIterator;
use tree_sitter::{Parser, Query, QueryCursor, Tree};

/// Configuration for [`TreeSitterIndenter`].
#[derive(Debug, Clone)]
pub struct TreeSitterIndenterConfig {
    /// Tree-sitter language source (native or WASM).
    pub language: TreeSitterLanguage,
    /// Indentation query (`indents.scm`).
    pub indents_query: String,
}

impl TreeSitterIndenterConfig {
    /// Create a config from a language source and query text.
    pub fn new(language: TreeSitterLanguage, indents_query: impl Into<String>) -> Self {
        Self {
            language,
            indents_query: indents_query.into(),
        }
    }
}

/// A small Tree-sitter powered indenter driven by an `indents.scm` query.
///
/// This is an **optional** companion to [`crate::TreeSitterProcessor`]:
/// - The processor focuses on derived state (highlighting/folding).
/// - The indenter focuses on edit-time indentation decisions (auto-indent on newline).
///
/// Query conventions (minimal subset):
/// - Captures named `@indent` indicate syntax nodes that increase indentation for their contents.
/// - Captures named `@outdent` indicate syntax tokens/nodes that outdent when they begin a line.
///
/// Notes:
/// - This implementation is intentionally conservative; it aims to provide a solid baseline.
pub struct TreeSitterIndenter {
    config: TreeSitterIndenterConfig,
    parser: Parser,
    indent_query: Query,
    tree: Option<Tree>,
    text: String,
    line_index: LineIndex,
    last_synced_version: Option<u64>,
    // Keep the Wasmtime engine alive for the lifetime of the parser's Wasm store.
    #[allow(dead_code)]
    wasm_engine: Option<tree_sitter::wasmtime::Engine>,
}

impl TreeSitterIndenter {
    /// Create a new indenter from the given config.
    pub fn new(config: TreeSitterIndenterConfig) -> Result<Self, TreeSitterError> {
        let mut parser = Parser::new();

        let (language, wasm_engine) = match &config.language {
            TreeSitterLanguage::Native(language) => {
                parser
                    .set_language(language)
                    .map_err(|e| TreeSitterError::Language(e.to_string()))?;
                (language.clone(), None)
            }
            TreeSitterLanguage::Wasm {
                language_id,
                wasm_bytes,
            } => {
                let engine = tree_sitter::wasmtime::Engine::default();

                // Parser store (must use the same engine as the language).
                let store = tree_sitter::WasmStore::new(&engine)
                    .map_err(|e| TreeSitterError::Wasm(e.to_string()))?;
                parser
                    .set_wasm_store(store)
                    .map_err(|e| TreeSitterError::Language(e.to_string()))?;

                // Load the language (can use a separate store, but must share the same engine).
                let mut store = tree_sitter::WasmStore::new(&engine)
                    .map_err(|e| TreeSitterError::Wasm(e.to_string()))?;
                let language = store
                    .load_language(language_id, wasm_bytes)
                    .map_err(|e| TreeSitterError::Wasm(e.to_string()))?;

                parser
                    .set_language(&language)
                    .map_err(|e| TreeSitterError::Language(e.to_string()))?;

                (language, Some(engine))
            }
        };

        let indent_query = Query::new(&language, &config.indents_query)
            .map_err(|e| TreeSitterError::Query(e.to_string()))?;

        Ok(Self {
            config,
            parser,
            indent_query,
            tree: None,
            text: String::new(),
            line_index: LineIndex::new(),
            last_synced_version: None,
            wasm_engine,
        })
    }

    /// Synchronize the indenter with the given editor `version` and full `text`.
    ///
    /// Notes:
    /// - This API is intentionally "full text" based (no `TextDelta` required), to make it easy
    ///   to drive from UI/FFI boundaries.
    /// - Re-parsing is skipped when `version` is unchanged.
    pub fn sync_to_text(&mut self, version: u64, text: &str) -> Result<(), TreeSitterError> {
        if self.last_synced_version == Some(version) {
            return Ok(());
        }

        self.text.clear();
        self.text.push_str(text);
        self.line_index = LineIndex::from_text(&self.text);

        self.tree = self.parser.parse(&self.text, None);
        if self.tree.is_none() {
            return Err(TreeSitterError::Language(
                "tree-sitter parse returned None".to_string(),
            ));
        }

        self.last_synced_version = Some(version);
        Ok(())
    }

    fn is_indent_capture(name: &str) -> bool {
        name == "indent" || name.starts_with("indent.")
    }

    fn is_outdent_capture(name: &str) -> bool {
        name == "outdent" || name.starts_with("outdent.") || name == "dedent"
    }

    fn indent_unit(indent_style: IndentStyle) -> String {
        match indent_style {
            IndentStyle::Tabs => "\t".to_string(),
            IndentStyle::Spaces(width) => " ".repeat(width.max(1) as usize),
        }
    }

    /// Compute the desired leading whitespace for a logical line.
    ///
    /// Returns `None` if the indenter is not yet synchronized (call [`Self::sync_to_text`] first),
    /// or if `line` is out of range.
    pub fn indent_string_for_line(&self, line: usize, indent_style: IndentStyle) -> Option<String> {
        let tree = self.tree.as_ref()?;
        let line_text = self.line_index.get_line_text(line)?;

        let line_start_char = self.line_index.position_to_char_offset(line, 0);
        let line_start_byte = self.line_index.char_offset_to_byte_offset(line_start_char);

        // Use the *next line start* as the end bound when possible so empty lines still have
        // a non-empty search range (include the newline byte).
        let line_end_byte = if line + 1 < self.line_index.line_count() {
            let next_line_start_char = self.line_index.position_to_char_offset(line + 1, 0);
            self.line_index
                .char_offset_to_byte_offset(next_line_start_char)
        } else {
            self.text.len()
        };

        let leading_ws_bytes = line_text
            .bytes()
            .take_while(|b| *b == b' ' || *b == b'\t')
            .count();

        let mut cursor = QueryCursor::new();
        if line_end_byte > line_start_byte {
            cursor.set_byte_range(line_start_byte..line_end_byte);
        }

        let root = tree.root_node();
        let capture_names = self.indent_query.capture_names();

        let mut indent_nodes: HashSet<(usize, usize)> = HashSet::new();
        let mut indent_count = 0usize;
        let mut should_outdent = false;

        let mut matches = cursor.matches(&self.indent_query, root, self.text.as_bytes());
        while let Some(m) = matches.next() {
            for capture in m.captures {
                let name = capture_names
                    .get(capture.index as usize)
                    .copied()
                    .unwrap_or("");
                let node = capture.node;

                if Self::is_indent_capture(name) {
                    // De-dupe by node byte range to avoid double-counting overlapping query patterns.
                    if !indent_nodes.insert((node.start_byte(), node.end_byte())) {
                        continue;
                    }

                    let start_row = node.start_position().row as usize;
                    let end_row = node.end_position().row as usize;

                    // Indent applies to lines *after* the node's start row, up to and including
                    // its end row (outdent capture can offset this on closing lines).
                    if line > start_row && line <= end_row {
                        indent_count = indent_count.saturating_add(1);
                    }

                    continue;
                }

                if Self::is_outdent_capture(name) {
                    let start_pos = node.start_position();
                    if start_pos.row as usize != line {
                        continue;
                    }

                    // Only outdent when the token begins the line (ignoring leading whitespace).
                    if (start_pos.column as usize) <= leading_ws_bytes {
                        should_outdent = true;
                    }
                }
            }
        }

        let indent_level = indent_count.saturating_sub(if should_outdent { 1 } else { 0 });
        let unit = Self::indent_unit(indent_style);
        Some(unit.repeat(indent_level))
    }

    /// Build a text edit that replaces the current line's leading whitespace with the computed
    /// Tree-sitter indentation.
    ///
    /// Returns `None` if no change is needed, if the indenter is not synchronized, or if `line`
    /// is out of range.
    pub fn reindent_text_edit_for_line(
        &self,
        line: usize,
        indent_style: IndentStyle,
    ) -> Option<TextEditSpec> {
        let line_text = self.line_index.get_line_text(line)?;
        let desired = self.indent_string_for_line(line, indent_style)?;

        let existing_prefix: String = line_text
            .chars()
            .take_while(|ch| *ch == ' ' || *ch == '\t')
            .collect();

        if existing_prefix == desired {
            return None;
        }

        let prefix_len = existing_prefix.chars().count();
        let start = self.line_index.position_to_char_offset(line, 0);
        let end = self.line_index.position_to_char_offset(line, prefix_len);

        Some(TextEditSpec {
            start,
            end,
            text: desired,
        })
    }
}

impl std::fmt::Debug for TreeSitterIndenter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TreeSitterIndenter")
            .field("config.language", &"<language>")
            .field("config.indents_query.len", &self.config.indents_query.len())
            .field("has_tree", &self.tree.is_some())
            .field("text.len", &self.text.len())
            .field("last_synced_version", &self.last_synced_version)
            .finish()
    }
}
