//! JSON-RPC/LSP stdio framing helpers.
//!
//! LSP messages are JSON values framed by HTTP-like headers:
//!
//! ```text
//! Content-Length: <n>\r\n
//! \r\n
//! <n bytes of UTF-8 JSON>
//! ```

use serde_json::Value;
use std::io::{self, BufRead, Write};

/// Write a single LSP JSON-RPC message to `writer`.
pub fn write_lsp_message<W: Write>(writer: &mut W, value: &Value) -> io::Result<()> {
    let body =
        serde_json::to_vec(value).map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;

    write!(writer, "Content-Length: {}\r\n\r\n", body.len())?;
    writer.write_all(&body)?;
    writer.flush()?;
    Ok(())
}

/// Read a single LSP JSON-RPC message from `reader`.
///
/// Returns:
/// - `Ok(Some(value))` when a message is successfully read.
/// - `Ok(None)` on clean EOF (no more messages).
pub fn read_lsp_message<R: BufRead>(reader: &mut R) -> io::Result<Option<Value>> {
    let mut content_length: Option<usize> = None;
    let mut line = String::new();

    loop {
        line.clear();
        let read = reader.read_line(&mut line)?;
        if read == 0 {
            return Ok(None);
        }

        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }

        // LSP uses `Content-Length` (case-insensitive in practice).
        if let Some((name, rest)) = trimmed.split_once(':')
            && name.trim().eq_ignore_ascii_case("Content-Length")
        {
            content_length = rest.trim().parse::<usize>().ok();
        }
    }

    let len = content_length.ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "Missing Content-Length header")
    })?;

    let mut body = vec![0u8; len];
    reader.read_exact(&mut body)?;

    let value: Value = serde_json::from_slice(&body)
        .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;

    Ok(Some(value))
}
