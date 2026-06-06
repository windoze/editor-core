//! Headless diff-view primitives for `editor-core` integrations.
//!
//! This crate is intentionally pure headless infrastructure: it contains no
//! rendering, scrolling, splitter, pixel, or font logic. It follows the v1
//! staging in the workspace [`PLAN.md`](../../../PLAN.md).

pub mod model;
pub mod projection;
pub mod style;
pub mod view;

pub use model::{AlignUnit, DiffModel, SideDoc};
pub use projection::{DiffMode, DiffProjection, Gutter, Row, RowSlot};
pub use view::DiffColumnView;
