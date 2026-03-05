import XCTest
@testable import EditorCoreFFI

final class FFILibrarySmokeTests: XCTestCase {
    func testLoadsLibraryAndVersion() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        XCTAssertGreaterThan(library.abiVersion, 0)
        XCTAssertFalse((try library.versionString()).isEmpty)
    }

    func testPathInitializerIsIgnoredInStaticLinkMode() throws {
        // 该 initializer 为了兼容早期的动态加载实现而保留；
        // 静态链接模式下应当忽略路径并正常工作。
        let library = try EditorCoreFFILibrary(path: "/__definitely_not_exists__/libeditor_core_ffi.dylib")
        XCTAssertGreaterThan(library.abiVersion, 0)
    }
}
