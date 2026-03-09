use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileIoOptions {
    /// If true, attempt an atomic save by writing to a temp file in the same directory and renaming.
    pub atomic: bool,
    /// If true, attempt to preserve existing file permissions where possible.
    pub preserve_permissions: bool,
}

impl Default for FileIoOptions {
    fn default() -> Self {
        Self {
            atomic: true,
            preserve_permissions: true,
        }
    }
}

#[derive(Debug, Error)]
pub enum FileIoError {
    #[error("path has no parent directory: {0}")]
    NoParent(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("file is not valid UTF-8: {0}")]
    InvalidUtf8(String),
}

/// Read a file as UTF-8 text.
///
/// Notes:
/// - If a UTF-8 BOM is present, it is stripped.
pub fn read_utf8_file(path: &Path) -> Result<String, FileIoError> {
    let mut f = fs::File::open(path)?;
    let mut bytes = Vec::new();
    f.read_to_end(&mut bytes)?;

    // Strip UTF-8 BOM.
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        bytes.drain(0..3);
    }

    String::from_utf8(bytes).map_err(|_| FileIoError::InvalidUtf8(path.to_string_lossy().to_string()))
}

fn unique_temp_path_for(target: &Path) -> Result<PathBuf, FileIoError> {
    let parent = target
        .parent()
        .ok_or_else(|| FileIoError::NoParent(target.to_string_lossy().to_string()))?;

    let file_name = target
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "file".to_string());

    let pid = std::process::id();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    Ok(parent.join(format!(".{file_name}.{pid}.{nanos}.tmp")))
}

/// Write a UTF-8 text file (optionally via atomic save) and return `Ok(())` if successful.
pub fn write_utf8_file_atomic(
    path: &Path,
    contents: &str,
    options: FileIoOptions,
) -> Result<(), FileIoError> {
    if !options.atomic {
        let mut f = fs::File::create(path)?;
        f.write_all(contents.as_bytes())?;
        f.sync_all()?;
        return Ok(());
    }

    let tmp_path = unique_temp_path_for(path)?;

    let existing_permissions = if options.preserve_permissions {
        fs::metadata(path).ok().map(|m| m.permissions())
    } else {
        None
    };

    {
        let mut tmp = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp_path)?;
        tmp.write_all(contents.as_bytes())?;
        tmp.sync_all()?;
    }

    if let Some(perm) = existing_permissions {
        let _ = fs::set_permissions(&tmp_path, perm);
    }

    // Best-effort replace:
    // - Unix `rename` replaces atomically
    // - Windows `rename` fails if destination exists; fall back to remove+rename.
    if fs::rename(&tmp_path, path).is_ok() {
        return Ok(());
    }

    if path.exists() {
        let _ = fs::remove_file(path);
    }
    fs::rename(&tmp_path, path)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use tempfile::tempdir;

    #[test]
    fn read_utf8_strips_bom() {
        let temp = tempdir().unwrap();
        let path = temp.path().join("bom.txt");
        fs::write(&path, [0xEFu8, 0xBB, 0xBF].into_iter().chain(b"abc".iter().copied()).collect::<Vec<_>>()).unwrap();
        assert_eq!(read_utf8_file(&path).unwrap(), "abc");
    }

    #[test]
    fn write_atomic_roundtrips_contents() {
        let temp = tempdir().unwrap();
        let path = temp.path().join("out.txt");
        write_utf8_file_atomic(&path, "hello\n", FileIoOptions::default()).unwrap();
        assert_eq!(read_utf8_file(&path).unwrap(), "hello\n");
    }

    #[cfg(unix)]
    #[test]
    fn write_atomic_preserves_permissions_on_unix_when_requested() {
        use std::os::unix::fs::PermissionsExt;

        let temp = tempdir().unwrap();
        let path = temp.path().join("perm.txt");
        fs::write(&path, "old").unwrap();

        let original_mode = 0o640;
        fs::set_permissions(&path, fs::Permissions::from_mode(original_mode)).unwrap();

        write_utf8_file_atomic(
            &path,
            "new",
            FileIoOptions {
                atomic: true,
                preserve_permissions: true,
            },
        )
        .unwrap();

        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, original_mode);
    }
}

