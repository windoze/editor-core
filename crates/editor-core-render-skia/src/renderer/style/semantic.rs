pub(in crate::renderer) fn semantic_token_base_style_id(style_id: u32) -> Option<u32> {
    // All currently reserved/builtin style id ranges are >= 0x0300_0000.
    // The default LSP semantic encoding is: (token_type << 16) | (modifier_bits & 0xFFFF),
    // which lives in a low range (token_type is small).
    if style_id >= 0x0300_0000 {
        return None;
    }
    if (style_id & 0xFFFF) == 0 {
        return None;
    }
    Some(style_id & 0xFFFF_0000)
}

pub(in crate::renderer) fn is_lsp_diagnostics_style_id(style_id: u32) -> bool {
    // Matches `editor-core-lsp` encoding: 0x0400_0100 | severity(1..=4).
    const BASE: u32 = 0x0400_0100;
    if (style_id & 0xFFFF_FF00) != BASE {
        return false;
    }
    let sev = style_id & 0xFF;
    (1..=4).contains(&sev)
}
