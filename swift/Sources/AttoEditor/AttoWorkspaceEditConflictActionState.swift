import EditorCoreUIFFI
import Foundation

struct AttoWorkspaceEditActionButtonState: Equatable {
    let title: String?
    let isEnabled: Bool
    let toolTip: String?

    static func enabled(toolTip: String? = nil, title: String? = nil) -> Self {
        Self(title: title, isEnabled: true, toolTip: toolTip)
    }

    static func disabled(_ toolTip: String, title: String? = nil) -> Self {
        Self(title: title, isEnabled: false, toolTip: toolTip)
    }
}

struct AttoWorkspaceEditHistoryActionState: Equatable {
    let openConflict: AttoWorkspaceEditActionButtonState
    let saveConflict: AttoWorkspaceEditActionButtonState
    let discardConflict: AttoWorkspaceEditActionButtonState
    let saveAndResolve: AttoWorkspaceEditActionButtonState
    let discardAndResolve: AttoWorkspaceEditActionButtonState
    let rerunRequest: AttoWorkspaceEditActionButtonState
    let reapply: AttoWorkspaceEditActionButtonState
    let undoLatest: AttoWorkspaceEditActionButtonState
}

enum AttoWorkspaceEditConflictActionState {
    static func previewOpenConflict(targetURI: String?) -> AttoWorkspaceEditActionButtonState {
        guard let targetURI else {
            return .disabled("Select a WorkspaceEdit conflict to open its target.")
        }
        return .enabled(toolTip: "Open conflict target: \(displayName(for: targetURI))")
    }

    static func previewSaveConflict(targetURI: String?) -> AttoWorkspaceEditActionButtonState {
        guard let targetURI else {
            return .disabled("Selected conflict cannot be resolved by saving an open tab.")
        }
        return .enabled(toolTip: "Save conflict target: \(displayName(for: targetURI))")
    }

    static func previewDiscardConflict(targetURI: String?) -> AttoWorkspaceEditActionButtonState {
        guard let targetURI else {
            return .disabled("Selected conflict cannot be resolved by discarding an open tab.")
        }
        return .enabled(toolTip: "Discard conflict target changes: \(displayName(for: targetURI))")
    }

    static func previewSaveAndRetry(
        targetURI: String?,
        preview: AttoWorkspaceEditPreview?
    ) -> AttoWorkspaceEditActionButtonState {
        guard preview?.canResolveConflictAndRetry != false else {
            return .disabled(preview?.requestRetryUnavailableToolTip ?? "WorkspaceEdit retry is unavailable.")
        }
        guard let targetURI else {
            return .disabled("Selected conflict cannot be resolved by saving before retry.")
        }
        return .enabled(toolTip: "Save \(displayName(for: targetURI)), then retry the WorkspaceEdit.")
    }

    static func previewDiscardAndRetry(
        targetURI: String?,
        preview: AttoWorkspaceEditPreview?
    ) -> AttoWorkspaceEditActionButtonState {
        guard preview?.canResolveConflictAndRetry != false else {
            return .disabled(preview?.requestRetryUnavailableToolTip ?? "WorkspaceEdit retry is unavailable.")
        }
        guard let targetURI else {
            return .disabled("Selected conflict cannot be resolved by discarding before retry.")
        }
        return .enabled(toolTip: "Discard \(displayName(for: targetURI)), then retry the WorkspaceEdit.")
    }

    static func history(
        for item: AttoWorkspaceEditHistoryPanelController.Item?,
        hasUndoLatest: Bool
    ) -> AttoWorkspaceEditHistoryActionState {
        let requestLabel = nonEmpty(item?.requestRetryLabel)
        let hasRequest = requestLabel != nil
        let canRerun = item?.canRerunRequest == true
        let workspaceEditJSON = nonEmpty(item?.workspaceEditJSON)
        let saveURI = nonEmpty(item?.firstSaveableConflictURI)
        let discardURI = nonEmpty(item?.firstDiscardableConflictURI)

        return AttoWorkspaceEditHistoryActionState(
            openConflict: historyOpenConflict(item),
            saveConflict: historySaveConflict(item),
            discardConflict: historyDiscardConflict(item),
            saveAndResolve: historySaveAndResolve(
                item,
                title: hasRequest ? "Save & Rerun" : "Save & Reapply",
                requestLabel: requestLabel,
                canRerun: canRerun,
                workspaceEditJSON: workspaceEditJSON,
                saveURI: saveURI
            ),
            discardAndResolve: historyDiscardAndResolve(
                item,
                title: hasRequest ? "Discard & Rerun" : "Discard & Reapply",
                requestLabel: requestLabel,
                canRerun: canRerun,
                workspaceEditJSON: workspaceEditJSON,
                discardURI: discardURI
            ),
            rerunRequest: historyRerunRequest(item, requestLabel: requestLabel, canRerun: canRerun),
            reapply: historyReapply(item, workspaceEditJSON: workspaceEditJSON),
            undoLatest: hasUndoLatest
                ? .enabled(toolTip: "Undo the latest applied WorkspaceEdit transaction.")
                : .disabled("No applied WorkspaceEdit transaction is available to undo.")
        )
    }

    static func historyConflictSummary(
        for conflicts: [EcuWorkspaceEditTransactionConflict]
    ) -> String {
        let countText = conflicts.count == 1 ? "1 conflict" : "\(conflicts.count) conflicts"
        guard conflicts.isEmpty == false else { return countText }
        if conflicts.count == 1, let conflict = conflicts.first {
            let groupTitle = AttoWorkspaceEditPreview.conflictGroupTitle(
                kind: conflict.kind,
                operation: conflict.operation
            )
            guard conflict.uri.isEmpty == false else { return "\(countText): \(groupTitle)" }
            return "\(countText): \(groupTitle) in \(displayName(for: conflict.uri))"
        }

        var groups: [String: Int] = [:]
        var metadata: [String: (kind: String, operation: String?)] = [:]
        for conflict in conflicts {
            let key = "\(conflict.kind)\u{1F}\(conflict.operation ?? "")"
            groups[key, default: 0] += 1
            metadata[key] = (kind: conflict.kind, operation: conflict.operation)
        }
        let groupRows = groups.keys.sorted { lhs, rhs in
            let lhsMetadata = metadata[lhs] ?? ("", nil)
            let rhsMetadata = metadata[rhs] ?? ("", nil)
            return AttoWorkspaceEditPreview.conflictGroupTitle(
                kind: lhsMetadata.kind,
                operation: lhsMetadata.operation
            ) < AttoWorkspaceEditPreview.conflictGroupTitle(
                kind: rhsMetadata.kind,
                operation: rhsMetadata.operation
            )
        }.map { key -> String in
            let data = metadata[key] ?? ("", nil)
            return "\(AttoWorkspaceEditPreview.conflictGroupTitle(kind: data.kind, operation: data.operation)) \(groups[key] ?? 0)"
        }
        return "\(countText): \(groupRows.joined(separator: ", "))"
    }

    static func unavailableFeedback(for button: AttoWorkspaceEditActionButtonState) -> String {
        button.toolTip ?? "WorkspaceEdit action unavailable."
    }

    private static func historyOpenConflict(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?
    ) -> AttoWorkspaceEditActionButtonState {
        guard let uri = nonEmpty(item?.firstConflictURI) else {
            return .disabled("Select a WorkspaceEdit history row with a conflict to open its target.")
        }
        return .enabled(toolTip: "Open conflict target: \(displayName(for: uri))")
    }

    private static func historySaveConflict(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?
    ) -> AttoWorkspaceEditActionButtonState {
        guard let uri = nonEmpty(item?.firstSaveableConflictURI) else {
            return .disabled(saveUnavailableToolTip(for: item))
        }
        return .enabled(toolTip: "Save conflict target: \(displayName(for: uri))")
    }

    private static func historyDiscardConflict(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?
    ) -> AttoWorkspaceEditActionButtonState {
        guard let uri = nonEmpty(item?.firstDiscardableConflictURI) else {
            return .disabled(discardUnavailableToolTip(for: item))
        }
        return .enabled(toolTip: "Discard conflict target changes: \(displayName(for: uri))")
    }

    private static func historySaveAndResolve(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?,
        title: String,
        requestLabel: String?,
        canRerun: Bool,
        workspaceEditJSON: String?,
        saveURI: String?
    ) -> AttoWorkspaceEditActionButtonState {
        if let reason = resolveUnavailableToolTip(
            item,
            requestLabel: requestLabel,
            canRerun: canRerun,
            workspaceEditJSON: workspaceEditJSON,
            conflictURI: saveURI,
            resolveVerb: "saving",
            conflictKind: "saveable"
        ) {
            return .disabled(reason, title: title)
        }
        if let requestLabel {
            return .enabled(toolTip: "Save conflict target, then rerun \(requestLabel).", title: title)
        }
        return .enabled(toolTip: "Save conflict target, then reapply the WorkspaceEdit.", title: title)
    }

    private static func historyDiscardAndResolve(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?,
        title: String,
        requestLabel: String?,
        canRerun: Bool,
        workspaceEditJSON: String?,
        discardURI: String?
    ) -> AttoWorkspaceEditActionButtonState {
        if let reason = resolveUnavailableToolTip(
            item,
            requestLabel: requestLabel,
            canRerun: canRerun,
            workspaceEditJSON: workspaceEditJSON,
            conflictURI: discardURI,
            resolveVerb: "discarding",
            conflictKind: "discardable"
        ) {
            return .disabled(reason, title: title)
        }
        if let requestLabel {
            return .enabled(toolTip: "Discard conflict changes, then rerun \(requestLabel).", title: title)
        }
        return .enabled(toolTip: "Discard conflict changes, then reapply the WorkspaceEdit.", title: title)
    }

    private static func historyRerunRequest(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?,
        requestLabel: String?,
        canRerun: Bool
    ) -> AttoWorkspaceEditActionButtonState {
        guard let requestLabel else {
            return .disabled("Selected WorkspaceEdit was not recorded with a rerunnable request.")
        }
        guard canRerun else {
            return .disabled(cannotRerunToolTip(label: requestLabel, reason: item?.requestRetryUnavailableReason))
        }
        return .enabled(toolTip: "Rerun request: \(requestLabel)")
    }

    private static func historyReapply(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?,
        workspaceEditJSON: String?
    ) -> AttoWorkspaceEditActionButtonState {
        guard workspaceEditJSON != nil else {
            return .disabled("Original WorkspaceEdit payload is unavailable.")
        }
        let suffix = item?.status == "Rejected" ? " Rejected conflicts may need to be resolved first." : ""
        return .enabled(toolTip: "Reapply the captured WorkspaceEdit payload.\(suffix)")
    }

    private static func resolveUnavailableToolTip(
        _ item: AttoWorkspaceEditHistoryPanelController.Item?,
        requestLabel: String?,
        canRerun: Bool,
        workspaceEditJSON: String?,
        conflictURI: String?,
        resolveVerb: String,
        conflictKind: String
    ) -> String? {
        guard item != nil else {
            return "Select a WorkspaceEdit history row before \(resolveVerb) and retrying."
        }
        guard item?.status == "Rejected" else {
            return "This combined action is available for rejected WorkspaceEdit transactions."
        }
        guard conflictURI != nil else {
            return "Selected WorkspaceEdit has no \(conflictKind) open-tab conflict."
        }
        if let requestLabel {
            guard canRerun else {
                return cannotRerunToolTip(label: requestLabel, reason: item?.requestRetryUnavailableReason)
            }
            return nil
        }
        guard workspaceEditJSON != nil else {
            return "Original WorkspaceEdit payload is unavailable."
        }
        return nil
    }

    private static func saveUnavailableToolTip(
        for item: AttoWorkspaceEditHistoryPanelController.Item?
    ) -> String {
        guard item != nil else {
            return "Select a WorkspaceEdit history row with a saveable conflict."
        }
        guard item?.conflictCount ?? 0 > 0 else {
            return "Selected WorkspaceEdit has no conflicts."
        }
        return "Selected conflict cannot be resolved by saving an open tab."
    }

    private static func discardUnavailableToolTip(
        for item: AttoWorkspaceEditHistoryPanelController.Item?
    ) -> String {
        guard item != nil else {
            return "Select a WorkspaceEdit history row with a discardable conflict."
        }
        guard item?.conflictCount ?? 0 > 0 else {
            return "Selected WorkspaceEdit has no conflicts."
        }
        return "Selected conflict cannot be resolved by discarding an open tab."
    }

    private static func cannotRerunToolTip(label: String, reason: String?) -> String {
        if let reason, reason.isEmpty == false {
            return "Cannot rerun \(label): \(reason)"
        }
        return "Cannot rerun \(label): retry unavailable"
    }

    private static func displayName(for uri: String) -> String {
        guard let url = URL(string: uri), url.isFileURL, url.lastPathComponent.isEmpty == false else {
            return uri
        }
        return url.lastPathComponent
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value
    }
}
