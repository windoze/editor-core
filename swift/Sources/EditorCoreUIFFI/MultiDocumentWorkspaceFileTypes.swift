public struct EcuWorkspaceFileSearchResult: Decodable, Equatable, Sendable {
    public let uri: String
    public let path: String
    public let relativePath: String
    public let line1: UInt32
    public let column1: UInt32
    public let lineText: String
    public let matchStart: UInt32
    public let matchEnd: UInt32

    private enum CodingKeys: String, CodingKey {
        case uri
        case path
        case relativePath = "relative_path"
        case line1
        case column1
        case lineText = "line_text"
        case matchStart = "match_start"
        case matchEnd = "match_end"
    }
}

public struct EcuWorkspaceFileScanOptions: Encodable, Equatable, Sendable {
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var maxResults: UInt32
    public var offset: UInt32
    public var maxFileSizeBytes: UInt64
    public var skipBinary: Bool
    public var respectIgnoreFiles: Bool
    public var cancelled: Bool
    public var cancelAfterFiles: UInt32?

    public init(
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        maxResults: UInt32 = 0,
        offset: UInt32 = 0,
        maxFileSizeBytes: UInt64 = 0,
        skipBinary: Bool = true,
        respectIgnoreFiles: Bool = true,
        cancelled: Bool = false,
        cancelAfterFiles: UInt32? = nil
    ) {
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.maxResults = maxResults
        self.offset = offset
        self.maxFileSizeBytes = maxFileSizeBytes
        self.skipBinary = skipBinary
        self.respectIgnoreFiles = respectIgnoreFiles
        self.cancelled = cancelled
        self.cancelAfterFiles = cancelAfterFiles
    }

    private enum CodingKeys: String, CodingKey {
        case includeGlobs = "include_globs"
        case excludeGlobs = "exclude_globs"
        case maxResults = "max_results"
        case offset
        case maxFileSizeBytes = "max_file_size_bytes"
        case skipBinary = "skip_binary"
        case respectIgnoreFiles = "respect_ignore_files"
        case cancelled
        case cancelAfterFiles = "cancel_after_files"
    }
}

public struct EcuWorkspaceFileScanSummary: Decodable, Equatable, Sendable {
    public let offset: UInt64
    public let maxResults: UInt64
    public let nextOffset: UInt64?
    public let truncated: Bool
    public let cancelled: Bool
    public let visitedFiles: UInt64
    public let matchedResults: UInt64
    public let returnedResults: UInt64
    public let skippedLargeFiles: UInt64
    public let skippedBinaryFiles: UInt64
    public let skippedUnreadableFiles: UInt64
    public let ignoreFilesEnabled: Bool

    public init(
        offset: UInt64 = 0,
        maxResults: UInt64 = 0,
        nextOffset: UInt64? = nil,
        truncated: Bool = false,
        cancelled: Bool = false,
        visitedFiles: UInt64 = 0,
        matchedResults: UInt64 = 0,
        returnedResults: UInt64 = 0,
        skippedLargeFiles: UInt64 = 0,
        skippedBinaryFiles: UInt64 = 0,
        skippedUnreadableFiles: UInt64 = 0,
        ignoreFilesEnabled: Bool = false
    ) {
        self.offset = offset
        self.maxResults = maxResults
        self.nextOffset = nextOffset
        self.truncated = truncated
        self.cancelled = cancelled
        self.visitedFiles = visitedFiles
        self.matchedResults = matchedResults
        self.returnedResults = returnedResults
        self.skippedLargeFiles = skippedLargeFiles
        self.skippedBinaryFiles = skippedBinaryFiles
        self.skippedUnreadableFiles = skippedUnreadableFiles
        self.ignoreFilesEnabled = ignoreFilesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case offset
        case maxResults = "max_results"
        case nextOffset = "next_offset"
        case truncated
        case cancelled
        case visitedFiles = "visited_files"
        case matchedResults = "matched_results"
        case returnedResults = "returned_results"
        case skippedLargeFiles = "skipped_large_files"
        case skippedBinaryFiles = "skipped_binary_files"
        case skippedUnreadableFiles = "skipped_unreadable_files"
        case ignoreFilesEnabled = "ignore_files_enabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decodeIfPresent(UInt64.self, forKey: .offset) ?? 0
        maxResults = try container.decodeIfPresent(UInt64.self, forKey: .maxResults) ?? 0
        nextOffset = try container.decodeIfPresent(UInt64.self, forKey: .nextOffset)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
        visitedFiles = try container.decodeIfPresent(UInt64.self, forKey: .visitedFiles) ?? 0
        matchedResults = try container.decodeIfPresent(UInt64.self, forKey: .matchedResults) ?? 0
        returnedResults = try container.decodeIfPresent(UInt64.self, forKey: .returnedResults) ?? 0
        skippedLargeFiles = try container.decodeIfPresent(UInt64.self, forKey: .skippedLargeFiles) ?? 0
        skippedBinaryFiles = try container.decodeIfPresent(UInt64.self, forKey: .skippedBinaryFiles) ?? 0
        skippedUnreadableFiles = try container.decodeIfPresent(UInt64.self, forKey: .skippedUnreadableFiles) ?? 0
        ignoreFilesEnabled = try container.decodeIfPresent(Bool.self, forKey: .ignoreFilesEnabled) ?? false
    }
}

public struct EcuWorkspaceFileEntry: Decodable, Equatable, Sendable {
    public let uri: String
    public let path: String
    public let relativePath: String

    public init(uri: String, path: String, relativePath: String) {
        self.uri = uri
        self.path = path
        self.relativePath = relativePath
    }

    private enum CodingKeys: String, CodingKey {
        case uri
        case path
        case relativePath = "relative_path"
    }
}

public struct EcuProjectFileIndexSnapshot: Decodable, Equatable, Sendable {
    public let workspaceRoots: [String]
    public let files: [EcuWorkspaceFileEntry]
    public let isBuilt: Bool
    public let maxResults: UInt32

    private enum CodingKeys: String, CodingKey {
        case workspaceRoots = "workspace_roots"
        case files
        case isBuilt = "is_built"
        case maxResults = "max_results"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        files = try container.decodeIfPresent([EcuWorkspaceFileEntry].self, forKey: .files) ?? []
        isBuilt = try container.decodeIfPresent(Bool.self, forKey: .isBuilt) ?? false
        maxResults = try container.decodeIfPresent(UInt32.self, forKey: .maxResults) ?? 0
    }
}

public struct EcuProjectFileIndexQueryResult: Decodable, Equatable, Sendable {
    public let uri: String
    public let path: String
    public let relativePath: String
    public let score: Int32

    private enum CodingKeys: String, CodingKey {
        case uri
        case path
        case relativePath = "relative_path"
        case score
    }
}

public struct EcuWorkspaceFileSearchResponse: Decodable, Equatable, Sendable {
    public let results: [EcuWorkspaceFileSearchResult]
    public let scan: EcuWorkspaceFileScanSummary

    private enum CodingKeys: String, CodingKey {
        case results
        case scan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([EcuWorkspaceFileSearchResult].self, forKey: .results) ?? []
        scan = try container.decodeIfPresent(EcuWorkspaceFileScanSummary.self, forKey: .scan) ?? EcuWorkspaceFileScanSummary()
    }
}

public struct EcuWorkspaceFileListResponse: Decodable, Equatable, Sendable {
    public let files: [EcuWorkspaceFileEntry]
    public let scan: EcuWorkspaceFileScanSummary

    private enum CodingKeys: String, CodingKey {
        case files
        case scan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decodeIfPresent([EcuWorkspaceFileEntry].self, forKey: .files) ?? []
        scan = try container.decodeIfPresent(EcuWorkspaceFileScanSummary.self, forKey: .scan) ?? EcuWorkspaceFileScanSummary()
    }
}

struct EcuProjectFileIndexQueryResponse: Decodable {
    let results: [EcuProjectFileIndexQueryResult]
}
