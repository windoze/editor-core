use super::set::FontVariant;
use skia_safe::{GlyphId, Point};
use std::collections::{HashMap, VecDeque};

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(in crate::renderer) struct ShapedRunKey {
    pub(in crate::renderer) text: String,
    pub(in crate::renderer) font_variant: FontVariant,
    pub(in crate::renderer) font_index: usize,
    pub(in crate::renderer) cell_width_bits: u32,
    pub(in crate::renderer) enable_ligatures: bool,
}

#[derive(Debug, Clone)]
pub(in crate::renderer) struct ShapedRun {
    pub(in crate::renderer) glyphs: Vec<GlyphId>,
    pub(in crate::renderer) positions: Vec<Point>,
}

#[derive(Debug)]
pub(in crate::renderer) struct ShapedRunCache {
    entries: HashMap<ShapedRunKey, ShapedRun>,
    order: VecDeque<ShapedRunKey>,
    capacity: usize,
}

impl ShapedRunCache {
    pub(super) fn new(capacity: usize) -> Self {
        Self {
            entries: HashMap::new(),
            order: VecDeque::new(),
            capacity: capacity.max(1),
        }
    }

    pub(super) fn clear(&mut self) {
        self.entries.clear();
        self.order.clear();
    }

    pub(super) fn get(&self, key: &ShapedRunKey) -> Option<&ShapedRun> {
        self.entries.get(key)
    }

    pub(super) fn insert(&mut self, key: ShapedRunKey, run: ShapedRun) {
        if self.capacity == 0 {
            return;
        }

        match self.entries.entry(key) {
            std::collections::hash_map::Entry::Occupied(mut e) => {
                // Keep insertion idempotent; do not grow `order` with duplicates.
                e.insert(run);
                return;
            }
            std::collections::hash_map::Entry::Vacant(e) => {
                let key = e.key().clone();
                e.insert(run);
                self.order.push_back(key);
            }
        }

        while self.order.len() > self.capacity {
            if let Some(old) = self.order.pop_front() {
                self.entries.remove(&old);
            }
        }
    }
}
