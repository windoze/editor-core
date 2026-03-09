use crate::FuzzyMatcher;
use ignore::WalkBuilder;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileIndexEntry {
    pub path: PathBuf,
    pub relative_path: String,
}

#[derive(Debug, Error)]
pub enum WorkspaceFileIndexError {
    #[error("workspace root does not exist: {0}")]
    RootMissing(String),
    #[error("workspace root is not a directory: {0}")]
    RootNotDirectory(String),
    #[error("walk error: {0}")]
    Walk(String),
}

/// A lightweight on-demand file index for a workspace folder.
///
/// This is intended for:
/// - “Go to file” / quick-open (fuzzy)
/// - simple workspace-wide features that need a file list
#[derive(Debug, Clone)]
pub struct WorkspaceFileIndex {
    root: PathBuf,
    cached: Vec<FileIndexEntry>,
    built: bool,
}

impl WorkspaceFileIndex {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            cached: Vec::new(),
            built: false,
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn set_root(&mut self, root: impl Into<PathBuf>) {
        self.root = root.into();
        self.cached.clear();
        self.built = false;
    }

    pub fn entries(&mut self) -> Result<&[FileIndexEntry], WorkspaceFileIndexError> {
        if !self.built {
            self.rebuild()?;
        }
        Ok(&self.cached)
    }

    pub fn rebuild(&mut self) -> Result<(), WorkspaceFileIndexError> {
        let root = &self.root;
        if !root.exists() {
            return Err(WorkspaceFileIndexError::RootMissing(
                root.to_string_lossy().to_string(),
            ));
        }
        if !root.is_dir() {
            return Err(WorkspaceFileIndexError::RootNotDirectory(
                root.to_string_lossy().to_string(),
            ));
        }

        let root_clone = root.to_path_buf();
        let walker = WalkBuilder::new(root)
            .hidden(true)
            .git_ignore(true)
            .git_exclude(true)
            .ignore(true)
            .require_git(false)
            .parents(true)
            .filter_entry(move |entry| {
                // Skip some noisy build folders (matching the Swift demo behavior).
                let Some(name) = entry.file_name().to_str() else {
                    return true;
                };
                match name {
                    ".git" | "target" | ".build" => false,
                    _ => true,
                }
            })
            .build();

        let mut out: Vec<FileIndexEntry> = Vec::new();
        for result in walker {
            let dent = result.map_err(|e| WorkspaceFileIndexError::Walk(e.to_string()))?;
            if !dent.file_type().is_some_and(|t| t.is_file()) {
                continue;
            }
            let path = dent.into_path();
            let rel = path
                .strip_prefix(&root_clone)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            out.push(FileIndexEntry {
                path,
                relative_path: rel,
            });
        }

        // Stable display order when query is empty.
        out.sort_by(|a, b| a.relative_path.to_lowercase().cmp(&b.relative_path.to_lowercase()));

        self.cached = out;
        self.built = true;
        Ok(())
    }

    /// Fuzzy-search the indexed workspace file list.
    pub fn search(&mut self, query: &str, limit: usize) -> Result<Vec<FileIndexEntry>, WorkspaceFileIndexError> {
        let entries = self.entries()?;
        let q = query.trim();
        if q.is_empty() {
            return Ok(entries.iter().take(limit).cloned().collect());
        }

        let mut scored: Vec<(i32, &FileIndexEntry)> = Vec::new();
        for entry in entries {
            if let Some(score) = FuzzyMatcher::score(&entry.relative_path, q) {
                scored.push((score, entry));
            }
        }

        scored.sort_by(|a, b| {
            if a.0 == b.0 {
                a.1.relative_path
                    .to_lowercase()
                    .cmp(&b.1.relative_path.to_lowercase())
            } else {
                b.0.cmp(&a.0)
            }
        });

        Ok(scored
            .into_iter()
            .take(limit)
            .map(|(_, e)| e.clone())
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn file_index_skips_hidden_and_common_build_dirs() {
        let temp = tempdir().unwrap();
        let root = temp.path();

        fs::create_dir_all(root.join("src")).unwrap();
        fs::write(root.join("src/main.rs"), "fn main() {}\n").unwrap();

        fs::create_dir_all(root.join("target/debug")).unwrap();
        fs::write(root.join("target/debug/app"), "bin").unwrap();

        fs::write(root.join(".hidden"), "x").unwrap();

        let mut index = WorkspaceFileIndex::new(root);
        let entries = index.entries().unwrap();

        let rels: Vec<String> = entries.iter().map(|e| e.relative_path.clone()).collect();
        assert_eq!(rels, vec!["src/main.rs".to_string()]);
    }

    #[test]
    fn file_index_respects_gitignore() {
        let temp = tempdir().unwrap();
        let root = temp.path();

        fs::write(root.join(".gitignore"), "ignored.log\n").unwrap();
        fs::write(root.join("ignored.log"), "nope").unwrap();
        fs::write(root.join("keep.txt"), "ok").unwrap();

        let mut index = WorkspaceFileIndex::new(root);
        let entries = index.entries().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].relative_path, "keep.txt");
    }

    #[test]
    fn file_index_fuzzy_search_ranks_matches() {
        let temp = tempdir().unwrap();
        let root = temp.path();

        fs::create_dir_all(root.join("src")).unwrap();
        fs::write(root.join("src/main.rs"), "fn main() {}\n").unwrap();
        fs::write(root.join("src/lib.rs"), "pub fn lib() {}\n").unwrap();

        let mut index = WorkspaceFileIndex::new(root);
        let results = index.search("main", 10).unwrap();
        assert_eq!(results.first().unwrap().relative_path, "src/main.rs");
    }
}
