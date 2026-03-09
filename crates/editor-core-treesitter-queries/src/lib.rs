#![warn(missing_docs)]
//! `editor-core-treesitter-queries` - built-in Tree-sitter query packs for `editor-core`.
//!
//! This crate provides **data** (queries + language handles) that higher layers can select by
//! pack id (e.g. `"rust"`).
//!
//! It does not own editor state, and it does not apply highlighting/folding by itself. Use
//! `editor-core-treesitter::TreeSitterProcessor` for the actual processing pipeline.

/// A built-in Tree-sitter query pack (language + queries).
#[derive(Debug, Clone, Copy)]
pub struct TreeSitterQueryPack {
    /// Stable pack id (e.g. `"rust"`).
    pub id: &'static str,
    /// Human-friendly language name (e.g. `"Rust"`).
    pub language_name: &'static str,
    /// Return the Tree-sitter language handle for this pack.
    pub language: fn() -> tree_sitter::Language,
    /// Syntax highlighting query (`.scm`).
    pub highlights_query: &'static str,
    /// Optional folding query (`.scm`). Each capture becomes a fold candidate.
    pub folds_query: Option<&'static str>,
}

fn rust_language() -> tree_sitter::Language {
    tree_sitter_rust::LANGUAGE.into()
}

const RUST_FOLDS_QUERY: &str = r#"
(function_item) @fold
(impl_item) @fold
(struct_item) @fold
(enum_item) @fold
(mod_item) @fold
(block) @fold
"#;

/// Built-in Rust query pack.
pub const RUST: TreeSitterQueryPack = TreeSitterQueryPack {
    id: "rust",
    language_name: "Rust",
    language: rust_language,
    highlights_query: tree_sitter_rust::HIGHLIGHTS_QUERY,
    folds_query: Some(RUST_FOLDS_QUERY),
};

static BUILTIN: &[TreeSitterQueryPack] = &[RUST];

/// List all built-in query packs.
pub fn all_query_packs() -> &'static [TreeSitterQueryPack] {
    BUILTIN
}

/// Look up a built-in query pack by id.
pub fn query_pack(id: &str) -> Option<&'static TreeSitterQueryPack> {
    BUILTIN.iter().find(|p| p.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rust_pack_is_present_and_queries_compile() {
        let pack = query_pack("rust").expect("rust pack");
        let language = (pack.language)();
        let q = tree_sitter::Query::new(&language, pack.highlights_query)
            .expect("highlights query compiles");
        assert!(!q.capture_names().is_empty());

        if let Some(folds) = pack.folds_query {
            tree_sitter::Query::new(&language, folds).expect("folds query compiles");
        }
    }
}
