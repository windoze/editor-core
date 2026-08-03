import Foundation

enum AttoConfigurationSettingsScope: String, Codable, Equatable {
    case user
    case workspace
    case runtime
}

struct AttoConfigurationResolution: Equatable {
    var snapshot: AttoConfigurationSnapshot
    var appliedScopes: [AttoConfigurationSettingsScope]
}

struct AttoConfigurationSettings: Codable, Equatable {
    static let legacySchemaVersion = 0
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var editor: AttoEditorPreferenceSettings?
    var rendering: AttoRenderingPreferenceSettings?
    var language: AttoLanguagePreferenceSettings?
    var workspace: AttoWorkspacePreferenceSettings?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        editor: AttoEditorPreferenceSettings? = nil,
        rendering: AttoRenderingPreferenceSettings? = nil,
        language: AttoLanguagePreferenceSettings? = nil,
        workspace: AttoWorkspacePreferenceSettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.editor = editor
        self.rendering = rendering
        self.language = language
        self.workspace = workspace
    }

    var isEmpty: Bool {
        editor == nil && rendering == nil && language == nil && workspace == nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case editor
        case rendering
        case language
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.legacySchemaVersion
        self.editor = try container.decodeIfPresent(AttoEditorPreferenceSettings.self, forKey: .editor)
        self.rendering = try container.decodeIfPresent(AttoRenderingPreferenceSettings.self, forKey: .rendering)
        self.language = try container.decodeIfPresent(AttoLanguagePreferenceSettings.self, forKey: .language)
        self.workspace = try container.decodeIfPresent(AttoWorkspacePreferenceSettings.self, forKey: .workspace)
    }

    func migratedToCurrentSchema() -> Self {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        var migrated = self
        migrated.schemaVersion = Self.currentSchemaVersion
        return migrated
    }
}

struct AttoEditorPreferenceSettings: Codable, Equatable {
    var fontFamilies: [String]?
    var fontSizePoints: Double?
    var autoPairsEnabled: Bool?
    var wrapMode: String?
    var wrapIndent: String?
    var findCaseSensitive: Bool?
    var findWholeWord: Bool?
    var findRegex: Bool?

    init(
        fontFamilies: [String]? = nil,
        fontSizePoints: Double? = nil,
        autoPairsEnabled: Bool? = nil,
        wrapMode: String? = nil,
        wrapIndent: String? = nil,
        findCaseSensitive: Bool? = nil,
        findWholeWord: Bool? = nil,
        findRegex: Bool? = nil
    ) {
        self.fontFamilies = fontFamilies
        self.fontSizePoints = fontSizePoints
        self.autoPairsEnabled = autoPairsEnabled
        self.wrapMode = wrapMode
        self.wrapIndent = wrapIndent
        self.findCaseSensitive = findCaseSensitive
        self.findWholeWord = findWholeWord
        self.findRegex = findRegex
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamilies = "font_families"
        case fontSizePoints = "font_size_points"
        case autoPairsEnabled = "auto_pairs_enabled"
        case wrapMode = "wrap_mode"
        case wrapIndent = "wrap_indent"
        case findCaseSensitive = "find_case_sensitive"
        case findWholeWord = "find_whole_word"
        case findRegex = "find_regex"
    }
}

struct AttoRenderingPreferenceSettings: Codable, Equatable {
    var themeName: String?
    var fontLigaturesEnabled: Bool?

    init(
        themeName: String? = nil,
        fontLigaturesEnabled: Bool? = nil
    ) {
        self.themeName = themeName
        self.fontLigaturesEnabled = fontLigaturesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case themeName = "theme_name"
        case fontLigaturesEnabled = "font_ligatures_enabled"
    }
}

struct AttoLanguagePreferenceSettings: Codable, Equatable {
    var commentConfigurations: [String: AttoCommentConfiguration]?
    var lspAutoRestart: AttoLspAutoRestartPolicySettings?

    init(
        commentConfigurations: [String: AttoCommentConfiguration]? = nil,
        lspAutoRestart: AttoLspAutoRestartPolicySettings? = nil
    ) {
        self.commentConfigurations = commentConfigurations
        self.lspAutoRestart = lspAutoRestart
    }

    private enum CodingKeys: String, CodingKey {
        case commentConfigurations = "comment_configurations"
        case lspAutoRestart = "lsp_auto_restart"
    }
}

struct AttoLspAutoRestartPolicySettings: Codable, Equatable {
    var enabled: Bool?
    var maxAttempts: Int?
    var baseDelaySeconds: Double?
    var disabledServerKeys: [String]?
    var serverMaxAttempts: [String: Int]?
    var serverBaseDelaySeconds: [String: Double]?

    init(
        enabled: Bool? = nil,
        maxAttempts: Int? = nil,
        baseDelaySeconds: Double? = nil,
        disabledServerKeys: [String]? = nil,
        serverMaxAttempts: [String: Int]? = nil,
        serverBaseDelaySeconds: [String: Double]? = nil
    ) {
        self.enabled = enabled
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.disabledServerKeys = disabledServerKeys
        self.serverMaxAttempts = serverMaxAttempts
        self.serverBaseDelaySeconds = serverBaseDelaySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case maxAttempts = "max_attempts"
        case baseDelaySeconds = "base_delay_seconds"
        case disabledServerKeys = "disabled_server_keys"
        case serverMaxAttempts = "server_max_attempts"
        case serverBaseDelaySeconds = "server_base_delay_seconds"
    }
}

struct AttoWorkspacePreferenceSettings: Codable, Equatable {
    var rootURL: String?
    var rootPath: String?

    init(rootURL: String? = nil, rootPath: String? = nil) {
        self.rootURL = rootURL
        self.rootPath = rootPath
    }

    private enum CodingKeys: String, CodingKey {
        case rootURL = "root_url"
        case rootPath = "root_path"
    }
}

struct AttoConfigurationSettingsStore {
    let userSettingsURL: URL
    let fileManager: FileManager

    init(
        userSettingsURL: URL = AttoConfigurationSettingsStore.defaultUserSettingsURL(),
        fileManager: FileManager = .default
    ) {
        self.userSettingsURL = userSettingsURL
        self.fileManager = fileManager
    }

    static func defaultUserSettingsURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    static func workspaceSettingsURL(forWorkspaceRootURL workspaceRootURL: URL) -> URL {
        workspaceRootURL
            .standardizedFileURL
            .appendingPathComponent(".attoeditor", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    func loadUserSettings() throws -> AttoConfigurationSettings? {
        try load(from: userSettingsURL)
    }

    func saveUserSettings(_ settings: AttoConfigurationSettings) throws {
        try save(settings, to: userSettingsURL)
    }

    func loadWorkspaceSettings(workspaceRootURL: URL) throws -> AttoConfigurationSettings? {
        try load(from: Self.workspaceSettingsURL(forWorkspaceRootURL: workspaceRootURL))
    }

    func saveWorkspaceSettings(
        _ settings: AttoConfigurationSettings,
        workspaceRootURL: URL
    ) throws {
        try save(settings, to: Self.workspaceSettingsURL(forWorkspaceRootURL: workspaceRootURL))
    }

    func load(from url: URL) throws -> AttoConfigurationSettings? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let settings: AttoConfigurationSettings
        do {
            settings = try JSONDecoder().decode(AttoConfigurationSettings.self, from: data)
        } catch {
            _ = try backupCorruptSettingsFile(at: url)
            return nil
        }

        guard settings.schemaVersion < AttoConfigurationSettings.currentSchemaVersion else {
            return settings
        }

        let migrated = settings.migratedToCurrentSchema()
        _ = try backupMigratedSettingsFile(at: url, schemaVersion: settings.schemaVersion)
        try save(migrated, to: url)
        return migrated
    }

    func save(_ settings: AttoConfigurationSettings, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    @discardableResult
    func backupCorruptSettingsFile(at url: URL) throws -> URL {
        let backupURL = nextCorruptSettingsBackupURL(for: url)
        try fileManager.moveItem(at: url, to: backupURL)
        return backupURL
    }

    func nextCorruptSettingsBackupURL(for url: URL) -> URL {
        let base = url.appendingPathExtension("invalid")
        return nextAvailableBackupURL(base: base)
    }

    @discardableResult
    func backupMigratedSettingsFile(at url: URL, schemaVersion: Int) throws -> URL {
        let backupURL = nextMigratedSettingsBackupURL(for: url, schemaVersion: schemaVersion)
        try fileManager.moveItem(at: url, to: backupURL)
        return backupURL
    }

    func nextMigratedSettingsBackupURL(for url: URL, schemaVersion: Int) -> URL {
        let normalizedSchemaVersion = max(AttoConfigurationSettings.legacySchemaVersion, schemaVersion)
        let base = url
            .appendingPathExtension("v\(normalizedSchemaVersion)")
            .appendingPathExtension("backup")
        return nextAvailableBackupURL(base: base)
    }

    private func nextAvailableBackupURL(base: URL) -> URL {
        if fileManager.fileExists(atPath: base.path) == false {
            return base
        }

        for index in 1... {
            let candidate = URL(fileURLWithPath: "\(base.path).\(index)", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) == false {
                return candidate
            }
        }

        return URL(fileURLWithPath: "\(base.path).\(UUID().uuidString)", isDirectory: false)
    }
}

extension AttoConfigurationSnapshot {
    func resolvingSettings(
        user: AttoConfigurationSettings? = nil,
        workspace: AttoConfigurationSettings? = nil,
        runtime: AttoConfigurationSettings? = nil
    ) -> AttoConfigurationResolution {
        var snapshot = self
        var appliedScopes: [AttoConfigurationSettingsScope] = []

        for (scope, settings) in [
            (AttoConfigurationSettingsScope.user, user),
            (.workspace, workspace),
            (.runtime, runtime),
        ] {
            guard let settings, settings.isEmpty == false else { continue }
            snapshot.apply(settings)
            appliedScopes.append(scope)
        }

        return AttoConfigurationResolution(snapshot: snapshot, appliedScopes: appliedScopes)
    }

    private mutating func apply(_ settings: AttoConfigurationSettings) {
        if let editor = settings.editor {
            apply(editor)
        }
        if let rendering = settings.rendering {
            apply(rendering)
        }
        if let language = settings.language {
            apply(language)
        }
        if let workspace = settings.workspace {
            apply(workspace)
        }
    }

    private mutating func apply(_ settings: AttoEditorPreferenceSettings) {
        if let fontFamilies = settings.fontFamilies {
            editor.fontFamilies = fontFamilies
        }
        if let fontSizePoints = settings.fontSizePoints {
            editor.fontSizePoints = fontSizePoints
        }
        if let autoPairsEnabled = settings.autoPairsEnabled {
            editor.autoPairsEnabled = autoPairsEnabled
        }
        if let wrapMode = settings.wrapMode {
            editor.wrapMode = wrapMode
        }
        if let wrapIndent = settings.wrapIndent {
            editor.wrapIndent = wrapIndent
        }
        if let findCaseSensitive = settings.findCaseSensitive {
            editor.findCaseSensitive = findCaseSensitive
        }
        if let findWholeWord = settings.findWholeWord {
            editor.findWholeWord = findWholeWord
        }
        if let findRegex = settings.findRegex {
            editor.findRegex = findRegex
        }
    }

    private mutating func apply(_ settings: AttoRenderingPreferenceSettings) {
        if let themeName = settings.themeName {
            rendering.themeName = themeName
        }
        if let fontLigaturesEnabled = settings.fontLigaturesEnabled {
            rendering.fontLigaturesEnabled = fontLigaturesEnabled
        }
    }

    private mutating func apply(_ settings: AttoLanguagePreferenceSettings) {
        if let commentConfigurations = settings.commentConfigurations {
            language.commentConfigurations.merge(commentConfigurations) { _, new in new }
        }
        if let lspAutoRestart = settings.lspAutoRestart {
            apply(lspAutoRestart)
        }
    }

    private mutating func apply(_ settings: AttoLspAutoRestartPolicySettings) {
        if let enabled = settings.enabled {
            language.lspAutoRestart.enabled = enabled
        }
        if let maxAttempts = settings.maxAttempts {
            language.lspAutoRestart.maxAttempts = maxAttempts
        }
        if let baseDelaySeconds = settings.baseDelaySeconds {
            language.lspAutoRestart.baseDelaySeconds = baseDelaySeconds
        }
        if let disabledServerKeys = settings.disabledServerKeys {
            language.lspAutoRestart.disabledServerKeys = disabledServerKeys
        }
        if let serverMaxAttempts = settings.serverMaxAttempts {
            language.lspAutoRestart.serverMaxAttempts.merge(serverMaxAttempts) { _, new in new }
        }
        if let serverBaseDelaySeconds = settings.serverBaseDelaySeconds {
            language.lspAutoRestart.serverBaseDelaySeconds.merge(serverBaseDelaySeconds) { _, new in new }
        }
    }

    private mutating func apply(_ settings: AttoWorkspacePreferenceSettings) {
        if let rootURL = settings.rootURL {
            workspace.rootURL = rootURL
        }
        if let rootPath = settings.rootPath {
            workspace.rootPath = rootPath
        }
    }
}
