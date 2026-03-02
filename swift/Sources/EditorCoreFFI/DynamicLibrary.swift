import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class DynamicLibrary {
    let handle: UnsafeMutableRawPointer
    let path: String

    init(path: String) throws {
        self.path = path

        let flags = RTLD_NOW | RTLD_LOCAL
        guard let handle = dlopen(path, flags) else {
            let message: String
            if let err = dlerror() {
                message = String(cString: err)
            } else {
                message = "dlopen failed"
            }
            throw EditorCoreFFIError.failedToLoadLibrary(tried: [path], errors: ["\(path): \(message)"])
        }
        self.handle = handle
    }

    deinit {
        dlclose(handle)
    }

    func loadSymbol<T>(_ name: String, as: T.Type = T.self) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw EditorCoreFFIError.missingSymbol(name: name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

