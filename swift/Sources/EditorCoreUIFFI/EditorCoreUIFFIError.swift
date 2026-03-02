import Foundation

public enum EditorCoreUIFFIError: Error, CustomStringConvertible {
    case failedToLoadLibrary(tried: [String], errors: [String])
    case missingSymbol(name: String)
    case ffiStatus(code: EcuStatus, context: String, message: String)

    public var description: String {
        switch self {
        case let .failedToLoadLibrary(tried, errors):
            return """
            failedToLoadLibrary
            tried:
            \(tried.joined(separator: "\n"))
            errors:
            \(errors.joined(separator: "\n"))
            """
        case let .missingSymbol(name):
            return "missingSymbol(\(name))"
        case let .ffiStatus(code, context, message):
            return "ffiStatus(code=\(code), context=\(context), message=\(message))"
        }
    }

    public var localizedDescription: String { description }
}

