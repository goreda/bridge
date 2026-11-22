// CacheAccounting: portable generation-scoped cache byte accounting (SUPPORT only).
// No I/O, no eviction, no player/ffmpeg/live cache wiring. Darwin/Linux portable.
// Archive item identifiers enter only through the explicit boundary below
// (ArchiveItemSource.identifier); this type never re-implements identifier rules.
//
// Concurrency scope: synchronous single-owner. Instances are NOT thread-safe;
// confinement is the caller's responsibility. The only shared state is the
// instance-id counter, owned by LockedCounter below (NSLock-based, Sendable);
// strict Swift 6 complete-concurrency clean, no nonisolated(unsafe).
// Deployment floor preserved: NSLock predates macOS 13; no macOS-15-only
// symbols (no Synchronization.Mutex).
import Foundation

public enum CacheAccountingError: Error, Equatable {
    /// Identifier refused at the ArchiveItemSource boundary.
    case invalidIdentifier
    /// Token belongs to a generation invalidated by reset().
    case staleGeneration(expected: UInt64, found: UInt64)
    /// Token was already consumed for the requested transition (double commit/release).
    case duplicateToken(id: UInt64)
    /// Token id was never issued in the current generation.
    case unknownToken(id: UInt64)
    /// Token was issued by a different CacheAccounting instance (including a
    /// re-created instance after the issuer was destroyed).
    case foreignInstance
    /// Capacity bound, a UInt64 arithmetic limit, the reset-generation space,
    /// or the instance-id space would be exceeded.
    case overflow
    /// A release/commit would subtract more bytes than the token accounts for.
    case underflow
}

/// A token is bound to its issuing instance AND generation. It has no public
/// initializer: tokens can only be obtained from reserve(), so issuer state is
/// not forgeable through the public API.
public struct CacheToken: Equatable, Hashable, Sendable {
    public let instance: UInt64
    public let generation: UInt64
    public let id: UInt64
}

/// Accounting is generation-scoped: reset() invalidates every prior token
/// (staleGeneration) and releases all accounted bytes. Token tombstones (.released)
/// live only within their generation, so reset() bounds bookkeeping growth.
/// Sendable owner for the process-wide issuer counter. The @unchecked Sendable
/// conformance is the single unavoidable waiver, stated explicitly: mutual
/// exclusion is implemented manually with NSLock, so every access to the
/// protected value is serialized by construction. NSLock is used (not
/// Synchronization.Mutex, which requires macOS 15) to preserve the macOS 13
/// deployment floor. Not public API; internal only as the labeled test seam.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    /// Checked, non-wrapping, fail-closed: nil at UInt64 exhaustion, never traps.
    func allocate() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { return nil }
        value = next
        return next
    }
    /// Labeled test seam (@testable only): seed/read the counter.
    func seed(_ newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
    func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public final class CacheAccounting {
    public let capacity: UInt64
    public let instanceID: UInt64
    public private(set) var generation: UInt64
    public private(set) var reservedBytes: UInt64 = 0
    public private(set) var committedBytes: UInt64 = 0
    public private(set) var nextTokenID: UInt64 = 0
    /// True when the process instance-id space was exhausted while creating this
    /// instance. A poisoned instance refuses every operation with .overflow and
    /// never accounts bytes (fail-closed; the allocator never traps).
    public private(set) var isExhausted: Bool

    private enum TokenState: Equatable {
        case reserved(UInt64)
        case committed(UInt64)
        case released
    }
    private var tokens: [UInt64: TokenState] = [:]

    /// Process-wide issuer counter, owned by a Sendable lock box. Internal
    /// (not private) ONLY as a labeled test seam so counter exhaustion is
    /// exercisable without 2^64 allocations; access always goes through the
    /// locked methods, so there is no nonisolated mutable state.
    static let issuerCounter = LockedCounter()
    /// Fail-closed allocation: returns nil at UInt64 exhaustion instead of
    /// trapping or wrapping. instanceID 0 is never issued, so a poisoned
    /// instance's tokens can never collide with a real issuer's.
    private static func allocateInstanceID() -> UInt64? {
        issuerCounter.allocate()
    }

    public init(capacity: UInt64) {
        self.capacity = capacity
        if let allocated = Self.allocateInstanceID() {
            self.instanceID = allocated
            self.isExhausted = false
        } else {
            self.instanceID = 0
            self.isExhausted = true
        }
        self.generation = 0
    }

    /// LABELED INSTRUMENTATION, test-only seam (@testable): constructs an
    /// instance at a chosen generation so reset-exhaustion behavior is reachable
    /// without 2^64 real resets. Not public API.
    init(capacity: UInt64, generation: UInt64) {
        self.capacity = capacity
        if let allocated = Self.allocateInstanceID() {
            self.instanceID = allocated
            self.isExhausted = false
        } else {
            self.instanceID = 0
            self.isExhausted = true
        }
        self.generation = generation
    }

    /// Explicit adapter boundary: identifiers are validated by the pinned
    /// ArchiveItemSource and mapped to a typed refusal here.
    public static func validatedIdentifier(_ id: String) throws -> String {
        do {
            return try ArchiveItemSource.identifier(id)
        } catch {
            throw CacheAccountingError.invalidIdentifier
        }
    }

    /// Total bytes currently accounted. Mutations keep this <= capacity via
    /// checked arithmetic, so the plain addition here cannot overflow.
    public var accountedBytes: UInt64 { reservedBytes + committedBytes }

    /// Reserve bytes in the current generation. Atomic: a refused reserve
    /// changes no counters and issues no token.
    @discardableResult
    public func reserve(identifier: String, bytes: UInt64) throws -> CacheToken {
        guard !isExhausted else { throw CacheAccountingError.overflow }
        _ = try Self.validatedIdentifier(identifier)
        guard bytes > 0 else { throw CacheAccountingError.underflow }
        let (newAccounted, accountOverflow) = accountedBytes.addingReportingOverflow(bytes)
        guard !accountOverflow, newAccounted <= capacity else {
            throw CacheAccountingError.overflow
        }
        let (nextID, idOverflow) = nextTokenID.addingReportingOverflow(1)
        guard !idOverflow else { throw CacheAccountingError.overflow }
        let token = CacheToken(instance: instanceID, generation: generation, id: nextTokenID)
        tokens[token.id] = .reserved(bytes)
        reservedBytes += bytes
        nextTokenID = nextID
        return token
    }

    private func stateForToken(_ token: CacheToken) throws -> TokenState {
        guard !isExhausted else { throw CacheAccountingError.overflow }
        guard token.instance == instanceID else { throw CacheAccountingError.foreignInstance }
        guard token.generation == generation else {
            throw CacheAccountingError.staleGeneration(expected: generation, found: token.generation)
        }
        guard let state = tokens[token.id] else {
            throw CacheAccountingError.unknownToken(id: token.id)
        }
        return state
    }

    /// Commit a reserved token: its bytes move from reserved to committed.
    public func commit(_ token: CacheToken) throws {
        switch try stateForToken(token) {
        case .reserved(let bytes):
            let (newCommitted, commitOverflow) = committedBytes.addingReportingOverflow(bytes)
            guard bytes <= reservedBytes, !commitOverflow else {
                throw CacheAccountingError.underflow
            }
            reservedBytes -= bytes
            committedBytes = newCommitted
            tokens[token.id] = .committed(bytes)
        case .committed:
            throw CacheAccountingError.duplicateToken(id: token.id)
        case .released:
            throw CacheAccountingError.duplicateToken(id: token.id)
        }
    }

    /// Release a token: its bytes leave the accounting exactly once.
    public func release(_ token: CacheToken) throws {
        switch try stateForToken(token) {
        case .reserved(let bytes):
            guard bytes <= reservedBytes else { throw CacheAccountingError.underflow }
            reservedBytes -= bytes
            tokens[token.id] = .released
        case .committed(let bytes):
            guard bytes <= committedBytes else { throw CacheAccountingError.underflow }
            committedBytes -= bytes
            tokens[token.id] = .released
        case .released:
            throw CacheAccountingError.duplicateToken(id: token.id)
        }
    }

    /// Invalidate the current generation: all accounted bytes are released and
    /// every prior token becomes stale. Generation exhaustion is an explicit
    /// typed refusal (overflow) that leaves state unchanged; there is no silent
    /// wrap and no prior token can re-validate.
    public func reset() throws {
        guard !isExhausted else { throw CacheAccountingError.overflow }
        guard generation < UInt64.max else { throw CacheAccountingError.overflow }
        tokens.removeAll()
        reservedBytes = 0
        committedBytes = 0
        nextTokenID = 0
        generation += 1
    }
}
