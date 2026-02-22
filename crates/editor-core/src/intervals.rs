//! Phase 4: Styles and Folding (Intervals & Visibility)
//!
//! Uses Interval Tree to manage style metadata and code folding.

/// Style ID type
pub type StyleId = u32;

/// Built-in style id used for folding placeholder text (e.g. `/*...*/`, `use ...`).
///
/// Consumers should map this to a muted style.
pub const FOLD_PLACEHOLDER_STYLE_ID: StyleId = 0x0300_0001;

/// Built-in style id for LSP `textDocument/documentHighlight` (kind: Text/unspecified).
pub const DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID: StyleId = 0x0400_0001;
/// Built-in style id for LSP `textDocument/documentHighlight` (kind: Read).
pub const DOCUMENT_HIGHLIGHT_READ_STYLE_ID: StyleId = 0x0400_0002;
/// Built-in style id for LSP `textDocument/documentHighlight` (kind: Write).
pub const DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID: StyleId = 0x0400_0003;

/// Style layer ID
///
/// Used to distinguish style sources (e.g., LSP semantic highlighting, simple syntax highlighting, diagnostics, etc.),
/// allowing replacement/clearing of one layer without affecting other style layers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct StyleLayerId(pub u32);

impl StyleLayerId {
    /// Create a style layer id from a raw numeric identifier.
    pub const fn new(id: u32) -> Self {
        Self(id)
    }

    /// LSP `semanticTokens` style layer (recommended for semantic highlighting).
    pub const SEMANTIC_TOKENS: Self = Self(1);

    /// Simple syntax highlighting style layer (e.g., regex-based JSON/INI highlighting).
    pub const SIMPLE_SYNTAX: Self = Self(2);

    /// Sublime Text `.sublime-syntax` style layer (lightweight syntax highlighting/folding).
    pub const SUBLIME_SYNTAX: Self = Self(3);

    /// LSP diagnostics overlay layer.
    ///
    /// This is intended for underlines / gutter markers sourced from LSP diagnostics.
    pub const DIAGNOSTICS: Self = Self(4);

    /// LSP `textDocument/documentHighlight` overlay layer.
    pub const DOCUMENT_HIGHLIGHTS: Self = Self(5);
}

/// Interval structure
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interval {
    /// Start offset (bytes or characters, depending on usage scenario)
    pub start: usize,
    /// End offset (exclusive)
    pub end: usize,
    /// Style ID
    pub style_id: StyleId,
}

impl Interval {
    /// Create a new interval with `[start, end)` offsets and a style id.
    pub fn new(start: usize, end: usize, style_id: StyleId) -> Self {
        Self {
            start,
            end,
            style_id,
        }
    }

    /// Check if interval contains a specific position
    pub fn contains(&self, pos: usize) -> bool {
        self.start <= pos && pos < self.end
    }

    /// Check if two intervals overlap
    pub fn overlaps(&self, other: &Interval) -> bool {
        self.start < other.end && other.start < self.end
    }
}

/// Interval tree - manages style intervals
///
/// Uses a sorted vector with binary search for efficient interval queries.
/// Query complexity: O(log n + k), where k is the number of overlapping intervals.
/// Insertion complexity: O(n) (requires maintaining sort order).
pub struct IntervalTree {
    /// List of intervals (kept sorted by start position)
    intervals: Vec<Interval>,
    /// Prefix maximum end position: `prefix_max_end[i] = max(intervals[0..=i].end)`
    ///
    /// Used for early pruning in `query_point` / `query_range`, avoiding degradation to O(n) scan when there are many style intervals.
    prefix_max_end: Vec<usize>,
}

impl IntervalTree {
    /// Create an empty interval tree.
    pub fn new() -> Self {
        Self {
            intervals: Vec::new(),
            prefix_max_end: Vec::new(),
        }
    }

    fn rebuild_prefix_max_end_from(&mut self, start_idx: usize) {
        if self.intervals.is_empty() {
            self.prefix_max_end.clear();
            return;
        }

        if self.prefix_max_end.len() != self.intervals.len() {
            self.prefix_max_end.resize(self.intervals.len(), 0);
        }

        let mut max_end = if start_idx == 0 {
            0
        } else {
            self.prefix_max_end[start_idx - 1]
        };

        for (idx, interval) in self.intervals.iter().enumerate().skip(start_idx) {
            max_end = max_end.max(interval.end);
            self.prefix_max_end[idx] = max_end;
        }
    }

    fn rebuild_prefix_max_end(&mut self) {
        self.rebuild_prefix_max_end_from(0);
    }

    /// Insert an interval
    pub fn insert(&mut self, interval: Interval) {
        // Find insertion position (maintaining sort order)
        let pos = self
            .intervals
            .binary_search_by_key(&interval.start, |i| i.start)
            .unwrap_or_else(|pos| pos);

        self.intervals.insert(pos, interval);
        self.prefix_max_end.insert(pos, 0);
        self.rebuild_prefix_max_end_from(pos);
    }

    /// Remove interval that exactly matches the specified interval
    pub fn remove(&mut self, start: usize, end: usize, style_id: StyleId) -> bool {
        if let Some(pos) = self
            .intervals
            .iter()
            .position(|i| i.start == start && i.end == end && i.style_id == style_id)
        {
            self.intervals.remove(pos);
            self.prefix_max_end.remove(pos);
            if pos < self.intervals.len() {
                self.rebuild_prefix_max_end_from(pos);
            }
            true
        } else {
            false
        }
    }

    /// Query all intervals containing a specific position
    /// Optimized version: uses binary search to locate interval range that may contain pos
    pub fn query_point(&self, pos: usize) -> Vec<&Interval> {
        self.query_point_impl(pos).0
    }

    fn query_point_impl(&self, pos: usize) -> (Vec<&Interval>, usize) {
        if self.intervals.is_empty() {
            return (Vec::new(), 0);
        }

        let mut result = Vec::new();
        let mut scanned = 0usize;

        // Use binary search to find first position where start > pos
        let search_key = pos.saturating_add(1);
        let idx = match self
            .intervals
            .binary_search_by_key(&search_key, |i| i.start)
        {
            Ok(idx) => idx,
            Err(idx) => idx,
        };

        // Starting from idx-1, check backward for all intervals that may contain pos
        // Because intervals are sorted by start, all intervals with start <= pos are before idx
        for i in (0..idx).rev() {
            scanned = scanned.saturating_add(1);

            // If maximum end of `intervals[0..=i]` is <= pos, earlier intervals cannot contain pos.
            if self.prefix_max_end[i] <= pos {
                break;
            }

            let interval = &self.intervals[i];
            if interval.contains(pos) {
                result.push(interval);
            }
        }

        (result, scanned)
    }

    #[cfg(test)]
    fn query_point_scan_count(&self, pos: usize) -> usize {
        self.query_point_impl(pos).1
    }

    /// Query all intervals overlapping with specified range
    /// Optimized version: uses binary search to locate interval range that may overlap
    pub fn query_range(&self, start: usize, end: usize) -> Vec<&Interval> {
        if self.intervals.is_empty() || start >= end {
            return Vec::new();
        }

        let mut result = Vec::new();

        // Use binary search to find first position where interval.start >= end
        // All intervals that may overlap are before this position
        let search_end = match self.intervals.binary_search_by_key(&end, |i| i.start) {
            Ok(idx) => idx,
            Err(idx) => idx,
        };

        if search_end == 0 {
            return result;
        }

        // First find position where start >= start, then expand backward,
        // until `prefix_max_end` indicates earlier intervals cannot cross start.
        let mut scan_start = match self.intervals.binary_search_by_key(&start, |i| i.start) {
            Ok(idx) | Err(idx) => idx.min(search_end),
        };

        while scan_start > 0 && self.prefix_max_end[scan_start - 1] > start {
            scan_start -= 1;
        }

        for interval in self.intervals[scan_start..search_end].iter() {
            if interval.start < end && interval.end > start {
                result.push(interval);
            }
        }

        result
    }

    /// Clear all intervals
    pub fn clear(&mut self) {
        self.intervals.clear();
        self.prefix_max_end.clear();
    }

    /// Get number of intervals
    pub fn len(&self) -> usize {
        self.intervals.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.intervals.is_empty()
    }

    /// Update offsets (when text changes)
    ///
    /// Call this method to update all intervals when inserting text of `delta` length at position `pos`
    pub fn update_for_insertion(&mut self, pos: usize, delta: usize) {
        for interval in &mut self.intervals {
            if interval.start >= pos {
                interval.start += delta;
                interval.end += delta;
            } else if interval.end > pos {
                // Interval spans insertion point, extend end position
                interval.end += delta;
            }
        }
        self.rebuild_prefix_max_end();
    }

    /// Update offsets (when text is deleted)
    ///
    /// Call this method to update all intervals when deleting text in range `[start, end)`
    pub fn update_for_deletion(&mut self, start: usize, end: usize) {
        let delta = end - start;
        let mut to_remove = Vec::new();

        for (idx, interval) in self.intervals.iter_mut().enumerate() {
            if interval.end <= start {
                // Interval is before deletion range, unaffected
                continue;
            } else if interval.start >= end {
                // Interval is after deletion range, move forward
                interval.start -= delta;
                interval.end -= delta;
            } else if interval.start >= start && interval.end <= end {
                // Interval is completely within deletion range, mark for removal
                to_remove.push(idx);
            } else if interval.start < start && interval.end > end {
                // Interval spans deletion range, shrink
                interval.end -= delta;
            } else if interval.start < start {
                // Interval partially in deletion range (end part)
                interval.end = start;
            } else {
                // Interval partially in deletion range (start part)
                interval.start = start;
                interval.end -= delta;
            }
        }

        // Remove completely deleted intervals
        for idx in to_remove.into_iter().rev() {
            self.intervals.remove(idx);
        }

        self.rebuild_prefix_max_end();
    }
}

impl Default for IntervalTree {
    fn default() -> Self {
        Self::new()
    }
}

/// Fold region
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FoldRegion {
    /// Start line number
    pub start_line: usize,
    /// End line number (inclusive)
    pub end_line: usize,
    /// Whether folded
    pub is_collapsed: bool,
    /// Placeholder text shown when folded (e.g., "[...]")
    pub placeholder: String,
}

impl FoldRegion {
    /// Create a folding region for an inclusive line range.
    pub fn new(start_line: usize, end_line: usize) -> Self {
        Self {
            start_line,
            end_line,
            is_collapsed: false,
            placeholder: String::from("[...]"),
        }
    }

    /// Create a folding region with a custom placeholder string.
    pub fn with_placeholder(start_line: usize, end_line: usize, placeholder: String) -> Self {
        Self {
            start_line,
            end_line,
            is_collapsed: false,
            placeholder,
        }
    }

    /// Expand
    pub fn expand(&mut self) {
        self.is_collapsed = false;
    }

    /// Collapse
    pub fn collapse(&mut self) {
        self.is_collapsed = true;
    }

    /// Toggle fold state
    pub fn toggle(&mut self) {
        self.is_collapsed = !self.is_collapsed;
    }

    /// Check if line number is within fold region
    pub fn contains_line(&self, line: usize) -> bool {
        line >= self.start_line && line <= self.end_line
    }
}

/// Folding manager
pub struct FoldingManager {
    /// Fold regions sourced from external/derived providers (LSP, sublime syntax, etc.).
    derived_regions: Vec<FoldRegion>,
    /// Fold regions created explicitly by the user (via commands).
    user_regions: Vec<FoldRegion>,
    /// Cached merged view (sorted/deduplicated) used for rendering and coordinate mapping.
    merged_regions: Vec<FoldRegion>,
}

impl FoldingManager {
    /// Create an empty folding manager.
    pub fn new() -> Self {
        Self {
            derived_regions: Vec::new(),
            user_regions: Vec::new(),
            merged_regions: Vec::new(),
        }
    }

    fn rebuild_merged_regions(&mut self) {
        self.merged_regions.clear();
        self.merged_regions
            .extend(self.derived_regions.iter().cloned());
        self.merged_regions
            .extend(self.user_regions.iter().cloned());

        self.merged_regions
            .sort_by_key(|r| (r.start_line, r.end_line));
        self.merged_regions
            .dedup_by(|a, b| a.start_line == b.start_line && a.end_line == b.end_line);
    }

    fn normalize_regions(regions: &mut Vec<FoldRegion>) {
        regions.sort_by_key(|r| (r.start_line, r.end_line));
        regions.dedup_by(|a, b| a.start_line == b.start_line && a.end_line == b.end_line);
        regions.retain(|r| r.end_line > r.start_line);
    }

    fn clamp_regions(regions: &mut Vec<FoldRegion>, max_line: usize) {
        for r in regions.iter_mut() {
            r.start_line = r.start_line.min(max_line);
            r.end_line = r.end_line.min(max_line);
        }
        Self::normalize_regions(regions);
    }

    /// Add a user-created fold region.
    pub fn add_region(&mut self, region: FoldRegion) {
        // Keep sorted by start line.
        let pos = self
            .user_regions
            .binary_search_by_key(&region.start_line, |r| r.start_line)
            .unwrap_or_else(|pos| pos);

        self.user_regions.insert(pos, region);
        Self::normalize_regions(&mut self.user_regions);
        self.rebuild_merged_regions();
    }

    /// Remove a user-created fold region.
    pub fn remove_region(&mut self, start_line: usize, end_line: usize) -> bool {
        if let Some(pos) = self
            .user_regions
            .iter()
            .position(|r| r.start_line == start_line && r.end_line == end_line)
        {
            self.user_regions.remove(pos);
            self.rebuild_merged_regions();
            true
        } else {
            false
        }
    }

    /// Get fold region containing specified line (merged view).
    pub fn get_region_for_line(&self, line: usize) -> Option<&FoldRegion> {
        self.merged_regions.iter().find(|r| r.contains_line(line))
    }

    /// Get mutable reference to a fold region containing specified line (prefers user folds).
    pub fn get_region_for_line_mut(&mut self, line: usize) -> Option<&mut FoldRegion> {
        if let Some(region) = self.user_regions.iter_mut().find(|r| r.contains_line(line)) {
            return Some(region);
        }
        self.derived_regions
            .iter_mut()
            .find(|r| r.contains_line(line))
    }

    /// Collapse specified line
    pub fn collapse_line(&mut self, line: usize) -> bool {
        if let Some(region) = self.get_region_for_line_mut(line) {
            region.collapse();
            self.rebuild_merged_regions();
            true
        } else {
            false
        }
    }

    /// Expand specified line
    pub fn expand_line(&mut self, line: usize) -> bool {
        if let Some(region) = self.get_region_for_line_mut(line) {
            region.expand();
            self.rebuild_merged_regions();
            true
        } else {
            false
        }
    }

    /// Toggle fold state of specified line
    pub fn toggle_line(&mut self, line: usize) -> bool {
        if let Some(region) = self.get_region_for_line_mut(line) {
            region.toggle();
            self.rebuild_merged_regions();
            true
        } else {
            false
        }
    }

    /// Toggle fold region starting at specified line (preferring "innermost" region).
    ///
    /// `rust-analyzer` / LSP folding ranges often contain nested regions. To make TUI and other frontends
    /// behave more intuitively when "cursor is on a start line", we choose:
    /// - Among all regions with `start_line == line`, the one with smallest `end_line` (innermost)
    pub fn toggle_region_starting_at_line(&mut self, start_line: usize) -> bool {
        if self.merged_regions.is_empty() {
            return false;
        }

        // Find the innermost region among both sources, preferring user folds on ties.
        let mut best_source = None::<(bool, usize)>; // (is_user, index)
        let mut best_end = usize::MAX;

        for (is_user, regions) in [
            (true, &mut self.user_regions),
            (false, &mut self.derived_regions),
        ] {
            let Ok(mut idx) = regions.binary_search_by_key(&start_line, |r| r.start_line) else {
                continue;
            };

            while idx > 0 && regions[idx - 1].start_line == start_line {
                idx -= 1;
            }

            for i in idx..regions.len() {
                let region = &regions[i];
                if region.start_line != start_line {
                    break;
                }
                if region.end_line <= region.start_line {
                    continue;
                }
                if region.end_line < best_end
                    || (region.end_line == best_end
                        && best_source.is_some_and(|(prev_is_user, _)| !prev_is_user && is_user))
                {
                    best_end = region.end_line;
                    best_source = Some((is_user, i));
                }
            }
        }

        let Some((is_user, idx)) = best_source else {
            return false;
        };

        if is_user {
            if let Some(region) = self.user_regions.get_mut(idx) {
                region.toggle();
            }
        } else if let Some(region) = self.derived_regions.get_mut(idx) {
            region.toggle();
        }

        self.rebuild_merged_regions();
        true
    }

    /// Calculate mapping from logical line to visual line
    ///
    /// Returns the visual line number for the specified logical line number, or None if folded
    pub fn logical_to_visual(&self, logical_line: usize, base_visual: usize) -> Option<usize> {
        let mut hidden_lines = 0;

        for region in &self.merged_regions {
            if region.is_collapsed {
                if logical_line > region.start_line && logical_line <= region.end_line {
                    // This line is folded
                    return None;
                } else if logical_line > region.end_line {
                    // This fold region is before the target line, count hidden lines
                    hidden_lines += region.end_line - region.start_line;
                }
            }
        }

        Some(base_visual + logical_line - hidden_lines)
    }

    /// Calculate mapping from visual line to logical line
    pub fn visual_to_logical(&self, visual_line: usize, base_visual: usize) -> usize {
        let mut logical = visual_line - base_visual;

        for region in &self.merged_regions {
            if region.is_collapsed {
                let hidden_lines = region.end_line - region.start_line;

                if logical == region.start_line {
                    // Visual line is exactly the fold start line
                    return region.start_line;
                } else if logical > region.start_line {
                    // Visual line is after fold region, need to add hidden lines
                    logical += hidden_lines;
                }
            }
        }

        logical
    }

    /// Get all fold regions
    pub fn regions(&self) -> &[FoldRegion] {
        &self.merged_regions
    }

    /// Get all derived fold regions.
    pub fn derived_regions(&self) -> &[FoldRegion] {
        &self.derived_regions
    }

    /// Get all user-created fold regions.
    pub fn user_regions(&self) -> &[FoldRegion] {
        &self.user_regions
    }

    /// Clear all fold regions (derived + user).
    pub fn clear(&mut self) {
        self.derived_regions.clear();
        self.user_regions.clear();
        self.merged_regions.clear();
    }

    /// Clear all derived fold regions, leaving user folds intact.
    pub fn clear_derived_regions(&mut self) {
        self.derived_regions.clear();
        self.rebuild_merged_regions();
    }

    /// Replace derived fold regions (will be sorted by start line and deduplicated).
    pub fn replace_derived_regions(&mut self, mut regions: Vec<FoldRegion>) {
        Self::normalize_regions(&mut regions);
        self.derived_regions = regions;
        self.rebuild_merged_regions();
    }

    /// Replace fold regions with new list (legacy API).
    ///
    /// This replaces *derived* fold regions, leaving user folds intact.
    pub fn replace_regions(&mut self, regions: Vec<FoldRegion>) {
        self.replace_derived_regions(regions);
    }

    /// Expand all folds
    pub fn expand_all(&mut self) {
        for region in &mut self.derived_regions {
            region.expand();
        }
        for region in &mut self.user_regions {
            region.expand();
        }
        self.rebuild_merged_regions();
    }

    /// Collapse all regions
    pub fn collapse_all(&mut self) {
        for region in &mut self.derived_regions {
            region.collapse();
        }
        for region in &mut self.user_regions {
            region.collapse();
        }
        self.rebuild_merged_regions();
    }

    /// Update fold regions to account for an edit that changes the number of logical lines.
    ///
    /// This is intended to keep **user folds** stable across newline insertions/deletions.
    ///
    /// - `edit_line` is the logical line where the edit occurred (pre-edit).
    /// - `line_delta` is the net change in line count (`+n` for inserted newlines, `-n` for deleted).
    pub fn apply_line_delta(&mut self, edit_line: usize, line_delta: isize) {
        if line_delta == 0 {
            return;
        }

        let apply = |regions: &mut Vec<FoldRegion>| {
            for region in regions.iter_mut() {
                if edit_line <= region.start_line {
                    let start = region.start_line as isize + line_delta;
                    let end = region.end_line as isize + line_delta;
                    region.start_line = start.max(0) as usize;
                    region.end_line = end.max(0) as usize;
                } else if edit_line <= region.end_line {
                    let end = region.end_line as isize + line_delta;
                    region.end_line = end.max(region.start_line as isize) as usize;
                }
            }
        };

        apply(&mut self.derived_regions);
        apply(&mut self.user_regions);
    }

    /// Clamp fold regions to the given `line_count` after a text edit, dropping invalid regions.
    pub fn clamp_to_line_count(&mut self, line_count: usize) {
        let max_line = line_count.saturating_sub(1);
        Self::clamp_regions(&mut self.derived_regions, max_line);
        Self::clamp_regions(&mut self.user_regions, max_line);
        self.rebuild_merged_regions();
    }
}

impl Default for FoldingManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_interval_contains() {
        let interval = Interval::new(10, 20, 1);
        assert!(interval.contains(10));
        assert!(interval.contains(15));
        assert!(interval.contains(19));
        assert!(!interval.contains(20));
        assert!(!interval.contains(9));
    }

    #[test]
    fn test_interval_overlaps() {
        let i1 = Interval::new(10, 20, 1);
        let i2 = Interval::new(15, 25, 2);
        let i3 = Interval::new(25, 30, 3);

        assert!(i1.overlaps(&i2));
        assert!(i2.overlaps(&i1));
        assert!(!i1.overlaps(&i3));
        assert!(!i3.overlaps(&i1));
    }

    #[test]
    fn test_interval_tree_insert() {
        let mut tree = IntervalTree::new();
        tree.insert(Interval::new(10, 20, 1));
        tree.insert(Interval::new(5, 15, 2));
        tree.insert(Interval::new(15, 25, 3));

        assert_eq!(tree.len(), 3);
    }

    #[test]
    fn test_interval_tree_query_point() {
        let mut tree = IntervalTree::new();
        tree.insert(Interval::new(10, 20, 1));
        tree.insert(Interval::new(5, 15, 2));
        tree.insert(Interval::new(15, 25, 3));

        let results = tree.query_point(12);
        assert_eq!(results.len(), 2); // intervals 1 and 2

        let results = tree.query_point(18);
        assert_eq!(results.len(), 2); // intervals 1 and 3
    }

    #[test]
    fn test_interval_tree_query_point_prunes_scan() {
        let mut tree = IntervalTree::new();

        // Construct many non-overlapping intervals: ideally point query should only need to check few candidate intervals.
        for i in 0..10_000usize {
            let start = i * 2;
            tree.insert(Interval::new(start, start + 1, 1));
        }

        let pos = 2 * 10_000 - 2; // Falls within last interval
        let results = tree.query_point(pos);
        assert_eq!(results.len(), 1);

        // After pruning with prefix_max_end, should avoid degrading to linear scan of all intervals.
        assert!(
            tree.query_point_scan_count(pos) <= 4,
            "scan should be pruned for disjoint intervals"
        );
    }

    #[test]
    fn test_interval_tree_query_range() {
        let mut tree = IntervalTree::new();
        tree.insert(Interval::new(10, 20, 1));
        tree.insert(Interval::new(25, 35, 2));
        tree.insert(Interval::new(40, 50, 3));

        let results = tree.query_range(15, 30);
        assert_eq!(results.len(), 2); // intervals 1 and 2

        let results = tree.query_range(0, 60);
        assert_eq!(results.len(), 3); // all intervals
    }

    #[test]
    fn test_interval_tree_update_insertion() {
        let mut tree = IntervalTree::new();
        tree.insert(Interval::new(10, 20, 1));
        tree.insert(Interval::new(30, 40, 2));

        tree.update_for_insertion(15, 5);

        assert_eq!(tree.intervals[0].start, 10);
        assert_eq!(tree.intervals[0].end, 25); // 20 + 5

        assert_eq!(tree.intervals[1].start, 35); // 30 + 5
        assert_eq!(tree.intervals[1].end, 45); // 40 + 5
    }

    #[test]
    fn test_interval_tree_update_deletion() {
        let mut tree = IntervalTree::new();
        tree.insert(Interval::new(10, 20, 1));
        tree.insert(Interval::new(30, 40, 2));
        tree.insert(Interval::new(50, 60, 3));

        tree.update_for_deletion(25, 35);

        assert_eq!(tree.intervals[0].start, 10);
        assert_eq!(tree.intervals[0].end, 20); // Unaffected

        assert_eq!(tree.intervals[1].start, 25); // 30 - (35-25)
        assert_eq!(tree.intervals[1].end, 30); // 40 - (35-25)

        assert_eq!(tree.intervals[2].start, 40); // 50 - 10
        assert_eq!(tree.intervals[2].end, 50); // 60 - 10
    }

    #[test]
    fn test_fold_region() {
        let mut region = FoldRegion::new(5, 10);
        assert!(!region.is_collapsed);

        region.collapse();
        assert!(region.is_collapsed);

        region.expand();
        assert!(!region.is_collapsed);

        region.toggle();
        assert!(region.is_collapsed);
    }

    #[test]
    fn test_folding_manager() {
        let mut manager = FoldingManager::new();

        manager.add_region(FoldRegion::new(5, 10));
        manager.add_region(FoldRegion::new(15, 20));

        assert!(manager.collapse_line(7));
        assert!(manager.get_region_for_line(7).unwrap().is_collapsed);

        assert!(manager.expand_line(7));
        assert!(!manager.get_region_for_line(7).unwrap().is_collapsed);
    }

    #[test]
    fn test_logical_to_visual_with_folding() {
        let mut manager = FoldingManager::new();

        let mut region = FoldRegion::new(5, 10);
        region.collapse();
        manager.add_region(region);

        // Line before fold
        assert_eq!(manager.logical_to_visual(3, 0), Some(3));

        // Fold start line
        assert_eq!(manager.logical_to_visual(5, 0), Some(5));

        // Middle line of fold should return None
        assert_eq!(manager.logical_to_visual(7, 0), None);

        // Line after fold should have adjusted position
        assert_eq!(manager.logical_to_visual(15, 0), Some(10)); // 15 - 5 hidden lines
    }

    #[test]
    fn test_multiple_overlapping_styles() {
        let mut tree = IntervalTree::new();

        // Add overlapping style intervals
        tree.insert(Interval::new(0, 100, 1)); // Syntax highlighting
        tree.insert(Interval::new(20, 30, 2)); // Search highlighting
        tree.insert(Interval::new(25, 35, 3)); // Selection region

        // Query position 27, should have 3 styles
        let styles = tree.query_point(27);
        assert_eq!(styles.len(), 3);

        // Verify all styles were found
        let style_ids: Vec<StyleId> = styles.iter().map(|i| i.style_id).collect();
        assert!(style_ids.contains(&1));
        assert!(style_ids.contains(&2));
        assert!(style_ids.contains(&3));
    }
}
