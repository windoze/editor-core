import Foundation

enum JSON {
    static func decode<T: Decodable>(_ type: T.Type, from json: String, context: String) throws -> T {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EditorCoreFFIError.ffiReturnedNull(
                context: "decode_json(\(context))",
                message: "JSON decode failed: \(error)"
            )
        }
    }
}

