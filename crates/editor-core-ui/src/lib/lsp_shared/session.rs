use crate::UiError;
use crate::prelude::*;
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct SharedLspKey {
    pub(crate) cmd: String,
    pub(crate) args: Vec<String>,
    pub(crate) root_uri: String,
}

pub(crate) struct SharedLspSession {
    pub(crate) cmd: String,
    pub(crate) args: Vec<String>,
    pub(crate) root_uris: Mutex<BTreeSet<String>>,
    pub(crate) session: Mutex<Option<LspSession>>,
}

impl SharedLspSession {
    pub(crate) fn with_session_mut<R>(
        &self,
        f: impl FnOnce(&mut LspSession) -> Result<R, String>,
    ) -> Result<R, String> {
        let mut guard = self
            .session
            .lock()
            .map_err(|_| "LSP session lock poisoned".to_string())?;

        let Some(session) = guard.as_mut() else {
            return Err("LSP session is not available".to_string());
        };

        match f(session) {
            Ok(v) => Ok(v),
            Err(err) => {
                // Mark the shared session as dead so other users can fail fast.
                *guard = None;
                Err(err)
            }
        }
    }

    pub(crate) fn shutdown(&self) -> Result<bool, String> {
        let mut guard = self
            .session
            .lock()
            .map_err(|_| "LSP session lock poisoned".to_string())?;

        let Some(mut session) = guard.take() else {
            return Ok(false);
        };

        session.exit()?;
        Ok(true)
    }

    pub(crate) fn is_alive(&self) -> bool {
        self.session
            .lock()
            .map(|guard| guard.is_some())
            .unwrap_or(false)
    }

    pub(crate) fn update_root_aliases(
        self: &Arc<Self>,
        added: &[serde_json::Value],
        removed: &[serde_json::Value],
    ) {
        let added_roots = added
            .iter()
            .filter_map(workspace_folder_uri)
            .collect::<Vec<_>>();
        let removed_roots = removed
            .iter()
            .filter_map(workspace_folder_uri)
            .collect::<Vec<_>>();

        if added_roots.is_empty() && removed_roots.is_empty() {
            return;
        }

        if let Ok(mut root_uris) = self.root_uris.lock() {
            for root in &removed_roots {
                root_uris.remove(root);
            }
            for root in &added_roots {
                root_uris.insert(root.clone());
            }
        }

        let Ok(mut pool) = shared_lsp_pool().lock() else {
            return;
        };

        for root in removed_roots {
            let key = self.key_for_root(root);
            if pool
                .get(&key)
                .and_then(|weak| weak.upgrade())
                .is_some_and(|existing| Arc::ptr_eq(&existing, self))
            {
                pool.remove(&key);
            }
        }

        for root in added_roots {
            let key = self.key_for_root(root);
            let should_insert = match pool.get(&key).and_then(|weak| weak.upgrade()) {
                Some(existing) => Arc::ptr_eq(&existing, self) || existing.is_alive() == false,
                None => true,
            };
            if should_insert {
                pool.insert(key, Arc::downgrade(self));
            }
        }
    }

    fn key_for_root(&self, root_uri: String) -> SharedLspKey {
        SharedLspKey {
            cmd: self.cmd.clone(),
            args: self.args.clone(),
            root_uri,
        }
    }
}

impl Drop for SharedLspSession {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

static SHARED_LSP_POOL: OnceLock<Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>>> =
    OnceLock::new();

fn shared_lsp_pool() -> &'static Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>> {
    SHARED_LSP_POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn get_or_start_shared_lsp_session(
    key: SharedLspKey,
    start: LspSessionStartOptions,
) -> Result<Arc<SharedLspSession>, UiError> {
    // Fast path: try an existing session.
    if let Ok(mut pool) = shared_lsp_pool().lock() {
        if let Some(existing) = pool.get(&key).and_then(|w| w.upgrade()) {
            if existing.is_alive() {
                return Ok(existing);
            }
        }
        // Drop stale weak entries.
        pool.remove(&key);
    }

    // Start outside the pool lock.
    let session = LspSession::start(start).map_err(|e| UiError::Processor(e.to_string()))?;
    let initial_root_uri = key.root_uri.clone();
    let shared = Arc::new(SharedLspSession {
        cmd: key.cmd.clone(),
        args: key.args.clone(),
        root_uris: Mutex::new(root_uri_set([initial_root_uri])),
        session: Mutex::new(Some(session)),
    });

    if let Ok(mut pool) = shared_lsp_pool().lock() {
        pool.insert(key, Arc::downgrade(&shared));
    }

    Ok(shared)
}

fn workspace_folder_uri(folder: &serde_json::Value) -> Option<String> {
    folder
        .get("uri")
        .and_then(serde_json::Value::as_str)
        .map(normalize_root_uri)
        .filter(|uri| uri.is_empty() == false)
}

fn normalize_root_uri(root_uri: &str) -> String {
    root_uri.trim().trim_end_matches('/').to_string()
}

fn root_uri_set<I>(roots: I) -> BTreeSet<String>
where
    I: IntoIterator<Item = String>,
{
    roots
        .into_iter()
        .map(|root| normalize_root_uri(root.as_str()))
        .filter(|root| root.is_empty() == false)
        .collect()
}
