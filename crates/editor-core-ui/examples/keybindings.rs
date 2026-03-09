use editor_core_ui::{
    EditorUi, Key, KeyStroke, KeybindingContext, KeybindingResolver, KeybindingResolverResult,
    Keymap, Modifiers, Platform, dispatch_command_to_editor_ui,
};

fn main() {
    let platform = Platform::current();

    // 一个 VSCode-ish 的 keymap JSON（最小字段：`keys` + `command`）。
    // - `primary` 会在 macOS 映射到 Cmd，其他平台映射到 Ctrl
    // - 支持 chord（用空格分隔）：`Ctrl+K Ctrl+C`
    let keymap_json = r#"
    [
      { "keys": "primary+z", "command": "editor.undo", "when": "editorFocus" },
      { "keys": "primary+shift+z", "command": "editor.redo", "when": "editorFocus" },
      { "keys": "ctrl+k ctrl+c", "command": "editor.selectAll", "when": "editorFocus" }
    ]
    "#;

    let keymap = Keymap::from_json_str(keymap_json, platform).expect("parse keymap json");
    let mut resolver = KeybindingResolver::new(platform, keymap);

    let ctx = KeybindingContext::new(platform).with("editorFocus", true);

    let mut ui = EditorUi::new("Hello\nWorld\n", 80);
    ui.commit_text("!!!").expect("insert text");

    // 模拟按键：primary+z（undo）
    press(
        &mut resolver,
        &ctx,
        &mut ui,
        Key::Char('z'),
        Modifiers::primary(platform),
    );

    // 模拟 chord：Ctrl+K Ctrl+C（这里示例映射到 selectAll）
    press(
        &mut resolver,
        &ctx,
        &mut ui,
        Key::Char('k'),
        Modifiers::CTRL,
    );
    press(
        &mut resolver,
        &ctx,
        &mut ui,
        Key::Char('c'),
        Modifiers::CTRL,
    );

    println!("最终文本：\n{}", ui.text());
    let (sels, primary) = ui.selections_offsets();
    println!("选区：{sels:?}, primary={primary}");
}

fn press(
    resolver: &mut KeybindingResolver,
    ctx: &KeybindingContext,
    ui: &mut EditorUi,
    key: Key,
    modifiers: Modifiers,
) {
    let stroke = KeyStroke::new(key, modifiers);
    match resolver.resolve(stroke, ctx) {
        KeybindingResolverResult::Matched(cmd) => {
            let handled = dispatch_command_to_editor_ui(ui, &cmd).expect("dispatch command");
            println!("匹配命令：{} (handled={handled})", cmd.id);
        }
        KeybindingResolverResult::PendingChord => {
            println!("进入 chord，等待下一次按键…");
        }
        KeybindingResolverResult::NotHandled => {
            println!("无匹配 keybinding：{stroke:?}");
        }
    }
}
