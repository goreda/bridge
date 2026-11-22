// W-gdb-019: seek-vector pack model (adversarial seek vector pack).
//
// Added by the W-gdb-019 patch. Pack schema: seek-vector-pack/1, generated
// by kits/seek-vectors/generate.py (byte-deterministic). The pack asserts
// ONLY the pinned vocabulary of gorav @ 2112af0d60df16c5473173b664903f76ce54173e:
//   SeekAudioOutcome  (8 cases)
//   AudioSeekResult   { refused(AudioSeekRefusal) | nativeReady(...) | closeRequired(...) }
//   AudioSeekRefusal  (7 cases)
// No media bytes: synthetic stream descriptions only.
//
// STATUS: authored for Swift 6.1.2 / Foundation. NOT BUILT, NOT RUN in the
// authoring environment (no Swift toolchain there). The integrator must run:
//   swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json
// and the negative control:
//   swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json --negative-control
// See README-SEEKVECTORS.md for the one-line wiring into the existing main.

import Foundation

public struct SeekVectorPack: Codable {
    public var packId: String
    public var schema: String
    public var productRepo: String
    public var productSha: String
    public var vocabulary: SeekVectorVocabulary
    /// Pack schema conventions (e.g. acceptedTargetTicks arithmetic is a
    /// pack convention, not excerpt-derived).
    public var conventions: [String]?
    public var vectors: [SeekVector]

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case schema
        case productRepo = "product_repo"
        case productSha = "product_sha"
        case vocabulary
        case conventions
        case vectors
    }
}

public struct SeekVectorVocabulary: Codable, Equatable {
    public var seekAudioOutcome: [String]
    public var audioSeekRefusal: [String]
    public var audioSeekResult: [String]

    enum CodingKeys: String, CodingKey {
        case seekAudioOutcome = "SeekAudioOutcome"
        case audioSeekRefusal = "AudioSeekRefusal"
        case audioSeekResult = "AudioSeekResult"
    }
}

public struct SeekVector: Codable {
    public var id: String
    public var vectorClass: String
    public var note: String
    public var stream: SeekVectorStream
    public var request: SeekVectorRequest
    public var scenario: SeekVectorScenario
    public var expected: SeekVectorDecision

    enum CodingKeys: String, CodingKey {
        case id
        case vectorClass = "class"
        case note, stream, request, scenario, expected
    }
}

public struct SeekVectorStream: Codable {
    public var kind: String
    public var timescale: Int64
    public var durationTicks: Int64
    public var gopTicks: Int64
    public var editListOffsetTicks: Int64
    public var seekable: Bool
    public var originKnown: Bool
    public var bindingState: String
    public var audioMode: String
}

public struct SeekVectorRequest: Codable {
    public var targetTicks: Int64
    public var targetSeconds: Double
    public var parkedVideo: Bool
    public var priorSeekInFlight: Bool
    public var priorCorrelation: UInt64
    public var correlation: UInt64
}

public struct SeekVectorScenario: Codable {
    public var videoSeekCommitted: Bool
    /// "presented" | "timeout" | "skipped-parked"
    public var firstFrameAnchor: String
    /// "ok" | "refused"
    public var ringReset: String
    /// "ok" | "refused"
    public var resumeProducer: String
    public var audioSeek: SeekVectorAudioSeek
}

public struct SeekVectorAudioSeek: Codable {
    /// "native" | "refused"
    public var kind: String
    public var nativeCode: Int32?
    public var seekTicks: Int64?
    /// AudioSeekRefusal case name when kind == "refused"
    public var reason: String?
}

/// The decision table one vector asserts: accepted target, anchor
/// expectation, reset requirement, typed outcome, typed audio result.
public struct SeekVectorDecision: Codable, Equatable {
    public var acceptedTargetTicks: Int64
    /// "required-and-presented" | "skipped-parked" | "timeout-closes" | "not-reached"
    public var anchorExpectation: String
    public var ringResetRequired: Bool
    /// SeekAudioOutcome case name (pinned vocabulary)
    public var outcome: String
    public var audioSeekResult: SeekVectorAudioResult?
}

public struct SeekVectorAudioResult: Codable, Equatable {
    /// "nativeReady" | "refused" | "closeRequired"
    public var kind: String
    public var seekTicks: Int64?
    public var reason: String?
    public var nativeCode: Int32?
}

public enum SeekVectorPackError: Error {
    case unreadablePack(String)
    case vocabularyMismatch(String)
}

extension SeekVectorPack {
    public static func load(from path: String) throws -> SeekVectorPack {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw SeekVectorPackError.unreadablePack(path)
        }
        return try JSONDecoder().decode(SeekVectorPack.self, from: data)
    }

    /// Fails if any expected outcome / refusal reason is outside the pinned
    /// vocabulary. No invented outcome strings are accepted.
    public func validateVocabulary() throws {
        let pinnedOutcomes = SeekVectorReplay.pinnedSeekAudioOutcomes
        let pinnedRefusals = SeekVectorReplay.pinnedAudioSeekRefusals
        guard vocabulary.seekAudioOutcome == pinnedOutcomes else {
            throw SeekVectorPackError.vocabularyMismatch("SeekAudioOutcome")
        }
        guard vocabulary.audioSeekRefusal == pinnedRefusals else {
            throw SeekVectorPackError.vocabularyMismatch("AudioSeekRefusal")
        }
        for vector in vectors {
            guard pinnedOutcomes.contains(vector.expected.outcome) else {
                throw SeekVectorPackError.vocabularyMismatch(
                    "\(vector.id): outcome \(vector.expected.outcome)")
            }
            if let result = vector.expected.audioSeekResult {
                guard ["nativeReady", "refused", "closeRequired"].contains(result.kind) else {
                    throw SeekVectorPackError.vocabularyMismatch(
                        "\(vector.id): audioSeekResult kind \(result.kind)")
                }
                if result.kind == "refused",
                   let reason = result.reason,
                   !pinnedRefusals.contains(reason) {
                    throw SeekVectorPackError.vocabularyMismatch(
                        "\(vector.id): refusal \(reason)")
                }
            }
        }
    }
}
