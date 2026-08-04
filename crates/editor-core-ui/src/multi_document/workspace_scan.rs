use crate::UiError;
use editor_core_lsp::{file_uri_to_path, path_to_file_uri};
use ignore::WalkBuilder;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

pub(crate) const DEFAULT_MAX_WORKSPACE_SCAN_FILE_BYTES: u64 = 2 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileScanOptions {
    pub include_globs: Vec<String>,
    pub exclude_globs: Vec<String>,
    pub max_results: usize,
    pub offset: usize,
    pub max_file_size_bytes: u64,
    pub skip_binary: bool,
    pub respect_ignore_files: bool,
    pub cancelled: bool,
    pub cancel_after_files: Option<usize>,
}

impl Default for WorkspaceFileScanOptions {
    fn default() -> Self {
        Self {
            include_globs: Vec::new(),
            exclude_globs: Vec::new(),
            max_results: 0,
            offset: 0,
            max_file_size_bytes: DEFAULT_MAX_WORKSPACE_SCAN_FILE_BYTES,
            skip_binary: true,
            respect_ignore_files: true,
            cancelled: false,
            cancel_after_files: None,
        }
    }
}

impl WorkspaceFileScanOptions {
    pub fn from_globs(
        include_globs: Vec<String>,
        exclude_globs: Vec<String>,
        max_results: usize,
    ) -> Self {
        Self {
            include_globs,
            exclude_globs,
            max_results,
            ..Self::default()
        }
    }

    pub(crate) fn resolved(mut self, default_max_results: usize) -> Self {
        if self.max_results == 0 {
            self.max_results = default_max_results;
        }
        if self.max_file_size_bytes == 0 {
            self.max_file_size_bytes = DEFAULT_MAX_WORKSPACE_SCAN_FILE_BYTES;
        }
        self.include_globs = normalize_globs(&self.include_globs);
        self.exclude_globs = normalize_globs(&self.exclude_globs);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceFileScanSummary {
    pub offset: usize,
    pub max_results: usize,
    pub next_offset: Option<usize>,
    pub truncated: bool,
    pub cancelled: bool,
    pub visited_files: usize,
    pub matched_results: usize,
    pub returned_results: usize,
    pub skipped_large_files: usize,
    pub skipped_binary_files: usize,
    pub skipped_unreadable_files: usize,
    pub ignore_files_enabled: bool,
}

impl WorkspaceFileScanSummary {
    fn new(options: &WorkspaceFileScanOptions) -> Self {
        Self {
            offset: options.offset,
            max_results: options.max_results,
            next_offset: None,
            truncated: false,
            cancelled: options.cancelled,
            visited_files: 0,
            matched_results: 0,
            returned_results: 0,
            skipped_large_files: 0,
            skipped_binary_files: 0,
            skipped_unreadable_files: 0,
            ignore_files_enabled: options.respect_ignore_files,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct WorkspaceFileCandidate {
    pub path: PathBuf,
    pub uri: String,
    pub relative_path: String,
}

pub(crate) struct WorkspaceFileScanPager {
    options: WorkspaceFileScanOptions,
    summary: WorkspaceFileScanSummary,
}

impl WorkspaceFileScanPager {
    fn new(options: WorkspaceFileScanOptions) -> Self {
        Self {
            summary: WorkspaceFileScanSummary::new(&options),
            options,
        }
    }

    fn finish(self) -> WorkspaceFileScanSummary {
        self.summary
    }

    pub(crate) fn should_stop(&self) -> bool {
        self.summary.cancelled || self.summary.truncated
    }

    fn note_file_visit(&mut self) -> bool {
        if self.should_stop() {
            return false;
        }
        if let Some(limit) = self.options.cancel_after_files
            && self.summary.visited_files >= limit
        {
            self.summary.cancelled = true;
            return false;
        }
        self.summary.visited_files += 1;
        true
    }

    pub(crate) fn accept_result(&mut self) -> bool {
        if self.should_stop() {
            return false;
        }

        let result_index = self.summary.matched_results;
        self.summary.matched_results += 1;
        if result_index < self.options.offset {
            return false;
        }

        if self.summary.returned_results < self.options.max_results {
            self.summary.returned_results += 1;
            return true;
        }

        self.summary.truncated = true;
        self.summary.next_offset =
            Some(self.options.offset.saturating_add(self.options.max_results));
        false
    }

    fn skip_large_file(&mut self) {
        self.summary.skipped_large_files += 1;
    }

    fn skip_binary_file(&mut self) {
        self.summary.skipped_binary_files += 1;
    }

    fn skip_unreadable_file(&mut self) {
        self.summary.skipped_unreadable_files += 1;
    }
}

pub(crate) fn empty_scan_summary(
    options: WorkspaceFileScanOptions,
    default_max_results: usize,
) -> WorkspaceFileScanSummary {
    WorkspaceFileScanSummary::new(&options.resolved(default_max_results))
}

pub(crate) fn walk_workspace_files<F>(
    workspace_roots: &[String],
    options: WorkspaceFileScanOptions,
    default_max_results: usize,
    mut visit: F,
) -> Result<WorkspaceFileScanSummary, UiError>
where
    F: FnMut(WorkspaceFileCandidate, &mut WorkspaceFileScanPager) -> Result<(), UiError>,
{
    let options = options.resolved(default_max_results);
    let mut pager = WorkspaceFileScanPager::new(options.clone());
    if pager.should_stop() {
        return Ok(pager.finish());
    }

    let mut candidates = Vec::new();
    for root in workspace_root_paths(workspace_roots) {
        collect_workspace_file_candidates(&root, &options, &mut candidates)?;
    }
    candidates.sort_by(|a, b| {
        a.relative_path
            .cmp(&b.relative_path)
            .then(a.path.cmp(&b.path))
    });

    for candidate in candidates {
        if !pager.note_file_visit() {
            break;
        }
        visit(candidate, &mut pager)?;
        if pager.should_stop() {
            break;
        }
    }

    Ok(pager.finish())
}

pub(crate) fn read_workspace_text_file(
    path: &Path,
    pager: &mut WorkspaceFileScanPager,
) -> Option<String> {
    if let Ok(metadata) = fs::metadata(path)
        && metadata.len() > pager.options.max_file_size_bytes
    {
        pager.skip_large_file();
        return None;
    }

    let Ok(bytes) = fs::read(path) else {
        pager.skip_unreadable_file();
        return None;
    };
    if pager.options.skip_binary && bytes.contains(&0) {
        pager.skip_binary_file();
        return None;
    }

    match String::from_utf8(bytes) {
        Ok(text) => Some(text),
        Err(_) => {
            pager.skip_binary_file();
            None
        }
    }
}

pub(crate) fn workspace_root_paths(workspace_roots: &[String]) -> Vec<PathBuf> {
    let mut roots = workspace_roots
        .iter()
        .filter_map(|root| file_uri_to_path(root))
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    roots.sort();
    roots.dedup();
    roots
}

pub(crate) fn relative_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

pub(crate) fn normalize_globs(patterns: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for pattern in patterns {
        let mut normalized = pattern.trim().replace('\\', "/");
        while normalized.contains("//") {
            normalized = normalized.replace("//", "/");
        }
        if let Some(stripped) = normalized.strip_prefix("./") {
            normalized = stripped.to_string();
        }
        if normalized.ends_with('/') {
            normalized.push_str("**");
        }
        if normalized.is_empty() || out.contains(&normalized) {
            continue;
        }
        out.push(normalized);
    }
    out
}

pub(crate) fn path_included(
    relative_path: &str,
    include_globs: &[String],
    exclude_globs: &[String],
) -> bool {
    let included = include_globs.is_empty()
        || include_globs
            .iter()
            .any(|glob| glob_matches(relative_path, glob));
    included
        && !exclude_globs
            .iter()
            .any(|glob| glob_matches(relative_path, glob))
}

pub(crate) fn should_skip_name(name: &str) -> bool {
    name.starts_with('.') || matches!(name, "target" | ".build")
}

fn collect_workspace_file_candidates(
    root: &Path,
    options: &WorkspaceFileScanOptions,
    out: &mut Vec<WorkspaceFileCandidate>,
) -> Result<(), UiError> {
    let mut builder = WalkBuilder::new(root);
    builder
        .hidden(options.respect_ignore_files)
        .git_ignore(options.respect_ignore_files)
        .git_exclude(options.respect_ignore_files)
        .ignore(options.respect_ignore_files)
        .require_git(false)
        .parents(options.respect_ignore_files)
        .filter_entry(|entry| {
            entry
                .file_name()
                .to_str()
                .is_none_or(|name| !should_skip_name(name))
        });

    for entry in builder.build() {
        let entry =
            entry.map_err(|err| UiError::Processor(format!("workspace walk failed: {err}")))?;
        if !entry
            .file_type()
            .is_some_and(|file_type| file_type.is_file())
        {
            continue;
        }

        let path = entry.into_path();
        let relative_path = relative_path(root, &path);
        if !path_included(
            &relative_path,
            &options.include_globs,
            &options.exclude_globs,
        ) {
            continue;
        }

        out.push(WorkspaceFileCandidate {
            uri: path_to_file_uri(&path),
            path,
            relative_path,
        });
    }

    Ok(())
}

fn glob_matches(path: &str, pattern: &str) -> bool {
    let path = path.replace('\\', "/").to_lowercase();
    let pattern = pattern.replace('\\', "/").to_lowercase();
    if pattern.contains('/') {
        return glob_match_chars(
            &pattern.chars().collect::<Vec<_>>(),
            &path.chars().collect::<Vec<_>>(),
            true,
        );
    }

    path.split('/').any(|component| {
        glob_match_chars(
            &pattern.chars().collect::<Vec<_>>(),
            &component.chars().collect::<Vec<_>>(),
            false,
        )
    })
}

fn glob_match_chars(pattern: &[char], text: &[char], slash_sensitive: bool) -> bool {
    fn inner(pattern: &[char], pi: usize, text: &[char], ti: usize, slash_sensitive: bool) -> bool {
        if pi == pattern.len() {
            return ti == text.len();
        }

        match pattern[pi] {
            '*' => {
                let is_double_star = pi + 1 < pattern.len() && pattern[pi + 1] == '*';
                if is_double_star {
                    let next_pi = pi + 2;
                    let mut next_ti = ti;
                    while next_ti <= text.len() {
                        if inner(pattern, next_pi, text, next_ti, slash_sensitive) {
                            return true;
                        }
                        next_ti += 1;
                    }
                    false
                } else {
                    let mut next_ti = ti;
                    while next_ti <= text.len() {
                        if inner(pattern, pi + 1, text, next_ti, slash_sensitive) {
                            return true;
                        }
                        if next_ti == text.len() || (slash_sensitive && text[next_ti] == '/') {
                            break;
                        }
                        next_ti += 1;
                    }
                    false
                }
            }
            '?' => {
                ti < text.len()
                    && !(slash_sensitive && text[ti] == '/')
                    && inner(pattern, pi + 1, text, ti + 1, slash_sensitive)
            }
            ch => {
                ti < text.len()
                    && text[ti] == ch
                    && inner(pattern, pi + 1, text, ti + 1, slash_sensitive)
            }
        }
    }

    inner(pattern, 0, text, 0, slash_sensitive)
}
