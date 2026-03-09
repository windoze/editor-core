use editor_core::workspace::{BufferId, ViewId, Workspace};
use editor_core::{Command, ViewCommand, WrapIndent, WrapMode};
use editor_core_lang::{IndentStyle, IndentationConfig, LanguageRegistry};
use serde::Deserialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SettingsError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("toml error: {0}")]
    Toml(#[from] toml::de::Error),
    #[error("workspace error: {0}")]
    Workspace(String),
    #[error("invalid setting: {0}")]
    InvalidSetting(String),
}

impl From<editor_core::workspace::WorkspaceError> for SettingsError {
    fn from(err: editor_core::workspace::WorkspaceError) -> Self {
        Self::Workspace(format!("{err:?}"))
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct Settings {
    pub editor: Option<EditorSettings>,
    pub languages: Option<HashMap<String, EditorSettings>>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct EditorSettings {
    pub tab_width: Option<usize>,
    pub wrap_mode: Option<String>,
    pub wrap_indent: Option<WrapIndentSetting>,
    pub indent_style: Option<String>,
    pub indent_width: Option<u8>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum WrapIndentSetting {
    String(String),
    FixedCells { fixed_cells: usize },
}

fn parse_wrap_mode(v: &str) -> Option<WrapMode> {
    match v.trim().to_ascii_lowercase().as_str() {
        "none" => Some(WrapMode::None),
        "char" => Some(WrapMode::Char),
        "word" => Some(WrapMode::Word),
        _ => None,
    }
}

fn parse_wrap_indent(v: &WrapIndentSetting) -> Option<WrapIndent> {
    match v {
        WrapIndentSetting::String(s) => match s.trim().to_ascii_lowercase().as_str() {
            "none" => Some(WrapIndent::None),
            "same_as_line_indent" => Some(WrapIndent::SameAsLineIndent),
            _ => None,
        },
        WrapIndentSetting::FixedCells { fixed_cells } => Some(WrapIndent::FixedCells(*fixed_cells)),
    }
}

fn parse_indent_style(style: &str, width: Option<u8>) -> Option<IndentStyle> {
    match style.trim().to_ascii_lowercase().as_str() {
        "tabs" => Some(IndentStyle::Tabs),
        "spaces" => Some(IndentStyle::Spaces(width.unwrap_or(4))),
        _ => None,
    }
}

fn buffer_path(ws: &Workspace, buffer_id: BufferId) -> Option<PathBuf> {
    let uri = ws.buffer_metadata(buffer_id)?.uri.as_deref()?;
    editor_core_lsp::file_uri_to_path(uri)
}

pub fn apply_settings_to_view(
    ws: &mut Workspace,
    view_id: ViewId,
    settings: &Settings,
    languages: &LanguageRegistry,
) -> Result<(), SettingsError> {
    let buffer_id = ws.buffer_id_for_view(view_id)?;
    let path = buffer_path(ws, buffer_id);
    let language_id = path
        .as_deref()
        .and_then(|p| languages.language_for_path(p))
        .map(|l| l.id.as_str().to_string());

    // Apply base editor settings first, then per-language overrides.
    if let Some(base) = settings.editor.as_ref() {
        apply_editor_settings(ws, view_id, base)?;
    }
    if let (Some(lang_id), Some(map)) = (language_id, settings.languages.as_ref())
        && let Some(over) = map.get(&lang_id)
    {
        apply_editor_settings(ws, view_id, over)?;
    }

    Ok(())
}

fn apply_editor_settings(
    ws: &mut Workspace,
    view_id: ViewId,
    s: &EditorSettings,
) -> Result<(), SettingsError> {
    if let Some(width) = s.tab_width {
        if width == 0 {
            return Err(SettingsError::InvalidSetting(
                "tab_width must be > 0".to_string(),
            ));
        }
        ws.execute(view_id, Command::View(ViewCommand::SetTabWidth { width }))?;
    }

    if let Some(mode) = s.wrap_mode.as_deref() {
        let mode = parse_wrap_mode(mode)
            .ok_or_else(|| SettingsError::InvalidSetting(format!("invalid wrap_mode: {mode}")))?;
        ws.execute(view_id, Command::View(ViewCommand::SetWrapMode { mode }))?;
    }

    if let Some(indent) = s.wrap_indent.as_ref() {
        let indent = parse_wrap_indent(indent)
            .ok_or_else(|| SettingsError::InvalidSetting("invalid wrap_indent".to_string()))?;
        ws.execute(
            view_id,
            Command::View(ViewCommand::SetWrapIndent { indent }),
        )?;
    }

    if let Some(style) = s.indent_style.as_deref() {
        let style = parse_indent_style(style, s.indent_width).ok_or_else(|| {
            SettingsError::InvalidSetting(format!("invalid indent_style: {style}"))
        })?;
        let cfg = IndentationConfig {
            style,
            ..Default::default()
        };
        ws.execute(
            view_id,
            Command::View(ViewCommand::SetIndentationConfig { config: cfg }),
        )?;
    }

    Ok(())
}

#[derive(Debug, Clone)]
pub struct SettingsStore {
    path: PathBuf,
    last_modified: Option<SystemTime>,
    settings: Settings,
}

impl SettingsStore {
    pub fn load(path: impl Into<PathBuf>) -> Result<Self, SettingsError> {
        let path = path.into();
        let text = std::fs::read_to_string(&path)?;
        let settings: Settings = toml::from_str(&text)?;
        let last_modified = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
        Ok(Self {
            path,
            last_modified,
            settings,
        })
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    pub fn reload_if_changed(&mut self) -> Result<bool, SettingsError> {
        let modified = std::fs::metadata(&self.path)
            .and_then(|m| m.modified())
            .ok();
        if modified.is_none() || modified == self.last_modified {
            return Ok(false);
        }

        let text = std::fs::read_to_string(&self.path)?;
        self.settings = toml::from_str(&text)?;
        self.last_modified = modified;
        Ok(true)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::Workspace;
    use pretty_assertions::assert_eq;

    #[test]
    fn parse_and_apply_editor_settings_to_view() {
        let toml = r#"
[editor]
tab_width = 8
wrap_mode = "word"
wrap_indent = "same_as_line_indent"
indent_style = "spaces"
indent_width = 2

[languages.rust]
tab_width = 4
"#;

        let settings: Settings = toml::from_str(toml).unwrap();

        let mut ws = Workspace::new();
        let opened = ws
            .open_buffer(Some("file:///tmp/proj/src/main.rs".to_string()), "x\n", 80)
            .unwrap();

        let reg = LanguageRegistry::default();
        apply_settings_to_view(&mut ws, opened.view_id, &settings, &reg).unwrap();

        assert_eq!(ws.tab_width_for_view(opened.view_id).unwrap(), 4);
        assert_eq!(
            ws.wrap_mode_for_view(opened.view_id).unwrap(),
            WrapMode::Word
        );
        assert_eq!(
            ws.wrap_indent_for_view(opened.view_id).unwrap(),
            WrapIndent::SameAsLineIndent
        );

        let indent = ws.indentation_config_for_view(opened.view_id).unwrap();
        assert_eq!(indent.style, IndentStyle::Spaces(2));
    }
}
