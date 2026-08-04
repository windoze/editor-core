import AppKit
import Foundation

extension AttoEditorAreaViewController {
    @discardableResult
    func showLspWorkbenchHistoryPanel() -> Bool {
        showLspWorkbenchHistoryPanel(family: nil)
    }

    @discardableResult
    func showLspWorkbenchHistoryPanel(family: String?) -> Bool {
        showLspWorkbenchHistoryPanel(family: family, pinnedOnly: false)
    }

    @discardableResult
    func showLspWorkbenchPinnedResultsPanel() -> Bool {
        showLspWorkbenchHistoryPanel(family: nil, pinnedOnly: true)
    }

    @discardableResult
    private func showLspWorkbenchHistoryPanel(family: String?, pinnedOnly: Bool) -> Bool {
        let items = lspWorkbenchHistoryItems(family: family, pinnedOnly: pinnedOnly)
        guard items.isEmpty == false else {
            if pinnedOnly, let family {
                setTransientStatusText("LSP workbench pinned results: none for \(family)")
            } else if pinnedOnly {
                setTransientStatusText("LSP workbench pinned results: none")
            } else if let family {
                setTransientStatusText("LSP workbench history: none for \(family)")
            } else {
                setTransientStatusText("LSP workbench history: none")
            }
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            if pinnedOnly, let family {
                setTransientStatusText("LSP workbench pinned results: \(items.count) for \(family)")
            } else if pinnedOnly {
                setTransientStatusText("LSP workbench pinned results: \(items.count)")
            } else if let family {
                setTransientStatusText("LSP workbench history: \(items.count) for \(family)")
            } else {
                setTransientStatusText("LSP workbench history: \(items.count)")
            }
            return true
        }

        lspWorkbenchHistoryPanelFamilyFilter = family
        lspWorkbenchHistoryPanelPinnedOnly = pinnedOnly
        let controller = lspWorkbenchHistoryPanelController ?? makeLspWorkbenchHistoryPanelController()
        lspWorkbenchHistoryPanelController = controller
        return controller.show(relativeTo: window, items: items)
    }

    func updateVisibleLspWorkbenchHistoryPanel() {
        guard lspWorkbenchHistoryPanelController?.isVisible == true else { return }
        lspWorkbenchHistoryPanelController?.update(
            items: lspWorkbenchHistoryItems(
                family: lspWorkbenchHistoryPanelFamilyFilter,
                pinnedOnly: lspWorkbenchHistoryPanelPinnedOnly
            )
        )
    }

    func lspWorkbenchHistoryItems() -> [AttoLspWorkbenchHistoryPanelController.Item] {
        lspWorkbenchHistoryItems(family: nil)
    }

    func lspWorkbenchHistoryItems(family selectedFamily: String?) -> [AttoLspWorkbenchHistoryPanelController.Item] {
        lspWorkbenchHistoryItems(family: selectedFamily, pinnedOnly: false)
    }

    func lspWorkbenchPinnedHistoryItems() -> [AttoLspWorkbenchHistoryPanelController.Item] {
        lspWorkbenchHistoryItems(family: nil, pinnedOnly: true)
    }

    func lspWorkbenchHistoryItems(
        family selectedFamily: String?,
        pinnedOnly: Bool
    ) -> [AttoLspWorkbenchHistoryPanelController.Item] {
        var items: [AttoLspWorkbenchHistoryPanelController.Item] = []

        items.append(contentsOf: lspLocationResultStore.historyEntries.map { entry in
            lspWorkbenchHistoryItem(
                idPrefix: "locations",
                family: "locations",
                title: entry.title.isEmpty ? "Locations" : entry.title,
                detail: historyCountText(entry.snapshot.items.count, singular: "location", plural: "locations"),
                entry: entry,
                isPinned: pinnedLifecycleEntry(
                    lspLocationResultStore.pinnedEntriesByKey["locations"],
                    matches: entry
                )
            )
        })

        for entry in lspSymbolResultStore.historyEntries {
            let isOutline = lspWorkbenchHistoryIsWorkspaceOutlineEntry(entry)
            let family = isOutline ? "workspace_outline" : "symbols"
            items.append(lspWorkbenchHistoryItem(
                idPrefix: family,
                family: family,
                title: entry.title.isEmpty ? entry.snapshot.title : entry.title,
                detail: historyCountText(entry.snapshot.symbols.count, singular: "symbol", plural: "symbols"),
                entry: entry,
                isPinned: pinnedLifecycleEntry(
                    lspSymbolResultStore.pinnedEntriesByKey[family],
                    matches: entry
                )
            ))
        }

        items.append(contentsOf: diagnosticsLifecycleStore.historyEntries.map { entry in
            let family = entry.family == "diagnostics.workspace" ? "workspace_problems" : "active_problems"
            return lspWorkbenchHistoryItem(
                idPrefix: family,
                family: family,
                title: entry.title.isEmpty ? diagnosticsHistoryTitle(for: entry.snapshot) : entry.title,
                detail: historyCountText(entry.snapshot.problems.count, singular: "problem", plural: "problems"),
                entry: entry,
                isPinned: pinnedLifecycleEntry(
                    diagnosticsLifecycleStore.pinnedEntriesByKey[entry.family],
                    matches: entry
                )
            )
        })

        let visibleEventFamilies: Set<String> = [
            "code_lens",
            "inlay_hints",
            "document_links",
            "document_colors",
            "hierarchy",
        ]
        items.append(contentsOf: lspResultEventStream.events.compactMap { event in
            guard visibleEventFamilies.contains(event.family) else { return nil }
            return lspWorkbenchHistoryItem(
                event: event,
                isPinned: lspResultEventStream.pinnedEventsByFamily[event.family]?.sequence == event.sequence
            )
        })
        appendRetainedPinnedLspWorkbenchHistoryItems(
            to: &items,
            visibleEventFamilies: visibleEventFamilies
        )

        let sorted = items.sorted {
            if $0.recordedAt == $1.recordedAt {
                return $0.id > $1.id
            }
            return $0.recordedAt > $1.recordedAt
        }
        let familyFiltered: [AttoLspWorkbenchHistoryPanelController.Item]
        if let selectedFamily {
            familyFiltered = sorted.filter { $0.family == selectedFamily }
        } else {
            familyFiltered = sorted
        }
        guard pinnedOnly else { return familyFiltered }
        return familyFiltered.filter(\.isPinned)
    }

    private func makeLspWorkbenchHistoryPanelController() -> AttoLspWorkbenchHistoryPanelController {
        AttoLspWorkbenchHistoryPanelController { [weak self] item in
            self?.openLspWorkbenchHistoryItem(item)
        }
    }

    private func appendRetainedPinnedLspWorkbenchHistoryItems(
        to items: inout [AttoLspWorkbenchHistoryPanelController.Item],
        visibleEventFamilies: Set<String>
    ) {
        if let entry = lspLocationResultStore.pinnedEntriesByKey["locations"],
           containsLspWorkbenchHistoryItem(items, family: "locations", sequence: entry.sequence) == false {
            items.append(lspWorkbenchHistoryItem(
                idPrefix: "locations",
                family: "locations",
                title: entry.title.isEmpty ? "Locations" : entry.title,
                detail: historyCountText(entry.snapshot.items.count, singular: "location", plural: "locations"),
                entry: entry,
                isPinned: true
            ))
        }

        for family in ["symbols", "workspace_outline"] {
            guard let entry = lspSymbolResultStore.pinnedEntriesByKey[family],
                  containsLspWorkbenchHistoryItem(items, family: family, sequence: entry.sequence) == false
            else {
                continue
            }
            items.append(lspWorkbenchHistoryItem(
                idPrefix: family,
                family: family,
                title: entry.title.isEmpty ? entry.snapshot.title : entry.title,
                detail: historyCountText(entry.snapshot.symbols.count, singular: "symbol", plural: "symbols"),
                entry: entry,
                isPinned: true
            ))
        }

        for (key, family) in [
            ("diagnostics.active", "active_problems"),
            ("diagnostics.workspace", "workspace_problems"),
        ] {
            guard let entry = diagnosticsLifecycleStore.pinnedEntriesByKey[key],
                  containsLspWorkbenchHistoryItem(items, family: family, sequence: entry.sequence) == false
            else {
                continue
            }
            items.append(lspWorkbenchHistoryItem(
                idPrefix: family,
                family: family,
                title: entry.title.isEmpty ? diagnosticsHistoryTitle(for: entry.snapshot) : entry.title,
                detail: historyCountText(entry.snapshot.problems.count, singular: "problem", plural: "problems"),
                entry: entry,
                isPinned: true
            ))
        }

        for (family, event) in lspResultEventStream.pinnedEventsByFamily
            where visibleEventFamilies.contains(family)
                && containsLspWorkbenchHistoryItem(items, family: family, sequence: event.sequence) == false {
            items.append(lspWorkbenchHistoryItem(event: event, isPinned: true))
        }
    }

    private func containsLspWorkbenchHistoryItem(
        _ items: [AttoLspWorkbenchHistoryPanelController.Item],
        family: String,
        sequence: UInt64
    ) -> Bool {
        items.contains {
            $0.family == family && $0.resultSequence == sequence
        }
    }

    @discardableResult
    func openLspWorkbenchHistoryItem(_ item: AttoLspWorkbenchHistoryPanelController.Item) -> Bool {
        if restoreLspWorkbenchHistoryItem(item) {
            return true
        }

        switch item.family {
        case "active_problems":
            return showProblemsPanelInActiveTab()
        case "workspace_problems":
            return showWorkspaceProblemsPanelInActiveTab()
        case "locations":
            return showLspLocationHistory()
        case "symbols":
            return showLspSymbolHistory()
        case "workspace_outline":
            return showWorkspaceOutlinePanel()
        case "code_lens":
            return showCodeLensPanelInActiveTab()
        case "inlay_hints":
            return showInlayHintsPanelInActiveTab()
        case "document_links":
            return showDocumentLinksPanelInActiveTab()
        case "document_colors":
            return showDocumentColorsPanelInActiveTab()
        case "hierarchy":
            return showHierarchyPanelInActiveTab()
        default:
            NSSound.beep()
            return false
        }
    }

    private func restoreLspWorkbenchHistoryItem(_ item: AttoLspWorkbenchHistoryPanelController.Item) -> Bool {
        guard restoreLspWorkbenchHistoryCurrentEntry(item) else {
            return false
        }

        switch item.family {
        case "locations":
            return showLspLocationPanel()
        case "symbols", "workspace_outline":
            return showLspSymbolPanel()
        case "active_problems", "workspace_problems":
            guard let entry = diagnosticsLifecycleStore.currentEntry else { return false }
            return showDiagnosticsLifecycleEntryPanel(entry)
        case "code_lens", "inlay_hints", "document_links", "document_colors", "hierarchy":
            guard let entry = lspWorkbenchAuxiliaryHistoryStore.entry(eventSequence: item.resultSequence) else {
                return false
            }
            return showLspWorkbenchAuxiliaryHistoryEntry(entry)
        default:
            return false
        }
    }

    @discardableResult
    func restoreLspWorkbenchHistoryCurrentEntry(_ item: AttoLspWorkbenchHistoryPanelController.Item) -> Bool {
        switch item.family {
        case "locations":
            guard let entry = lspLocationResultStore.historyEntries.first(where: {
                $0.sequence == item.resultSequence
            }) ?? pinnedLspLocationHistoryEntry(sequence: item.resultSequence) else {
                return false
            }
            guard restoreLspResultOwnerSelection(entry.owner) else { return false }
            lspLocationResultStore.makeCurrent(entry)
            lspLocationPanelController?.update(entry: entry)
            updateVisibleLspWorkbenchPanel()
            updateVisibleLspWorkbenchHistoryPanel()
            return true

        case "symbols", "workspace_outline":
            guard let entry = lspSymbolResultStore.historyEntries.first(where: {
                $0.sequence == item.resultSequence
                    && lspWorkbenchHistoryIsWorkspaceOutlineEntry($0) == (item.family == "workspace_outline")
            }) ?? pinnedLspSymbolHistoryEntry(family: item.family, sequence: item.resultSequence) else {
                return false
            }
            guard restoreLspResultOwnerSelection(entry.owner) else { return false }
            lspSymbolResultStore.makeCurrent(entry)
            lspSymbolPanelController?.update(entry: entry)
            updateVisibleLspWorkbenchPanel()
            updateVisibleLspWorkbenchHistoryPanel()
            return true

        case "active_problems":
            guard let entry = diagnosticsLifecycleStore.historyEntries.first(where: {
                $0.sequence == item.resultSequence && $0.family == "diagnostics.active"
            }) ?? pinnedDiagnosticsHistoryEntry(key: "diagnostics.active", sequence: item.resultSequence) else {
                return false
            }
            guard restoreLspResultOwnerSelection(entry.owner) else { return false }
            diagnosticsLifecycleStore.makeCurrent(entry)
            updateVisibleLspWorkbenchPanel()
            updateVisibleLspWorkbenchHistoryPanel()
            return true

        case "workspace_problems":
            guard let entry = diagnosticsLifecycleStore.historyEntries.first(where: {
                $0.sequence == item.resultSequence && $0.family == "diagnostics.workspace"
            }) ?? pinnedDiagnosticsHistoryEntry(key: "diagnostics.workspace", sequence: item.resultSequence) else {
                return false
            }
            guard restoreLspResultOwnerSelection(entry.owner) else { return false }
            diagnosticsLifecycleStore.makeCurrent(entry)
            updateVisibleLspWorkbenchPanel()
            updateVisibleLspWorkbenchHistoryPanel()
            return true

        default:
            guard let entry = lspWorkbenchAuxiliaryHistoryStore.entry(eventSequence: item.resultSequence),
                  entry.family == item.family
            else {
                return false
            }
            guard restoreLspResultOwnerSelection(entry.owner) else { return false }
            restoreLspWorkbenchAuxiliaryHistoryEntry(entry)
            updateVisibleLspWorkbenchPanel()
            updateVisibleLspWorkbenchHistoryPanel()
            return true
        }
    }

    private func pinnedLspLocationHistoryEntry(
        sequence: UInt64
    ) -> AttoLspResultLifecycleEntry<LspLocationResultSnapshot>? {
        guard let entry = lspLocationResultStore.pinnedEntriesByKey["locations"],
              entry.sequence == sequence
        else {
            return nil
        }
        return entry
    }

    private func pinnedLspSymbolHistoryEntry(
        family: String,
        sequence: UInt64
    ) -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        guard let entry = lspSymbolResultStore.pinnedEntriesByKey[family],
              entry.sequence == sequence
        else {
            return nil
        }
        return entry
    }

    private func pinnedDiagnosticsHistoryEntry(
        key: String,
        sequence: UInt64
    ) -> AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>? {
        guard let entry = diagnosticsLifecycleStore.pinnedEntriesByKey[key],
              entry.sequence == sequence
        else {
            return nil
        }
        return entry
    }

    private func lspWorkbenchHistoryItem<Snapshot>(
        idPrefix: String,
        family: String,
        title: String,
        detail: String,
        entry: AttoLspResultLifecycleEntry<Snapshot>,
        isPinned: Bool
    ) -> AttoLspWorkbenchHistoryPanelController.Item {
        AttoLspWorkbenchHistoryPanelController.Item(
            id: "\(idPrefix).\(entry.sequence)",
            family: family,
            resultSequence: entry.sequence,
            title: title,
            detail: detail,
            status: "\(entry.state.displayText) | Result #\(entry.sequence)",
            recordedAt: entry.recordedAt,
            isPinned: isPinned
        )
    }

    private func lspWorkbenchHistoryItem(
        event: AttoLspResultLifecycleEvent,
        isPinned: Bool
    ) -> AttoLspWorkbenchHistoryPanelController.Item {
        AttoLspWorkbenchHistoryPanelController.Item(
            id: "\(event.family).\(event.sequence)",
            family: event.family,
            resultSequence: event.sequence,
            title: event.title.isEmpty ? event.family : event.title,
            detail: lspWorkbenchHistoryEventDetail(event.payload),
            status: "\(event.state.displayText) | Result #\(event.sequence)",
            recordedAt: event.recordedAt,
            isPinned: isPinned
        )
    }

    private func pinnedLifecycleEntry<Snapshot>(
        _ pinnedEntry: AttoLspResultLifecycleEntry<Snapshot>?,
        matches entry: AttoLspResultLifecycleEntry<Snapshot>
    ) -> Bool {
        pinnedEntry?.sequence == entry.sequence && pinnedEntry?.family == entry.family
    }

    private func lspWorkbenchHistoryIsWorkspaceOutlineEntry(
        _ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>
    ) -> Bool {
        entry.snapshot.title == "Workspace Outline" || entry.title.hasPrefix("Workspace Outline")
    }

    private func diagnosticsHistoryTitle(for snapshot: AttoDiagnosticsLifecycleSnapshot) -> String {
        switch snapshot.scope {
        case .activeTab(_, let fileURL):
            return fileURL.lastPathComponent
        case .workspace:
            return "Workspace Problems"
        }
    }

    private func historyCountText(_ count: Int, singular: String, plural: String) -> String {
        AttoLspResultMetadataText.count(count, singular: singular, plural: plural)
    }

    private func lspWorkbenchHistoryEventDetail(_ payload: AttoLspResultLifecycleEvent.Payload) -> String {
        switch payload {
        case .codeLens(let itemCount):
            return historyCountText(itemCount, singular: "action", plural: "actions")
        case .inlayHints(let itemCount):
            return historyCountText(itemCount, singular: "hint", plural: "hints")
        case .documentLinks(let itemCount):
            return historyCountText(itemCount, singular: "link", plural: "links")
        case .documentColors(let mode, let itemCount):
            return "\(historyCountText(itemCount, singular: "color", plural: "colors")) | \(mode)"
        case .hierarchy(let title, let itemCount):
            return "\(historyCountText(itemCount, singular: "result", plural: "results")) | \(title)"
        default:
            return "result"
        }
    }
}
