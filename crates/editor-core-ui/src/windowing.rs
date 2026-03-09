use thiserror::Error;

#[derive(Debug, Error)]
pub enum WindowingError {
    #[error("RGBA source length must be a multiple of 4 bytes")]
    InvalidSourceLen,
    #[error("pixel count mismatch: src={src_pixels} dst={dst_pixels}")]
    PixelCountMismatch {
        src_pixels: usize,
        dst_pixels: usize,
    },
}

/// Convert an RGBA8888 byte buffer (`[r, g, b, a, ...]`) into a `u32` ARGB buffer (`0xAARRGGBB`).
///
/// This is a small helper for windowing “shells” that want to present `EditorUi`’s CPU RGBA output
/// via APIs like `softbuffer` (which commonly take `u32` pixels).
pub fn rgba8_to_argb_u32(src_rgba: &[u8], dst_argb: &mut [u32]) -> Result<(), WindowingError> {
    if !src_rgba.len().is_multiple_of(4) {
        return Err(WindowingError::InvalidSourceLen);
    }
    let src_pixels = src_rgba.len() / 4;
    if dst_argb.len() != src_pixels {
        return Err(WindowingError::PixelCountMismatch {
            src_pixels,
            dst_pixels: dst_argb.len(),
        });
    }

    for (i, px) in dst_argb.iter_mut().enumerate() {
        let base = i * 4;
        let r = src_rgba[base] as u32;
        let g = src_rgba[base + 1] as u32;
        let b = src_rgba[base + 2] as u32;
        let a = src_rgba[base + 3] as u32;
        *px = (a << 24) | (r << 16) | (g << 8) | b;
    }

    Ok(())
}
