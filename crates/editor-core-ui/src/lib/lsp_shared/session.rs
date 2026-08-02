use crate::UiError;
use crate::prelude::*;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct SharedLspKey {
    pub(crate) cmd: String,
    pub(crate) args: Vec<String>,
    pub(crate) root_uri: String,
}

pub(crate) struct SharedLspSession {
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
}

impl Drop for SharedLspSession {
    fn drop(&mut self) {
        let Ok(mut guard) = self.session.lock() else {
            return;
        };
        let Some(mut session) = guard.take() else {
            return;
        };
        let _ = session.exit();
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
            return Ok(existing);
        }
        // Drop stale weak entries.
        pool.remove(&key);
    }

    // Start outside the pool lock.
    let session = LspSession::start(start).map_err(|e| UiError::Processor(e.to_string()))?;
    let shared = Arc::new(SharedLspSession {
        session: Mutex::new(Some(session)),
    });

    if let Ok(mut pool) = shared_lsp_pool().lock() {
        pool.insert(key, Arc::downgrade(&shared));
    }

    Ok(shared)
}
