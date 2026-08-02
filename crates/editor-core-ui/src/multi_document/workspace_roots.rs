use serde::{Deserialize, Serialize};

/// LSP-compatible workspace folder metadata derived from a core-owned workspace root URI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceFolder {
    pub uri: String,
    pub name: String,
}

/// Diff returned when the core-owned workspace root list changes.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceRootsChange {
    pub added: Vec<WorkspaceFolder>,
    pub removed: Vec<WorkspaceFolder>,
}

impl WorkspaceRootsChange {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.removed.is_empty()
    }
}

pub(crate) fn normalize_workspace_roots<I, S>(roots: I) -> Vec<String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut out = Vec::<String>::new();
    for root in roots {
        let root = root.into();
        if root.is_empty() || out.iter().any(|existing| existing == &root) {
            continue;
        }
        out.push(root);
    }
    out
}

pub(crate) fn workspace_roots_change(previous: &[String], next: &[String]) -> WorkspaceRootsChange {
    let removed = previous
        .iter()
        .filter(|root| !next.iter().any(|next_root| next_root == *root))
        .map(|root| workspace_folder(root))
        .collect();
    let added = next
        .iter()
        .filter(|root| !previous.iter().any(|previous_root| previous_root == *root))
        .map(|root| workspace_folder(root))
        .collect();

    WorkspaceRootsChange { added, removed }
}

fn workspace_folder(root_uri: &str) -> WorkspaceFolder {
    WorkspaceFolder {
        uri: root_uri.to_string(),
        name: workspace_folder_name(root_uri),
    }
}

fn workspace_folder_name(root_uri: &str) -> String {
    root_uri
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or("workspace")
        .to_string()
}
