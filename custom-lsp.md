# AttoEditor：自定义 LSP（按文件扩展名映射）

## 背景 / 现状

AttoEditor 目前仅在打开 Rust 文件（`.rs`）时自动启用 LSP，并且默认只会尝试启动 `rust-analyzer`（可通过环境变量覆写）。其他语言即使存在可用的 LSP 服务器，也不会自动启用。

目标是让 AttoEditor 支持 **“按文件扩展名 → LSP 可执行程序”** 的用户可配置映射，并在打开对应文件时自动启动该 LSP。

> 注：本计划只写设计与落地步骤，不包含任何代码改动。

---

## 目标（MVP）

1. **按扩展名自动启用 LSP**
   - 当打开文件 `foo.<ext>` 时，若 `<ext>` 在配置映射中存在条目，则尝试启动对应 LSP。
   - 启动失败不应影响编辑器可用性：应回退到 Tree-sitter / Sublime 语法高亮链路（与当前逻辑一致）。

2. **配置文件放在“默认 app preferences 目录”下（JSON）**
   - macOS 上使用 `Application Support` 作为 AttoEditor 的用户可写配置根目录（项目现有惯例）。
   - 位置建议（与现有 `session.json`、`treesitter/` 目录保持一致）：
     - `~/Library/Application Support/codes.unwritten.attoeditor/lsp/servers.json`

3. **最小可用的 JSON schema（可版本化）**
   - 支持扩展名到 LSP “可执行命令”的映射。
   - 为了避免未来不可控的破坏性变更，加入 `schema_version`。

4. **兼容现有 Rust 行为**
   - 未创建 `servers.json` 时：打开 `.rs` 仍应像现在一样尝试 `rust-analyzer`（并继续支持环境变量覆写）。

---

## 非目标（MVP 不做）

- 不做 UI 面板编辑该映射（先让用户直接改 JSON）。
- 不做配置文件热重载 / 文件监听（可作为后续增强）。
- 不做“单 workspace 共享一个 LSP session”之类的进程复用优化（先保证功能正确）。
- 不承诺覆盖所有语言 server 的差异化初始化需求（仅提供必要的配置入口）。

---

## 配置文件路径与目录约定

### 配置根目录（macOS）

复用 AttoEditor 现有落盘路径约定（`Application Support`）：

- `~/Library/Application Support/codes.unwritten.attoeditor/`

在其下新增子目录：

- `~/Library/Application Support/codes.unwritten.attoeditor/lsp/`

最终配置文件：

- `~/Library/Application Support/codes.unwritten.attoeditor/lsp/servers.json`

### 行为约定

- 如果文件不存在：使用内置默认映射（至少包含 Rust）。
- 如果 JSON 不可解析 / schema 不兼容：忽略该文件（并记录日志），继续使用内置默认映射。
- 如果某个扩展名条目无效（例如 command 为空）：忽略该条目，其他条目仍可用。

---

## JSON 格式（建议）

### 顶层结构（schema_version + extension_map）

建议格式如下：

```json
{
  "schema_version": 1,
  "extension_map": {
    "rs": { "command": "rust-analyzer", "args": "", "language_id": "rust" },
    "py": { "command": "pylsp", "args": "", "language_id": "python" },
    "ts": { "command": "typescript-language-server", "args": "--stdio", "language_id": "typescript" }
  }
}
```

字段说明：

- `schema_version`：整数，当前为 `1`。
- `extension_map`：对象，key 为**不带点**的扩展名（建议统一小写，例如 `rs`、`py`）。
  - `command`：LSP 可执行文件（如 `rust-analyzer`、`pylsp`）。可为绝对路径或依赖 `PATH`。
  - `args`：可选，字符串（与现有环境变量 args 行为一致：以空白分隔；MVP 先不处理复杂 shell quoting）。
  - `language_id`：可选但推荐填写，用于 LSP `initialize` 的 `languageId`（例如 `rust`、`python`、`typescript`）。

### 兼容更简写的值（可选增强）

为了让配置更贴近“扩展名 → 可执行程序”的直觉写法，可以允许：

```json
{
  "schema_version": 1,
  "extension_map": {
    "rs": "rust-analyzer",
    "py": "pylsp"
  }
}
```

此时：

- `command = "<string>"`
- `args = ""`
- `language_id`：由内置扩展名推断（见下文），推断失败则不启用 LSP（或要求用户显式提供）。

> 是否支持简写取决于实现复杂度；MVP 可先只支持对象形式。

### “禁用某个扩展名的默认 LSP”（可选增强）

如果希望用户能显式关闭内置默认（例如不想对 `.rs` 启用 LSP），可以允许：

```json
{
  "schema_version": 1,
  "extension_map": {
    "rs": null
  }
}
```

语义：对 `rs` 明确禁用（即使内置默认存在）。

---

## 语言 ID 推断策略（language_id）

LSP 初始化需要 `languageId`。MVP 建议：

1. 配置里显式提供 `language_id`（最可靠）。
2. 若未提供，则按扩展名进行最小推断（内置表），例如：
   - `rs -> rust`
   - `py -> python`
   - `js -> javascript`
   - `ts -> typescript`
   - `go -> go`
3. 推断失败时：
   - 保守策略：不启动 LSP（并记录日志提示用户补充 `language_id`）。

---

## 启动时机与回退逻辑

### 启动时机

- 在 “打开文件 / 新建 tab 并构建 EditCore” 的路径中决定是否启用 LSP。
- 以当前实现为基准：在语法支持配置函数中（目前只对 `.rs` 分支启用 LSP）改为：
  1) 查 `servers.json` 映射  
  2) 命中则尝试启用 LSP  
  3) 成功则关闭其它语法引擎（保持 “LSP 优先”）  
  4) 失败则继续尝试 Tree-sitter，再尝试 Sublime syntax

### 回退逻辑（必须）

- LSP 启用失败（命令不存在、初始化失败等）：
  - 不阻塞 UI
  - 不报错弹窗（除非已有同类策略）；仅日志 + 状态栏提示（可选）
  - 继续走 Tree-sitter / Sublime fallback

---

## 优先级与兼容性

为了不破坏现有开发/调试方式，建议优先级如下：

1. **禁用开关**：`ATTO_EDITOR_DISABLE_LSP=1` / `EDITOR_CORE_APPKIT_DISABLE_LSP=1`（保持现有逻辑）
2. **按扩展名 JSON 映射**：`servers.json` 中命中的条目
3. **现有 Rust-only 环境变量覆写**（保持兼容）：
   - `ATTO_EDITOR_LSP_CMD` / `EDITOR_CORE_APPKIT_LSP_CMD`
   - `ATTO_EDITOR_LSP_ARGS` / `EDITOR_CORE_APPKIT_LSP_ARGS`
4. **内置默认**：`rs -> rust-analyzer`

> 第 3 点只在 `.rs` 且未命中 JSON（或 JSON 未提供）时生效，可以最大化保持“旧行为不变”。

---

## 代码落地步骤（计划）

### 1) 新增配置解析与路径解析模块（Swift）

- 新增一个小而独立的配置模块（建议文件名）：
  - `swift/Sources/AttoEditor/AttoLspRegistry.swift`
- 职责：
  - 解析 `servers.json`
  - 规范化扩展名 key（去掉点、转小写）
  - 提供 `lookup(extension:) -> LspLaunchSpec?`
  - 处理错误：返回 `nil` + 记录日志，不抛到 UI 层
- 参考现有落盘/解析模式：
  - `AttoSessionStore`（json 编解码、路径约定）
  - `AttoTreeSitterRegistry`（用户覆盖文件存在则优先、否则默认）

### 2) 接入打开文件的语法链路

- 修改 `configureSyntaxSupport(for:editCore:)`（当前 Rust-only 分支）：
  - 从“仅 `.rs` 才看 env 并启动 `rust-analyzer`”改为：
    - 任意扩展名：查 `AttoLspRegistry`
    - 命中则调用 `editCore.editor.lspEnable(...)`
  - 语言 id 来自 `language_id` 或推断
  - rootURI 继续使用现有 `workspaceRootURL.absoluteString`

### 3) 状态栏与可观测性（可选但建议）

- 状态栏当前只对 Rust 显示更友好（MVP 逻辑注释里也写了 “Rust-only”）。
- 调整为对任意 LSP：
  - 显示 `LSP: on/off` + 服务器名字（若可取到 `command` 的 basename）
  - 当配置 JSON 无效时：只在日志里提示，不污染 UI（或轻量状态提示一次）

### 4) 测试策略（建议）

优先写**纯解析测试**，避免需要真实启动 LSP 进程：

- `servers.json` 解析：
  - 正常对象形式
  - key 大小写/带点输入的兼容（若支持）
  - 无效 JSON（应安全返回默认/空）
  - schema_version 不匹配（应忽略）
- 路径解析：
  - 使用可注入的 `FileManager` 或临时目录（与 `AttoSessionStore` 类似）

### 5) 用户文档（后续）

在 `swift/README.md` 或专门的 AttoEditor 文档中追加：

- 配置文件路径
- 示例 `servers.json`
- 常见 server 命令（例如 `pylsp`、`gopls`、`typescript-language-server --stdio`）

---

## 验收标准（Definition of Done）

1. 不创建 `servers.json`：
   - 打开 `.rs` 仍会尝试启动 `rust-analyzer`（与当前一致）。
2. 创建 `servers.json` 并配置：
   - 打开对应扩展名文件时会尝试启动配置的 LSP。
3. LSP 启动失败：
   - 不崩溃、不卡 UI，且能回退到 Tree-sitter / Sublime（与当前链路一致）。
4. 配置文件 JSON 损坏：
   - 忽略并回退到默认行为（只在日志记录）。

