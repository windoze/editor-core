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

        // Keep IDs dense for fast reverse lookup.
        //
        // Reserved indices within `BASE` range:
        // - 0: unused
        // - 1: `editor_core::intervals::FOLD_PLACEHOLDER_STYLE_ID` (0x0300_0001)
        //
        // Actual Sublime scopes start at index 2 to avoid collisions.
        let idx = self.id_to_scope.len() as u32 + 2;
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
        let raw = style_id & 0x00FF_FFFF;
        if raw < 2 {
            return None;
        }
        let idx = (raw - 2) as usize;
        self.id_to_scope.get(idx).map(|s| s.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mapper_reserves_fold_placeholder_style_id() {
        let mut mapper = SublimeScopeMapper::new();

        // The first allocated scope must not collide with FOLD_PLACEHOLDER_STYLE_ID (0x0300_0001).
        let id = mapper.style_id_for_scope("comment.line.test");
        assert_eq!(id, SublimeScopeMapper::BASE | 2);
        assert_eq!(mapper.scope_for_style_id(id), Some("comment.line.test"));

        // Index 1 is reserved and should not resolve to a scope string.
        assert_eq!(
            mapper.scope_for_style_id(SublimeScopeMapper::BASE | 1),
            None
        );
    }
}
