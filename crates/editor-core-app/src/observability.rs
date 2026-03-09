use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LogEntry {
    /// Milliseconds since UNIX epoch.
    pub ts_ms: u64,
    pub level: LogLevel,
    pub message: String,
}

impl LogEntry {
    pub fn new(level: LogLevel, message: impl Into<String>) -> Self {
        let ts_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        Self {
            ts_ms,
            level,
            message: message.into(),
        }
    }
}

/// A small in-memory log buffer that frontends can surface in an “internal logs” panel.
#[derive(Debug, Clone)]
pub struct AppLog {
    capacity: usize,
    entries: VecDeque<LogEntry>,
}

impl Default for AppLog {
    fn default() -> Self {
        Self::new(1024)
    }
}

impl AppLog {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity: capacity.max(1),
            entries: VecDeque::new(),
        }
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn entries(&self) -> impl Iterator<Item = &LogEntry> {
        self.entries.iter()
    }

    pub fn push(&mut self, level: LogLevel, message: impl Into<String>) {
        if self.entries.len() >= self.capacity {
            let _ = self.entries.pop_front();
        }
        self.entries.push_back(LogEntry::new(level, message));
    }

    /// Write the current log buffer as JSON lines (one entry per line).
    pub fn write_json_lines(&self, path: &Path) -> Result<(), std::io::Error> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut out = String::new();
        for entry in &self.entries {
            out.push_str(&serde_json::to_string(entry).unwrap_or_else(|_| "{}".to_string()));
            out.push('\n');
        }
        std::fs::write(path, out)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use tempfile::tempdir;

    #[test]
    fn log_buffer_is_bounded() {
        let mut log = AppLog::new(2);
        log.push(LogLevel::Info, "a");
        log.push(LogLevel::Info, "b");
        log.push(LogLevel::Info, "c");
        assert_eq!(log.len(), 2);
        let msgs: Vec<String> = log.entries().map(|e| e.message.clone()).collect();
        assert_eq!(msgs, vec!["b".to_string(), "c".to_string()]);
    }

    #[test]
    fn log_buffer_writes_json_lines() {
        let temp = tempdir().unwrap();
        let path = temp.path().join("logs.jsonl");
        let mut log = AppLog::new(8);
        log.push(LogLevel::Warn, "hello");
        log.write_json_lines(&path).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("hello"));
    }
}

