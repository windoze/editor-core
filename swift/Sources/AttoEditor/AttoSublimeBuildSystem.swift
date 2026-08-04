import Foundation

struct AttoSublimeBuildSystem: Equatable {
    struct LaunchDescriptor: Equatable {
        let executableURL: URL
        let arguments: [String]
        let workingDirectoryURL: URL
        let displayCommand: String
    }

    let name: String
    let fileURL: URL
    let command: [String]
    let shellCommand: String?
    let workingDirectory: String?

    var displayName: String {
        name.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : name
    }

    static func discover(
        in workspaceRootURL: URL,
        fileManager: FileManager = .default,
        limit: Int = 50
    ) -> [AttoSublimeBuildSystem] {
        guard let enumerator = fileManager.enumerator(
            at: workspaceRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var systems: [AttoSublimeBuildSystem] = []
        for case let url as URL in enumerator {
            guard shouldVisit(url: url) else {
                if hasHiddenPathComponent(url: url, rootURL: workspaceRootURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension == "sublime-build",
                  let system = load(from: url, fileManager: fileManager)
            else {
                continue
            }
            systems.append(system)
            if systems.count >= limit { break }
        }

        return systems.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func load(
        from url: URL,
        fileManager: FileManager = .default
    ) -> AttoSublimeBuildSystem? {
        guard let data = fileManager.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode(RawBuildSystem.self, from: data)
        else {
            return nil
        }

        let fallbackName = url.deletingPathExtension().lastPathComponent
        return AttoSublimeBuildSystem(
            name: decoded.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallbackName,
            fileURL: url.standardizedFileURL,
            command: decoded.cmd ?? [],
            shellCommand: decoded.shellCmd?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            workingDirectory: decoded.workingDir?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )
    }

    func launchDescriptor(workspaceRootURL: URL) -> LaunchDescriptor? {
        let workingDirectoryURL = resolvedWorkingDirectoryURL(workspaceRootURL: workspaceRootURL)

        if let first = command.first?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            let executable = expandVariables(in: first, workspaceRootURL: workspaceRootURL)
            let arguments = command.dropFirst().map { expandVariables(in: $0, workspaceRootURL: workspaceRootURL) }
            return LaunchDescriptor(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL,
                displayCommand: ([executable] + arguments).joined(separator: " ")
            )
        }

        guard let shellCommand else { return nil }
        let expanded = expandVariables(in: shellCommand, workspaceRootURL: workspaceRootURL)
        return LaunchDescriptor(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-lc", expanded],
            workingDirectoryURL: workingDirectoryURL,
            displayCommand: expanded
        )
    }

    private func resolvedWorkingDirectoryURL(workspaceRootURL: URL) -> URL {
        guard let workingDirectory else { return workspaceRootURL.standardizedFileURL }
        let expanded = expandVariables(in: workingDirectory, workspaceRootURL: workspaceRootURL)
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return workspaceRootURL.appendingPathComponent(expanded, isDirectory: true).standardizedFileURL
    }

    private func expandVariables(in value: String, workspaceRootURL: URL) -> String {
        value
            .replacingOccurrences(of: "${project_path}", with: workspaceRootURL.path)
            .replacingOccurrences(of: "$project_path", with: workspaceRootURL.path)
            .replacingOccurrences(of: "${folder}", with: workspaceRootURL.path)
            .replacingOccurrences(of: "$folder", with: workspaceRootURL.path)
    }

    private static func shouldVisit(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]) else {
            return false
        }
        return values.isHidden != true || values.isRegularFile == true
    }

    private static func hasHiddenPathComponent(url: URL, rootURL: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count)
        return components.contains { $0.hasPrefix(".") }
    }

    private struct RawBuildSystem: Decodable {
        let name: String?
        let cmd: [String]?
        let shellCmd: String?
        let workingDir: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case cmd
            case shellCmd = "shell_cmd"
            case workingDir = "working_dir"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
