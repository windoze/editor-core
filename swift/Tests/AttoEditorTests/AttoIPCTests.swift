import AttoEditorSupport
import Foundation
import XCTest

final class AttoIPCTests: XCTestCase {
    func testIPCPathsUseExplicitEnvironmentOverrides() {
        let env = [
            AttoIPC.socketPathEnvKey: "/tmp/atto-custom.sock",
            AttoIPC.spoolDirPathEnvKey: "/tmp/atto-custom.spool",
        ]

        XCTAssertEqual(AttoIPC.socketPath(env: env), "/tmp/atto-custom.sock")
        XCTAssertEqual(AttoIPC.spoolDirPath(env: env), "/tmp/atto-custom.spool")
    }

    func testIPCPathsCanShareRuntimeDirectoryOverride() {
        let runtimeDir = "/tmp/atto-runtime-\(UUID().uuidString)"
        let env = [AttoIPC.runtimeDirEnvKey: runtimeDir]

        XCTAssertEqual(
            AttoIPC.socketPath(env: env),
            "\(runtimeDir)/codes.unwritten.attoeditor.\(getuid()).sock"
        )
        XCTAssertEqual(
            AttoIPC.spoolDirPath(env: env),
            "\(runtimeDir)/codes.unwritten.attoeditor.\(getuid()).spool"
        )
    }
}
