import XCTest
@testable import GorAVPlaybackCore

final class CacheAccountingTests: XCTestCase {
    private func make(capacity: UInt64 = 1024) -> CacheAccounting { CacheAccounting(capacity: capacity) }

    func testReserveThenCommitThenRelease() throws {
        let acct = make()
        let t = try acct.reserve(identifier: "some-item_01", bytes: 100)
        XCTAssertEqual(acct.reservedBytes, 100)
        XCTAssertEqual(acct.accountedBytes, 100)
        try acct.commit(t)
        XCTAssertEqual(acct.reservedBytes, 0)
        XCTAssertEqual(acct.committedBytes, 100)
        try acct.release(t)
        XCTAssertEqual(acct.committedBytes, 0)
        XCTAssertEqual(acct.accountedBytes, 0)
    }

    func testFailureAtomicityOfRefusedReserve() throws {
        let acct = make(capacity: 100)
        let t = try acct.reserve(identifier: "ok", bytes: 60)
        XCTAssertThrowsError(try acct.reserve(identifier: "too-big", bytes: 41)) {
            XCTAssertEqual($0 as? CacheAccountingError, .overflow)
        }
        // Refused reserve changed nothing: prior state intact, no token leaked.
        XCTAssertEqual(acct.accountedBytes, 60)
        XCTAssertEqual(acct.nextTokenID, 1)
        try acct.release(t)
        XCTAssertEqual(acct.accountedBytes, 0)
    }

    func testOverCapacityRefusedExactlyAtBound() throws {
        let acct = make(capacity: 200)
        _ = try acct.reserve(identifier: "a", bytes: 200)
        XCTAssertThrowsError(try acct.reserve(identifier: "b", bytes: 1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .overflow)
        }
        XCTAssertEqual(acct.accountedBytes, 200)
    }

    func testUInt64BoundaryArithmetic() throws {
        let acct = make(capacity: UInt64.max)
        let t = try acct.reserve(identifier: "big", bytes: UInt64.max)
        XCTAssertEqual(acct.accountedBytes, UInt64.max)
        // One more byte must be a typed overflow, not a wrap to zero.
        XCTAssertThrowsError(try acct.reserve(identifier: "wrap", bytes: 1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .overflow)
        }
        XCTAssertEqual(acct.accountedBytes, UInt64.max)
        try acct.commit(t)
        XCTAssertEqual(acct.committedBytes, UInt64.max)
        try acct.release(t)
        XCTAssertEqual(acct.accountedBytes, 0)
    }

    func testDoubleReleaseAndDoubleCommitRefused() throws {
        let acct = make()
        let t1 = try acct.reserve(identifier: "d1", bytes: 10)
        try acct.release(t1)
        XCTAssertThrowsError(try acct.release(t1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .duplicateToken(id: t1.id))
        }
        XCTAssertThrowsError(try acct.commit(t1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .duplicateToken(id: t1.id))
        }
        let t2 = try acct.reserve(identifier: "d2", bytes: 10)
        try acct.commit(t2)
        XCTAssertThrowsError(try acct.commit(t2)) {
            XCTAssertEqual($0 as? CacheAccountingError, .duplicateToken(id: t2.id))
        }
        try acct.release(t2)
        XCTAssertEqual(acct.accountedBytes, 0)
    }

    func testUnknownTokenRefused() throws {
        let acct = make()
        let forged = CacheToken(generation: 0, id: 77)
        XCTAssertThrowsError(try acct.release(forged)) {
            XCTAssertEqual($0 as? CacheAccountingError, .unknownToken(id: 77))
        }
    }

    func testResetInvalidatesPriorGeneration() throws {
        let acct = make()
        let t = try acct.reserve(identifier: "old", bytes: 50)
        try acct.commit(t)
        acct.reset()
        XCTAssertEqual(acct.accountedBytes, 0)
        XCTAssertEqual(acct.generation, 1)
        XCTAssertThrowsError(try acct.release(t)) {
            XCTAssertEqual($0 as? CacheAccountingError, .staleGeneration(expected: 1, found: 0))
        }
        // New generation reuses token ids safely: generation is part of the token.
        let t2 = try acct.reserve(identifier: "new", bytes: 50)
        XCTAssertEqual(t2.generation, 1)
        try acct.release(t2)
    }

    func testZeroSizeRefused() throws {
        let acct = make()
        XCTAssertThrowsError(try acct.reserve(identifier: "zero", bytes: 0)) {
            XCTAssertEqual($0 as? CacheAccountingError, .underflow)
        }
        XCTAssertEqual(acct.accountedBytes, 0)
        XCTAssertEqual(acct.nextTokenID, 0)
    }

    func testIdentifierBoundaryUsesArchiveItemSource() throws {
        let acct = make()
        XCTAssertThrowsError(try acct.reserve(identifier: "bad id!", bytes: 1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .invalidIdentifier)
        }
        XCTAssertThrowsError(try acct.reserve(identifier: "..", bytes: 1)) {
            XCTAssertEqual($0 as? CacheAccountingError, .invalidIdentifier)
        }
        _ = try acct.reserve(identifier: "good-item_1.2", bytes: 1)
        XCTAssertEqual(try CacheAccounting.validatedIdentifier("good-item_1.2"), "good-item_1.2")
    }

    func testDeterministicReplay() throws {
        func script() throws -> [UInt64] {
            let acct = make(capacity: 500)
            var seen: [UInt64] = []
            let a = try acct.reserve(identifier: "r1", bytes: 100)
            let b = try acct.reserve(identifier: "r2", bytes: 100)
            try acct.commit(a)
            try acct.release(b)
            acct.reset()
            let c = try acct.reserve(identifier: "r3", bytes: 500)
            seen = [a.id, b.id, c.id, acct.accountedBytes, acct.generation]
            return seen
        }
        XCTAssertEqual(try script(), try script())
        XCTAssertEqual(try script(), [0, 1, 0, 500, 1])
    }
}
