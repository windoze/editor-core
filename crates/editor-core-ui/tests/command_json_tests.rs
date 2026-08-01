use editor_core_ui::EditorUi;
use serde_json::Value;

fn assert_success(ui: &mut EditorUi, command: &str) {
    let result = ui.execute_command_json(command).unwrap();
    let value: Value = serde_json::from_str(&result).unwrap();
    assert_eq!(value["kind"], "success");
}

#[test]
fn execute_command_json_runs_core_edit_view_style_and_snippet_commands() {
    let mut ui = EditorUi::new("a\nb\nc\n", 80);

    assert_success(
        &mut ui,
        r#"{"kind":"cursor","op":"move_to","line":1,"column":0}"#,
    );
    assert_success(&mut ui, r#"{"kind":"edit","op":"duplicate_lines"}"#);
    assert_eq!(ui.text(), "a\nb\nb\nc\n");

    assert_success(
        &mut ui,
        r#"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#,
    );
    assert_eq!(ui.text(), "a\nb\n// b\nc\n");

    assert_success(
        &mut ui,
        r#"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#,
    );
    assert_success(
        &mut ui,
        r#"{"kind":"style","op":"fold","start_line":0,"end_line":2}"#,
    );

    let viewport = ui
        .execute_command_json(r#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        .unwrap();
    let value: Value = serde_json::from_str(&viewport).unwrap();
    assert_eq!(value["kind"], "viewport");
    assert!(
        value["viewport"]["lines"]
            .as_array()
            .unwrap()
            .iter()
            .any(|line| line["is_fold_placeholder_appended"] == true)
    );

    let mut snippet_ui = EditorUi::new("", 80);
    assert_success(
        &mut snippet_ui,
        r#"{"kind":"edit","op":"apply_snippet","start":0,"end":0,"snippet":"println!(${1:msg})$0"}"#,
    );
    assert_eq!(snippet_ui.text(), "println!(msg)");
    assert!(snippet_ui.has_active_snippet_session().unwrap());
}

#[test]
fn execute_command_json_reports_parse_errors() {
    let mut ui = EditorUi::new("", 80);
    let err = ui
        .execute_command_json(r#"{"kind":"edit","op":"type_char","ch":"too long"}"#)
        .unwrap_err();
    assert!(err.to_string().contains("ch must be exactly one character"));
}
