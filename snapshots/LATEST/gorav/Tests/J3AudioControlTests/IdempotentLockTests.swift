import XCTest
import GorAVPlaybackCore

private actor ConcurrentTerminalSource: FrameSource {
    private var pulls = 0
    func nextEvent() async -> SourceEvent {
        pulls += 1
        await Task.yield()
        return .ended(.endOfStream)
    }
    func count() -> Int { pulls }
}

final class IdempotentLockTests: XCTestCase {
    func testConcurrentTerminalLatchAndCounter() async {
        let inner = ConcurrentTerminalSource()
        let source = IdempotentEventSource(inner, binding: SourceSession(session: 99, revision: 1))
        let allTerminal = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for _ in 0..<128 {
                group.addTask {
                    let event = await source.nextEvent()
                    source.recordViolation(.eventAfterTerminal)
                    if case .ended(.endOfStream) = event { return true }
                    return false
                }
            }
            var result = true
            for await terminal in group { result = result && terminal }
            return result
        }
        XCTAssertTrue(allTerminal)
        XCTAssertEqual(source.violationCount, 128)
        XCTAssertEqual(source.lastViolation, .eventAfterTerminal)
        let beforeReplay = await inner.count()
        for _ in 0..<20 {
            guard case .ended(.endOfStream) = await source.nextEvent() else {
                XCTFail("latched terminal not replayed"); return
            }
        }
        let afterReplay = await inner.count()
        XCTAssertEqual(afterReplay, beforeReplay, "no inner pulls after terminal latch")
        XCTAssertEqual(source.binding, SourceSession(session: 99, revision: 1))
    }
}
