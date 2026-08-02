import Foundation

final class AttoLspResultLifecycleStore<Snapshot> {
    private let maxHistoryEntries: Int
    private(set) var current: Snapshot?
    private(set) var history: [Snapshot] = []

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(_ snapshot: Snapshot) -> Snapshot {
        current = snapshot
        history.append(snapshot)
        if history.count > maxHistoryEntries {
            history.removeFirst(history.count - maxHistoryEntries)
        }
        return snapshot
    }

    func makeCurrent(_ snapshot: Snapshot) {
        current = snapshot
    }

    func clear() {
        current = nil
        history.removeAll()
    }
}
