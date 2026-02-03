//! Generic document processing interfaces.
//!
//! This module defines a shared "edit" format for derived editor state, such as:
//! - syntax / semantic highlighting (style layers)
//! - folding regions
//!
//! External crates (`editor-core-*`) can produce [`ProcessingEdit`] values and apply them to an
//! [`EditorStateManager`] via
//! [`EditorStateManager::apply_processing_edits`](crate::EditorStateManager::apply_processing_edits).

use crate::EditorStateManager;
use crate::intervals::{FoldRegion, Interval, StyleLayerId};

/// A change to derived editor state (highlighting, folding, etc.).
#[derive(Debug, Clone)]
pub enum ProcessingEdit {
    /// Replace an entire style layer with the given intervals (char offsets).
    ReplaceStyleLayer {
        /// The style layer being replaced.
        layer: StyleLayerId,
        /// The full set of style intervals for the layer (char offsets, half-open).
        intervals: Vec<Interval>,
    },
    /// Clear a style layer.
    ClearStyleLayer {
        /// The style layer being cleared.
        layer: StyleLayerId,
    },
    /// Replace folding regions.
    ///
    /// If `preserve_collapsed` is true, regions that match an existing collapsed region
    /// (`start_line`, `end_line`) will remain collapsed after replacement.
    ReplaceFoldingRegions {
        /// The complete set of folding regions.
        regions: Vec<FoldRegion>,
        /// Whether to preserve the collapsed/expanded state for regions that still exist.
        preserve_collapsed: bool,
    },
    /// Clear all folding regions.
    ClearFoldingRegions,
}

/// A generic processor that produces [`ProcessingEdit`]s for an editor document.
pub trait DocumentProcessor {
    /// The error type returned by [`DocumentProcessor::process`].
    type Error;

    /// Compute derived state updates to apply to the editor.
    ///
    /// Implementations should avoid mutating `state`; instead, return edits that the caller can
    /// apply (e.g. via [`EditorStateManager::apply_processing_edits`](crate::EditorStateManager::apply_processing_edits)).
    fn process(&mut self, state: &EditorStateManager) -> Result<Vec<ProcessingEdit>, Self::Error>;
}
