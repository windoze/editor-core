import Foundation

enum AttoConfigurationSettingsValidationSeverity: String, Codable, Equatable {
    case error
    case warning
}

struct AttoConfigurationSettingsValidationIssue: Codable, Equatable {
    var keyPath: String
    var message: String
    var severity: AttoConfigurationSettingsValidationSeverity
    var scope: AttoConfigurationSettingsScope
}

struct AttoConfigurationSettingsValidationResult: Codable, Equatable {
    var issues: [AttoConfigurationSettingsValidationIssue]

    var isValid: Bool {
        issues.contains { $0.severity == .error } == false
    }
}

extension AttoConfigurationSettingsSchemaDescriptor {
    func validate(
        _ settings: AttoConfigurationSettings,
        scope: AttoConfigurationSettingsScope = .user
    ) -> AttoConfigurationSettingsValidationResult {
        var validator = AttoConfigurationSettingsValidator(schema: self)
        validator.validate(settings, scope: scope)
        return AttoConfigurationSettingsValidationResult(issues: validator.issues)
    }
}

private struct AttoConfigurationSettingsValidator {
    let schema: AttoConfigurationSettingsSchemaDescriptor
    var issues: [AttoConfigurationSettingsValidationIssue] = []

    mutating func validate(
        _ settings: AttoConfigurationSettings,
        scope: AttoConfigurationSettingsScope
    ) {
        validateEditor(settings.editor, scope: scope, prefix: "")
        validateLanguage(settings.language, scope: scope, prefix: "")
        validateWorkspace(settings.workspace, scope: scope, prefix: "")

        for (index, scopedSettings) in settings.scopedSettings.enumerated() {
            let scopedScope = scope.scopedVariant
            let prefix = "scoped_settings[\(index)]."
            validateSelectors(scopedSettings.selectors, scope: scopedScope, keyPath: "\(prefix)selectors")
            validateEditor(scopedSettings.editor, scope: scopedScope, prefix: prefix)
            validateLanguage(scopedSettings.language, scope: scopedScope, prefix: prefix)
        }
    }

    private mutating func validateEditor(
        _ settings: AttoEditorPreferenceSettings?,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let settings else { return }
        validateNumber(settings.fontSizePoints, field: "editor.font_size_points", scope: scope, prefix: prefix)
        validateChoice(settings.wrapMode, field: "editor.wrap_mode", scope: scope, prefix: prefix)
        validateWrapIndent(settings.wrapIndent, scope: scope, prefix: prefix)
    }

    private mutating func validateLanguage(
        _ settings: AttoLanguagePreferenceSettings?,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let settings else { return }
        validateLspAutoRestart(settings.lspAutoRestart, scope: scope, prefix: prefix)
    }

    private mutating func validateWorkspace(
        _ settings: AttoWorkspacePreferenceSettings?,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let settings else { return }
        validateChoice(
            settings.findInFilesDefaultScope,
            field: "workspace.find_in_files_default_scope",
            scope: scope,
            prefix: prefix
        )
    }

    private mutating func validateLspAutoRestart(
        _ settings: AttoLspAutoRestartPolicySettings?,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let settings else { return }
        validateInteger(
            settings.maxAttempts,
            field: "language.lsp_auto_restart.max_attempts",
            scope: scope,
            prefix: prefix
        )
        validateNumber(
            settings.baseDelaySeconds,
            field: "language.lsp_auto_restart.base_delay_seconds",
            scope: scope,
            prefix: prefix
        )
        validateIntegerDictionary(
            settings.serverMaxAttempts,
            field: "language.lsp_auto_restart.server_max_attempts",
            scope: scope,
            prefix: prefix
        )
        validateNumberDictionary(
            settings.serverBaseDelaySeconds,
            field: "language.lsp_auto_restart.server_base_delay_seconds",
            scope: scope,
            prefix: prefix
        )
    }

    private mutating func validateSelectors(
        _ selectors: [String],
        scope: AttoConfigurationSettingsScope,
        keyPath: String
    ) {
        guard selectors.isEmpty == false else {
            addIssue(keyPath: keyPath, scope: scope, message: "Scoped settings must include at least one selector.")
            return
        }
        if selectors.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            addIssue(keyPath: keyPath, scope: scope, message: "Scoped settings selectors cannot be empty.")
        }
    }

    private mutating func validateChoice(
        _ value: String?,
        field keyPath: String,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let value else { return }
        guard let field = field(keyPath, scope: scope) else { return }
        guard field.choices.isEmpty == false else { return }
        let allowedValues = Set(field.choices.map(\.value))
        if allowedValues.contains(value) == false {
            addIssue(
                keyPath: prefixed(prefix, keyPath),
                scope: scope,
                message: "Value '\(value)' is not one of: \(field.choices.map(\.value).joined(separator: ", "))."
            )
        }
    }

    private mutating func validateWrapIndent(
        _ value: String?,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let value else { return }
        guard field("editor.wrap_indent", scope: scope) != nil else { return }
        if isValidWrapIndent(value) == false {
            addIssue(
                keyPath: prefixed(prefix, "editor.wrap_indent"),
                scope: scope,
                message: "Wrap indent must be 'none', 'same_as_line_indent', or 'fixed_cells:<number>'."
            )
        }
    }

    private mutating func validateInteger(
        _ value: Int?,
        field keyPath: String,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let value else { return }
        validateNumber(Double(value), field: keyPath, scope: scope, prefix: prefix)
    }

    private mutating func validateNumber(
        _ value: Double?,
        field keyPath: String,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let value else { return }
        guard let field = field(keyPath, scope: scope) else { return }
        validateNumberValue(value, field: field, issuePath: prefixed(prefix, keyPath), scope: scope)
    }

    private mutating func validateNumberValue(
        _ value: Double,
        field: AttoConfigurationSettingsFieldSchema,
        issuePath: String,
        scope: AttoConfigurationSettingsScope
    ) {
        guard value.isFinite else {
            addIssue(keyPath: issuePath, scope: scope, message: "Value must be finite.")
            return
        }
        if let minimum = field.minimum, value < minimum {
            addIssue(keyPath: issuePath, scope: scope, message: "Value must be at least \(format(minimum)).")
        }
        if let maximum = field.maximum, value > maximum {
            addIssue(keyPath: issuePath, scope: scope, message: "Value must be at most \(format(maximum)).")
        }
    }

    private mutating func validateIntegerDictionary(
        _ values: [String: Int]?,
        field keyPath: String,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let values else { return }
        guard let field = field(keyPath, scope: scope) else { return }
        for (key, value) in values {
            validateNumberValue(
                Double(value),
                field: field,
                issuePath: "\(prefixed(prefix, keyPath))[\(key)]",
                scope: scope
            )
        }
    }

    private mutating func validateNumberDictionary(
        _ values: [String: Double]?,
        field keyPath: String,
        scope: AttoConfigurationSettingsScope,
        prefix: String
    ) {
        guard let values else { return }
        guard let field = field(keyPath, scope: scope) else { return }
        for (key, value) in values {
            validateNumberValue(
                value,
                field: field,
                issuePath: "\(prefixed(prefix, keyPath))[\(key)]",
                scope: scope
            )
        }
    }

    private func field(
        _ keyPath: String,
        scope: AttoConfigurationSettingsScope
    ) -> AttoConfigurationSettingsFieldSchema? {
        guard let field = schema.field(keyPath: keyPath) else { return nil }
        guard field.supports(scope) else { return nil }
        return field
    }

    private mutating func addIssue(
        keyPath: String,
        scope: AttoConfigurationSettingsScope,
        message: String,
        severity: AttoConfigurationSettingsValidationSeverity = .error
    ) {
        issues.append(AttoConfigurationSettingsValidationIssue(
            keyPath: keyPath,
            message: message,
            severity: severity,
            scope: scope
        ))
    }

    private func prefixed(_ prefix: String, _ keyPath: String) -> String {
        "\(prefix)\(keyPath)"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func isValidWrapIndent(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.isEmpty == false else { return false }
        if ["none", "off", "same_as_line_indent", "same-as-line-indent", "same"].contains(value) {
            return true
        }

        for prefix in ["fixed_cells:", "fixed-cells:", "fixed:"] where value.hasPrefix(prefix) {
            let rawNumber = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return UInt32(rawNumber) != nil
        }
        return false
    }
}

private extension AttoConfigurationSettingsFieldSchema {
    func supports(_ scope: AttoConfigurationSettingsScope) -> Bool {
        supportedScopes.contains(scope.baseVariant)
            && (scope.isScoped == false || supportsDocumentSelectors)
    }
}

private extension AttoConfigurationSettingsScope {
    var baseVariant: Self {
        switch self {
        case .user, .userScoped:
            return .user
        case .workspace, .workspaceScoped:
            return .workspace
        case .runtime, .runtimeScoped:
            return .runtime
        }
    }

    var isScoped: Bool {
        switch self {
        case .userScoped, .workspaceScoped, .runtimeScoped:
            return true
        case .user, .workspace, .runtime:
            return false
        }
    }
}
