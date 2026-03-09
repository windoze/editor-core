use editor_core_app::WorkspaceFileIndex;
use std::path::PathBuf;

fn main() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let root = args
        .next()
        .ok_or_else(|| "usage: workspace_file_index <root> [query]".to_string())?;
    let query = args.next().unwrap_or_default();

    let mut index = WorkspaceFileIndex::new(PathBuf::from(root));
    let results = index
        .search(&query, 20)
        .map_err(|e| format!("index error: {e}"))?;

    for entry in results {
        println!("{}", entry.relative_path);
    }
    Ok(())
}

