use crate::{EditorUi, UiError};
use serde_json::Value;
use std::collections::HashMap;
use std::time::{Duration, Instant};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Platform {
    MacOS,
    Windows,
    Linux,
    Other,
}

impl Platform {
    pub fn current() -> Self {
        #[cfg(target_os = "macos")]
        {
            return Self::MacOS;
        }
        #[cfg(target_os = "windows")]
        {
            return Self::Windows;
        }
        #[cfg(target_os = "linux")]
        {
            return Self::Linux;
        }
        #[allow(unreachable_code)]
        Self::Other
    }

    pub fn is_macos(self) -> bool {
        matches!(self, Self::MacOS)
    }

    pub fn is_windows(self) -> bool {
        matches!(self, Self::Windows)
    }

    pub fn is_linux(self) -> bool {
        matches!(self, Self::Linux)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Key {
    Char(char),
    Enter,
    Tab,
    Backspace,
    Delete,
    Escape,
    Space,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    F(u8),
}

impl Key {
    fn normalized(self) -> Self {
        match self {
            Self::Char(' ') => Self::Space,
            Self::Char(c) if c.is_ascii_alphabetic() => Self::Char(c.to_ascii_lowercase()),
            other => other,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Modifiers(u8);

impl Modifiers {
    const SHIFT_BIT: u8 = 1 << 0;
    const CTRL_BIT: u8 = 1 << 1;
    const ALT_BIT: u8 = 1 << 2;
    const META_BIT: u8 = 1 << 3;

    pub const NONE: Self = Self(0);
    pub const SHIFT: Self = Self(Self::SHIFT_BIT);
    pub const CTRL: Self = Self(Self::CTRL_BIT);
    pub const ALT: Self = Self(Self::ALT_BIT);
    pub const META: Self = Self(Self::META_BIT);

    pub fn primary(platform: Platform) -> Self {
        if platform.is_macos() { Self::META } else { Self::CTRL }
    }

    pub fn contains(self, other: Self) -> bool {
        (self.0 & other.0) == other.0
    }

    pub fn insert(&mut self, other: Self) {
        self.0 |= other.0;
    }
}

impl std::ops::BitOr for Modifiers {
    type Output = Self;

    fn bitor(self, rhs: Self) -> Self::Output {
        Self(self.0 | rhs.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct KeyStroke {
    pub key: Key,
    pub modifiers: Modifiers,
}

impl KeyStroke {
    pub fn new(key: Key, modifiers: Modifiers) -> Self {
        Self {
            key: key.normalized(),
            modifiers,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeybindingWhen {
    Always,
    Expr(WhenExpr),
}

impl KeybindingWhen {
    pub fn parse(expr: &str) -> Result<Self, WhenParseError> {
        let trimmed = expr.trim();
        if trimmed.is_empty() {
            return Ok(Self::Always);
        }
        let parsed = WhenExpr::parse(trimmed)?;
        Ok(Self::Expr(parsed))
    }

    pub fn eval(&self, ctx: &KeybindingContext) -> bool {
        match self {
            Self::Always => true,
            Self::Expr(expr) => expr.eval(ctx),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WhenExpr {
    Const(bool),
    Key(String),
    Not(Box<WhenExpr>),
    And(Vec<WhenExpr>),
    Or(Vec<WhenExpr>),
}

impl WhenExpr {
    pub fn parse(input: &str) -> Result<Self, WhenParseError> {
        let mut parser = WhenParser::new(input);
        let expr = parser.parse_expr()?;
        parser.expect_end()?;
        Ok(expr)
    }

    pub fn eval(&self, ctx: &KeybindingContext) -> bool {
        match self {
            Self::Const(v) => *v,
            Self::Key(k) => ctx.get(k),
            Self::Not(inner) => !inner.eval(ctx),
            Self::And(parts) => parts.iter().all(|p| p.eval(ctx)),
            Self::Or(parts) => parts.iter().any(|p| p.eval(ctx)),
        }
    }
}

#[derive(Debug, Clone)]
pub struct KeybindingContext {
    platform: Platform,
    keys: HashMap<String, bool>,
}

impl KeybindingContext {
    pub fn new(platform: Platform) -> Self {
        Self {
            platform,
            keys: HashMap::new(),
        }
    }

    pub fn platform(&self) -> Platform {
        self.platform
    }

    pub fn set(&mut self, key: impl Into<String>, value: bool) {
        self.keys.insert(key.into(), value);
    }

    pub fn with(mut self, key: impl Into<String>, value: bool) -> Self {
        self.set(key, value);
        self
    }

    pub fn get(&self, key: &str) -> bool {
        match key {
            "isMac" | "isMacOS" => self.platform.is_macos(),
            "isWindows" => self.platform.is_windows(),
            "isLinux" => self.platform.is_linux(),
            _ => self.keys.get(key).copied().unwrap_or(false),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Keybinding {
    pub sequence: Vec<KeyStroke>,
    pub command: String,
    pub args: Option<Value>,
    pub when: KeybindingWhen,
}

#[derive(Debug, Clone, Default)]
pub struct Keymap {
    bindings: Vec<Keybinding>,
}

impl Keymap {
    pub fn new(bindings: Vec<Keybinding>) -> Self {
        Self { bindings }
    }

    pub fn bindings(&self) -> &[Keybinding] {
        &self.bindings
    }

    pub fn push(&mut self, binding: Keybinding) {
        self.bindings.push(binding);
    }

    pub fn from_json_str(json: &str, platform: Platform) -> Result<Self, KeymapParseError> {
        let value: Value =
            serde_json::from_str(json).map_err(|e| KeymapParseError::Json(e.to_string()))?;
        Self::from_json_value(value, platform)
    }

    pub fn from_json_value(value: Value, platform: Platform) -> Result<Self, KeymapParseError> {
        let arr = value
            .as_array()
            .ok_or_else(|| KeymapParseError::InvalidFormat("expected a JSON array".to_string()))?;

        let mut bindings: Vec<Keybinding> = Vec::with_capacity(arr.len());
        for (idx, item) in arr.iter().enumerate() {
            let obj = item.as_object().ok_or_else(|| {
                KeymapParseError::InvalidBinding {
                    index: idx,
                    message: "expected an object".to_string(),
                }
            })?;

            let command = obj
                .get("command")
                .and_then(|v| v.as_str())
                .ok_or_else(|| KeymapParseError::InvalidBinding {
                    index: idx,
                    message: "missing string field `command`".to_string(),
                })?
                .to_string();

            let keys_spec = key_sequence_for_platform(obj, platform).ok_or_else(|| {
                KeymapParseError::InvalidBinding {
                    index: idx,
                    message:
                        "missing string field `keys`/`key` (or platform override like `mac`)".into(),
                }
            })?;

            let sequence = parse_key_sequence(&keys_spec, platform).map_err(|e| {
                KeymapParseError::InvalidBinding {
                    index: idx,
                    message: format!("invalid `keys`: {e}"),
                }
            })?;

            let when = match obj.get("when").and_then(|v| v.as_str()) {
                Some(expr) => KeybindingWhen::parse(expr).map_err(|e| KeymapParseError::InvalidBinding {
                    index: idx,
                    message: format!("invalid `when`: {e}"),
                })?,
                None => KeybindingWhen::Always,
            };

            let args = obj.get("args").cloned();

            bindings.push(Keybinding {
                sequence,
                command,
                args,
                when,
            });
        }

        Ok(Self { bindings })
    }
}

fn key_sequence_for_platform(
    obj: &serde_json::Map<String, Value>,
    platform: Platform,
) -> Option<String> {
    let platform_key = match platform {
        Platform::MacOS => "mac",
        Platform::Windows => "win",
        Platform::Linux => "linux",
        Platform::Other => "other",
    };
    if let Some(v) = obj.get(platform_key).and_then(|v| v.as_str()) {
        return Some(v.to_string());
    }
    if let Some(v) = obj.get("keys").and_then(|v| v.as_str()) {
        return Some(v.to_string());
    }
    if let Some(v) = obj.get("key").and_then(|v| v.as_str()) {
        return Some(v.to_string());
    }
    None
}

#[derive(Debug, Error)]
pub enum KeymapParseError {
    #[error("invalid keymap json: {0}")]
    Json(String),
    #[error("invalid keymap format: {0}")]
    InvalidFormat(String),
    #[error("invalid binding[{index}]: {message}")]
    InvalidBinding { index: usize, message: String },
}

#[derive(Debug, Error, Clone)]
pub enum KeySequenceParseError {
    #[error("empty key sequence")]
    EmptySequence,
    #[error("empty chord in key sequence")]
    EmptyChord,
    #[error("chord has no key: {0}")]
    MissingKey(String),
    #[error("chord has multiple keys: {0}")]
    MultipleKeys(String),
    #[error("unknown token `{0}`")]
    UnknownToken(String),
    #[error("invalid function key `{0}`")]
    InvalidFunctionKey(String),
}

fn parse_key_sequence(spec: &str, platform: Platform) -> Result<Vec<KeyStroke>, KeySequenceParseError> {
    let chords: Vec<&str> = spec.trim().split_whitespace().collect();
    if chords.is_empty() {
        return Err(KeySequenceParseError::EmptySequence);
    }
    let mut out: Vec<KeyStroke> = Vec::with_capacity(chords.len());
    for chord in chords {
        let chord = chord.trim();
        if chord.is_empty() {
            return Err(KeySequenceParseError::EmptyChord);
        }
        out.push(parse_chord(chord, platform)?);
    }
    Ok(out)
}

fn parse_chord(chord: &str, platform: Platform) -> Result<KeyStroke, KeySequenceParseError> {
    let mut modifiers = Modifiers::NONE;
    let mut key: Option<Key> = None;

    for raw in chord.split('+') {
        let token = raw.trim();
        if token.is_empty() {
            continue;
        }

        let token_lc = token.to_ascii_lowercase();
        if let Some(m) = modifier_from_token(&token_lc, platform) {
            modifiers.insert(m);
            continue;
        }

        let parsed_key = key_from_token(token)?;
        if key.is_some() {
            return Err(KeySequenceParseError::MultipleKeys(chord.to_string()));
        }
        key = Some(parsed_key);
    }

    let Some(key) = key else {
        return Err(KeySequenceParseError::MissingKey(chord.to_string()));
    };
    Ok(KeyStroke::new(key, modifiers))
}

fn modifier_from_token(token_lc: &str, platform: Platform) -> Option<Modifiers> {
    match token_lc {
        "shift" => Some(Modifiers::SHIFT),
        "ctrl" | "control" => Some(Modifiers::CTRL),
        "alt" | "option" => Some(Modifiers::ALT),
        "cmd" | "command" | "meta" | "super" => Some(Modifiers::META),
        "primary" | "cmdorctrl" => Some(Modifiers::primary(platform)),
        _ => None,
    }
}

fn key_from_token(token: &str) -> Result<Key, KeySequenceParseError> {
    let token_trimmed = token.trim();
    if token_trimmed.is_empty() {
        return Err(KeySequenceParseError::UnknownToken(token.to_string()));
    }

    let lc = token_trimmed.to_ascii_lowercase();
    let key = match lc.as_str() {
        "enter" | "return" => Key::Enter,
        "tab" => Key::Tab,
        "backspace" => Key::Backspace,
        "delete" | "del" => Key::Delete,
        "esc" | "escape" => Key::Escape,
        "space" => Key::Space,
        "left" | "arrowleft" => Key::Left,
        "right" | "arrowright" => Key::Right,
        "up" | "arrowup" => Key::Up,
        "down" | "arrowdown" => Key::Down,
        "home" => Key::Home,
        "end" => Key::End,
        "pageup" => Key::PageUp,
        "pagedown" => Key::PageDown,
        "plus" => Key::Char('+'),
        "minus" => Key::Char('-'),
        _ => {
            if let Some(rest) = lc.strip_prefix('f') {
                let num = rest
                    .parse::<u8>()
                    .map_err(|_| KeySequenceParseError::InvalidFunctionKey(token.to_string()))?;
                if (1..=24).contains(&num) {
                    Key::F(num)
                } else {
                    return Err(KeySequenceParseError::InvalidFunctionKey(token.to_string()));
                }
            } else if token_trimmed.chars().count() == 1 {
                let ch = token_trimmed.chars().next().unwrap();
                Key::Char(ch)
            } else {
                return Err(KeySequenceParseError::UnknownToken(token.to_string()));
            }
        }
    };
    Ok(key.normalized())
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedCommand {
    pub id: String,
    pub args: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum KeybindingResolverResult {
    Matched(ResolvedCommand),
    PendingChord,
    NotHandled,
}

pub struct KeybindingResolver {
    platform: Platform,
    keymap: Keymap,
    chord_timeout: Duration,
    pending: Vec<KeyStroke>,
    pending_since: Option<Instant>,
}

impl KeybindingResolver {
    pub fn new(platform: Platform, keymap: Keymap) -> Self {
        Self {
            platform,
            keymap,
            chord_timeout: Duration::from_millis(1000),
            pending: Vec::new(),
            pending_since: None,
        }
    }

    pub fn platform(&self) -> Platform {
        self.platform
    }

    pub fn set_keymap(&mut self, keymap: Keymap) {
        self.keymap = keymap;
        self.reset_chord();
    }

    pub fn set_chord_timeout(&mut self, timeout: Duration) {
        self.chord_timeout = timeout;
    }

    pub fn reset_chord(&mut self) {
        self.pending.clear();
        self.pending_since = None;
    }

    pub fn pending_sequence(&self) -> &[KeyStroke] {
        &self.pending
    }

    pub fn resolve(
        &mut self,
        stroke: KeyStroke,
        ctx: &KeybindingContext,
    ) -> KeybindingResolverResult {
        self.maybe_expire_pending();

        // Prefer continuing an existing chord.
        if !self.pending.is_empty() {
            let mut seq = self.pending.clone();
            seq.push(stroke);

            if let Some(cmd) = self.match_exact(&seq, ctx) {
                self.reset_chord();
                return KeybindingResolverResult::Matched(cmd);
            }

            if self.has_prefix(&seq, ctx) {
                self.pending = seq;
                self.pending_since = Some(Instant::now());
                return KeybindingResolverResult::PendingChord;
            }

            // Chord failed: reset and try the current keystroke as a fresh start.
            self.reset_chord();
        }

        let seq = vec![stroke];

        if let Some(cmd) = self.match_exact(&seq, ctx) {
            return KeybindingResolverResult::Matched(cmd);
        }

        if self.has_prefix(&seq, ctx) {
            self.pending = seq;
            self.pending_since = Some(Instant::now());
            return KeybindingResolverResult::PendingChord;
        }

        KeybindingResolverResult::NotHandled
    }

    fn maybe_expire_pending(&mut self) {
        let Some(since) = self.pending_since else {
            return;
        };
        if since.elapsed() > self.chord_timeout {
            self.reset_chord();
        }
    }

    fn match_exact(&self, seq: &[KeyStroke], ctx: &KeybindingContext) -> Option<ResolvedCommand> {
        let mut found: Option<&Keybinding> = None;
        for binding in self.keymap.bindings() {
            if binding.sequence.as_slice() != seq {
                continue;
            }
            if !binding.when.eval(ctx) {
                continue;
            }
            found = Some(binding);
        }
        found.map(|b| ResolvedCommand {
            id: b.command.clone(),
            args: b.args.clone(),
        })
    }

    fn has_prefix(&self, seq: &[KeyStroke], ctx: &KeybindingContext) -> bool {
        for binding in self.keymap.bindings() {
            if !binding.when.eval(ctx) {
                continue;
            }
            if binding.sequence.len() <= seq.len() {
                continue;
            }
            if binding.sequence[..seq.len()] == *seq {
                return true;
            }
        }
        false
    }
}

/// Dispatch a resolved command into `EditorUi` using a small built-in command set.
///
/// Returns:
/// - `Ok(true)` when the command is recognized and executed
/// - `Ok(false)` when the command is unknown (host should handle it)
pub fn dispatch_command_to_editor_ui(
    ui: &mut EditorUi,
    cmd: &ResolvedCommand,
) -> Result<bool, UiError> {
    match cmd.id.as_str() {
        // Editing
        "editor.undo" => {
            ui.undo()?;
            Ok(true)
        }
        "editor.redo" => {
            ui.redo()?;
            Ok(true)
        }
        "editor.backspace" | "editor.deleteBackward" => {
            ui.backspace()?;
            Ok(true)
        }
        "editor.deleteForward" => {
            ui.delete_forward()?;
            Ok(true)
        }
        "editor.deleteWordBackward" => {
            ui.delete_word_back()?;
            Ok(true)
        }
        "editor.deleteWordForward" => {
            ui.delete_word_forward()?;
            Ok(true)
        }
        "editor.insertTab" => {
            ui.insert_tab()?;
            Ok(true)
        }
        "editor.insertNewline" => {
            ui.commit_text("\n")?;
            Ok(true)
        }
        "editor.commitText" => {
            let text = match &cmd.args {
                Some(Value::String(s)) => s.as_str(),
                Some(Value::Object(obj)) => obj.get("text").and_then(|v| v.as_str()).unwrap_or(""),
                _ => "",
            };
            ui.commit_text(text)?;
            Ok(true)
        }
        "editor.pasteText" => {
            let text = match &cmd.args {
                Some(Value::String(s)) => s.as_str(),
                Some(Value::Object(obj)) => obj.get("text").and_then(|v| v.as_str()).unwrap_or(""),
                _ => "",
            };
            ui.paste_text(text)?;
            Ok(true)
        }

        // Navigation (no selection)
        "editor.moveLeft" => {
            ui.move_grapheme_left()?;
            Ok(true)
        }
        "editor.moveRight" => {
            ui.move_grapheme_right()?;
            Ok(true)
        }
        "editor.moveWordLeft" => {
            ui.move_word_left()?;
            Ok(true)
        }
        "editor.moveWordRight" => {
            ui.move_word_right()?;
            Ok(true)
        }
        "editor.moveUp" => {
            ui.move_visual_by_rows(-1)?;
            Ok(true)
        }
        "editor.moveDown" => {
            ui.move_visual_by_rows(1)?;
            Ok(true)
        }
        "editor.pageUp" => {
            ui.move_visual_by_pages(-1)?;
            Ok(true)
        }
        "editor.pageDown" => {
            ui.move_visual_by_pages(1)?;
            Ok(true)
        }
        "editor.lineStart" => {
            ui.move_to_visual_line_start()?;
            Ok(true)
        }
        "editor.lineEnd" => {
            ui.move_to_visual_line_end()?;
            Ok(true)
        }
        "editor.docStart" => {
            ui.move_to_document_start()?;
            Ok(true)
        }
        "editor.docEnd" => {
            ui.move_to_document_end()?;
            Ok(true)
        }
        "editor.moveToMatchingBracket" => {
            ui.move_to_matching_bracket()?;
            Ok(true)
        }
        "editor.selectAll" => {
            let len = ui.text().chars().count();
            ui.set_selections_offsets(&[(0, len)], 0)?;
            Ok(true)
        }

        // Selection variants
        "editor.selectLeft" => {
            ui.move_grapheme_left_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectRight" => {
            ui.move_grapheme_right_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectWordLeft" => {
            ui.move_word_left_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectWordRight" => {
            ui.move_word_right_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectUp" => {
            ui.move_visual_by_rows_and_modify_selection(-1)?;
            Ok(true)
        }
        "editor.selectDown" => {
            ui.move_visual_by_rows_and_modify_selection(1)?;
            Ok(true)
        }
        "editor.selectPageUp" => {
            ui.move_visual_by_pages_and_modify_selection(-1)?;
            Ok(true)
        }
        "editor.selectPageDown" => {
            ui.move_visual_by_pages_and_modify_selection(1)?;
            Ok(true)
        }
        "editor.selectLineStart" => {
            ui.move_to_visual_line_start_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectLineEnd" => {
            ui.move_to_visual_line_end_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectDocStart" => {
            ui.move_to_document_start_and_modify_selection()?;
            Ok(true)
        }
        "editor.selectDocEnd" => {
            ui.move_to_document_end_and_modify_selection()?;
            Ok(true)
        }

        _ => Ok(false),
    }
}

#[derive(Debug, Error, Clone)]
pub enum WhenParseError {
    #[error("unexpected token near `{0}`")]
    Unexpected(String),
    #[error("expected closing `)`")]
    ExpectedRParen,
    #[error("unexpected end of expression")]
    UnexpectedEof,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum WhenToken {
    Ident(String),
    And,
    Or,
    Not,
    LParen,
    RParen,
}

struct WhenParser<'a> {
    src: &'a str,
    idx: usize,
    lookahead: Option<WhenToken>,
}

impl<'a> WhenParser<'a> {
    fn new(src: &'a str) -> Self {
        Self {
            src,
            idx: 0,
            lookahead: None,
        }
    }

    fn parse_expr(&mut self) -> Result<WhenExpr, WhenParseError> {
        self.parse_or()
    }

    fn parse_or(&mut self) -> Result<WhenExpr, WhenParseError> {
        let mut left = self.parse_and()?;
        while matches!(self.peek_token()?, Some(WhenToken::Or)) {
            self.next_token()?;
            let right = self.parse_and()?;
            left = match left {
                WhenExpr::Or(mut parts) => {
                    parts.push(right);
                    WhenExpr::Or(parts)
                }
                other => WhenExpr::Or(vec![other, right]),
            };
        }
        Ok(left)
    }

    fn parse_and(&mut self) -> Result<WhenExpr, WhenParseError> {
        let mut left = self.parse_unary()?;
        while matches!(self.peek_token()?, Some(WhenToken::And)) {
            self.next_token()?;
            let right = self.parse_unary()?;
            left = match left {
                WhenExpr::And(mut parts) => {
                    parts.push(right);
                    WhenExpr::And(parts)
                }
                other => WhenExpr::And(vec![other, right]),
            };
        }
        Ok(left)
    }

    fn parse_unary(&mut self) -> Result<WhenExpr, WhenParseError> {
        match self.peek_token()? {
            Some(WhenToken::Not) => {
                self.next_token()?;
                Ok(WhenExpr::Not(Box::new(self.parse_unary()?)))
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_primary(&mut self) -> Result<WhenExpr, WhenParseError> {
        match self.next_token()? {
            Some(WhenToken::Ident(id)) => match id.as_str() {
                "true" => Ok(WhenExpr::Const(true)),
                "false" => Ok(WhenExpr::Const(false)),
                _ => Ok(WhenExpr::Key(id)),
            },
            Some(WhenToken::LParen) => {
                let inner = self.parse_expr()?;
                match self.next_token()? {
                    Some(WhenToken::RParen) => Ok(inner),
                    _ => Err(WhenParseError::ExpectedRParen),
                }
            }
            Some(tok) => Err(WhenParseError::Unexpected(format!("{tok:?}"))),
            None => Err(WhenParseError::UnexpectedEof),
        }
    }

    fn expect_end(&mut self) -> Result<(), WhenParseError> {
        match self.next_token()? {
            Some(tok) => Err(WhenParseError::Unexpected(format!("{tok:?}"))),
            None => Ok(()),
        }
    }

    fn peek_token(&mut self) -> Result<Option<WhenToken>, WhenParseError> {
        if self.lookahead.is_none() {
            self.lookahead = self.lex_token()?;
        }
        Ok(self.lookahead.clone())
    }

    fn next_token(&mut self) -> Result<Option<WhenToken>, WhenParseError> {
        if let Some(tok) = self.lookahead.take() {
            return Ok(Some(tok));
        }
        self.lex_token()
    }

    fn lex_token(&mut self) -> Result<Option<WhenToken>, WhenParseError> {
        self.skip_ws();
        if self.idx >= self.src.len() {
            return Ok(None);
        }

        let rest = &self.src[self.idx..];
        if rest.starts_with("&&") {
            self.idx += 2;
            return Ok(Some(WhenToken::And));
        }
        if rest.starts_with("||") {
            self.idx += 2;
            return Ok(Some(WhenToken::Or));
        }
        let ch = rest.chars().next().ok_or(WhenParseError::UnexpectedEof)?;
        match ch {
            '!' => {
                self.idx += 1;
                Ok(Some(WhenToken::Not))
            }
            '(' => {
                self.idx += 1;
                Ok(Some(WhenToken::LParen))
            }
            ')' => {
                self.idx += 1;
                Ok(Some(WhenToken::RParen))
            }
            _ => {
                if !is_ident_start(ch) {
                    return Err(WhenParseError::Unexpected(rest.chars().take(8).collect()));
                }
                let start = self.idx;
                self.idx += ch.len_utf8();
                while self.idx < self.src.len() {
                    let c = self.src[self.idx..].chars().next().unwrap();
                    if is_ident_continue(c) {
                        self.idx += c.len_utf8();
                    } else {
                        break;
                    }
                }
                let ident = self.src[start..self.idx].to_string();
                Ok(Some(WhenToken::Ident(ident)))
            }
        }
    }

    fn skip_ws(&mut self) {
        while self.idx < self.src.len() {
            let c = self.src[self.idx..].chars().next().unwrap();
            if c.is_whitespace() {
                self.idx += c.len_utf8();
            } else {
                break;
            }
        }
    }
}

fn is_ident_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_' || c == '$'
}

fn is_ident_continue(c: char) -> bool {
    is_ident_start(c) || c.is_ascii_digit() || matches!(c, '.' | ':' | '-' )
}
