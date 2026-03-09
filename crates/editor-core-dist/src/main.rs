use editor_core_dist::{FfiDistOptions, LinkMode, package_ffi_dist};
use std::path::PathBuf;

fn usage() -> &'static str {
    r#"editor-core-dist

Usage:
  editor-core-dist ffi [--out DIR] [--profile debug|release] [--target TRIPLE] [--mode static|dynamic|both]
                     [--core-only|--ui-only] [--no-overwrite] [--repo PATH]

Notes:
  - This tool only packages *already built* artifacts (Cargo build output + headers).
  - Run `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release` first.
"#
}

fn main() {
    if let Err(err) = try_main() {
        eprintln!("error: {err}");
        eprintln!();
        eprintln!("{}", usage());
        std::process::exit(2);
    }
}

fn try_main() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let Some(cmd) = args.next() else {
        return Err("missing subcommand".to_string());
    };

    match cmd.as_str() {
        "ffi" => {
            let mut out_dir: Option<PathBuf> = None;
            let mut profile: Option<String> = None;
            let mut target: Option<String> = None;
            let mut mode: Option<LinkMode> = None;
            let mut include_core = true;
            let mut include_ui = true;
            let mut overwrite = true;
            let mut repo_root: Option<PathBuf> = None;

            while let Some(arg) = args.next() {
                match arg.as_str() {
                    "--out" => {
                        let v = args.next().ok_or_else(|| "--out requires a value".to_string())?;
                        out_dir = Some(PathBuf::from(v));
                    }
                    "--profile" => {
                        profile = Some(args.next().ok_or_else(|| "--profile requires a value".to_string())?);
                    }
                    "--target" => {
                        target = Some(args.next().ok_or_else(|| "--target requires a value".to_string())?);
                    }
                    "--mode" => {
                        let v = args.next().ok_or_else(|| "--mode requires a value".to_string())?;
                        mode = Some(LinkMode::parse(&v).map_err(|e| e.to_string())?);
                    }
                    "--core-only" => {
                        include_core = true;
                        include_ui = false;
                    }
                    "--ui-only" => {
                        include_core = false;
                        include_ui = true;
                    }
                    "--no-overwrite" => {
                        overwrite = false;
                    }
                    "--repo" => {
                        let v = args.next().ok_or_else(|| "--repo requires a value".to_string())?;
                        repo_root = Some(PathBuf::from(v));
                    }
                    "--help" | "-h" => {
                        println!("{}", usage());
                        return Ok(());
                    }
                    other => {
                        return Err(format!("unknown argument: {other}"));
                    }
                }
            }

            let repo_root = repo_root.unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
            let mut opts = FfiDistOptions::for_repo_root(repo_root);
            if let Some(out) = out_dir {
                opts.out_dir = out;
            }
            if let Some(profile) = profile {
                opts.profile = profile;
            }
            if let Some(target) = target {
                opts.target_triple = target;
            }
            if let Some(mode) = mode {
                opts.mode = mode;
            }
            opts.include_core = include_core;
            opts.include_ui = include_ui;
            opts.overwrite = overwrite;

            let manifest = package_ffi_dist(&opts).map_err(|e| e.to_string())?;
            println!(
                "packaged {} entries to {}/{}/{}",
                manifest.entries.len(),
                opts.out_dir.display(),
                opts.target_triple,
                opts.profile
            );
            Ok(())
        }
        other => Err(format!("unknown subcommand: {other}")),
    }
}

