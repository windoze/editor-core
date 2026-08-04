import Foundation

struct AttoConfigurationSettingsJSONSourceLocation: Codable, Equatable {
    var line: Int
    var column: Int
    var characterOffset: Int

    var displayText: String {
        "line \(line), column \(column)"
    }
}

enum AttoConfigurationSettingsJSONLocationIndex {
    static func locations(in text: String) -> [String: AttoConfigurationSettingsJSONSourceLocation] {
        var parser = Parser(text: text)
        parser.parse()
        return parser.locations
    }
}

private struct Parser {
    let text: String
    var index: String.Index
    var locations: [String: AttoConfigurationSettingsJSONSourceLocation] = [:]

    init(text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func parse() {
        parseValue(path: "")
    }

    private var current: Character? {
        guard index < text.endIndex else { return nil }
        return text[index]
    }

    private mutating func parseValue(path: String) {
        skipWhitespace()
        guard let character = current else { return }
        if path.isEmpty == false, locations[path] == nil {
            locations[path] = location(at: index)
        }

        switch character {
        case "{":
            parseObject(path: path)
        case "[":
            parseArray(path: path)
        case "\"":
            _ = parseString()
        default:
            skipPrimitive()
        }
    }

    private mutating func parseObject(path: String) {
        guard consume("{") else { return }
        skipWhitespace()
        if consume("}") {
            return
        }

        while index < text.endIndex {
            skipWhitespace()
            guard current == "\"" else { return }
            let keyStart = index
            guard let key = parseString() else { return }
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            let keyLocation = location(at: keyStart)
            locations[childPath] = keyLocation
            if path.isEmpty == false {
                locations["\(path)[\(key)]"] = keyLocation
            }

            skipWhitespace()
            guard consume(":") else { return }
            parseValue(path: childPath)

            skipWhitespace()
            if consume(",") {
                continue
            }
            _ = consume("}")
            return
        }
    }

    private mutating func parseArray(path: String) {
        guard consume("[") else { return }
        skipWhitespace()
        if consume("]") {
            return
        }

        var elementIndex = 0
        while index < text.endIndex {
            let elementPath = "\(path)[\(elementIndex)]"
            parseValue(path: elementPath)

            skipWhitespace()
            if consume(",") {
                elementIndex += 1
                continue
            }
            _ = consume("]")
            return
        }
    }

    private mutating func parseString() -> String? {
        guard consume("\"") else { return nil }
        var value = ""
        while let character = current {
            if character == "\"" {
                advance()
                return value
            }
            if character == "\\" {
                advance()
                appendEscapedCharacter(to: &value)
                continue
            }

            value.append(character)
            advance()
        }
        return nil
    }

    private mutating func appendEscapedCharacter(to value: inout String) {
        guard let character = current else { return }
        switch character {
        case "\"", "\\", "/":
            value.append(character)
            advance()
        case "b":
            value.append("\u{08}")
            advance()
        case "f":
            value.append("\u{0C}")
            advance()
        case "n":
            value.append("\n")
            advance()
        case "r":
            value.append("\r")
            advance()
        case "t":
            value.append("\t")
            advance()
        case "u":
            advance()
            appendUnicodeEscape(to: &value)
        default:
            value.append(character)
            advance()
        }
    }

    private mutating func appendUnicodeEscape(to value: inout String) {
        var hex = ""
        for _ in 0..<4 {
            guard let character = current else { return }
            hex.append(character)
            advance()
        }
        guard let scalarValue = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(scalarValue) else { return }
        value.append(Character(scalar))
    }

    private mutating func skipPrimitive() {
        while let character = current,
              character != ",",
              character != "]",
              character != "}",
              isWhitespace(character) == false
        {
            advance()
        }
    }

    private mutating func skipWhitespace() {
        while let character = current, isWhitespace(character) {
            advance()
        }
    }

    private func isWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\n" || character == "\r" || character == "\t"
    }

    private mutating func consume(_ expected: Character) -> Bool {
        guard current == expected else { return false }
        advance()
        return true
    }

    private mutating func advance() {
        index = text.index(after: index)
    }

    private func location(at target: String.Index) -> AttoConfigurationSettingsJSONSourceLocation {
        var line = 1
        var column = 1
        var offset = 0
        var cursor = text.startIndex
        while cursor < target {
            if text[cursor] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            offset += 1
            cursor = text.index(after: cursor)
        }
        return AttoConfigurationSettingsJSONSourceLocation(
            line: line,
            column: column,
            characterOffset: offset
        )
    }
}
