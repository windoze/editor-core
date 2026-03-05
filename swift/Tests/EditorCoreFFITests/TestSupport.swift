import Foundation
import XCTest
@testable import EditorCoreFFI

final class EditorCoreFFITestSupport: @unchecked Sendable {
    static let shared = EditorCoreFFITestSupport()

    func loadLibrary() throws -> EditorCoreFFILibrary {
        // SwiftPM 现在通过 C target + Rust `staticlib` 做静态链接；
        // 因此这里不需要再定位/加载 dylib。
        return try EditorCoreFFILibrary()
    }

    func makeTempDir(prefix: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum JSONTestHelpers {
    static func object(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            XCTFail("期望 JSON object，但实际是：\(type(of: obj))")
            return [:]
        }
        return dict
    }

    static func array(_ json: String) throws -> [Any] {
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = obj as? [Any] else {
            XCTFail("期望 JSON array，但实际是：\(type(of: obj))")
            return []
        }
        return arr
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    static func stringify(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum FFITestHelpers {
    static func assertLastErrorSet(
        _ library: EditorCoreFFILibrary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = library.lastErrorMessage().trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(message.isEmpty, file: file, line: line)
        XCTAssertNotEqual(message, "no error", file: file, line: line)
    }
}

extension ViewportBlob {
    func stylesForCell(at index: Int) -> [UInt32] {
        guard index >= 0 && index < cells.count else {
            return []
        }
        let cell = cells[index]
        let start = Int(cell.styleStartIndex)
        let count = Int(cell.styleCount)
        guard count > 0 else {
            return []
        }
        guard start >= 0, start + count <= styleIds.count else {
            return []
        }
        return Array(styleIds[start..<(start + count)])
    }
}
