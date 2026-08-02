import CEditorCoreUIFFI
import Foundation

public struct EcuMultiDocumentTabSnapshot: Decodable, Equatable, Sendable {
    public let id: UInt64
    public let title: String?
    public let documentURI: String?
    public let isPreview: Bool
    public let isActive: Bool
    public let isModified: Bool
    public let viewCount: UInt32
    public let activeViewIndex: UInt32

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case documentURI = "document_uri"
        case isPreview = "is_preview"
        case isActive = "is_active"
        case isModified = "is_modified"
        case viewCount = "view_count"
        case activeViewIndex = "active_view_index"
    }
}

public struct EcuMultiDocumentSnapshot: Decodable, Equatable, Sendable {
    public let activeTabId: UInt64?
    public let workspaceRoots: [String]
    public let tabs: [EcuMultiDocumentTabSnapshot]

    private enum CodingKeys: String, CodingKey {
        case activeTabId = "active_tab_id"
        case workspaceRoots = "workspace_roots"
        case tabs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeTabId = try container.decodeIfPresent(UInt64.self, forKey: .activeTabId)
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        tabs = try container.decodeIfPresent([EcuMultiDocumentTabSnapshot].self, forKey: .tabs) ?? []
    }
}

public struct EcuTabSearchMatch: Decodable, Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32
}

public struct EcuTabSearchResult: Decodable, Equatable, Sendable {
    public let tabId: UInt64
    public let matches: [EcuTabSearchMatch]

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case matches
    }
}

private struct EcuTabSearchResponse: Decodable {
    let results: [EcuTabSearchResult]
}

public struct EcuWorkspaceEditTransactionDocument: Decodable, Equatable, Sendable {
    public let uri: String
    public let editCount: Int
    public let hasOverlappingEdits: Bool
    public let expectedVersion: Int?
    public let actualVersion: UInt64?
    public let versionMismatch: Bool
    public let isOpen: Bool
    public let isDirty: Bool
    public let tabId: UInt64?

    private enum CodingKeys: String, CodingKey {
        case uri
        case editCount = "edit_count"
        case hasOverlappingEdits = "has_overlapping_edits"
        case expectedVersion = "expected_version"
        case actualVersion = "actual_version"
        case versionMismatch = "version_mismatch"
        case isOpen = "is_open"
        case isDirty = "is_dirty"
        case tabId = "tab_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        editCount = try container.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        hasOverlappingEdits = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasOverlappingEdits
        ) ?? false
        expectedVersion = try container.decodeIfPresent(Int.self, forKey: .expectedVersion)
        actualVersion = try container.decodeIfPresent(UInt64.self, forKey: .actualVersion)
        versionMismatch = try container.decodeIfPresent(Bool.self, forKey: .versionMismatch)
            ?? false
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
        isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        tabId = try container.decodeIfPresent(UInt64.self, forKey: .tabId)
    }
}

public struct EcuWorkspaceEditTransactionSkippedDetail: Decodable, Equatable, Sendable {
    public let uri: String
    public let reason: String
    public let operation: String?
    public let message: String
}

public struct EcuWorkspaceEditTransactionConflict: Decodable, Equatable, Sendable {
    public let uri: String
    public let kind: String
    public let reason: String
    public let operation: String?
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case uri
        case kind
        case reason
        case operation
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}

public struct EcuWorkspaceEditTransactionResourceOperation: Decodable, Equatable, Sendable {
    public let kind: String
    public let uri: String?
    public let oldURI: String?
    public let newURI: String?
    public let affectedURIs: [String]
    public let supported: Bool
    public let applied: Bool

    private enum CodingKeys: String, CodingKey {
        case kind
        case uri
        case oldURI = "old_uri"
        case newURI = "new_uri"
        case affectedURIs = "affected_uris"
        case supported
        case applied
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        oldURI = try container.decodeIfPresent(String.self, forKey: .oldURI)
        newURI = try container.decodeIfPresent(String.self, forKey: .newURI)
        affectedURIs = try container.decodeIfPresent([String].self, forKey: .affectedURIs) ?? []
        supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied) ?? false
    }
}

public struct EcuWorkspaceEditTransactionResult: Decodable, Equatable, Sendable {
    public let mode: String
    public let applyMode: String
    public let applied: Bool
    public let appliedURI: String?
    public let appliedURIs: [String]
    public let appliedEditCount: Int
    public let appliedResourceOperationCount: Int
    public let resourceOperations: [EcuWorkspaceEditTransactionResourceOperation]
    public let dirtyDocumentURIs: [String]
    public let conflicts: [EcuWorkspaceEditTransactionConflict]
    public let skippedURIs: [String]
    public let skippedDetails: [EcuWorkspaceEditTransactionSkippedDetail]
    public let unsupportedOperationURIs: [String]
    public let documents: [EcuWorkspaceEditTransactionDocument]

    private enum CodingKeys: String, CodingKey {
        case mode
        case applyMode = "apply_mode"
        case applied
        case appliedURI = "applied_uri"
        case appliedURIs = "applied_uris"
        case appliedEditCount = "applied_edit_count"
        case appliedResourceOperationCount = "applied_resource_operation_count"
        case resourceOperations = "resource_operations"
        case dirtyDocumentURIs = "dirty_document_uris"
        case conflicts
        case skippedURIs = "skipped_uris"
        case skippedDetails = "skipped_details"
        case unsupportedOperationURIs = "unsupported_operation_uris"
        case documents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        applyMode = try container.decodeIfPresent(String.self, forKey: .applyMode) ?? "partial"
        applied = try container.decode(Bool.self, forKey: .applied)
        appliedURI = try container.decodeIfPresent(String.self, forKey: .appliedURI)
        appliedURIs = try container.decodeIfPresent([String].self, forKey: .appliedURIs) ?? []
        appliedEditCount = try container.decodeIfPresent(Int.self, forKey: .appliedEditCount) ?? 0
        appliedResourceOperationCount = try container.decodeIfPresent(
            Int.self,
            forKey: .appliedResourceOperationCount
        ) ?? 0
        resourceOperations = try container.decodeIfPresent(
            [EcuWorkspaceEditTransactionResourceOperation].self,
            forKey: .resourceOperations
        ) ?? []
        dirtyDocumentURIs = try container.decodeIfPresent(
            [String].self,
            forKey: .dirtyDocumentURIs
        ) ?? []
        conflicts = try container.decodeIfPresent(
            [EcuWorkspaceEditTransactionConflict].self,
            forKey: .conflicts
        ) ?? []
        skippedURIs = try container.decodeIfPresent([String].self, forKey: .skippedURIs) ?? []
        skippedDetails = try container.decodeIfPresent(
            [EcuWorkspaceEditTransactionSkippedDetail].self,
            forKey: .skippedDetails
        ) ?? []
        unsupportedOperationURIs = try container.decodeIfPresent(
            [String].self,
            forKey: .unsupportedOperationURIs
        ) ?? []
        documents = try container.decodeIfPresent(
            [EcuWorkspaceEditTransactionDocument].self,
            forKey: .documents
        ) ?? []
    }
}

public struct EcuWorkspaceEditTransactionEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let operation: String
    public let result: EcuWorkspaceEditTransactionResult
}

public struct EcuWorkspaceEditTransactionEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuWorkspaceEditTransactionEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuWorkspaceDiagnosticTarget: Decodable, Equatable, Sendable {
    public let uri: String
    public let line: UInt32
    public let utf16Character: UInt32

    private enum CodingKeys: String, CodingKey {
        case uri
        case line
        case utf16Character = "utf16_character"
    }
}

public struct EcuWorkspaceDiagnostic: Decodable, Equatable, Sendable {
    public let target: EcuWorkspaceDiagnosticTarget
    public let endLine: UInt32
    public let endUTF16Character: UInt32
    public let severity: UInt32?
    public let severityLabel: String?
    public let code: String?
    public let source: String?
    public let message: String
    public let resultId: String?

    private enum CodingKeys: String, CodingKey {
        case target
        case endLine = "end_line"
        case endUTF16Character = "end_utf16_character"
        case severity
        case severityLabel = "severity_label"
        case code
        case source
        case message
        case resultId = "result_id"
    }
}

public struct EcuWorkspaceDiagnosticDocumentReport: Decodable, Equatable, Sendable {
    public let uri: String
    public let kind: String
    public let resultId: String?
    public let diagnostics: [EcuWorkspaceDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case uri
        case kind
        case resultId = "result_id"
        case diagnostics
    }
}

public struct EcuWorkspaceDiagnosticsSnapshot: Decodable, Equatable, Sendable {
    public let documents: [EcuWorkspaceDiagnosticDocumentReport]
    public let diagnostics: [EcuWorkspaceDiagnostic]
}

public struct EcuWorkspaceDiagnosticMarker: Decodable, Equatable, Sendable {
    public let uri: String
    public let line: UInt32
    public let utf16Character: UInt32
    public let severity: UInt32?
    public let severityLabel: String?

    public init(
        uri: String,
        line: UInt32,
        utf16Character: UInt32,
        severity: UInt32?,
        severityLabel: String?
    ) {
        self.uri = uri
        self.line = line
        self.utf16Character = utf16Character
        self.severity = severity
        self.severityLabel = severityLabel
    }

    private enum CodingKeys: String, CodingKey {
        case uri
        case line
        case utf16Character = "utf16_character"
        case severity
        case severityLabel = "severity_label"
    }
}

public struct EcuWorkspaceDiagnosticMarkersSnapshot: Decodable, Equatable, Sendable {
    public let markers: [EcuWorkspaceDiagnosticMarker]
}

public struct EcuWorkspaceDiagnosticsEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let family: String
    public let title: String
    public let operation: String
    public let documentCount: Int
    public let diagnosticCount: Int
    public let markerCount: Int

    private enum CodingKeys: String, CodingKey {
        case sequence
        case family
        case title
        case operation
        case documentCount = "document_count"
        case diagnosticCount = "diagnostic_count"
        case markerCount = "marker_count"
    }
}

public struct EcuWorkspaceDiagnosticsEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuWorkspaceDiagnosticsEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuMultiDocumentLSPResultEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let tabId: UInt64
    public let viewIndex: Int
    public let viewId: UInt64
    public let sourceSequence: UInt64
    public let family: String
    public let title: String
    public let slot: String
    public let method: String
    public let requestId: UInt64
    public let status: String
    public let hasResult: Bool
    public let resultJSONLength: Int
    public let errorCode: Int64?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case sequence
        case tabId = "tab_id"
        case viewIndex = "view_index"
        case viewId = "view_id"
        case sourceSequence = "source_sequence"
        case family
        case title
        case slot
        case method
        case requestId = "request_id"
        case status
        case hasResult = "has_result"
        case resultJSONLength = "result_json_len"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

public struct EcuMultiDocumentLSPResultEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuMultiDocumentLSPResultEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuMultiDocumentLSPRequestEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let tabId: UInt64
    public let viewIndex: Int
    public let viewId: UInt64
    public let sourceSequence: UInt64
    public let sourceResultSequence: UInt64?
    public let family: String
    public let title: String
    public let slot: String
    public let method: String
    public let requestId: UInt64
    public let phase: String
    public let status: String
    public let errorCode: Int64?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case sequence
        case tabId = "tab_id"
        case viewIndex = "view_index"
        case viewId = "view_id"
        case sourceSequence = "source_sequence"
        case sourceResultSequence = "source_result_sequence"
        case family
        case title
        case slot
        case method
        case requestId = "request_id"
        case phase
        case status
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

public struct EcuMultiDocumentLSPRequestEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuMultiDocumentLSPRequestEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public struct EcuMultiDocumentStateEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let tabId: UInt64
    public let viewIndex: Int
    public let viewId: UInt64
    public let sourceSequence: UInt64
    public let kind: String
    public let family: String
    public let title: String
    public let stateEvent: EcuEditorUIStateEvent

    private enum CodingKeys: String, CodingKey {
        case sequence
        case tabId = "tab_id"
        case viewIndex = "view_index"
        case viewId = "view_id"
        case sourceSequence = "source_sequence"
        case kind
        case family
        case title
        case stateEvent = "state_event"
    }
}

public struct EcuMultiDocumentStateEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuMultiDocumentStateEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}

public final class MultiDocumentEditorUI {
    public let library: EditorCoreUIFFILibrary
    private let handle: OpaquePointer

    public init(library: EditorCoreUIFFILibrary) throws {
        self.library = library
        guard let ptr = editor_core_ui_ffi_multi_document_new() else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "multi_document_new",
                message: library.lastErrorMessageString()
            )
        }
        self.handle = ptr
    }

    deinit {
        editor_core_ui_ffi_multi_document_free(handle)
    }

    public func openTab(text: String, viewportWidthCells: UInt32 = 120) throws -> UInt64 {
        var tabId: UInt64 = 0
        let status = text.withCString { textPtr in
            editor_core_ui_ffi_multi_document_open_tab(handle, textPtr, viewportWidthCells, &tabId)
        }
        try library.ensureStatus(status, context: "multi_document_open_tab")
        return tabId
    }

    public func openPreviewTab(text: String, viewportWidthCells: UInt32 = 120) throws -> UInt64 {
        var tabId: UInt64 = 0
        let status = text.withCString { textPtr in
            editor_core_ui_ffi_multi_document_open_preview_tab(handle, textPtr, viewportWidthCells, &tabId)
        }
        try library.ensureStatus(status, context: "multi_document_open_preview_tab")
        return tabId
    }

    public func activeTabId() throws -> UInt64? {
        var hasActive: UInt8 = 0
        var tabId: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_active_tab_id(handle, &hasActive, &tabId)
        try library.ensureStatus(status, context: "multi_document_active_tab_id")
        return hasActive == 0 ? nil : tabId
    }

    public func snapshotJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_multi_document_snapshot_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "multi_document_snapshot_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func snapshot() throws -> EcuMultiDocumentSnapshot {
        try decode(EcuMultiDocumentSnapshot.self, from: snapshotJSON(), context: "multi_document_snapshot_decode")
    }

    public func setWorkspaceRoots(_ roots: [String]) throws {
        let data = try JSONEncoder().encode(roots)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "multi_document_set_workspace_roots_encode",
                message: "failed to encode workspace roots JSON"
            )
        }
        let status = json.withCString { rootsPtr in
            editor_core_ui_ffi_multi_document_set_workspace_roots_json(handle, rootsPtr)
        }
        try library.ensureStatus(status, context: "multi_document_set_workspace_roots_json")
    }

    public func setActiveTab(_ tabId: UInt64) throws {
        let status = editor_core_ui_ffi_multi_document_set_active_tab(handle, tabId)
        try library.ensureStatus(status, context: "multi_document_set_active_tab")
    }

    public func setTabTitle(_ title: String?, tabId: UInt64) throws {
        let status: Int32
        if let title {
            status = title.withCString { titlePtr in
                editor_core_ui_ffi_multi_document_set_tab_title(handle, tabId, titlePtr)
            }
        } else {
            status = editor_core_ui_ffi_multi_document_set_tab_title(handle, tabId, nil)
        }
        try library.ensureStatus(status, context: "multi_document_set_tab_title")
    }

    public func tabDocumentURI(tabId: UInt64) throws -> String? {
        var out: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_multi_document_tab_document_uri(handle, tabId, &out)
        try library.ensureStatus(status, context: "multi_document_tab_document_uri")
        guard let out else { return nil }
        defer { editor_core_ui_ffi_string_free(out) }
        return String(cString: out)
    }

    public func setTabDocumentURI(_ documentURI: String?, tabId: UInt64) throws {
        let status: Int32
        if let documentURI {
            status = documentURI.withCString { uriPtr in
                editor_core_ui_ffi_multi_document_set_tab_document_uri(handle, tabId, uriPtr)
            }
        } else {
            status = editor_core_ui_ffi_multi_document_set_tab_document_uri(handle, tabId, nil)
        }
        try library.ensureStatus(status, context: "multi_document_set_tab_document_uri")
    }

    public func isPreviewTab(_ tabId: UInt64) throws -> Bool {
        var raw: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_is_preview_tab(handle, tabId, &raw)
        try library.ensureStatus(status, context: "multi_document_is_preview_tab")
        return raw != 0
    }

    public func pinTab(_ tabId: UInt64) throws {
        let status = editor_core_ui_ffi_multi_document_pin_tab(handle, tabId)
        try library.ensureStatus(status, context: "multi_document_pin_tab")
    }

    @discardableResult
    public func closeTab(_ tabId: UInt64) throws -> Bool {
        var closed: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_close_tab(handle, tabId, &closed)
        try library.ensureStatus(status, context: "multi_document_close_tab")
        return closed != 0
    }

    public func closeAllTabs() throws {
        let status = editor_core_ui_ffi_multi_document_close_all_tabs(handle)
        try library.ensureStatus(status, context: "multi_document_close_all_tabs")
    }

    @discardableResult
    public func closeOtherTabs(keeping tabId: UInt64) throws -> UInt32 {
        var closed: UInt32 = 0
        let status = editor_core_ui_ffi_multi_document_close_other_tabs(handle, tabId, &closed)
        try library.ensureStatus(status, context: "multi_document_close_other_tabs")
        return closed
    }

    @discardableResult
    public func closeTabsToRight(of tabId: UInt64) throws -> UInt32 {
        var closed: UInt32 = 0
        let status = editor_core_ui_ffi_multi_document_close_tabs_to_right(handle, tabId, &closed)
        try library.ensureStatus(status, context: "multi_document_close_tabs_to_right")
        return closed
    }

    @discardableResult
    public func moveTab(fromIndex: UInt32, toIndex: UInt32) throws -> Bool {
        var moved: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_move_tab_index(handle, fromIndex, toIndex, &moved)
        try library.ensureStatus(status, context: "multi_document_move_tab_index")
        return moved != 0
    }

    @discardableResult
    public func splitTab(_ tabId: UInt64, viewportWidthCells: UInt32 = 120) throws -> UInt32 {
        var viewIndex: UInt32 = 0
        let status = editor_core_ui_ffi_multi_document_split_tab(handle, tabId, viewportWidthCells, &viewIndex)
        try library.ensureStatus(status, context: "multi_document_split_tab")
        return viewIndex
    }

    public func setActiveViewIndex(tabId: UInt64, viewIndex: UInt32) throws {
        let status = editor_core_ui_ffi_multi_document_set_active_view_index(handle, tabId, viewIndex)
        try library.ensureStatus(status, context: "multi_document_set_active_view_index")
    }

    @discardableResult
    public func moveView(tabId: UInt64, fromIndex: UInt32, toIndex: UInt32) throws -> Bool {
        var moved: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_move_view_index(
            handle,
            tabId,
            fromIndex,
            toIndex,
            &moved
        )
        try library.ensureStatus(status, context: "multi_document_move_view_index")
        return moved != 0
    }

    @discardableResult
    public func closeView(tabId: UInt64, viewIndex: UInt32) throws -> Bool {
        var closed: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_close_view_index(handle, tabId, viewIndex, &closed)
        try library.ensureStatus(status, context: "multi_document_close_view_index")
        return closed != 0
    }

    public func viewCount(tabId: UInt64) throws -> UInt32 {
        var count: UInt32 = 0
        let status = editor_core_ui_ffi_multi_document_view_count(handle, tabId, &count)
        try library.ensureStatus(status, context: "multi_document_view_count")
        return count
    }

    public func tabText(tabId: UInt64) throws -> String {
        guard let ptr = editor_core_ui_ffi_multi_document_tab_text(handle, tabId) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "multi_document_tab_text",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func replaceTabText(tabId: UInt64, text: String, markSaved: Bool = false) throws {
        let status = text.withCString { textPtr in
            editor_core_ui_ffi_multi_document_replace_tab_text(
                handle,
                tabId,
                textPtr,
                markSaved ? 1 : 0
            )
        }
        try library.ensureStatus(status, context: "multi_document_replace_tab_text")
    }

    public func isTabModified(_ tabId: UInt64) throws -> Bool {
        var raw: UInt8 = 0
        let status = editor_core_ui_ffi_multi_document_is_tab_modified(handle, tabId, &raw)
        try library.ensureStatus(status, context: "multi_document_is_tab_modified")
        return raw != 0
    }

    public func markTabSaved(_ tabId: UInt64) throws {
        let status = editor_core_ui_ffi_multi_document_mark_tab_saved(handle, tabId)
        try library.ensureStatus(status, context: "multi_document_mark_tab_saved")
    }

    public func searchAllTabsJSON(query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> String {
        let ptr = query.withCString { queryPtr in
            editor_core_ui_ffi_multi_document_search_all_tabs_json(
                handle,
                queryPtr,
                options.ffiCaseSensitive,
                options.ffiWholeWord,
                options.ffiRegex
            )
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "multi_document_search_all_tabs_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func searchAllTabs(query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> [EcuTabSearchResult] {
        let json = try searchAllTabsJSON(query: query, options: options)
        return try decode(EcuTabSearchResponse.self, from: json, context: "multi_document_search_decode").results
    }

    public func workspaceOutlineSnapshotJSON() throws -> String {
        try ffiStringResult(context: "multi_document_workspace_outline_snapshot_json") {
            editor_core_ui_ffi_multi_document_workspace_outline_snapshot_json(handle)
        }
    }

    public func workspaceOutlineSnapshot() throws -> EcuWorkspaceOutlineSnapshot {
        try decode(
            EcuWorkspaceOutlineSnapshot.self,
            from: workspaceOutlineSnapshotJSON(),
            context: "multi_document_workspace_outline_snapshot_decode"
        )
    }

    public func applyTabDocumentSymbolsJSON(tabId: UInt64, resultJSON: String) throws {
        let status = resultJSON.withCString { resultPtr in
            editor_core_ui_ffi_multi_document_apply_tab_document_symbols_json(handle, tabId, resultPtr)
        }
        try library.ensureStatus(status, context: "multi_document_apply_tab_document_symbols_json")
    }

    public func previewWorkspaceEditTransactionJSON(_ workspaceEditJSON: String) throws -> String {
        try ffiStringResult(context: "multi_document_preview_workspace_edit_transaction_json") {
            workspaceEditJSON.withCString { editPtr in
                editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(handle, editPtr)
            }
        }
    }

    public func previewWorkspaceEditTransaction(_ workspaceEditJSON: String) throws -> EcuWorkspaceEditTransactionResult {
        try decode(
            EcuWorkspaceEditTransactionResult.self,
            from: previewWorkspaceEditTransactionJSON(workspaceEditJSON),
            context: "multi_document_preview_workspace_edit_transaction_decode"
        )
    }

    public func applyWorkspaceEditTransactionJSON(_ workspaceEditJSON: String) throws -> String {
        try ffiStringResult(context: "multi_document_apply_workspace_edit_transaction_json") {
            workspaceEditJSON.withCString { editPtr in
                editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(handle, editPtr)
            }
        }
    }

    public func applyWorkspaceEditTransaction(_ workspaceEditJSON: String) throws -> EcuWorkspaceEditTransactionResult {
        try decode(
            EcuWorkspaceEditTransactionResult.self,
            from: applyWorkspaceEditTransactionJSON(workspaceEditJSON),
            context: "multi_document_apply_workspace_edit_transaction_decode"
        )
    }

    public func workspaceEditTransactionEventsLatestSequence() throws -> UInt64 {
        var sequence: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(handle, &sequence)
        try library.ensureStatus(status, context: "multi_document_workspace_edit_transaction_events_latest_sequence")
        return sequence
    }

    public func workspaceEditTransactionEventsJSON(after sequence: UInt64 = 0) throws -> String {
        try ffiStringResult(context: "multi_document_workspace_edit_transaction_events_json") {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_json(handle, sequence)
        }
    }

    public func workspaceEditTransactionEvents(after sequence: UInt64 = 0) throws -> EcuWorkspaceEditTransactionEventsSnapshot {
        try decode(
            EcuWorkspaceEditTransactionEventsSnapshot.self,
            from: workspaceEditTransactionEventsJSON(after: sequence),
            context: "multi_document_workspace_edit_transaction_events_decode"
        )
    }

    public func applyWorkspaceDiagnosticsJSON(_ resultJSON: String) throws -> EcuWorkspaceDiagnosticsSnapshot {
        let json = try applyWorkspaceDiagnosticsSnapshotJSON(resultJSON)
        return try decode(
            EcuWorkspaceDiagnosticsSnapshot.self,
            from: json,
            context: "multi_document_workspace_diagnostics_apply_decode"
        )
    }

    public func applyWorkspaceDiagnosticsSnapshotJSON(_ resultJSON: String) throws -> String {
        try ffiStringResult(context: "multi_document_apply_workspace_diagnostics_json") {
            resultJSON.withCString { resultPtr in
                editor_core_ui_ffi_multi_document_apply_workspace_diagnostics_json(handle, resultPtr)
            }
        }
    }

    public func workspaceDiagnosticsSnapshotJSON() throws -> String {
        try ffiStringResult(context: "multi_document_workspace_diagnostics_snapshot_json") {
            editor_core_ui_ffi_multi_document_workspace_diagnostics_snapshot_json(handle)
        }
    }

    public func workspaceDiagnosticsSnapshot() throws -> EcuWorkspaceDiagnosticsSnapshot {
        try decode(
            EcuWorkspaceDiagnosticsSnapshot.self,
            from: workspaceDiagnosticsSnapshotJSON(),
            context: "multi_document_workspace_diagnostics_snapshot_decode"
        )
    }

    public func workspaceDiagnosticMarkersJSON() throws -> String {
        try ffiStringResult(context: "multi_document_workspace_diagnostic_markers_json") {
            editor_core_ui_ffi_multi_document_workspace_diagnostic_markers_json(handle)
        }
    }

    public func workspaceDiagnosticMarkersSnapshot() throws -> EcuWorkspaceDiagnosticMarkersSnapshot {
        try decode(
            EcuWorkspaceDiagnosticMarkersSnapshot.self,
            from: workspaceDiagnosticMarkersJSON(),
            context: "multi_document_workspace_diagnostic_markers_decode"
        )
    }

    public func workspaceDiagnosticsPreviousResultIdsJSON() throws -> String {
        try ffiStringResult(context: "multi_document_workspace_diagnostics_previous_result_ids_json") {
            editor_core_ui_ffi_multi_document_workspace_diagnostics_previous_result_ids_json(handle)
        }
    }

    public func workspaceDiagnosticsLatestEventSequence() throws -> UInt64 {
        var sequence: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_workspace_diagnostics_latest_event_sequence(handle, &sequence)
        try library.ensureStatus(status, context: "multi_document_workspace_diagnostics_latest_event_sequence")
        return sequence
    }

    public func workspaceDiagnosticsEventsJSON(after sequence: UInt64 = 0) throws -> String {
        try ffiStringResult(context: "multi_document_workspace_diagnostics_events_json") {
            editor_core_ui_ffi_multi_document_workspace_diagnostics_events_json(handle, sequence)
        }
    }

    public func workspaceDiagnosticsEvents(after sequence: UInt64 = 0) throws -> EcuWorkspaceDiagnosticsEventsSnapshot {
        try decode(
            EcuWorkspaceDiagnosticsEventsSnapshot.self,
            from: workspaceDiagnosticsEventsJSON(after: sequence),
            context: "multi_document_workspace_diagnostics_events_decode"
        )
    }

    public func lspResultEventsLatestSequence() throws -> UInt64 {
        var sequence: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_lsp_result_events_latest_sequence(handle, &sequence)
        try library.ensureStatus(status, context: "multi_document_lsp_result_events_latest_sequence")
        return sequence
    }

    public func lspResultEventsJSON(after sequence: UInt64 = 0) throws -> String {
        try ffiStringResult(context: "multi_document_lsp_result_events_json") {
            editor_core_ui_ffi_multi_document_lsp_result_events_json(handle, sequence)
        }
    }

    public func lspResultEvents(after sequence: UInt64 = 0) throws -> EcuMultiDocumentLSPResultEventsSnapshot {
        try decode(
            EcuMultiDocumentLSPResultEventsSnapshot.self,
            from: lspResultEventsJSON(after: sequence),
            context: "multi_document_lsp_result_events_decode"
        )
    }

    public func lspRequestEventsLatestSequence() throws -> UInt64 {
        var sequence: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_lsp_request_events_latest_sequence(handle, &sequence)
        try library.ensureStatus(status, context: "multi_document_lsp_request_events_latest_sequence")
        return sequence
    }

    public func lspRequestEventsJSON(after sequence: UInt64 = 0) throws -> String {
        try ffiStringResult(context: "multi_document_lsp_request_events_json") {
            editor_core_ui_ffi_multi_document_lsp_request_events_json(handle, sequence)
        }
    }

    public func lspRequestEvents(after sequence: UInt64 = 0) throws -> EcuMultiDocumentLSPRequestEventsSnapshot {
        try decode(
            EcuMultiDocumentLSPRequestEventsSnapshot.self,
            from: lspRequestEventsJSON(after: sequence),
            context: "multi_document_lsp_request_events_decode"
        )
    }

    public func stateEventsLatestSequence() throws -> UInt64 {
        var sequence: UInt64 = 0
        let status = editor_core_ui_ffi_multi_document_state_events_latest_sequence(handle, &sequence)
        try library.ensureStatus(status, context: "multi_document_state_events_latest_sequence")
        return sequence
    }

    public func stateEventsJSON(after sequence: UInt64 = 0) throws -> String {
        try ffiStringResult(context: "multi_document_state_events_json") {
            editor_core_ui_ffi_multi_document_state_events_json(handle, sequence)
        }
    }

    public func stateEvents(after sequence: UInt64 = 0) throws -> EcuMultiDocumentStateEventsSnapshot {
        try decode(
            EcuMultiDocumentStateEventsSnapshot.self,
            from: stateEventsJSON(after: sequence),
            context: "multi_document_state_events_decode"
        )
    }

    public func clearWorkspaceDiagnostics() throws {
        let status = editor_core_ui_ffi_multi_document_clear_workspace_diagnostics(handle)
        try library.ensureStatus(status, context: "multi_document_clear_workspace_diagnostics")
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String, context: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: "JSON is not UTF-8"
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }

    private func ffiStringResult(
        context: String,
        _ body: () -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        guard let ptr = body() else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: context,
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }
}
