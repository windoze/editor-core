import XCTest
@testable import EditorCoreFFI

final class FFILibrarySmokeTests: XCTestCase {
    func testLoadsLibraryAndVersion() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        XCTAssertGreaterThan(library.abiVersion, 0)
        XCTAssertFalse((try library.versionString()).isEmpty)

        let info = try library.runtimeInfo()
        XCTAssertEqual(info.abiVersion, library.abiVersion)
        XCTAssertFalse(info.version.isEmpty)
        XCTAssertTrue(info.supports(.jsonCommandDispatch))
        XCTAssertTrue(info.supports(.typedHotPath))
        XCTAssertTrue(info.supports(.workspaceTypedAPI))
        XCTAssertTrue(info.supports(.viewportBlob))
        XCTAssertTrue(info.supports(.processingEditJSON))
        XCTAssertTrue(info.supports(.lspHelpers))
        XCTAssertTrue(info.supports(.sublimeProcessor))
        XCTAssertTrue(info.supports(.treeSitterProcessor))
        XCTAssertTrue(info.supports(.jsonCommandEnvelope))
        XCTAssertTrue(info.supports(.renderingSnapshotEnvelope))
        XCTAssertTrue(info.supports(.editorStateDerivedSnapshotEnvelope))
        XCTAssertTrue(info.supports(.workspaceResultEnvelope))
        XCTAssertTrue(info.supports(.workspaceQueryEnvelope))

        let runtimeJSON = try JSONTestHelpers.object(try library.runtimeInfoJSON())
        XCTAssertEqual(runtimeJSON["kind"] as? String, "editor-core-ffi")
        XCTAssertEqual((runtimeJSON["abi_version"] as? NSNumber)?.uint32Value, library.abiVersion)
        XCTAssertEqual((runtimeJSON["feature_flags"] as? NSNumber)?.uint64Value, library.featureFlags.rawValue)
        let features = try XCTUnwrap(runtimeJSON["features"] as? [[String: Any]])
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "json_command_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 8
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.jsonCommandEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "rendering_snapshot_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 9
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.renderingSnapshotEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "editor_state_derived_snapshot_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 10
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.editorStateDerivedSnapshotEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_result_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 11
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.workspaceResultEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_query_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 12
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.workspaceQueryEnvelope.rawValue
        })
    }

    func testPathInitializerIsIgnoredInStaticLinkMode() throws {
        // 该 initializer 为了兼容早期的动态加载实现而保留；
        // 静态链接模式下应当忽略路径并正常工作。
        let library = try EditorCoreFFILibrary(path: "/__definitely_not_exists__/libeditor_core_ffi.dylib")
        XCTAssertGreaterThan(library.abiVersion, 0)
        XCTAssertTrue(library.featureFlags.contains(.jsonCommandEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.renderingSnapshotEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.editorStateDerivedSnapshotEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.workspaceResultEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.workspaceQueryEnvelope))
    }
}
