pub(crate) fn split_lines_preserve_trailing(text: &str) -> Vec<String> {
    // `str::split('\n')` preserves trailing empty segments, which matches typical editor
    // line semantics (N newlines => N+1 lines), and keeps behavior consistent with Rope.
    text.split('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line).to_string())
        .collect()
}
