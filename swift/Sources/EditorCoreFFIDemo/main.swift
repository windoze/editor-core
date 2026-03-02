import EditorCoreFFI
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@main
struct EditorCoreFFIDemoMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let explicitPath = args.first

        do {
            let library = try EditorCoreFFILibrary(path: explicitPath)
            let version = try library.versionString()
            print("editor-core-ffi loaded")
            print("  path: \(library.resolvedLibraryPath)")
            print("  abi:  \(library.abiVersion)")
            print("  ver:  \(version)")

            let state = try EditorState(library: library, initialText: "Hello\nWorld\n", viewportWidth: 80)
            try state.moveTo(line: 0, column: 5)
            try state.insertText(", Swift")

            let text = try state.text()
            print("\n--- text ---\n\(text)")

            let stats = try state.documentStats()
            print("\n--- stats ---")
            print("lines=\(stats.lineCount) chars=\(stats.charCount) bytes=\(stats.byteCount) modified=\(stats.isModified) ver=\(stats.version)")

            let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 20)
            print("\n--- viewport blob ---")
            print("lines=\(blob.header.lineCount) cells=\(blob.header.cellCount) styleIds=\(blob.header.styleIdCount)")
        } catch {
            eprint("Error: \(error)")
            exit(1)
        }
    }
}

