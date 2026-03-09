use editor_core_lang::LanguageRegistry;
use std::path::Path;

fn main() {
    let reg = LanguageRegistry::default();

    let path = Path::new("src/main.rs");
    let lang = reg.language_for_path(path).expect("language match");

    println!("{} → {}", path.display(), lang.display_name);
}

