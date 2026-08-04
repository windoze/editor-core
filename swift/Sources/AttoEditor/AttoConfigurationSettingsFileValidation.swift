import Foundation

enum AttoConfigurationSettingsFileValidationError: Error, Equatable {
    case missingFile(URL)
}

struct AttoConfigurationSettingsFileValidationReport: Equatable {
    var url: URL
    var scope: AttoConfigurationSettingsScope
    var settings: AttoConfigurationSettings
    var result: AttoConfigurationSettingsValidationResult
    var issueLocations: [String: AttoConfigurationSettingsJSONSourceLocation] = [:]

    func location(for issue: AttoConfigurationSettingsValidationIssue) -> AttoConfigurationSettingsJSONSourceLocation? {
        issueLocations[issue.keyPath]
    }
}

extension AttoConfigurationSettingsSchemaDescriptor {
    func validateSettingsFile(
        at url: URL,
        scope: AttoConfigurationSettingsScope
    ) throws -> AttoConfigurationSettingsFileValidationReport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AttoConfigurationSettingsFileValidationError.missingFile(url)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AttoConfigurationSettings.self, from: data)
        let settings = decoded.migratedToCurrentSchema()
        let result = validate(settings, scope: scope)
        let source = String(decoding: data, as: UTF8.self)
        let sourceLocations = AttoConfigurationSettingsJSONLocationIndex.locations(in: source)
        var issueLocations: [String: AttoConfigurationSettingsJSONSourceLocation] = [:]
        for issue in result.issues where issueLocations[issue.keyPath] == nil {
            issueLocations[issue.keyPath] = sourceLocations[issue.keyPath]
        }

        return AttoConfigurationSettingsFileValidationReport(
            url: url,
            scope: scope,
            settings: settings,
            result: result,
            issueLocations: issueLocations
        )
    }
}
