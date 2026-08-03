import Foundation

struct AttoMacroStore {
    let macroFileURL: URL

    init(macroFileURL: URL = AttoMacroStore.defaultMacroFileURL()) {
        self.macroFileURL = macroFileURL
    }

    static let appDefault = AttoMacroStore()

    static func defaultMacroFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
            .appendingPathComponent("Macros", isDirectory: true)
            .appendingPathComponent("Last Macro.sublime-macro", isDirectory: false)
    }

    func load(maxCount: Int) -> [AttoRecordedCommand] {
        guard FileManager.default.fileExists(atPath: macroFileURL.path),
              let data = try? Data(contentsOf: macroFileURL),
              let stored = try? JSONDecoder().decode([StoredCommand].self, from: data)
        else {
            return []
        }
        return sanitize(stored.map(\.record), maxCount: maxCount)
    }

    func save(_ commands: [AttoRecordedCommand], maxCount: Int) throws {
        let sanitized = sanitize(commands, maxCount: maxCount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized.map(StoredCommand.init(record:)))
        try FileManager.default.createDirectory(
            at: macroFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: macroFileURL, options: [.atomic])
    }

    private func sanitize(_ commands: [AttoRecordedCommand], maxCount: Int) -> [AttoRecordedCommand] {
        let limit = max(0, maxCount)
        guard limit > 0 else { return [] }

        var out: [AttoRecordedCommand] = []
        for command in commands {
            let trimmed = command.commandID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            out.append(AttoRecordedCommand(commandID: trimmed, arguments: command.arguments))
            if out.count >= limit { break }
        }
        return out
    }

    private struct StoredCommand: Codable {
        let command: String
        let args: [String: MacroJSONValue]?

        init(record: AttoRecordedCommand) {
            command = record.commandID
            args = record.arguments.isEmpty ? nil : record.arguments.mapValues(MacroJSONValue.init(argument:))
        }

        var record: AttoRecordedCommand {
            AttoRecordedCommand(
                commandID: command,
                arguments: args?.compactMapValues { $0.argumentValue } ?? [:]
            )
        }
    }

    private enum MacroJSONValue: Codable, Equatable {
        case null
        case bool(Bool)
        case integer(Int)
        case number(Double)
        case string(String)
        case array([MacroJSONValue])
        case object([String: MacroJSONValue])

        init(argument: AttoCommandArgumentValue) {
            switch argument {
            case .string(let value):
                self = .string(value)
            case .integer(let value):
                self = .integer(value)
            case .number(let value):
                self = .number(value)
            case .boolean(let value):
                self = .bool(value)
            case .json(let value):
                if let data = value.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(MacroJSONValue.self, from: data)
                {
                    self = decoded
                } else {
                    self = .string(value)
                }
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([MacroJSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: MacroJSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.typeMismatch(
                    MacroJSONValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "unsupported macro JSON value")
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null:
                try container.encodeNil()
            case .bool(let value):
                try container.encode(value)
            case .integer(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .array(let values):
                try container.encode(values)
            case .object(let values):
                try container.encode(values)
            }
        }

        var argumentValue: AttoCommandArgumentValue? {
            switch self {
            case .null, .array, .object:
                return .json(jsonString)
            case .bool(let value):
                return .boolean(value)
            case .integer(let value):
                return .integer(value)
            case .number(let value):
                return .number(value)
            case .string(let value):
                return .string(value)
            }
        }

        private var jsonString: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(self),
                  let string = String(data: data, encoding: .utf8)
            else {
                return "null"
            }
            return string
        }
    }
}
