use editor_core::anchors::{AnchorBias, TextAnchor};
use editor_core::search::{SearchError, SearchMatch, SearchOptions, find_all};
use editor_core::workspace::{BufferId, Workspace};
use std::collections::BTreeMap;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AnchoredMatchRange {
    pub start: TextAnchor,
    pub end: TextAnchor,
}

impl AnchoredMatchRange {
    pub fn from_match(m: SearchMatch) -> Self {
        Self {
            start: TextAnchor::new(m.start, AnchorBias::Left),
            end: TextAnchor::new(m.end, AnchorBias::Right),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BufferSearchResults {
    pub buffer_id: BufferId,
    pub matches: Vec<AnchoredMatchRange>,
}

#[derive(Debug, Error)]
pub enum SearchResultsError {
    #[error("search error: {0}")]
    Search(#[from] SearchError),
    #[error("workspace error: {0}")]
    Workspace(String),
}

impl From<editor_core::workspace::WorkspaceError> for SearchResultsError {
    fn from(err: editor_core::workspace::WorkspaceError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

/// A stable “search results” model that can keep match locations anchored under edits.
///
/// Notes:
/// - This does **not** automatically re-run the search when text changes.
/// - Instead, it keeps prior results stable by applying `TextDelta` to the stored anchors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchResultsModel {
    pub query: String,
    pub options: SearchOptions,
    pub results: Vec<BufferSearchResults>,
}

impl SearchResultsModel {
    pub fn build(
        ws: &Workspace,
        query: impl Into<String>,
        options: SearchOptions,
    ) -> Result<Self, SearchResultsError> {
        let query = query.into();
        let mut per_buffer: Vec<BufferSearchResults> = Vec::new();

        for buffer_id in ws.buffer_ids() {
            let text = ws.buffer_text(buffer_id)?;
            let matches = find_all(&text, &query, options)?;
            if matches.is_empty() {
                continue;
            }
            per_buffer.push(BufferSearchResults {
                buffer_id,
                matches: matches
                    .into_iter()
                    .map(AnchoredMatchRange::from_match)
                    .collect(),
            });
        }

        Ok(Self {
            query,
            options,
            results: per_buffer,
        })
    }

    /// Apply pending buffer deltas from the workspace, updating all anchored match ranges.
    ///
    /// This consumes each buffer's last delta via `Workspace::take_last_text_delta_for_buffer`.
    pub fn apply_workspace_deltas(&mut self, ws: &mut Workspace) -> Result<(), SearchResultsError> {
        for r in &mut self.results {
            let Some(delta) = ws.take_last_text_delta_for_buffer(r.buffer_id)? else {
                continue;
            };
            for m in &mut r.matches {
                m.start.apply_delta(&delta);
                m.end.apply_delta(&delta);
            }
        }
        Ok(())
    }

    /// Compute current match locations as `(line, column)` pairs (0-based) for each buffer.
    ///
    /// This is a convenience for UI layers that want to render “click to jump” results.
    pub fn locations_by_buffer(
        &self,
        ws: &Workspace,
    ) -> Result<BTreeMap<BufferId, Vec<(usize, usize)>>, SearchResultsError> {
        let mut out: BTreeMap<BufferId, Vec<(usize, usize)>> = BTreeMap::new();
        for r in &self.results {
            let line_index = ws.buffer_line_index(r.buffer_id)?;
            let mut locs: Vec<(usize, usize)> = Vec::with_capacity(r.matches.len());
            for m in &r.matches {
                let (line, col) = line_index.char_offset_to_position(m.start.offset);
                locs.push((line, col));
            }
            out.insert(r.buffer_id, locs);
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::{Command, EditCommand, Workspace};
    use pretty_assertions::assert_eq;

    #[test]
    fn anchored_search_results_shift_under_edits() {
        let mut ws = Workspace::new();
        let opened = ws.open_buffer(None, "hello world\n", 80).unwrap();

        let mut results =
            SearchResultsModel::build(&ws, "world", SearchOptions::default()).unwrap();
        assert_eq!(results.results.len(), 1);
        let m0 = results.results[0].matches[0];
        assert_eq!(m0.start.offset, 6);
        assert_eq!(m0.end.offset, 11);

        ws.execute(
            opened.view_id,
            Command::Edit(EditCommand::Insert {
                offset: 0,
                text: "X".to_string(),
            }),
        )
        .unwrap();

        results.apply_workspace_deltas(&mut ws).unwrap();
        let m0 = results.results[0].matches[0];
        assert_eq!(m0.start.offset, 7);
        assert_eq!(m0.end.offset, 12);
    }
}
