import Foundation

public struct EcuProjectLspServerConfig: Codable, Equatable, Sendable {
    public let key: String
    public let command: String
    public let args: [String]
    public let languageId: String
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let autoStart: Bool

    private enum CodingKeys: String, CodingKey {
        case key
        case command
        case args
        case languageId = "language_id"
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case autoStart = "auto_start"
    }

    public init(
        key: String,
        command: String,
        args: [String] = [],
        languageId: String,
        workspaceRoots: [String] = [],
        workspaceFolders: [EcuProjectLspWorkspaceFolder] = [],
        autoStart: Bool = true
    ) {
        self.key = key
        self.command = command
        self.args = args
        self.languageId = languageId
        self.workspaceRoots = workspaceRoots
        self.workspaceFolders = workspaceFolders
        self.autoStart = autoStart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
    }
}

public struct EcuProjectLspWorkspaceFolder: Codable, Equatable, Sendable {
    public let uri: String
    public let name: String
    public let rootAlias: String?

    private enum CodingKeys: String, CodingKey {
        case uri
        case name
        case rootAlias = "root_alias"
    }

    public init(
        uri: String,
        name: String,
        rootAlias: String? = nil
    ) {
        self.uri = uri
        self.name = name
        self.rootAlias = rootAlias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        rootAlias = try container.decodeIfPresent(String.self, forKey: .rootAlias)
    }
}

public struct EcuProjectLspStartPlanEntry: Decodable, Equatable, Sendable {
    public let operation: String
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]

    private enum CodingKeys: String, CodingKey {
        case operation
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "start"
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
    }
}

public struct EcuProjectLspStopPlanEntry: Decodable, Equatable, Sendable {
    public let operation: String
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]

    private enum CodingKeys: String, CodingKey {
        case operation
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "stop"
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
    }
}

public struct EcuProjectLspRestartPlanEntry: Decodable, Equatable, Sendable {
    public let operation: String
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]

    private enum CodingKeys: String, CodingKey {
        case operation
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "restart"
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
    }
}

public struct EcuProjectLspStartOutcome: Encodable, Equatable, Sendable {
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let operation: String
    public let documentURI: String
    public let languageId: String
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let trigger: String
    public let status: String
    public let attemptId: UInt64?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case operation
        case documentURI = "document_uri"
        case languageId = "language_id"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case trigger
        case status
        case attemptId = "attempt_id"
        case errorMessage = "error_message"
    }

    public init(
        tabId: UInt64,
        activeViewIndex: UInt32 = 0,
        operation: String = "start",
        documentURI: String,
        languageId: String,
        serverKey: String,
        command: String,
        args: [String] = [],
        workspaceRoots: [String] = [],
        workspaceFolders: [EcuProjectLspWorkspaceFolder] = [],
        trigger: String = "auto_start",
        status: String,
        attemptId: UInt64? = nil,
        errorMessage: String? = nil
    ) {
        self.tabId = tabId
        self.activeViewIndex = activeViewIndex
        self.operation = operation
        self.documentURI = documentURI
        self.languageId = languageId
        self.serverKey = serverKey
        self.command = command
        self.args = args
        self.workspaceRoots = workspaceRoots
        self.workspaceFolders = workspaceFolders
        self.trigger = trigger
        self.status = status
        self.attemptId = attemptId
        self.errorMessage = errorMessage
    }
}

public struct EcuProjectLspLifecycleEvent: Decodable, Equatable, Sendable {
    public let sequence: UInt64
    public let operation: String
    public let trigger: String
    public let status: String
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let attemptId: UInt64?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case sequence
        case operation
        case trigger
        case status
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case attemptId = "attempt_id"
        case errorMessage = "error_message"
    }
}

public struct EcuProjectLspLifecycleEventsSnapshot: Decodable, Equatable, Sendable {
    public let latestSequence: UInt64
    public let events: [EcuProjectLspLifecycleEvent]

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case events
    }
}
