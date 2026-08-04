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
        XCTAssertTrue(info.supports(.workspaceLifecycleEnvelope))
        XCTAssertTrue(info.supports(.editorStateQueryEnvelope))
        XCTAssertTrue(info.supports(.lspHelperEnvelope))
        XCTAssertTrue(info.supports(.lspEditHelperEnvelope))
        XCTAssertTrue(info.supports(.processorResultEnvelope))

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
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_lifecycle_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 13
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.workspaceLifecycleEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "editor_state_query_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 14
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.editorStateQueryEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_helper_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 15
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.lspHelperEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_edit_helper_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 16
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.lspEditHelperEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "processor_result_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 17
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreFFIFeatures.processorResultEnvelope.rawValue
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
        XCTAssertTrue(library.featureFlags.contains(.workspaceLifecycleEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.editorStateQueryEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.lspHelperEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.lspEditHelperEnvelope))
        XCTAssertTrue(library.featureFlags.contains(.processorResultEnvelope))
    }

    func testRuntimeInfoJSONDescriptorsCoverKnownFeatures() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let runtimeJSON = try JSONTestHelpers.object(try library.runtimeInfoJSON())
        let features = try XCTUnwrap(runtimeJSON["features"] as? [[String: Any]])

        for knownFeature in EditorCoreFFIRuntimeCompatibility.knownFeatures {
            let flag = knownFeature.feature.rawValue
            let descriptor = try XCTUnwrap(
                features.first { feature in
                    (feature["flag"] as? NSNumber)?.uint64Value == flag
                },
                "missing runtime descriptor for \(knownFeature.name)"
            )
            XCTAssertEqual(
                (descriptor["bit"] as? NSNumber)?.intValue,
                flag.trailingZeroBitCount,
                "wrong runtime descriptor bit for \(knownFeature.name)"
            )
            XCTAssertFalse((descriptor["name"] as? String ?? "").isEmpty)
            XCTAssertFalse((descriptor["description"] as? String ?? "").isEmpty)
        }
    }

    func testRuntimeCapabilitySnapshotDecodesFeatureDescriptors() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let snapshot = try library.runtimeCapabilitySnapshot()

        XCTAssertEqual(snapshot.kind, "editor-core-ffi")
        XCTAssertEqual(snapshot.abiVersion, library.abiVersion)
        XCTAssertEqual(snapshot.featureFlags, library.featureFlags)
        XCTAssertEqual(snapshot.runtimeInfo, try library.runtimeInfo())
        XCTAssertTrue(snapshot.supports(.processorResultEnvelope))

        let descriptor = try XCTUnwrap(
            snapshot.features.first { $0.feature == .processorResultEnvelope }
        )
        XCTAssertEqual(descriptor.bit, 17)
        XCTAssertEqual(descriptor.flag, EditorCoreFFIFeatures.processorResultEnvelope.rawValue)
        XCTAssertEqual(descriptor.name, "processor_result_envelope")
        XCTAssertFalse(descriptor.description.isEmpty)
    }
}
