//! Workspace and multi-document model.
//!
//! `editor-core` is intentionally UI-agnostic, but a full-featured editor typically needs a
//! kernel-level model for managing multiple open documents/buffers.
//!
//! This module provides a small `Workspace` type that owns multiple [`EditorStateManager`]
//! instances and provides:
//! - stable, opaque document ids
//! - optional URI->document lookup for integrations (e.g. LSP)
//! - an "active document" convenience slot (host-driven)

use crate::EditorStateManager;
use std::collections::{BTreeMap, HashMap};

/// Opaque identifier for an open document in a [`Workspace`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DocumentId(u64);

impl DocumentId {
    /// Get the underlying numeric id.
    pub fn get(self) -> u64 {
        self.0
    }
}

/// Metadata attached to a workspace document.
#[derive(Debug, Clone)]
pub struct DocumentMetadata {
    /// Optional document URI/path (host-provided).
    pub uri: Option<String>,
}

struct DocumentEntry {
    meta: DocumentMetadata,
    state: EditorStateManager,
}

/// Workspace-level errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceError {
    /// A document with this uri already exists.
    UriAlreadyOpen(String),
    /// A document id was not found.
    DocumentNotFound(DocumentId),
}

/// A collection of open documents/buffers and their state.
#[derive(Default)]
pub struct Workspace {
    next_id: u64,
    documents: BTreeMap<DocumentId, DocumentEntry>,
    uri_to_id: HashMap<String, DocumentId>,
    active: Option<DocumentId>,
}

impl std::fmt::Debug for Workspace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Workspace")
            .field("next_id", &self.next_id)
            .field("document_count", &self.documents.len())
            .field("uri_count", &self.uri_to_id.len())
            .field("active", &self.active)
            .finish()
    }
}

impl Workspace {
    /// Create an empty workspace.
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the number of open documents.
    pub fn len(&self) -> usize {
        self.documents.len()
    }

    /// Returns `true` if there are no open documents.
    pub fn is_empty(&self) -> bool {
        self.documents.is_empty()
    }

    /// Return the active document id (if any).
    pub fn active_document_id(&self) -> Option<DocumentId> {
        self.active
    }

    /// Set the active document.
    pub fn set_active_document(&mut self, id: DocumentId) -> Result<(), WorkspaceError> {
        if !self.documents.contains_key(&id) {
            return Err(WorkspaceError::DocumentNotFound(id));
        }
        self.active = Some(id);
        Ok(())
    }

    /// Open a new document in the workspace.
    ///
    /// - `uri` is optional and host-provided (e.g. `file:///...`).
    /// - `text` is the initial contents.
    pub fn open_document(
        &mut self,
        uri: Option<String>,
        text: &str,
        viewport_width: usize,
    ) -> Result<DocumentId, WorkspaceError> {
        if let Some(uri) = uri.as_ref()
            && self.uri_to_id.contains_key(uri)
        {
            return Err(WorkspaceError::UriAlreadyOpen(uri.clone()));
        }

        let id = DocumentId(self.next_id);
        self.next_id = self.next_id.saturating_add(1);

        let state = EditorStateManager::new(text, viewport_width);
        let meta = DocumentMetadata { uri: uri.clone() };

        if let Some(uri) = uri {
            self.uri_to_id.insert(uri, id);
        }
        self.documents.insert(id, DocumentEntry { meta, state });

        if self.active.is_none() {
            self.active = Some(id);
        }

        Ok(id)
    }

    /// Close a document.
    pub fn close_document(&mut self, id: DocumentId) -> Result<(), WorkspaceError> {
        let Some(entry) = self.documents.remove(&id) else {
            return Err(WorkspaceError::DocumentNotFound(id));
        };

        if let Some(uri) = entry.meta.uri.as_ref() {
            self.uri_to_id.remove(uri);
        }

        if self.active == Some(id) {
            self.active = self.documents.keys().next().copied();
        }

        Ok(())
    }

    /// Look up a document by uri.
    pub fn document_id_for_uri(&self, uri: &str) -> Option<DocumentId> {
        self.uri_to_id.get(uri).copied()
    }

    /// Get a document's metadata.
    pub fn document_metadata(&self, id: DocumentId) -> Option<&DocumentMetadata> {
        self.documents.get(&id).map(|e| &e.meta)
    }

    /// Update a document's uri/path.
    pub fn set_document_uri(
        &mut self,
        id: DocumentId,
        uri: Option<String>,
    ) -> Result<(), WorkspaceError> {
        let Some(entry) = self.documents.get_mut(&id) else {
            return Err(WorkspaceError::DocumentNotFound(id));
        };

        if let Some(next) = uri.as_ref()
            && self.uri_to_id.contains_key(next)
            && entry.meta.uri.as_deref() != Some(next.as_str())
        {
            return Err(WorkspaceError::UriAlreadyOpen(next.clone()));
        }

        if let Some(prev) = entry.meta.uri.take() {
            self.uri_to_id.remove(&prev);
        }

        if let Some(next) = uri.clone() {
            self.uri_to_id.insert(next, id);
        }

        entry.meta.uri = uri;
        Ok(())
    }

    /// Get an immutable reference to a document state manager.
    pub fn document(&self, id: DocumentId) -> Option<&EditorStateManager> {
        self.documents.get(&id).map(|e| &e.state)
    }

    /// Get a mutable reference to a document state manager.
    pub fn document_mut(&mut self, id: DocumentId) -> Option<&mut EditorStateManager> {
        self.documents.get_mut(&id).map(|e| &mut e.state)
    }

    /// Get the active document (if any).
    pub fn active_document(&self) -> Option<&EditorStateManager> {
        let id = self.active?;
        self.document(id)
    }

    /// Get the active document mutably (if any).
    pub fn active_document_mut(&mut self) -> Option<&mut EditorStateManager> {
        let id = self.active?;
        self.document_mut(id)
    }

    /// Iterate over open documents in `DocumentId` order.
    pub fn iter(&self) -> impl Iterator<Item = (DocumentId, &EditorStateManager)> {
        self.documents.iter().map(|(id, entry)| (*id, &entry.state))
    }
}
