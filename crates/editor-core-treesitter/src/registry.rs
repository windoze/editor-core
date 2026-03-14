use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Mapping from file extension (without `.`) to Tree-sitter `language_id`.
///
/// Example: `"rs" -> "rust"`.
pub type TreeSitterExtensionMap = BTreeMap<String, String>;

/// Mapping from Tree-sitter `language_id` (e.g. `"rust"`) to its on-disk configuration.
pub type TreeSitterConfigMap = BTreeMap<String, TreeSitterConfig>;

/// File-based Tree-sitter configuration for one language.
///
/// This is intentionally UI-agnostic: it describes *where* the editor can load a Tree-sitter WASM
/// grammar and related query files.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeSitterConfig {
    /// WASM grammar module (`language.wasm`).
    pub wasm_path: PathBuf,
    /// Syntax highlighting query (`highlights.scm`).
    pub highlights_path: PathBuf,
    /// Optional folding query (`folds.scm`).
    pub folds_path: Option<PathBuf>,
    /// Optional indentation query (`indents.scm`).
    pub indents_path: Option<PathBuf>,
    /// Optional tags query (`tags.scm`).
    pub tags_path: Option<PathBuf>,
    /// Optional injections query (`injections.scm`).
    pub injections_path: Option<PathBuf>,
}

impl TreeSitterConfig {
    /// Create a config from explicit paths.
    pub fn new(wasm_path: PathBuf, highlights_path: PathBuf) -> Self {
        Self {
            wasm_path,
            highlights_path,
            folds_path: None,
            indents_path: None,
            tags_path: None,
            injections_path: None,
        }
    }

    /// Load a config by scanning a `<language_id>/` directory for conventional filenames.
    ///
    /// Required:
    /// - `language.wasm`
    /// - `highlights.scm`
    ///
    /// Optional:
    /// - `folds.scm`
    /// - `indents.scm`
    /// - `tags.scm`
    /// - `injections.scm`
    pub fn from_language_dir(dir: &Path) -> Option<Self> {
        let wasm_path = dir.join("language.wasm");
        let highlights_path = dir.join("highlights.scm");
        if !wasm_path.is_file() || !highlights_path.is_file() {
            return None;
        }

        let folds_path = {
            let p = dir.join("folds.scm");
            p.is_file().then_some(p)
        };
        let indents_path = {
            let p = dir.join("indents.scm");
            p.is_file().then_some(p)
        };
        let tags_path = {
            let p = dir.join("tags.scm");
            p.is_file().then_some(p)
        };
        let injections_path = {
            let p = dir.join("injections.scm");
            p.is_file().then_some(p)
        };

        Some(Self {
            wasm_path,
            highlights_path,
            folds_path,
            indents_path,
            tags_path,
            injections_path,
        })
    }
}

/// Combined Tree-sitter registry used by the UI layer and FFI boundary.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct TreeSitterRegistry {
    /// Mapping from extension → language id.
    pub extension_map: TreeSitterExtensionMap,
    /// Mapping from language id → file-based config.
    pub languages: TreeSitterConfigMap,
}

/// Errors produced when parsing/validating a Tree-sitter registry.
#[derive(Debug)]
pub enum TreeSitterRegistryError {
    /// JSON parsing or schema validation failed.
    Json(String),
    /// Unsupported registry schema version.
    UnsupportedSchemaVersion(u32),
    /// A required value was missing or invalid.
    InvalidValue(String),
    /// I/O error while scanning a directory.
    Io(String),
}

impl std::fmt::Display for TreeSitterRegistryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Json(msg) => write!(f, "tree-sitter registry json error: {msg}"),
            Self::UnsupportedSchemaVersion(v) => {
                write!(f, "tree-sitter registry unsupported schema_version: {v}")
            }
            Self::InvalidValue(msg) => write!(f, "tree-sitter registry invalid value: {msg}"),
            Self::Io(msg) => write!(f, "tree-sitter registry io error: {msg}"),
        }
    }
}

impl std::error::Error for TreeSitterRegistryError {}

#[derive(Debug, Deserialize)]
struct RegistryJson {
    schema_version: u32,
    #[serde(default)]
    root_dir: Option<String>,
    #[serde(default)]
    extension_map: TreeSitterExtensionMap,
    #[serde(default)]
    languages: BTreeMap<String, LanguageJson>,
}

#[derive(Debug, Deserialize)]
struct LanguageJson {
    wasm: String,
    highlights: String,
    #[serde(default)]
    folds: Option<String>,
    #[serde(default)]
    indents: Option<String>,
    #[serde(default)]
    tags: Option<String>,
    #[serde(default)]
    injections: Option<String>,
}

impl TreeSitterRegistry {
    /// Parse a schema-versioned Tree-sitter registry JSON string.
    ///
    /// The registry supports:
    /// - absolute paths
    /// - or relative paths resolved against `root_dir`
    pub fn from_json_str(json: &str) -> Result<Self, TreeSitterRegistryError> {
        Self::from_json_str_with_default_root_dir(json, None)
    }

    /// Parse a schema-versioned Tree-sitter registry JSON string, but allow the caller to provide
    /// a default `root_dir` to resolve relative paths when the JSON does not include one.
    ///
    /// This matches common on-disk conventions where a `registry.json` sits next to the
    /// `treesitter/` directory and uses relative paths like `rust/language.wasm`.
    pub fn from_json_str_with_default_root_dir(
        json: &str,
        default_root_dir: Option<&Path>,
    ) -> Result<Self, TreeSitterRegistryError> {
        let parsed: RegistryJson =
            serde_json::from_str(json).map_err(|e| TreeSitterRegistryError::Json(e.to_string()))?;
        if parsed.schema_version != 1 {
            return Err(TreeSitterRegistryError::UnsupportedSchemaVersion(
                parsed.schema_version,
            ));
        }

        let json_root = parsed.root_dir.as_deref().map(PathBuf::from);
        let root_dir = json_root.as_deref().or(default_root_dir);

        let mut languages = TreeSitterConfigMap::new();
        for (language_id, lang) in parsed.languages {
            if language_id.trim().is_empty() {
                return Err(TreeSitterRegistryError::InvalidValue(
                    "language_id must not be empty".to_string(),
                ));
            }

            let wasm_path = resolve_path(root_dir, &lang.wasm)
                .map_err(TreeSitterRegistryError::InvalidValue)?;
            let highlights_path = resolve_path(root_dir, &lang.highlights)
                .map_err(TreeSitterRegistryError::InvalidValue)?;
            let folds_path = match lang.folds.as_deref() {
                Some(p) if !p.trim().is_empty() => {
                    Some(resolve_path(root_dir, p).map_err(TreeSitterRegistryError::InvalidValue)?)
                }
                _ => None,
            };
            let indents_path = match lang.indents.as_deref() {
                Some(p) if !p.trim().is_empty() => {
                    Some(resolve_path(root_dir, p).map_err(TreeSitterRegistryError::InvalidValue)?)
                }
                _ => None,
            };
            let tags_path = match lang.tags.as_deref() {
                Some(p) if !p.trim().is_empty() => {
                    Some(resolve_path(root_dir, p).map_err(TreeSitterRegistryError::InvalidValue)?)
                }
                _ => None,
            };
            let injections_path = match lang.injections.as_deref() {
                Some(p) if !p.trim().is_empty() => {
                    Some(resolve_path(root_dir, p).map_err(TreeSitterRegistryError::InvalidValue)?)
                }
                _ => None,
            };

            languages.insert(
                language_id,
                TreeSitterConfig {
                    wasm_path,
                    highlights_path,
                    folds_path,
                    indents_path,
                    tags_path,
                    injections_path,
                },
            );
        }

        Ok(Self {
            extension_map: parsed.extension_map,
            languages,
        })
    }

    /// Return the configured language id for a file path, based on its extension.
    pub fn language_id_for_path<'a>(&'a self, path: &Path) -> Option<&'a str> {
        let ext = normalized_extension_for_path(path)?;
        self.extension_map.get(&ext).map(|s| s.as_str())
    }

    /// Scan a `treesitter/` root directory and return a `language_id -> config` map.
    ///
    /// This is useful for hosts that follow the conventional on-disk layout:
    ///
    /// ```text
    /// treesitter/
    ///   rust/
    ///     language.wasm
    ///     highlights.scm
    /// ```
    pub fn scan_language_configs(
        root_dir: &Path,
    ) -> Result<TreeSitterConfigMap, TreeSitterRegistryError> {
        let mut out = TreeSitterConfigMap::new();
        let entries =
            std::fs::read_dir(root_dir).map_err(|e| TreeSitterRegistryError::Io(e.to_string()))?;
        for entry in entries {
            let entry = entry.map_err(|e| TreeSitterRegistryError::Io(e.to_string()))?;
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            let Some(language_id) = entry.file_name().to_str().map(|s| s.to_string()) else {
                continue;
            };
            if language_id.starts_with('.') {
                continue;
            }

            let Some(cfg) = TreeSitterConfig::from_language_dir(&path) else {
                continue;
            };
            out.insert(language_id, cfg);
        }
        Ok(out)
    }
}

fn resolve_path(root_dir: Option<&Path>, raw: &str) -> Result<PathBuf, String> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Err("path must not be empty".to_string());
    }
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        return Ok(path);
    }
    let Some(root_dir) = root_dir else {
        return Err(format!("relative path without root_dir: {raw}"));
    };
    Ok(root_dir.join(path))
}

fn normalized_extension_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    let ext = ext.trim().trim_start_matches('.');
    if ext.is_empty() {
        return None;
    }
    Some(ext.to_ascii_lowercase())
}
