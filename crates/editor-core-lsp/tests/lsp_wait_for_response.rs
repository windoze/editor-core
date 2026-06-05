use editor_core::LineIndex;
use editor_core_lsp::{LspClient, LspDocument, LspInbound, LspSession, LspSessionStartOptions};
use serde_json::{Value, json};
use std::io;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

fn framed_message_script(body: &str) -> String {
    format!(
        "body='{}'; printf 'Content-Length: %s\r\n\r\n%s' \"${{#body}}\" \"$body\"",
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

fn client_for_script(script: &str) -> LspClient {
    let child = spawn_shell_child(script).expect("spawn fake server");
    LspClient::from_child(child, Vec::new()).expect("create client")
}

fn session_for_script(script: &str) -> LspSession {
    LspSession::start(LspSessionStartOptions {
        cmd: shell_command(script),
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: "file:///tmp/lsp-wait-test.rs".to_string(),
            language_id: "rust".to_string(),
            version: 1,
        },
        initial_text: "abc\n".to_string(),
    })
    .expect("session starts")
}

fn next_message(client: &LspClient) -> Value {
    match client.try_recv().expect("deferred inbound message") {
        LspInbound::Message(msg) => msg,
        LspInbound::IoError(err) => panic!("unexpected LSP I/O error: {err}"),
    }
}

#[test]
fn wait_for_response_preserves_other_pending_responses() {
    let response_two = framed_message_script(r#"{"jsonrpc":"2.0","id":2,"result":{"value":2}}"#);
    let response_one = framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"value":1}}"#);
    let script = format!("{response_two}; {response_one}; sleep 0.05");
    let mut client = client_for_script(&script);

    let response = client
        .wait_for_response(1, Duration::from_secs(1))
        .expect("wait for requested response");

    assert_eq!(response.get("id").and_then(Value::as_u64), Some(1));
    assert_eq!(response["result"]["value"].as_u64(), Some(1));

    let deferred = next_message(&client);
    assert_eq!(deferred.get("id").and_then(Value::as_u64), Some(2));
    assert_eq!(deferred["result"]["value"].as_u64(), Some(2));
}

#[test]
fn wait_for_response_replies_to_server_request_before_target_response() {
    let server_request = framed_message_script(
        r#"{"jsonrpc":"2.0","id":99,"method":"workspace/configuration","params":{"items":[{},{}]}}"#,
    );
    let response_one =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"unblocked":true}}"#);
    let script = format!(
        "{server_request}; IFS= read -r header; case \"$header\" in Content-Length:*) ;; *) exit 1;; esac; {response_one}; sleep 0.05"
    );
    let mut client = client_for_script(&script);

    let response = client
        .wait_for_response(1, Duration::from_secs(1))
        .expect("server request response unblocks fake server");

    assert_eq!(response.get("id").and_then(Value::as_u64), Some(1));
    assert_eq!(response["result"]["unblocked"].as_bool(), Some(true));
}

#[test]
fn wait_for_response_preserves_notifications() {
    let notification = framed_message_script(
        r#"{"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3,"message":"hello"}}"#,
    );
    let response_one = framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":null}"#);
    let script = format!("{notification}; {response_one}; sleep 0.05");
    let mut client = client_for_script(&script);

    client
        .wait_for_response(1, Duration::from_secs(1))
        .expect("wait for requested response");

    let deferred = next_message(&client);
    assert_eq!(
        deferred.get("method").and_then(Value::as_str),
        Some("window/logMessage")
    );
    assert_eq!(deferred["params"]["message"].as_str(), Some("hello"));
}

#[test]
fn wait_for_response_preserves_malformed_response_ids() {
    let malformed =
        framed_message_script(r#"{"jsonrpc":"2.0","id":"not-a-number","result":{"value":2}}"#);
    let response_one = framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":null}"#);
    let script = format!("{malformed}; {response_one}; sleep 0.05");
    let mut client = client_for_script(&script);

    client
        .wait_for_response(1, Duration::from_secs(1))
        .expect("wait for requested response");

    let deferred = next_message(&client);
    assert_eq!(
        deferred.get("id").and_then(Value::as_str),
        Some("not-a-number")
    );
    assert_eq!(deferred["result"]["value"].as_u64(), Some(2));
}

#[test]
fn wait_for_response_keeps_malformed_requests_observable_to_session_poll() {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let malformed = framed_message_script(
        r#"{"jsonrpc":"2.0","id":"bad-request","method":"workspace/configuration","params":{"items":[]}}"#,
    );
    let response_two = framed_message_script(r#"{"jsonrpc":"2.0","id":2,"result":null}"#);
    let script = format!("{initialize}; sleep 0.05; {malformed}; {response_two}; sleep 30");
    let mut session = session_for_script(&script);
    let line_index = LineIndex::from_text("abc\n");

    let request_id = session
        .client_mut()
        .request("workspace/symbol", json!({}))
        .expect("send explicit request");
    assert_eq!(request_id, 2);
    session
        .wait_for_response(request_id, Duration::from_secs(1))
        .expect("wait for requested response");

    let mut unhandled = Vec::new();
    session
        .poll_edits_with_line_index_and_handler(&line_index, |msg| unhandled.push(msg))
        .expect("poll succeeds");

    assert_eq!(unhandled.len(), 1);
    assert_eq!(
        unhandled[0].get("id").and_then(Value::as_str),
        Some("bad-request")
    );
    assert_eq!(
        unhandled[0].get("method").and_then(Value::as_str),
        Some("workspace/configuration")
    );
}
