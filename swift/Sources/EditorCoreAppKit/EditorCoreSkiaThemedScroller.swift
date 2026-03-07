import AppKit
import Foundation

/// 为 demo/自绘 editor 提供可主题化颜色的 `NSScroller`。
///
/// 说明：
/// - AppKit 自带 `NSScroller` 并不方便精确设置任意颜色（更多是系统外观/knobStyle）。
/// - 我们在 `.legacy` scroller style 下覆写绘制函数，实现最小的“背景/前景”配色能力。
@MainActor
final class EditorCoreSkiaThemedScroller: NSScroller {
    var slotFillColor: NSColor? { didSet { needsDisplay = true } }
    var knobFillColor: NSColor? { didSet { needsDisplay = true } }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard let color = slotFillColor else {
            super.drawKnobSlot(in: slotRect, highlight: flag)
            return
        }

        color.setFill()
        slotRect.fill()
    }

    override func drawKnob() {
        guard let color = knobFillColor else {
            super.drawKnob()
            return
        }

        // knob 的 rect 由 NSScroller 计算（受 knobProportion / doubleValue 影响）。
        let r = rect(for: .knob)
        guard r.isEmpty == false else { return }

        // 简单的圆角矩形；保持像素对齐，减少“发虚”的边缘。
        let inset: CGFloat = 1
        let rr = r.insetBy(dx: inset, dy: inset)
        let radius = min(6, min(rr.width, rr.height) * 0.5)

        let path = NSBezierPath(roundedRect: rr.integral, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()
    }
}

