import AppKit
import Foundation

@MainActor
private enum AttoEditorMain {
    private static func resolvedExecutablePath() -> String {
        // `argv[0]` 可能是相对路径；用 cwd 兜底转成绝对路径。
        let argv0 = ProcessInfo.processInfo.arguments.first ?? "AttoEditor"
        if argv0.hasPrefix("/") { return argv0 }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: argv0, relativeTo: cwd).standardizedFileURL.path
    }

    private static func runCLI() -> Never {
        let parsed = AttoCommandLine.parse(arguments: ProcessInfo.processInfo.arguments)
        let requestID = UUID().uuidString

        let req = AttoIpcOpenRequest(
            requestID: requestID,
            newWindow: parsed.newWindow,
            wait: parsed.wait,
            directories: parsed.directories.map(\.path),
            files: parsed.files.map { f in
                AttoIpcFileRequest(
                    path: f.url.path,
                    line1: f.location?.line1,
                    column1: f.location?.column1
                )
            }
        )

        let code = AttoIpcClient.sendOpenRequest(
            req,
            executablePath: resolvedExecutablePath()
        )
        exit(code)
    }

    static func buildMainMenu(appDelegate: AttoAppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        // App menu (AttoEditor)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About AttoEditor",
            action: nil,
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit AttoEditor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let openFolder = NSMenuItem(
            title: "Open Folder…",
            action: #selector(AttoAppDelegate.openFolderMenuClicked(_:)),
            keyEquivalent: "o"
        )
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        openFolder.target = appDelegate
        fileMenu.addItem(openFolder)

        let openFile = NSMenuItem(
            title: "Open File…",
            action: #selector(AttoAppDelegate.openFileMenuClicked(_:)),
            keyEquivalent: "o"
        )
        openFile.keyEquivalentModifierMask = [.command]
        openFile.target = appDelegate
        fileMenu.addItem(openFile)

        let save = NSMenuItem(
            title: "Save",
            action: #selector(AttoAppDelegate.saveMenuClicked(_:)),
            keyEquivalent: "s"
        )
        save.keyEquivalentModifierMask = [.command]
        save.target = appDelegate
        fileMenu.addItem(save)

        fileMenu.addItem(.separator())

        let closeTab = NSMenuItem(
            title: "Close Tab",
            action: #selector(AttoAppDelegate.closeTabMenuClicked(_:)),
            keyEquivalent: "w"
        )
        closeTab.keyEquivalentModifierMask = [.command]
        closeTab.target = appDelegate
        fileMenu.addItem(closeTab)

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let toggleSidebar = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(AttoAppDelegate.toggleSidebarMenuClicked(_:)),
            keyEquivalent: "b"
        )
        toggleSidebar.keyEquivalentModifierMask = [.command]
        toggleSidebar.target = appDelegate
        viewMenu.addItem(toggleSidebar)

        let toggleMinimap = NSMenuItem(
            title: "Toggle Minimap",
            action: #selector(AttoAppDelegate.toggleMinimapMenuClicked(_:)),
            keyEquivalent: "m"
        )
        toggleMinimap.keyEquivalentModifierMask = [.command]
        toggleMinimap.target = appDelegate
        viewMenu.addItem(toggleMinimap)

        // Go menu (Command Palette)
        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu

        let goToFile = NSMenuItem(
            title: "Go to File…",
            action: #selector(AttoAppDelegate.goToFileMenuClicked(_:)),
            keyEquivalent: "p"
        )
        goToFile.keyEquivalentModifierMask = [.command]
        goToFile.target = appDelegate
        goMenu.addItem(goToFile)

        let commandPalette = NSMenuItem(
            title: "Command Palette…",
            action: #selector(AttoAppDelegate.commandPaletteMenuClicked(_:)),
            keyEquivalent: "p"
        )
        commandPalette.keyEquivalentModifierMask = [.command, .shift]
        commandPalette.target = appDelegate
        goMenu.addItem(commandPalette)

        return mainMenu
    }

    static func run() {
        if ProcessInfo.processInfo.arguments.contains(AttoIPC.internalServerFlag) == false {
            runCLI()
        }

        let noDefaultWindow = ProcessInfo.processInfo.arguments.contains(AttoIPC.internalNoDefaultWindowFlag)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        // AttoEditor has its own in-app tab UI. Disable macOS window tabbing to avoid
        // the system tab bar ("Show Tab Bar") showing up under the title bar.
        NSWindow.allowsAutomaticWindowTabbing = false

        // VSCode-ish dark appearance by default.
        app.appearance = NSAppearance(named: .darkAqua)

        let delegate = AttoAppDelegate()
        delegate.createDefaultWindowOnLaunch = (noDefaultWindow == false)

        let ipcServer = AttoIpcServer { req in
            delegate.handleOpenRequest(req)
        }
        delegate.ipcServer = ipcServer

        let start = ipcServer.start()
        if start.isPrimaryInstance == false {
            // 已有实例在运行；当前进程不应再启动 GUI。
            exit(0)
        }

        app.delegate = delegate
        app.mainMenu = buildMainMenu(appDelegate: delegate)

        app.run()
    }
}

AttoEditorMain.run()
