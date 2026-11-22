// 199r-03 SUBTITLE-OWNER: authoritative sidecar selection policy + async load
// cancellation lifetime. Pure Swift value types, Linux-verifiable, no
// Foundation dependency, no file I/O, no discovery. Discovery stays with
// SubtitleAutoLoad; the session stays the cue/clock owner. This plan is the
// single authority for WHICH candidate a selector resolves to and for WHETHER
// an in-flight load completion may still land. Selection is typed and loud:
// an explicit request that the discovered set cannot honor is a typed
// refusal, never a silent fallback (same contract as AudioTrackPlan 199r-01).
//
// Wiring state: UNWIRED support seam. SubtitleSidecarSession adoption (its
// loadExactPrimary/select semantics map 1:1 onto this plan, and its ad-hoc
// revision/ticket pair maps onto SubtitleLoadLedger) is a separate claim on
// that existing shared file; until then this file changes no runtime
// behavior. The lab SubtitleSelectionPolicy is NOT edited or ported here;
// this is the gorav-native authority.

/// One playback slot as the selection layer needs it (mirrors
/// SubtitleController.Slot without dragging the controller into the policy).
public enum SubtitleSidecarSlot: String, Equatable, Sendable, CaseIterable {
    case primary
    case secondary
}

/// One discovered sidecar as the policy needs it (mirrors
/// SubtitleAutoLoad.Candidate without importing discovery).
public struct SubtitleSidecarCandidate: Equatable, Sendable {
    /// Canonical local path of the sidecar file.
    public let path: String
    /// nil for an exact-basename match; otherwise the tag between the video
    /// basename and the extension (usually a language code).
    public let tag: String?
    /// "srt" or "ass" ("ssa" is normalized to "ass" by discovery).
    public let format: String
    public init?(path: String, tag: String?, format: String) {
        guard !path.isEmpty, !format.isEmpty else { return nil }
        self.path = path; self.tag = tag; self.format = format
    }
}

public enum SubtitleSidecarSelector: Equatable, Sendable {
    /// Exact-basename SRT first; an exact-basename ASS with no exact SRT is a
    /// typed refusal; tagged files are never auto-selected. This is exactly
    /// the session's loadExactPrimary semantics today.
    case auto
    /// Explicit discovered path.
    case path(String)
    /// Exact tag, case-insensitive (e.g. "en", "tr").
    case tag(String)
}

public enum SubtitleSidecarPlanRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    /// The discovered candidate set is empty.
    case noSidecars
    /// Auto selection found no exact-basename sidecar at all.
    case noExactSidecar
    /// The resolved candidate is ASS/SSA; only SRT is supported today.
    case unsupportedASS
    /// An explicit path that discovery never produced.
    case notDiscovered(String)
    /// An explicit tag no candidate carries.
    case requestedTagAbsent(String)
    /// 199r-03: two candidates carry the same tag (e.g. movie.en.srt and
    /// movie.en.ass), so any tag pick among them would be arbitrary. Typed
    /// refusal, never a silent pick (mirrors AudioTrackRefusal.duplicateIndex).
    case duplicateTag(String)
    public var description: String {
        switch self {
        case .noSidecars: return "noSidecars"
        case .noExactSidecar: return "noExactSidecar"
        case .unsupportedASS: return "unsupportedASS"
        case .notDiscovered(let p): return "notDiscovered(\(p))"
        case .requestedTagAbsent(let t): return "requestedTagAbsent(\(t))"
        case .duplicateTag(let t): return "duplicateTag(\(t))"
        }
    }
}

public enum SubtitleSidecarPlan {
    public static func select(_ selector: SubtitleSidecarSelector,
                              from candidates: [SubtitleSidecarCandidate])
        -> Result<SubtitleSidecarCandidate, SubtitleSidecarPlanRefusal> {
        guard !candidates.isEmpty else { return .failure(.noSidecars) }
        // 199r-03: an ambiguous tag set is refused before any selector runs.
        if let d = duplicateTag(in: candidates) { return .failure(.duplicateTag(d)) }
        switch selector {
        case .auto:
            if let exact = candidates.first(where: { $0.tag == nil && $0.format == "srt" }) {
                return .success(exact)
            }
            if candidates.contains(where: { $0.tag == nil && $0.format == "ass" }) {
                return .failure(.unsupportedASS)
            }
            return .failure(.noExactSidecar)
        case .path(let p):
            guard let c = candidates.first(where: { $0.path == p }) else {
                return .failure(.notDiscovered(p))
            }
            guard c.format == "srt" else { return .failure(.unsupportedASS) }
            return .success(c)
        case .tag(let t):
            let wanted = t.lowercased()
            guard let c = candidates.first(where: { $0.tag?.lowercased() == wanted }) else {
                return .failure(.requestedTagAbsent(t))
            }
            guard c.format == "srt" else { return .failure(.unsupportedASS) }
            return .success(c)
        }
    }

    /// 199r-03: ordered tag preferences followed by the current auto policy.
    /// Deterministic: the first preference that matches any candidate wins,
    /// and within one preference the first matching candidate in discovery
    /// order. A preference that matches nothing advances to the next one;
    /// exhausted preferences resolve exactly like `.auto`. Matching is
    /// case-insensitive, same as `.tag`. An ambiguous tag set is refused
    /// before any preference runs; an empty preference list is pure auto.
    /// A matched candidate with an unsupported format is a typed refusal,
    /// never a silent skip to the next preference.
    public static func selectPreferred(_ preferences: [String],
                                       from candidates: [SubtitleSidecarCandidate])
        -> Result<SubtitleSidecarCandidate, SubtitleSidecarPlanRefusal> {
        guard !candidates.isEmpty else { return .failure(.noSidecars) }
        if let d = duplicateTag(in: candidates) { return .failure(.duplicateTag(d)) }
        for preference in preferences {
            let wanted = preference.lowercased()
            if let c = candidates.first(where: { $0.tag?.lowercased() == wanted }) {
                guard c.format == "srt" else { return .failure(.unsupportedASS) }
                return .success(c)
            }
        }
        return select(.auto, from: candidates)
    }

    /// The first tag (original casing, discovery order) carried by more than
    /// one candidate, compared case-insensitively, if any.
    private static func duplicateTag(in candidates: [SubtitleSidecarCandidate]) -> String? {
        var seen = Set<String>()
        for c in candidates {
            guard let tag = c.tag else { continue }
            if !seen.insert(tag.lowercased()).inserted { return tag }
        }
        return nil
    }
}

/// One issued async load attempt. A completion carrying this lease may land
/// only while the issuing ledger still honors it.
public struct SubtitleLoadLease: Equatable, Sendable {
    public let revision: UInt64
    public let slot: SubtitleSidecarSlot
    public let ticket: UInt64
}

/// 199r-03 SUBTITLE-OWNER: authoritative cancellation-lifetime ledger for
/// async sidecar loads. This formalizes exactly the session's existing
/// revision/ticket fences as one testable value type: issuing a load bumps
/// only that slot's ticket; source replacement, seek and reset invalidate
/// every in-flight lease at once; close is terminal and monotonic - a closed
/// ledger never revives and honors nothing. All arithmetic is wrapping, same
/// as the session's &+=, so a long-lived session cannot overflow into a
/// collision domain within any realistic lifetime.
public struct SubtitleLoadLedger: Equatable, Sendable {
    public private(set) var revision: UInt64 = 0
    public private(set) var closed = false
    private var primaryTicket: UInt64 = 0
    private var secondaryTicket: UInt64 = 0

    public init() {}

    /// Issue the next lease for a slot, superseding that slot's outstanding
    /// lease only. nil once closed: a closed session issues no new loads.
    public mutating func issue(_ slot: SubtitleSidecarSlot) -> SubtitleLoadLease? {
        guard !closed else { return nil }
        switch slot {
        case .primary: primaryTicket &+= 1
        case .secondary: secondaryTicket &+= 1
        }
        return SubtitleLoadLease(revision: revision, slot: slot, ticket: ticket(slot))
    }

    /// Invalidate every in-flight lease (source replacement, seek, reset).
    public mutating func invalidateAll() {
        revision &+= 1
        primaryTicket &+= 1
        secondaryTicket &+= 1
    }

    /// Terminal: invalidates everything and honors nothing ever again.
    public mutating func close() {
        guard !closed else { return }
        invalidateAll()
        closed = true
    }

    /// A completion is honored only while its lease is current: ledger open,
    /// revision untouched since issue, and the slot's ticket unbumped.
    public func honors(_ lease: SubtitleLoadLease) -> Bool {
        !closed && lease.revision == revision && lease.ticket == ticket(lease.slot)
    }

    private func ticket(_ slot: SubtitleSidecarSlot) -> UInt64 {
        switch slot {
        case .primary: return primaryTicket
        case .secondary: return secondaryTicket
        }
    }
}
