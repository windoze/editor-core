import Foundation

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
