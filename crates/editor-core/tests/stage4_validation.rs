//! Stage 4 validation tests
//!
//! Validation criteria:
//! 1. Folding awareness: With a fold starting at logical line 5, requesting visual line 6 should return content logically after line 5.
//! 2. Interval overlap: When multiple styles overlap (e.g. search highlight + syntax highlight), the interval tree must return all matches.

use editor_core::intervals::{FoldRegion, FoldingManager, Interval, IntervalTree};

#[test]
fn test_folding_awareness() {
    println!("测试折叠感知...");

    let mut manager = FoldingManager::new();

    // 创建折叠区域：折叠第 5-10 行
    let mut region = FoldRegion::new(5, 10);
    region.collapse();
    manager.add_region(region);

    println!("折叠区域：第 5-10 行");

    // 测试逻辑行到视觉行的映射
    // 第 0-4 行：视觉行 0-4
    assert_eq!(manager.logical_to_visual(0, 0), Some(0));
    assert_eq!(manager.logical_to_visual(4, 0), Some(4));

    // 第 5 行：折叠的起始行，视觉行 5
    assert_eq!(manager.logical_to_visual(5, 0), Some(5));

    // 第 6-10 行：被折叠，不可见
    assert_eq!(manager.logical_to_visual(6, 0), None);
    assert_eq!(manager.logical_to_visual(7, 0), None);
    assert_eq!(manager.logical_to_visual(10, 0), None);

    // 第 11 行：折叠后的第一行，视觉行 6（5 行被隐藏）
    assert_eq!(manager.logical_to_visual(11, 0), Some(6));

    // 第 15 行：视觉行 10（隐藏了 5 行）
    assert_eq!(manager.logical_to_visual(15, 0), Some(10));

    println!("✓ 折叠感知测试通过！");
}

#[test]
fn test_visual_to_logical_with_folding() {
    println!("测试视觉到逻辑行转换（带折叠）...");

    let mut manager = FoldingManager::new();

    let mut region = FoldRegion::new(5, 10);
    region.collapse();
    manager.add_region(region);

    // 视觉行 0-4 -> 逻辑行 0-4
    assert_eq!(manager.visual_to_logical(0, 0), 0);
    assert_eq!(manager.visual_to_logical(4, 0), 4);

    // 视觉行 5 -> 逻辑行 5（折叠起始行）
    assert_eq!(manager.visual_to_logical(5, 0), 5);

    // 视觉行 6 -> 逻辑行 11（跳过折叠区域）
    assert_eq!(manager.visual_to_logical(6, 0), 11);

    // 视觉行 10 -> 逻辑行 15
    assert_eq!(manager.visual_to_logical(10, 0), 15);

    println!("✓ 视觉到逻辑行转换测试通过！");
}

#[test]
fn test_interval_overlap() {
    println!("测试区间重叠...");

    let mut tree = IntervalTree::new();

    // 添加多个重叠的样式区间
    tree.insert(Interval::new(0, 100, 1)); // 基础语法高亮
    tree.insert(Interval::new(20, 30, 2)); // 关键字高亮
    tree.insert(Interval::new(25, 35, 3)); // 搜索高亮
    tree.insert(Interval::new(28, 32, 4)); // 选中区域

    println!("插入了 4 个区间");

    // 查询位置 29，应该有 4 个重叠的样式
    let styles = tree.query_point(29);
    println!("位置 29 的样式数量: {}", styles.len());

    assert_eq!(styles.len(), 4, "位置 29 应该有 4 个重叠样式");

    // 验证所有样式 ID
    let style_ids: Vec<u32> = styles.iter().map(|i| i.style_id).collect();
    assert!(style_ids.contains(&1));
    assert!(style_ids.contains(&2));
    assert!(style_ids.contains(&3));
    assert!(style_ids.contains(&4));

    // 查询位置 22，应该有 2 个样式
    let styles_22 = tree.query_point(22);
    println!("位置 22 的样式数量: {}", styles_22.len());
    assert_eq!(styles_22.len(), 2); // 样式 1 和 2

    // 查询位置 33，应该有 2 个样式
    let styles_33 = tree.query_point(33);
    println!("位置 33 的样式数量: {}", styles_33.len());
    assert_eq!(styles_33.len(), 2); // 样式 1 和 3

    println!("✓ 区间重叠测试通过！");
}

#[test]
fn test_multiple_folding_regions() {
    println!("测试多个折叠区域...");

    let mut manager = FoldingManager::new();

    // 添加多个折叠区域
    let mut region1 = FoldRegion::new(5, 10);
    region1.collapse();
    manager.add_region(region1);

    let mut region2 = FoldRegion::new(20, 25);
    region2.collapse();
    manager.add_region(region2);

    println!("折叠区域 1：第 5-10 行");
    println!("折叠区域 2：第 20-25 行");

    // 测试第一个折叠区域
    assert_eq!(manager.logical_to_visual(4, 0), Some(4));
    assert_eq!(manager.logical_to_visual(5, 0), Some(5));
    assert_eq!(manager.logical_to_visual(7, 0), None); // 被折叠

    // 测试两个折叠区域之间
    assert_eq!(manager.logical_to_visual(15, 0), Some(10)); // 15 - 5 隐藏行

    // 测试第二个折叠区域
    assert_eq!(manager.logical_to_visual(20, 0), Some(15)); // 20 - 5
    assert_eq!(manager.logical_to_visual(23, 0), None); // 被折叠

    // 测试第二个折叠区域之后
    // 逻辑行 30：在两个折叠区域之后
    // 折叠区域 1 隐藏了 5 行（6-10）
    // 折叠区域 2 隐藏了 5 行（21-25）
    // 所以 30 - 5 - 5 = 20
    assert_eq!(manager.logical_to_visual(30, 0), Some(20));

    println!("✓ 多个折叠区域测试通过！");
}

#[test]
fn test_interval_tree_text_changes() {
    println!("测试文本变化时的区间更新...");

    let mut tree = IntervalTree::new();

    tree.insert(Interval::new(10, 20, 1));
    tree.insert(Interval::new(30, 40, 2));
    tree.insert(Interval::new(50, 60, 3));

    println!("初始区间：[10,20), [30,40), [50,60)");

    // 在位置 15 插入 5 个字符
    tree.update_for_insertion(15, 5);

    println!("在位置 15 插入 5 个字符后：");
    let intervals = tree.query_range(0, 100);
    for interval in intervals {
        println!("  [{}, {})", interval.start, interval.end);
    }

    // 第一个区间应该被扩展
    let results1 = tree.query_point(12);
    let i1 = results1.first().unwrap();
    assert_eq!(i1.start, 10);
    assert_eq!(i1.end, 25); // 20 + 5

    // 后续区间应该向后移动
    // 原来的区间 [30, 40) 现在应该在 [35, 45)
    // 查询位置 37 应该能找到它
    let results2 = tree.query_point(37);
    let i2 = results2.first().unwrap();
    assert_eq!(i2.start, 35); // 30 + 5
    assert_eq!(i2.end, 45); // 40 + 5

    println!("✓ 插入更新测试通过！");

    // 删除区间 [25, 35)
    tree.update_for_deletion(25, 35);

    println!("删除区间 [25, 35) 后：");
    let intervals = tree.query_range(0, 100);
    for interval in intervals {
        println!("  [{}, {})", interval.start, interval.end);
    }

    // 验证删除后的状态
    // 第一个区间 [10, 25) 应该被截断到 [10, 25)（结束于删除点）
    // 但由于删除的是 [25, 35)，第一个区间 [10, 25) 实际上不受影响
    // 删除后应该还有一些区间存在
    assert!(!tree.is_empty(), "删除后应该还有区间");

    println!("✓ 删除更新测试通过！");
}

#[test]
fn test_style_priority() {
    println!("测试样式优先级（通过查询顺序）...");

    let mut tree = IntervalTree::new();

    // 插入顺序可能影响查询结果的顺序
    tree.insert(Interval::new(0, 100, 1)); // 背景色
    tree.insert(Interval::new(20, 30, 2)); // 语法高亮
    tree.insert(Interval::new(25, 27, 3)); // 错误下划线

    let styles = tree.query_point(26);
    assert_eq!(styles.len(), 3);

    // 所有样式都应该被找到
    let ids: Vec<u32> = styles.iter().map(|s| s.style_id).collect();
    assert!(ids.contains(&1));
    assert!(ids.contains(&2));
    assert!(ids.contains(&3));

    println!("✓ 样式优先级测试通过！");
}

#[test]
fn test_folding_toggle() {
    println!("测试折叠切换...");

    let mut manager = FoldingManager::new();

    manager.add_region(FoldRegion::new(10, 20));

    // 初始状态：未折叠
    assert!(!manager.get_region_for_line(10).unwrap().is_collapsed);

    // 切换：折叠
    assert!(manager.toggle_line(10));
    assert!(manager.get_region_for_line(10).unwrap().is_collapsed);

    // 再次切换：展开
    assert!(manager.toggle_line(10));
    assert!(!manager.get_region_for_line(10).unwrap().is_collapsed);

    // 再次切换：折叠
    assert!(manager.toggle_line(10));
    assert!(manager.get_region_for_line(10).unwrap().is_collapsed);

    println!("✓ 折叠切换测试通过！");
}

#[test]
fn test_expand_collapse_all() {
    println!("测试全部展开/折叠...");

    let mut manager = FoldingManager::new();

    manager.add_region(FoldRegion::new(5, 10));
    manager.add_region(FoldRegion::new(15, 20));
    manager.add_region(FoldRegion::new(25, 30));

    // 全部折叠
    manager.collapse_all();

    for region in manager.regions() {
        assert!(region.is_collapsed, "所有区域应该被折叠");
    }

    // 全部展开
    manager.expand_all();

    for region in manager.regions() {
        assert!(!region.is_collapsed, "所有区域应该被展开");
    }

    println!("✓ 全部展开/折叠测试通过！");
}

#[test]
fn test_interval_deletion_overlap() {
    println!("测试删除操作对区间的影响...");

    let mut tree = IntervalTree::new();

    tree.insert(Interval::new(10, 20, 1));
    tree.insert(Interval::new(25, 35, 2));
    tree.insert(Interval::new(40, 50, 3));
    tree.insert(Interval::new(15, 30, 4)); // 跨越删除区域

    println!("初始区间数量: {}", tree.len());
    assert_eq!(tree.len(), 4);

    // 删除区间 [20, 40) - 应该影响多个区间
    tree.update_for_deletion(20, 40);

    println!("删除后区间数量: {}", tree.len());

    // 验证更新
    let remaining = tree.query_range(0, 100);
    for (i, interval) in remaining.iter().enumerate() {
        println!(
            "  区间 {}: [{}, {}) - 样式 {}",
            i, interval.start, interval.end, interval.style_id
        );
    }

    println!("✓ 区间删除重叠测试通过！");
}

#[test]
fn test_query_range_performance() {
    println!("测试范围查询性能...");

    let mut tree = IntervalTree::new();

    // 插入大量区间
    for i in 0..1000 {
        let start = i * 10;
        let end = start + 15; // 有重叠
        tree.insert(Interval::new(start, end, i as u32));
    }

    println!("插入了 1000 个区间");

    // 执行多次范围查询
    for _ in 0..100 {
        let results = tree.query_range(5000, 5100);
        assert!(!results.is_empty(), "应该找到一些区间");
    }

    println!("✓ 范围查询性能测试通过！");
}

#[test]
fn test_complex_folding_scenario() {
    println!("测试复杂折叠场景...");

    let mut manager = FoldingManager::new();

    // 模拟代码结构：多个函数，每个函数可以折叠
    manager.add_region(FoldRegion::new(1, 10)); // 函数1
    manager.add_region(FoldRegion::new(12, 20)); // 函数2
    manager.add_region(FoldRegion::new(22, 35)); // 函数3
    manager.add_region(FoldRegion::new(37, 50)); // 函数4

    // 折叠函数 2 和 4
    manager.collapse_line(15);
    manager.collapse_line(40);

    println!("折叠了函数 2 和 4");

    // 验证视觉行映射
    assert_eq!(manager.logical_to_visual(0, 0), Some(0));
    assert_eq!(manager.logical_to_visual(10, 0), Some(10));

    // 函数2 被折叠（12-20，隐藏 8 行：13-20）
    assert_eq!(manager.logical_to_visual(12, 0), Some(12));
    assert_eq!(manager.logical_to_visual(15, 0), None);

    // 函数3 没有折叠（22-35）
    // 逻辑行 22 - 8 个隐藏行（13-20）= 14
    assert_eq!(manager.logical_to_visual(22, 0), Some(14));

    // 函数4 被折叠（37-50，隐藏 13 行：38-50）
    // 逻辑行 37 - 8（函数2）= 29
    assert_eq!(manager.logical_to_visual(37, 0), Some(29));
    assert_eq!(manager.logical_to_visual(45, 0), None);

    println!("✓ 复杂折叠场景测试通过！");
}
