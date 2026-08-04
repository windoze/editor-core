import Foundation

public struct EcuProjectLspRecoveryPolicy: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let maxAttempts: UInt32
    public let baseDelayMillis: UInt64

    private enum CodingKeys: String, CodingKey {
        case enabled
        case maxAttempts = "max_attempts"
        case baseDelayMillis = "base_delay_millis"
    }

    public init(
        enabled: Bool = true,
        maxAttempts: UInt32 = 3,
        baseDelayMillis: UInt64 = 5_000
    ) {
        self.enabled = enabled
        self.maxAttempts = maxAttempts
        self.baseDelayMillis = baseDelayMillis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        maxAttempts = try container.decodeIfPresent(UInt32.self, forKey: .maxAttempts) ?? 3
        baseDelayMillis = try container.decodeIfPresent(UInt64.self, forKey: .baseDelayMillis) ?? 5_000
    }
}

public struct EcuProjectLspSessionPolicy: Codable, Equatable, Sendable {
    public let scope: String
    public let mergeStrategy: String
    public let deduplicate: Bool
    public let shutdownPolicy: String

    private enum CodingKeys: String, CodingKey {
        case scope
        case mergeStrategy = "merge_strategy"
        case deduplicate
        case shutdownPolicy = "shutdown_policy"
    }

    public init(
        scope: String = "workspace",
        mergeStrategy: String = "server_workspace_roots",
        deduplicate: Bool = true,
        shutdownPolicy: String = "last_document"
    ) {
        self.scope = scope
        self.mergeStrategy = mergeStrategy
        self.deduplicate = deduplicate
        self.shutdownPolicy = shutdownPolicy
    }

    public init(sharedSession: Bool) {
        self = sharedSession ? Self.workspaceScoped() : Self.documentScoped()
    }

    public var isSharedSession: Bool {
        scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "workspace"
    }

    public func normalized(sharedSession: Bool) -> Self {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if sharedSession == false {
            return Self.documentScoped()
        }
        if normalizedScope == "document" {
            return Self.documentScoped()
        }
        return Self.workspaceScoped()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? "workspace"
        mergeStrategy = try container.decodeIfPresent(String.self, forKey: .mergeStrategy)
            ?? "server_workspace_roots"
        deduplicate = try container.decodeIfPresent(Bool.self, forKey: .deduplicate) ?? true
        shutdownPolicy = try container.decodeIfPresent(String.self, forKey: .shutdownPolicy) ?? "last_document"
    }

    private static func workspaceScoped() -> Self {
        Self(
            scope: "workspace",
            mergeStrategy: "server_workspace_roots",
            deduplicate: true,
            shutdownPolicy: "last_document"
        )
    }

    private static func documentScoped() -> Self {
        Self(
            scope: "document",
            mergeStrategy: "document",
            deduplicate: false,
            shutdownPolicy: "document_close"
        )
    }
}

public struct EcuProjectLspServerConfig: Codable, Equatable, Sendable {
    public let key: String
    public let command: String
    public let args: [String]
    public let languageId: String
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let autoStart: Bool
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy

    private enum CodingKeys: String, CodingKey {
        case key
        case command
        case args
        case languageId = "language_id"
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionPolicy = "session_policy"
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case autoStart = "auto_start"
        case recoveryPolicy = "recovery_policy"
    }

    public init(
        key: String,
        command: String,
        args: [String] = [],
        languageId: String,
        languageName: String = "",
        serverCapabilities: EcuJSONValue = .object([:]),
        sharedSession: Bool = true,
        sessionPolicy: EcuProjectLspSessionPolicy = EcuProjectLspSessionPolicy(),
        workspaceRoots: [String] = [],
        workspaceFolders: [EcuProjectLspWorkspaceFolder] = [],
        autoStart: Bool = true,
        recoveryPolicy: EcuProjectLspRecoveryPolicy = EcuProjectLspRecoveryPolicy()
    ) {
        self.key = key
        self.command = command
        self.args = args
        self.languageId = languageId
        self.languageName = languageName
        self.serverCapabilities = serverCapabilities
        let normalizedSessionPolicy = sessionPolicy.normalized(sharedSession: sharedSession)
        self.sharedSession = normalizedSessionPolicy.isSharedSession
        self.sessionPolicy = normalizedSessionPolicy
        self.workspaceRoots = workspaceRoots
        self.workspaceFolders = workspaceFolders
        self.autoStart = autoStart
        self.recoveryPolicy = recoveryPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? languageId
        serverCapabilities = try container.decodeIfPresent(EcuJSONValue.self, forKey: .serverCapabilities) ?? .object([:])
        let decodedSharedSession = try container.decodeIfPresent(Bool.self, forKey: .sharedSession) ?? true
        let decodedSessionPolicy = try container.decodeIfPresent(
            EcuProjectLspSessionPolicy.self,
            forKey: .sessionPolicy
        ) ?? EcuProjectLspSessionPolicy(sharedSession: decodedSharedSession)
        let normalizedSessionPolicy = decodedSessionPolicy.normalized(sharedSession: decodedSharedSession)
        sharedSession = normalizedSessionPolicy.isSharedSession
        sessionPolicy = normalizedSessionPolicy
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        recoveryPolicy = try container.decodeIfPresent(
            EcuProjectLspRecoveryPolicy.self,
            forKey: .recoveryPolicy
        ) ?? EcuProjectLspRecoveryPolicy()
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
    public let attemptId: UInt64?
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionKey: String
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy

    private enum CodingKeys: String, CodingKey {
        case operation
        case attemptId = "attempt_id"
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionKey = "session_key"
        case sessionPolicy = "session_policy"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case recoveryPolicy = "recovery_policy"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "start"
        attemptId = try container.decodeIfPresent(UInt64.self, forKey: .attemptId)
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? languageId
        serverCapabilities = try container.decodeIfPresent(EcuJSONValue.self, forKey: .serverCapabilities) ?? .object([:])
        let decodedSharedSession = try container.decodeIfPresent(Bool.self, forKey: .sharedSession) ?? true
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey) ?? ""
        let decodedSessionPolicy = try container.decodeIfPresent(
            EcuProjectLspSessionPolicy.self,
            forKey: .sessionPolicy
        ) ?? EcuProjectLspSessionPolicy(sharedSession: decodedSharedSession)
        sessionPolicy = decodedSessionPolicy.normalized(sharedSession: decodedSharedSession)
        sharedSession = sessionPolicy.isSharedSession
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        recoveryPolicy = try container.decodeIfPresent(
            EcuProjectLspRecoveryPolicy.self,
            forKey: .recoveryPolicy
        ) ?? EcuProjectLspRecoveryPolicy()
    }
}

public struct EcuProjectLspStopPlanEntry: Decodable, Equatable, Sendable {
    public let operation: String
    public let attemptId: UInt64?
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionKey: String
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy

    private enum CodingKeys: String, CodingKey {
        case operation
        case attemptId = "attempt_id"
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionKey = "session_key"
        case sessionPolicy = "session_policy"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case recoveryPolicy = "recovery_policy"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "stop"
        attemptId = try container.decodeIfPresent(UInt64.self, forKey: .attemptId)
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? languageId
        serverCapabilities = try container.decodeIfPresent(EcuJSONValue.self, forKey: .serverCapabilities) ?? .object([:])
        let decodedSharedSession = try container.decodeIfPresent(Bool.self, forKey: .sharedSession) ?? true
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey) ?? ""
        let decodedSessionPolicy = try container.decodeIfPresent(
            EcuProjectLspSessionPolicy.self,
            forKey: .sessionPolicy
        ) ?? EcuProjectLspSessionPolicy(sharedSession: decodedSharedSession)
        sessionPolicy = decodedSessionPolicy.normalized(sharedSession: decodedSharedSession)
        sharedSession = sessionPolicy.isSharedSession
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        recoveryPolicy = try container.decodeIfPresent(
            EcuProjectLspRecoveryPolicy.self,
            forKey: .recoveryPolicy
        ) ?? EcuProjectLspRecoveryPolicy()
    }
}

public struct EcuProjectLspRestartPlanEntry: Decodable, Equatable, Sendable {
    public let operation: String
    public let attemptId: UInt64?
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let documentURI: String
    public let languageId: String
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionKey: String
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy

    private enum CodingKeys: String, CodingKey {
        case operation
        case attemptId = "attempt_id"
        case tabId = "tab_id"
        case activeViewIndex = "active_view_index"
        case documentURI = "document_uri"
        case languageId = "language_id"
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionKey = "session_key"
        case sessionPolicy = "session_policy"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case recoveryPolicy = "recovery_policy"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "restart"
        attemptId = try container.decodeIfPresent(UInt64.self, forKey: .attemptId)
        tabId = try container.decode(UInt64.self, forKey: .tabId)
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? languageId
        serverCapabilities = try container.decodeIfPresent(EcuJSONValue.self, forKey: .serverCapabilities) ?? .object([:])
        let decodedSharedSession = try container.decodeIfPresent(Bool.self, forKey: .sharedSession) ?? true
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey) ?? ""
        let decodedSessionPolicy = try container.decodeIfPresent(
            EcuProjectLspSessionPolicy.self,
            forKey: .sessionPolicy
        ) ?? EcuProjectLspSessionPolicy(sharedSession: decodedSharedSession)
        sessionPolicy = decodedSessionPolicy.normalized(sharedSession: decodedSharedSession)
        sharedSession = sessionPolicy.isSharedSession
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        recoveryPolicy = try container.decodeIfPresent(
            EcuProjectLspRecoveryPolicy.self,
            forKey: .recoveryPolicy
        ) ?? EcuProjectLspRecoveryPolicy()
    }
}

public struct EcuProjectLspStartOutcome: Encodable, Equatable, Sendable {
    public let tabId: UInt64
    public let activeViewIndex: UInt32
    public let operation: String
    public let documentURI: String
    public let languageId: String
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionKey: String
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy
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
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionKey = "session_key"
        case sessionPolicy = "session_policy"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case recoveryPolicy = "recovery_policy"
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
        languageName: String? = nil,
        serverCapabilities: EcuJSONValue = .object([:]),
        sharedSession: Bool = true,
        sessionKey: String = "",
        sessionPolicy: EcuProjectLspSessionPolicy = EcuProjectLspSessionPolicy(),
        serverKey: String,
        command: String,
        args: [String] = [],
        workspaceRoots: [String] = [],
        workspaceFolders: [EcuProjectLspWorkspaceFolder] = [],
        recoveryPolicy: EcuProjectLspRecoveryPolicy = EcuProjectLspRecoveryPolicy(),
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
        self.languageName = languageName ?? languageId
        self.serverCapabilities = serverCapabilities
        let normalizedSessionPolicy = sessionPolicy.normalized(sharedSession: sharedSession)
        self.sharedSession = normalizedSessionPolicy.isSharedSession
        self.sessionKey = sessionKey
        self.sessionPolicy = normalizedSessionPolicy
        self.serverKey = serverKey
        self.command = command
        self.args = args
        self.workspaceRoots = workspaceRoots
        self.workspaceFolders = workspaceFolders
        self.recoveryPolicy = recoveryPolicy
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
    public let languageName: String
    public let serverCapabilities: EcuJSONValue
    public let sharedSession: Bool
    public let sessionKey: String
    public let sessionPolicy: EcuProjectLspSessionPolicy
    public let serverKey: String
    public let command: String
    public let args: [String]
    public let workspaceRoots: [String]
    public let workspaceFolders: [EcuProjectLspWorkspaceFolder]
    public let recoveryPolicy: EcuProjectLspRecoveryPolicy
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
        case languageName = "language_name"
        case serverCapabilities = "server_capabilities"
        case sharedSession = "shared_session"
        case sessionKey = "session_key"
        case sessionPolicy = "session_policy"
        case serverKey = "server_key"
        case command
        case args
        case workspaceRoots = "workspace_roots"
        case workspaceFolders = "workspace_folders"
        case recoveryPolicy = "recovery_policy"
        case attemptId = "attempt_id"
        case errorMessage = "error_message"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decodeIfPresent(UInt64.self, forKey: .sequence) ?? 0
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "start"
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? "auto_start"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        tabId = try container.decodeIfPresent(UInt64.self, forKey: .tabId) ?? 0
        activeViewIndex = try container.decodeIfPresent(UInt32.self, forKey: .activeViewIndex) ?? 0
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI) ?? ""
        languageId = try container.decodeIfPresent(String.self, forKey: .languageId) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? languageId
        serverCapabilities = try container.decodeIfPresent(EcuJSONValue.self, forKey: .serverCapabilities) ?? .object([:])
        let decodedSharedSession = try container.decodeIfPresent(Bool.self, forKey: .sharedSession) ?? true
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey) ?? ""
        let decodedSessionPolicy = try container.decodeIfPresent(
            EcuProjectLspSessionPolicy.self,
            forKey: .sessionPolicy
        ) ?? EcuProjectLspSessionPolicy(sharedSession: decodedSharedSession)
        sessionPolicy = decodedSessionPolicy.normalized(sharedSession: decodedSharedSession)
        sharedSession = sessionPolicy.isSharedSession
        serverKey = try container.decodeIfPresent(String.self, forKey: .serverKey) ?? ""
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workspaceRoots = try container.decodeIfPresent([String].self, forKey: .workspaceRoots) ?? []
        workspaceFolders = try container.decodeIfPresent(
            [EcuProjectLspWorkspaceFolder].self,
            forKey: .workspaceFolders
        ) ?? []
        recoveryPolicy = try container.decodeIfPresent(
            EcuProjectLspRecoveryPolicy.self,
            forKey: .recoveryPolicy
        ) ?? EcuProjectLspRecoveryPolicy()
        attemptId = try container.decodeIfPresent(UInt64.self, forKey: .attemptId)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
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
