import EditorCoreFFI
import EditorCoreUIFFI
import XCTest

final class EditorCoreFFIErrorModelTests: XCTestCase {
    func testHeadlessAndUIStatusCodesShareNumericModelAndLabels() {
        let pairs: [(EcfStatus, EcuStatus, String, String, String)] = [
            (.ok, .ok, "ok", "ECF_OK", "ECU_OK"),
            (
                .invalidArgument,
                .invalidArgument,
                "invalid_argument",
                "ECF_ERR_INVALID_ARGUMENT",
                "ECU_ERR_INVALID_ARGUMENT"
            ),
            (.invalidUtf8, .invalidUtf8, "invalid_utf8", "ECF_ERR_INVALID_UTF8", "ECU_ERR_INVALID_UTF8"),
            (.notFound, .notFound, "not_found", "ECF_ERR_NOT_FOUND", "ECU_ERR_NOT_FOUND"),
            (
                .bufferTooSmall,
                .bufferTooSmall,
                "buffer_too_small",
                "ECF_ERR_BUFFER_TOO_SMALL",
                "ECU_ERR_BUFFER_TOO_SMALL"
            ),
            (.parse, .parse, "parse", "ECF_ERR_PARSE", "ECU_ERR_PARSE"),
            (.commandFailed, .commandFailed, "command_failed", "ECF_ERR_COMMAND_FAILED", "ECU_ERR_COMMAND_FAILED"),
            (.internal, .internal, "internal", "ECF_ERR_INTERNAL", "ECU_ERR_INTERNAL"),
            (.unsupported, .unsupported, "unsupported", "ECF_ERR_UNSUPPORTED", "ECU_ERR_UNSUPPORTED"),
            (
                .versionMismatch,
                .versionMismatch,
                "version_mismatch",
                "ECF_ERR_VERSION_MISMATCH",
                "ECU_ERR_VERSION_MISMATCH"
            ),
        ]

        for (ecf, ecu, label, ecfSymbol, ecuSymbol) in pairs {
            XCTAssertEqual(ecf.rawValue, ecu.rawValue)
            XCTAssertEqual(ecf.abiLabel, label)
            XCTAssertEqual(ecu.abiLabel, label)
            XCTAssertEqual(ecf.description, ecfSymbol)
            XCTAssertEqual(ecu.description, ecuSymbol)
        }
    }

    func testAppVisibleErrorDescriptionsIncludeSharedErrorLabels() {
        let headless = EditorCoreFFIError.ffiStatus(
            code: .invalidArgument,
            context: "headless_context",
            message: "bad argument"
        )
        XCTAssertTrue(headless.description.contains("ECF_ERR_INVALID_ARGUMENT"))
        XCTAssertTrue(headless.description.contains("invalid_argument"))

        let ui = EditorCoreUIFFIError.ffiStatus(
            code: .invalidArgument,
            context: "ui_context",
            message: "bad argument"
        )
        XCTAssertTrue(ui.localizedDescription.contains("ECU_ERR_INVALID_ARGUMENT"))
        XCTAssertTrue(ui.localizedDescription.contains("invalid_argument"))
    }
}
