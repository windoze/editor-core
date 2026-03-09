use serde::{Deserialize, Serialize};
use std::ffi::OsStr;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkMode {
    Static,
    Dynamic,
    Both,
}

impl LinkMode {
    pub fn parse(s: &str) -> Result<Self, DistError> {
        match s.trim().to_ascii_lowercase().as_str() {
            "static" => Ok(Self::Static),
            "dynamic" => Ok(Self::Dynamic),
            "both" => Ok(Self::Both),
            other => Err(DistError::InvalidArgument(format!(
                "invalid link mode: {other} (expected static|dynamic|both)"
            ))),
        }
    }
}

#[derive(Debug, Clone)]
pub struct FfiDistOptions {
    pub repo_root: PathBuf,
    pub out_dir: PathBuf,
    pub profile: String,
    pub target_triple: String,
    pub mode: LinkMode,
    pub include_core: bool,
    pub include_ui: bool,
    pub overwrite: bool,
}

impl FfiDistOptions {
    pub fn for_repo_root(repo_root: impl Into<PathBuf>) -> Self {
        Self {
            repo_root: repo_root.into(),
            out_dir: PathBuf::from("dist/ffi"),
            profile: "release".to_string(),
            // Default to "host" because Cargo does not expose an easy, stable runtime env var for
            // the full target triple of the *already built* artifacts. Callers can pass an
            // explicit `--target <triple>` when packaging cross-target builds.
            target_triple: "host".to_string(),
            mode: LinkMode::Static,
            include_core: true,
            include_ui: true,
            overwrite: true,
        }
    }
}

#[derive(Debug)]
pub enum DistError {
    InvalidArgument(String),
    MissingArtifact(String),
    Io(std::io::Error),
    Json(serde_json::Error),
}

impl fmt::Display for DistError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DistError::InvalidArgument(msg) => write!(f, "invalid argument: {msg}"),
            DistError::MissingArtifact(msg) => write!(f, "missing artifact: {msg}"),
            DistError::Io(err) => write!(f, "io error: {err}"),
            DistError::Json(err) => write!(f, "json error: {err}"),
        }
    }
}

impl std::error::Error for DistError {}

impl From<std::io::Error> for DistError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<serde_json::Error> for DistError {
    fn from(value: serde_json::Error) -> Self {
        Self::Json(value)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FfiDistManifest {
    pub schema_version: u32,
    pub editor_core_version: String,
    pub target_triple: String,
    pub profile: String,
    pub entries: Vec<FfiDistEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FfiDistEntry {
    pub kind: String,
    pub headers: Vec<String>,
    pub libraries: Vec<String>,
    pub notes: Vec<String>,
}

fn require_dir(path: &Path) -> Result<(), DistError> {
    if path.is_dir() {
        return Ok(());
    }
    Err(DistError::MissingArtifact(format!(
        "directory not found: {}",
        path.display()
    )))
}

fn copy_file(src: &Path, dst: &Path, overwrite: bool) -> Result<(), DistError> {
    if !overwrite && dst.exists() {
        return Err(DistError::InvalidArgument(format!(
            "destination already exists: {}",
            dst.display()
        )));
    }
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(src, dst)?;
    Ok(())
}

fn find_first_existing(dir: &Path, candidates: &[&str]) -> Option<PathBuf> {
    candidates
        .iter()
        .map(|name| dir.join(name))
        .find(|p| p.is_file())
}

fn list_existing(dir: &Path, candidates: &[&str]) -> Vec<PathBuf> {
    candidates
        .iter()
        .map(|name| dir.join(name))
        .filter(|p| p.is_file())
        .collect()
}

fn resolve_profile_dir(
    repo_root: &Path,
    target_triple: &str,
    profile: &str,
) -> Result<PathBuf, DistError> {
    let target_dir = repo_root.join("target");
    require_dir(&target_dir)?;

    let triple_dir = target_dir.join(target_triple).join(profile);
    let host_dir = target_dir.join(profile);

    if triple_dir.is_dir() {
        Ok(triple_dir)
    } else if host_dir.is_dir() {
        Ok(host_dir)
    } else {
        Err(DistError::MissingArtifact(format!(
            "no cargo profile dir found (tried {} and {})",
            triple_dir.display(),
            host_dir.display()
        )))
    }
}

fn headers_for_kind(repo_root: &Path, kind: &str) -> Result<Vec<PathBuf>, DistError> {
    let headers = match kind {
        "core" => vec![repo_root.join("crates/editor-core-ffi/include/editor_core_ffi.h")],
        "ui" => vec![repo_root.join("crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h")],
        other => {
            return Err(DistError::InvalidArgument(format!("unknown kind: {other}")));
        }
    };
    for h in &headers {
        if !h.is_file() {
            return Err(DistError::MissingArtifact(format!(
                "header not found: {}",
                h.display()
            )));
        }
    }
    Ok(headers)
}

fn libs_for_kind(
    profile_dir: &Path,
    kind: &str,
    mode: LinkMode,
) -> Result<Vec<PathBuf>, DistError> {
    let (static_candidates, dynamic_candidates, extra_dynamic_import_candidates) = match kind {
        "core" => (
            ["libeditor_core_ffi.a", "editor_core_ffi.lib"],
            [
                "libeditor_core_ffi.dylib",
                "libeditor_core_ffi.so",
                "editor_core_ffi.dll",
            ],
            ["editor_core_ffi.dll.lib"],
        ),
        "ui" => (
            ["libeditor_core_ui_ffi.a", "editor_core_ui_ffi.lib"],
            [
                "libeditor_core_ui_ffi.dylib",
                "libeditor_core_ui_ffi.so",
                "editor_core_ui_ffi.dll",
            ],
            ["editor_core_ui_ffi.dll.lib"],
        ),
        other => {
            return Err(DistError::InvalidArgument(format!("unknown kind: {other}")));
        }
    };

    let mut libs = Vec::new();
    match mode {
        LinkMode::Static => {
            let Some(path) = find_first_existing(profile_dir, &static_candidates) else {
                return Err(DistError::MissingArtifact(format!(
                    "missing static library for {kind} in {} (expected one of: {})",
                    profile_dir.display(),
                    static_candidates.join(", ")
                )));
            };
            libs.push(path);
        }
        LinkMode::Dynamic => {
            let Some(path) = find_first_existing(profile_dir, &dynamic_candidates) else {
                return Err(DistError::MissingArtifact(format!(
                    "missing dynamic library for {kind} in {} (expected one of: {})",
                    profile_dir.display(),
                    dynamic_candidates.join(", ")
                )));
            };
            libs.push(path);
            // Optional: MSVC import library for the dll (if present).
            libs.extend(list_existing(profile_dir, &extra_dynamic_import_candidates));
        }
        LinkMode::Both => {
            libs.extend(libs_for_kind(profile_dir, kind, LinkMode::Static)?);
            libs.extend(libs_for_kind(profile_dir, kind, LinkMode::Dynamic)?);
        }
    }
    Ok(libs)
}

fn notes_for_kind(kind: &str) -> Vec<String> {
    match kind {
        "core" => Vec::new(),
        "ui" => vec![
            "macOS: link libc++ and required frameworks (CoreGraphics/CoreText/CoreFoundation/Metal/QuartzCore) when using the Skia-backed UI FFI staticlib.".to_string(),
            "Windows/Linux: UI FFI bundles a Skia build; ensure your host build links the C++ runtime and ships any required runtime deps (dll/so) when using dynamic linking.".to_string(),
        ],
        _ => Vec::new(),
    }
}

pub fn package_ffi_dist(options: &FfiDistOptions) -> Result<FfiDistManifest, DistError> {
    if !options.include_core && !options.include_ui {
        return Err(DistError::InvalidArgument(
            "nothing selected: set include_core and/or include_ui".to_string(),
        ));
    }

    let profile_dir =
        resolve_profile_dir(&options.repo_root, &options.target_triple, &options.profile)?;
    let out_root = options
        .out_dir
        .join(&options.target_triple)
        .join(&options.profile);

    let include_dir = out_root.join("include");
    let lib_dir = out_root.join("lib");
    fs::create_dir_all(&include_dir)?;
    fs::create_dir_all(&lib_dir)?;

    let mut entries = Vec::new();

    for kind in ["core", "ui"] {
        let enabled =
            (kind == "core" && options.include_core) || (kind == "ui" && options.include_ui);
        if !enabled {
            continue;
        }

        let headers = headers_for_kind(&options.repo_root, kind)?;
        let libs = libs_for_kind(&profile_dir, kind, options.mode)?;

        let mut header_rel = Vec::new();
        for h in headers {
            let file_name = h
                .file_name()
                .and_then(OsStr::to_str)
                .ok_or_else(|| DistError::InvalidArgument("header has no file name".to_string()))?;
            let dst = include_dir.join(file_name);
            copy_file(&h, &dst, options.overwrite)?;
            header_rel.push(format!("include/{file_name}"));
        }

        let mut lib_rel = Vec::new();
        for lib in libs {
            let file_name = lib.file_name().and_then(OsStr::to_str).ok_or_else(|| {
                DistError::InvalidArgument("library has no file name".to_string())
            })?;
            let dst = lib_dir.join(file_name);
            copy_file(&lib, &dst, options.overwrite)?;
            lib_rel.push(format!("lib/{file_name}"));
        }

        entries.push(FfiDistEntry {
            kind: kind.to_string(),
            headers: header_rel,
            libraries: lib_rel,
            notes: notes_for_kind(kind),
        });
    }

    let manifest = FfiDistManifest {
        schema_version: 1,
        editor_core_version: env!("CARGO_PKG_VERSION").to_string(),
        target_triple: options.target_triple.clone(),
        profile: options.profile.clone(),
        entries,
    };

    let manifest_path = out_root.join("manifest.json");
    fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?)?;

    Ok(manifest)
}
