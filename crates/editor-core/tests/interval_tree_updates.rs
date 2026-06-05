use editor_core::{
    Command, EditCommand, EditorStateManager, Interval, IntervalTextEdit, IntervalTree,
    StyleCommand, StyleLayerId, TextEditSpec,
};

fn interval_snapshot(tree: &IntervalTree) -> Vec<(usize, usize, u32)> {
    tree.query_range(0, 10_000)
        .into_iter()
        .map(|interval| (interval.start, interval.end, interval.style_id))
        .collect()
}

fn apply_sequential(tree: &mut IntervalTree, edits: &[IntervalTextEdit]) {
    let mut edits = edits.to_vec();
    edits.sort_by_key(|edit| std::cmp::Reverse(edit.start));
    for edit in edits {
        if edit.delete_len > 0 {
            tree.update_for_deletion(edit.start, edit.start + edit.delete_len);
        }
        if edit.insert_len > 0 {
            tree.update_for_insertion(edit.start, edit.insert_len);
        }
    }
}

#[test]
fn batch_interval_update_matches_sequential_insert_delete_and_removal() {
    let edits = [
        IntervalTextEdit::new(18, 4, 2),
        IntervalTextEdit::new(9, 6, 0),
        IntervalTextEdit::new(3, 0, 3),
    ];

    let mut sequential = IntervalTree::new();
    sequential.insert(Interval::new(0, 5, 1));
    sequential.insert(Interval::new(7, 13, 2));
    sequential.insert(Interval::new(10, 14, 3));
    sequential.insert(Interval::new(16, 24, 4));
    apply_sequential(&mut sequential, &edits);

    let mut batched = IntervalTree::new();
    batched.insert(Interval::new(0, 5, 1));
    batched.insert(Interval::new(7, 13, 2));
    batched.insert(Interval::new(10, 14, 3));
    batched.insert(Interval::new(16, 24, 4));
    batched.update_for_text_edits(&edits);

    assert_eq!(interval_snapshot(&batched), interval_snapshot(&sequential));
    assert_eq!(
        batched.query_point(11).len(),
        sequential.query_point(11).len()
    );
}

#[test]
fn apply_text_edits_updates_base_and_layered_styles_once_per_batch() {
    let mut manager = EditorStateManager::new("abcdefghijklmnopqrstuvwxyz", 80);
    manager
        .execute(Command::Style(StyleCommand::AddStyle {
            start: 2,
            end: 10,
            style_id: 1,
        }))
        .unwrap();

    let layer_a = StyleLayerId::new(101);
    let layer_b = StyleLayerId::new(102);
    manager.replace_style_layer(layer_a, vec![Interval::new(0, 6, 11)]);
    manager.replace_style_layer(layer_b, vec![Interval::new(12, 22, 12)]);

    let edits = vec![
        TextEditSpec {
            start: 1,
            end: 1,
            text: "XX".to_string(),
        },
        TextEditSpec {
            start: 5,
            end: 8,
            text: String::new(),
        },
        TextEditSpec {
            start: 16,
            end: 20,
            text: "y".to_string(),
        },
    ];
    let interval_edits: Vec<IntervalTextEdit> = edits
        .iter()
        .map(|edit| {
            IntervalTextEdit::new(edit.start, edit.end - edit.start, edit.text.chars().count())
        })
        .collect();

    let mut expected_base = IntervalTree::new();
    expected_base.insert(Interval::new(2, 10, 1));
    apply_sequential(&mut expected_base, &interval_edits);

    let mut expected_a = IntervalTree::new();
    expected_a.insert(Interval::new(0, 6, 11));
    apply_sequential(&mut expected_a, &interval_edits);

    let mut expected_b = IntervalTree::new();
    expected_b.insert(Interval::new(12, 22, 12));
    apply_sequential(&mut expected_b, &interval_edits);

    manager
        .execute(Command::Edit(EditCommand::ApplyTextEdits { edits }))
        .unwrap();

    assert_eq!(
        interval_snapshot(manager.editor().interval_tree()),
        interval_snapshot(&expected_base)
    );
    assert_eq!(
        interval_snapshot(manager.editor().style_layer(layer_a).unwrap()),
        interval_snapshot(&expected_a)
    );
    assert_eq!(
        interval_snapshot(manager.editor().style_layer(layer_b).unwrap()),
        interval_snapshot(&expected_b)
    );
}
