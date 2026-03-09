import EditorCoreUIFFI
import Foundation
import XCTest

final class EditorCoreUIFFITestSupport: @unchecked Sendable {
    static let shared = EditorCoreUIFFITestSupport()

    func loadLibrary() throws -> EditorCoreUIFFILibrary {
        return EditorCoreUIFFILibrary()
    }
}
