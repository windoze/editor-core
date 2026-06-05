//! Stage 1 validation tests
//!
//! Validation criteria:
//! 1. Consistency: Run many random insert/delete operations on a reasonably sized document and verify it matches a reference implementation.
//! 2. Memory footprint: Perform 1,000,000 small edits; memory growth should be limited to the size of the `AddBuffer`.

use editor_core::storage::PieceTable;
use rand::Rng;
use ropey::Rope;

/// Generate a large text blob for testing.
fn generate_large_text(size_kb: usize) -> String {
    let target_bytes = size_kb * 1024;
    let mut text = String::with_capacity(target_bytes);

    let sample = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. \
                  Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n";

    while text.len() < target_bytes {
        text.push_str(sample);
    }

    text.truncate(target_bytes);
    text
}

#[test]
fn test_consistency_medium_document() {
    // 默认测试应保持在可接受的时间内（debug profile 下也能快速跑完）。
    // 如需更强压力测试，可将 size_kb / operation_count 调大。
    let size_kb = 20;
    let operation_count = 300;

    println!("测试 {}KB 文档一致性...", size_kb);
    let original_text = generate_large_text(size_kb);

    let mut piece_table = PieceTable::new(&original_text);
    // 使用 Rope 作为参考实现（按字符偏移插入/删除），避免 String 的 O(n) 字符索引开销。
    let mut reference = Rope::from_str(&original_text);

    let mut rng = rand::thread_rng();
    println!("执行 {} 次随机操作...", operation_count);

    for i in 0..operation_count {
        if i % 50 == 0 {
            println!("  进度: {}/{}", i, operation_count);
        }

        let operation = rng.gen_bool(0.5);

        if operation {
            // 插入：只在文档开头、中间或末尾
            let text = match rng.gen_range(0..4) {
                0 => "X",
                1 => "你好",
                2 => "👋",
                _ => "test\n",
            };

            let len = piece_table.char_count();
            let offset = match rng.gen_range(0..3) {
                0 => 0,       // 开头
                1 => len,     // 末尾
                _ => len / 2, // 中间
            };

            piece_table.insert(offset, text);

            reference.insert(offset, text);
        } else {
            // 删除
            let len = piece_table.char_count();
            if len > 10 {
                let offset = match rng.gen_range(0..3) {
                    0 => 0,
                    1 => len - 10,
                    _ => (len / 2).saturating_sub(5),
                };

                let delete_len = rng.gen_range(1..=10.min(len - offset));

                piece_table.delete(offset, delete_len);
                reference.remove(offset..offset + delete_len);
            }
        }

        // 定期验证一次（避免每步都做昂贵的全量对比）
        if i % 100 == 99 {
            assert_eq!(
                piece_table.char_count(),
                reference.len_chars(),
                "第 {} 次操作后字符数不匹配",
                i
            );
        }
    }

    println!("最终验证...");
    let result = piece_table.get_text();
    let reference = reference.to_string();

    assert_eq!(result.len(), reference.len(), "字节长度不匹配");
    assert_eq!(
        result.chars().count(),
        reference.chars().count(),
        "字符数不匹配"
    );
    assert_eq!(result, reference, "内容不一致");

    println!(
        "✓ 一致性测试通过！({}KB, {}次操作)",
        size_kb, operation_count
    );
}

#[test]
fn test_memory_footprint_1m_operations() {
    println!("测试内存足迹 (100万次操作)...");
    let mut piece_table = PieceTable::empty();

    let operation_count = 1_000_000;
    let mut total_inserted_bytes = 0;

    println!("执行 {} 次末尾插入...", operation_count);

    for i in 0..operation_count {
        if i % 100_000 == 0 {
            println!("  进度: {}/{}", i, operation_count);
        }

        let text = "a";
        let len = piece_table.char_count();
        piece_table.insert(len, text);
        total_inserted_bytes += text.len();
    }

    let add_buffer_size = piece_table.add_buffer_size();

    println!("总插入字节: {}", total_inserted_bytes);
    println!("AddBuffer 大小: {}", add_buffer_size);
    println!(
        "内存增长比率: {:.2}%",
        (add_buffer_size as f64 / total_inserted_bytes as f64) * 100.0
    );

    assert_eq!(
        add_buffer_size, total_inserted_bytes,
        "AddBuffer 大小应等于插入的总字节数"
    );

    println!("✓ 内存足迹测试通过！");
}

#[test]
fn test_stress_mixed_operations() {
    println!("压力测试 (10000次混合操作)...");
    let mut piece_table = PieceTable::new("Initial content for testing.");
    let mut reference = String::from("Initial content for testing.");
    let mut rng = rand::thread_rng();

    for i in 0..10_000 {
        if i % 1000 == 0 {
            println!("  进度: {}/10000", i);
        }

        let len = reference.chars().count();
        if len == 0 {
            piece_table.insert(0, "x");
            reference.push('x');
            continue;
        }

        match rng.gen_range(0..3) {
            0 => {
                // 插入
                let offset = rng.gen_range(0..=len);
                let text = "测";
                piece_table.insert(offset, text);

                let byte_offset = reference
                    .char_indices()
                    .nth(offset)
                    .map(|(i, _)| i)
                    .unwrap_or(reference.len());
                reference.insert_str(byte_offset, text);
            }
            1 => {
                // 删除
                if len > 5 {
                    let offset = rng.gen_range(0..len - 5);
                    let delete_len = rng.gen_range(1..=5);

                    piece_table.delete(offset, delete_len);

                    let start_byte = reference
                        .char_indices()
                        .nth(offset)
                        .map(|(i, _)| i)
                        .unwrap_or(reference.len());
                    let end_byte = reference
                        .char_indices()
                        .nth(offset + delete_len)
                        .map(|(i, _)| i)
                        .unwrap_or(reference.len());
                    reference.drain(start_byte..end_byte);
                }
            }
            _ => {
                // 范围查询
                if len > 10 {
                    let start = rng.gen_range(0..len - 10);
                    let range_len = rng.gen_range(1..=10);

                    let piece_range = piece_table.get_range(start, range_len);

                    let start_byte = reference
                        .char_indices()
                        .nth(start)
                        .map(|(i, _)| i)
                        .unwrap_or(reference.len());
                    let end_byte = reference
                        .char_indices()
                        .nth(start + range_len)
                        .map(|(i, _)| i)
                        .unwrap_or(reference.len());
                    let ref_range = &reference[start_byte..end_byte];

                    assert_eq!(piece_range, ref_range, "范围查询不一致");
                }
            }
        }

        // 定期验证
        if i % 1000 == 999 {
            assert_eq!(piece_table.get_text(), reference, "第 {} 次操作后不一致", i);
        }
    }

    println!("最终验证...");
    assert_eq!(piece_table.get_text(), reference);
    println!("✓ 压力测试通过！");
}

#[test]
fn test_large_document_append_performance() {
    // 测试大文档追加性能（不需要参考字符串）
    println!("测试大文档追加性能...");

    // 从 1KB 开始
    let initial_text = generate_large_text(1);
    let mut piece_table = PieceTable::new(&initial_text);

    println!("执行 50000 次末尾追加...");
    for i in 0..50_000 {
        if i % 10_000 == 0 {
            println!(
                "  进度: {}/50000, 当前大小: {} KB",
                i,
                piece_table.byte_count() / 1024
            );
        }

        let len = piece_table.char_count();
        piece_table.insert(len, "append ");
    }

    let final_size_kb = piece_table.byte_count() / 1024;
    println!("最终文档大小: {} KB", final_size_kb);
    println!("✓ 大文档追加性能测试通过！");
}
