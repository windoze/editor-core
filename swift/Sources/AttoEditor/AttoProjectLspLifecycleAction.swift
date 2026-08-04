import EditorCoreUIFFI
import Foundation

struct AttoProjectLspLifecycleAction {
    let coreTabID: UInt64?
    let operation: String
    let trigger: String
    let activeViewIndex: UInt32
    let documentURI: String
    let languageId: String
    let serverKey: String
    let command: String
    let args: [String]
    let workspaceRoots: [String]

    @MainActor
    static func start(
        tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        planEntry: EcuProjectLspStartPlanEntry?,
        fallbackWorkspaceRoots: [String]
    ) -> AttoProjectLspLifecycleAction {
        AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "start",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        )
    }

    @MainActor
    static func restart(
        tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        planEntry: EcuProjectLspRestartPlanEntry?,
        fallbackWorkspaceRoots: [String]
    ) -> AttoProjectLspLifecycleAction {
        AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "restart",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        )
    }

    @MainActor
    static func stop(
        tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        planEntry: EcuProjectLspStopPlanEntry?,
        fallbackWorkspaceRoots: [String]
    ) -> AttoProjectLspLifecycleAction {
        AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "stop",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        )
    }

    func outcome(
        status: String,
        attemptId: UInt64? = nil,
        errorMessage: String? = nil
    ) -> EcuProjectLspStartOutcome? {
        guard let coreTabID else { return nil }
        return EcuProjectLspStartOutcome(
            tabId: coreTabID,
            activeViewIndex: activeViewIndex,
            operation: operation,
            documentURI: documentURI,
            languageId: languageId,
            serverKey: serverKey,
            command: command,
            args: args,
            workspaceRoots: workspaceRoots,
            trigger: trigger,
            status: status,
            attemptId: attemptId,
            errorMessage: errorMessage
        )
    }
}
