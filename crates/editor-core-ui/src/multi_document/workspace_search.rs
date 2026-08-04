use crate::UiError;
use editor_core::{CompiledSearch, SearchMatch, SearchOptions};
use editor_core_lsp::{LspCoordinateConverter, LspPosition};
use regex::RegexBuilder;
use serde::Serialize;
use serde_json::json;

use super::workspace_scan::{
    self, WorkspaceFileCandidate, WorkspaceFileScanOptions, WorkspaceFileScanPager,
    WorkspaceFileScanSummary, read_workspace_text_file, walk_workspace_files,
};

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

impl WorkspaceFileSearchOptions {
    pub(crate) fn scan_options(&self) -> WorkspaceFileScanOptions {
        workspace_scan::WorkspaceFileScanOptions::from_globs(
            self.include_globs.clone(),
            self.exclude_globs.clone(),
            self.max_results,
        )
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceFileSearchResponse {
    pub results: Vec<WorkspaceFileSearchResult>,
    pub scan: WorkspaceFileScanSummary,
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

impl WorkspaceFileReplacementOptions {
    pub(crate) fn scan_options(&self) -> WorkspaceFileScanOptions {
        workspace_scan::WorkspaceFileScanOptions::from_globs(
            self.include_globs.clone(),
            self.exclude_globs.clone(),
            self.max_results,
        )
    }
}

pub(crate) fn search_workspace_files(
    workspace_roots: &[String],
    query: &str,
    search_options: SearchOptions,
    file_options: WorkspaceFileSearchOptions,
) -> Result<Vec<WorkspaceFileSearchResult>, UiError> {
    Ok(search_workspace_files_with_scan_options(
        workspace_roots,
        query,
        search_options,
        file_options.scan_options(),
    )?
    .results)
}

pub(crate) fn search_workspace_files_with_scan_options(
    workspace_roots: &[String],
    query: &str,
    search_options: SearchOptions,
    scan_options: WorkspaceFileScanOptions,
) -> Result<WorkspaceFileSearchResponse, UiError> {
    let query = query.trim();
    if query.is_empty() || workspace_roots.is_empty() {
        return Ok(WorkspaceFileSearchResponse {
            results: Vec::new(),
            scan: workspace_scan::empty_scan_summary(
                scan_options,
                DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS,
            ),
        });
    }

    let compiled = CompiledSearch::new(query, search_options)
        .map_err(|err| UiError::Processor(err.to_string()))?;
    let mut results = Vec::new();
    let scan = walk_workspace_files(
        workspace_roots,
        scan_options,
        DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS,
        |candidate, pager| {
            search_file(&candidate, &compiled, pager, &mut results);
            Ok(())
        },
    )?;

    results.sort_by(|a, b| {
        a.relative_path
            .cmp(&b.relative_path)
            .then(a.line1.cmp(&b.line1))
            .then(a.column1.cmp(&b.column1))
    });
    Ok(WorkspaceFileSearchResponse { results, scan })
}

pub(crate) fn workspace_file_replacement_workspace_edit_json(
    workspace_roots: &[String],
    query: &str,
    replacement: &str,
    search_options: SearchOptions,
    replacement_options: WorkspaceFileReplacementOptions,
) -> Result<String, UiError> {
    let scan_options = replacement_options.scan_options();
    let apply_mode = replacement_options.apply_mode;
    workspace_file_replacement_workspace_edit_json_with_scan_options(
        workspace_roots,
        query,
        replacement,
        search_options,
        scan_options,
        apply_mode,
    )
}

pub(crate) fn workspace_file_replacement_workspace_edit_json_with_scan_options(
    workspace_roots: &[String],
    query: &str,
    replacement: &str,
    search_options: SearchOptions,
    scan_options: WorkspaceFileScanOptions,
    apply_mode: String,
) -> Result<String, UiError> {
    let replacement_options = WorkspaceFileReplacementOptions {
        include_globs: scan_options.include_globs.clone(),
        exclude_globs: scan_options.exclude_globs.clone(),
        max_results: scan_options.max_results,
        apply_mode,
    };
    let query = query.trim();
    if query.is_empty() || workspace_roots.is_empty() {
        let scan =
            workspace_scan::empty_scan_summary(scan_options, DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS);
        return encode_workspace_file_replacement_workspace_edit(
            Vec::new(),
            &replacement_options,
            scan,
        );
    }

    validate_apply_mode(&replacement_options.apply_mode)?;

    let compiled = CompiledSearch::new(query, search_options)
        .map_err(|err| UiError::Processor(err.to_string()))?;
    let replacement_regex = if search_options.regex {
        Some(compile_replacement_regex(query, search_options)?)
    } else {
        None
    };

    let mut documents = Vec::new();
    let scan = walk_workspace_files(
        workspace_roots,
        scan_options,
        DEFAULT_MAX_WORKSPACE_SEARCH_RESULTS,
        |candidate, pager| {
            if let Some(document) = replacement_edits_for_file(
                &candidate,
                &compiled,
                replacement_regex.as_ref(),
                replacement,
                pager,
            ) {
                documents.push(document);
            }
            Ok(())
        },
    )?;

    encode_workspace_file_replacement_workspace_edit(documents, &replacement_options, scan)
}

fn search_file(
    candidate: &WorkspaceFileCandidate,
    compiled: &CompiledSearch,
    pager: &mut WorkspaceFileScanPager,
    results: &mut Vec<WorkspaceFileSearchResult>,
) {
    let Some(text) = read_workspace_text_file(&candidate.path, pager) else {
        return;
    };

    for (line_index, line) in text.split('\n').enumerate() {
        if pager.should_stop() {
            break;
        }

        for m in compiled.find_all(line) {
            if pager.accept_result() {
                results.push(WorkspaceFileSearchResult {
                    uri: candidate.uri.clone(),
                    path: candidate.path.to_string_lossy().into_owned(),
                    relative_path: candidate.relative_path.clone(),
                    line1: line_index + 1,
                    column1: m.start + 1,
                    line_text: line_preview(line),
                    match_start: m.start,
                    match_end: m.end,
                });
            }
            if pager.should_stop() {
                break;
            }
        }
    }
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
    candidate: &WorkspaceFileCandidate,
    compiled: &CompiledSearch,
    replacement_regex: Option<&regex::Regex>,
    replacement: &str,
    pager: &mut WorkspaceFileScanPager,
) -> Option<WorkspaceFileReplacementDocument> {
    let text = read_workspace_text_file(&candidate.path, pager)?;

    let mut edits = Vec::new();
    for (line_index, line) in text.split('\n').enumerate() {
        if pager.should_stop() {
            break;
        }

        for m in compiled.find_all(line) {
            let Some(new_text) =
                replacement_text_for_match(line, m, replacement_regex, replacement)
            else {
                continue;
            };
            if pager.accept_result() {
                edits.push(WorkspaceFileReplacementEdit {
                    line: line_index,
                    start_utf16: utf16_character_for_line_char(line, line_index, m.start),
                    end_utf16: utf16_character_for_line_char(line, line_index, m.end),
                    new_text,
                });
            }
            if pager.should_stop() {
                break;
            }
        }
    }

    if edits.is_empty() {
        return None;
    }
    Some(WorkspaceFileReplacementDocument {
        uri: candidate.uri.clone(),
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
    scan: WorkspaceFileScanSummary,
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
        "scan": scan,
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
