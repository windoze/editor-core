use crate::read_utf8_file;
use editor_core::search::{SearchError, SearchMatch, SearchOptions, find_all};
use ignore::WalkBuilder;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FindInFilesConfig {
    /// Stop after collecting this many total matches across all files.
    pub max_total_matches: usize,
    /// Skip files larger than this many bytes (best-effort, via metadata).
    pub max_file_size_bytes: u64,
    /// Include up to this many lines of context around each matching line.
    pub context_lines: usize,
}

impl Default for FindInFilesConfig {
    fn default() -> Self {
        Self {
            max_total_matches: 10_000,
            max_file_size_bytes: 2 * 1024 * 1024,
            context_lines: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FindInFilesLineMatch {
    /// 0-based line index.
    pub line: usize,
    /// The line text (LF normalized; does not include trailing newline).
    pub text: String,
    /// Match ranges within `text` as character offsets.
    pub ranges: Vec<SearchMatch>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FindInFilesFileResult {
    pub path: PathBuf,
    pub matches: Vec<FindInFilesLineMatch>,
}

#[derive(Debug, Error)]
pub enum FindInFilesError {
    #[error("search error: {0}")]
    Search(#[from] SearchError),
    #[error("root does not exist: {0}")]
    RootMissing(String),
    #[error("root is not a directory: {0}")]
    RootNotDirectory(String),
    #[error("walk error: {0}")]
    Walk(String),
    #[error("file read error: {path}: {error}")]
    ReadFile { path: String, error: String },
}

fn normalize_newlines_to_lf(text: &str) -> String {
    // First normalize CRLF, then any remaining CR.
    text.replace("\r\n", "\n").replace('\r', "\n")
}

/// Search across files under `root`, respecting ignore files (`.gitignore`, `.ignore`, ...).
///
/// Notes:
/// - This is intentionally a “good default” implementation, not a ripgrep replacement.
/// - Frontends can build UI panels on top of the returned `FindInFilesFileResult`.
pub fn find_in_files(
    root: &Path,
    query: &str,
    options: SearchOptions,
    config: FindInFilesConfig,
) -> Result<Vec<FindInFilesFileResult>, FindInFilesError> {
    if !root.exists() {
        return Err(FindInFilesError::RootMissing(
            root.to_string_lossy().to_string(),
        ));
    }
    if !root.is_dir() {
        return Err(FindInFilesError::RootNotDirectory(
            root.to_string_lossy().to_string(),
        ));
    }

    if query.trim().is_empty() {
        return Ok(Vec::new());
    }

    let walker = WalkBuilder::new(root)
        .hidden(true)
        .git_ignore(true)
        .git_exclude(true)
        .ignore(true)
        .require_git(false)
        .parents(true)
        .filter_entry(|entry| {
            let Some(name) = entry.file_name().to_str() else {
                return true;
            };
            match name {
                ".git" | "target" | ".build" => false,
                _ => true,
            }
        })
        .build();

    let mut total_matches: usize = 0;
    let mut results: Vec<FindInFilesFileResult> = Vec::new();

    for result in walker {
        let dent = result.map_err(|e| FindInFilesError::Walk(e.to_string()))?;
        if !dent.file_type().is_some_and(|t| t.is_file()) {
            continue;
        }

        let path = dent.into_path();
        if let Ok(meta) = std::fs::metadata(&path) {
            if meta.len() > config.max_file_size_bytes {
                continue;
            }
        }

        let raw = read_utf8_file(&path).map_err(|e| FindInFilesError::ReadFile {
            path: path.to_string_lossy().to_string(),
            error: e.to_string(),
        })?;
        let text = normalize_newlines_to_lf(&raw);

        let mut file_matches: Vec<FindInFilesLineMatch> = Vec::new();
        for (line_idx, line) in text.lines().enumerate() {
            let ranges = find_all(line, query, options)?;
            if ranges.is_empty() {
                continue;
            }

            file_matches.push(FindInFilesLineMatch {
                line: line_idx,
                text: line.to_string(),
                ranges: ranges.clone(),
            });

            total_matches = total_matches.saturating_add(ranges.len());
            if total_matches >= config.max_total_matches {
                break;
            }
        }

        if !file_matches.is_empty() {
            results.push(FindInFilesFileResult {
                path: path.clone(),
                matches: file_matches,
            });
        }

        if total_matches >= config.max_total_matches {
            break;
        }
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use tempfile::tempdir;

    #[test]
    fn find_in_files_respects_gitignore_and_finds_matches() {
        let temp = tempdir().unwrap();
        let root = temp.path();

        std::fs::write(root.join(".gitignore"), "ignored.txt\n").unwrap();
        std::fs::write(root.join("ignored.txt"), "TODO: ignore\n").unwrap();
        std::fs::write(root.join("keep.txt"), "TODO: keep\nnope\n").unwrap();

        let results = find_in_files(
            root,
            "TODO",
            SearchOptions::default(),
            FindInFilesConfig {
                max_total_matches: 100,
                max_file_size_bytes: 1024 * 1024,
                context_lines: 0,
            },
        )
        .unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(
            results[0].path.file_name().unwrap().to_string_lossy(),
            "keep.txt"
        );
        assert_eq!(results[0].matches.len(), 1);
        assert_eq!(results[0].matches[0].line, 0);
        assert_eq!(results[0].matches[0].text, "TODO: keep");
    }

    #[test]
    fn find_in_files_normalizes_crlf() {
        let temp = tempdir().unwrap();
        let root = temp.path();
        std::fs::write(root.join("a.txt"), "A\r\nTODO\r\n").unwrap();

        let results = find_in_files(root, "TODO", SearchOptions::default(), FindInFilesConfig::default()).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].matches[0].line, 1);
        assert_eq!(results[0].matches[0].text, "TODO");
    }
}

