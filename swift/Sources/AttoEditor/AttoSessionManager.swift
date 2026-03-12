import AttoEditorSupport
import Foundation

/// Session 保存/恢复的调度器（防抖保存 + 恢复期间抑制写盘）。
@MainActor
final class AttoSessionManager {
    private let store: AttoSessionStore
    private let debounceSeconds: TimeInterval

    private var saveTask: Task<Void, Never>?
    private var isRestoring: Bool = false
    private var needsSaveAfterRestore: Bool = false

    private let ioQueue = DispatchQueue(label: "codes.unwritten.attoeditor.session.io", qos: .utility)

    init(store: AttoSessionStore = AttoSessionStore(), debounceSeconds: TimeInterval = 1.0) {
        self.store = store
        self.debounceSeconds = debounceSeconds
    }

    func shouldRestoreOnLaunch(arguments: [String]) -> Bool {
        // 仅 Finder / `open AttoEditor.app` 这类 bundle 启动才恢复；
        // CLI 冷启动（内部 server）不恢复，避免突然弹出一堆旧窗口。
        let isBundledApp = (Bundle.main.bundleURL.pathExtension == "app")
        let isInternalServer = arguments.contains(AttoIPC.internalServerFlag)
        return isBundledApp && (isInternalServer == false)
    }

    func loadSnapshotForRestore(arguments: [String]) -> AttoSessionSnapshot? {
        guard shouldRestoreOnLaunch(arguments: arguments) else { return nil }
        return store.load()
    }

    func beginRestoring() {
        isRestoring = true
    }

    func endRestoring(capture: @MainActor @escaping () -> AttoSessionSnapshot?) {
        isRestoring = false
        if needsSaveAfterRestore {
            needsSaveAfterRestore = false
            scheduleSave(reason: "after_restore", capture: capture)
        }
    }

    func scheduleSave(reason: String, capture: @MainActor @escaping () -> AttoSessionSnapshot?) {
        if isRestoring {
            needsSaveAfterRestore = true
            return
        }

        guard let snapshot = capture() else { return }

        saveTask?.cancel()
        let debounceSeconds = debounceSeconds
        let store = store
        let ioQueue = ioQueue

        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            } catch {
                return
            }
            if Task.isCancelled { return }
            ioQueue.async {
                do {
                    try store.save(snapshot)
                } catch {
                    NSLog("AttoEditor: session save failed (%@): %@", reason, String(describing: error))
                }
            }
        }
    }

    func saveNow(reason: String, capture: @MainActor () -> AttoSessionSnapshot?) {
        saveTask?.cancel()
        saveTask = nil

        guard let snapshot = capture() else { return }
        do {
            try store.save(snapshot)
        } catch {
            NSLog("AttoEditor: session saveNow failed (%@): %@", reason, String(describing: error))
        }
    }
}
