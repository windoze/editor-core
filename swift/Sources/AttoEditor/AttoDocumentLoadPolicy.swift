import Foundation

struct AttoDocumentLoadResult: Equatable {
    let text: String
    let languageProcessingDisabledReason: String?
    let fallbackReasons: [String]

    var disablesLanguageProcessing: Bool {
        languageProcessingDisabledReason != nil
    }
}

enum AttoDocumentLoadPolicy {
    static let defaultLargeFileByteLimit = 2 * 1024 * 1024

    static func loadText(
        from url: URL,
        largeFileByteLimit: Int = defaultLargeFileByteLimit
    ) throws -> AttoDocumentLoadResult {
        let data = try Data(contentsOf: url)
        let byteCount = data.count
        let isLarge = byteCount > largeFileByteLimit
        let isBinary = data.contains(0)
        let validUTF8 = String(data: data, encoding: .utf8)
        let text = validUTF8 ?? String(decoding: data, as: UTF8.self)

        var disabledReasons: [String] = []
        var fallbackReasons: [String] = []

        if isLarge {
            let size = stableByteCount(byteCount)
            disabledReasons.append("large file \(size)")
            fallbackReasons.append("Large file (\(size)) opened with language services disabled.")
        }

        if isBinary {
            disabledReasons.append("binary content")
            fallbackReasons.append("Binary content detected; language services disabled.")
        }

        if validUTF8 == nil {
            disabledReasons.append("invalid UTF-8")
            fallbackReasons.append("Invalid UTF-8 detected; opened with replacement characters and language services disabled.")
        }

        return AttoDocumentLoadResult(
            text: text,
            languageProcessingDisabledReason: disabledReasons.isEmpty ? nil : disabledReasons.joined(separator: ", "),
            fallbackReasons: fallbackReasons
        )
    }

    static func overriddenText(_ text: String) -> AttoDocumentLoadResult {
        AttoDocumentLoadResult(
            text: text,
            languageProcessingDisabledReason: nil,
            fallbackReasons: []
        )
    }

    private static func stableByteCount(_ byteCount: Int) -> String {
        if byteCount == 1 {
            return "1 byte"
        }
        if byteCount < 1024 {
            return "\(byteCount) bytes"
        }

        let units = ["KB", "MB", "GB"]
        var value = Double(byteCount) / 1024.0
        var unitIndex = 0
        while value >= 1024.0, unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) \(units[unitIndex])"
        }
        return "\(rounded) \(units[unitIndex])"
    }
}
