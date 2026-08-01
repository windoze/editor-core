use super::*;

pub(crate) fn damage_rect_for_row_range(
    start_row: usize,
    end_row: usize,
    config: RenderConfig,
) -> Option<DamageRect> {
    if start_row >= end_row {
        return None;
    }

    let y0 = config.padding_y_px + start_row as f32 * config.line_height_px - config.scroll_y_px;
    let y1 = config.padding_y_px + end_row as f32 * config.line_height_px - config.scroll_y_px;
    if !y0.is_finite() || !y1.is_finite() {
        return None;
    }

    let mut y0i = y0.floor() as i64;
    let mut y1i = y1.ceil() as i64;

    let h_total = config.height_px as i64;
    y0i = y0i.clamp(0, h_total);
    y1i = y1i.clamp(0, h_total);
    if y1i <= y0i {
        return None;
    }

    Some(DamageRect {
        x: 0,
        y: y0i as u32,
        width: config.width_px,
        height: (y1i - y0i) as u32,
    })
}

pub(crate) fn dirty_row_ranges(prev: &[u64], next: &[u64]) -> Vec<(usize, usize)> {
    if prev.len() != next.len() {
        if next.is_empty() {
            return Vec::new();
        }
        return vec![(0, next.len())];
    }

    let mut ranges: Vec<(usize, usize)> = Vec::new();
    let mut start: Option<usize> = None;

    for i in 0..next.len() {
        let dirty = prev[i] != next[i];
        match (dirty, start) {
            (true, None) => start = Some(i),
            (false, Some(s)) => {
                ranges.push((s, i));
                start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = start {
        ranges.push((s, next.len()));
    }
    ranges
}
