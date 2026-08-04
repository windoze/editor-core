import Foundation

enum AttoMacroStoreError: Error, Equatable {
    case invalidMacroFilePath(String)
    case invalidMacroName(String)
    case macroAlreadyExists(String)
    case macroNotFound(String)
}

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
        load(from: macroFileURL, maxCount: maxCount) ?? []
    }

    func loadNamedMacro(_ name: String, maxCount: Int) -> [AttoRecordedCommand]? {
        guard let fileURL = namedMacroFileURL(name) else { return nil }
        return load(from: fileURL, maxCount: maxCount)
    }

    func namedMacroNames() -> [String] {
        let directoryURL = macroFileURL.deletingLastPathComponent()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "sublime-macro" }
            .filter { $0.standardizedFileURL != macroFileURL.standardizedFileURL }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func save(_ commands: [AttoRecordedCommand], named name: String, maxCount: Int) throws {
        guard let fileURL = namedMacroFileURL(name) else {
            throw AttoMacroStoreError.invalidMacroName(name)
        }
        try save(commands, to: fileURL, maxCount: maxCount)
    }

    func importNamedMacro(from sourceURL: URL, named name: String, maxCount: Int) throws {
        guard let fileURL = externalMacroFileURL(sourceURL) else {
            throw AttoMacroStoreError.invalidMacroFilePath(sourceURL.path)
        }
        guard let commands = load(from: fileURL, maxCount: maxCount) else {
            throw AttoMacroStoreError.macroNotFound(sourceURL.path)
        }
        try save(commands, named: name, maxCount: maxCount)
    }

    func exportNamedMacro(_ name: String, to destinationURL: URL, maxCount: Int) throws {
        guard let fileURL = externalMacroFileURL(destinationURL) else {
            throw AttoMacroStoreError.invalidMacroFilePath(destinationURL.path)
        }
        guard let commands = loadNamedMacro(name, maxCount: maxCount) else {
            throw AttoMacroStoreError.macroNotFound(name)
        }
        try save(commands, to: fileURL, maxCount: maxCount)
    }

    func deleteNamedMacro(_ name: String) throws {
        guard let fileURL = namedMacroFileURL(name) else {
            throw AttoMacroStoreError.invalidMacroName(name)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AttoMacroStoreError.macroNotFound(name)
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    func normalizedNamedMacroNames(_ rawNames: [String]) throws -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for rawName in rawNames {
            guard let name = normalizedNamedMacroName(rawName) else {
                throw AttoMacroStoreError.invalidMacroName(rawName)
            }
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        guard names.isEmpty == false else {
            throw AttoMacroStoreError.invalidMacroName("")
        }
        return names
    }

    func deleteNamedMacros(_ rawNames: [String]) throws {
        let names = try normalizedNamedMacroNames(rawNames)
        let fileURLs = try names.map { name in
            guard let fileURL = namedMacroFileURL(name) else {
                throw AttoMacroStoreError.invalidMacroName(name)
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw AttoMacroStoreError.macroNotFound(name)
            }
            return fileURL
        }
        for fileURL in fileURLs {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func restoreNamedMacros(_ macros: [(name: String, commands: [AttoRecordedCommand])], maxCount: Int) throws {
        let names = try normalizedNamedMacroNames(macros.map { $0.name })
        guard names.count == macros.count else {
            throw AttoMacroStoreError.invalidMacroName("")
        }
        let restoreItems = try zip(names, macros).map { name, macro in
            guard let fileURL = namedMacroFileURL(name) else {
                throw AttoMacroStoreError.invalidMacroName(macro.name)
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) == false else {
                throw AttoMacroStoreError.macroAlreadyExists(name)
            }
            return (commands: macro.commands, fileURL: fileURL)
        }
        for item in restoreItems {
            try save(item.commands, to: item.fileURL, maxCount: maxCount)
        }
    }

    func loadDeletedMacroUndoRecords(maxRecords: Int, maxCommands: Int) -> [AttoDeletedMacroUndoRecord] {
        let fileURL = deletedMacroUndoRecordsFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StoredDeletedMacroUndoRecord].self, from: data)
        else {
            return []
        }
        return sanitizeDeletedMacroUndoRecords(stored.compactMap(\.record), maxRecords: maxRecords, maxCommands: maxCommands)
    }

    func saveDeletedMacroUndoRecords(
        _ records: [AttoDeletedMacroUndoRecord],
        maxRecords: Int,
        maxCommands: Int
    ) throws {
        let fileURL = deletedMacroUndoRecordsFileURL()
        let sanitized = sanitizeDeletedMacroUndoRecords(records, maxRecords: maxRecords, maxCommands: maxCommands)
        guard sanitized.isEmpty == false else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized.map(StoredDeletedMacroUndoRecord.init(record:)))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    func renameNamedMacro(_ oldName: String, to newName: String) throws {
        guard let oldFileURL = namedMacroFileURL(oldName) else {
            throw AttoMacroStoreError.invalidMacroName(oldName)
        }
        guard let newFileURL = namedMacroFileURL(newName) else {
            throw AttoMacroStoreError.invalidMacroName(newName)
        }
        guard FileManager.default.fileExists(atPath: oldFileURL.path) else {
            throw AttoMacroStoreError.macroNotFound(oldName)
        }
        guard FileManager.default.fileExists(atPath: newFileURL.path) == false else {
            throw AttoMacroStoreError.macroAlreadyExists(newName)
        }
        try FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
    }

    func save(_ commands: [AttoRecordedCommand], maxCount: Int) throws {
        try save(commands, to: macroFileURL, maxCount: maxCount)
    }

    private func load(from fileURL: URL, maxCount: Int) -> [AttoRecordedCommand]? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StoredCommand].self, from: data)
        else {
            return nil
        }
        return sanitize(stored.map(\.record), maxCount: maxCount)
    }

    private func save(_ commands: [AttoRecordedCommand], to fileURL: URL, maxCount: Int) throws {
        let sanitized = sanitize(commands, maxCount: maxCount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized.map(StoredCommand.init(record:)))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    private func namedMacroFileURL(_ rawName: String) -> URL? {
        guard let name = normalizedMacroName(rawName) else { return nil }
        let fileURL = macroFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension("sublime-macro")
            .standardizedFileURL
        guard fileURL != macroFileURL.standardizedFileURL else { return nil }
        return fileURL
    }

    private func normalizedNamedMacroName(_ rawName: String) -> String? {
        namedMacroFileURL(rawName)?.deletingPathExtension().lastPathComponent
    }

    private func deletedMacroUndoRecordsFileURL() -> URL {
        macroFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".AttoDeletedMacroUndoHistory.json", isDirectory: false)
            .standardizedFileURL
    }

    private func externalMacroFileURL(_ url: URL) -> URL? {
        let fileURL = url.standardizedFileURL
        guard fileURL.pathExtension.lowercased() == "sublime-macro" else { return nil }
        return fileURL
    }

    private func normalizedMacroName(_ rawName: String) -> String? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".sublime-macro") {
            name.removeLast(".sublime-macro".count)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard name.isEmpty == false, name != ".", name != ".." else { return nil }
        guard name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:")) == nil else { return nil }
        return name
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

    private func sanitizeDeletedMacroUndoRecords(
        _ records: [AttoDeletedMacroUndoRecord],
        maxRecords: Int,
        maxCommands: Int
    ) -> [AttoDeletedMacroUndoRecord] {
        let recordLimit = max(0, maxRecords)
        guard recordLimit > 0 else { return [] }

        var out: [AttoDeletedMacroUndoRecord] = []
        for record in records {
            var snapshots: [AttoDeletedMacroSnapshot] = []
            var rawNames: [String] = []
            for snapshot in record.macros {
                guard let name = normalizedNamedMacroName(snapshot.name) else { continue }
                rawNames.append(name)
                snapshots.append(AttoDeletedMacroSnapshot(
                    name: name,
                    commands: sanitize(snapshot.commands, maxCount: maxCommands)
                ))
            }
            guard snapshots.isEmpty == false,
                  (try? normalizedNamedMacroNames(rawNames)).map({ $0.count == snapshots.count }) == true
            else {
                continue
            }
            out.append(AttoDeletedMacroUndoRecord(macros: snapshots))
        }
        if out.count > recordLimit {
            out.removeFirst(out.count - recordLimit)
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

    private struct StoredDeletedMacroUndoRecord: Codable {
        let macros: [StoredDeletedMacro]

        init(record: AttoDeletedMacroUndoRecord) {
            macros = record.macros.map(StoredDeletedMacro.init(snapshot:))
        }

        var record: AttoDeletedMacroUndoRecord? {
            let snapshots = macros.map(\.snapshot)
            guard snapshots.isEmpty == false else { return nil }
            return AttoDeletedMacroUndoRecord(macros: snapshots)
        }
    }

    private struct StoredDeletedMacro: Codable {
        let name: String
        let commands: [StoredCommand]

        init(snapshot: AttoDeletedMacroSnapshot) {
            name = snapshot.name
            commands = snapshot.commands.map(StoredCommand.init(record:))
        }

        var snapshot: AttoDeletedMacroSnapshot {
            AttoDeletedMacroSnapshot(name: name, commands: commands.map(\.record))
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
