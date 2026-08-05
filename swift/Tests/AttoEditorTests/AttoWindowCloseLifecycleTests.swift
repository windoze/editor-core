import AttoEditorSupport
@testable import AttoEditor
import Foundation
import XCTest

/// 窗口关闭生命周期回归测试。
///
/// 历史 bug：`atto -w FILE1 FILE2` 打开多个窗口后，关闭其中一个窗口会崩溃（SIGSEGV）。
/// 根因：ctx（进而 window）的最后一个强引用在 `windowWillClose` 内被释放，
/// window 在 AppKit 自身的 close/动画流程中提前 dealloc，
/// 后续 autoreleasepool drain / CA commit 对已释放的 window 再次 release。
@MainActor
final class AttoWindowCloseLifecycleTests: XCTestCase {
    func testClosingOneOfMultipleWaitWindowsDoesNotCrash() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("atto-window-close-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("a.txt")
        let fileB = dir.appendingPathComponent("b.txt")
        try "hello a\n".write(to: fileA, atomically: true, encoding: .utf8)
        try "hello b\n".write(to: fileB, atomically: true, encoding: .utf8)

        let delegate = AttoAppDelegate(keyBindings: [:])
        let req = AttoIpcOpenRequest(
            requestID: UUID().uuidString,
            newWindow: false,
            wait: true,
            directories: [],
            files: [
                AttoIpcFileRequest(path: fileA.path, line1: nil, column1: nil),
                AttoIpcFileRequest(path: fileB.path, line1: nil, column1: nil),
            ]
        )
        let result = delegate.handleOpenRequest(req)
        XCTAssertEqual(result.pendingTokens.count, 2)

        // 让窗口完成首次布局/显示。
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let windows = NSApplication.shared.windows.filter { $0.delegate is AttoWindowContext }
        XCTAssertEqual(windows.count, 2)

        // 关闭其中一个窗口。
        windows[0].close()

        // 跑 runloop 让 close 收尾、autoreleasepool drain、CA commit 全部走完（历史崩溃点）。
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))

        // 关闭另一个窗口（覆盖“最后一个窗口关闭”路径）。
        for window in NSApplication.shared.windows where window.delegate is AttoWindowContext {
            window.close()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
    }
}
