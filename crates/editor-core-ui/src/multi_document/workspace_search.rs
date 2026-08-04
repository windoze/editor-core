use crate::UiError;
use editor_core::{CompiledSearch, SearchMatch, SearchOptions};
use editor_core_lsp::{LspCoordinateConverter, LspPosition, file_uri_to_path, path_to_file_uri};
use regex::RegexBuilder;
use serde::Serialize;
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

const DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS: usize = 2000;
const MAX_LINE_PREVIEW_CHARS: usize = 240;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileSearchOptions {
    pub include_globs: Vec<String>,
    pub exclude_globs: Vec<String>,
    pub max_results: usize,
}

impl Default for WorkspaceFileSearchOptions {
    fn default() -> Self {
        Self {
            include_globs: Vec::new(),
            exclude_globs: Vec::new(),
            max_results: DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceFileSearchResult {
    pub uri: String,
    pub path: String,
    pub relative_path: String,
    pub line1: usize,
    pub column1: usize,
    pub line_text: String,
    pub match_start: usize,
    pub match_end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileReplacementOptions {
    pub include_globs: Vec<String>,
    pub exclude_globs: Vec<String>,
    pub max_results: usize,
    pub apply_mode: String,
}

impl Default for WorkspaceFileReplacementOptions {
    fn default() -> Self {
        Self {
            include_globs: Vec::new(),
            exclude_globs: Vec::new(),
            max_results: DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS,
            apply_mode: "atomic".to_string(),
        }
    }
}

pub(crate) fn search_workspace_files(
    workspace_roots: &[String],
    query: &str,
    search_options: SearchOptions,
    file_options: WorkspaceFileSearchOptions,
) -> Result<Vec<WorkspaceFileSearchResult>, UiError> {
    let query = query.trim();
    if query.is_empty() || workspace_roots.is_empty() {
        return Ok(Vec::new());
    }

    let compiled = CompiledSearch::new(query, search_options)
        .map_err(|err| UiError::Processor(err.to_string()))?;
    let include_globs = normalize_globs(&file_options.include_globs);
    let exclude_globs = normalize_globs(&file_options.exclude_globs);
    let max_results = if file_options.max_results == 0 {
        DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS
    } else {
        file_options.max_results
    };

    let mut results = Vec::new();
    let mut roots = workspace_roots
        .iter()
        .filter_map(|root| file_uri_to_path(root))
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    roots.sort();
    roots.dedup();

    for root in roots {
        search_root(
            &root,
            &root,
            &compiled,
            &include_globs,
            &exclude_globs,
            max_results,
            &mut results,
        );
        if results.len() >= max_results {
            break;
        }
    }

    results.sort_by(|a, b| {
        a.relative_path
            .cmp(&b.relative_path)
            .then(a.line1.cmp(&b.line1))
            .then(a.column1.cmp(&b.column1))
    });
    Ok(results)
}

pub(crate) fn workspace_file_replacement_workspace_edit_json(
    workspace_roots: &[String],
    query: &str,
    replacement: &str,
    search_options: SearchOptions,
    replacement_options: WorkspaceFileReplacementOptions,
) -> Result<String, UiError> {
    let query = query.trim();
    if query.is_empty() || workspace_roots.is_empty() {
        return encode_workspace_file_replacement_workspace_edit(Vec::new(), &replacement_options);
    }

    validate_apply_mode(&replacement_options.apply_mode)?;

    let compiled = CompiledSearch::new(query, search_options)
        .map_err(|err| UiError::Processor(err.to_string()))?;
    let replacement_regex = if search_options.regex {
        Some(compile_replacement_regex(query, search_options)?)
    } else {
        None
    };
    let include_globs = normalize_globs(&replacement_options.include_globs);
    let exclude_globs = normalize_globs(&replacement_options.exclude_globs);
    let max_results = normalized_max_results(replacement_options.max_results);
    let mut documents = Vec::new();
    let mut roots = workspace_root_paths(workspace_roots);

    for root in roots.drain(..) {
        collect_replacement_edits_root(
            &root,
            &root,
            &compiled,
            replacement_regex.as_ref(),
            replacement,
            &include_globs,
            &exclude_globs,
            max_results,
            &mut documents,
        );
        if replacement_document_edit_count(&documents) >= max_results {
            break;
        }
    }

    encode_workspace_file_replacement_workspace_edit(documents, &replacement_options)
}

fn search_root(
    root: &Path,
    dir: &Path,
    compiled: &CompiledSearch,
    include_globs: &[String],
    exclude_globs: &[String],
    max_results: usize,
    results: &mut Vec<WorkspaceFileSearchResult>,
) {
    if results.len() >= max_results {
        return;
    }

    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut entries = entries.filter_map(Result::ok).collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.path());

    for entry in entries {
        if results.len() >= max_results {
            break;
        }

        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if should_skip_name(&name) {
            continue;
        }

        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            search_root(
                root,
                &path,
                compiled,
                include_globs,
                exclude_globs,
                max_results,
                results,
            );
            continue;
        }
        if !file_type.is_file() {
            continue;
        }

        let relative_path = relative_path(root, &path);
        if !path_included(&relative_path, include_globs, exclude_globs) {
            continue;
        }

        search_file(root, path, relative_path, compiled, max_results, results);
    }
}

fn collect_replacement_edits_root(
    root: &Path,
    dir: &Path,
    compiled: &CompiledSearch,
    replacement_regex: Option<&regex::Regex>,
    replacement: &str,
    include_globs: &[String],
    exclude_globs: &[String],
    max_results: usize,
    documents: &mut Vec<WorkspaceFileReplacementDocument>,
) {
    if replacement_document_edit_count(documents) >= max_results {
        return;
    }

    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut entries = entries.filter_map(Result::ok).collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.path());

    for entry in entries {
        if replacement_document_edit_count(documents) >= max_results {
            break;
        }

        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if should_skip_name(&name) {
            continue;
        }

        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            collect_replacement_edits_root(
                root,
                &path,
                compiled,
                replacement_regex,
                replacement,
                include_globs,
                exclude_globs,
                max_results,
                documents,
            );
            continue;
        }
        if !file_type.is_file() {
            continue;
        }

        let relative_path = relative_path(root, &path);
        if !path_included(&relative_path, include_globs, exclude_globs) {
            continue;
        }

        if let Some(document) = replacement_edits_for_file(
            path,
            compiled,
            replacement_regex,
            replacement,
            max_results.saturating_sub(replacement_document_edit_count(documents)),
        ) {
            documents.push(document);
        }
    }
}

fn search_file(
    _root: &Path,
    path: PathBuf,
    relative_path: String,
    compiled: &CompiledSearch,
    max_results: usize,
    results: &mut Vec<WorkspaceFileSearchResult>,
) {
    let Ok(text) = fs::read_to_string(&path) else {
        return;
    };

    for (line_index, line) in text.split('\n').enumerate() {
        if results.len() >= max_results {
            break;
        }

        for m in compiled.find_all(line) {
            if results.len() >= max_results {
                break;
            }
            results.push(WorkspaceFileSearchResult {
                uri: path_to_file_uri(&path),
                path: path.to_string_lossy().into_owned(),
                relative_path: relative_path.clone(),
                line1: line_index + 1,
                column1: m.start + 1,
                line_text: line_preview(line),
                match_start: m.start,
                match_end: m.end,
            });
        }
    }
}

pub(crate) fn should_skip_name(name: &str) -> bool {
    name.starts_with('.') || matches!(name, "target" | ".build")
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

fn normalized_max_results(max_results: usize) -> usize {
    if max_results == 0 {
        DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS
    } else {
        max_results
    }
}

pub(crate) fn relative_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

fn line_preview(line: &str) -> String {
    let trimmed = line.trim();
    if trimmed.chars().count() <= MAX_LINE_PREVIEW_CHARS {
        return trimmed.to_string();
    }
    let mut out = trimmed
        .chars()
        .take(MAX_LINE_PREVIEW_CHARS)
        .collect::<String>();
    out.push_str("...");
    out
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

#[derive(Debug, Clone, PartialEq, Eq)]
struct WorkspaceFileReplacementDocument {
    uri: String,
    edits: Vec<WorkspaceFileReplacementEdit>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WorkspaceFileReplacementEdit {
    line: usize,
    start_utf16: u32,
    end_utf16: u32,
    new_text: String,
}

fn replacement_edits_for_file(
    path: PathBuf,
    compiled: &CompiledSearch,
    replacement_regex: Option<&regex::Regex>,
    replacement: &str,
    remaining: usize,
) -> Option<WorkspaceFileReplacementDocument> {
    if remaining == 0 {
        return None;
    }
    let Ok(text) = fs::read_to_string(&path) else {
        return None;
    };

    let mut edits = Vec::new();
    for (line_index, line) in text.split('\n').enumerate() {
        if edits.len() >= remaining {
            break;
        }

        for m in compiled.find_all(line) {
            if edits.len() >= remaining {
                break;
            }
            let Some(new_text) =
                replacement_text_for_match(line, m, replacement_regex, replacement)
            else {
                continue;
            };
            edits.push(WorkspaceFileReplacementEdit {
                line: line_index,
                start_utf16: utf16_character_for_line_char(line, line_index, m.start),
                end_utf16: utf16_character_for_line_char(line, line_index, m.end),
                new_text,
            });
        }
    }

    if edits.is_empty() {
        return None;
    }
    Some(WorkspaceFileReplacementDocument {
        uri: path_to_file_uri(&path),
        edits,
    })
}

fn replacement_text_for_match(
    line: &str,
    m: SearchMatch,
    replacement_regex: Option<&regex::Regex>,
    replacement: &str,
) -> Option<String> {
    let Some(re) = replacement_regex else {
        return Some(replacement.to_string());
    };

    let start_byte = char_to_byte(line, m.start);
    let end_byte = char_to_byte(line, m.end);
    let captures = re.captures_at(line, start_byte)?;
    let whole = captures.get(0)?;
    if whole.start() != start_byte || whole.end() != end_byte {
        return None;
    }
    let mut expanded = String::new();
    captures.expand(replacement, &mut expanded);
    Some(expanded)
}

fn char_to_byte(text: &str, char_offset: usize) -> usize {
    text.char_indices()
        .map(|(byte_offset, _)| byte_offset)
        .chain(std::iter::once(text.len()))
        .nth(char_offset)
        .unwrap_or(text.len())
}

fn compile_replacement_regex(query: &str, options: SearchOptions) -> Result<regex::Regex, UiError> {
    RegexBuilder::new(query)
        .case_insensitive(!options.case_sensitive)
        .multi_line(true)
        .build()
        .map_err(|err| UiError::Processor(err.to_string()))
}

fn encode_workspace_file_replacement_workspace_edit(
    documents: Vec<WorkspaceFileReplacementDocument>,
    options: &WorkspaceFileReplacementOptions,
) -> Result<String, UiError> {
    validate_apply_mode(&options.apply_mode)?;
    let document_changes = documents
        .into_iter()
        .map(|document| {
            json!({
                "textDocument": {
                    "uri": document.uri,
                },
                "edits": document
                    .edits
                    .into_iter()
                    .map(|edit| json!({
                        "range": range_json(edit.line, edit.start_utf16, edit.end_utf16),
                        "newText": edit.new_text,
                    }))
                    .collect::<Vec<_>>(),
            })
        })
        .collect::<Vec<_>>();

    serde_json::to_string(&json!({
        "workspaceEdit": {
            "documentChanges": document_changes,
        },
        "applyMode": options.apply_mode,
    }))
    .map_err(|err| UiError::Processor(format!("failed to encode replacement WorkspaceEdit: {err}")))
}

fn validate_apply_mode(mode: &str) -> Result<(), UiError> {
    match mode {
        "partial" | "atomic" => Ok(()),
        other => Err(UiError::Processor(format!(
            "unsupported workspace file replacement apply mode: {other}"
        ))),
    }
}

fn range_json(line: usize, start_utf16: u32, end_utf16: u32) -> serde_json::Value {
    let start = LspPosition::new(line as u32, start_utf16);
    let end = LspPosition::new(line as u32, end_utf16);
    json!({
        "start": {
            "line": start.line,
            "character": start.character,
        },
        "end": {
            "line": end.line,
            "character": end.character,
        },
    })
}

fn utf16_character_for_line_char(line_text: &str, line: usize, char_in_line: usize) -> u32 {
    LspCoordinateConverter::position_to_lsp(line_text, line, char_in_line).character
}

fn replacement_document_edit_count(documents: &[WorkspaceFileReplacementDocument]) -> usize {
    documents.iter().map(|document| document.edits.len()).sum()
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
                if ti == text.len() || (slash_sensitive && text[ti] == '/') {
                    false
                } else {
                    inner(pattern, pi + 1, text, ti + 1, slash_sensitive)
                }
            }
            literal => {
                if ti < text.len() && text[ti] == literal {
                    inner(pattern, pi + 1, text, ti + 1, slash_sensitive)
                } else {
                    false
                }
            }
        }
    }

    inner(pattern, 0, text, 0, slash_sensitive)
}
