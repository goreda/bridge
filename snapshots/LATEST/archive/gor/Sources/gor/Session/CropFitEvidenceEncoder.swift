// Session/CropFitEvidenceEncoder.swift
// Pure crop/fit evidence event encoder: fixed numeric schema, staged rows, landing verdict computed here, row/byte/line caps; no I/O.
// Uses: Foundation
// Engine: none
import Foundation

/// Pure event encoder. Owner injects UTC/monotonic clocks and sends the returned
/// data to its existing bounded per-player DiagSessionSink, never a new file.
/// One instance per player/load. This object deliberately does no I/O.
struct CropFitEvidenceEncoder {
    enum Stage: String {
        case requested, readRequested, readCompleted, consensus, fitGated
        case fitTarget, dispatched, commandACK, landing
    }
    struct Identity {
        let player: String, window: Int, load: UInt64, scan: UInt64
    }
    struct Event {
        let stage: Stage
        let utcMilliseconds: Int64, monotonicSeconds: Double
        /// Fixed numeric schema only. No source URLs, names, command bodies or stderr.
        var numbers: [String: Double] = [:]
        var reason: String = "none"
    }
    private static let allowedNumbers: Set<String> = [
        "request_bytes", "actual_bytes", "deadline_s", "elapsed_s", "samples",
        "supporters", "x", "y", "w", "h", "source_aspect", "target_aspect",
        "observed_aspect", "tolerance", "ack", "gate", "observed", "matched",
        "target_x", "target_y", "target_w", "target_h", "observed_x", "observed_y", "observed_w", "observed_h"
    ]
    private(set) var emitted = 0
    private(set) var bytes = 0
    static let maxRows = 2048
    static let maxBytes = 1048576
    static let maxLineBytes = 2048

    mutating func encode(_ event: Event, identity: Identity) -> Data? {
        guard emitted < Self.maxRows, event.monotonicSeconds.isFinite,
              event.monotonicSeconds >= 0, identity.window > 0,
              !identity.player.isEmpty else { return nil }
        // Never permit an ACK or a target to masquerade as physical success.
        let expected = event.numbers["target_aspect"] ?? 0
        let actual = event.numbers["observed_aspect"] ?? 0
        let tolerance = event.numbers["tolerance"] ?? 0
        let frameMatches = ["x", "y", "w", "h"].allSatisfy { axis in
            guard let a = event.numbers["target_" + axis],
                  let b = event.numbers["observed_" + axis], a.isFinite, b.isFinite else { return false }
            if axis == "w" || axis == "h" { guard a > 0, b > 0 else { return false } }
            return abs(a - b) <= 1.5
        }
        let landed = event.stage == .landing && frameMatches
            && event.numbers["observed"] == 1
            && expected.isFinite && actual.isFinite && expected > 0 && actual > 0
            && tolerance.isFinite && tolerance > 0 && tolerance <= 0.01
            && abs(actual / expected - 1) <= tolerance
        var row: [String: Any] = [
            "kind": "crop-fit-v1", "player": String(identity.player.prefix(64)),
            "window": identity.window, "load": String(identity.load),
            "scan": String(identity.scan), "stage": event.stage.rawValue,
            "utc_ms": event.utcMilliseconds, "mono_s": event.monotonicSeconds,
            "reason": String(event.reason.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.prefix(64)),
            "physical_fit": landed ? "observed_match" : "unproven"
        ]
        for (key, value) in event.numbers where Self.allowedNumbers.contains(key) && value.isFinite {
            row[key] = value
        }
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              data.count + 1 <= Self.maxLineBytes,
              bytes + data.count + 1 <= Self.maxBytes else { return nil }
        data.append(0x0A)
        emitted += 1; bytes += data.count
        return data
    }
}
