use super::*;

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

static SHARED_LSP_POOL: OnceLock<Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>>> =
    OnceLock::new();

pub(crate) fn shared_lsp_pool() -> &'static Mutex<HashMap<SharedLspKey, Weak<SharedLspSession>>> {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum LspResultSlot {
    Hover,
    Definition,
    Declaration,
    TypeDefinition,
    Implementation,
    References,
    Completion,
    CompletionResolve,
    SignatureHelp,
    PrepareRename,
    Rename,
    CodeAction,
    CodeActionResolve,
    ExecuteCommand,
    CodeLens,
    CodeLensResolve,
    DocumentSymbols,
    WorkspaceSymbols,
    FoldingRanges,
    SelectionRange,
    LinkedEditingRange,
    DocumentDiagnostic,
    WorkspaceDiagnostic,
    DocumentColor,
    ColorPresentation,
    PrepareCallHierarchy,
    CallHierarchyIncoming,
    CallHierarchyOutgoing,
    PrepareTypeHierarchy,
    TypeHierarchySupertypes,
    TypeHierarchySubtypes,
}

impl LspResultSlot {
    pub(crate) fn from_response_method(method: &str) -> Option<Self> {
        match method {
            "textDocument/hover" => Some(Self::Hover),
            "textDocument/definition" => Some(Self::Definition),
            "textDocument/declaration" => Some(Self::Declaration),
            "textDocument/typeDefinition" => Some(Self::TypeDefinition),
            "textDocument/implementation" => Some(Self::Implementation),
            "textDocument/references" => Some(Self::References),
            "textDocument/completion" => Some(Self::Completion),
            "completionItem/resolve" => Some(Self::CompletionResolve),
            "textDocument/signatureHelp" => Some(Self::SignatureHelp),
            "textDocument/prepareRename" => Some(Self::PrepareRename),
            "textDocument/rename" => Some(Self::Rename),
            "textDocument/codeAction" => Some(Self::CodeAction),
            "codeAction/resolve" => Some(Self::CodeActionResolve),
            "workspace/executeCommand" => Some(Self::ExecuteCommand),
            "textDocument/codeLens" => Some(Self::CodeLens),
            "codeLens/resolve" => Some(Self::CodeLensResolve),
            "textDocument/documentSymbol" => Some(Self::DocumentSymbols),
            "workspace/symbol" => Some(Self::WorkspaceSymbols),
            "textDocument/foldingRange" => Some(Self::FoldingRanges),
            "textDocument/selectionRange" => Some(Self::SelectionRange),
            "textDocument/linkedEditingRange" => Some(Self::LinkedEditingRange),
            "textDocument/diagnostic" => Some(Self::DocumentDiagnostic),
            "workspace/diagnostic" => Some(Self::WorkspaceDiagnostic),
            "textDocument/documentColor" => Some(Self::DocumentColor),
            "textDocument/colorPresentation" => Some(Self::ColorPresentation),
            "textDocument/prepareCallHierarchy" => Some(Self::PrepareCallHierarchy),
            "callHierarchy/incomingCalls" => Some(Self::CallHierarchyIncoming),
            "callHierarchy/outgoingCalls" => Some(Self::CallHierarchyOutgoing),
            "textDocument/prepareTypeHierarchy" => Some(Self::PrepareTypeHierarchy),
            "typeHierarchy/supertypes" => Some(Self::TypeHierarchySupertypes),
            "typeHierarchy/subtypes" => Some(Self::TypeHierarchySubtypes),
            _ => None,
        }
    }
}

pub(crate) fn stored_lsp_error_result_json(
    slot: LspResultSlot,
    error: LspResponseError,
) -> Option<String> {
    if slot != LspResultSlot::ExecuteCommand && slot != LspResultSlot::CodeLens {
        return None;
    }

    Some(
        serde_json::json!({
            "error": {
                "code": error.code,
                "message": error.message,
                "data": error.data,
            }
        })
        .to_string(),
    )
}

pub(crate) fn stored_lsp_success_result_json(
    slot: LspResultSlot,
    result: serde_json::Value,
) -> Option<String> {
    if slot == LspResultSlot::ExecuteCommand {
        return Some(serde_json::json!({ "result": result }).to_string());
    }
    if slot == LspResultSlot::CodeLens {
        return Some(result.to_string());
    }

    if result.is_null() {
        None
    } else {
        Some(result.to_string())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LspClientRequest {
    Result { view: ViewId, slot: LspResultSlot },
    OnTypeFormatting { view: ViewId, version: u64 },
}
