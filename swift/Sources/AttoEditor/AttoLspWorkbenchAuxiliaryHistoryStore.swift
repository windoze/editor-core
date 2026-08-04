import Foundation

@MainActor
final class AttoLspWorkbenchAuxiliaryHistoryStore {
    struct Entry: Equatable {
        enum Payload: Equatable {
            case codeLens([AttoLspCodeLensParser.Item])
            case inlayHints([AttoLspInlayHintParser.Item])
            case documentLinks([AttoLspDocumentLinkParser.Item])
            case documentColors([AttoLspDocumentColorParser.Item])
            case hierarchy(AttoHierarchyPanelController.Snapshot)
        }

        let eventSequence: UInt64
        let family: String
        let title: String
        let recordedAt: Date
        let owner: AttoLspResultOwner?
        let payload: Payload
    }

    private let maxHistoryEntries: Int
    private var order: [UInt64] = []
    private var entriesBySequence: [UInt64: Entry] = [:]
    private var pinnedEntriesByFamily: [String: Entry] = [:]

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(
        event: AttoLspResultLifecycleEvent,
        payload: Entry.Payload
    ) -> Entry {
        let entry = Entry(
            eventSequence: event.sequence,
            family: event.family,
            title: event.title,
            recordedAt: event.recordedAt,
            owner: event.owner,
            payload: payload
        )

        if entriesBySequence[event.sequence] == nil {
            order.append(event.sequence)
        }
        entriesBySequence[event.sequence] = entry
        trimIfNeeded()
        return entry
    }

    func entry(eventSequence: UInt64) -> Entry? {
        entriesBySequence[eventSequence] ?? pinnedEntriesByFamily.values.first {
            $0.eventSequence == eventSequence
        }
    }

    @discardableResult
    func pinLatest(
        family: String,
        ownerMatches: (AttoLspResultOwner?) -> Bool = { _ in true }
    ) -> Entry? {
        guard let sequence = order.reversed().first(where: {
            guard let entry = entriesBySequence[$0] else { return false }
            return entry.family == family && ownerMatches(entry.owner)
        }),
              let entry = entriesBySequence[sequence]
        else {
            return nil
        }
        pinnedEntriesByFamily[family] = entry
        return entry
    }

    @discardableResult
    func unpin(family: String) -> Entry? {
        pinnedEntriesByFamily.removeValue(forKey: family)
    }

    func clear() {
        order.removeAll()
        entriesBySequence.removeAll()
        pinnedEntriesByFamily.removeAll()
    }

    private func trimIfNeeded() {
        guard order.count > maxHistoryEntries else { return }
        let removeCount = order.count - maxHistoryEntries
        let removed = order.prefix(removeCount)
        order.removeFirst(removeCount)
        for sequence in removed {
            entriesBySequence.removeValue(forKey: sequence)
        }
    }
}
