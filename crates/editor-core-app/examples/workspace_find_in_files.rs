use editor_core::SearchOptions;
use editor_core_app::{FindInFilesConfig, find_in_files};
use std::path::PathBuf;

fn main() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let root = args
        .next()
        .ok_or_else(|| "usage: workspace_find_in_files <root> <query>".to_string())?;
    let query = args
        .next()
        .ok_or_else(|| "usage: workspace_find_in_files <root> <query>".to_string())?;

    let root = PathBuf::from(root);
    let results = find_in_files(
        &root,
        &query,
        SearchOptions::default(),
        FindInFilesConfig::default(),
    )
    .map_err(|e| e.to_string())?;

    for file in results {
        let path = file.path.to_string_lossy();
        for m in file.matches {
            println!("{path}:{}:{}", m.line + 1, m.text);
        }
    }

    Ok(())
}
