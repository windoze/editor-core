use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct WindowId(u64);

impl WindowId {
    pub const fn from_raw(id: u64) -> Self {
        Self(id)
    }

    pub fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PaneId(u64);

impl PaneId {
    pub const fn from_raw(id: u64) -> Self {
        Self(id)
    }

    pub fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SplitDirection {
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone)]
enum Node {
    Leaf(PaneId),
    Split {
        #[allow(dead_code)]
        direction: SplitDirection,
        a: Box<Node>,
        b: Box<Node>,
    },
}

#[derive(Debug, Clone)]
pub struct PaneLayout {
    next_pane_id: u64,
    root: Node,
}

impl PaneLayout {
    pub fn new_single() -> (Self, PaneId) {
        let id = PaneId(1);
        (
            Self {
                next_pane_id: 2,
                root: Node::Leaf(id),
            },
            id,
        )
    }

    pub fn leaf_panes(&self) -> Vec<PaneId> {
        let mut out = Vec::new();
        self.root.collect_leaves(&mut out);
        out
    }

    pub fn split(&mut self, pane: PaneId, direction: SplitDirection) -> Option<(PaneId, PaneId)> {
        let new_id = PaneId(self.next_pane_id);
        self.next_pane_id = self.next_pane_id.saturating_add(1);

        let replaced = self.root.replace_leaf_with_split(pane, direction, new_id);
        replaced.then(|| (pane, new_id))
    }

    pub fn focus_next(&self, current: PaneId) -> PaneId {
        let leaves = self.leaf_panes();
        if leaves.is_empty() {
            return current;
        }
        let idx = leaves.iter().position(|p| *p == current).unwrap_or(0);
        leaves[(idx + 1) % leaves.len()]
    }

    pub fn focus_prev(&self, current: PaneId) -> PaneId {
        let leaves = self.leaf_panes();
        if leaves.is_empty() {
            return current;
        }
        let idx = leaves.iter().position(|p| *p == current).unwrap_or(0);
        let prev = if idx == 0 { leaves.len() - 1 } else { idx - 1 };
        leaves[prev]
    }
}

impl Node {
    fn collect_leaves(&self, out: &mut Vec<PaneId>) {
        match self {
            Self::Leaf(id) => out.push(*id),
            Self::Split { a, b, .. } => {
                a.collect_leaves(out);
                b.collect_leaves(out);
            }
        }
    }

    fn replace_leaf_with_split(
        &mut self,
        target: PaneId,
        direction: SplitDirection,
        new_pane: PaneId,
    ) -> bool {
        match self {
            Self::Leaf(id) => {
                if *id != target {
                    return false;
                }
                *self = Self::Split {
                    direction,
                    a: Box::new(Self::Leaf(*id)),
                    b: Box::new(Self::Leaf(new_pane)),
                };
                true
            }
            Self::Split { a, b, .. } => {
                if a.replace_leaf_with_split(target, direction, new_pane) {
                    return true;
                }
                b.replace_leaf_with_split(target, direction, new_pane)
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct WindowManager {
    next_window_id: u64,
    windows: BTreeMap<WindowId, PaneLayout>,
    active_window: Option<WindowId>,
    active_pane: BTreeMap<WindowId, PaneId>,
}

impl Default for WindowManager {
    fn default() -> Self {
        Self::new()
    }
}

impl WindowManager {
    pub fn new() -> Self {
        Self {
            next_window_id: 1,
            windows: BTreeMap::new(),
            active_window: None,
            active_pane: BTreeMap::new(),
        }
    }

    pub fn create_window(&mut self) -> WindowId {
        let id = WindowId(self.next_window_id);
        self.next_window_id = self.next_window_id.saturating_add(1);
        let (layout, pane) = PaneLayout::new_single();
        self.windows.insert(id, layout);
        self.active_pane.insert(id, pane);
        if self.active_window.is_none() {
            self.active_window = Some(id);
        }
        id
    }

    pub fn window_ids(&self) -> Vec<WindowId> {
        self.windows.keys().copied().collect()
    }

    pub fn active_window_id(&self) -> Option<WindowId> {
        self.active_window
    }

    pub fn set_active_window(&mut self, id: WindowId) -> bool {
        if !self.windows.contains_key(&id) {
            return false;
        }
        self.active_window = Some(id);
        true
    }

    pub fn active_pane_id(&self) -> Option<PaneId> {
        let win = self.active_window?;
        self.active_pane.get(&win).copied()
    }

    pub fn split_active_pane(&mut self, direction: SplitDirection) -> Option<PaneId> {
        let win = self.active_window?;
        let pane = *self.active_pane.get(&win)?;
        let layout = self.windows.get_mut(&win)?;
        let (_a, b) = layout.split(pane, direction)?;
        self.active_pane.insert(win, b);
        Some(b)
    }

    pub fn focus_next_pane(&mut self) -> Option<PaneId> {
        let win = self.active_window?;
        let current = *self.active_pane.get(&win)?;
        let layout = self.windows.get(&win)?;
        let next = layout.focus_next(current);
        self.active_pane.insert(win, next);
        Some(next)
    }

    pub fn focus_prev_pane(&mut self) -> Option<PaneId> {
        let win = self.active_window?;
        let current = *self.active_pane.get(&win)?;
        let layout = self.windows.get(&win)?;
        let prev = layout.focus_prev(current);
        self.active_pane.insert(win, prev);
        Some(prev)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn pane_layout_splits_and_cycles_focus() {
        let (mut layout, p0) = PaneLayout::new_single();
        let (_a, p1) = layout.split(p0, SplitDirection::Vertical).unwrap();
        assert_eq!(layout.leaf_panes(), vec![p0, p1]);
        assert_eq!(layout.focus_next(p0), p1);
        assert_eq!(layout.focus_next(p1), p0);
        assert_eq!(layout.focus_prev(p0), p1);
    }

    #[test]
    fn window_manager_tracks_active_window_and_pane() {
        let mut wm = WindowManager::new();
        let w0 = wm.create_window();
        assert_eq!(wm.active_window_id(), Some(w0));
        let p0 = wm.active_pane_id().unwrap();
        let p1 = wm.split_active_pane(SplitDirection::Horizontal).unwrap();
        assert_ne!(p0, p1);
        assert_eq!(wm.active_pane_id(), Some(p1));
        wm.focus_prev_pane().unwrap();
        assert_eq!(wm.active_pane_id(), Some(p0));
    }
}
