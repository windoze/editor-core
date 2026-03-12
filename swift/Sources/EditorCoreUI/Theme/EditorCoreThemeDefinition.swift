import Foundation

/// A JSON-backed theme definition that can be converted into an `EditorCoreSkiaTheme`.
///
/// This is intentionally renderer/host-facing metadata (name/appearance) + a concrete `EditorCoreSkiaTheme`.
@frozen
public struct EditorCoreThemeDefinition: Equatable {
    public var schemaVersion: Int
    public var name: String
    public var appearance: EditorCoreThemeAppearance
    public var skiaTheme: EditorCoreSkiaTheme

    public init(
        schemaVersion: Int,
        name: String,
        appearance: EditorCoreThemeAppearance = .unspecified,
        skiaTheme: EditorCoreSkiaTheme
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.appearance = appearance
        self.skiaTheme = skiaTheme
    }
}

public enum EditorCoreThemeAppearance: String, CaseIterable, Equatable {
    case light
    case dark
    case unspecified
}

public enum EditorCoreThemeError: Error, LocalizedError, Equatable {
    case invalidJSONRoot
    case unsupportedSchemaVersion(Int)
    case missingRequiredField(String)
    case invalidFieldType(field: String, expected: String)
    case invalidColor(String)
    case invalidStyleSelector
    case invalidStyleId(String)
    case invalidUnderlineStyle(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSONRoot:
            return "Theme JSON root must be an object."
        case let .unsupportedSchemaVersion(v):
            return "Unsupported theme schema_version=\(v)."
        case let .missingRequiredField(field):
            return "Missing required field: \(field)"
        case let .invalidFieldType(field, expected):
            return "Invalid field type for \(field). Expected \(expected)."
        case let .invalidColor(value):
            return "Invalid color value: \(value)"
        case .invalidStyleSelector:
            return "Invalid style selector (expected one-of: style_id/builtin/reserved/lsp_semantic)."
        case let .invalidStyleId(value):
            return "Invalid style_id: \(value)"
        case let .invalidUnderlineStyle(value):
            return "Invalid underline style: \(value)"
        }
    }
}
