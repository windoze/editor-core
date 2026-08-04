mod draw;
mod resolve;
mod run;

pub(super) use draw::draw_decoration_run;
pub(super) use resolve::resolve_cell_line_decorations;
pub(super) use run::{
    LineDecorationKind, LineDecorationRun, extend_decoration_run, flush_decoration_run,
};
