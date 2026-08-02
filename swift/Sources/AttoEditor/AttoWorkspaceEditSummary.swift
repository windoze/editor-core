import Foundation
import EditorCoreUIFFI

enum AttoWorkspaceEditPreviewDecision: Equatable {
    case apply
    case cancel
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
        let hasOverlappingEdits: Bool
        let versionMismatch: Bool
    }

    struct SkippedDetail: Equatable {
        let uri: String
        let reason: String
        let operation: String?
        let message: String
    }

    let applied: Bool
    let appliedEditCount: Int
    let appliedResourceOperationCount: Int
    let appliedURIs: [String]
    let documents: [Document]
    let skippedDetails: [SkippedDetail]
    let unsupportedOperationURIs: [String]
    var sections: [Section]

    init(
        result: EcuWorkspaceEditTransactionResult,
        parsedWorkspaceEdit: AttoWorkspaceEditParser.ParseResult? = nil
    ) {
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
        var previewDocuments = result.documents.map {
            Document(
                uri: $0.uri,
                editCount: $0.editCount,
                isOpen: $0.isOpen,
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
        skippedDetails = result.skippedDetails.map {
            SkippedDetail(
                uri: $0.uri,
                reason: $0.reason,
                operation: $0.operation,
                message: $0.message
            )
        }
        unsupportedOperationURIs = result.unsupportedOperationURIs
        sections = []
    }

    var affectedURIs: [String] {
        var seen = Set<String>()
        var uris: [String] = []
        for uri in documents.map(\.uri) + appliedURIs + skippedDetails.map(\.uri) + unsupportedOperationURIs {
            guard seen.insert(uri).inserted else { continue }
            uris.append(uri)
        }
        return uris
    }

    var requiresConfirmation: Bool {
        if appliedResourceOperationCount > 0 { return true }
        if affectedURIs.count > 1 { return true }
        if documents.contains(where: { $0.editCount > 0 && $0.isOpen == false }) { return true }
        if applied && (skippedDetails.isEmpty == false || unsupportedOperationURIs.isEmpty == false) {
            return true
        }
        return false
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

        let documentRows = previewRows()
        if documentRows.isEmpty == false {
            lines.append("")
            lines.append("Will affect:")
            lines.append(contentsOf: documentRows)
        }

        let skippedRows = skippedPreviewRows()
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

    private func skippedPreviewRows() -> [String] {
        var rows = skippedDetails.map { detail in
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

    fileprivate static func editCountText(_ count: Int) -> String {
        count == 1 ? "1 edit" : "\(count) edits"
    }

    fileprivate static func resourceOperationCountText(_ count: Int) -> String {
        count == 1 ? "1 resource operation" : "\(count) resource operations"
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

        for detail in preview.skippedDetails {
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

    let applied: Bool
    let appliedURI: String?
    let appliedEditCount: Int
    let skippedURIs: [String]
    let documents: [Document]

    init(
        applied: Bool,
        appliedURI: String?,
        appliedEditCount: Int,
        skippedURIs: [String],
        documents: [Document]
    ) {
        self.applied = applied
        self.appliedURI = appliedURI
        self.appliedEditCount = appliedEditCount
        self.skippedURIs = skippedURIs
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
            documents = []
            return
        }

        applied = Self.boolValue(obj["applied"]) ?? false
        appliedURI = obj["applied_uri"] as? String
        appliedEditCount = Self.intValue(obj["applied_edit_count"]) ?? 0
        skippedURIs = obj["skipped_uris"] as? [String] ?? []
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
        let skipped = Set(skippedURIs)
        return documents.filter { skipped.contains($0.uri) }
    }

    var appliedDocuments: [Document] {
        let skipped = Set(skippedURIs)
        return documents.filter { skipped.contains($0.uri) == false && $0.editCount > 0 }
    }

    var needsUserSummary: Bool {
        skippedURIs.isEmpty == false
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

        let docs = result.skippedDocuments.isEmpty
            ? result.skippedURIs.map {
                Document(uri: $0, editCount: 0, hasOverlappingEdits: false)
            }
            : result.skippedDocuments

        for doc in docs.sorted(by: { displayName(for: $0.uri) < displayName(for: $1.uri) }) {
            var suffix = doc.editCount > 0 ? " (\(editCountText(doc.editCount)))" : ""
            if doc.hasOverlappingEdits {
                suffix += " [overlapping edits]"
            }
            lines.append("- \(displayName(for: doc.uri))\(suffix)")
        }

        return lines.joined(separator: "\n")
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
