import EditorCoreUIFFI
import Foundation

struct AttoConfigurationSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var editor: AttoEditorPreferenceSnapshot
    var rendering: AttoRenderingPreferenceSnapshot
    var language: AttoLanguagePreferenceSnapshot
    var workspace: AttoWorkspacePreferenceSnapshot

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        editor: AttoEditorPreferenceSnapshot,
        rendering: AttoRenderingPreferenceSnapshot,
        language: AttoLanguagePreferenceSnapshot,
        workspace: AttoWorkspacePreferenceSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.editor = editor
        self.rendering = rendering
        self.language = language
        self.workspace = workspace
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case editor
        case rendering
        case language
        case workspace
    }
}

struct AttoEditorPreferenceSnapshot: Codable, Equatable {
    var fontFamilies: [String]
    var fontSizePoints: Double
    var autoPairsEnabled: Bool
    var wrapMode: String
    var wrapIndent: String
    var findCaseSensitive: Bool
    var findWholeWord: Bool
    var findRegex: Bool

    init(
        fontFamilies: [String],
        fontSizePoints: Double,
        autoPairsEnabled: Bool,
        wrapMode: String,
        wrapIndent: String,
        findCaseSensitive: Bool = true,
        findWholeWord: Bool = false,
        findRegex: Bool = false
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fontFamilies: try container.decode([String].self, forKey: .fontFamilies),
            fontSizePoints: try container.decode(Double.self, forKey: .fontSizePoints),
            autoPairsEnabled: try container.decode(Bool.self, forKey: .autoPairsEnabled),
            wrapMode: try container.decode(String.self, forKey: .wrapMode),
            wrapIndent: try container.decode(String.self, forKey: .wrapIndent),
            findCaseSensitive: try container.decodeIfPresent(Bool.self, forKey: .findCaseSensitive) ?? true,
            findWholeWord: try container.decodeIfPresent(Bool.self, forKey: .findWholeWord) ?? false,
            findRegex: try container.decodeIfPresent(Bool.self, forKey: .findRegex) ?? false
        )
    }
}

struct AttoRenderingPreferenceSnapshot: Codable, Equatable {
    var themeName: String
    var fontLigaturesEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case themeName = "theme_name"
        case fontLigaturesEnabled = "font_ligatures_enabled"
    }
}

struct AttoLanguagePreferenceSnapshot: Codable, Equatable {
    var commentConfigurations: [String: AttoCommentConfiguration]
    var semanticHighlightingEnabled: Bool
    var lspAutoRestart: AttoLspAutoRestartPolicySnapshot

    private enum CodingKeys: String, CodingKey {
        case commentConfigurations = "comment_configurations"
        case semanticHighlightingEnabled = "semantic_highlighting_enabled"
        case lspAutoRestart = "lsp_auto_restart"
    }

    init(
        commentConfigurations: [String: AttoCommentConfiguration],
        semanticHighlightingEnabled: Bool = true,
        lspAutoRestart: AttoLspAutoRestartPolicySnapshot
    ) {
        self.commentConfigurations = commentConfigurations
        self.semanticHighlightingEnabled = semanticHighlightingEnabled
        self.lspAutoRestart = lspAutoRestart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            commentConfigurations: try container.decodeIfPresent(
                [String: AttoCommentConfiguration].self,
                forKey: .commentConfigurations
            ) ?? [:],
            semanticHighlightingEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .semanticHighlightingEnabled
            ) ?? true,
            lspAutoRestart: try container.decode(AttoLspAutoRestartPolicySnapshot.self, forKey: .lspAutoRestart)
        )
    }
}

struct AttoLspAutoRestartPolicySnapshot: Codable, Equatable {
    var enabled: Bool
    var maxAttempts: Int
    var baseDelaySeconds: Double
    var disabledServerKeys: [String]
    var serverMaxAttempts: [String: Int]
    var serverBaseDelaySeconds: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case enabled
        case maxAttempts = "max_attempts"
        case baseDelaySeconds = "base_delay_seconds"
        case disabledServerKeys = "disabled_server_keys"
        case serverMaxAttempts = "server_max_attempts"
        case serverBaseDelaySeconds = "server_base_delay_seconds"
    }
}

struct AttoWorkspacePreferenceSnapshot: Codable, Equatable {
    static let defaultFindInFilesScope = "opened_files"

    var rootURL: String?
    var rootPath: String?
    var findInFilesDefaultScope: String
    var workspaceSearchIncludeGlobs: [String]
    var workspaceSearchExcludeGlobs: [String]

    init(
        rootURL: String? = nil,
        rootPath: String? = nil,
        findInFilesDefaultScope: String = Self.defaultFindInFilesScope,
        workspaceSearchIncludeGlobs: [String] = [],
        workspaceSearchExcludeGlobs: [String] = []
    ) {
        self.rootURL = rootURL
        self.rootPath = rootPath
        self.findInFilesDefaultScope = findInFilesDefaultScope
        self.workspaceSearchIncludeGlobs = workspaceSearchIncludeGlobs
        self.workspaceSearchExcludeGlobs = workspaceSearchExcludeGlobs
    }

    private enum CodingKeys: String, CodingKey {
        case rootURL = "root_url"
        case rootPath = "root_path"
        case findInFilesDefaultScope = "find_in_files_default_scope"
        case workspaceSearchIncludeGlobs = "workspace_search_include_globs"
        case workspaceSearchExcludeGlobs = "workspace_search_exclude_globs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rootURL: try container.decodeIfPresent(String.self, forKey: .rootURL),
            rootPath: try container.decodeIfPresent(String.self, forKey: .rootPath),
            findInFilesDefaultScope: try container.decodeIfPresent(String.self, forKey: .findInFilesDefaultScope)
                ?? Self.defaultFindInFilesScope,
            workspaceSearchIncludeGlobs: try container.decodeIfPresent(
                [String].self,
                forKey: .workspaceSearchIncludeGlobs
            ) ?? [],
            workspaceSearchExcludeGlobs: try container.decodeIfPresent(
                [String].self,
                forKey: .workspaceSearchExcludeGlobs
            ) ?? []
        )
    }
}

struct AttoCapabilitySnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var uiRuntime: AttoUIRuntimeCapabilitySnapshot?
    var requiredUIFeatures: [AttoFeatureCapabilitySnapshot]
    var optionalUIFeatures: [AttoFeatureCapabilitySnapshot]
    var missingRequiredUIFeatures: [String]
    var missingOptionalUIFeatures: [String]
    var lsp: AttoLspCapabilitySnapshot?
    var platform: AttoPlatformCapabilitySnapshot
    var app: AttoAppCapabilitySnapshot
    var loadError: String?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        uiRuntime: AttoUIRuntimeCapabilitySnapshot?,
        requiredUIFeatures: [AttoFeatureCapabilitySnapshot],
        optionalUIFeatures: [AttoFeatureCapabilitySnapshot],
        missingRequiredUIFeatures: [String],
        missingOptionalUIFeatures: [String],
        lsp: AttoLspCapabilitySnapshot?,
        platform: AttoPlatformCapabilitySnapshot = .current(),
        app: AttoAppCapabilitySnapshot = .current(),
        loadError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.uiRuntime = uiRuntime
        self.requiredUIFeatures = requiredUIFeatures
        self.optionalUIFeatures = optionalUIFeatures
        self.missingRequiredUIFeatures = missingRequiredUIFeatures
        self.missingOptionalUIFeatures = missingOptionalUIFeatures
        self.lsp = lsp
        self.platform = platform
        self.app = app
        self.loadError = loadError
    }

    init(
        runtimeReport: AttoRuntimeCompatibility.Report,
        lspCapabilities: EcuLspCapabilities? = nil,
        platform: AttoPlatformCapabilitySnapshot = .current(),
        app: AttoAppCapabilitySnapshot = .current()
    ) {
        self.init(
            uiRuntime: runtimeReport.runtimeInfo.map { AttoUIRuntimeCapabilitySnapshot(runtimeInfo: $0) },
            requiredUIFeatures: AttoRuntimeCompatibility.requiredFeatures.map(AttoFeatureCapabilitySnapshot.init),
            optionalUIFeatures: AttoRuntimeCompatibility.optionalFeatures.map(AttoFeatureCapabilitySnapshot.init),
            missingRequiredUIFeatures: runtimeReport.missingFeatures.map(\.name),
            missingOptionalUIFeatures: runtimeReport.missingOptionalFeatures.map(\.name),
            lsp: lspCapabilities.map(AttoLspCapabilitySnapshot.init),
            platform: platform,
            app: app,
            loadError: runtimeReport.loadError
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case uiRuntime = "ui_runtime"
        case requiredUIFeatures = "required_ui_features"
        case optionalUIFeatures = "optional_ui_features"
        case missingRequiredUIFeatures = "missing_required_ui_features"
        case missingOptionalUIFeatures = "missing_optional_ui_features"
        case lsp
        case platform
        case app
        case loadError = "load_error"
    }
}

struct AttoUIRuntimeCapabilitySnapshot: Codable, Equatable {
    var abiVersion: UInt32
    var version: String
    var rawFeatureFlags: UInt64
    var knownFeatureNames: [String]

    init(runtimeInfo: EditorCoreUIFFIRuntimeInfo) {
        self.abiVersion = runtimeInfo.abiVersion
        self.version = runtimeInfo.version
        self.rawFeatureFlags = runtimeInfo.features.rawValue
        self.knownFeatureNames = AttoRuntimeCompatibility.knownRuntimeFeatures
            .filter { runtimeInfo.features.contains($0.feature) }
            .map(\.name)
    }

    private enum CodingKeys: String, CodingKey {
        case abiVersion = "abi_version"
        case version
        case rawFeatureFlags = "raw_feature_flags"
        case knownFeatureNames = "known_feature_names"
    }
}

struct AttoFeatureCapabilitySnapshot: Codable, Equatable {
    var name: String
    var rawValue: UInt64
    var reason: String

    init(feature: AttoRuntimeCompatibility.RuntimeFeature) {
        self.name = feature.name
        self.rawValue = feature.feature.rawValue
        self.reason = feature.reason
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case rawValue = "raw_value"
        case reason
    }
}

struct AttoLspCapabilitySnapshot: Codable, Equatable {
    var semanticTokens: Bool
    var semanticTokensDelta: Bool
    var completionSupported: Bool
    var completionItemResolve: Bool
    var completionTriggerCharacters: [String]
    var completionCommitCharacters: [String]
    var foldingRanges: Bool
    var onTypeFormatting: Bool
    var signatureHelpSupported: Bool
    var signatureHelpTriggerCharacters: [String]
    var signatureHelpRetriggerCharacters: [String]

    init(capabilities: EcuLspCapabilities) {
        self.semanticTokens = capabilities.semanticTokens
        self.semanticTokensDelta = capabilities.semanticTokensDelta
        self.completionSupported = capabilities.completion.supported
        self.completionItemResolve = capabilities.completionItemResolve
        self.completionTriggerCharacters = capabilities.completion.triggerCharacters
        self.completionCommitCharacters = capabilities.completion.allCommitCharacters
        self.foldingRanges = capabilities.foldingRanges
        self.onTypeFormatting = capabilities.onTypeFormatting
        self.signatureHelpSupported = capabilities.signatureHelp.supported
        self.signatureHelpTriggerCharacters = capabilities.signatureHelp.triggerCharacters
        self.signatureHelpRetriggerCharacters = capabilities.signatureHelp.retriggerCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case semanticTokens = "semantic_tokens"
        case semanticTokensDelta = "semantic_tokens_delta"
        case completionSupported = "completion_supported"
        case completionItemResolve = "completion_item_resolve"
        case completionTriggerCharacters = "completion_trigger_characters"
        case completionCommitCharacters = "completion_commit_characters"
        case foldingRanges = "folding_ranges"
        case onTypeFormatting = "on_type_formatting"
        case signatureHelpSupported = "signature_help_supported"
        case signatureHelpTriggerCharacters = "signature_help_trigger_characters"
        case signatureHelpRetriggerCharacters = "signature_help_retrigger_characters"
    }
}

struct AttoPlatformCapabilitySnapshot: Codable, Equatable {
    var operatingSystem: String
    var operatingSystemVersion: String
    var architecture: String
    var supportsAppKit: Bool
    var supportsNativeFileDialogs: Bool
    var supportsChildWindows: Bool

    static func current() -> Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            operatingSystem: "macOS",
            operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: currentArchitecture(),
            supportsAppKit: true,
            supportsNativeFileDialogs: true,
            supportsChildWindows: true
        )
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private enum CodingKeys: String, CodingKey {
        case operatingSystem = "operating_system"
        case operatingSystemVersion = "operating_system_version"
        case architecture
        case supportsAppKit = "supports_app_kit"
        case supportsNativeFileDialogs = "supports_native_file_dialogs"
        case supportsChildWindows = "supports_child_windows"
    }
}

struct AttoAppCapabilitySnapshot: Codable, Equatable {
    var supportsCommandPalette: Bool
    var supportsMenuCommandValidation: Bool
    var supportsUserDefaultsPersistence: Bool
    var supportsWorkspaceSessions: Bool
    var supportsMultipleWindows: Bool

    static func current() -> Self {
        Self(
            supportsCommandPalette: true,
            supportsMenuCommandValidation: true,
            supportsUserDefaultsPersistence: true,
            supportsWorkspaceSessions: true,
            supportsMultipleWindows: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case supportsCommandPalette = "supports_command_palette"
        case supportsMenuCommandValidation = "supports_menu_command_validation"
        case supportsUserDefaultsPersistence = "supports_user_defaults_persistence"
        case supportsWorkspaceSessions = "supports_workspace_sessions"
        case supportsMultipleWindows = "supports_multiple_windows"
    }
}

extension AttoPreferences {
    func effectiveConfigurationSnapshot(workspaceRootURL: URL? = nil) -> AttoConfigurationSnapshot {
        AttoConfigurationSnapshot(
            editor: AttoEditorPreferenceSnapshot(
                fontFamilies: effectiveFontFaces,
                fontSizePoints: effectiveFontSizePoints,
                autoPairsEnabled: effectiveAutoPairsEnabled,
                wrapMode: effectiveWrapMode.rawValue,
                wrapIndent: Self.wrapIndentStorageString(effectiveWrapIndent),
                findCaseSensitive: effectiveFindCaseSensitive,
                findWholeWord: effectiveFindWholeWord,
                findRegex: effectiveFindRegex
            ),
            rendering: AttoRenderingPreferenceSnapshot(
                themeName: effectiveThemeName,
                fontLigaturesEnabled: effectiveLigaturesEnabled
            ),
            language: AttoLanguagePreferenceSnapshot(
                commentConfigurations: storedCommentConfigurations,
                semanticHighlightingEnabled: effectiveSemanticHighlightingEnabled,
                lspAutoRestart: AttoLspAutoRestartPolicySnapshot(
                    enabled: effectiveLspAutoRestartEnabled,
                    maxAttempts: effectiveLspAutoRestartMaxAttempts,
                    baseDelaySeconds: effectiveLspAutoRestartBaseDelaySeconds,
                    disabledServerKeys: storedLspAutoRestartDisabledServerKeys,
                    serverMaxAttempts: storedLspAutoRestartServerMaxAttempts,
                    serverBaseDelaySeconds: storedLspAutoRestartServerBaseDelaySeconds
                )
            ),
            workspace: AttoWorkspacePreferenceSnapshot(
                rootURL: workspaceRootURL?.absoluteString,
                rootPath: workspaceRootURL?.path,
                findInFilesDefaultScope: effectiveFindInFilesDefaultScope,
                workspaceSearchIncludeGlobs: effectiveWorkspaceSearchIncludeGlobs,
                workspaceSearchExcludeGlobs: effectiveWorkspaceSearchExcludeGlobs
            )
        )
    }
}

extension AttoRuntimeCompatibility {
    static var knownRuntimeFeatures: [RuntimeFeature] {
        requiredFeatures + optionalFeatures
    }
}
