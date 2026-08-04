use editor_core_lsp::{LspClient, LspDocument, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::io;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::Duration;

fn framed_message_script(body: &str) -> String {
    format!(
        "body='{}'; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"",
        body
    )
}

fn spawn_shell_child(script: &str) -> io::Result<Child> {
    Command::new("/bin/sh")
        .arg("-c")
        .arg(script)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
}

fn shell_command(script: &str) -> Command {
    let mut cmd = Command::new("/bin/sh");
    cmd.arg("-c").arg(script).stderr(Stdio::null());
    cmd
}

fn shell_command_with_piped_stderr(script: &str) -> Command {
    let mut cmd = Command::new("/bin/sh");
    cmd.arg("-c").arg(script).stderr(Stdio::piped());
    cmd
}

fn process_exists(pid: u32) -> bool {
    let output = Command::new("ps")
        .arg("-p")
        .arg(pid.to_string())
        .arg("-o")
        .arg("pid=")
        .output();

    let Ok(output) = output else {
        return false;
    };

    output.status.success() && !String::from_utf8_lossy(&output.stdout).trim().is_empty()
}

fn assert_process_exited(pid: u32) {
    for _ in 0..50 {
        if !process_exists(pid) {
            return;
        }
        thread::sleep(Duration::from_millis(20));
    }

    panic!("process {pid} still exists");
}

fn start_session(script: &str) -> LspSession {
    LspSession::start(LspSessionStartOptions {
        cmd: shell_command(script),
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: "file:///tmp/lifecycle-test.rs".to_string(),
            language_id: "rust".to_string(),
            version: 1,
        },
        initial_text: String::new(),
    })
    .expect("session starts")
}

fn start_session_with_cmd(cmd: Command) -> LspSession {
    LspSession::start(LspSessionStartOptions {
        cmd,
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: "file:///tmp/lifecycle-test.rs".to_string(),
            language_id: "rust".to_string(),
            version: 1,
        },
        initial_text: String::new(),
    })
    .expect("session starts")
}

#[test]
fn drop_kills_unresponsive_lsp_client() {
    let child = spawn_shell_child("sleep 30").expect("spawn fake server");
    let pid = child.id();

    {
        let _client = LspClient::from_child(child, Vec::new()).expect("create client");
    }

    assert_process_exited(pid);
}

#[test]
fn session_exit_kills_server_that_ignores_shutdown() {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let script = format!("{initialize}; sleep 30");
    let mut session = start_session(&script);
    let pid = session.client().process_id();

    session.exit().expect("exit recovers by killing server");

    assert_process_exited(pid);
}

#[test]
fn session_exit_accepts_responsive_shutdown() {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let shutdown = framed_message_script(r#"{"jsonrpc":"2.0","id":2,"result":null}"#);
    let script = format!("{initialize}; sleep 0.05; {shutdown}; sleep 0.05");
    let mut session = start_session(&script);
    let pid = session.client().process_id();

    session.exit().expect("responsive shutdown succeeds");

    assert_process_exited(pid);
}

#[test]
fn session_status_reports_exited_server_process() {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let script = format!("{initialize}; sleep 0.05; exit 7");
    let mut session = start_session(&script);

    for _ in 0..50 {
        session.refresh_process_status().unwrap();
        if session.status().process.state == editor_core_lsp::LspProcessState::Exited {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }

    let status = session.status();
    assert_eq!(
        status.process.state,
        editor_core_lsp::LspProcessState::Exited
    );
    assert_eq!(status.process.exit_code, Some(7));
}

#[test]
fn session_status_reports_stderr_tail() {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let script = format!("printf 'first warning\\nsecond warning\\n' >&2; {initialize}; sleep 30");
    let session = start_session_with_cmd(shell_command_with_piped_stderr(&script));

    for _ in 0..50 {
        if session
            .status()
            .process
            .stderr_tail
            .as_deref()
            .is_some_and(|tail| tail.contains("second warning"))
        {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }

    let status = session.status();
    let stderr_tail = status
        .process
        .stderr_tail
        .expect("expected stderr tail in process status");
    assert!(stderr_tail.contains("first warning"), "{stderr_tail}");
    assert!(stderr_tail.contains("second warning"), "{stderr_tail}");
}
