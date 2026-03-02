import XCTest
@testable import EditorCoreFFI

final class FFILibrarySmokeTests: XCTestCase {
    func testLoadsLibraryAndVersion() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        XCTAssertGreaterThan(library.abiVersion, 0)
        XCTAssertFalse((try library.versionString()).isEmpty)
        XCTAssertFalse(library.resolvedLibraryPath.isEmpty)
    }

    func testBadLibraryPathFails() throws {
        do {
            _ = try EditorCoreFFILibrary(path: "/__definitely_not_exists__/libeditor_core_ffi.dylib")
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            // 这里只要确保不是静默成功即可；错误消息在不同平台/ld 实现下会不同。
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }
}

