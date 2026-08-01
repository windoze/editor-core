use super::*;

impl SkiaRenderer {
    pub fn required_rgba_len(config: RenderConfig) -> Result<usize, RenderError> {
        if config.width_px == 0 || config.height_px == 0 {
            return Err(RenderError::InvalidSize {
                width_px: config.width_px,
                height_px: config.height_px,
            });
        }
        (config.width_px as usize)
            .checked_mul(config.height_px as usize)
            .and_then(|v| v.checked_mul(4))
            .ok_or(RenderError::SizeOverflow {
                width_px: config.width_px,
                height_px: config.height_px,
            })
    }
}
