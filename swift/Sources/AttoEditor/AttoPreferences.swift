import EditorCoreUIFFI
import Foundation

struct AttoCommentConfiguration: Equatable {
    var line: String?
    var blockStart: String?
    var blockEnd: String?

    var jsonObject: [String: String] {
        var out: [String: String] = [:]
        if let line { out["line"] = line }
        if let blockStart { out["block_start"] = blockStart }
        if let blockEnd { out["block_end"] = blockEnd }
        return out
    }

    var normalized: Self? {
        let line = line?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let blockStart = blockStart?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let blockEnd = blockEnd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if blockStart != nil, blockEnd == nil { return nil }
        if blockStart == nil, blockEnd != nil { return nil }
        if line == nil, blockStart == nil { return nil }

        return Self(line: line, blockStart: blockStart, blockEnd: blockEnd)
    }

    static func line(_ token: String) -> Self {
        Self(line: token, blockStart: nil, blockEnd: nil)
    }

    static func block(_ start: String, _ end: String) -> Self {
        Self(line: nil, blockStart: start, blockEnd: end)
    }

    static func lineAndBlock(_ line: String, _ start: String, _ end: String) -> Self {
        Self(line: line, blockStart: start, blockEnd: end)
    }
}

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
        static let commentConfigurations = "AttoEditor.preferences.commentConfigurations"
        static let lspAutoRestartEnabled = "AttoEditor.preferences.lspAutoRestartEnabled"
        static let lspAutoRestartMaxAttempts = "AttoEditor.preferences.lspAutoRestartMaxAttempts"
        static let lspAutoRestartBaseDelaySeconds = "AttoEditor.preferences.lspAutoRestartBaseDelaySeconds"
        static let lspAutoRestartDisabledServerKeys = "AttoEditor.preferences.lspAutoRestartDisabledServerKeys"
        static let lspAutoRestartServerMaxAttempts = "AttoEditor.preferences.lspAutoRestartServerMaxAttempts"
        static let lspAutoRestartServerBaseDelaySeconds = "AttoEditor.preferences.lspAutoRestartServerBaseDelaySeconds"
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

    var effectiveLspAutoRestartEnabled: Bool {
        if let stored = storedLspAutoRestartEnabled { return stored }
        if let parsed = Self.parseBoolEnv(env["ATTO_EDITOR_LSP_AUTO_RESTART"])
            ?? Self.parseBoolEnv(env["EDITOR_CORE_APPKIT_LSP_AUTO_RESTART"])
        {
            return parsed
        }
        return true
    }

    var effectiveLspAutoRestartMaxAttempts: Int {
        if let stored = storedLspAutoRestartMaxAttempts { return stored }
        if let parsed = Self.parseIntEnv(env["ATTO_EDITOR_LSP_AUTO_RESTART_MAX_ATTEMPTS"])
            ?? Self.parseIntEnv(env["EDITOR_CORE_APPKIT_LSP_AUTO_RESTART_MAX_ATTEMPTS"])
        {
            return Self.normalizeLspAutoRestartMaxAttempts(parsed)
        }
        return 3
    }

    var effectiveLspAutoRestartBaseDelaySeconds: Double {
        if let stored = storedLspAutoRestartBaseDelaySeconds { return stored }
        if let parsed = Self.parseDoubleEnv(env["ATTO_EDITOR_LSP_AUTO_RESTART_BASE_DELAY_SECONDS"])
            ?? Self.parseDoubleEnv(env["EDITOR_CORE_APPKIT_LSP_AUTO_RESTART_BASE_DELAY_SECONDS"])
        {
            return Self.normalizeLspAutoRestartBaseDelaySeconds(parsed)
        }
        return 5.0
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

    var storedCommentConfigurations: [String: AttoCommentConfiguration] {
        commentConfigurationStorage().compactMapValues(Self.parseCommentConfiguration)
    }

    var storedLspAutoRestartEnabled: Bool? {
        defaults.object(forKey: Keys.lspAutoRestartEnabled) as? Bool
    }

    var storedLspAutoRestartMaxAttempts: Int? {
        guard let raw = defaults.object(forKey: Keys.lspAutoRestartMaxAttempts) else { return nil }
        if let value = raw as? NSNumber {
            return Self.normalizeLspAutoRestartMaxAttempts(value.intValue)
        }
        if let value = raw as? Int {
            return Self.normalizeLspAutoRestartMaxAttempts(value)
        }
        return nil
    }

    var storedLspAutoRestartBaseDelaySeconds: Double? {
        guard let raw = defaults.object(forKey: Keys.lspAutoRestartBaseDelaySeconds) else { return nil }
        if let value = raw as? NSNumber {
            return Self.normalizeLspAutoRestartBaseDelaySeconds(value.doubleValue)
        }
        if let value = raw as? Double {
            return Self.normalizeLspAutoRestartBaseDelaySeconds(value)
        }
        return nil
    }

    var storedLspAutoRestartDisabledServerKeys: [String] {
        Self.normalizeLspAutoRestartServerKeys(
            defaults.stringArray(forKey: Keys.lspAutoRestartDisabledServerKeys) ?? []
        )
    }

    var storedLspAutoRestartServerMaxAttempts: [String: Int] {
        Self.normalizeLspAutoRestartServerMaxAttempts(
            defaults.dictionary(forKey: Keys.lspAutoRestartServerMaxAttempts) ?? [:]
        )
    }

    var storedLspAutoRestartServerBaseDelaySeconds: [String: Double] {
        Self.normalizeLspAutoRestartServerBaseDelaySeconds(
            defaults.dictionary(forKey: Keys.lspAutoRestartServerBaseDelaySeconds) ?? [:]
        )
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

    func setLspAutoRestartEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.lspAutoRestartEnabled)
        postDidChange()
    }

    func setLspAutoRestartMaxAttempts(_ attempts: Int) {
        defaults.set(Self.normalizeLspAutoRestartMaxAttempts(attempts), forKey: Keys.lspAutoRestartMaxAttempts)
        postDidChange()
    }

    func setLspAutoRestartBaseDelaySeconds(_ seconds: Double) {
        defaults.set(Self.normalizeLspAutoRestartBaseDelaySeconds(seconds), forKey: Keys.lspAutoRestartBaseDelaySeconds)
        postDidChange()
    }

    func effectiveLspAutoRestartMaxAttempts(serverName: String?, serverCommand: String?) -> Int {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return effectiveLspAutoRestartMaxAttempts
        }
        return storedLspAutoRestartServerMaxAttempts[key] ?? effectiveLspAutoRestartMaxAttempts
    }

    func effectiveLspAutoRestartBaseDelaySeconds(serverName: String?, serverCommand: String?) -> Double {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return effectiveLspAutoRestartBaseDelaySeconds
        }
        return storedLspAutoRestartServerBaseDelaySeconds[key] ?? effectiveLspAutoRestartBaseDelaySeconds
    }

    func hasLspAutoRestartPolicyOverrideForServer(serverName: String?, serverCommand: String?) -> Bool {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return false
        }
        return storedLspAutoRestartDisabledServerKeys.contains(key)
            || storedLspAutoRestartServerMaxAttempts.keys.contains(key)
            || storedLspAutoRestartServerBaseDelaySeconds.keys.contains(key)
    }

    func isLspAutoRestartDisabledForServer(serverName: String?, serverCommand: String?) -> Bool {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return false
        }
        return storedLspAutoRestartDisabledServerKeys.contains(key)
    }

    func setLspAutoRestartDisabled(
        _ disabled: Bool,
        forServerName serverName: String?,
        serverCommand: String?
    ) {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return
        }
        var keys = Set(storedLspAutoRestartDisabledServerKeys)
        if disabled {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        let sorted = keys.sorted()
        if sorted.isEmpty {
            defaults.removeObject(forKey: Keys.lspAutoRestartDisabledServerKeys)
        } else {
            defaults.set(sorted, forKey: Keys.lspAutoRestartDisabledServerKeys)
        }
        postDidChange()
    }

    func setLspAutoRestartMaxAttempts(
        _ attempts: Int,
        forServerName serverName: String?,
        serverCommand: String?
    ) {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return
        }
        var overrides = storedLspAutoRestartServerMaxAttempts
        overrides[key] = Self.normalizeLspAutoRestartMaxAttempts(attempts)
        defaults.set(overrides, forKey: Keys.lspAutoRestartServerMaxAttempts)
        postDidChange()
    }

    func setLspAutoRestartBaseDelaySeconds(
        _ seconds: Double,
        forServerName serverName: String?,
        serverCommand: String?
    ) {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return
        }
        var overrides = storedLspAutoRestartServerBaseDelaySeconds
        overrides[key] = Self.normalizeLspAutoRestartBaseDelaySeconds(seconds)
        defaults.set(overrides, forKey: Keys.lspAutoRestartServerBaseDelaySeconds)
        postDidChange()
    }

    func resetLspAutoRestartPolicy(forServerName serverName: String?, serverCommand: String?) {
        guard let key = Self.lspAutoRestartServerKey(serverName: serverName, serverCommand: serverCommand) else {
            return
        }

        var disabledKeys = Set(storedLspAutoRestartDisabledServerKeys)
        disabledKeys.remove(key)
        if disabledKeys.isEmpty {
            defaults.removeObject(forKey: Keys.lspAutoRestartDisabledServerKeys)
        } else {
            defaults.set(disabledKeys.sorted(), forKey: Keys.lspAutoRestartDisabledServerKeys)
        }

        var maxAttempts = storedLspAutoRestartServerMaxAttempts
        maxAttempts.removeValue(forKey: key)
        if maxAttempts.isEmpty {
            defaults.removeObject(forKey: Keys.lspAutoRestartServerMaxAttempts)
        } else {
            defaults.set(maxAttempts, forKey: Keys.lspAutoRestartServerMaxAttempts)
        }

        var baseDelay = storedLspAutoRestartServerBaseDelaySeconds
        baseDelay.removeValue(forKey: key)
        if baseDelay.isEmpty {
            defaults.removeObject(forKey: Keys.lspAutoRestartServerBaseDelaySeconds)
        } else {
            defaults.set(baseDelay, forKey: Keys.lspAutoRestartServerBaseDelaySeconds)
        }

        postDidChange()
    }

    func commentConfigurationOverride(forLanguageKey languageKey: String) -> AttoCommentConfiguration? {
        storedCommentConfigurations[Self.normalizeCommentConfigurationKey(languageKey)]
    }

    func setCommentConfiguration(_ configuration: AttoCommentConfiguration?, forLanguageKey rawKey: String) {
        let key = Self.normalizeCommentConfigurationKey(rawKey)
        guard key.isEmpty == false else { return }

        var storage = commentConfigurationStorage()
        if let normalized = configuration?.normalized {
            storage[key] = Self.commentConfigurationStorageObject(normalized)
        } else {
            storage.removeValue(forKey: key)
        }

        if storage.isEmpty {
            defaults.removeObject(forKey: Keys.commentConfigurations)
        } else {
            defaults.set(storage, forKey: Keys.commentConfigurations)
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

    private static func normalizeLspAutoRestartMaxAttempts(_ v: Int) -> Int {
        min(max(v, 0), 10)
    }

    private static func normalizeLspAutoRestartBaseDelaySeconds(_ v: Double) -> Double {
        guard v.isFinite else { return 5.0 }
        return min(max(v, 0.0), 3_600.0)
    }

    static func lspAutoRestartServerKey(serverName: String?, serverCommand: String?) -> String? {
        let raw = serverName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? serverCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let raw else { return nil }
        return raw.lowercased()
    }

    private static func normalizeLspAutoRestartServerKeys(_ keys: [String]) -> [String] {
        Array(Set(keys.compactMap { raw in
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return key.isEmpty ? nil : key
        })).sorted()
    }

    private static func normalizeLspAutoRestartServerMaxAttempts(_ raw: [String: Any]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (rawKey, rawValue) in raw {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key.isEmpty == false else { continue }
            guard let value = parseStoredInt(rawValue) else { continue }
            out[key] = normalizeLspAutoRestartMaxAttempts(value)
        }
        return out
    }

    private static func normalizeLspAutoRestartServerBaseDelaySeconds(_ raw: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (rawKey, rawValue) in raw {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key.isEmpty == false else { continue }
            guard let value = parseStoredDouble(rawValue) else { continue }
            out[key] = normalizeLspAutoRestartBaseDelaySeconds(value)
        }
        return out
    }

    static func normalizeCommentConfigurationKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func commentConfigurationStorage() -> [String: [String: String]] {
        guard let raw = defaults.dictionary(forKey: Keys.commentConfigurations) else { return [:] }

        var out: [String: [String: String]] = [:]
        for (rawKey, rawValue) in raw {
            let key = Self.normalizeCommentConfigurationKey(rawKey)
            guard key.isEmpty == false else { continue }

            if let value = rawValue as? [String: String] {
                out[key] = value
            } else if let value = rawValue as? [String: Any] {
                out[key] = value.compactMapValues { $0 as? String }
            }
        }
        return out
    }

    private static func parseCommentConfiguration(_ raw: [String: String]) -> AttoCommentConfiguration? {
        AttoCommentConfiguration(
            line: raw["line"],
            blockStart: raw["block_start"],
            blockEnd: raw["block_end"]
        ).normalized
    }

    private static func commentConfigurationStorageObject(_ configuration: AttoCommentConfiguration) -> [String: String] {
        configuration.jsonObject
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

    private static func parseIntEnv(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseDoubleEnv(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseStoredInt(_ raw: Any) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = raw as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func parseStoredDouble(_ raw: Any) -> Double? {
        if let value = raw as? Double {
            return value
        }
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        if let value = raw as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
