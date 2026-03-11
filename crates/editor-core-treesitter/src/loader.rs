use crate::{
    TreeSitterConfig, TreeSitterIndenterConfig, TreeSitterLanguage, TreeSitterProcessorConfig,
};

/// Errors produced when loading Tree-sitter WASM and query files from disk.
#[derive(Debug)]
pub enum TreeSitterLoadError {
    /// I/O error while reading a required file.
    Io(String),
    /// A required file was not valid UTF-8.
    InvalidUtf8(String),
}

impl std::fmt::Display for TreeSitterLoadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(msg) => write!(f, "tree-sitter load io error: {msg}"),
            Self::InvalidUtf8(msg) => write!(f, "tree-sitter load utf-8 error: {msg}"),
        }
    }
}

impl std::error::Error for TreeSitterLoadError {}

/// Load a [`TreeSitterProcessorConfig`] from a file-based [`TreeSitterConfig`].
///
/// This reads:
/// - the WASM grammar bytes
/// - `highlights.scm`
/// - optionally `folds.scm`
pub fn load_processor_config_from_config(
    language_id: &str,
    config: &TreeSitterConfig,
) -> Result<TreeSitterProcessorConfig, TreeSitterLoadError> {
    let wasm_bytes = std::fs::read(&config.wasm_path)
        .map_err(|e| TreeSitterLoadError::Io(format!("{}: {e}", config.wasm_path.display())))?;

    let highlights_query = std::fs::read_to_string(&config.highlights_path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::InvalidData {
            TreeSitterLoadError::InvalidUtf8(format!("{}: {e}", config.highlights_path.display()))
        } else {
            TreeSitterLoadError::Io(format!("{}: {e}", config.highlights_path.display()))
        }
    })?;

    let mut out = TreeSitterProcessorConfig::new(
        TreeSitterLanguage::wasm(language_id.to_string(), wasm_bytes),
        highlights_query,
    );

    if let Some(folds_path) = &config.folds_path {
        let folds_query = std::fs::read_to_string(folds_path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::InvalidData {
                TreeSitterLoadError::InvalidUtf8(format!("{}: {e}", folds_path.display()))
            } else {
                TreeSitterLoadError::Io(format!("{}: {e}", folds_path.display()))
            }
        })?;
        if !folds_query.trim().is_empty() {
            out = out.with_folds_query(folds_query);
        }
    }

    Ok(out)
}

/// Load a [`TreeSitterIndenterConfig`] from a file-based [`TreeSitterConfig`], if available.
///
/// This reads:
/// - the WASM grammar bytes
/// - `indents.scm` (optional; returns `Ok(None)` when missing)
pub fn load_indenter_config_from_config(
    language_id: &str,
    config: &TreeSitterConfig,
) -> Result<Option<TreeSitterIndenterConfig>, TreeSitterLoadError> {
    let Some(indents_path) = &config.indents_path else {
        return Ok(None);
    };

    let wasm_bytes = std::fs::read(&config.wasm_path)
        .map_err(|e| TreeSitterLoadError::Io(format!("{}: {e}", config.wasm_path.display())))?;

    let indents_query = std::fs::read_to_string(indents_path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::InvalidData {
            TreeSitterLoadError::InvalidUtf8(format!("{}: {e}", indents_path.display()))
        } else {
            TreeSitterLoadError::Io(format!("{}: {e}", indents_path.display()))
        }
    })?;

    Ok(Some(TreeSitterIndenterConfig::new(
        TreeSitterLanguage::wasm(language_id.to_string(), wasm_bytes),
        indents_query,
    )))
}
