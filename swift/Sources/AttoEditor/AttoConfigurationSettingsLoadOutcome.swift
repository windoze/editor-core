import Foundation

struct AttoConfigurationSettingsLoadOutcome: Equatable {
    var settings: AttoConfigurationSettings?
    var event: AttoConfigurationSettingsLoadEvent?
}

enum AttoConfigurationSettingsLoadEvent: Equatable {
    case invalidBackedUp(settingsURL: URL, backupURL: URL)
    case migrated(settingsURL: URL, backupURL: URL, fromSchemaVersion: Int)

    var eventKey: String {
        switch self {
        case .invalidBackedUp(let settingsURL, let backupURL):
            return "invalid|\(settingsURL.path)|\(backupURL.path)"
        case .migrated(let settingsURL, let backupURL, let fromSchemaVersion):
            return "migrated|\(settingsURL.path)|\(backupURL.path)|\(fromSchemaVersion)"
        }
    }

    func statusText(displayName: String) -> String {
        switch self {
        case .invalidBackedUp:
            return "\(displayName) invalid; using fallback settings"
        case .migrated(_, _, let fromSchemaVersion):
            return "\(displayName) migrated from schema v\(fromSchemaVersion)"
        }
    }

    func logText(displayName: String) -> String {
        switch self {
        case .invalidBackedUp(let settingsURL, let backupURL):
            return "\(displayName) invalid at \(settingsURL.path); backed up to \(backupURL.path) and using fallback settings"
        case .migrated(let settingsURL, let backupURL, let fromSchemaVersion):
            return "\(displayName) migrated at \(settingsURL.path) from schema v\(fromSchemaVersion); original backed up to \(backupURL.path)"
        }
    }
}
