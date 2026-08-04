use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessingPollResult {
    pub applied: bool,
    pub pending: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreeSitterProcessingConfig {
    /// Debounce window for running Tree-sitter queries (highlighting/folding).
    pub debounce_ms: u32,
    /// Soft budget for a single query pass; when exceeded, the worker enters a cooldown window
    /// and prefers visible-range queries.
    pub query_budget_ms: u32,
    /// Cooldown window after an over-budget query pass.
    pub cooldown_ms: u32,
    /// When the document exceeds this many Unicode scalar values, prefer visible-range queries.
    pub large_doc_char_threshold: u32,
    /// If true, large documents use visible/prefetch-range queries by default.
    pub prefer_visible_range_on_large_docs: bool,
}

impl Default for TreeSitterProcessingConfig {
    fn default() -> Self {
        Self {
            debounce_ms: 16,
            query_budget_ms: 30,
            cooldown_ms: 200,
            large_doc_char_threshold: 200_000,
            prefer_visible_range_on_large_docs: true,
        }
    }
}

pub(crate) enum TreeSitterWorkerMsg {
    Init {
        config: TreeSitterProcessorConfig,
        runtime: TreeSitterProcessingConfig,
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    ApplyDelta {
        version: u64,
        delta: editor_core::delta::TextDelta,
        prefetch_char_range: Option<(usize, usize)>,
    },
    FullSync {
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    UpdateRuntimeConfig {
        runtime: TreeSitterProcessingConfig,
    },
    Shutdown,
}

pub(crate) enum TreeSitterWorkerEvent {
    Processed {
        version: u64,
        edits: Vec<ProcessingEdit>,
        update_mode: TreeSitterUpdateMode,
    },
    NeedFullSync,
    Error(String),
}
