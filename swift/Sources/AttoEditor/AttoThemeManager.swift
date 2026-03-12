import EditorCoreUI
import Foundation

enum AttoThemeManager {
    static let defaultThemeName: String = "Atto Dark"

    static func customThemesDirectoryURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        let configRoot = appSupport.appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
        return configRoot.appendingPathComponent("themes", isDirectory: true)
    }

    static func builtinThemeURLs(bundle: Bundle = .module) -> [URL] {
        let inThemesDir = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        if inThemesDir.isEmpty == false {
            return inThemesDir.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        // SwiftPM may flatten resources into the root of the generated bundle (depending on the resource rule).
        // Keep a fallback path so built-in themes remain discoverable in all build modes.
        let allJSON = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return allJSON
            .filter { $0.lastPathComponent.lowercased().hasPrefix("atto-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func customThemeURLs(fileManager: FileManager = .default) -> [URL] {
        let dir = customThemesDirectoryURL(fileManager: fileManager)
        return customThemeURLs(in: dir, fileManager: fileManager)
    }

    static func customThemeURLs(in dir: URL, fileManager: FileManager = .default) -> [URL] {
        guard fileManager.fileExists(atPath: dir.path) else { return [] }

        let urls: [URL] = (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func loadRegistry(
        fileManager: FileManager = .default,
        builtinBundle: Bundle = .module
    ) -> EditorCoreThemeRegistry {
        loadRegistry(
            builtinThemeURLs: builtinThemeURLs(bundle: builtinBundle),
            customThemeURLs: customThemeURLs(fileManager: fileManager)
        )
    }

    static func loadRegistry(
        builtinThemeURLs: [URL],
        customThemeURLs: [URL]
    ) -> EditorCoreThemeRegistry {
        var registry = EditorCoreThemeRegistry()

        for url in builtinThemeURLs {
            do {
                let theme = try EditorCoreThemeLoader.loadTheme(from: url)
                registry.register(.init(theme: theme, source: .builtin, url: url))
            } catch {
                NSLog("AttoEditor: failed to load builtin theme %@: %@", url.path, String(describing: error))
            }
        }

        for url in customThemeURLs {
            do {
                let theme = try EditorCoreThemeLoader.loadTheme(from: url)
                registry.register(.init(theme: theme, source: .custom, url: url))
            } catch {
                NSLog("AttoEditor: failed to load custom theme %@: %@", url.path, String(describing: error))
            }
        }

        return registry
    }

    static func resolveSkiaTheme(
        themeName: String,
        registry: EditorCoreThemeRegistry
    ) -> (resolvedName: String, theme: EditorCoreSkiaTheme) {
        if let t = registry.theme(named: themeName) {
            return (resolvedName: t.name, theme: t.skiaTheme)
        }

        if let fallback = registry.theme(named: defaultThemeName) {
            return (resolvedName: fallback.name, theme: fallback.skiaTheme)
        }

        // Absolute fallback (should only happen when resources are missing).
        return (resolvedName: "Fallback", theme: EditorCoreSkiaTheme.demoRustLspDark())
    }
}
