import Foundation

public enum EcfStatus: Int32, Sendable {
    case ok = 0
    case invalidArgument = 1
    case invalidUtf8 = 2
    case notFound = 3
    case bufferTooSmall = 4
    case parse = 5
    case commandFailed = 6
    case `internal` = 7
    case unsupported = 8
    case versionMismatch = 9
}

extension EcfStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ok:
            return "ECF_OK"
        case .invalidArgument:
            return "ECF_ERR_INVALID_ARGUMENT"
        case .invalidUtf8:
            return "ECF_ERR_INVALID_UTF8"
        case .notFound:
            return "ECF_ERR_NOT_FOUND"
        case .bufferTooSmall:
            return "ECF_ERR_BUFFER_TOO_SMALL"
        case .parse:
            return "ECF_ERR_PARSE"
        case .commandFailed:
            return "ECF_ERR_COMMAND_FAILED"
        case .internal:
            return "ECF_ERR_INTERNAL"
        case .unsupported:
            return "ECF_ERR_UNSUPPORTED"
        case .versionMismatch:
            return "ECF_ERR_VERSION_MISMATCH"
        }
    }
}

public enum EditorCoreFFIError: Error, CustomStringConvertible {
    case failedToLoadLibrary(tried: [String], errors: [String])
    case missingSymbol(name: String)
    case ffiReturnedNull(context: String, message: String)
    case ffiStatus(code: EcfStatus, context: String, message: String)
    case invalidViewportBlob(reason: String)

    public var description: String {
        switch self {
        case .failedToLoadLibrary(let tried, let errors):
            var lines: [String] = []
            lines.append("Failed to load editor-core-ffi dynamic library.")
            if !tried.isEmpty {
                lines.append("Tried:")
                lines.append(contentsOf: tried.map { "  \($0)" })
            }
            if !errors.isEmpty {
                lines.append("Errors:")
                lines.append(contentsOf: errors.map { "  \($0)" })
            }
            return lines.joined(separator: "\n")

        case .missingSymbol(let name):
            return "Missing FFI symbol: \(name)"

        case .ffiReturnedNull(let context, let message):
            return "FFI call returned null (\(context)): \(message)"

        case .ffiStatus(let code, let context, let message):
            return "FFI call failed (\(context)): \(code) — \(message)"

        case .invalidViewportBlob(let reason):
            return "Invalid viewport blob: \(reason)"
        }
    }
}

