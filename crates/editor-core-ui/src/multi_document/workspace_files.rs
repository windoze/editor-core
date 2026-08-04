use crate::UiError;
use editor_core_lsp::path_to_file_uri;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

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

pub(crate) fn list_workspace_files(
    workspace_roots: &[String],
    options: WorkspaceFileListOptions,
) -> Result<Vec<WorkspaceFileEntry>, UiError> {
    let include_globs = super::workspace_search::normalize_globs(&options.include_globs);
    let exclude_globs = super::workspace_search::normalize_globs(&options.exclude_globs);
    let max_results = options.resolved_max_results();

    let mut out = Vec::new();
    let mut roots = super::workspace_search::workspace_root_paths(workspace_roots);
    for root in roots.drain(..) {
        collect_root(
            &root,
            &root,
            &include_globs,
            &exclude_globs,
            max_results,
            &mut out,
        );
        if out.len() >= max_results {
            break;
        }
    }

    out.sort_by(|a, b| {
        a.relative_path
            .cmp(&b.relative_path)
            .then(a.path.cmp(&b.path))
    });
    out.truncate(max_results);
    Ok(out)
}

fn collect_root(
    root: &Path,
    dir: &Path,
    include_globs: &[String],
    exclude_globs: &[String],
    max_results: usize,
    out: &mut Vec<WorkspaceFileEntry>,
) {
    if out.len() >= max_results {
        return;
    }

    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut entries = entries.filter_map(Result::ok).collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.path());

    for entry in entries {
        if out.len() >= max_results {
            break;
        }

        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if super::workspace_search::should_skip_name(&name) {
            continue;
        }

        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            collect_root(root, &path, include_globs, exclude_globs, max_results, out);
            continue;
        }
        if !file_type.is_file() {
            continue;
        }

        collect_file(root, path, include_globs, exclude_globs, out);
    }
}

fn collect_file(
    root: &Path,
    path: PathBuf,
    include_globs: &[String],
    exclude_globs: &[String],
    out: &mut Vec<WorkspaceFileEntry>,
) {
    let relative_path = super::workspace_search::relative_path(root, &path);
    if !super::workspace_search::path_included(&relative_path, include_globs, exclude_globs) {
        return;
    }

    out.push(WorkspaceFileEntry {
        uri: path_to_file_uri(&path),
        path: path.to_string_lossy().into_owned(),
        relative_path,
    });
}
