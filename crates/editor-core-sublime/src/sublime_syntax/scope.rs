use editor_core::intervals::StyleId;
use std::collections::HashMap;

/// A simple scope-to-`StyleId` mapper for `.sublime-syntax` scopes.
///
/// Consumers are expected to keep a mapper instance around so `StyleId`s stay
/// stable across re-highlighting passes.
#[derive(Debug, Default)]
pub struct SublimeScopeMapper {
    scope_to_id: HashMap<String, StyleId>,
    id_to_scope: Vec<String>,
}

impl SublimeScopeMapper {
    /// Base prefix for Sublime scope `StyleId`s.
    ///
    /// Values below this are reserved for other style sources (e.g. semantic
    /// tokens, simple regex highlighting).
    pub const BASE: StyleId = 0x0300_0000;

    /// Create a new scope mapper.
    pub fn new() -> Self {
        Self::default()
    }

    /// Get (or allocate) a stable `StyleId` for a Sublime scope string.
    pub fn style_id_for_scope(&mut self, scope: &str) -> StyleId {
        if let Some(&id) = self.scope_to_id.get(scope) {
            return id;
        }

        // Keep IDs dense for fast reverse lookup. 0 is unused within this range.
        let idx = self.id_to_scope.len() as u32 + 1;
        let id = Self::BASE | idx;

        self.id_to_scope.push(scope.to_string());
        self.scope_to_id.insert(scope.to_string(), id);
        id
    }

    /// Return the original scope string for a previously allocated `StyleId`.
    pub fn scope_for_style_id(&self, style_id: StyleId) -> Option<&str> {
        if style_id & 0xFF00_0000 != Self::BASE {
            return None;
        }
        let idx = (style_id & 0x00FF_FFFF).saturating_sub(1) as usize;
        self.id_to_scope.get(idx).map(|s| s.as_str())
    }
}
