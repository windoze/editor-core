import Foundation

extension Notification.Name {
    static let attoPreferencesDidChange = Notification.Name("AttoEditor.attoPreferencesDidChange")
}

/// User-configurable preferences for AttoEditor.
///
/// Notes:
/// - Values are persisted via `UserDefaults.standard`.
/// - When a preference is not explicitly set by the user, we fall back to environment variables
///   (for parity with existing demo/dev workflows).
@MainActor
final class AttoPreferences: NSObject {
    static let shared = AttoPreferences()

    private enum Keys {
        static let fontFaces = "AttoEditor.preferences.fontFaces"
        static let fontSizePoints = "AttoEditor.preferences.fontSizePoints"
        static let ligaturesEnabled = "AttoEditor.preferences.ligaturesEnabled"
    }

    private let defaults: UserDefaults
    private let env: [String: String]

    init(defaults: UserDefaults = .standard, env: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.env = env
        super.init()
    }

    // MARK: - Effective (stored ⟶ env ⟶ default)

    var effectiveFontFaces: [String] {
        if let stored = storedFontFaces { return stored }

        let csv = env["ATTO_EDITOR_FONT_FAMILIES"] ?? env["EDITOR_CORE_APPKIT_FONT_FAMILIES"]
        if let csv, csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return Self.normalizeFontFaces(Self.parseCSVFontFaces(csv))
        }
        return []
    }

    var effectiveFontSizePoints: Double {
        if let stored = storedFontSizePoints { return stored }
        return 13.0
    }

    var effectiveLigaturesEnabled: Bool {
        if let stored = storedLigaturesEnabled { return stored }
        return (env["ATTO_EDITOR_ENABLE_LIGATURES"] == "1") || (env["EDITOR_CORE_APPKIT_ENABLE_LIGATURES"] == "1")
    }

    // MARK: - Stored (explicit user preference)

    var storedFontFaces: [String]? {
        defaults.stringArray(forKey: Keys.fontFaces).map(Self.normalizeFontFaces)
    }

    var storedFontSizePoints: Double? {
        guard let v = defaults.object(forKey: Keys.fontSizePoints) as? Double else { return nil }
        return Self.normalizeFontSizePoints(v)
    }

    var storedLigaturesEnabled: Bool? {
        defaults.object(forKey: Keys.ligaturesEnabled) as? Bool
    }

    func setFontFaces(_ faces: [String]) {
        let normalized = Self.normalizeFontFaces(faces)
        defaults.set(normalized, forKey: Keys.fontFaces)
        postDidChange()
    }

    func setFontSizePoints(_ size: Double) {
        defaults.set(Self.normalizeFontSizePoints(size), forKey: Keys.fontSizePoints)
        postDidChange()
    }

    func setLigaturesEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.ligaturesEnabled)
        postDidChange()
    }

    // MARK: - Convenience formatting

    /// For initial view construction. Returns `nil` when no override is needed.
    func fontFamiliesCSVForNewViews() -> String? {
        let faces = effectiveFontFaces
        guard faces.isEmpty == false else { return nil }
        return faces.joined(separator: ", ")
    }

    /// For applying to already-created editor views. Empty string means "reset to default".
    func fontFamiliesCSVForApplying() -> String {
        let faces = effectiveFontFaces
        return faces.joined(separator: ", ")
    }

    func fontFacesMultilineTextForUI() -> String {
        let faces = effectiveFontFaces
        if faces.isEmpty {
            return Self.systemDefaultFontFacesForUI().joined(separator: "\n")
        }
        return faces.joined(separator: "\n")
    }

    static func parseMultilineFontFaces(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
    }

    static func parseCSVFontFaces(_ csv: String) -> [String] {
        csv
            .split(separator: ",")
            .map { String($0) }
    }

    /// The default fallback chain we use when no explicit font faces are configured.
    ///
    /// This is used for UI display only (so the font list isn't empty when using "System Default").
    private static func systemDefaultFontFacesForUI() -> [String] {
        // Keep this aligned with the Skia renderer defaults (see `default_font_families()` on the Rust side).
        [
            // Primary monospace candidates.
            "Menlo",
            "SF Mono",
            "Monaco",
            "Courier New",
            "Courier",
            // CJK fallbacks.
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            // Emoji fallback.
            "Apple Color Emoji",
        ]
    }

    // MARK: - Normalization

    private static func normalizeFontFaces(_ faces: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(faces.count)

        var seen: Set<String> = Set()
        for raw in faces {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            // Case-insensitive de-dupe while preserving original casing.
            let key = trimmed.lowercased()
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }

    private static func normalizeFontSizePoints(_ v: Double) -> Double {
        guard v.isFinite else { return 13.0 }
        return min(max(v, 6.0), 72.0)
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .attoPreferencesDidChange, object: self)
    }
}
