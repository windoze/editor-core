import Foundation

extension AttoKeymap {
    static func sublimeCompatibleJSONData(from data: Data) -> Data {
        guard let raw = String(data: data, encoding: .utf8) else { return data }
        return Data(removeTrailingCommas(from: stripJSONComments(from: raw)).utf8)
    }

    private static func stripJSONComments(from raw: String) -> String {
        var out = ""
        var index = raw.startIndex
        var isInString = false
        var isEscaping = false

        while index < raw.endIndex {
            let character = raw[index]
            let nextIndex = raw.index(after: index)

            if isInString {
                out.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInString = false
                }
                index = nextIndex
                continue
            }

            if character == "\"" {
                isInString = true
                out.append(character)
                index = nextIndex
                continue
            }

            if character == "/", nextIndex < raw.endIndex {
                let nextCharacter = raw[nextIndex]
                if nextCharacter == "/" {
                    index = raw.index(after: nextIndex)
                    while index < raw.endIndex, raw[index] != "\n" {
                        index = raw.index(after: index)
                    }
                    if index < raw.endIndex {
                        out.append(raw[index])
                        index = raw.index(after: index)
                    }
                    continue
                }
                if nextCharacter == "*" {
                    index = raw.index(after: nextIndex)
                    while index < raw.endIndex {
                        let current = raw[index]
                        let afterCurrent = raw.index(after: index)
                        if current == "\n" {
                            out.append(current)
                        }
                        if current == "*", afterCurrent < raw.endIndex, raw[afterCurrent] == "/" {
                            index = raw.index(after: afterCurrent)
                            break
                        }
                        index = afterCurrent
                    }
                    continue
                }
            }

            out.append(character)
            index = nextIndex
        }

        return out
    }

    private static func removeTrailingCommas(from raw: String) -> String {
        var out = ""
        var index = raw.startIndex
        var isInString = false
        var isEscaping = false

        while index < raw.endIndex {
            let character = raw[index]
            let nextIndex = raw.index(after: index)

            if isInString {
                out.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInString = false
                }
                index = nextIndex
                continue
            }

            if character == "\"" {
                isInString = true
                out.append(character)
                index = nextIndex
                continue
            }

            if character == "," {
                var lookahead = nextIndex
                while lookahead < raw.endIndex, raw[lookahead].isWhitespace {
                    lookahead = raw.index(after: lookahead)
                }
                if lookahead < raw.endIndex, (raw[lookahead] == "}" || raw[lookahead] == "]") {
                    index = nextIndex
                    continue
                }
            }

            out.append(character)
            index = nextIndex
        }

        return out
    }
}
