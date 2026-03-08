use editor_core_ui::{
    dispatch_command_to_editor_ui, EditorUi, Key, KeyStroke, KeybindingResolver,
    KeybindingResolverResult, KeybindingWhen, Keymap, KeybindingContext, Modifiers, Platform,
    ResolvedCommand,
};
use serde_json::json;

#[test]
fn keymap_parses_primary_modifier_per_platform() {
    let json = r#"[{ "keys": "primary+z", "command": "editor.undo" }]"#;

    let km_mac = Keymap::from_json_str(json, Platform::MacOS).unwrap();
    let mods_mac = km_mac.bindings()[0].sequence[0].modifiers;
    assert!(mods_mac.contains(Modifiers::META));
    assert!(!mods_mac.contains(Modifiers::CTRL));

    let km_win = Keymap::from_json_str(json, Platform::Windows).unwrap();
    let mods_win = km_win.bindings()[0].sequence[0].modifiers;
    assert!(mods_win.contains(Modifiers::CTRL));
    assert!(!mods_win.contains(Modifiers::META));
}

#[test]
fn when_clause_parses_and_evaluates() {
    let when = KeybindingWhen::parse("editorFocus && !inPalette").unwrap();

    let ctx_ok = KeybindingContext::new(Platform::Linux)
        .with("editorFocus", true)
        .with("inPalette", false);
    assert!(when.eval(&ctx_ok));

    let ctx_bad = KeybindingContext::new(Platform::Linux)
        .with("editorFocus", true)
        .with("inPalette", true);
    assert!(!when.eval(&ctx_bad));
}

#[test]
fn resolver_supports_chords_and_resets_state() {
    let platform = Platform::Linux;
    let keymap = Keymap::from_json_str(include_str!("fixtures/keymap_basic.json"), platform).unwrap();
    let mut resolver = KeybindingResolver::new(platform, keymap);

    let ctx = KeybindingContext::new(platform)
        .with("editorFocus", true)
        .with("inPalette", false);

    let r1 = resolver.resolve(KeyStroke::new(Key::Char('k'), Modifiers::CTRL), &ctx);
    assert_eq!(r1, KeybindingResolverResult::PendingChord);
    assert_eq!(resolver.pending_sequence().len(), 1);

    let r2 = resolver.resolve(KeyStroke::new(Key::Char('c'), Modifiers::CTRL), &ctx);
    let KeybindingResolverResult::Matched(cmd) = r2 else {
        panic!("expected chord match, got {r2:?}");
    };
    assert_eq!(cmd.id, "editor.commentLine");
    assert!(resolver.pending_sequence().is_empty());
}

#[test]
fn resolver_respects_when_clause_for_prefix_matching() {
    let platform = Platform::Linux;
    let keymap = Keymap::from_json_str(include_str!("fixtures/keymap_basic.json"), platform).unwrap();
    let mut resolver = KeybindingResolver::new(platform, keymap);

    // Same key sequence as the chord bindings, but `when` is false here.
    let ctx = KeybindingContext::new(platform)
        .with("editorFocus", true)
        .with("inPalette", true);

    let r1 = resolver.resolve(KeyStroke::new(Key::Char('k'), Modifiers::CTRL), &ctx);
    assert_eq!(r1, KeybindingResolverResult::NotHandled);
    assert!(resolver.pending_sequence().is_empty());
}

#[test]
fn dispatch_runs_editor_ui_commands() {
    let mut ui = EditorUi::new("ab", 80);
    ui.move_to_document_end().unwrap();

    let backspace = ResolvedCommand {
        id: "editor.deleteBackward".to_string(),
        args: None,
    };
    assert!(dispatch_command_to_editor_ui(&mut ui, &backspace).unwrap());
    assert_eq!(ui.text(), "a");

    let select_all = ResolvedCommand {
        id: "editor.selectAll".to_string(),
        args: None,
    };
    assert!(dispatch_command_to_editor_ui(&mut ui, &select_all).unwrap());
    let (ranges, primary) = ui.selections_offsets();
    assert_eq!(primary, 0);
    assert_eq!(ranges, vec![(0, 1)]);

    let insert = ResolvedCommand {
        id: "editor.commitText".to_string(),
        args: Some(json!({"text": "Z"})),
    };
    assert!(dispatch_command_to_editor_ui(&mut ui, &insert).unwrap());
    assert_eq!(ui.text(), "Z");
}

