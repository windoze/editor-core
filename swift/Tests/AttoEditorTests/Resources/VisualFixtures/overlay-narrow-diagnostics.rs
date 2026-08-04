alpha overlay marker alpha overlay marker

fn narrow_panel_state(value: i32) -> String {
    let mut status = String::new();
    for index in 0..value {
        if index % 2 == 0 {
            status.push_str("even-overlay ");
        } else {
            status.push_str("odd-overlay ");
        }
    }
    status
}

// Diagnostics and collapsed folds should remain legible in a narrow window.
// The minimap should keep markers visible while the editor chrome stays aligned.
