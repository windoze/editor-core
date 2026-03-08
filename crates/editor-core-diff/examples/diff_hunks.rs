use editor_core_diff::{diff_line_hunks, LineDiffConfig};

fn main() {
    let before = "fn main() {\n    println!(\"hello\")\n}\n";
    let after = "fn main() {\n    println!(\"hello\");\n    println!(\"world\");\n}\n";

    let mut cfg = LineDiffConfig::default();
    cfg.context_lines = 2;

    let hunks = diff_line_hunks(before, after, cfg);
    for h in hunks {
        println!(
            "@@ -{},{} +{},{} @@",
            h.before.start + 1,
            h.before.len(),
            h.after.start + 1,
            h.after.len()
        );
        for line in h.lines {
            let prefix = match line.kind {
                editor_core_diff::DiffLineKind::Context => ' ',
                editor_core_diff::DiffLineKind::Add => '+',
                editor_core_diff::DiffLineKind::Remove => '-',
            };
            print!("{prefix}{}", line.text);
        }
    }
}

