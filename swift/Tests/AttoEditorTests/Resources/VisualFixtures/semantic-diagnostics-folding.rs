fn render_widget(input: i32) -> String {
    let status = compute_status(input);
    if status.is_empty() {
        return "empty";
    }
    status
}

fn compute_status(input: i32) -> String {
    format!("status-{input}")
}
