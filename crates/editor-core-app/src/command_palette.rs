use crate::FuzzyMatcher;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandPaletteItem {
    pub id: String,
    pub title: String,
    pub shortcut: Option<String>,
    pub category: Option<String>,
}

impl CommandPaletteItem {
    pub fn new(id: impl Into<String>, title: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            shortcut: None,
            category: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandPaletteResult {
    pub item: CommandPaletteItem,
    pub score: i32,
}

/// A lightweight command palette model: holds commands and performs fuzzy filtering.
#[derive(Debug, Default, Clone)]
pub struct CommandPalette {
    items: Vec<CommandPaletteItem>,
}

impl CommandPalette {
    pub fn new(items: Vec<CommandPaletteItem>) -> Self {
        Self { items }
    }

    pub fn items(&self) -> &[CommandPaletteItem] {
        &self.items
    }

    pub fn set_items(&mut self, items: Vec<CommandPaletteItem>) {
        self.items = items;
    }

    /// Filter items using subsequence fuzzy matching.
    ///
    /// - When `query` is empty, returns items in their existing order (up to `limit`).
    pub fn filter(&self, query: &str, limit: usize) -> Vec<CommandPaletteResult> {
        let q = query.trim();
        if q.is_empty() {
            return self
                .items
                .iter()
                .take(limit)
                .cloned()
                .map(|item| CommandPaletteResult { item, score: 0 })
                .collect();
        }

        let mut scored: Vec<CommandPaletteResult> = Vec::new();
        for item in &self.items {
            if let Some(score) = FuzzyMatcher::score(&item.title, q) {
                scored.push(CommandPaletteResult {
                    item: item.clone(),
                    score,
                });
            }
        }

        scored.sort_by(|a, b| {
            if a.score == b.score {
                a.item
                    .title
                    .to_lowercase()
                    .cmp(&b.item.title.to_lowercase())
            } else {
                b.score.cmp(&a.score)
            }
        });

        scored.truncate(limit);
        scored
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn command_palette_filters_and_sorts_by_score() {
        let palette = CommandPalette::new(vec![
            CommandPaletteItem::new("save", "File: Save"),
            CommandPaletteItem::new("open", "File: Open"),
            CommandPaletteItem::new("close", "File: Close Tab"),
        ]);

        let results = palette.filter("sav", 10);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].item.id, "save");
    }
}

