import AttoEditorSupport
import Foundation
import XCTest

@MainActor
final class AttoCommandLineTests: XCTestCase {
    func testParseFlagsDirectoriesAndFileLocations() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("atto_cmdline_tests_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let dir = tmp.appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = tmp.appendingPathComponent("a.rs", isDirectory: false)
        try "fn main() {}\n".write(to: file, atomically: true, encoding: .utf8)

        let argv = [
            "/usr/bin/AttoEditor",
            "-n",
            "--wait",
            dir.path,
            "\(file.path):10:5",
        ]

        let parsed = AttoCommandLine.parse(arguments: argv, fileManager: fm, currentDirectoryURL: tmp)

        XCTAssertTrue(parsed.newWindow)
        XCTAssertTrue(parsed.wait)
        XCTAssertEqual(parsed.directories, [dir.standardizedFileURL])
        XCTAssertEqual(
            parsed.files,
            [.init(url: file.standardizedFileURL, location: .init(line1: 10, column1: 5))]
        )
    }

    func testParseFileLineOnly() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("atto_cmdline_tests_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("demo.txt", isDirectory: false)
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)

        let argv = [
            "/usr/bin/AttoEditor",
            "\(file.path):3",
        ]

        let parsed = AttoCommandLine.parse(arguments: argv, fileManager: fm, currentDirectoryURL: tmp)
        XCTAssertEqual(parsed.directories, [])
        XCTAssertEqual(parsed.files.count, 1)
        XCTAssertEqual(parsed.files[0].url, file.standardizedFileURL)
        XCTAssertEqual(parsed.files[0].location, .init(line1: 3, column1: nil))
    }

    func testParseStopsOptionParsingAfterDoubleDash() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("atto_cmdline_tests_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("--new-window", isDirectory: false)
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let argv = [
            "/usr/bin/AttoEditor",
            "--",
            file.path,
        ]

        let parsed = AttoCommandLine.parse(arguments: argv, fileManager: fm, currentDirectoryURL: tmp)
        XCTAssertFalse(parsed.newWindow)
        XCTAssertFalse(parsed.wait)
        XCTAssertEqual(parsed.files.map(\.url), [file.standardizedFileURL])
    }

    func testParseHelpFlags() throws {
        for flag in ["-h", "--help"] {
            let parsed = AttoCommandLine.parse(arguments: ["/usr/bin/atto", flag])
            XCTAssertTrue(parsed.helpRequested, "flag=\(flag)")
            XCTAssertFalse(parsed.newWindow)
            XCTAssertFalse(parsed.wait)
            XCTAssertEqual(parsed.directories, [])
            XCTAssertEqual(parsed.files, [])
        }
    }

    func testParseDoesNotTreatHelpAsPathAfterDoubleDash() throws {
        let parsed = AttoCommandLine.parse(arguments: ["/usr/bin/atto", "--", "--help"])
        XCTAssertFalse(parsed.helpRequested)
        XCTAssertEqual(parsed.files.count, 1)
        XCTAssertTrue(parsed.files[0].url.lastPathComponent == "--help")
    }

    func testUsageTextDocumentsSupportedFlags() {
        let usage = AttoCommandLine.usageText
        XCTAssertTrue(usage.contains("-h") || usage.contains("--help"))
        XCTAssertTrue(usage.contains("--new-window"))
        XCTAssertTrue(usage.contains("--wait"))
        XCTAssertTrue(usage.contains("--"))
    }
}
