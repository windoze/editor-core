import Foundation
import EditorCoreUIFFI

enum AttoWorkspaceEditPreviewDecision: Equatable {
    case apply
    case cancel
    case openConflict(String)
    case saveConflict(String)
    case discardConflict(String)
    case saveAndRetry(String)
    case discardAndRetry(String)
}

struct AttoWorkspaceEditPreview: Equatable {
    struct Section: Equatable {
        let uri: String
        let title: String
        let subtitle: String
        let detailText: String
    }

    struct Document: Equatable {
        let uri: String
        let editCount: Int
        let isOpen: Bool
        let isDirty: Bool
        let hasOverlappingEdits: Bool
        let versionMismatch: Bool
    }

    struct SkippedDetail: Equatable {
        let uri: String
        let reason: String
        let operation: String?
        let message: String
    }

    struct Conflict: Equatable {
        let uri: String
        let kind: String
        let severity: String
        let applyImpact: String
        let resolution: String
        let reason: String
        let operation: String?
        let message: String
    }

    struct ConflictGroup: Equatable {
        let kind: String
        let operation: String?
        let conflicts: [Conflict]
    }

    let applyMode: String
    let applied: Bool
    let appliedEditCount: Int
    let appliedResourceOperationCount: Int
    let appliedURIs: [String]
    let documents: [Document]
    let conflicts: [Conflict]
    let skippedDetails: [SkippedDetail]
    let unsupportedOperationURIs: [String]
    var requestRetryDescriptor: AttoWorkspaceEditRequestRetryDescriptor?
    var sections: [Section]

    init(
        result: EcuWorkspaceEditTransactionResult,
        parsedWorkspaceEdit: AttoWorkspaceEditParser.ParseResult? = nil
    ) {
        applyMode = result.applyMode
        applied = result.applied
        let parsedEditCount = parsedWorkspaceEdit?.documents.reduce(0) { $0 + $1.edits.count } ?? 0
        appliedEditCount = max(result.appliedEditCount, parsedEditCount)
        if result.appliedResourceOperationCount > 0 || parsedWorkspaceEdit == nil {
            appliedResourceOperationCount = max(
                result.appliedResourceOperationCount,
                result.resourceOperations.count
            )
        } else {
            appliedResourceOperationCount = parsedWorkspaceEdit?.resourceOperations.count ?? 0
        }

        var previewAppliedURIs = result.appliedURIs
        let dirtyDocumentURIs = Set(result.dirtyDocumentURIs)
        var previewDocuments = result.documents.map {
            Document(
                uri: $0.uri,
                editCount: $0.editCount,
                isOpen: $0.isOpen,
                isDirty: $0.isDirty || dirtyDocumentURIs.contains($0.uri),
                hasOverlappingEdits: $0.hasOverlappingEdits,
                versionMismatch: $0.versionMismatch
            )
        }
        if let parsedWorkspaceEdit {
            let existingDocumentURIs = Set(previewDocuments.map(\.uri))
            for document in parsedWorkspaceEdit.documents where existingDocumentURIs.contains(document.uri) == false {
                previewDocuments.append(
                    Document(
                        uri: document.uri,
                        editCount: document.edits.count,
                        isOpen: false,
                        isDirty: dirtyDocumentURIs.contains(document.uri),
                        hasOverlappingEdits: document.hasOverlappingEdits,
                        versionMismatch: false
                    )
                )
            }
            for operation in parsedWorkspaceEdit.resourceOperations {
                previewAppliedURIs.append(contentsOf: operation.affectedURIs)
            }
        } else {
            for operation in result.resourceOperations {
                previewAppliedURIs.append(contentsOf: operation.affectedURIs)
            }
        }
        appliedURIs = Self.uniqueURIs(previewAppliedURIs)
        documents = previewDocuments
        conflicts = result.conflicts.map {
            Conflict(
                uri: $0.uri,
                kind: $0.kind,
                severity: $0.severity,
                applyImpact: $0.applyImpact,
                resolution: $0.resolution,
                reason: $0.reason,
                operation: $0.operation,
                message: $0.message
            )
        }
        skippedDetails = result.skippedDetails.map {
            SkippedDetail(
                uri: $0.uri,
                reason: $0.reason,
                operation: $0.operation,
                message: $0.message
            )
        }
        unsupportedOperationURIs = result.unsupportedOperationURIs
        requestRetryDescriptor = nil
        sections = []
    }

    var affectedURIs: [String] {
        var seen = Set<String>()
        var uris: [String] = []
        for uri in documents.map(\.uri) + appliedURIs + conflicts.map(\.uri) + skippedDetails.map(\.uri) + unsupportedOperationURIs {
            guard seen.insert(uri).inserted else { continue }
            uris.append(uri)
        }
        return uris
    }

    var requiresConfirmation: Bool {
        if appliedResourceOperationCount > 0 { return true }
        if conflicts.isEmpty == false { return true }
        if skippedDetails.isEmpty == false { return true }
        if unsupportedOperationURIs.isEmpty == false { return true }
        if affectedURIs.count > 1 { return true }
        if documents.contains(where: { $0.editCount > 0 && $0.isOpen == false }) { return true }
        return false
    }

    var applyButtonTitle: String {
        guard conflicts.isEmpty == false else { return "Apply" }
        if canApply == false {
            return "Resolve Conflicts First"
        }
        return "Apply Non-Conflicting Changes"
    }

    var canApply: Bool {
        hasBlockingConflicts == false
    }

    var firstConflictTargetURI: String? {
        conflicts.first { $0.uri.isEmpty == false }?.uri
    }

    var firstSaveableConflictTargetURI: String? {
        conflicts.first { Self.isSaveOrDiscardConflict($0) && $0.uri.isEmpty == false }?.uri
    }

    var firstDiscardableConflictTargetURI: String? {
        conflicts.first { Self.isSaveOrDiscardConflict($0) && $0.uri.isEmpty == false }?.uri
    }

    var conflictGroups: [ConflictGroup] {
        var groupsByKey: [String: [Conflict]] = [:]
        var groupMetadata: [String: (kind: String, operation: String?)] = [:]
        for conflict in conflicts {
            let key = Self.conflictGroupKey(kind: conflict.kind, operation: conflict.operation)
            groupsByKey[key, default: []].append(conflict)
            groupMetadata[key] = (conflict.kind, conflict.operation)
        }
        return groupsByKey.keys.sorted { lhs, rhs in
            let lhsMetadata = groupMetadata[lhs] ?? ("", nil)
            let rhsMetadata = groupMetadata[rhs] ?? ("", nil)
            return Self.conflictGroupSortKey(kind: lhsMetadata.kind, operation: lhsMetadata.operation)
                < Self.conflictGroupSortKey(kind: rhsMetadata.kind, operation: rhsMetadata.operation)
        }.map { key in
            let metadata = groupMetadata[key] ?? ("", nil)
            let conflicts = (groupsByKey[key] ?? []).sorted {
                Self.conflictSortKey($0) < Self.conflictSortKey($1)
            }
            return ConflictGroup(kind: metadata.kind, operation: metadata.operation, conflicts: conflicts)
        }
    }

    var panelSections: [Section] {
        if sections.isEmpty == false {
            return sections
        }
        return [
            Section(
                uri: "",
                title: "Summary",
                subtitle: summaryLine,
                detailText: displayText
            ),
        ]
    }

    var displayText: String {
        var lines: [String] = []
        lines.append("Workspace edit preview.")
        lines.append(summaryLine)

        if let conflictSummaryLine {
            lines.append(conflictSummaryLine)
        }
        if let requestRetrySummaryLine {
            lines.append(requestRetrySummaryLine)
        }

        let documentRows = previewRows()
        if documentRows.isEmpty == false {
            lines.append("")
            lines.append("Will affect:")
            lines.append(contentsOf: documentRows)
        }

        let conflictRows = conflictPreviewRows()
        if conflictRows.isEmpty == false {
            lines.append("")
            lines.append("Conflicts:")
            lines.append(contentsOf: conflictRows)
        }

        let skippedRows = skippedPreviewRows(excluding: conflictIdentities())
        if skippedRows.isEmpty == false {
            lines.append("")
            lines.append("Not applicable:")
            lines.append(contentsOf: skippedRows)
        }

        return lines.joined(separator: "\n")
    }

    private var summaryLine: String {
        let editText = Self.editCountText(appliedEditCount)
        let resourceText = Self.resourceOperationCountText(appliedResourceOperationCount)
        let documentText = Self.documentCountText(max(affectedURIs.count, documents.count, 1))
        if appliedResourceOperationCount > 0 {
            return "Will apply \(editText) and \(resourceText) across \(documentText)."
        }
        return "Will apply \(editText) across \(documentText)."
    }

    private var conflictSummaryLine: String? {
        guard conflicts.isEmpty == false else { return nil }
        let countText = Self.conflictCountText(conflicts.count)
        if hasBlockingConflicts {
            return "\(countText) will block atomic apply until resolved."
        }
        return "\(countText) will be skipped; non-conflicting changes remain applicable."
    }

    private var hasBlockingConflicts: Bool {
        if conflicts.contains(where: { $0.applyImpact == "blocks_atomic_apply" }) {
            return true
        }
        return applyMode == "atomic" && conflicts.isEmpty == false
    }

    private func previewRows() -> [String] {
        let documentsByURI = Dictionary(uniqueKeysWithValues: documents.map { ($0.uri, $0) })
        return affectedURIs.compactMap { uri in
            if skippedDetails.contains(where: { $0.uri == uri }) {
                return nil
            }
            if unsupportedOperationURIs.contains(uri) {
                return nil
            }

            var details: [String] = []
            if let document = documentsByURI[uri] {
                if document.editCount > 0 {
                    details.append(Self.editCountText(document.editCount))
                }
                if document.isOpen {
                    details.append("open")
                }
                if document.isDirty {
                    details.append("dirty")
                }
                if document.hasOverlappingEdits {
                    details.append("overlapping edits")
                }
                if document.versionMismatch {
                    details.append("version mismatch")
                }
            }
            if appliedURIs.contains(uri),
               documentsByURI[uri] == nil || details.isEmpty {
                details.append("resource operation")
            }
            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return "- \(Self.displayName(for: uri))\(suffix)"
        }.sorted()
    }

    private func conflictPreviewRows() -> [String] {
        var rows: [String] = []
        for group in conflictGroups {
            let groupTitle = Self.conflictGroupTitle(kind: group.kind, operation: group.operation)
            rows.append("- \(groupTitle): \(Self.conflictCountText(group.conflicts.count))")
            for conflict in group.conflicts {
                var details: [String] = []
                if conflict.reason.isEmpty == false {
                    details.append(conflict.reason)
                }
                let suffix = details.isEmpty ? "" : " [\(details.joined(separator: ": "))]"
                rows.append("  - \(Self.displayName(for: conflict.uri))\(suffix)")
            }
        }
        return rows
    }

    private func skippedPreviewRows(excluding excludedIdentities: Set<String>) -> [String] {
        var rows: [String] = skippedDetails.compactMap { detail -> String? in
            guard excludedIdentities.contains(Self.detailIdentity(
                uri: detail.uri,
                reason: detail.reason,
                operation: detail.operation
            )) == false else {
                return nil
            }
            var details: [String] = []
            if let operation = detail.operation, operation.isEmpty == false {
                details.append(operation)
            }
            if detail.reason.isEmpty == false {
                details.append(detail.reason)
            }
            let suffix = details.isEmpty ? "" : " [\(details.joined(separator: ": "))]"
            return "- \(Self.displayName(for: detail.uri))\(suffix)"
        }
        rows.append(contentsOf: unsupportedOperationURIs.map {
            "- \(Self.displayName(for: $0)) [unsupported operation]"
        })
        return rows.sorted()
    }

    fileprivate func conflictIdentities() -> Set<String> {
        Set(conflicts.map {
            Self.detailIdentity(uri: $0.uri, reason: $0.reason, operation: $0.operation)
        })
    }

    func conflictTargetURI(for section: Section?) -> String? {
        if let section,
           section.uri.isEmpty == false,
           conflicts.contains(where: { $0.uri == section.uri }) {
            return section.uri
        }
        return firstConflictTargetURI
    }

    func saveableConflictTargetURI(for section: Section?) -> String? {
        if let section,
           section.uri.isEmpty == false,
           conflicts.contains(where: { $0.uri == section.uri && Self.isSaveOrDiscardConflict($0) }) {
            return section.uri
        }
        return firstSaveableConflictTargetURI
    }

    func discardableConflictTargetURI(for section: Section?) -> String? {
        if let section,
           section.uri.isEmpty == false,
           conflicts.contains(where: { $0.uri == section.uri && Self.isSaveOrDiscardConflict($0) }) {
            return section.uri
        }
        return firstDiscardableConflictTargetURI
    }

    private static func isSaveOrDiscardConflict(_ conflict: Conflict) -> Bool {
        conflict.resolution == "save_or_discard" || conflict.kind == "dirty_document"
    }

    fileprivate static func editCountText(_ count: Int) -> String {
        count == 1 ? "1 edit" : "\(count) edits"
    }

    fileprivate static func resourceOperationCountText(_ count: Int) -> String {
        count == 1 ? "1 resource operation" : "\(count) resource operations"
    }

    fileprivate static func conflictCountText(_ count: Int) -> String {
        count == 1 ? "1 conflict" : "\(count) conflicts"
    }

    private static func documentCountText(_ count: Int) -> String {
        count == 1 ? "1 document" : "\(count) documents"
    }

    private static func uniqueURIs(_ uris: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for uri in uris where seen.insert(uri).inserted {
            result.append(uri)
        }
        return result
    }

    fileprivate static func displayName(for uri: String) -> String {
        if let url = URL(string: uri), url.isFileURL, url.lastPathComponent.isEmpty == false {
            return url.lastPathComponent
        }
        return uri
    }

    fileprivate static func detailIdentity(uri: String, reason: String, operation: String?) -> String {
        "\(uri)\u{1F}\(reason)\u{1F}\(operation ?? "")"
    }

    fileprivate static func conflictKindDisplayName(_ kind: String) -> String {
        switch kind {
        case "dirty_document":
            return "Dirty document"
        case "version":
            return "Version mismatch"
        case "overlap":
            return "Overlapping text edits"
        case "resource_dependency":
            return "Resource dependency"
        case "resource_target":
            return "Resource target"
        case "missing_resource":
            return "Missing resource"
        case "workspace_boundary":
            return "Workspace boundary"
        case "unsupported_uri":
            return "Unsupported URI"
        case "resource_options":
            return "Resource options"
        case "apply_failure":
            return "Apply failure"
        case "secondary_rollback_failure":
            return "Secondary rollback failure"
        case "", "other":
            return "Other conflict"
        default:
            return conflictTokenDisplayName(kind)
        }
    }

    fileprivate static func conflictGroupTitle(kind: String, operation: String?) -> String {
        let kindTitle = conflictKindDisplayName(kind)
        guard let operation, operation.isEmpty == false else {
            return kindTitle
        }
        return "\(kindTitle) \(conflictOperationDisplayName(operation))"
    }

    fileprivate static func conflictOperationDisplayName(_ operation: String) -> String {
        operation.replacingOccurrences(of: "_", with: " ")
    }

    fileprivate static func conflictApplyImpactDisplayName(_ applyImpact: String) -> String {
        switch applyImpact {
        case "blocks_atomic_apply":
            return "Blocks atomic apply"
        case "skips_change":
            return "Skipped change"
        case "":
            return "Skipped change"
        default:
            return conflictTokenDisplayName(applyImpact)
        }
    }

    fileprivate static func conflictResolutionHint(_ conflict: Conflict) -> String {
        switch conflict.resolution {
        case "save_or_discard":
            return "Save or discard the open tab changes, then run the action again."
        case "refresh_request":
            return "Refresh the language-server result or re-run the action against the current document version."
        case "recompute_edit":
            return "Request a new edit or apply smaller non-overlapping changes."
        case "resolve_dependency":
            return "Resolve the earlier resource operation conflict before applying dependent text edits."
        case "adjust_target":
            return "Rename, close, or remove the target file before retrying."
        case "restore_resource":
            return "Restore or open the target resource, then re-run the action."
        case "move_inside_workspace":
            return "Keep the operation inside the configured workspace root."
        case "unsupported":
            return "Only local file:// WorkspaceEdit resources are supported by this App path."
        case "adjust_options":
            return "Adjust the resource operation options before retrying."
        case "retry_after_io":
            return "Review the failure and retry after the file can be read or written."
        case "manual_recovery":
            return "Inspect the workspace and recover files or tabs manually before retrying."
        default:
            return conflictResolutionHintForKind(conflict.kind)
        }
    }

    private static func conflictResolutionHintForKind(_ kind: String) -> String {
        switch kind {
        case "dirty_document":
            return "Save or discard the open tab changes, then run the action again."
        case "version":
            return "Refresh the language-server result or re-run the action against the current document version."
        case "overlap":
            return "Request a new edit or apply smaller non-overlapping changes."
        case "resource_dependency":
            return "Resolve the earlier resource operation conflict before applying dependent text edits."
        case "resource_target":
            return "Rename, close, or remove the target file before retrying."
        case "missing_resource":
            return "Restore or open the target resource, then re-run the action."
        case "workspace_boundary":
            return "Keep the operation inside the configured workspace root."
        case "unsupported_uri":
            return "Only local file:// WorkspaceEdit resources are supported by this App path."
        case "resource_options":
            return "Adjust the resource operation options before retrying."
        case "apply_failure":
            return "Review the failure and retry after the file can be read or written."
        case "secondary_rollback_failure":
            return "Inspect the workspace and recover files or tabs manually before retrying."
        default:
            return "Review this conflict before retrying the WorkspaceEdit."
        }
    }

    private static func conflictGroupKey(kind: String, operation: String?) -> String {
        "\(kind)\u{1F}\(operation ?? "")"
    }

    private static func conflictGroupSortKey(kind: String, operation: String?) -> String {
        let rank = conflictKindRank(kind)
        return "\(String(format: "%02d", rank))|\(operation ?? "")|\(kind)"
    }

    private static func conflictSortKey(_ conflict: Conflict) -> String {
        "\(displayName(for: conflict.uri))|\(conflict.reason)|\(conflict.operation ?? "")"
    }

    private static func conflictKindRank(_ kind: String) -> Int {
        switch kind {
        case "dirty_document":
            return 0
        case "version":
            return 1
        case "overlap":
            return 2
        case "resource_dependency":
            return 3
        case "resource_target":
            return 4
        case "missing_resource":
            return 5
        case "workspace_boundary":
            return 6
        case "unsupported_uri":
            return 7
        case "resource_options":
            return 8
        case "apply_failure":
            return 9
        case "secondary_rollback_failure":
            return 10
        default:
            return 11
        }
    }

    private static func conflictTokenDisplayName(_ token: String) -> String {
        token
            .split(separator: "_")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}

enum AttoWorkspaceEditPreviewDetailBuilder {
    typealias TextProvider = (String) -> String?

    static func sections(
        preview: AttoWorkspaceEditPreview,
        workspaceEdit: AttoWorkspaceEditParser.ParseResult,
        textForURI: TextProvider
    ) -> [AttoWorkspaceEditPreview.Section] {
        let previewDocumentsByURI = Dictionary(uniqueKeysWithValues: preview.documents.map { ($0.uri, $0) })
        var sections: [AttoWorkspaceEditPreview.Section] = []

        for document in workspaceEdit.documents {
            let previewDocument = previewDocumentsByURI[document.uri]
            sections.append(documentSection(
                document,
                previewDocument: previewDocument,
                textForURI: textForURI
            ))
        }

        for operation in workspaceEdit.resourceOperations {
            sections.append(resourceOperationSection(operation))
        }

        for conflict in preview.conflicts {
            sections.append(conflictSection(conflict))
        }

        let conflictIdentities = preview.conflictIdentities()
        for detail in preview.skippedDetails where conflictIdentities.contains(
            AttoWorkspaceEditPreview.detailIdentity(
                uri: detail.uri,
                reason: detail.reason,
                operation: detail.operation
            )
        ) == false {
            sections.append(skippedSection(detail))
        }

        let unsupportedURIs = uniqueURIs(workspaceEdit.unsupportedURIs + preview.unsupportedOperationURIs)
        for uri in unsupportedURIs {
            sections.append(unsupportedSection(uri))
        }

        return sections
    }

    private static func documentSection(
        _ document: AttoWorkspaceEditParser.DocumentEdit,
        previewDocument: AttoWorkspaceEditPreview.Document?,
        textForURI: TextProvider
    ) -> AttoWorkspaceEditPreview.Section {
        let title = AttoWorkspaceEditPreview.displayName(for: document.uri)
        let subtitle = documentSubtitle(document, previewDocument: previewDocument)
        let detailText = documentDetailText(
            document,
            title: title,
            previewDocument: previewDocument,
            textForURI: textForURI
        )
        return AttoWorkspaceEditPreview.Section(
            uri: document.uri,
            title: title,
            subtitle: subtitle,
            detailText: detailText
        )
    }

    private static func documentSubtitle(
        _ document: AttoWorkspaceEditParser.DocumentEdit,
        previewDocument: AttoWorkspaceEditPreview.Document?
    ) -> String {
        var parts = [AttoWorkspaceEditPreview.editCountText(document.edits.count)]
        if previewDocument?.isOpen == true {
            parts.append("open")
        } else {
            parts.append("unopened")
        }
        if previewDocument?.isDirty == true {
            parts.append("dirty")
        }
        if document.hasOverlappingEdits || previewDocument?.hasOverlappingEdits == true {
            parts.append("overlapping edits")
        }
        if previewDocument?.versionMismatch == true {
            parts.append("version mismatch")
        }
        return parts.joined(separator: ", ")
    }

    private static func documentDetailText(
        _ document: AttoWorkspaceEditParser.DocumentEdit,
        title: String,
        previewDocument: AttoWorkspaceEditPreview.Document?,
        textForURI: TextProvider
    ) -> String {
        var lines = detailHeader(title: title, uri: document.uri, subtitle: documentSubtitle(
            document,
            previewDocument: previewDocument
        ))

        guard document.edits.isEmpty == false else {
            lines.append("No text edits.")
            return lines.joined(separator: "\n")
        }

        if document.hasOverlappingEdits || previewDocument?.hasOverlappingEdits == true {
            lines.append("Diff unavailable: document has overlapping edits.")
            return lines.joined(separator: "\n")
        }

        guard let oldText = textForURI(document.uri) else {
            lines.append("Diff unavailable: document text was not available.")
            return lines.joined(separator: "\n")
        }

        guard let result = AttoWorkspaceEditParser.apply(document, to: oldText) else {
            lines.append("Diff unavailable: edit range is outside the current document.")
            return lines.joined(separator: "\n")
        }

        lines.append(lineDiff(oldText: oldText, newText: result.text, title: title))
        return lines.joined(separator: "\n")
    }

    private static func resourceOperationSection(
        _ operation: AttoWorkspaceEditParser.ResourceOperation
    ) -> AttoWorkspaceEditPreview.Section {
        switch operation {
        case .create(let create):
            let title = AttoWorkspaceEditPreview.displayName(for: create.uri)
            let subtitle = "create file"
            let detail = detailHeader(title: title, uri: create.uri, subtitle: subtitle) + [
                "Create file",
                "overwrite: \(create.overwrite)",
                "ignoreIfExists: \(create.ignoreIfExists)",
            ]
            return AttoWorkspaceEditPreview.Section(
                uri: create.uri,
                title: title,
                subtitle: subtitle,
                detailText: detail.joined(separator: "\n")
            )
        case .rename(let rename):
            let title = "\(AttoWorkspaceEditPreview.displayName(for: rename.oldURI)) -> \(AttoWorkspaceEditPreview.displayName(for: rename.newURI))"
            let subtitle = "rename file"
            let detail = detailHeader(title: title, uri: rename.oldURI, subtitle: subtitle) + [
                "Rename file",
                "from: \(rename.oldURI)",
                "to: \(rename.newURI)",
                "overwrite: \(rename.overwrite)",
                "ignoreIfExists: \(rename.ignoreIfExists)",
            ]
            return AttoWorkspaceEditPreview.Section(
                uri: rename.oldURI,
                title: title,
                subtitle: subtitle,
                detailText: detail.joined(separator: "\n")
            )
        case .delete(let delete):
            let title = AttoWorkspaceEditPreview.displayName(for: delete.uri)
            let subtitle = "delete file"
            let detail = detailHeader(title: title, uri: delete.uri, subtitle: subtitle) + [
                "Delete file",
                "recursive: \(delete.recursive)",
                "ignoreIfNotExists: \(delete.ignoreIfNotExists)",
            ]
            return AttoWorkspaceEditPreview.Section(
                uri: delete.uri,
                title: title,
                subtitle: subtitle,
                detailText: detail.joined(separator: "\n")
            )
        }
    }

    private static func conflictSection(
        _ conflict: AttoWorkspaceEditPreview.Conflict
    ) -> AttoWorkspaceEditPreview.Section {
        let title = AttoWorkspaceEditPreview.displayName(for: conflict.uri)
        let subtitle = [
            AttoWorkspaceEditPreview.conflictKindDisplayName(conflict.kind),
            conflict.operation.map { AttoWorkspaceEditPreview.conflictOperationDisplayName($0) },
            conflict.reason,
        ]
            .compactMap { value in
                guard let value, value.isEmpty == false else { return nil }
                return value
            }
            .joined(separator: ": ")
        let detailLines = detailHeader(title: title, uri: conflict.uri, subtitle: "conflict") + [
            "Category: \(AttoWorkspaceEditPreview.conflictKindDisplayName(conflict.kind))",
            "Severity: \(conflict.severity.isEmpty ? "warning" : conflict.severity)",
            "Apply impact: \(AttoWorkspaceEditPreview.conflictApplyImpactDisplayName(conflict.applyImpact))",
            "Kind: \(conflict.kind.isEmpty ? "other" : conflict.kind)",
            "Operation: \(conflict.operation ?? "unknown")",
            "Reason: \(conflict.reason.isEmpty ? "unknown" : conflict.reason)",
            "Message: \(conflict.message.isEmpty ? "No detail." : conflict.message)",
            "Suggested action: \(AttoWorkspaceEditPreview.conflictResolutionHint(conflict))",
        ]
        return AttoWorkspaceEditPreview.Section(
            uri: conflict.uri,
            title: title,
            subtitle: subtitle.isEmpty ? "conflict" : subtitle,
            detailText: detailLines.joined(separator: "\n")
        )
    }

    private static func skippedSection(
        _ detail: AttoWorkspaceEditPreview.SkippedDetail
    ) -> AttoWorkspaceEditPreview.Section {
        let title = AttoWorkspaceEditPreview.displayName(for: detail.uri)
        let subtitle = [detail.operation, detail.reason]
            .compactMap { value in
                guard let value, value.isEmpty == false else { return nil }
                return value
            }
            .joined(separator: ": ")
        let detailLines = detailHeader(title: title, uri: detail.uri, subtitle: "not applicable") + [
            "Operation: \(detail.operation ?? "unknown")",
            "Reason: \(detail.reason.isEmpty ? "unknown" : detail.reason)",
            "Message: \(detail.message.isEmpty ? "No detail." : detail.message)",
        ]
        return AttoWorkspaceEditPreview.Section(
            uri: detail.uri,
            title: title,
            subtitle: subtitle.isEmpty ? "not applicable" : subtitle,
            detailText: detailLines.joined(separator: "\n")
        )
    }

    private static func unsupportedSection(_ uri: String) -> AttoWorkspaceEditPreview.Section {
        let title = AttoWorkspaceEditPreview.displayName(for: uri)
        let detail = detailHeader(title: title, uri: uri, subtitle: "unsupported operation") + [
            "This WorkspaceEdit operation is not supported by the current App path.",
        ]
        return AttoWorkspaceEditPreview.Section(
            uri: uri,
            title: title,
            subtitle: "unsupported operation",
            detailText: detail.joined(separator: "\n")
        )
    }

    private static func detailHeader(title: String, uri: String, subtitle: String) -> [String] {
        [
            title,
            subtitle,
            uri,
            "",
        ]
    }

    private static func lineDiff(oldText: String, newText: String, title: String) -> String {
        guard oldText != newText else { return "No visible text change." }

        let oldLines = splitLines(oldText)
        let newLines = splitLines(newText)
        var prefix = 0
        while prefix < oldLines.count,
              prefix < newLines.count,
              oldLines[prefix] == newLines[prefix]
        {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldLines.count - prefix,
              suffix < newLines.count - prefix,
              oldLines[oldLines.count - suffix - 1] == newLines[newLines.count - suffix - 1]
        {
            suffix += 1
        }

        let oldChangeEnd = oldLines.count - suffix
        let newChangeEnd = newLines.count - suffix
        let context = 3
        let contextStart = max(0, prefix - context)
        let contextEnd = min(oldLines.count, oldChangeEnd + context)

        var lines: [String] = []
        lines.append("--- \(title)")
        lines.append("+++ \(title)")
        lines.append("@@ line \(contextStart + 1) @@")

        if contextStart > 0 {
            lines.append(" ...")
        }
        if contextStart < prefix {
            for index in contextStart..<prefix {
                lines.append(" \(oldLines[index])")
            }
        }
        if prefix < oldChangeEnd {
            for index in prefix..<oldChangeEnd {
                lines.append("-\(oldLines[index])")
            }
        }
        if prefix < newChangeEnd {
            for index in prefix..<newChangeEnd {
                lines.append("+\(newLines[index])")
            }
        }
        if oldChangeEnd < contextEnd {
            for index in oldChangeEnd..<contextEnd {
                lines.append(" \(oldLines[index])")
            }
        }
        if contextEnd < oldLines.count {
            lines.append(" ...")
        }

        return limitedLines(lines).joined(separator: "\n")
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func limitedLines(_ lines: [String], maxLineCount: Int = 160) -> [String] {
        guard lines.count > maxLineCount else { return lines }
        var result = Array(lines.prefix(maxLineCount))
        result.append("... diff truncated ...")
        return result
    }

    private static func uniqueURIs(_ uris: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for uri in uris where seen.insert(uri).inserted {
            result.append(uri)
        }
        return result
    }
}

struct AttoWorkspaceEditApplyResult: Equatable {
    struct Document: Equatable {
        let uri: String
        let editCount: Int
        let hasOverlappingEdits: Bool
    }

    struct SkippedDetail: Equatable {
        let uri: String
        let reason: String
        let operation: String?
    }

    let applied: Bool
    let appliedURI: String?
    let appliedEditCount: Int
    let skippedURIs: [String]
    let skippedDetails: [SkippedDetail]
    let unsupportedURIs: [String]
    let documents: [Document]

    init(
        applied: Bool,
        appliedURI: String?,
        appliedEditCount: Int,
        skippedURIs: [String],
        skippedDetails: [SkippedDetail] = [],
        unsupportedURIs: [String] = [],
        documents: [Document]
    ) {
        self.applied = applied
        self.appliedURI = appliedURI
        self.appliedEditCount = appliedEditCount
        self.skippedURIs = skippedURIs
        self.skippedDetails = skippedDetails
        self.unsupportedURIs = unsupportedURIs
        self.documents = documents
    }

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        else {
            applied = false
            appliedURI = nil
            appliedEditCount = 0
            skippedURIs = []
            skippedDetails = []
            unsupportedURIs = []
            documents = []
            return
        }

        applied = Self.boolValue(obj["applied"]) ?? false
        appliedURI = obj["applied_uri"] as? String
        appliedEditCount = Self.intValue(obj["applied_edit_count"]) ?? 0
        skippedURIs = obj["skipped_uris"] as? [String] ?? []
        skippedDetails = (obj["skipped_details"] as? [[String: Any]] ?? []).compactMap { detail in
            guard let uri = detail["uri"] as? String else { return nil }
            return SkippedDetail(
                uri: uri,
                reason: detail["reason"] as? String ?? "",
                operation: detail["operation"] as? String
            )
        }
        unsupportedURIs = obj["unsupported_operation_uris"] as? [String] ?? []
        documents = (obj["documents"] as? [[String: Any]] ?? []).compactMap { doc in
            guard let uri = doc["uri"] as? String else { return nil }
            return Document(
                uri: uri,
                editCount: Self.intValue(doc["edit_count"]) ?? 0,
                hasOverlappingEdits: Self.boolValue(doc["has_overlapping_edits"]) ?? false
            )
        }
    }

    var skippedDocuments: [Document] {
        let notApplied = notAppliedURISet
        return documents.filter { notApplied.contains($0.uri) }
    }

    var appliedDocuments: [Document] {
        let notApplied = notAppliedURISet
        return documents.filter { notApplied.contains($0.uri) == false && $0.editCount > 0 }
    }

    var needsUserSummary: Bool {
        skippedURIs.isEmpty == false || skippedDetails.isEmpty == false || unsupportedURIs.isEmpty == false
    }

    private var notAppliedURISet: Set<String> {
        Set(skippedURIs)
            .union(skippedDetails.map(\.uri))
            .union(unsupportedURIs)
    }

    static func displayText(for result: AttoWorkspaceEditApplyResult) -> String? {
        guard result.needsUserSummary else { return nil }

        var lines: [String] = []
        if result.applied {
            let count = editCountText(result.appliedEditCount)
            let documentCount = documentCountText(max(result.appliedDocuments.count, 1))
            lines.append("Workspace edit partially applied.")
            lines.append("Applied \(count) across \(documentCount).")
            lines.append("")
            lines.append("Not applied:")
        } else {
            lines.append("Workspace edit was not applied.")
            lines.append("No edits were applied.")
            lines.append("")
            lines.append("Affected documents:")
        }

        let notAppliedURIs = Array(result.notAppliedURISet).sorted()
        let docs = result.skippedDocuments.isEmpty
            ? notAppliedURIs.map {
                Document(uri: $0, editCount: 0, hasOverlappingEdits: false)
            }
            : result.skippedDocuments

        let unsupported = Set(result.unsupportedURIs)
        for doc in docs.sorted(by: { displayName(for: $0.uri) < displayName(for: $1.uri) }) {
            var suffix = doc.editCount > 0 ? " (\(editCountText(doc.editCount)))" : ""
            if doc.hasOverlappingEdits {
                suffix += " [overlapping edits]"
            }
            if unsupported.contains(doc.uri) {
                suffix += " [unsupported operation]"
            }
            for skippedDetail in result.skippedDetailSuffixes(for: doc.uri) {
                suffix += " [\(skippedDetail)]"
            }
            lines.append("- \(displayName(for: doc.uri))\(suffix)")
        }

        return lines.joined(separator: "\n")
    }

    private func skippedDetailSuffixes(for uri: String) -> [String] {
        skippedDetails
            .filter { $0.uri == uri }
            .compactMap { detail in
                let operation = detail.operation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let reason = detail.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if operation.isEmpty {
                    return reason.isEmpty ? nil : reason
                }
                if reason.isEmpty {
                    return operation
                }
                return "\(operation): \(reason)"
            }
    }

    private static func editCountText(_ count: Int) -> String {
        count == 1 ? "1 edit" : "\(count) edits"
    }

    private static func documentCountText(_ count: Int) -> String {
        count == 1 ? "1 document" : "\(count) documents"
    }

    private static func displayName(for uri: String) -> String {
        if let url = URL(string: uri), url.isFileURL, url.lastPathComponent.isEmpty == false {
            return url.lastPathComponent
        }
        return uri
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
