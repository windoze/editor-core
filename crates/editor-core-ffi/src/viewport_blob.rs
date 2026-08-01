use super::*;

fn write_le_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_le_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

pub(crate) fn build_viewport_blob(grid: &HeadlessGrid) -> Result<Vec<u8>, (EcfStatus, String)> {
    let line_count = checked_u32(grid.lines.len(), "line_count")?;

    let mut line_records: Vec<EcfViewportLine> = Vec::with_capacity(grid.lines.len());
    let mut cell_records: Vec<EcfViewportCell> = Vec::new();
    let mut style_ids: Vec<u32> = Vec::new();

    for line in &grid.lines {
        let line_cell_start_index = checked_u32(cell_records.len(), "cell_start_index")?;
        let line_cell_count = checked_u32(line.cells.len(), "line_cell_count")?;

        for cell in &line.cells {
            let style_start_index = checked_u32(style_ids.len(), "style_start_index")?;
            let style_count = checked_u16(cell.styles.len(), "style_count")?;
            style_ids.extend(cell.styles.iter().copied());

            cell_records.push(EcfViewportCell {
                scalar_value: u32::from(cell.ch),
                width: checked_u16(cell.width, "cell width")?,
                style_count,
                style_start_index,
            });
        }

        line_records.push(EcfViewportLine {
            logical_line_index: checked_u32(line.logical_line_index, "logical_line_index")?,
            visual_in_logical: checked_u32(line.visual_in_logical, "visual_in_logical")?,
            char_offset_start: checked_u32(line.char_offset_start, "char_offset_start")?,
            char_offset_end: checked_u32(line.char_offset_end, "char_offset_end")?,
            cell_start_index: line_cell_start_index,
            cell_count: line_cell_count,
            segment_x_start_cells: checked_u16(
                line.segment_x_start_cells,
                "segment_x_start_cells",
            )?,
            is_wrapped_part: if line.is_wrapped_part { 1 } else { 0 },
            is_fold_placeholder_appended: if line.is_fold_placeholder_appended {
                1
            } else {
                0
            },
        });
    }

    let cell_count = checked_u32(cell_records.len(), "cell_count")?;
    let style_id_count = checked_u32(style_ids.len(), "style_id_count")?;

    let header_size = checked_u32(size_of::<EcfViewportBlobHeader>(), "header_size")?;
    let line_size = checked_u32(size_of::<EcfViewportLine>(), "line_size")?;
    let cell_size = checked_u32(size_of::<EcfViewportCell>(), "cell_size")?;

    let lines_bytes = line_count.checked_mul(line_size).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "line table size overflow".to_string(),
        )
    })?;
    let cells_bytes = cell_count.checked_mul(cell_size).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "cell table size overflow".to_string(),
        )
    })?;
    let styles_bytes = style_id_count.checked_mul(4).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "style table size overflow".to_string(),
        )
    })?;

    let lines_offset = header_size;
    let cells_offset = lines_offset
        .checked_add(lines_bytes)
        .ok_or_else(|| (EcfStatus::Unsupported, "cells_offset overflow".to_string()))?;
    let style_ids_offset = cells_offset.checked_add(cells_bytes).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "style_ids_offset overflow".to_string(),
        )
    })?;
    let total_len = style_ids_offset.checked_add(styles_bytes).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "blob total size overflow".to_string(),
        )
    })?;

    let total_len_usize = usize::try_from(total_len).map_err(|_| {
        (
            EcfStatus::Unsupported,
            "blob size exceeds addressable memory".to_string(),
        )
    })?;

    let mut out = Vec::<u8>::with_capacity(total_len_usize);

    let header = EcfViewportBlobHeader {
        abi_version: ECF_ABI_VERSION,
        header_size,
        line_count,
        cell_count,
        style_id_count,
        lines_offset,
        cells_offset,
        style_ids_offset,
        reserved: 0,
    };

    write_le_u32(&mut out, header.abi_version);
    write_le_u32(&mut out, header.header_size);
    write_le_u32(&mut out, header.line_count);
    write_le_u32(&mut out, header.cell_count);
    write_le_u32(&mut out, header.style_id_count);
    write_le_u32(&mut out, header.lines_offset);
    write_le_u32(&mut out, header.cells_offset);
    write_le_u32(&mut out, header.style_ids_offset);
    write_le_u32(&mut out, header.reserved);

    for line in &line_records {
        write_le_u32(&mut out, line.logical_line_index);
        write_le_u32(&mut out, line.visual_in_logical);
        write_le_u32(&mut out, line.char_offset_start);
        write_le_u32(&mut out, line.char_offset_end);
        write_le_u32(&mut out, line.cell_start_index);
        write_le_u32(&mut out, line.cell_count);
        write_le_u16(&mut out, line.segment_x_start_cells);
        out.push(line.is_wrapped_part);
        out.push(line.is_fold_placeholder_appended);
    }

    for cell in &cell_records {
        write_le_u32(&mut out, cell.scalar_value);
        write_le_u16(&mut out, cell.width);
        write_le_u16(&mut out, cell.style_count);
        write_le_u32(&mut out, cell.style_start_index);
    }

    for style_id in &style_ids {
        write_le_u32(&mut out, *style_id);
    }

    if out.len() != total_len_usize {
        return Err((
            EcfStatus::Internal,
            format!(
                "unexpected viewport blob length: got {}, expected {}",
                out.len(),
                total_len_usize
            ),
        ));
    }

    Ok(out)
}

pub(crate) fn copy_blob_to_output(
    blob: &[u8],
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> Result<(), (EcfStatus, String)> {
    if out_len.is_null() {
        return Err((EcfStatus::InvalidArgument, "out_len is null".to_string()));
    }

    let needed = checked_u32(blob.len(), "blob length")?;
    // SAFETY: checked non-null and owned by caller.
    unsafe {
        *out_len = needed;
    }

    if out_buf.is_null() || out_cap < needed {
        return Err((
            EcfStatus::BufferTooSmall,
            format!("output buffer too small: need {needed}, have {out_cap}"),
        ));
    }

    let needed_usize = usize::try_from(needed).map_err(|_| {
        (
            EcfStatus::Unsupported,
            "blob size exceeds usize".to_string(),
        )
    })?;
    // SAFETY: caller provided valid buffer with at least needed bytes; pointers do not overlap.
    unsafe {
        ptr::copy_nonoverlapping(blob.as_ptr(), out_buf, needed_usize);
    }

    Ok(())
}
