import Foundation
import XCTest
@testable import ExecutableEntrySentinel

final class ExecutableEntrySentinelTests: XCTestCase {
    @MainActor func testCallableSymbolWithoutExecutingEntry() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["GOR_ENTRY_SENTINEL_PATH"])
        let success = try XCTUnwrap(ProcessInfo.processInfo.environment["GOR_ENTRY_SENTINEL_SUCCESS"])
        // Renderer supplies clean, unique paths and retains both after execution.
        guard !FileManager.default.fileExists(atPath: path),
              !FileManager.default.fileExists(atPath: success) else {
            XCTFail("sentinel evidence paths must begin absent")
            return
        }
        XCTAssertEqual(callableExecutableSymbol(), 42)
        guard callableExecutableSymbol() == 42 else { return }
        await Task.yield()
        guard !FileManager.default.fileExists(atPath: path) else {
            XCTFail("executable entry unexpectedly ran")
            return
        }
        try Data("CALLABLE_42_ENTRY_ABSENT\n".utf8).write(to: URL(fileURLWithPath: success), options: .atomic)
    }
}
