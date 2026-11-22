import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Non-log runtime files are never adopted or removed by the log publisher.
/// One private directory per app process, including when log capture is absent.
/// This preserves existing resource sizes; it is not a disk quota mechanism.
enum PlayerRuntimeResources {
    private static let allocation: Result<URL, Error> = Result {
        // mkdtemp creates the final owned directory atomically with mode 0700.
        // Do not follow or adopt an existing resource directory by name.
        var template = Array((NSTemporaryDirectory() + "gor-runtime-\(ProcessInfo.processInfo.processIdentifier)-XXXXXX").utf8CString)
        // mkdtemp rewrites the template in place. The returned C pointer
        // aliases the inout bridge buffer and must not escape the call; read
        // the owned array instead (Linux -O traps otherwise, UB anywhere).
        guard mkdtemp(&template) != nil else { throw CocoaError(.fileWriteUnknown) }
        let path = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    static func root() throws -> URL { try allocation.get() }
    static func path(_ original: String) throws -> String {
        let name = URL(fileURLWithPath: original).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix(".") else { throw CocoaError(.fileWriteInvalidFileName) }
        return try root().appendingPathComponent(name).path
    }
    // No deinit/global sweep. Child-specific owners may remove their exact
    // resources only after their real writer lifetime has been established.
}
