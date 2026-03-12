import AppKit
import AttoEditorSupport
import Foundation
import MachO

@MainActor
private enum AttoEditorMain {
    private static func isRunningInsideAppBundle() -> Bool {
        // 当可执行文件位于 `*.app/Contents/MacOS/` 中时，Bundle.main 指向 `.app` 根目录。
        // 这用于区分：
        // - 终端里运行的 CLI 二进制（默认走 IPC 打开/拉起主实例）
        // - Finder 双击启动的 `.app`（默认应直接启动 GUI/Server）
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func resolvedExecutablePath() -> String {
        // 需要一个“真实可执行文件路径”用于 CLI 拉起 GUI/server 子进程。
        //
        // 注意：在 `swift run` 下，argv[0] 可能只是 "AttoEditor"（不带路径），
        // 用 cwd 拼接会得到一个不存在的路径，导致 `-w/--wait` 触发的 detached 启动失败。
        let argv0 = ProcessInfo.processInfo.arguments.first ?? "AttoEditor"
        let fm = FileManager.default

        func isExecutable(_ p: String) -> Bool {
            fm.isExecutableFile(atPath: p)
        }

        if argv0.hasPrefix("/") {
            let p = URL(fileURLWithPath: argv0).standardizedFileURL.path
            if isExecutable(p) { return p }
        }

        // 相对路径（包含 '/'）时按 cwd 解析。
        if argv0.contains("/") {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let p = URL(fileURLWithPath: argv0, relativeTo: cwd).standardizedFileURL.path
            if isExecutable(p) { return p }
        }

        // 在 PATH 里查找（`swift run` 可能通过 PATH 注入 build 产物目录）。
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for part in pathEnv.split(separator: ":") {
                if part.isEmpty { continue }
                let candidate = URL(fileURLWithPath: String(part), isDirectory: true)
                    .appendingPathComponent(argv0, isDirectory: false)
                    .standardizedFileURL
                    .path
                if isExecutable(candidate) { return candidate }
            }
        }

        // 兜底：从 dyld 获取当前进程真实路径。
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: Int(size))
            if _NSGetExecutablePath(&buf, &size) == 0 {
                let bytes = buf.map { UInt8(bitPattern: $0) }
                let nul = bytes.firstIndex(of: 0) ?? bytes.count
                let path = String(decoding: bytes.prefix(nul), as: UTF8.self)
                let p = URL(fileURLWithPath: path).standardizedFileURL.path
                if isExecutable(p) { return p }
            }
        }

        // 最差情况：返回 argv0（可能不可执行，但避免 crash）。
        return argv0
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
        let preferences = NSMenuItem(
            title: "Preferences…",
            action: #selector(AttoAppDelegate.preferencesMenuClicked(_:)),
            keyEquivalent: ","
        )
        preferences.keyEquivalentModifierMask = [.command]
        preferences.target = appDelegate
        appMenu.addItem(preferences)
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

        let newFile = NSMenuItem(
            title: "New File",
            action: #selector(AttoAppDelegate.newFileMenuClicked(_:)),
            keyEquivalent: "n"
        )
        newFile.keyEquivalentModifierMask = [.command]
        newFile.target = appDelegate
        fileMenu.addItem(newFile)

        fileMenu.addItem(.separator())

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

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let find = NSMenuItem(
            title: "Find…",
            action: #selector(AttoAppDelegate.findMenuClicked(_:)),
            keyEquivalent: "f"
        )
        find.keyEquivalentModifierMask = [.command]
        find.target = appDelegate
        editMenu.addItem(find)

        let replace = NSMenuItem(
            title: "Replace…",
            action: #selector(AttoAppDelegate.replaceMenuClicked(_:)),
            keyEquivalent: "f"
        )
        replace.keyEquivalentModifierMask = [.command, .option]
        replace.target = appDelegate
        editMenu.addItem(replace)

        let findInFiles = NSMenuItem(
            title: "Find in Files…",
            action: #selector(AttoAppDelegate.findInFilesMenuClicked(_:)),
            keyEquivalent: "f"
        )
        findInFiles.keyEquivalentModifierMask = [.command, .shift]
        findInFiles.target = appDelegate
        editMenu.addItem(findInFiles)

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
        AttoIPC.ignoreSIGPIPE()

        let args = ProcessInfo.processInfo.arguments
        let isInternalServer = args.contains(AttoIPC.internalServerFlag)
        let isBundledApp = isRunningInsideAppBundle()

        if isInternalServer == false && isBundledApp == false {
            runCLI()
        }

        // GUI/server 模式：尽早安装文件日志（避免 detached 启动时日志泄露到 CLI console）。
        AttoLogging.installIfNeeded()

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

        NSLog(
            "AttoEditor: primary instance started (pid=%d) socket=%@ spool=%@",
            ProcessInfo.processInfo.processIdentifier,
            AttoIPC.socketPath(),
            AttoIPC.spoolDirPath()
        )

        app.delegate = delegate
        app.mainMenu = buildMainMenu(appDelegate: delegate)

        app.run()
    }
}

AttoEditorMain.run()
