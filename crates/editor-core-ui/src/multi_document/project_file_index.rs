use crate::UiError;
use serde::Serialize;

use super::workspace_files::{self, WorkspaceFileEntry, WorkspaceFileListOptions};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProjectFileIndexSnapshot {
    pub workspace_roots: Vec<String>,
    pub files: Vec<WorkspaceFileEntry>,
    pub is_built: bool,
    pub max_results: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProjectFileIndexQueryResult {
    pub uri: String,
    pub path: String,
    pub relative_path: String,
    pub score: i32,
}

#[derive(Debug, Clone, Default)]
pub struct ProjectFileIndexStore {
    files: Vec<WorkspaceFileEntry>,
    is_built: bool,
    max_results: usize,
}

impl ProjectFileIndexStore {
    pub fn refresh(
        &mut self,
        workspace_roots: &[String],
        options: WorkspaceFileListOptions,
    ) -> Result<ProjectFileIndexSnapshot, UiError> {
        let max_results = options.resolved_max_results();
        self.files = workspace_files::list_workspace_files(workspace_roots, options)?;
        self.is_built = true;
        self.max_results = max_results;
        Ok(self.snapshot(workspace_roots))
    }

    pub fn clear(&mut self) {
        self.files.clear();
        self.is_built = false;
        self.max_results = 0;
    }

    pub fn snapshot(&self, workspace_roots: &[String]) -> ProjectFileIndexSnapshot {
        ProjectFileIndexSnapshot {
            workspace_roots: workspace_roots.to_vec(),
            files: self.files.clone(),
            is_built: self.is_built,
            max_results: self.max_results,
        }
    }

    pub fn query(&self, query: &str, max_results: usize) -> Vec<ProjectFileIndexQueryResult> {
        let max_results = if max_results == 0 {
            self.files.len()
        } else {
            max_results
        };
        if max_results == 0 {
            return Vec::new();
        }

        let query = query.trim();
        if query.is_empty() {
            return self
                .files
                .iter()
                .take(max_results)
                .map(|file| query_result(file, 0))
                .collect();
        }

        let mut scored = self
            .files
            .iter()
            .filter_map(|file| fuzzy_score(&file.relative_path, query).map(|score| (file, score)))
            .collect::<Vec<_>>();
        scored.sort_by(|(a_file, a_score), (b_file, b_score)| {
            b_score
                .cmp(a_score)
                .then_with(|| a_file.relative_path.cmp(&b_file.relative_path))
                .then_with(|| a_file.path.cmp(&b_file.path))
        });
        scored
            .into_iter()
            .take(max_results)
            .map(|(file, score)| query_result(file, score))
            .collect()
    }
}

fn query_result(file: &WorkspaceFileEntry, score: i32) -> ProjectFileIndexQueryResult {
    ProjectFileIndexQueryResult {
        uri: file.uri.clone(),
        path: file.path.clone(),
        relative_path: file.relative_path.clone(),
        score,
    }
}

fn fuzzy_score(candidate: &str, query: &str) -> Option<i32> {
    let query = query.trim();
    if query.is_empty() {
        return Some(0);
    }

    let candidate_chars = candidate.to_lowercase().chars().collect::<Vec<_>>();
    let query_chars = query.to_lowercase().chars().collect::<Vec<_>>();

    let mut score = 0;
    let mut candidate_index = 0;
    let mut consecutive = 0;
    let mut first_match = None;

    for query_char in query_chars {
        while candidate_index < candidate_chars.len()
            && candidate_chars[candidate_index] != query_char
        {
            candidate_index += 1;
            consecutive = 0;
        }
        if candidate_index >= candidate_chars.len() {
            return None;
        }

        if first_match.is_none() {
            first_match = Some(candidate_index);
        }

        score += 10;
        score += consecutive * 6;
        if candidate_index == 0 || is_boundary(candidate_chars[candidate_index - 1]) {
            score += 4;
        }

        consecutive += 1;
        candidate_index += 1;
    }

    if let Some(first_match) = first_match {
        score -= first_match.min(20) as i32;
    }
    Some(score)
}

fn is_boundary(ch: char) -> bool {
    matches!(ch, '/' | '\\' | '_' | '-' | ' ' | '.')
}
