mod navigation;
mod query;

use super::*;

#[allow(unused_imports)]
pub use navigation::*;
#[allow(unused_imports)]
pub use query::*;

fn ffi_search_options(case_sensitive: u8, whole_word: u8, regex: u8) -> editor_core::SearchOptions {
    editor_core::SearchOptions {
        case_sensitive: case_sensitive != 0,
        whole_word: whole_word != 0,
        regex: regex != 0,
    }
}
