//! Regression test for C-7: `EditorStateManager` must notify subscribers when a view-config
//! command mutates state, consistent with `ViewCommand::is_mutating` and the `Workspace` path.

use std::sync::{Arc, Mutex};

use editor_core::{
    AutoPairsConfig, Command, EditorStateManager, StateChangeType, TabKeyBehavior, ViewCommand,
};

fn recording_manager() -> (EditorStateManager, Arc<Mutex<Vec<StateChangeType>>>) {
    let mut state = EditorStateManager::new("hello world\n", 80);
    let log: Arc<Mutex<Vec<StateChangeType>>> = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&log);
    state.subscribe(move |change| {
        sink.lock().unwrap().push(change.change_type);
    });
    (state, log)
}

fn assert_notified(command: Command) {
    let (mut state, log) = recording_manager();
    state.execute(command).unwrap();
    let seen = log.lock().unwrap().clone();
    assert!(
        seen.contains(&StateChangeType::ViewportChanged),
        "expected a ViewportChanged notification for a view-config command, got {seen:?}"
    );
}

#[test]
fn set_tab_key_behavior_notifies_subscribers() {
    assert_notified(Command::View(ViewCommand::SetTabKeyBehavior {
        behavior: TabKeyBehavior::Spaces,
    }));
}

#[test]
fn set_auto_pairs_enabled_notifies_subscribers() {
    assert_notified(Command::View(ViewCommand::SetAutoPairsEnabled { enabled: true }));
}

#[test]
fn set_auto_pairs_config_notifies_subscribers() {
    assert_notified(Command::View(ViewCommand::SetAutoPairsConfig {
        config: AutoPairsConfig::default(),
    }));
}

#[test]
fn set_word_boundary_chars_notifies_subscribers() {
    assert_notified(Command::View(
        ViewCommand::SetWordBoundaryAsciiBoundaryChars {
            boundary_chars: ".".to_string(),
        },
    ));
}

#[test]
fn get_viewport_query_does_not_notify() {
    // A pure query must NOT produce a state-change notification.
    let (mut state, log) = recording_manager();
    let _ = state.execute(Command::View(ViewCommand::GetViewport {
        start_row: 0,
        count: 10,
    }));
    assert!(
        log.lock().unwrap().is_empty(),
        "GetViewport is a query and must not notify"
    );
}
