import EditorCoreUIFFI
import Foundation

struct AttoProjectLspLifecycleAction {
    let coreTabID: UInt64?
    let operation: String
    let trigger: String
    let activeViewIndex: UInt32
    let documentURI: String
    let languageId: String
    let languageName: String
    let serverCapabilities: EcuJSONValue
    let serverKey: String
    let command: String
    let args: [String]
    let workspaceRoots: [String]
    let workspaceFolders: [EcuProjectLspWorkspaceFolder]

    @MainActor
    static func start(
        tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        planEntry: EcuProjectLspStartPlanEntry?,
        fallbackWorkspaceRoots: [String]
    ) -> AttoProjectLspLifecycleAction {
        let workspaceRoots = planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        let workspaceFolders = planEntry?.workspaceFolders ?? Self.workspaceFolders(from: workspaceRoots)
        return AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "start",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            languageName: planEntry?.languageName ?? config.languageId,
            serverCapabilities: planEntry?.serverCapabilities ?? .object([:]),
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: workspaceRoots,
            workspaceFolders: workspaceFolders
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
        let workspaceRoots = planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        let workspaceFolders = planEntry?.workspaceFolders ?? Self.workspaceFolders(from: workspaceRoots)
        return AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "restart",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            languageName: planEntry?.languageName ?? config.languageId,
            serverCapabilities: planEntry?.serverCapabilities ?? .object([:]),
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: workspaceRoots,
            workspaceFolders: workspaceFolders
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
        let workspaceRoots = planEntry?.workspaceRoots ?? fallbackWorkspaceRoots
        let workspaceFolders = planEntry?.workspaceFolders ?? Self.workspaceFolders(from: workspaceRoots)
        return AttoProjectLspLifecycleAction(
            coreTabID: tab.coreTabID,
            operation: planEntry?.operation ?? "stop",
            trigger: trigger,
            activeViewIndex: planEntry?.activeViewIndex ?? UInt32(clamping: tab.activePaneIndex),
            documentURI: planEntry?.documentURI ?? documentURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? config.languageId,
            languageName: planEntry?.languageName ?? config.languageId,
            serverCapabilities: planEntry?.serverCapabilities ?? .object([:]),
            serverKey: planEntry?.serverKey ?? AttoEditorAreaViewController.projectLspServerConfigKey(for: config),
            command: planEntry?.command ?? config.command,
            args: planEntry?.args ?? AttoEditorAreaViewController.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: workspaceRoots,
            workspaceFolders: workspaceFolders
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
            languageName: languageName,
            serverCapabilities: serverCapabilities,
            serverKey: serverKey,
            command: command,
            args: args,
            workspaceRoots: workspaceRoots,
            workspaceFolders: workspaceFolders,
            trigger: trigger,
            status: status,
            attemptId: attemptId,
            errorMessage: errorMessage
        )
    }

    private static func workspaceFolders(from roots: [String]) -> [EcuProjectLspWorkspaceFolder] {
        roots.compactMap { root in
            let uri = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard uri.isEmpty == false else { return nil }
            return EcuProjectLspWorkspaceFolder(
                uri: uri,
                name: workspaceFolderName(for: uri)
            )
        }
    }

    private static func workspaceFolderName(for uri: String) -> String {
        let trimmed = uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed
            .split(separator: "/")
            .last
            .map(String.init) ?? uri
    }
}
