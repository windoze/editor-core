import Foundation

enum AttoConfigurationSettingsValueKind: String, Codable, Equatable, CaseIterable {
    case boolean
    case integer
    case number
    case string
    case stringArray = "string_array"
    case stringDictionary = "string_dictionary"
    case integerDictionary = "integer_dictionary"
    case numberDictionary = "number_dictionary"
    case commentConfigurationDictionary = "comment_configuration_dictionary"
}

struct AttoConfigurationSettingsChoice: Codable, Equatable {
    var value: String
    var title: String
}

struct AttoConfigurationSettingsFieldSchema: Codable, Equatable {
    var keyPath: String
    var title: String
    var valueKind: AttoConfigurationSettingsValueKind
    var supportedScopes: [AttoConfigurationSettingsScope]
    var supportsDocumentSelectors: Bool
    var choices: [AttoConfigurationSettingsChoice]
    var minimum: Double?
    var maximum: Double?
    var example: String?

    init(
        keyPath: String,
        title: String,
        valueKind: AttoConfigurationSettingsValueKind,
        supportedScopes: [AttoConfigurationSettingsScope] = [.user, .workspace, .runtime],
        supportsDocumentSelectors: Bool = true,
        choices: [AttoConfigurationSettingsChoice] = [],
        minimum: Double? = nil,
        maximum: Double? = nil,
        example: String? = nil
    ) {
        self.keyPath = keyPath
        self.title = title
        self.valueKind = valueKind
        self.supportedScopes = supportedScopes
        self.supportsDocumentSelectors = supportsDocumentSelectors
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
        self.example = example
    }
}

struct AttoConfigurationSettingsSchemaDescriptor: Codable, Equatable {
    var schemaVersion: Int
    var fields: [AttoConfigurationSettingsFieldSchema]

    func field(keyPath: String) -> AttoConfigurationSettingsFieldSchema? {
        fields.first { $0.keyPath == keyPath }
    }
}

enum AttoConfigurationSettingsSchema {
    static let current = AttoConfigurationSettingsSchemaDescriptor(
        schemaVersion: AttoConfigurationSettings.currentSchemaVersion,
        fields: [
            .init(keyPath: "editor.font_families", title: "Font Families", valueKind: .stringArray),
            .init(
                keyPath: "editor.font_size_points",
                title: "Font Size",
                valueKind: .number,
                minimum: 6,
                maximum: 72
            ),
            .init(keyPath: "editor.auto_pairs_enabled", title: "Auto Pairs", valueKind: .boolean),
            .init(
                keyPath: "editor.wrap_mode",
                title: "Word Wrap",
                valueKind: .string,
                choices: [
                    .init(value: "none", title: "Off"),
                    .init(value: "char", title: "By Character"),
                    .init(value: "word", title: "By Word"),
                ]
            ),
            .init(
                keyPath: "editor.wrap_indent",
                title: "Wrap Indent",
                valueKind: .string,
                choices: [
                    .init(value: "none", title: "None"),
                    .init(value: "same_as_line_indent", title: "Same as Line Indent"),
                    .init(value: "fixed_cells:4", title: "Fixed Cells"),
                ]
            ),
            .init(keyPath: "editor.find_case_sensitive", title: "Find Match Case", valueKind: .boolean),
            .init(keyPath: "editor.find_whole_word", title: "Find Whole Word", valueKind: .boolean),
            .init(keyPath: "editor.find_regex", title: "Find Regex", valueKind: .boolean),
            .init(
                keyPath: "editor.word_boundary_ascii_boundary_chars",
                title: "Word Boundary Characters",
                valueKind: .string
            ),
            .init(keyPath: "rendering.theme_name", title: "Theme", valueKind: .string),
            .init(keyPath: "rendering.font_ligatures_enabled", title: "Font Ligatures", valueKind: .boolean),
            .init(
                keyPath: "language.comment_configurations",
                title: "Comment Configurations",
                valueKind: .commentConfigurationDictionary
            ),
            .init(
                keyPath: "language.semantic_highlighting_enabled",
                title: "Semantic Highlighting",
                valueKind: .boolean
            ),
            .init(keyPath: "language.format_on_save_enabled", title: "Format on Save", valueKind: .boolean),
            .init(keyPath: "language.format_on_type_enabled", title: "Format on Type", valueKind: .boolean),
            .init(keyPath: "language.lsp_auto_restart.enabled", title: "LSP Auto-Restart", valueKind: .boolean),
            .init(
                keyPath: "language.lsp_auto_restart.max_attempts",
                title: "LSP Auto-Restart Max Attempts",
                valueKind: .integer,
                minimum: 0,
                maximum: 10
            ),
            .init(
                keyPath: "language.lsp_auto_restart.base_delay_seconds",
                title: "LSP Auto-Restart Base Delay",
                valueKind: .number,
                minimum: 0,
                maximum: 3_600
            ),
            .init(
                keyPath: "language.lsp_auto_restart.disabled_server_keys",
                title: "LSP Auto-Restart Disabled Servers",
                valueKind: .stringArray
            ),
            .init(
                keyPath: "language.lsp_auto_restart.server_max_attempts",
                title: "LSP Auto-Restart Server Attempts",
                valueKind: .integerDictionary,
                minimum: 0,
                maximum: 10
            ),
            .init(
                keyPath: "language.lsp_auto_restart.server_base_delay_seconds",
                title: "LSP Auto-Restart Server Delays",
                valueKind: .numberDictionary,
                minimum: 0,
                maximum: 3_600
            ),
            .init(
                keyPath: "workspace.root_url",
                title: "Workspace Root URL",
                valueKind: .string,
                supportsDocumentSelectors: false
            ),
            .init(
                keyPath: "workspace.root_path",
                title: "Workspace Root Path",
                valueKind: .string,
                supportsDocumentSelectors: false
            ),
            .init(
                keyPath: "workspace.find_in_files_default_scope",
                title: "Find in Files Scope",
                valueKind: .string,
                supportsDocumentSelectors: false,
                choices: [
                    .init(value: "opened_files", title: "Opened Files"),
                    .init(value: "workspace", title: "Workspace"),
                ]
            ),
            .init(
                keyPath: "workspace.workspace_search_include_globs",
                title: "Workspace Search Include Globs",
                valueKind: .stringArray,
                supportsDocumentSelectors: false
            ),
            .init(
                keyPath: "workspace.workspace_search_exclude_globs",
                title: "Workspace Search Exclude Globs",
                valueKind: .stringArray,
                supportsDocumentSelectors: false
            ),
        ]
    )
}
