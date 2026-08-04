mod defaults;
mod factory;
mod fallback;
mod features;
mod normalize;

pub(crate) use normalize::normalize_font_family_name;

pub(in crate::renderer) use defaults::default_font_families;
pub(in crate::renderer) use factory::load_fonts_from_families_with_style;
pub(in crate::renderer) use features::make_shaper_feature;

#[cfg(test)]
pub(crate) use factory::make_configured_font;

use super::*;
