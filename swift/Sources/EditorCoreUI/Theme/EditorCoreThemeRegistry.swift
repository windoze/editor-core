import Foundation

/// A merged theme registry keyed by theme name (case-insensitive).
///
/// The registry is intentionally opinionated about override semantics:
/// - A later registration with the same name overrides the previous entry.
/// - Hosts can use this to implement “custom overrides builtin” by registering builtin first.
public struct EditorCoreThemeRegistry: Equatable {
    @frozen
    public enum Source: Equatable {
        case builtin
        case custom
    }

    @frozen
    public struct Entry: Equatable {
        public var theme: EditorCoreThemeDefinition
        public var source: Source
        public var url: URL?

        public init(theme: EditorCoreThemeDefinition, source: Source, url: URL? = nil) {
            self.theme = theme
            self.source = source
            self.url = url
        }
    }

    private var byKey: [String: Entry] = [:]

    public init() {}

    /// Register a theme. If another theme exists with the same normalized name, it is overridden.
    public mutating func register(_ entry: Entry) {
        let key = Self.normalizeThemeNameKey(entry.theme.name)
        guard key.isEmpty == false else { return }
        byKey[key] = entry
    }

    public func theme(named name: String) -> EditorCoreThemeDefinition? {
        let key = Self.normalizeThemeNameKey(name)
        return byKey[key]?.theme
    }

    public func entry(named name: String) -> Entry? {
        let key = Self.normalizeThemeNameKey(name)
        return byKey[key]
    }

    public func allEntriesSortedByName() -> [Entry] {
        byKey.values.sorted { a, b in
            a.theme.name.localizedCaseInsensitiveCompare(b.theme.name) == .orderedAscending
        }
    }

    public func allThemesSortedByName() -> [EditorCoreThemeDefinition] {
        allEntriesSortedByName().map(\.theme)
    }

    public static func normalizeThemeNameKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

