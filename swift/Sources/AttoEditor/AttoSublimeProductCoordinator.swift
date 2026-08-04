import AppKit
import Foundation

@MainActor
final class AttoSublimeProductCoordinator {
    private let activeWindowProvider: () -> AttoWindowContext?
    private let fileManager: FileManager

    private var buildSystemController: AttoCommandPaletteController?
    private var packageResourceController: AttoCommandPaletteController?
    private var quickPanelController: AttoCommandPaletteController?
    private var outputPanelController = AttoOutputPanelController(title: "Build Output")
    private var activeBuildProcess: Process?
    private var activeBuildName: String?
    private var activeBuildWasCancelled = false
    private var outputHasContent = false

    init(activeWindowProvider: @escaping () -> AttoWindowContext?, fileManager: FileManager = .default) {
        self.activeWindowProvider = activeWindowProvider
        self.fileManager = fileManager
    }

    var outputTextForTesting: String {
        outputPanelController.text
    }

    func runBuildSystem() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        guard activeBuildProcess == nil else {
            ctx.editorAreaController.setTransientStatusText("Build systems: build already running")
            outputPanelController.show(relativeTo: ctx.window)
            return true
        }

        let systems = AttoSublimeBuildSystem.discover(in: ctx.workspaceRootURL, fileManager: fileManager)
        guard systems.isEmpty == false else {
            ctx.editorAreaController.setTransientStatusText(AttoSublimeFeatureBoundary.runBuildSystem.statusText)
            return true
        }

        guard systems.count > 1 else {
            return startBuild(systems[0], in: ctx)
        }

        buildSystemController = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.SublimeBuildSystems",
            commandsProvider: { [weak self] in
                systems.enumerated().map { index, system in
                    AttoCommandPaletteCommand(
                        id: "build.system.\(index)",
                        title: system.displayName,
                        group: "Build"
                    ) { [weak self] in
                        guard let self, let ctx = self.activeWindowProvider() else { return }
                        _ = self.startBuild(system, in: ctx)
                    }
                }
            }
        )
        buildSystemController?.show(relativeTo: ctx.window, placeholder: "Select build system...")
        return true
    }

    func cancelBuildSystem() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        guard let process = activeBuildProcess, process.isRunning else {
            ctx.editorAreaController.setTransientStatusText(AttoSublimeFeatureBoundary.cancelBuildSystem.statusText)
            return true
        }
        activeBuildWasCancelled = true
        process.terminate()
        ctx.editorAreaController.setTransientStatusText("Build cancelled: \(activeBuildName ?? "Build")")
        return true
    }

    func openPackageResource() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        let resources = AttoSublimePackageResource.discover(in: ctx.workspaceRootURL, fileManager: fileManager)
        guard resources.isEmpty == false else {
            ctx.editorAreaController.setTransientStatusText(AttoSublimeFeatureBoundary.openPackageResource.statusText)
            return true
        }

        guard resources.count > 1 else {
            return openPackageResource(resources[0], in: ctx)
        }

        packageResourceController = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.SublimePackageResources",
            commandsProvider: { [weak self] in
                resources.enumerated().map { index, resource in
                    AttoCommandPaletteCommand(
                        id: "package.resource.\(index)",
                        title: resource.displayName,
                        group: "Package"
                    ) { [weak self] in
                        guard let self, let ctx = self.activeWindowProvider() else { return }
                        _ = self.openPackageResource(resource, in: ctx)
                    }
                }
            }
        )
        packageResourceController?.show(relativeTo: ctx.window, placeholder: "Open package resource...")
        return true
    }

    func showQuickPanel() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        quickPanelController = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.SublimeQuickPanel",
            commandsProvider: { [weak self] in
                [
                    AttoCommandPaletteCommand(id: "build.run", title: "Run Build System", group: "Build") {
                        _ = self?.runBuildSystem()
                    },
                    AttoCommandPaletteCommand(id: "package.open_resource", title: "Open Package Resource", group: "Package") {
                        _ = self?.openPackageResource()
                    },
                    AttoCommandPaletteCommand(id: "panel.show_output_panel", title: "Show Output Panel", group: "Panel") {
                        _ = self?.showOutputPanel()
                    },
                ]
            }
        )
        quickPanelController?.show(relativeTo: ctx.window, placeholder: "Filter Sublime commands...")
        ctx.editorAreaController.setTransientStatusText("Quick panel opened")
        return true
    }

    func showInputPanel() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        ctx.editorAreaController.setTransientStatusText(AttoSublimeFeatureBoundary.showInputPanel.statusText)
        return true
    }

    func showOutputPanel() -> Bool {
        guard let ctx = activeWindowProvider() else { return false }
        guard outputHasContent else {
            ctx.editorAreaController.setTransientStatusText("Output panels: no output")
            return true
        }
        outputPanelController.show(relativeTo: ctx.window)
        ctx.editorAreaController.setTransientStatusText("Output panel opened")
        return true
    }

    private func startBuild(_ system: AttoSublimeBuildSystem, in ctx: AttoWindowContext) -> Bool {
        guard let descriptor = system.launchDescriptor(workspaceRootURL: ctx.workspaceRootURL) else {
            ctx.editorAreaController.setTransientStatusText("Build systems: invalid build command")
            return true
        }

        let process = Process()
        process.executableURL = descriptor.executableURL
        process.arguments = descriptor.arguments
        process.currentDirectoryURL = descriptor.workingDirectoryURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        activeBuildProcess = process
        activeBuildName = system.displayName
        activeBuildWasCancelled = false
        outputHasContent = true
        outputPanelController.setText("[\(system.displayName)] \(descriptor.displayCommand)\n")
        outputPanelController.show(relativeTo: ctx.window)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { [weak self] in
                self?.outputPanelController.appendText(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { [weak self] in
                self?.finishBuild(process: process, pipe: pipe, context: ctx, name: system.displayName)
            }
        }

        do {
            try process.run()
            ctx.editorAreaController.setTransientStatusText("Build started: \(system.displayName)")
            return true
        } catch {
            activeBuildProcess = nil
            activeBuildName = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            outputPanelController.appendText("Failed to start build: \(error)\n")
            ctx.editorAreaController.setTransientStatusText("Build failed to start: \(system.displayName)")
            return true
        }
    }

    private func finishBuild(process: Process, pipe: Pipe, context ctx: AttoWindowContext, name: String) {
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.availableData
        if remainingData.isEmpty == false {
            let text = String(data: remainingData, encoding: .utf8) ?? String(decoding: remainingData, as: UTF8.self)
            outputPanelController.appendText(text)
        }
        activeBuildProcess = nil
        activeBuildName = nil

        if activeBuildWasCancelled {
            activeBuildWasCancelled = false
            outputPanelController.appendText("\nBuild cancelled: \(name)\n")
            ctx.editorAreaController.setTransientStatusText("Build cancelled: \(name)")
            return
        }

        if process.terminationStatus == 0 {
            outputPanelController.appendText("\nBuild finished: \(name)\n")
            ctx.editorAreaController.setTransientStatusText("Build finished: \(name)")
        } else {
            outputPanelController.appendText("\nBuild failed: \(name) (exit \(process.terminationStatus))\n")
            ctx.editorAreaController.setTransientStatusText("Build failed: \(name)")
        }
    }

    private func openPackageResource(_ resource: AttoSublimePackageResource, in ctx: AttoWindowContext) -> Bool {
        ctx.rememberRecentFile(resource.fileURL)
        guard ctx.editorAreaController.openFile(url: resource.fileURL, mode: .pinned) else {
            ctx.editorAreaController.setTransientStatusText("Failed to open package resource")
            return true
        }
        ctx.fileExplorerController.revealFile(resource.fileURL)
        ctx.editorAreaController.setTransientStatusText("Opened package resource: \(resource.relativePath)")
        return true
    }
}
