# SWIFT-GAPS.md: Deferred / Out-of-scope

完整历史、已完成提交记录和旧矩阵已归档到 `docs/archive/2026-08-04-swift-gaps-1/SWIFT-GAPS.md`。

本文只保留 `PLAN.md` 收口后仍不应在当前实现任务内继续推进的 deferred / out-of-scope 项。当前没有剩余产品实现 gap。

## Deferred

- SwiftPM 全量单进程 AppKit 测试：`swift test --package-path swift` 在当前环境中仍可能让 AppKit-heavy XCTest 进程以 `xctest ... exited with unexpected signal code 11` 退出。已用 `swift test --package-path swift --list-tests` 枚举出的 947 个测试通过小批次和单测尾部分片覆盖；后续应在 CI 或 Xcode test plan 中正式分片，或拆出更小的 AppKit test target。
- Opt-in `XCUIApplication` smoke：`swift/scripts/build-attoeditor-app.sh --debug --out /tmp/attoeditor-final-xcui` 可以构建 App bundle，默认 `AttoEditorXCUIApplicationSmokeTests` 会跳过并通过；但在 SwiftPM unit-test bundle 中启用 `ATTO_XCUI_SMOKE_TESTS=1` 会返回 `Device is not configured for UI testing`。实际执行这些黑盒 smoke 需要 Xcode UI-test-capable runner / UI test bundle。
