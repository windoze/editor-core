import AppKit

@MainActor
enum AttoWindowSizing {
    static let preferredContentSize = CGSize(width: 1180, height: 780)
    static let minimumContentSize = CGSize(width: 900, height: 600)

    static func defaultContentSize(forVisibleFrame visibleFrame: CGRect) -> CGSize {
        let visibleW = max(1, visibleFrame.width)
        let visibleH = max(1, visibleFrame.height)

        let wCandidate = min(preferredContentSize.width, visibleW * 0.9)
        let hCandidate = min(preferredContentSize.height, visibleH * 0.9)

        let w = min(visibleW, max(minimumContentSize.width, wCandidate))
        let h = min(visibleH, max(minimumContentSize.height, hCandidate))

        return CGSize(width: floor(w), height: floor(h))
    }
}

