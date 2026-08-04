import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    struct LspSupportConfiguration {
        let languageId: String
        let source: AttoLanguageSupportSource
    }

    func lspLaunchConfig(
        for url: URL,
        environment env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AttoLspServerLaunchConfig? {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let configured = AttoLspRegistry.loadServerMap()[ext]

        let command: String? = {
            if let configured { return configured.command }

            if ext == "rs" {
                return env["ATTO_EDITOR_LSP_CMD"]
                    ?? env["EDITOR_CORE_APPKIT_LSP_CMD"]
                    ?? "rust-analyzer"
            }

            return nil
        }()

        let args: String? = {
            if let configured { return configured.args }

            if ext == "rs" {
                return env["ATTO_EDITOR_LSP_ARGS"]
                    ?? env["EDITOR_CORE_APPKIT_LSP_ARGS"]
            }

            return nil
        }()

        let languageId: String? = {
            if let configured, let lang = configured.languageId { return lang }
            if let inferred = inferredTreeSitterLanguageId(for: url) { return inferred }
            return AttoLspLanguageId.guess(forExtension: ext)
        }()

        guard let command, let languageId, languageId.isEmpty == false else {
            return nil
        }

        return AttoLspServerLaunchConfig(
            command: command,
            args: args,
            languageId: languageId
        )
    }

    func isLspDisabled(environment env: [String: String]) -> Bool {
        env["ATTO_EDITOR_DISABLE_LSP"] == "1"
            || env["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"
    }

    func syncProjectLspServerConfigsToCore() {
        guard let coreDocuments else { return }

        do {
            try coreDocuments.setProjectLspServers(projectLspServerConfigsForOpenTabs())
        } catch {
            NSLog("AttoEditor: failed to sync project LSP server configs: %@", String(describing: error))
        }
    }

    func projectLspServerConfigsForOpenTabs(
        additionalLaunchConfigsByTab: [ObjectIdentifier: AttoLspServerLaunchConfig] = [:]
    ) -> [EcuProjectLspServerConfig] {
        let workspaceRootURIs = projectLspWorkspaceRootURIs()
        var configsByKey: [String: EcuProjectLspServerConfig] = [:]
        var orderedKeys: [String] = []

        for projected in coreProjectedTabsForWorkspaceLifecycle() {
            let tabKey = ObjectIdentifier(projected.tab)
            guard let launchConfig = projected.tab.lspServerConfig ?? additionalLaunchConfigsByTab[tabKey] else {
                continue
            }

            let key = Self.projectLspServerConfigKey(for: launchConfig)
            guard key.isEmpty == false else { continue }

            let autoStart = projected.tab.suppressesAutomaticLspStart == false
            if let existing = configsByKey[key] {
                var workspaceRoots = existing.workspaceRoots
                for rootURI in workspaceRootURIs where workspaceRoots.contains(rootURI) == false {
                    workspaceRoots.append(rootURI)
                }
                configsByKey[key] = EcuProjectLspServerConfig(
                    key: existing.key,
                    command: existing.command,
                    args: existing.args,
                    languageId: existing.languageId,
                    languageName: existing.languageName,
                    serverCapabilities: existing.serverCapabilities,
                    sharedSession: existing.sharedSession,
                    sessionPolicy: existing.sessionPolicy,
                    workspaceRoots: workspaceRoots,
                    autoStart: existing.autoStart || autoStart,
                    recoveryPolicy: existing.recoveryPolicy
                )
                continue
            }

            orderedKeys.append(key)
            configsByKey[key] = EcuProjectLspServerConfig(
                key: key,
                command: launchConfig.command,
                args: Self.projectLspServerConfigArgs(from: launchConfig.args),
                languageId: launchConfig.languageId,
                workspaceRoots: workspaceRootURIs,
                autoStart: autoStart,
                recoveryPolicy: projectLspRecoveryPolicy(for: launchConfig)
            )
        }

        return orderedKeys.compactMap { configsByKey[$0] }
    }

    func projectLspRecoveryPolicy(for config: AttoLspServerLaunchConfig) -> EcuProjectLspRecoveryPolicy {
        projectLspRecoveryPolicy(serverName: nil, serverCommand: config.command)
    }

    func projectLspRecoveryPolicy(
        serverName: String?,
        serverCommand: String?
    ) -> EcuProjectLspRecoveryPolicy {
        let enabled = preferences.effectiveLspAutoRestartEnabled
            && preferences.isLspAutoRestartDisabledForServer(
                serverName: serverName,
                serverCommand: serverCommand
            ) == false

        return EcuProjectLspRecoveryPolicy(
            enabled: enabled,
            maxAttempts: UInt32(clamping: preferences.effectiveLspAutoRestartMaxAttempts(
                serverName: serverName,
                serverCommand: serverCommand
            )),
            baseDelayMillis: Self.projectLspRecoveryBaseDelayMillis(
                preferences.effectiveLspAutoRestartBaseDelaySeconds(
                    serverName: serverName,
                    serverCommand: serverCommand
                )
            )
        )
    }

    func projectLspWorkspaceRootURIs() -> [String] {
        if let coreRoots = try? coreDocuments?.snapshot().workspaceRoots {
            let normalizedRoots = Self.uniqueProjectLspWorkspaceRootURIs(coreRoots)
            if normalizedRoots.isEmpty == false {
                return normalizedRoots
            }
        }

        return [workspaceRootURL.standardizedFileURL.absoluteString]
    }

    private static func uniqueProjectLspWorkspaceRootURIs(_ roots: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for root in roots {
            let normalized = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else {
                continue
            }
            ordered.append(normalized)
        }
        return ordered
    }

    static func projectLspServerConfigKey(for config: AttoLspServerLaunchConfig) -> String {
        ([config.languageId, config.command] + projectLspServerConfigArgs(from: config.args))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ":")
            .lowercased()
    }

    static func projectLspServerConfigArgs(from args: String?) -> [String] {
        guard let args else { return [] }
        return args.split { $0.isWhitespace }.map(String.init)
    }

    static func projectLspRecoveryBaseDelayMillis(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite else { return 5_000 }
        let clamped = min(max(seconds, 0.0), 3_600.0)
        return UInt64((clamped * 1_000.0).rounded())
    }

    static func projectLspRecoveryBaseDelaySeconds(_ millis: UInt64) -> TimeInterval {
        Double(millis) / 1_000.0
    }

    static func projectLspRecoveryPolicyDescription(_ policy: EcuProjectLspRecoveryPolicy) -> String {
        let enabled = policy.enabled ? "enabled" : "disabled"
        let baseDelay = formatProjectLspRecoverySeconds(projectLspRecoveryBaseDelaySeconds(policy.baseDelayMillis))
        return "\(enabled), max attempts \(policy.maxAttempts), base delay \(baseDelay)"
    }

    static func projectLspSessionPolicyDescription(_ policy: EcuProjectLspSessionPolicy) -> String {
        let deduplicate = policy.deduplicate ? "deduplicate" : "no deduplicate"
        return "\(policy.scope), merge \(policy.mergeStrategy), \(deduplicate), shutdown \(policy.shutdownPolicy)"
    }

    static func formatProjectLspRecoverySeconds(_ seconds: TimeInterval) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }
        return "\(seconds)s"
    }

    @discardableResult
    func enableLspSupport(
        for url: URL,
        editCore: EditCoreUI,
        config: AttoLspServerLaunchConfig,
        rootURI: String? = nil
    ) throws -> LspSupportConfiguration {
        try editCore.editor.lspEnable(
            command: config.command,
            args: config.args,
            rootURI: rootURI ?? workspaceRootURL.standardizedFileURL.absoluteString,
            documentURI: url.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )

        let supportsSemanticTokens: Bool = {
            guard let status = try? editCore.editor.lspStatusSnapshot() else { return false }
            return status.capabilities?.semanticTokens == true
        }()

        if supportsSemanticTokens {
            editCore.editor.treeSitterDisable()
            editCore.editor.sublimeDisable()
            return LspSupportConfiguration(languageId: config.languageId, source: .lspSemantic)
        } else {
            var enabledTreeSitterFallback = false
            do {
                try editCore.editor.treeSitterEnableForPath(url.path)
                editCore.editorView.kickProcessingPoll()
                enabledTreeSitterFallback = true
            } catch {
                NSLog(
                    "AttoEditor: Tree-sitter enable failed for %@ (fallback after LSP without semantic tokens): %@",
                    url.path,
                    String(describing: error)
                )
            }
            editCore.editor.sublimeDisable()
            return LspSupportConfiguration(
                languageId: config.languageId,
                source: enabledTreeSitterFallback ? .lspTreeSitter : .lspServices
            )
        }
    }
}
