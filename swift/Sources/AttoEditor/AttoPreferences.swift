import EditorCoreUIFFI
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
        static let autoPairsEnabled = "AttoEditor.preferences.autoPairsEnabled"
        static let wrapMode = "AttoEditor.preferences.wrapMode"
        static let wrapIndent = "AttoEditor.preferences.wrapIndent"
        static let themeName = "AttoEditor.preferences.themeName"
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

    var effectiveAutoPairsEnabled: Bool {
        if let stored = storedAutoPairsEnabled { return stored }
        if let parsed = Self.parseBoolEnv(env["ATTO_EDITOR_AUTO_PAIRS"])
            ?? Self.parseBoolEnv(env["EDITOR_CORE_APPKIT_AUTO_PAIRS"])
        {
            return parsed
        }
        return true
    }

    var effectiveWrapMode: EcuWrapMode {
        if let stored = storedWrapMode { return stored }
        if let parsed = Self.parseWrapModeEnv(env["ATTO_EDITOR_WRAP_MODE"])
            ?? Self.parseWrapModeEnv(env["EDITOR_CORE_APPKIT_WRAP_MODE"])
        {
            return parsed
        }
        return .char
    }

    var effectiveWrapIndent: EcuWrapIndent {
        if let stored = storedWrapIndent { return stored }
        if let parsed = Self.parseWrapIndentString(env["ATTO_EDITOR_WRAP_INDENT"])
            ?? Self.parseWrapIndentString(env["EDITOR_CORE_APPKIT_WRAP_INDENT"])
        {
            return parsed
        }
        return .none
    }

    var effectiveThemeName: String {
        if let stored = storedThemeName, stored.isEmpty == false { return stored }

        if let fromEnv = env["ATTO_EDITOR_THEME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           fromEnv.isEmpty == false
        {
            return fromEnv
        }

        return AttoThemeManager.defaultThemeName
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

    var storedAutoPairsEnabled: Bool? {
        defaults.object(forKey: Keys.autoPairsEnabled) as? Bool
    }

    var storedWrapMode: EcuWrapMode? {
        guard let raw = defaults.string(forKey: Keys.wrapMode) else { return nil }
        return EcuWrapMode(rawValue: raw)
    }

    var storedWrapIndent: EcuWrapIndent? {
        Self.parseWrapIndentString(defaults.string(forKey: Keys.wrapIndent))
    }

    var storedThemeName: String? {
        guard let raw = defaults.string(forKey: Keys.themeName) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    func setAutoPairsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.autoPairsEnabled)
        postDidChange()
    }

    func clearAutoPairsEnabled() {
        defaults.removeObject(forKey: Keys.autoPairsEnabled)
        postDidChange()
    }

    func setWrapMode(_ mode: EcuWrapMode?) {
        if let mode {
            defaults.set(mode.rawValue, forKey: Keys.wrapMode)
        } else {
            defaults.removeObject(forKey: Keys.wrapMode)
        }
        postDidChange()
    }

    func setWrapIndent(_ indent: EcuWrapIndent?) {
        if let indent {
            defaults.set(Self.wrapIndentStorageString(indent), forKey: Keys.wrapIndent)
        } else {
            defaults.removeObject(forKey: Keys.wrapIndent)
        }
        postDidChange()
    }

    func setThemeName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty == false {
            defaults.set(trimmed, forKey: Keys.themeName)
        } else {
            defaults.removeObject(forKey: Keys.themeName)
        }
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

    private static func parseBoolEnv(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func parseWrapModeEnv(_ raw: String?) -> EcuWrapMode? {
        guard let raw else { return nil }
        return EcuWrapMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func wrapIndentStorageString(_ indent: EcuWrapIndent) -> String {
        switch indent {
        case .none:
            return "none"
        case .sameAsLineIndent:
            return "same_as_line_indent"
        case let .fixedCells(cells):
            return "fixed_cells:\(cells)"
        }
    }

    static func parseWrapIndentString(_ raw: String?) -> EcuWrapIndent? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.isEmpty == false else { return nil }

        switch s {
        case "none", "off":
            return EcuWrapIndent.none
        case "same_as_line_indent", "same-as-line-indent", "same":
            return .sameAsLineIndent
        default:
            break
        }

        for prefix in ["fixed_cells:", "fixed-cells:", "fixed:"] {
            guard s.hasPrefix(prefix) else { continue }
            let rawNumber = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cells = UInt32(rawNumber) else { return nil }
            return .fixedCells(cells)
        }

        return nil
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .attoPreferencesDidChange, object: self)
    }
}
