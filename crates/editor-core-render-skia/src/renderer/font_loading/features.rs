use super::*;

pub(in crate::renderer) fn make_shaper_feature(tag: FourByteTag, value: u32) -> Feature {
    Feature {
        tag: *tag,
        value,
        start: 0,
        end: usize::MAX,
    }
}

/// Parse a HarfBuzz-style OpenType feature string into shaper features.
///
/// Tokens are separated by whitespace and/or commas. Each token is one of:
/// - `liga` or `+liga` — enable with value 1
/// - `-calt` — explicitly disable (value 0)
/// - `ss01=3` — enable with an explicit value
///
/// Malformed tokens (bad tag length, non-ASCII, bad value) are silently skipped so a
/// typo in configuration cannot break rendering.
pub(in crate::renderer) fn parse_shaper_features(spec: &str) -> Vec<Feature> {
    let mut out = Vec::new();
    for token in spec.split(|c: char| c == ',' || c.is_whitespace()) {
        if token.is_empty() {
            continue;
        }
        let (tag_str, value) = if let Some(rest) = token.strip_prefix('+') {
            (rest, 1)
        } else if let Some(rest) = token.strip_prefix('-') {
            (rest, 0)
        } else if let Some((tag, value)) = token.split_once('=') {
            match value.parse::<u32>() {
                Ok(v) => (tag, v),
                Err(_) => continue,
            }
        } else {
            (token, 1)
        };

        let bytes = tag_str.as_bytes();
        if bytes.len() != 4 || !bytes.is_ascii() {
            continue;
        }
        let tag = FourByteTag::from_chars(
            bytes[0] as char,
            bytes[1] as char,
            bytes[2] as char,
            bytes[3] as char,
        );
        out.push(make_shaper_feature(tag, value));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(features: &[Feature]) -> Vec<(u32, u32)> {
        features.iter().map(|f| (f.tag, f.value)).collect()
    }

    #[test]
    fn parses_enable_disable_and_explicit_values() {
        let f = parse_shaper_features("-calt +liga ss01 ss02=3");
        assert_eq!(f.len(), 4);
        let tags = tags(&f);
        assert_eq!(tags[0].0, u32::from_be_bytes(*b"calt"));
        assert_eq!(tags[0].1, 0);
        assert_eq!(tags[1].0, u32::from_be_bytes(*b"liga"));
        assert_eq!(tags[1].1, 1);
        assert_eq!(tags[2].0, u32::from_be_bytes(*b"ss01"));
        assert_eq!(tags[2].1, 1);
        assert_eq!(tags[3].0, u32::from_be_bytes(*b"ss02"));
        assert_eq!(tags[3].1, 3);
    }

    #[test]
    fn accepts_comma_and_whitespace_separators() {
        let f = parse_shaper_features("liga, calt\tclig\nss10");
        assert_eq!(f.len(), 4);
    }

    #[test]
    fn skips_malformed_tokens() {
        let f = parse_shaper_features("liga toolongtag ab=xy =1 '' ss01");
        let tags = tags(&f);
        assert_eq!(tags.len(), 2);
        assert_eq!(tags[0].0, u32::from_be_bytes(*b"liga"));
        assert_eq!(tags[1].0, u32::from_be_bytes(*b"ss01"));
    }

    #[test]
    fn empty_spec_yields_no_features() {
        assert!(parse_shaper_features("").is_empty());
        assert!(parse_shaper_features("  , ,  ").is_empty());
    }
}
