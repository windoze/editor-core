use serde::{Deserialize, Serialize};

pub const MAX_RECENT_FILES: usize = 20;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecentFileEntry {
    pub uri: String,
}

#[derive(Debug, Clone, Default)]
pub struct RecentFilesStore {
    entries: Vec<String>,
}

impl RecentFilesStore {
    pub fn entries(&self) -> &[String] {
        &self.entries
    }

    pub fn remember(&mut self, uri: impl Into<String>) {
        let Some(uri) = normalize_recent_file_uri(uri.into()) else {
            return;
        };

        self.entries.retain(|existing| existing != &uri);
        self.entries.insert(0, uri);
        self.entries.truncate(MAX_RECENT_FILES);
    }

    pub fn restore<I, S>(&mut self, uris: I)
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        self.entries.clear();
        for uri in uris {
            self.remember_oldest_first(uri);
        }
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }

    fn remember_oldest_first(&mut self, uri: impl Into<String>) {
        let Some(uri) = normalize_recent_file_uri(uri.into()) else {
            return;
        };
        if self.entries.contains(&uri) {
            return;
        }
        self.entries.push(uri);
        self.entries.truncate(MAX_RECENT_FILES);
    }
}

pub fn recent_file_entries(uris: &[String]) -> Vec<RecentFileEntry> {
    uris.iter()
        .cloned()
        .map(|uri| RecentFileEntry { uri })
        .collect()
}

fn normalize_recent_file_uri(uri: String) -> Option<String> {
    let trimmed = uri.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_files_deduplicate_and_keep_most_recent_first() {
        let mut store = RecentFilesStore::default();

        store.remember(" file:///workspace/a.rs ");
        store.remember("file:///workspace/b.rs");
        store.remember("file:///workspace/a.rs");
        store.remember("");

        assert_eq!(
            store.entries(),
            &[
                "file:///workspace/a.rs".to_string(),
                "file:///workspace/b.rs".to_string()
            ]
        );
    }

    #[test]
    fn recent_files_restore_preserves_snapshot_order() {
        let mut store = RecentFilesStore::default();

        store.restore([
            "file:///workspace/a.rs",
            "file:///workspace/b.rs",
            "file:///workspace/a.rs",
            " ",
        ]);

        assert_eq!(
            store.entries(),
            &[
                "file:///workspace/a.rs".to_string(),
                "file:///workspace/b.rs".to_string()
            ]
        );
    }

    #[test]
    fn recent_files_cap_entries() {
        let mut store = RecentFilesStore::default();

        for index in 0..(MAX_RECENT_FILES + 2) {
            store.remember(format!("file:///workspace/{index}.rs"));
        }

        assert_eq!(store.entries().len(), MAX_RECENT_FILES);
        assert_eq!(store.entries()[0], "file:///workspace/21.rs");
        assert_eq!(
            store.entries()[MAX_RECENT_FILES - 1],
            "file:///workspace/2.rs"
        );
    }
}
