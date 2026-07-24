//! LSP/URI helpers.
//!
//! This module keeps path/URI conversion self-contained for frontends that talk to LSP servers.

use std::fs;
use std::path::{Path, PathBuf};

/// Convert a local filesystem path to a `file://` URI.
///
/// This is a small helper used by LSP clients when building `textDocument.uri`,
/// `rootUri`, and `workspaceFolders`.
pub fn path_to_file_uri(path: &Path) -> String {
    let abs = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut path_str = abs.to_string_lossy().to_string();

    // Normalize to forward slashes for URIs.
    if cfg!(windows) {
        path_str = path_str.replace('\\', "/");
        if !path_str.starts_with('/') {
            path_str.insert(0, '/');
        }
    }

    format!("file://{}", percent_encode_path(&path_str))
}

/// Percent-encode a path segment for URIs.
///
/// Keeps URI-safe bytes and percent-encodes the rest. This is intentionally minimal and
/// targets `file://` URIs produced by `path_to_file_uri`.
pub fn percent_encode_path(path: &str) -> String {
    let mut out = String::with_capacity(path.len());
    for &b in path.as_bytes() {
        match b {
            // `:` is left unencoded so Windows drive letters round-trip as the standard
            // `file:///C:/...` (many LSP servers reject the encoded `C%3A` form). Colon is a valid
            // path character per RFC 3986/8089.
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' | b':' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

/// Percent-decode a `file://` URI path component.
pub fn percent_decode_path(path: &str) -> String {
    fn hex_val(b: u8) -> Option<u8> {
        match b {
            b'0'..=b'9' => Some(b - b'0'),
            b'a'..=b'f' => Some(b - b'a' + 10),
            b'A'..=b'F' => Some(b - b'A' + 10),
            _ => None,
        }
    }

    let bytes = path.as_bytes();
    let mut out = Vec::<u8>::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let (Some(hi), Some(lo)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2]))
        {
            out.push((hi << 4) | lo);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }

    String::from_utf8_lossy(&out).to_string()
}

/// Convert a `file://` URI back into a local filesystem path.
///
/// This is intentionally minimal and is primarily intended to round-trip URIs created by
/// [`path_to_file_uri`].
pub fn file_uri_to_path(uri: &str) -> Option<PathBuf> {
    let uri = uri.strip_prefix("file://")?;
    // `file://localhost/tmp/x` has authority "localhost"; strip only the authority, keeping the
    // leading `/` of the absolute path (stripping "localhost/" would turn it into a relative path).
    let uri = uri.strip_prefix("localhost").unwrap_or(uri);

    let decoded = percent_decode_path(uri);
    let mut path_str = decoded;

    // `file:///C:/...` -> `C:/...`
    if cfg!(windows) {
        if path_str.starts_with('/') && path_str.get(2..3) == Some(":") {
            path_str.remove(0);
        }
        path_str = path_str.replace('/', "\\");
    }

    Some(PathBuf::from(path_str))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_percent_roundtrip() {
        let input = "/tmp/hello world.txt";
        let encoded = percent_encode_path(input);
        assert_eq!(percent_decode_path(&encoded), input);
    }

    #[test]
    fn test_file_uri_roundtrip() {
        let path = Path::new("/tmp/hello world.txt");
        let uri = path_to_file_uri(path);
        let back = file_uri_to_path(&uri).unwrap();
        assert!(back.to_string_lossy().contains("hello world.txt"));
    }

    #[test]
    fn test_file_uri_with_localhost_authority_keeps_root_slash() {
        // Regression (P3-23): `file://localhost/tmp/x` must decode to the absolute `/tmp/x`, not
        // the relative `tmp/x`.
        let path = file_uri_to_path("file://localhost/tmp/x").unwrap();
        assert_eq!(path, PathBuf::from("/tmp/x"));
    }

    #[test]
    fn test_drive_letter_colon_is_not_percent_encoded() {
        // Regression (P3-24): a Windows-style absolute path must produce `file:///C:/...`, not the
        // `C%3A` form many servers reject.
        let uri = format!("file://{}", percent_encode_path("/C:/Users/x.rs"));
        assert_eq!(uri, "file:///C:/Users/x.rs");
        // And it must still decode back.
        assert_eq!(percent_decode_path("/C:/Users/x.rs"), "/C:/Users/x.rs");
    }
}
