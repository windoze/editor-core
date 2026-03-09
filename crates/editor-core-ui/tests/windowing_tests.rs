use editor_core_ui::{WindowingError, rgba8_to_argb_u32};

#[test]
fn rgba8_to_argb_u32_converts_pixels() {
    let src: Vec<u8> = vec![
        1, 2, 3, 4, // aarrggbb => 0x04010203
        255, 0, 128, 64, // aarrggbb => 0x40FF0080
    ];
    let mut dst = vec![0u32; 2];

    rgba8_to_argb_u32(&src, &mut dst).unwrap();
    assert_eq!(dst[0], 0x0401_0203);
    assert_eq!(dst[1], 0x40FF_0080);
}

#[test]
fn rgba8_to_argb_u32_rejects_invalid_lengths() {
    let mut dst = vec![0u32; 1];
    let err = rgba8_to_argb_u32(&[1, 2, 3], &mut dst).unwrap_err();
    assert!(matches!(err, WindowingError::InvalidSourceLen));

    let err = rgba8_to_argb_u32(&[1, 2, 3, 4], &mut []).unwrap_err();
    assert!(matches!(err, WindowingError::PixelCountMismatch { .. }));
}
