import Foundation

enum AttoSettingsSelector {
    static func matches(_ rawSelector: String, context: AttoConfigurationDocumentContext) -> Bool {
        let tokens = Tokenizer(rawSelector).tokens()
        guard tokens.isEmpty == false else { return false }
        guard let expression = Parser(tokens: tokens).parse() else { return false }
        return expression.matches(context)
    }
}

private indirect enum AttoSettingsSelectorExpression {
    case atom(String)
    case all([AttoSettingsSelectorExpression])
    case any([AttoSettingsSelectorExpression])
    case not(AttoSettingsSelectorExpression)

    func matches(_ context: AttoConfigurationDocumentContext) -> Bool {
        switch self {
        case .atom(let value):
            return AttoSettingsSelectorAtom(value).matches(context)
        case .all(let expressions):
            return expressions.allSatisfy { $0.matches(context) }
        case .any(let expressions):
            return expressions.contains { $0.matches(context) }
        case .not(let expression):
            return expression.matches(context) == false
        }
    }
}

private struct AttoSettingsSelectorAtom {
    let value: String

    init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func matches(_ context: AttoConfigurationDocumentContext) -> Bool {
        guard value.isEmpty == false else { return false }
        if value == "*" || value == "all" { return true }

        let languageId = context.normalizedLanguageId
        let fileExtension = context.normalizedFileExtension
        let fileName = context.normalizedFileName
        let filePath = context.normalizedPath
        let scopeName = context.normalizedScopeName

        if let prefixed = prefixedValue(prefixes: ["language:", "lang:"]) {
            return languageId == normalizedIdentifier(prefixed)
        }
        if let prefixed = prefixedValue(prefixes: ["extension:", "ext:"]) {
            return fileExtension == normalizedExtension(prefixed)
        }
        if let prefixed = prefixedValue(prefixes: ["filename:", "file:"]) {
            return fileName == normalizedPathComponent(prefixed)
        }
        if let prefixed = prefixedValue(prefixes: ["glob:", "path:"]) {
            return pathMatches(pattern: prefixed, fileName: fileName, filePath: filePath)
        }
        if let prefixed = prefixedValue(prefixes: ["scope:"]) {
            return scopeMatches(prefixed, scopeName: scopeName, languageId: languageId)
        }

        if value.hasPrefix(".") {
            return fileExtension == normalizedExtension(value)
        }
        if value.hasPrefix("*.") && value.dropFirst(2).contains("/") == false {
            return fileExtension == normalizedExtension(String(value.dropFirst(1)))
        }
        if value.contains("*") || value.contains("?") || value.contains("/") {
            return pathMatches(pattern: value, fileName: fileName, filePath: filePath)
        }
        if value.contains(".") {
            return scopeMatches(value, scopeName: scopeName, languageId: languageId)
                || fileName == normalizedPathComponent(value)
        }

        let normalized = normalizedIdentifier(value)
        return languageId == normalized
            || fileExtension == normalized
            || scopeContainsSegment(normalized, scopeName: scopeName)
    }

    private func prefixedValue(prefixes: [String]) -> String? {
        for prefix in prefixes where value.hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return nil
    }

    private func scopeMatches(_ selector: String, scopeName: String?, languageId: String?) -> Bool {
        let normalizedSelector = normalizedScope(selector)
        guard normalizedSelector.isEmpty == false else { return false }

        if let scopeName {
            let scopes = scopeName.split(separator: " ").map(String.init)
            if scopes.contains(where: { scope in scope == normalizedSelector || scope.hasPrefix("\(normalizedSelector).") }) {
                return true
            }
        }

        guard let languageId else { return false }
        if normalizedSelector == languageId { return true }
        return normalizedSelector
            .split(separator: ".")
            .contains { String($0) == languageId }
    }

    private func scopeContainsSegment(_ segment: String, scopeName: String?) -> Bool {
        guard let scopeName, segment.isEmpty == false else { return false }
        return scopeName
            .split(whereSeparator: { $0 == " " || $0 == "." })
            .contains { String($0) == segment }
    }

    private func pathMatches(pattern: String, fileName: String?, filePath: String?) -> Bool {
        let normalizedPattern = normalizedPathComponent(pattern) ?? ""
        if let filePath, glob(normalizedPattern, matches: filePath) {
            return true
        }
        if let fileName, glob(normalizedPattern, matches: fileName) {
            return true
        }
        return false
    }

    private func glob(_ pattern: String, matches text: String) -> Bool {
        let patternChars = Array(pattern)
        let textChars = Array(text)
        var memo: [String: Bool] = [:]

        func match(_ patternIndex: Int, _ textIndex: Int) -> Bool {
            let key = "\(patternIndex):\(textIndex)"
            if let cached = memo[key] { return cached }

            let result: Bool
            if patternIndex == patternChars.count {
                result = textIndex == textChars.count
            } else if patternChars[patternIndex] == "*" {
                result = match(patternIndex + 1, textIndex)
                    || (textIndex < textChars.count && match(patternIndex, textIndex + 1))
            } else if textIndex < textChars.count,
                      patternChars[patternIndex] == "?"
                        || patternChars[patternIndex] == textChars[textIndex]
            {
                result = match(patternIndex + 1, textIndex + 1)
            } else {
                result = false
            }

            memo[key] = result
            return result
        }

        return match(0, 0)
    }

    private func normalizedIdentifier(_ raw: String) -> String {
        AttoConfigurationDocumentContext.normalizedIdentifier(raw) ?? ""
    }

    private func normalizedExtension(_ raw: String) -> String {
        normalizedIdentifier(raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    private func normalizedScope(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
    }

    private func normalizedPathComponent(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

private enum AttoSettingsSelectorToken: Equatable {
    case atom(String)
    case lparen
    case rparen
    case or
    case and
    case not
}

private struct Tokenizer {
    let input: String

    init(_ input: String) {
        self.input = input
    }

    func tokens() -> [AttoSettingsSelectorToken] {
        var out: [AttoSettingsSelectorToken] = []
        var index = input.startIndex

        func advance() {
            index = input.index(after: index)
        }

        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace {
                advance()
                continue
            }

            switch char {
            case "(":
                out.append(.lparen)
                advance()
            case ")":
                out.append(.rparen)
                advance()
            case ",", "|":
                out.append(.or)
                advance()
            case "&":
                out.append(.and)
                advance()
            case "-", "!":
                out.append(.not)
                advance()
            default:
                let start = index
                while index < input.endIndex, isAtomTerminator(input[index]) == false {
                    advance()
                }
                let atom = String(input[start..<index])
                if atom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    out.append(.atom(atom))
                }
            }
        }

        return out
    }

    private func isAtomTerminator(_ char: Character) -> Bool {
        char.isWhitespace || char == "(" || char == ")" || char == "," || char == "|" || char == "&"
    }
}

private struct Parser {
    let tokens: [AttoSettingsSelectorToken]
    private var index = 0

    init(tokens: [AttoSettingsSelectorToken]) {
        self.tokens = tokens
    }

    func parse() -> AttoSettingsSelectorExpression? {
        var parser = self
        guard let expression = parser.parseOr() else { return nil }
        guard parser.isAtEnd else { return nil }
        return expression
    }

    private var isAtEnd: Bool {
        index >= tokens.count
    }

    private mutating func parseOr() -> AttoSettingsSelectorExpression? {
        guard var expressions = parseAnd().map({ [$0] }) else { return nil }
        while match(.or) {
            guard let rhs = parseAnd() else { return nil }
            expressions.append(rhs)
        }
        return expressions.count == 1 ? expressions[0] : .any(expressions)
    }

    private mutating func parseAnd() -> AttoSettingsSelectorExpression? {
        var expressions: [AttoSettingsSelectorExpression] = []
        while isAtEnd == false, startsPrimary(peek()) {
            if match(.and) { continue }
            guard let expression = parseUnary() else { return nil }
            expressions.append(expression)
        }
        guard expressions.isEmpty == false else { return nil }
        return expressions.count == 1 ? expressions[0] : .all(expressions)
    }

    private mutating func parseUnary() -> AttoSettingsSelectorExpression? {
        if match(.not) {
            return parseUnary().map(AttoSettingsSelectorExpression.not)
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> AttoSettingsSelectorExpression? {
        if match(.lparen) {
            guard let expression = parseOr(), match(.rparen) else { return nil }
            return expression
        }
        guard case .atom(let value)? = advance() else { return nil }
        return .atom(value)
    }

    private func startsPrimary(_ token: AttoSettingsSelectorToken?) -> Bool {
        switch token {
        case .atom, .lparen, .not, .and:
            return true
        case .or, .rparen, nil:
            return false
        }
    }

    private func peek() -> AttoSettingsSelectorToken? {
        isAtEnd ? nil : tokens[index]
    }

    private mutating func advance() -> AttoSettingsSelectorToken? {
        guard isAtEnd == false else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    private mutating func match(_ token: AttoSettingsSelectorToken) -> Bool {
        guard peek() == token else { return false }
        index += 1
        return true
    }
}
