//! TUI 编辑器演示
//!
//! 使用 crossterm 和 ratatui 构建的终端文本编辑器
//!
//! # 用法
//!
//! ```bash
//! cargo run -p tui-editor -- <file_path>
//! ```
//!
//! # Sublime `.sublime-syntax`（可选）
//!
//! 如果当前目录存在匹配的 `.sublime-syntax` 文件（例如 `TOML.sublime-syntax`），会自动启用
//! `editor-core-sublime` 语法高亮与折叠；否则（JSON/INI 等）会回退到内置正则高亮。
//!
//! # LSP（可选）
//!
//! 演示支持连接任意 LSP 服务器（stdio JSON-RPC）。
//!
//! - 默认行为：打开 `.rs` 文件时尝试启动 `rust-analyzer`（若已安装）
//! - 自定义：通过环境变量指定任意 LSP 服务器命令（对所有文件生效）
//!
//! ```bash
//! # 例：Python (pylsp)
//! EDITOR_CORE_LSP_CMD=pylsp EDITOR_CORE_LSP_LANGUAGE_ID=python cargo run -p tui-editor -- foo.py
//! ```
//!
//! 连接成功后会自动启用：
//! - 语义高亮（semanticTokens/full）
//! - 代码折叠（foldingRange）
//!
//! # 快捷键
//!
//! - 方向键: 移动光标
//! - Shift+方向键: 选择文本
//! - Home/End: 行首/行尾
//! - PageUp/PageDown: 翻页
//! - Ctrl+S: 保存文件
//! - Ctrl+X: 退出
//! - Ctrl+C: 复制选中文本
//! - Ctrl+V: 粘贴
//! - Ctrl+B: 切换矩形选择模式（Box/Column Selection）
//! - Ctrl+L: 折叠/展开（如果当前行有可折叠区域）
//! - Ctrl+U: 展开所有折叠
//! - Ctrl+F: 查找（输入完成后 Enter 查找下一个）
//! - F3 / Shift+F3: 查找下一个 / 上一个
//! - Ctrl+Shift+H: 替换（两步输入：Find / Replace）
//! - Ctrl+Shift+R: 替换当前
//! - Ctrl+Shift+A: 全部替换
//! - Alt+C / Alt+W / Alt+R: 切换大小写/整词/正则
//! - Backspace/Delete: 删除字符
//! - Enter: 插入换行
//! - 支持 IME 输入

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use editor_core::{
    Command, CommandResult, CursorCommand, EditCommand, EditorStateManager,
    FOLD_PLACEHOLDER_STYLE_ID, Position, SearchOptions, Selection, StyleLayerId, ViewCommand,
    layout::{cell_width_at, visual_x_for_column},
};
use editor_core_highlight_simple::{
    RegexHighlightProcessor, SIMPLE_STYLE_BOOLEAN, SIMPLE_STYLE_COMMENT, SIMPLE_STYLE_KEY,
    SIMPLE_STYLE_NULL, SIMPLE_STYLE_NUMBER, SIMPLE_STYLE_SECTION, SIMPLE_STYLE_STRING,
    SimpleIniStyles, SimpleJsonStyles,
};
use editor_core_lsp::{
    LspContentChange, LspDocument, LspSession, LspSessionStartOptions, clear_lsp_state,
    decode_semantic_style_id, path_to_file_uri,
};
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};
use ratatui::{
    Frame, Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};
use serde_json::json;
use std::{
    env, fs,
    io::{self, stdout},
    path::{Path, PathBuf},
    process::{self, Command as ProcessCommand, Stdio},
    time::{Duration, Instant},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InputMode {
    Normal,
    Find,
    ReplaceFind,
    ReplaceWith,
}

fn sublime_syntax_filename_for_extension(ext: &str) -> Option<&'static str> {
    // Demo map: keep small and explicit.
    match ext {
        "rs" => Some("Rust.sublime-syntax"),
        "toml" => Some("TOML.sublime-syntax"),
        "json" => Some("JSON.sublime-syntax"),
        "ini" | "conf" => Some("INI.sublime-syntax"),
        _ => None,
    }
}

fn find_project_root(path: &Path) -> Option<PathBuf> {
    let mut dir = if path.is_dir() {
        path.to_path_buf()
    } else {
        path.parent()?.to_path_buf()
    };

    // Keep this list small and generic. Callers may override via `EDITOR_CORE_LSP_ROOT`.
    const MARKERS: [&str; 6] = [
        "Cargo.toml",
        "package.json",
        "pyproject.toml",
        "go.mod",
        "Gemfile",
        ".git",
    ];

    loop {
        if MARKERS.iter().any(|m| dir.join(m).exists()) {
            return Some(dir);
        }
        if !dir.pop() {
            break;
        }
    }

    None
}

fn guess_lsp_language_id(path: &Path) -> String {
    let ext = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    match ext.as_str() {
        "rs" => "rust",
        "toml" => "toml",
        "json" => "json",
        "yaml" | "yml" => "yaml",
        "md" | "markdown" => "markdown",
        "py" => "python",
        "js" => "javascript",
        "jsx" => "javascriptreact",
        "ts" => "typescript",
        "tsx" => "typescriptreact",
        "go" => "go",
        "c" | "h" => "c",
        "cc" | "cpp" | "cxx" | "hpp" | "hh" => "cpp",
        "java" => "java",
        "kt" | "kts" => "kotlin",
        "swift" => "swift",
        "sh" | "bash" => "shellscript",
        "html" | "htm" => "html",
        "css" => "css",
        _ => "plaintext",
    }
    .to_string()
}

/// 应用状态
struct App {
    /// 状态管理器
    state_manager: EditorStateManager,
    /// 文件路径
    file_path: PathBuf,
    /// 是否需要退出
    should_quit: bool,
    /// 确认退出模式（如果有未保存修改）
    confirm_quit: bool,
    /// 状态消息
    status_message: String,
    /// 剪贴板
    clipboard: String,
    /// 简单语法高亮（基于正则规则；JSON/INI 在找不到 `.sublime-syntax` 时使用）
    syntax_highlighter: Option<RegexHighlightProcessor>,
    /// Sublime Text `.sublime-syntax`（可选；找不到定义时禁用）
    sublime_syntax: Option<SublimeProcessor>,
    /// LSP session over stdio (optional; auto-enabled based on file/env config)
    lsp: Option<LspSession>,
    /// 矩形选择模式（column/box selection）
    rect_selection_mode: bool,
    /// 矩形选择锚点（开始 selection 的位置）
    rect_selection_anchor: Option<Position>,
    /// 上一次插入文本的时间（用于 idle 时结束 undo group）
    last_insert_time: Option<Instant>,
    /// 查找/替换选项
    search_options: SearchOptions,
    /// 当前查找字符串
    search_query: String,
    /// 当前替换字符串
    replace_query: String,
    /// 当前输入模式（Normal/Find/Replace）
    input_mode: InputMode,
    /// 输入缓冲区（用于查找/替换 prompt）
    input_buffer: String,
}

impl App {
    /// 创建新的应用实例
    fn new(file_path: PathBuf) -> io::Result<Self> {
        // 读取文件内容（如果存在）
        let content = if file_path.exists() {
            fs::read_to_string(&file_path)?
        } else {
            String::new()
        };

        let mut state_manager = EditorStateManager::new(&content, 80);

        // 订阅状态变更
        state_manager.subscribe(|_change| {
            // 可以在这里处理状态变更通知
        });

        let mut app = Self {
            state_manager,
            file_path,
            should_quit: false,
            confirm_quit: false,
            status_message: String::new(),
            clipboard: String::new(),
            syntax_highlighter: None,
            sublime_syntax: None,
            lsp: None,
            rect_selection_mode: false,
            rect_selection_anchor: None,
            last_insert_time: None,
            search_options: SearchOptions::default(),
            search_query: String::new(),
            replace_query: String::new(),
            input_mode: InputMode::Normal,
            input_buffer: String::new(),
        };

        app.maybe_enable_lsp(&content);
        app.configure_syntax_highlighting();

        Ok(app)
    }

    fn file_extension_lowercase(&self) -> Option<String> {
        self.file_path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_ascii_lowercase())
    }

    fn configure_syntax_highlighting(&mut self) {
        // Clear previous state first to avoid mixing highlight sources.
        self.state_manager
            .clear_style_layer(StyleLayerId::SIMPLE_SYNTAX);
        self.syntax_highlighter = None;
        self.state_manager
            .clear_style_layer(StyleLayerId::SUBLIME_SYNTAX);
        self.sublime_syntax = None;

        // If LSP semantic tokens are available, prefer them for any language.
        if self
            .lsp
            .as_ref()
            .is_some_and(|lsp| lsp.supports_semantic_tokens())
        {
            return;
        }

        let Some(ext) = self.file_extension_lowercase() else {
            return;
        };

        // Rust: prefer LSP. If LSP is not available, fallback to `Rust.sublime-syntax` when present.
        if ext == "rs" {
            if self.lsp.is_none()
                && self.try_enable_sublime_syntax_by_filename("Rust.sublime-syntax")
            {
                if !self.status_message.is_empty() {
                    self.status_message =
                        format!("{}；已回退到 Rust.sublime-syntax", self.status_message);
                } else {
                    self.status_message = "已启用 Rust.sublime-syntax（无 LSP）".to_string();
                }
            }
            return;
        }

        // JSON/INI: prefer `.sublime-syntax` from CWD; fallback to internal regex highlighting.
        if ext == "json" || ext == "ini" || ext == "conf" {
            if let Some(syntax_file) = sublime_syntax_filename_for_extension(&ext)
                && self.try_enable_sublime_syntax_by_filename(syntax_file)
            {
                return;
            }

            self.syntax_highlighter = match ext.as_str() {
                "json" => RegexHighlightProcessor::json_default(SimpleJsonStyles::default()).ok(),
                "ini" | "conf" => {
                    RegexHighlightProcessor::ini_default(SimpleIniStyles::default()).ok()
                }
                _ => None,
            };
            if let Some(highlighter) = self.syntax_highlighter.as_mut() {
                let _ = self.state_manager.apply_processor(highlighter);
            }
            return;
        }

        // Other mapped extensions: try `.sublime-syntax` from CWD; otherwise disable.
        if let Some(syntax_file) = sublime_syntax_filename_for_extension(&ext) {
            let _ = self.try_enable_sublime_syntax_by_filename(syntax_file);
        }
    }

    fn try_enable_sublime_syntax_by_filename(&mut self, syntax_file: &str) -> bool {
        let cwd = match env::current_dir() {
            Ok(dir) => dir,
            Err(err) => {
                self.status_message = format!("读取当前目录失败，无法加载语法: {}", err);
                return false;
            }
        };

        let path = cwd.join(syntax_file);
        if !path.is_file() {
            return false;
        }

        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = match syntax_set.load_from_path(&path) {
            Ok(s) => s,
            Err(err) => {
                self.status_message = format!(
                    "解析/编译 `.sublime-syntax` 失败（{}）: {}",
                    path.display(),
                    err
                );
                return false;
            }
        };

        let mut processor = SublimeProcessor::new(syntax, syntax_set);
        if let Err(err) = self.state_manager.apply_processor(&mut processor) {
            self.status_message =
                format!("应用 `.sublime-syntax` 失败（{}）: {}", path.display(), err);
            return false;
        }

        self.sublime_syntax = Some(processor);
        true
    }

    fn maybe_enable_lsp(&mut self, initial_text: &str) {
        let configured_cmd = env::var("EDITOR_CORE_LSP_CMD")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let default_cmd = self
            .file_extension_lowercase()
            .is_some_and(|ext| ext == "rs")
            .then(|| "rust-analyzer".to_string());

        let Some(cmd_name) = configured_cmd.or(default_cmd) else {
            return;
        };

        let args: Vec<String> = env::var("EDITOR_CORE_LSP_ARGS")
            .ok()
            .map(|s| s.split_whitespace().map(|p| p.to_string()).collect())
            .unwrap_or_default();

        let language_id = env::var("EDITOR_CORE_LSP_LANGUAGE_ID")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| guess_lsp_language_id(&self.file_path));

        let root_dir = env::var("EDITOR_CORE_LSP_ROOT")
            .ok()
            .map(PathBuf::from)
            .or_else(|| find_project_root(&self.file_path))
            .unwrap_or_else(|| {
                self.file_path
                    .parent()
                    .unwrap_or_else(|| Path::new("."))
                    .to_path_buf()
            });

        let root_uri = path_to_file_uri(&root_dir);
        let doc_uri = path_to_file_uri(&self.file_path);

        let workspace_name = root_dir
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("workspace")
            .to_string();
        let workspace_folders = vec![json!({
            "uri": root_uri.clone(),
            "name": workspace_name,
        })];

        let token_types = vec![
            "namespace",
            "type",
            "class",
            "enum",
            "interface",
            "struct",
            "typeParameter",
            "parameter",
            "variable",
            "property",
            "enumMember",
            "event",
            "function",
            "method",
            "macro",
            "keyword",
            "modifier",
            "comment",
            "string",
            "number",
            "regexp",
            "operator",
        ];

        let token_modifiers = vec![
            "declaration",
            "definition",
            "readonly",
            "static",
            "deprecated",
            "abstract",
            "async",
            "modification",
            "documentation",
            "defaultLibrary",
        ];

        // Build initialize params in the demo (caller-controlled). Consumers may override or
        // replace this entirely.
        let init_params = json!({
            "processId": process::id(),
            "rootUri": root_uri,
            "workspaceFolders": workspace_folders.clone(),
            "capabilities": {
                "workspace": {
                    "configuration": true,
                    "workspaceFolders": true,
                },
                "textDocument": {
                    "semanticTokens": {
                        "dynamicRegistration": false,
                        "requests": { "range": false, "full": { "delta": false } },
                        "tokenTypes": token_types,
                        "tokenModifiers": token_modifiers,
                        "formats": ["relative"],
                        "multilineTokenSupport": true,
                        "overlappingTokenSupport": false,
                    },
                    "foldingRange": {
                        "dynamicRegistration": false,
                        "lineFoldingOnly": true,
                    },
                },
            },
            "clientInfo": { "name": "editor-core tui_editor" },
        });

        let mut cmd = ProcessCommand::new(&cmd_name);
        cmd.args(args);
        cmd.stderr(Stdio::null());

        let start = LspSessionStartOptions {
            cmd,
            workspace_folders: workspace_folders.clone(),
            initialize_params: init_params,
            initialize_timeout: Duration::from_secs(3),
            document: LspDocument {
                uri: doc_uri,
                language_id,
                version: 1,
            },
            initial_text: initial_text.to_string(),
        };

        match LspSession::start(start) {
            Ok(session) => {
                let server_label = session
                    .server_info()
                    .map(|info| match info.version.as_deref() {
                        Some(v) => format!("{} {}", info.name, v),
                        None => info.name.clone(),
                    })
                    .unwrap_or_else(|| cmd_name.clone());

                self.lsp = Some(session);
                self.status_message = format!("已连接 LSP: {}", server_label);
            }
            Err(err) if err.kind() == io::ErrorKind::NotFound => {
                self.status_message = format!("未找到 LSP 服务器命令：{}（已禁用）", cmd_name);
            }
            Err(err) => {
                self.status_message = format!("启动/初始化 LSP 失败（已禁用）: {}", err);
            }
        }
    }

    /// 处理键盘事件
    fn handle_key_event(&mut self, key: KeyEvent) {
        if key.kind != KeyEventKind::Press {
            return;
        }

        // 确认退出模式
        if self.confirm_quit {
            match key.code {
                KeyCode::Char('y') | KeyCode::Char('Y') => {
                    if let Err(e) = self.save_file() {
                        self.status_message = format!("保存失败: {}", e);
                        self.confirm_quit = false;
                    } else {
                        self.should_quit = true;
                    }
                }
                KeyCode::Char('n') | KeyCode::Char('N') => {
                    self.should_quit = true;
                }
                KeyCode::Esc => {
                    self.confirm_quit = false;
                    self.status_message.clear();
                }
                _ => {}
            }
            return;
        }

        if self.input_mode != InputMode::Normal {
            self.handle_prompt_key(key);
            self.adjust_scroll();
            return;
        }

        // 处理普通按键
        match (key.modifiers, key.code) {
            // Ctrl+S: 保存
            (KeyModifiers::CONTROL, KeyCode::Char('s')) => {
                if let Err(e) = self.save_file() {
                    self.status_message = format!("保存失败: {}", e);
                } else {
                    self.status_message = format!("已保存: {}", self.file_path.display());
                }
            }

            // Ctrl+X: 退出
            (KeyModifiers::CONTROL, KeyCode::Char('x')) => {
                if self.state_manager.get_document_state().is_modified {
                    self.confirm_quit = true;
                    self.status_message = "文件已修改。保存吗? (y/n)".to_string();
                } else {
                    self.should_quit = true;
                }
            }

            // Ctrl+C: 复制
            (KeyModifiers::CONTROL, KeyCode::Char('c')) => {
                self.copy_selection();
            }

            // Ctrl+V: 粘贴
            (KeyModifiers::CONTROL, KeyCode::Char('v')) => {
                self.paste();
            }

            // Ctrl+Z: 撤销
            (KeyModifiers::CONTROL, KeyCode::Char('z')) => {
                self.undo();
            }

            // Ctrl+Y: 重做
            (KeyModifiers::CONTROL, KeyCode::Char('y')) => {
                self.redo();
            }

            // Ctrl+F: 查找（输入 query）
            (KeyModifiers::CONTROL, KeyCode::Char('f')) => {
                self.start_find_prompt();
            }

            // Ctrl+Shift+H: 替换（输入 find + replace）
            (mods, KeyCode::Char('h')) if mods == (KeyModifiers::CONTROL | KeyModifiers::SHIFT) => {
                self.start_replace_prompt();
            }

            // F3 / Shift+F3: 查找下一个 / 上一个
            (KeyModifiers::NONE, KeyCode::F(3)) => {
                self.find_next();
            }
            (KeyModifiers::SHIFT, KeyCode::F(3)) => {
                self.find_prev();
            }

            // Ctrl+Shift+R: 替换当前
            (mods, KeyCode::Char('r')) if mods == (KeyModifiers::CONTROL | KeyModifiers::SHIFT) => {
                self.replace_current();
            }

            // Ctrl+Shift+A: 全部替换
            (mods, KeyCode::Char('a')) if mods == (KeyModifiers::CONTROL | KeyModifiers::SHIFT) => {
                self.replace_all();
            }

            // Alt+C/W/R: 切换查找选项
            (mods, KeyCode::Char('c' | 'C')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_case_sensitive();
            }
            (mods, KeyCode::Char('w' | 'W')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_whole_word();
            }
            (mods, KeyCode::Char('r' | 'R')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_regex();
            }

            // Ctrl+L: 折叠/展开（基于当前 folding regions）
            (KeyModifiers::CONTROL, KeyCode::Char('l')) => {
                self.toggle_fold_at_cursor();
            }

            // Ctrl+U: 展开全部折叠
            (KeyModifiers::CONTROL, KeyCode::Char('u')) => {
                self.unfold_all();
            }

            // Ctrl+B: 切换矩形选择模式（Box/Column Selection）
            (KeyModifiers::CONTROL, KeyCode::Char('b')) => {
                self.toggle_rect_selection_mode();
            }

            // 方向键移动
            (mods, KeyCode::Left) => {
                self.move_cursor_left(mods.contains(KeyModifiers::SHIFT));
            }
            (mods, KeyCode::Right) => {
                self.move_cursor_right(mods.contains(KeyModifiers::SHIFT));
            }
            (mods, KeyCode::Up) => {
                self.move_cursor_up(mods.contains(KeyModifiers::SHIFT));
            }
            (mods, KeyCode::Down) => {
                self.move_cursor_down(mods.contains(KeyModifiers::SHIFT));
            }

            // Home/End
            (mods, KeyCode::Home) => {
                self.move_cursor_home(mods.contains(KeyModifiers::SHIFT));
            }
            (mods, KeyCode::End) => {
                self.move_cursor_end(mods.contains(KeyModifiers::SHIFT));
            }

            // PageUp/PageDown
            (_, KeyCode::PageUp) => {
                self.page_up();
            }
            (_, KeyCode::PageDown) => {
                self.page_down();
            }

            // Backspace
            (_, KeyCode::Backspace) => {
                self.backspace();
            }

            // Delete
            (_, KeyCode::Delete) => {
                self.delete();
            }

            // Enter
            (_, KeyCode::Enter) => {
                self.insert_newline();
            }

            // Tab
            (_, KeyCode::Tab) => {
                self.insert_tab();
            }

            // 普通字符输入
            (_, KeyCode::Char(c)) => {
                self.insert_char(c);
            }

            _ => {}
        }

        // 更新滚动位置以跟随光标
        self.adjust_scroll();
    }

    fn toggle_rect_selection_mode(&mut self) {
        self.rect_selection_mode = !self.rect_selection_mode;
        self.rect_selection_anchor = None;
        if self.rect_selection_mode {
            self.status_message = "矩形选择: ON（Shift+方向键）".to_string();
        } else {
            self.status_message = "矩形选择: OFF".to_string();
        }
    }

    fn execute(&mut self, command: Command) -> bool {
        match self.state_manager.execute(command) {
            Ok(_) => true,
            Err(err) => {
                self.status_message = format!("命令失败: {}", err);
                false
            }
        }
    }

    fn execute_result(&mut self, command: Command) -> Option<CommandResult> {
        match self.state_manager.execute(command) {
            Ok(result) => Some(result),
            Err(err) => {
                self.status_message = format!("命令失败: {}", err);
                None
            }
        }
    }

    fn search_options_label(&self) -> String {
        let case = if self.search_options.case_sensitive {
            "Aa"
        } else {
            "aa"
        };
        let word = if self.search_options.whole_word {
            "W"
        } else {
            "-"
        };
        let regex = if self.search_options.regex { "R" } else { "-" };
        format!("{} {}{}", case, word, regex)
    }

    fn start_find_prompt(&mut self) {
        self.input_mode = InputMode::Find;
        self.input_buffer = self.search_query.clone();
        self.status_message.clear();
    }

    fn start_replace_prompt(&mut self) {
        self.input_mode = InputMode::ReplaceFind;
        self.input_buffer = self.search_query.clone();
        self.status_message.clear();
    }

    fn toggle_search_case_sensitive(&mut self) {
        self.search_options.case_sensitive = !self.search_options.case_sensitive;
        self.status_message = format!("查找选项: {}", self.search_options_label());
    }

    fn toggle_search_whole_word(&mut self) {
        self.search_options.whole_word = !self.search_options.whole_word;
        self.status_message = format!("查找选项: {}", self.search_options_label());
    }

    fn toggle_search_regex(&mut self) {
        self.search_options.regex = !self.search_options.regex;
        self.status_message = format!("查找选项: {}", self.search_options_label());
    }

    fn handle_prompt_key(&mut self, key: KeyEvent) {
        match (key.modifiers, key.code) {
            (_, KeyCode::Esc) => {
                self.input_mode = InputMode::Normal;
                self.input_buffer.clear();
                self.status_message.clear();
            }
            (_, KeyCode::Enter) => match self.input_mode {
                InputMode::Find => {
                    self.search_query = self.input_buffer.clone();
                    self.input_mode = InputMode::Normal;
                    self.input_buffer.clear();
                    self.find_next();
                }
                InputMode::ReplaceFind => {
                    self.search_query = self.input_buffer.clone();
                    self.input_mode = InputMode::ReplaceWith;
                    self.input_buffer = self.replace_query.clone();
                }
                InputMode::ReplaceWith => {
                    self.replace_query = self.input_buffer.clone();
                    self.input_mode = InputMode::Normal;
                    self.input_buffer.clear();
                    self.status_message =
                        format!("替换就绪: {} -> {}", self.search_query, self.replace_query);
                }
                InputMode::Normal => {}
            },
            (_, KeyCode::Backspace) => {
                self.input_buffer.pop();
            }
            (mods, KeyCode::Char('c' | 'C')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_case_sensitive();
            }
            (mods, KeyCode::Char('w' | 'W')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_whole_word();
            }
            (mods, KeyCode::Char('r' | 'R')) if mods.contains(KeyModifiers::ALT) => {
                self.toggle_search_regex();
            }
            (_, KeyCode::Char(c)) => {
                self.input_buffer.push(c);
            }
            _ => {}
        }
    }

    fn find_next(&mut self) {
        if self.search_query.is_empty() {
            self.status_message = "查找内容为空（Ctrl+Shift+F 输入）".to_string();
            return;
        }

        let Some(result) = self.execute_result(Command::Cursor(CursorCommand::FindNext {
            query: self.search_query.clone(),
            options: self.search_options,
        })) else {
            return;
        };

        match result {
            CommandResult::SearchMatch { start, end } => {
                self.status_message = format!("找到: {}..{}", start, end);
                self.rect_selection_anchor = None;
            }
            CommandResult::SearchNotFound => {
                self.status_message = "未找到".to_string();
            }
            _ => {}
        }
    }

    fn find_prev(&mut self) {
        if self.search_query.is_empty() {
            self.status_message = "查找内容为空（Ctrl+Shift+F 输入）".to_string();
            return;
        }

        let Some(result) = self.execute_result(Command::Cursor(CursorCommand::FindPrev {
            query: self.search_query.clone(),
            options: self.search_options,
        })) else {
            return;
        };

        match result {
            CommandResult::SearchMatch { start, end } => {
                self.status_message = format!("找到: {}..{}", start, end);
                self.rect_selection_anchor = None;
            }
            CommandResult::SearchNotFound => {
                self.status_message = "未找到".to_string();
            }
            _ => {}
        }
    }

    fn replace_current(&mut self) {
        if self.search_query.is_empty() {
            self.status_message = "查找内容为空（Ctrl+Shift+F 输入）".to_string();
            return;
        }

        let full_lsp_change = self.lsp.as_ref().map(|lsp| {
            let old_char_count = self.state_manager.editor().char_count();
            lsp.full_document_change(&self.state_manager.editor().line_index, old_char_count, "")
        });

        let Some(result) = self.execute_result(Command::Edit(EditCommand::ReplaceCurrent {
            query: self.search_query.clone(),
            replacement: self.replace_query.clone(),
            options: self.search_options,
        })) else {
            return;
        };

        let CommandResult::ReplaceResult { replaced } = result else {
            return;
        };

        self.status_message = format!("替换了 {} 处", replaced);
        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();

        if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    fn replace_all(&mut self) {
        if self.search_query.is_empty() {
            self.status_message = "查找内容为空（Ctrl+Shift+F 输入）".to_string();
            return;
        }

        let full_lsp_change = self.lsp.as_ref().map(|lsp| {
            let old_char_count = self.state_manager.editor().char_count();
            lsp.full_document_change(&self.state_manager.editor().line_index, old_char_count, "")
        });

        let Some(result) = self.execute_result(Command::Edit(EditCommand::ReplaceAll {
            query: self.search_query.clone(),
            replacement: self.replace_query.clone(),
            options: self.search_options,
        })) else {
            return;
        };

        let CommandResult::ReplaceResult { replaced } = result else {
            return;
        };

        self.status_message = format!("全部替换: {} 处", replaced);
        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();

        if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    fn maybe_end_undo_group_after_idle(&mut self) {
        let Some(last_insert_time) = self.last_insert_time else {
            return;
        };

        // Keep behavior simple and predictable: if the user pauses typing for a bit, end the
        // coalescing group so the next insert becomes a new undo step group.
        if last_insert_time.elapsed() < Duration::from_millis(750) {
            return;
        }

        if self
            .state_manager
            .get_undo_redo_state()
            .current_change_group
            .is_none()
        {
            self.last_insert_time = None;
            return;
        }

        // `EndUndoGroup` is a no-op for state versioning.
        self.execute(Command::Edit(EditCommand::EndUndoGroup));
        self.last_insert_time = None;
    }

    fn refresh_syntax_highlighting(&mut self) {
        // For Rust, LSP is the preferred highlighter when active.
        if self.lsp.is_some() {
            return;
        }

        if self.sublime_syntax.is_some() {
            let mut processor = self.sublime_syntax.take().expect("checked");
            if let Err(err) = self.state_manager.apply_processor(&mut processor) {
                self.status_message = format!("刷新 `.sublime-syntax` 失败: {}", err);
            }
            self.sublime_syntax = Some(processor);
            return;
        }

        if let Some(highlighter) = self.syntax_highlighter.as_mut() {
            let _ = self.state_manager.apply_processor(highlighter);
        }
    }

    fn lsp_did_change(&mut self, change: LspContentChange) {
        let result = {
            let Some(lsp) = self.lsp.as_mut() else {
                return;
            };
            lsp.did_change(change)
        };

        if let Err(reason) = result {
            self.disable_lsp(reason);
        }
    }

    fn disable_lsp(&mut self, reason: String) {
        self.lsp = None;
        clear_lsp_state(&mut self.state_manager);
        self.status_message = reason;

        // Rust fallback: try `Rust.sublime-syntax` if available.
        if self
            .file_extension_lowercase()
            .is_some_and(|ext| ext == "rs")
            && self.try_enable_sublime_syntax_by_filename("Rust.sublime-syntax")
        {
            self.status_message = format!("{}；已回退到 Rust.sublime-syntax", self.status_message);
        }
    }

    fn poll_lsp(&mut self) {
        let poll_result = {
            let Some(lsp) = self.lsp.as_mut() else {
                return;
            };
            self.state_manager.apply_processor(lsp)
        };

        if let Err(reason) = poll_result {
            self.disable_lsp(reason);
        }
    }

    fn cursor_offset(&self) -> usize {
        let pos = self.state_manager.editor().cursor_position();
        self.state_manager
            .editor()
            .line_index
            .position_to_char_offset(pos.line, pos.column)
    }

    fn selection_offsets(&self) -> Option<(usize, usize)> {
        let selection = self.state_manager.editor().selection()?;
        let start_offset = self
            .state_manager
            .editor()
            .line_index
            .position_to_char_offset(selection.start.line, selection.start.column);
        let end_offset = self
            .state_manager
            .editor()
            .line_index
            .position_to_char_offset(selection.end.line, selection.end.column);
        Some((start_offset.min(end_offset), start_offset.max(end_offset)))
    }

    fn is_logical_line_hidden(&self, logical_line: usize) -> bool {
        self.state_manager
            .editor()
            .folding_manager
            .regions()
            .iter()
            .any(|region| {
                region.is_collapsed
                    && logical_line > region.start_line
                    && logical_line <= region.end_line
            })
    }

    fn delete_selection(&mut self) {
        let has_multi = !self
            .state_manager
            .editor()
            .secondary_selections()
            .is_empty();

        let Some((start, end)) = self.selection_offsets() else {
            return;
        };

        if start == end && !has_multi {
            self.execute(Command::Cursor(CursorCommand::ClearSelection));
            return;
        }

        let mut full_lsp_change = None::<LspContentChange>;
        let mut lsp_change = None::<LspContentChange>;
        if let Some(lsp) = self.lsp.as_ref() {
            if has_multi {
                let old_char_count = self.state_manager.editor().char_count();
                full_lsp_change = Some(lsp.full_document_change(
                    &self.state_manager.editor().line_index,
                    old_char_count,
                    "",
                ));
            } else {
                lsp_change = Some(lsp.content_change_for_offsets(
                    &self.state_manager.editor().line_index,
                    start,
                    end,
                    "",
                ));
            }
        }

        let before_text = self.state_manager.editor().get_text();
        if !self.execute(Command::Edit(EditCommand::Backspace)) {
            return;
        }
        let after_text = self.state_manager.editor().get_text();
        if after_text == before_text {
            return;
        }

        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();
        if let Some(change) = lsp_change {
            self.lsp_did_change(change);
        } else if let Some(mut change) = full_lsp_change {
            change.text = after_text;
            self.lsp_did_change(change);
        }
    }

    fn insert_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }

        let has_multi = !self
            .state_manager
            .editor()
            .secondary_selections()
            .is_empty();

        let mut full_lsp_change = None::<LspContentChange>;
        let mut lsp_change = None::<LspContentChange>;
        if let Some(lsp) = self.lsp.as_ref() {
            if has_multi {
                let old_char_count = self.state_manager.editor().char_count();
                full_lsp_change = Some(lsp.full_document_change(
                    &self.state_manager.editor().line_index,
                    old_char_count,
                    "",
                ));
            } else {
                let (start, end) = self.selection_offsets().unwrap_or_else(|| {
                    let offset = self.cursor_offset();
                    (offset, offset)
                });
                lsp_change = Some(lsp.content_change_for_offsets(
                    &self.state_manager.editor().line_index,
                    start,
                    end,
                    text,
                ));
            }
        }

        if !self.execute(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        })) {
            return;
        }

        self.rect_selection_anchor = None;
        self.last_insert_time = Some(Instant::now());
        self.refresh_syntax_highlighting();
        if let Some(change) = lsp_change {
            self.lsp_did_change(change);
        } else if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    /// 处理粘贴事件（IME 支持）
    fn handle_paste(&mut self, text: String) {
        let len = text.chars().count();
        self.insert_text(&text);
        self.status_message = format!("粘贴了 {} 个字符", len);
        self.adjust_scroll();
    }

    /// 插入单个字符
    fn insert_char(&mut self, c: char) {
        self.insert_text(&c.to_string());
    }

    /// 插入换行
    fn insert_newline(&mut self) {
        self.insert_text("\n");
    }

    /// 插入 Tab（由 editor-core 根据 tab 设置决定插入 `\\t` 或空格）
    fn insert_tab(&mut self) {
        let mut full_lsp_change = None::<LspContentChange>;
        if let Some(lsp) = self.lsp.as_ref() {
            // Tab 插入（特别是 spaces 模式）在不同光标/列上会产生不同插入文本；
            // 为了保证 demo 的 LSP 同步正确，这里统一走全量替换。
            let old_char_count = self.state_manager.editor().char_count();
            full_lsp_change = Some(lsp.full_document_change(
                &self.state_manager.editor().line_index,
                old_char_count,
                "",
            ));
        }

        if !self.execute(Command::Edit(EditCommand::InsertTab)) {
            return;
        }

        self.rect_selection_anchor = None;
        self.last_insert_time = Some(Instant::now());
        self.refresh_syntax_highlighting();
        if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    /// 退格删除
    fn backspace(&mut self) {
        let has_multi = !self
            .state_manager
            .editor()
            .secondary_selections()
            .is_empty();

        let cursor_state = self.state_manager.get_cursor_state();
        let has_any_selection = cursor_state.selections.iter().any(|s| s.start != s.end);

        if has_any_selection && !has_multi {
            self.delete_selection();
            return;
        }

        let mut full_lsp_change = None::<LspContentChange>;
        let mut lsp_change = None::<LspContentChange>;
        if let Some(lsp) = self.lsp.as_ref() {
            if has_multi {
                let old_char_count = self.state_manager.editor().char_count();
                full_lsp_change = Some(lsp.full_document_change(
                    &self.state_manager.editor().line_index,
                    old_char_count,
                    "",
                ));
            } else {
                let offset = self.cursor_offset();
                if offset > 0 {
                    lsp_change = Some(lsp.content_change_for_offsets(
                        &self.state_manager.editor().line_index,
                        offset - 1,
                        offset,
                        "",
                    ));
                }
            }
        }

        let before_text = self.state_manager.editor().get_text();
        if !self.execute(Command::Edit(EditCommand::Backspace)) {
            return;
        }
        let after_text = self.state_manager.editor().get_text();
        if after_text == before_text {
            return;
        }

        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();
        if let Some(change) = lsp_change {
            self.lsp_did_change(change);
        } else if let Some(mut change) = full_lsp_change {
            change.text = after_text;
            self.lsp_did_change(change);
        }
    }

    /// Delete 键删除
    fn delete(&mut self) {
        let has_multi = !self
            .state_manager
            .editor()
            .secondary_selections()
            .is_empty();

        let cursor_state = self.state_manager.get_cursor_state();
        let has_any_selection = cursor_state.selections.iter().any(|s| s.start != s.end);

        if has_any_selection && !has_multi {
            self.delete_selection();
            return;
        }

        let mut full_lsp_change = None::<LspContentChange>;
        let mut lsp_change = None::<LspContentChange>;
        if let Some(lsp) = self.lsp.as_ref() {
            if has_multi {
                let old_char_count = self.state_manager.editor().char_count();
                full_lsp_change = Some(lsp.full_document_change(
                    &self.state_manager.editor().line_index,
                    old_char_count,
                    "",
                ));
            } else {
                let offset = self.cursor_offset();
                let max_offset = self.state_manager.editor().char_count();
                if offset < max_offset {
                    lsp_change = Some(lsp.content_change_for_offsets(
                        &self.state_manager.editor().line_index,
                        offset,
                        offset + 1,
                        "",
                    ));
                }
            }
        }

        let before_text = self.state_manager.editor().get_text();
        if !self.execute(Command::Edit(EditCommand::DeleteForward)) {
            return;
        }
        let after_text = self.state_manager.editor().get_text();
        if after_text == before_text {
            return;
        }

        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();
        if let Some(change) = lsp_change {
            self.lsp_did_change(change);
        } else if let Some(mut change) = full_lsp_change {
            change.text = after_text;
            self.lsp_did_change(change);
        }
    }

    /// 复制选中文本
    fn copy_selection(&mut self) {
        let cursor_state = self.state_manager.get_cursor_state();
        let selections: Vec<Selection> = cursor_state
            .selections
            .into_iter()
            .filter(|s| s.start != s.end)
            .collect();

        if selections.is_empty() {
            self.status_message = "没有选中文本".to_string();
            return;
        }

        let editor = self.state_manager.editor();
        let line_index = &editor.line_index;

        if selections.len() == 1 {
            let selection = &selections[0];
            let start_offset =
                line_index.position_to_char_offset(selection.start.line, selection.start.column);
            let end_offset =
                line_index.position_to_char_offset(selection.end.line, selection.end.column);
            let (min_offset, max_offset) = if start_offset <= end_offset {
                (start_offset, end_offset)
            } else {
                (end_offset, start_offset)
            };

            self.clipboard = editor
                .piece_table
                .get_range(min_offset, max_offset.saturating_sub(min_offset));
        } else {
            let mut parts = Vec::with_capacity(selections.len());
            for selection in selections {
                let start_offset = line_index
                    .position_to_char_offset(selection.start.line, selection.start.column);
                let end_offset =
                    line_index.position_to_char_offset(selection.end.line, selection.end.column);
                let (min_offset, max_offset) = if start_offset <= end_offset {
                    (start_offset, end_offset)
                } else {
                    (end_offset, start_offset)
                };
                parts.push(
                    editor
                        .piece_table
                        .get_range(min_offset, max_offset.saturating_sub(min_offset)),
                );
            }
            self.clipboard = parts.join("\n");
        }

        self.status_message = format!("已复制 {} 个字符", self.clipboard.chars().count());
    }

    /// 粘贴文本
    fn paste(&mut self) {
        if self.clipboard.is_empty() {
            self.status_message = "剪贴板为空".to_string();
            return;
        }

        let text = self.clipboard.clone();
        let len = text.chars().count();
        self.insert_text(&text);
        self.status_message = format!("粘贴了 {} 个字符", len);
    }

    /// 撤销操作
    fn undo(&mut self) {
        let undo_state = self.state_manager.get_undo_redo_state();
        if !undo_state.can_undo {
            self.status_message = "无可撤销操作".to_string();
            return;
        }

        let full_lsp_change = self.lsp.as_ref().map(|lsp| {
            let old_char_count = self.state_manager.editor().char_count();
            lsp.full_document_change(&self.state_manager.editor().line_index, old_char_count, "")
        });

        if !self.execute(Command::Edit(EditCommand::Undo)) {
            return;
        }

        self.status_message = "已撤销".to_string();
        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();
        if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    /// 重做操作
    fn redo(&mut self) {
        let undo_state = self.state_manager.get_undo_redo_state();
        if !undo_state.can_redo {
            self.status_message = "无可重做操作".to_string();
            return;
        }

        let full_lsp_change = self.lsp.as_ref().map(|lsp| {
            let old_char_count = self.state_manager.editor().char_count();
            lsp.full_document_change(&self.state_manager.editor().line_index, old_char_count, "")
        });

        if !self.execute(Command::Edit(EditCommand::Redo)) {
            return;
        }

        self.status_message = "已重做".to_string();
        self.rect_selection_anchor = None;
        self.last_insert_time = None;
        self.refresh_syntax_highlighting();
        if let Some(mut change) = full_lsp_change {
            change.text = self.state_manager.editor().get_text();
            self.lsp_did_change(change);
        }
    }

    fn toggle_fold_at_cursor(&mut self) {
        let line = self.state_manager.editor().cursor_position().line;
        let toggled = self
            .state_manager
            .editor_mut()
            .folding_manager
            .toggle_region_starting_at_line(line);

        if toggled {
            self.status_message = "已切换折叠状态".to_string();
        } else {
            self.status_message = "该行无可折叠区域".to_string();
        }

        self.adjust_scroll();
    }

    fn unfold_all(&mut self) {
        self.state_manager.editor_mut().folding_manager.expand_all();
        self.status_message = "已展开全部折叠".to_string();
        self.adjust_scroll();
    }

    /// 向左移动光标
    fn move_cursor_left(&mut self, selecting: bool) {
        let pos = self.state_manager.editor().cursor_position();
        if pos.column > 0 {
            let new_pos = Position::new(pos.line, pos.column - 1);
            self.move_cursor_to(new_pos, selecting);
        } else if pos.line > 0 {
            // 移动到上一行的末尾
            let mut prev_line = pos.line - 1;
            while prev_line > 0 && self.is_logical_line_hidden(prev_line) {
                prev_line -= 1;
            }

            let prev_line_len = self
                .state_manager
                .editor()
                .line_index
                .get_line_text(prev_line)
                .unwrap_or_default()
                .chars()
                .count();
            let new_pos = Position::new(prev_line, prev_line_len);
            self.move_cursor_to(new_pos, selecting);
        }
    }

    /// 向右移动光标
    fn move_cursor_right(&mut self, selecting: bool) {
        let pos = self.state_manager.editor().cursor_position();
        let current_line = self
            .state_manager
            .editor()
            .line_index
            .get_line_text(pos.line)
            .unwrap_or_default();
        let line_len = current_line.chars().count();

        if pos.column < line_len {
            let new_pos = Position::new(pos.line, pos.column + 1);
            self.move_cursor_to(new_pos, selecting);
        } else if pos.line + 1 < self.state_manager.editor().line_count() {
            // 移动到下一行的开头
            let mut next_line = pos.line + 1;
            while next_line < self.state_manager.editor().line_count()
                && self.is_logical_line_hidden(next_line)
            {
                next_line += 1;
            }
            if next_line < self.state_manager.editor().line_count() {
                let new_pos = Position::new(next_line, 0);
                self.move_cursor_to(new_pos, selecting);
            }
        }
    }

    /// 向上移动光标
    fn move_cursor_up(&mut self, selecting: bool) {
        self.move_cursor_by_visual_lines(-1, selecting);
    }

    /// 向下移动光标
    fn move_cursor_down(&mut self, selecting: bool) {
        self.move_cursor_by_visual_lines(1, selecting);
    }

    /// 移动到行首
    fn move_cursor_home(&mut self, selecting: bool) {
        let pos = self.state_manager.editor().cursor_position();
        let new_pos = Position::new(pos.line, 0);
        self.move_cursor_to(new_pos, selecting);
    }

    /// 移动到行尾
    fn move_cursor_end(&mut self, selecting: bool) {
        let pos = self.state_manager.editor().cursor_position();
        let line_len = self
            .state_manager
            .editor()
            .line_index
            .get_line_text(pos.line)
            .unwrap_or_default()
            .chars()
            .count();
        let new_pos = Position::new(pos.line, line_len);
        self.move_cursor_to(new_pos, selecting);
    }

    /// 向上翻页
    fn page_up(&mut self) {
        let page = self.state_manager.get_viewport_state().height.unwrap_or(0);
        if page == 0 {
            return;
        }
        self.move_cursor_by_visual_lines(-(page as isize), false);
    }

    /// 向下翻页
    fn page_down(&mut self) {
        let page = self.state_manager.get_viewport_state().height.unwrap_or(0);
        if page == 0 {
            return;
        }
        self.move_cursor_by_visual_lines(page as isize, false);
    }

    fn move_cursor_to(&mut self, new_pos: Position, selecting: bool) {
        let old_pos = self.state_manager.editor().cursor_position();

        if selecting {
            if self.rect_selection_mode {
                let anchor = match self.rect_selection_anchor {
                    Some(anchor) => anchor,
                    None => {
                        self.rect_selection_anchor = Some(old_pos);
                        old_pos
                    }
                };
                self.execute(Command::Cursor(CursorCommand::SetRectSelection {
                    anchor,
                    active: new_pos,
                }));
                // `SetRectSelection` already updates the primary caret; do not call `MoveTo`,
                // otherwise it would collapse secondary selections.
                return;
            }

            if self.state_manager.editor().selection().is_some() {
                self.execute(Command::Cursor(CursorCommand::ExtendSelection {
                    to: new_pos,
                }));
            } else {
                self.execute(Command::Cursor(CursorCommand::SetSelection {
                    start: old_pos,
                    end: new_pos,
                }));
            }
        } else {
            self.rect_selection_anchor = None;
            if self.state_manager.editor().selection().is_some() {
                self.execute(Command::Cursor(CursorCommand::ClearSelection));
            }
        }

        self.execute(Command::Cursor(CursorCommand::MoveTo {
            line: new_pos.line,
            column: new_pos.column,
        }));
    }

    fn column_for_x_in_segment(
        line_text: &str,
        segment_start_col: usize,
        segment_end_col: usize,
        target_x: usize,
        tab_width: usize,
    ) -> usize {
        let mut col = segment_start_col;
        let mut x_in_segment = 0usize;
        let mut x_in_line = visual_x_for_column(line_text, segment_start_col, tab_width);

        for ch in line_text
            .chars()
            .skip(segment_start_col)
            .take(segment_end_col.saturating_sub(segment_start_col))
        {
            let w = cell_width_at(ch, x_in_line, tab_width);
            if x_in_segment + w > target_x {
                break;
            }
            x_in_segment += w;
            x_in_line += w;
            col += 1;
        }

        col
    }

    fn move_cursor_by_visual_lines(&mut self, delta_visual: isize, selecting: bool) {
        let editor = self.state_manager.editor();
        let layout_engine = &editor.layout_engine;
        let cursor_pos = editor.cursor_position();

        let Some((cursor_visual_row, cursor_x)) =
            editor.logical_position_to_visual(cursor_pos.line, cursor_pos.column)
        else {
            return;
        };

        let total_visual = editor.visual_line_count();
        if total_visual == 0 {
            return;
        }

        let target_visual_row = if delta_visual >= 0 {
            cursor_visual_row.saturating_add(delta_visual as usize)
        } else {
            cursor_visual_row.saturating_sub((-delta_visual) as usize)
        }
        .min(total_visual.saturating_sub(1));

        let (target_line, visual_in_line) = editor.visual_to_logical_line(target_visual_row);
        let Some(layout) = layout_engine.get_line_layout(target_line) else {
            return;
        };

        let line_text = editor
            .line_index
            .get_line_text(target_line)
            .unwrap_or_default();
        let line_char_len = line_text.chars().count();

        let segment_start_col = if visual_in_line == 0 {
            0
        } else {
            layout
                .wrap_points
                .get(visual_in_line - 1)
                .map(|wp| wp.char_index)
                .unwrap_or(0)
                .min(line_char_len)
        };

        let segment_end_col = if visual_in_line < layout.wrap_points.len() {
            layout.wrap_points[visual_in_line]
                .char_index
                .min(line_char_len)
        } else {
            line_char_len
        };

        let target_col = Self::column_for_x_in_segment(
            &line_text,
            segment_start_col,
            segment_end_col,
            cursor_x,
            layout_engine.tab_width(),
        );
        self.move_cursor_to(Position::new(target_line, target_col), selecting);
    }

    fn max_scroll_top(&self, viewport_height: usize) -> usize {
        let total_visual = self.state_manager.editor().visual_line_count();
        total_visual.saturating_sub(viewport_height)
    }

    /// 调整滚动位置以跟随光标（按视觉行滚动）
    fn adjust_scroll(&mut self) {
        let viewport_height = self.state_manager.get_viewport_state().height.unwrap_or(0);
        if viewport_height == 0 {
            return;
        }

        let editor = self.state_manager.editor();
        let cursor_pos = editor.cursor_position();

        let Some((cursor_visual_row, _)) =
            editor.logical_position_to_visual(cursor_pos.line, cursor_pos.column)
        else {
            return;
        };

        let mut scroll_top = self.state_manager.get_viewport_state().scroll_top;
        if cursor_visual_row < scroll_top {
            scroll_top = cursor_visual_row;
        }
        if cursor_visual_row >= scroll_top + viewport_height {
            scroll_top = cursor_visual_row - viewport_height + 1;
        }

        scroll_top = scroll_top.min(self.max_scroll_top(viewport_height));
        self.state_manager.set_scroll_top(scroll_top);
    }

    /// 保存文件
    fn save_file(&mut self) -> io::Result<()> {
        let content = self.state_manager.editor().get_text();
        fs::write(&self.file_path, content)?;
        self.state_manager.mark_saved();
        Ok(())
    }

    /// 渲染 UI
    fn render(&mut self, frame: &mut Frame) {
        let size = frame.area();

        // 创建布局
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Min(1),    // 编辑器区域
                Constraint::Length(1), // 状态行
                Constraint::Length(1), // 快捷键提示
            ])
            .split(size);

        // 视口信息（编辑区内侧，不包含边框）
        let editor_area = chunks[0];
        let viewport_height = editor_area.height.saturating_sub(2) as usize;
        let viewport_width = editor_area.width.saturating_sub(2) as usize;

        self.state_manager.set_viewport_height(viewport_height);

        // 更新视口宽度（触发布局引擎重排）
        if viewport_width > 0 && viewport_width != self.state_manager.editor().viewport_width {
            self.execute(Command::View(ViewCommand::SetViewportWidth {
                width: viewport_width,
            }));
        }

        // Resize 后确保 scroll_top 合法，并尽量保持光标可见
        if viewport_height > 0 {
            let max_scroll_top = self.max_scroll_top(viewport_height);
            let current_scroll_top = self.state_manager.get_viewport_state().scroll_top;
            if current_scroll_top > max_scroll_top {
                self.state_manager.set_scroll_top(max_scroll_top);
            }
            self.adjust_scroll();
        }

        // 渲染编辑器内容
        self.render_editor(frame, editor_area);

        // 渲染状态行
        self.render_status_line(frame, chunks[1]);

        // 渲染快捷键提示
        self.render_shortcuts(frame, chunks[2]);
    }

    fn style_for_style_ids(&self, style_ids: &[u32]) -> Style {
        let mut fg = None::<Color>;
        let mut mods = Modifier::empty();

        let semantic_legend = self.lsp.as_ref().and_then(|lsp| lsp.semantic_legend());

        for &style_id in style_ids {
            match style_id {
                SIMPLE_STYLE_STRING => fg = Some(Color::Green),
                SIMPLE_STYLE_NUMBER => fg = Some(Color::Yellow),
                SIMPLE_STYLE_BOOLEAN => fg = Some(Color::Magenta),
                SIMPLE_STYLE_NULL => fg = Some(Color::DarkGray),
                SIMPLE_STYLE_SECTION => {
                    fg = Some(Color::Cyan);
                    mods |= Modifier::BOLD;
                }
                SIMPLE_STYLE_KEY => fg = Some(Color::Blue),
                SIMPLE_STYLE_COMMENT => {
                    fg = Some(Color::DarkGray);
                    mods |= Modifier::ITALIC;
                }
                FOLD_PLACEHOLDER_STYLE_ID => {
                    fg = Some(Color::DarkGray);
                    mods |= Modifier::ITALIC;
                }
                _ => {
                    if let Some(scope) = self
                        .sublime_syntax
                        .as_ref()
                        .and_then(|s| s.scope_mapper.scope_for_style_id(style_id))
                    {
                        let (scope_fg, scope_mods) = style_for_sublime_scope(scope);
                        if scope_fg.is_some() {
                            fg = scope_fg;
                        }
                        mods |= scope_mods;
                        continue;
                    }

                    // `StyleId` 对语义 token 的默认编码：高 16 位 token_type，低 16 位 modifiers。
                    // 这里用一个保守的启发式：只有小于 0x0100_0000 的 ID 才尝试当作语义 token 显示。
                    if style_id < 0x0100_0000 {
                        let (token_type_idx, token_modifiers_bits) =
                            decode_semantic_style_id(style_id);

                        let token_type_name = semantic_legend
                            .and_then(|legend| legend.token_types.get(token_type_idx as usize))
                            .map(|s| s.as_str());

                        fg = match token_type_name {
                            Some("comment") => Some(Color::DarkGray),
                            Some("string") => Some(Color::Green),
                            Some("number") => Some(Color::Yellow),
                            Some("keyword") => Some(Color::LightBlue),
                            Some("function") | Some("method") => Some(Color::Cyan),
                            Some("macro") => Some(Color::Magenta),
                            Some("type")
                            | Some("struct")
                            | Some("enum")
                            | Some("class")
                            | Some("interface")
                            | Some("typeParameter") => Some(Color::LightCyan),
                            Some("namespace") => Some(Color::LightMagenta),
                            Some("parameter") => Some(Color::LightYellow),
                            Some("operator") => Some(Color::LightRed),
                            Some("variable") | Some("property") | Some("enumMember") => {
                                Some(Color::White)
                            }
                            _ => {
                                let fallback_palette = [
                                    Color::Cyan,
                                    Color::Green,
                                    Color::Yellow,
                                    Color::Magenta,
                                    Color::Blue,
                                    Color::Red,
                                ];
                                Some(
                                    fallback_palette
                                        [(token_type_idx as usize) % fallback_palette.len()],
                                )
                            }
                        };

                        // token_modifiers 的位含义由 LSP 服务器的 legend 决定。
                        if let Some(legend) = semantic_legend {
                            for (i, name) in legend.token_modifiers.iter().enumerate() {
                                if i >= 32 {
                                    break;
                                }
                                if token_modifiers_bits & (1u32 << i) == 0 {
                                    continue;
                                }
                                match name.as_str() {
                                    "declaration" | "definition" => mods |= Modifier::BOLD,
                                    "documentation" => mods |= Modifier::ITALIC,
                                    "readonly" => mods |= Modifier::UNDERLINED,
                                    "static" => mods |= Modifier::DIM,
                                    "deprecated" => mods |= Modifier::UNDERLINED,
                                    "async" => mods |= Modifier::ITALIC,
                                    _ => {}
                                }
                            }
                        } else {
                            // 没有 legend 时做一个保守的“演示映射”。
                            if token_modifiers_bits & 0b0001 != 0 {
                                mods |= Modifier::BOLD;
                            }
                            if token_modifiers_bits & 0b0010 != 0 {
                                mods |= Modifier::ITALIC;
                            }
                            if token_modifiers_bits & 0b0100 != 0 {
                                mods |= Modifier::UNDERLINED;
                            }
                        }
                    }
                }
            }
        }

        let mut style = Style::default().fg(Color::White);
        if let Some(color) = fg {
            style = style.fg(color);
        }
        style.add_modifier(mods)
    }

    /// 渲染编辑器内容
    fn render_editor(&self, frame: &mut Frame, area: Rect) {
        let editor = self.state_manager.editor();
        let layout_engine = &editor.layout_engine;
        let line_index = &editor.line_index;

        let inner_height = area.height.saturating_sub(2) as usize;
        let inner_width = area.width.saturating_sub(2) as usize;
        let scroll_top = self.state_manager.get_viewport_state().scroll_top;
        let total_visual = editor.visual_line_count();

        let cursor_state = self.state_manager.get_cursor_state();
        let selections = cursor_state.selections;

        let grid = self
            .state_manager
            .get_viewport_content_styled(scroll_top, inner_height);

        let mut display_lines = Vec::with_capacity(inner_height);

        for i in 0..inner_height {
            if inner_width == 0 {
                display_lines.push(Line::from(""));
                continue;
            }

            let visual_row = scroll_top + i;
            if visual_row >= total_visual {
                display_lines.push(Line::from(""));
                continue;
            }

            let (logical_line, visual_in_line) = editor.visual_to_logical_line(visual_row);
            let Some(layout) = layout_engine.get_line_layout(logical_line) else {
                display_lines.push(Line::from(""));
                continue;
            };

            let line_text = line_index.get_line_text(logical_line).unwrap_or_default();
            let line_char_len = line_text.chars().count();

            let segment_start_col = if visual_in_line == 0 {
                0
            } else {
                layout
                    .wrap_points
                    .get(visual_in_line - 1)
                    .map(|wp| wp.char_index)
                    .unwrap_or(0)
                    .min(line_char_len)
            };

            let mut selection_ranges: Vec<(usize, usize)> = Vec::new();
            for selection in &selections {
                if selection.start == selection.end {
                    continue;
                }

                let (sel_start, sel_end) = if selection.start <= selection.end {
                    (selection.start, selection.end)
                } else {
                    (selection.end, selection.start)
                };

                if logical_line < sel_start.line || logical_line > sel_end.line {
                    continue;
                }

                let start_col = if logical_line == sel_start.line {
                    sel_start.column.min(line_char_len)
                } else {
                    0
                };
                let end_col = if logical_line == sel_end.line {
                    sel_end.column.min(line_char_len)
                } else {
                    line_char_len
                };

                if start_col < end_col {
                    selection_ranges.push((start_col, end_col));
                }
            }

            let Some(headless_line) = grid.lines.get(i) else {
                display_lines.push(Line::from(""));
                continue;
            };

            if headless_line.cells.is_empty() {
                display_lines.push(Line::from(""));
                continue;
            }

            let mut spans: Vec<Span> = Vec::new();
            let mut current_style: Option<Style> = None;
            let mut buffer = String::new();

            for (cell_idx, cell) in headless_line.cells.iter().enumerate() {
                let col = segment_start_col + cell_idx;
                let mut style = self.style_for_style_ids(&cell.styles);

                let is_selected = selection_ranges
                    .iter()
                    .any(|(start, end)| col >= *start && col < *end);
                if is_selected {
                    style = style.bg(Color::Blue).fg(Color::White);
                }

                if current_style.is_none() {
                    current_style = Some(style);
                }

                if current_style != Some(style) {
                    spans.push(Span::styled(
                        std::mem::take(&mut buffer),
                        current_style.unwrap_or_default(),
                    ));
                    current_style = Some(style);
                }

                if cell.ch == '\t' {
                    for _ in 0..cell.width.max(1) {
                        buffer.push(' ');
                    }
                } else {
                    buffer.push(cell.ch);
                }
            }

            if !buffer.is_empty() {
                spans.push(Span::styled(buffer, current_style.unwrap_or_default()));
            }

            display_lines.push(Line::from(spans));
        }

        let paragraph = Paragraph::new(display_lines).block(
            Block::default().borders(Borders::ALL).title(format!(
                " {} {} ",
                self.file_path.display(),
                if self.state_manager.get_document_state().is_modified {
                    "[+]"
                } else {
                    ""
                },
            )),
        );

        frame.render_widget(paragraph, area);

        // 渲染光标（使用 layout_engine 的逻辑 -> 视觉转换）
        if inner_height == 0 || inner_width == 0 {
            return;
        }

        let cursor_pos = editor.cursor_position();
        let cursor_visual = if self.rect_selection_mode {
            editor.logical_position_to_visual_allow_virtual(cursor_pos.line, cursor_pos.column)
        } else {
            editor.logical_position_to_visual(cursor_pos.line, cursor_pos.column)
        };
        let Some((cursor_visual_row, cursor_x)) = cursor_visual else {
            return;
        };

        if cursor_visual_row < scroll_top || cursor_visual_row >= scroll_top + inner_height {
            return;
        }

        let inner_left = area.x + 1;
        let inner_top = area.y + 1;
        let inner_right = area.x + area.width.saturating_sub(2);
        let inner_bottom = area.y + area.height.saturating_sub(2);

        if inner_left > inner_right || inner_top > inner_bottom {
            return;
        }

        let rel_row = (cursor_visual_row - scroll_top) as u16;
        let cursor_x = (inner_left + cursor_x as u16).min(inner_right);
        let cursor_y = (inner_top + rel_row).min(inner_bottom);
        frame.set_cursor_position((cursor_x, cursor_y));
    }

    /// 渲染状态行
    fn render_status_line(&self, frame: &mut Frame, area: Rect) {
        let doc_state = self.state_manager.get_document_state();
        let cursor_pos = self.state_manager.editor().cursor_position();
        let cursor_count = 1 + self.state_manager.editor().secondary_selections().len();
        let rect_tag = if self.rect_selection_mode {
            " | 矩形"
        } else {
            ""
        };

        let status_text = if self.input_mode != InputMode::Normal {
            match self.input_mode {
                InputMode::Find => format!(
                    "Find [{}] > {}  (Enter=Next, Esc=Cancel, Alt+C/W/R=Options)",
                    self.search_options_label(),
                    self.input_buffer
                ),
                InputMode::ReplaceFind => format!(
                    "Replace: Find [{}] > {}  (Enter=Next, Esc=Cancel, Alt+C/W/R=Options)",
                    self.search_options_label(),
                    self.input_buffer
                ),
                InputMode::ReplaceWith => format!(
                    "Replace: With [{}] > {}  (Enter=Done, Esc=Cancel)",
                    self.search_options_label(),
                    self.input_buffer
                ),
                InputMode::Normal => String::new(),
            }
        } else if !self.status_message.is_empty() {
            self.status_message.clone()
        } else {
            format!(
                "行:{} 列:{} | 光标:{}{} | 总行数:{} 字符数:{} | 版本:{}",
                cursor_pos.line + 1,
                cursor_pos.column + 1,
                cursor_count,
                rect_tag,
                doc_state.line_count,
                doc_state.char_count,
                doc_state.version
            )
        };

        let status_line = Paragraph::new(status_text).style(
            Style::default()
                .bg(Color::DarkGray)
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        );

        frame.render_widget(status_line, area);
    }

    /// 渲染快捷键提示
    fn render_shortcuts(&self, frame: &mut Frame, area: Rect) {
        let shortcuts = if self.confirm_quit {
            "Y:保存并退出  N:不保存退出  Esc:取消"
        } else {
            "Ctrl-S:保存  Ctrl-X:退出  Ctrl-Z/Y:撤销/重做  Ctrl-C/V:复制/粘贴  Ctrl-B:矩形  Ctrl-F/U:折叠/全展开  Ctrl-Shift-F/H:查找/替换  F3:下一个  Shift-F3:上一个  Ctrl-Shift-R/A:替换/全部"
        };

        let shortcuts_line =
            Paragraph::new(shortcuts).style(Style::default().bg(Color::Blue).fg(Color::White));

        frame.render_widget(shortcuts_line, area);
    }
}

fn style_for_sublime_scope(scope: &str) -> (Option<Color>, Modifier) {
    // Very small demo mapping: heuristics based on scope naming conventions.
    let mut mods = Modifier::empty();

    if scope.contains("invalid") || scope.contains("illegal") {
        return (Some(Color::LightRed), Modifier::BOLD);
    }

    if scope.contains("comment") {
        mods |= Modifier::ITALIC;
        return (Some(Color::DarkGray), mods);
    }

    if scope.contains("string") {
        return (Some(Color::Green), mods);
    }

    if scope.contains("constant.numeric")
        || scope.contains("meta.number")
        || scope.contains("constant.character.numeric")
    {
        return (Some(Color::Yellow), mods);
    }

    if scope.contains("keyword") {
        return (Some(Color::LightBlue), mods);
    }

    if scope.contains("entity.name")
        || scope.contains("support.type")
        || scope.contains("support.class")
        || scope.contains("storage.type")
    {
        mods |= Modifier::BOLD;
        return (Some(Color::Cyan), mods);
    }

    if scope.contains("punctuation") {
        return (Some(Color::DarkGray), mods);
    }

    (None, mods)
}

fn main() -> io::Result<()> {
    // 获取命令行参数
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("用法: {} <file_path>", args[0]);
        eprintln!("\n示例:");
        eprintln!("  {} example.txt", args[0]);
        process::exit(1);
    }

    let file_path = PathBuf::from(&args[1]);

    // 设置终端
    enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // 创建应用
    let mut app = App::new(file_path)?;

    // 主循环
    let result = run_app(&mut terminal, &mut app);

    // 恢复终端
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    if let Err(err) = result {
        eprintln!("错误: {}", err);
    }

    Ok(())
}

fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    app: &mut App,
) -> io::Result<()> {
    loop {
        app.poll_lsp();
        terminal.draw(|f| app.render(f))?;

        if app.should_quit {
            break;
        }

        // 处理事件
        if event::poll(std::time::Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => {
                    app.handle_key_event(key);
                }
                Event::Paste(text) => {
                    app.handle_paste(text);
                }
                Event::Resize(_, _) => {
                    // 重新渲染
                }
                _ => {}
            }
        }

        app.maybe_end_undo_group_after_idle();
    }

    Ok(())
}
