// CacheAccounting: portable generation-scoped cache byte accounting (SUPPORT only).
// No I/O, no eviction, no player/ffmpeg/live cache wiring. Darwin/Linux portable.
// Archive item identifiers enter only through the explicit boundary below
// (ArchiveItemSource.identifier); this type never re-implements identifier rules.
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
    /// Capacity bound or a UInt64 arithmetic limit would be exceeded.
    case overflow
    /// A release/commit would subtract more bytes than the token accounts for.
    case underflow
}

public struct CacheToken: Equatable, Hashable, Sendable {
    public let generation: UInt64
    public let id: UInt64
}

/// Accounting is generation-scoped: reset() invalidates every prior token
/// (staleGeneration) and releases all accounted bytes. Token tombstones (.released)
/// live only within their generation, so reset() bounds bookkeeping growth.
public final class CacheAccounting {
    public let capacity: UInt64
    public private(set) var generation: UInt64 = 0
    public private(set) var reservedBytes: UInt64 = 0
    public private(set) var committedBytes: UInt64 = 0
    public private(set) var nextTokenID: UInt64 = 0

    private enum TokenState: Equatable {
        case reserved(UInt64)
        case committed(UInt64)
        case released
    }
    private var tokens: [UInt64: TokenState] = [:]

    public init(capacity: UInt64) {
        self.capacity = capacity
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
        _ = try Self.validatedIdentifier(identifier)
        guard bytes > 0 else { throw CacheAccountingError.underflow }
        let (newAccounted, accountOverflow) = accountedBytes.addingReportingOverflow(bytes)
        guard !accountOverflow, newAccounted <= capacity else {
            throw CacheAccountingError.overflow
        }
        let (nextID, idOverflow) = nextTokenID.addingReportingOverflow(1)
        guard !idOverflow else { throw CacheAccountingError.overflow }
        let token = CacheToken(generation: generation, id: nextTokenID)
        tokens[token.id] = .reserved(bytes)
        reservedBytes += bytes
        nextTokenID = nextID
        return token
    }

    /// Commit a reserved token: its bytes move from reserved to committed.
    public func commit(_ token: CacheToken) throws {
        guard token.generation == generation else {
            throw CacheAccountingError.staleGeneration(expected: generation, found: token.generation)
        }
        guard let state = tokens[token.id] else {
            throw CacheAccountingError.unknownToken(id: token.id)
        }
        switch state {
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
        guard token.generation == generation else {
            throw CacheAccountingError.staleGeneration(expected: generation, found: token.generation)
        }
        guard let state = tokens[token.id] else {
            throw CacheAccountingError.unknownToken(id: token.id)
        }
        switch state {
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
    /// every prior token becomes stale. Wrapping generation still invalidates
    /// because tokens carry the pre-reset value.
    public func reset() {
        tokens.removeAll()
        reservedBytes = 0
        committedBytes = 0
        nextTokenID = 0
        generation = generation &+ 1
    }
}
