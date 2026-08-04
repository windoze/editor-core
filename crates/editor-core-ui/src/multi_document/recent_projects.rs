use serde::{Deserialize, Serialize};

pub const MAX_RECENT_PROJECTS: usize = 20;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecentProjectEntry {
    pub uri: String,
}

#[derive(Debug, Clone, Default)]
pub struct RecentProjectsStore {
    entries: Vec<String>,
}

impl RecentProjectsStore {
    pub fn entries(&self) -> &[String] {
        &self.entries
    }

    pub fn remember(&mut self, uri: impl Into<String>) {
        let Some(uri) = normalize_recent_project_uri(uri.into()) else {
            return;
        };

        self.entries.retain(|existing| existing != &uri);
        self.entries.insert(0, uri);
        self.entries.truncate(MAX_RECENT_PROJECTS);
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
        let Some(uri) = normalize_recent_project_uri(uri.into()) else {
            return;
        };
        if self.entries.contains(&uri) {
            return;
        }
        self.entries.push(uri);
        self.entries.truncate(MAX_RECENT_PROJECTS);
    }
}

pub fn recent_project_entries(uris: &[String]) -> Vec<RecentProjectEntry> {
    uris.iter()
        .cloned()
        .map(|uri| RecentProjectEntry { uri })
        .collect()
}

fn normalize_recent_project_uri(uri: String) -> Option<String> {
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
    fn recent_projects_deduplicate_and_keep_most_recent_first() {
        let mut store = RecentProjectsStore::default();

        store.remember(" file:///workspace/a ");
        store.remember("file:///workspace/b");
        store.remember("file:///workspace/a");
        store.remember("");

        assert_eq!(
            store.entries(),
            &[
                "file:///workspace/a".to_string(),
                "file:///workspace/b".to_string()
            ]
        );
    }

    #[test]
    fn recent_projects_restore_preserves_snapshot_order() {
        let mut store = RecentProjectsStore::default();

        store.restore([
            "file:///workspace/a",
            "file:///workspace/b",
            "file:///workspace/a",
            " ",
        ]);

        assert_eq!(
            store.entries(),
            &[
                "file:///workspace/a".to_string(),
                "file:///workspace/b".to_string()
            ]
        );
    }

    #[test]
    fn recent_projects_cap_entries() {
        let mut store = RecentProjectsStore::default();

        for index in 0..(MAX_RECENT_PROJECTS + 2) {
            store.remember(format!("file:///workspace/{index}"));
        }

        assert_eq!(store.entries().len(), MAX_RECENT_PROJECTS);
        assert_eq!(store.entries()[0], "file:///workspace/21");
        assert_eq!(
            store.entries()[MAX_RECENT_PROJECTS - 1],
            "file:///workspace/2"
        );
    }
}
