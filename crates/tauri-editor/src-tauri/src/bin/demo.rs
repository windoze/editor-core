// A small Rust demo to showcase tree-sitter syntax highlighting and code folding.

use std::collections::HashMap;

/// A point in 2-D space.
#[derive(Debug, Clone, Copy)]
struct Point {
    x: f64,
    y: f64,
}

impl Point {
    fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }

    fn distance(&self, other: &Point) -> f64 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }
}

/// Compute the centroid of a slice of points.
fn centroid(points: &[Point]) -> Option<Point> {
    if points.is_empty() {
        return None;
    }
    let n = points.len() as f64;
    let sum_x: f64 = points.iter().map(|p| p.x).sum();
    let sum_y: f64 = points.iter().map(|p| p.y).sum();
    Some(Point::new(sum_x / n, sum_y / n))
}

fn main() {
    let points = vec![
        Point::new(0.0, 0.0),
        Point::new(3.0, 4.0),
        Point::new(6.0, 0.0),
    ];

    if let Some(center) = centroid(&points) {
        println!("Centroid: ({:.2}, {:.2})", center.x, center.y);

        for (i, p) in points.iter().enumerate() {
            let d = p.distance(&center);
            println!("  Point {i} → distance to centroid = {d:.4}");
        }
    }

    // HashMap demo
    let mut counts: HashMap<&str, u32> = HashMap::new();
    let words = ["hello", "world", "hello", "rust"];
    for word in &words {
        *counts.entry(word).or_insert(0) += 1;
    }
    println!("Word counts: {counts:?}");
}
