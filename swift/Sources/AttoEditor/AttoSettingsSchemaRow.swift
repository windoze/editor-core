import CoreFoundation
import Foundation

struct AttoSettingsSchemaRow: Equatable {
    var keyPath: String
    var title: String
    var valueKind: AttoConfigurationSettingsValueKind
    var effectiveValue: String
    var source: String
    var overrideValue: String
    var validationError: String
}

enum AttoSettingsSchemaRows {
    static func make(
        schema: AttoConfigurationSettingsSchemaDescriptor,
        baseSnapshot: AttoConfigurationSnapshot,
        userSettings: AttoConfigurationSettings?,
        workspaceSettings: AttoConfigurationSettings?,
        runtimeSettings: AttoConfigurationSettings?,
        documentContext: AttoConfigurationDocumentContext? = nil,
        validationIssues: [AttoConfigurationSettingsValidationIssue] = []
    ) -> [AttoSettingsSchemaRow] {
        let resolution = baseSnapshot.resolvingSettings(
            user: userSettings,
            workspace: workspaceSettings,
            runtime: runtimeSettings,
            documentContext: documentContext
        )
        let effectiveJSONObject = AttoSettingsSchemaJSON.jsonObject(from: resolution.snapshot)
        let layers = [
            AttoSettingsSchemaLayer(scope: .user, settings: userSettings),
            AttoSettingsSchemaLayer(scope: .workspace, settings: workspaceSettings),
            AttoSettingsSchemaLayer(scope: .runtime, settings: runtimeSettings),
        ]

        return schema.fields.map { field in
            let effectiveValue = AttoSettingsSchemaJSON.displayValue(
                AttoSettingsSchemaJSON.value(for: field.keyPath, in: effectiveJSONObject)
            )
            let overrideEntries = overrideEntries(
                field: field,
                layers: layers
            )
            let source = effectiveSource(
                field: field,
                layers: layers,
                documentContext: documentContext
            )
            let validationError = validationText(
                for: field,
                issues: validationIssues
            )

            return AttoSettingsSchemaRow(
                keyPath: field.keyPath,
                title: field.title,
                valueKind: field.valueKind,
                effectiveValue: effectiveValue,
                source: source,
                overrideValue: overrideEntries.isEmpty ? "None" : overrideEntries.map(\.displayText).joined(separator: "; "),
                validationError: validationError
            )
        }
    }

    private static func effectiveSource(
        field: AttoConfigurationSettingsFieldSchema,
        layers: [AttoSettingsSchemaLayer],
        documentContext: AttoConfigurationDocumentContext?
    ) -> String {
        var source = "Default"
        for layer in layers {
            guard let settings = layer.settings else { continue }
            let settingsJSONObject = AttoSettingsSchemaJSON.jsonObject(from: settings)
            if AttoSettingsSchemaJSON.value(for: field.keyPath, in: settingsJSONObject) != nil {
                source = layer.scope.schemaDisplayName
            }

            guard let documentContext else { continue }
            for scopedSettings in settings.scopedSettings where scopedSettings.matches(documentContext) {
                let scopedJSONObject = AttoSettingsSchemaJSON.jsonObject(from: scopedSettings)
                if AttoSettingsSchemaJSON.value(for: field.keyPath, in: scopedJSONObject) != nil {
                    source = layer.scope.scopedVariant.schemaDisplayName
                }
            }
        }
        return source
    }

    private static func overrideEntries(
        field: AttoConfigurationSettingsFieldSchema,
        layers: [AttoSettingsSchemaLayer]
    ) -> [AttoSettingsSchemaOverrideEntry] {
        layers.flatMap { layer -> [AttoSettingsSchemaOverrideEntry] in
            guard let settings = layer.settings else { return [] }
            var entries: [AttoSettingsSchemaOverrideEntry] = []

            let settingsJSONObject = AttoSettingsSchemaJSON.jsonObject(from: settings)
            if let value = AttoSettingsSchemaJSON.value(for: field.keyPath, in: settingsJSONObject) {
                entries.append(AttoSettingsSchemaOverrideEntry(
                    label: layer.scope.schemaDisplayName,
                    value: AttoSettingsSchemaJSON.displayValue(value)
                ))
            }

            for (index, scopedSettings) in settings.scopedSettings.enumerated() {
                let scopedJSONObject = AttoSettingsSchemaJSON.jsonObject(from: scopedSettings)
                guard let value = AttoSettingsSchemaJSON.value(for: field.keyPath, in: scopedJSONObject) else {
                    continue
                }
                entries.append(AttoSettingsSchemaOverrideEntry(
                    label: scopedLabel(scope: layer.scope.scopedVariant, index: index, selectors: scopedSettings.selectors),
                    value: AttoSettingsSchemaJSON.displayValue(value)
                ))
            }

            return entries
        }
    }

    private static func scopedLabel(
        scope: AttoConfigurationSettingsScope,
        index: Int,
        selectors: [String]
    ) -> String {
        let label = "\(scope.schemaDisplayName)[\(index)]"
        let trimmedSelectors = selectors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard trimmedSelectors.isEmpty == false else { return label }
        return "\(label) (\(trimmedSelectors.joined(separator: ", ")))"
    }

    private static func validationText(
        for field: AttoConfigurationSettingsFieldSchema,
        issues: [AttoConfigurationSettingsValidationIssue]
    ) -> String {
        issues
            .filter { issueMatches(fieldKeyPath: field.keyPath, issueKeyPath: $0.keyPath) }
            .map { "\($0.scope.schemaDisplayName): \($0.message)" }
            .joined(separator: "; ")
    }

    private static func issueMatches(fieldKeyPath: String, issueKeyPath: String) -> Bool {
        if issuePath(issueKeyPath, matches: fieldKeyPath) {
            return true
        }
        guard issueKeyPath.hasPrefix("scoped_settings["),
              let suffixRange = issueKeyPath.range(of: "].")
        else {
            return false
        }
        let suffix = String(issueKeyPath[suffixRange.upperBound...])
        return issuePath(suffix, matches: fieldKeyPath)
    }

    private static func issuePath(_ issueKeyPath: String, matches fieldKeyPath: String) -> Bool {
        issueKeyPath == fieldKeyPath || issueKeyPath.hasPrefix("\(fieldKeyPath)[")
    }
}

private struct AttoSettingsSchemaLayer {
    var scope: AttoConfigurationSettingsScope
    var settings: AttoConfigurationSettings?
}

private struct AttoSettingsSchemaOverrideEntry {
    var label: String
    var value: String

    var displayText: String {
        "\(label): \(value)"
    }
}

private enum AttoSettingsSchemaJSON {
    static func jsonObject<Value: Encodable>(from value: Value) -> Any? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func value(for keyPath: String, in jsonObject: Any?) -> Any? {
        var current = jsonObject
        for component in keyPath.split(separator: ".").map(String.init) {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[component]
        }
        return current is NSNull ? nil : current
    }

    static func displayValue(_ value: Any?) -> String {
        guard let value else { return "Unset" }

        if let string = value as? String {
            return string.isEmpty ? "\"\"" : string
        }
        if let number = value as? NSNumber {
            return displayNumber(number)
        }
        if let array = value as? [Any] {
            return displayJSONObject(array)
        }
        if let dictionary = value as? [String: Any] {
            return displayJSONObject(dictionary)
        }
        return String(describing: value)
    }

    private static func displayNumber(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }

        let value = number.doubleValue
        if value.rounded() == value {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func displayJSONObject(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: object)
        }
        return text
    }
}

private extension AttoConfigurationSettingsScope {
    var schemaDisplayName: String {
        switch self {
        case .user:
            return "User"
        case .userScoped:
            return "User Scoped"
        case .workspace:
            return "Workspace"
        case .workspaceScoped:
            return "Workspace Scoped"
        case .runtime:
            return "Runtime"
        case .runtimeScoped:
            return "Runtime Scoped"
        }
    }
}
