use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileExplorerEntryKind {
    Directory,
    File,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileExplorerEntry {
    pub path: PathBuf,
    pub file_name: String,
    pub kind: FileExplorerEntryKind,
}

#[derive(Debug, Error)]
pub enum FileExplorerError {
    #[error("workspace root does not exist: {0}")]
    RootMissing(String),
    #[error("workspace root is not a directory: {0}")]
    RootNotDirectory(String),
    #[error("path is not under workspace root: {0}")]
    NotUnderRoot(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

/// A minimal filesystem-backed “file explorer” helper for a workspace root.
///
/// This is a UI-agnostic model: frontends are expected to render the returned entries in a tree.
#[derive(Debug, Clone)]
pub struct FileExplorer {
    root: PathBuf,
}

impl FileExplorer {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn set_root(&mut self, root: impl Into<PathBuf>) {
        self.root = root.into();
    }

    pub fn validate_root(&self) -> Result<(), FileExplorerError> {
        if !self.root.exists() {
            return Err(FileExplorerError::RootMissing(
                self.root.to_string_lossy().to_string(),
            ));
        }
        if !self.root.is_dir() {
            return Err(FileExplorerError::RootNotDirectory(
                self.root.to_string_lossy().to_string(),
            ));
        }
        Ok(())
    }

    pub fn is_under_root(&self, path: &Path) -> bool {
        let Ok(root) = self.root.canonicalize() else {
            return false;
        };
        let Ok(path) = path.canonicalize() else {
            return false;
        };
        path.starts_with(root)
    }

    /// List the direct children of `dir`.
    ///
    /// Sorting:
    /// - directories first, then files
    /// - name ascending, case-insensitive
    ///
    /// Filtering:
    /// - skips hidden entries and some noisy build folders (`.git`, `target`, `.build`)
    pub fn children(&self, dir: &Path) -> Result<Vec<FileExplorerEntry>, FileExplorerError> {
        self.validate_root()?;

        if !self.is_under_root(dir) {
            return Err(FileExplorerError::NotUnderRoot(
                dir.to_string_lossy().to_string(),
            ));
        }

        let mut out: Vec<FileExplorerEntry> = Vec::new();
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            let file_name = entry.file_name().to_string_lossy().to_string();
            if file_name.starts_with('.') {
                continue;
            }
            if matches!(file_name.as_str(), ".git" | "target" | ".build") {
                continue;
            }

            let kind = match entry.file_type() {
                Ok(t) if t.is_dir() => FileExplorerEntryKind::Directory,
                Ok(t) if t.is_file() => FileExplorerEntryKind::File,
                _ => continue,
            };
            out.push(FileExplorerEntry {
                path,
                file_name,
                kind,
            });
        }

        out.sort_by(|a, b| {
            if a.kind != b.kind {
                return match (a.kind, b.kind) {
                    (FileExplorerEntryKind::Directory, FileExplorerEntryKind::File) => {
                        std::cmp::Ordering::Less
                    }
                    (FileExplorerEntryKind::File, FileExplorerEntryKind::Directory) => {
                        std::cmp::Ordering::Greater
                    }
                    _ => std::cmp::Ordering::Equal,
                };
            }
            a.file_name.to_lowercase().cmp(&b.file_name.to_lowercase())
        });

        Ok(out)
    }

    /// Best-effort “reveal in tree” helper: returns the relative path segments from the root
    /// to the target.
    ///
    /// Example:
    /// - root: `/proj`
    /// - target: `/proj/src/main.rs`
    /// - returns: `["src", "src/main.rs"]`
    pub fn reveal_segments(&self, target: &Path) -> Result<Vec<String>, FileExplorerError> {
        self.validate_root()?;
        if !self.is_under_root(target) {
            return Err(FileExplorerError::NotUnderRoot(
                target.to_string_lossy().to_string(),
            ));
        }

        let root = self
            .root
            .canonicalize()
            .unwrap_or_else(|_| self.root.clone());
        let target = target
            .canonicalize()
            .unwrap_or_else(|_| target.to_path_buf());

        let rel = target.strip_prefix(&root).unwrap_or(&target);
        let mut parts: Vec<String> = Vec::new();
        let mut acc = PathBuf::new();
        for comp in rel.components() {
            acc.push(comp);
            parts.push(acc.to_string_lossy().replace('\\', "/"));
        }

        Ok(parts)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn children_sorts_dirs_first_and_filters_common_noise() {
        let temp = tempdir().unwrap();
        let root = temp.path();

        fs::create_dir_all(root.join("b_dir")).unwrap();
        fs::create_dir_all(root.join("a_dir")).unwrap();
        fs::create_dir_all(root.join("target/debug")).unwrap();
        fs::write(root.join("z.txt"), "z").unwrap();
        fs::write(root.join("a.txt"), "a").unwrap();
        fs::write(root.join(".hidden"), "x").unwrap();

        let explorer = FileExplorer::new(root);
        let children = explorer.children(root).unwrap();
        let names: Vec<String> = children.iter().map(|e| e.file_name.clone()).collect();
        assert_eq!(names, vec!["a_dir", "b_dir", "a.txt", "z.txt"]);
    }

    #[test]
    fn reveal_segments_returns_incremental_relative_paths() {
        let temp = tempdir().unwrap();
        let root = temp.path();
        fs::create_dir_all(root.join("src")).unwrap();
        fs::write(root.join("src/main.rs"), "fn main() {}\n").unwrap();

        let explorer = FileExplorer::new(root);
        let segs = explorer.reveal_segments(&root.join("src/main.rs")).unwrap();
        assert_eq!(segs, vec!["src", "src/main.rs"]);
    }
}
