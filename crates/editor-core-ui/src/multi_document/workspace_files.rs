use crate::UiError;
use serde::Serialize;

use super::workspace_scan::{
    self, WorkspaceFileScanOptions, WorkspaceFileScanSummary, walk_workspace_files,
};

const DEFAULT_MAX_WORKSPACE_FILE_LIST_RESULTS: usize = 10_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileListOptions {
    pub include_globs: Vec<String>,
    pub exclude_globs: Vec<String>,
    pub max_results: usize,
}

impl Default for WorkspaceFileListOptions {
    fn default() -> Self {
        Self {
            include_globs: Vec::new(),
            exclude_globs: Vec::new(),
            max_results: DEFAULT_MAX_WORKSPACE_FILE_LIST_RESULTS,
        }
    }
}

impl WorkspaceFileListOptions {
    pub(crate) fn resolved_max_results(&self) -> usize {
        if self.max_results == 0 {
            DEFAULT_MAX_WORKSPACE_FILE_LIST_RESULTS
        } else {
            self.max_results
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceFileEntry {
    pub uri: String,
    pub path: String,
    pub relative_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceFileListResponse {
    pub files: Vec<WorkspaceFileEntry>,
    pub scan: WorkspaceFileScanSummary,
}

pub(crate) fn list_workspace_files(
    workspace_roots: &[String],
    options: WorkspaceFileListOptions,
) -> Result<Vec<WorkspaceFileEntry>, UiError> {
    Ok(list_workspace_files_with_scan_options(workspace_roots, options.scan_options())?.files)
}

pub(crate) fn list_workspace_files_with_scan_options(
    workspace_roots: &[String],
    scan_options: WorkspaceFileScanOptions,
) -> Result<WorkspaceFileListResponse, UiError> {
    let mut out = Vec::new();
    let scan = walk_workspace_files(
        workspace_roots,
        scan_options,
        DEFAULT_MAX_WORKSPACE_FILE_LIST_RESULTS,
        |candidate, pager| {
            if pager.accept_result() {
                out.push(WorkspaceFileEntry {
                    uri: candidate.uri,
                    path: candidate.path.to_string_lossy().into_owned(),
                    relative_path: candidate.relative_path,
                });
            }
            Ok(())
        },
    )?;

    out.sort_by(|a, b| {
        a.relative_path
            .cmp(&b.relative_path)
            .then(a.path.cmp(&b.path))
    });
    Ok(WorkspaceFileListResponse { files: out, scan })
}

impl WorkspaceFileListOptions {
    pub(crate) fn scan_options(&self) -> WorkspaceFileScanOptions {
        workspace_scan::WorkspaceFileScanOptions::from_globs(
            self.include_globs.clone(),
            self.exclude_globs.clone(),
            self.max_results,
        )
    }
}
