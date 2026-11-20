# W-gdb-199au-in2tinct-02 - HLSCacheBudget validated construction, effective caps and exact prepare-time admission arithmetic
state: OPEN / unclaimed
lab: in2tinct
row: GORAV-CACHE-PARITY (A2)

Patch + tests authored by gdb (Ops, leg A) under arch-199au item 6; in2tinct verifies and ingests per the leg/lab rules. Real production change plus semantic Linux tests, both executed against the pin before publication (run proof below). Support-only: no native/UI/playback/Darwin claims, no gorav main ref change, no paid CI; integration lands on the target lane branch only after lab verification and integrator review.

PROBLEM. HLSCacheBudget accepted any values: zero/negative caps that refuse every fetch, and a whole-resource timeout shorter than the per-request timeout that aborts every transfer. The prepare-time total-budget guard existed only inline in HLSVODSource.prepare, untestable in isolation and free to drift from the pinned budget.

DECISION. Add HLSCacheBudget.validated(...) (failable, same validated-value style as CacheTuningPolicy.init?), effective cap accessors mirroring prepare's min(total, cap), and admitsNextSegment(initSegmentBytes:segmentBytes:fetchedSoFarBytes:) reproducing the exact per-segment guard arithmetic (initial <= total - fetched && bytes <= total - fetched - initial; init bytes join every segment). goravPinned now goes through validated. The memberwise init stays for source compatibility.

Scope boundaries: this packet touches only the listed files. It does not touch the returned/conflicting paths ABLoopPolicy.swift, SubtitleSelectionPolicy.swift, ASSParser.swift or the CacheAccounting.swift chain, and does not re-open their rows. No generic tooling, no label-only work, no fabricated evidence: every check below ran on this exact patch against the exact pin.

Repo goreda/gorav main pin 087c15cc068daf1e74112d436e63f07b3d254be4. Test toolchain: official Swift 6.2.3 (ubuntu22.04) on PATH, -swift-version 6 strict concurrency. Return full files on target branch lane/199au/hls-cache-budget-validation; the patch against the pin is derivable from the inline sources. Keep .build out of git.

```packet-json
{
  "packet_id": "W-gdb-199au-in2tinct-02",
  "lab": "in2tinct",
  "writer": "gdb",
  "code_owner": "gdb (Ops leg A) authored the patch and tests; goreda owns the gorav trunk integration decision; in2tinct verifies and ingests the listed files only",
  "product_repo": "goreda/gorav",
  "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "HLSCacheBudget.validated(playlistCapBytes:initSegmentCapBytes:segmentCapBytes:totalBudgetBytes:requestTimeoutSecs:resourceTimeoutSecs:sharedURLCacheDisabled:) -> HLSCacheBudget?; effectiveInitSegmentCapBytes/effectiveSegmentCapBytes: Int; admitsNextSegment(initSegmentBytes:segmentBytes:fetchedSoFarBytes:) -> Bool",
    "types": "HLSCacheBudget (additive only; memberwise init preserved)",
    "ownership_lifetime": "Owned production path Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift only.",
    "caller": "HLSVODSource.prepare(...) (Sources/GorAVPlaybackCore/HLSVODSource.swift:35) is the modeled call site; this packet wires nothing.",
    "callee": "Pure arithmetic over the budget fields; no fetch/URLSession coupling."
  },
  "scope": "product",
  "test": {
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au02 Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift kits/199au/in2tinct-02/main.swift && /tmp/wgdb199au02",
    "expected": "exit 0; log ends 'SEMANTIC_PASS W-gdb-199au-in2tinct-02 17 checks'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/199au/hls-cache-budget-validation",
    "paths": [
      "Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift",
      "kits/199au/in2tinct-02/main.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift",
        "block": "source1"
      },
      {
        "path": "kits/199au/in2tinct-02/main.swift",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au02 Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift kits/199au/in2tinct-02/main.swift && /tmp/wgdb199au02",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-20T20:39:42.368230+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEMANTIC_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift",
        "block": "source1",
        "sha256": "db6ff9f13769f0d386b2d5a023d7f8c3757fb9b4cb49ee4bbf1d95f5d60a5616"
      },
      {
        "path": "kits/199au/in2tinct-02/main.swift",
        "block": "fixtures1",
        "sha256": "340e562e4ec2753c04c0a9452416592c626d327faaf788454ff1385266b2a8d2"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "2f030faa11265e5f2451a43c187821529e55ea241a4bc86f993c5d68b3b55926",
    "last_5_lines": [
      "PASS A7 zero-byte segment and zero-byte init admit (no-op fetch)",
      "PASS D1 joined init-per-segment accumulation matches the guard",
      "PASS D2 a fourth 12 MiB joined part still fits",
      "PASS D3 exact fill at the budget admits, one more MiB refuses",
      "SEMANTIC_PASS W-gdb-199au-in2tinct-02 17 checks"
    ],
    "receipt_sha256": "ae52cfa655e0c6bca47b44fbc006884979fe2409e67370ca8b5e6a4424635d97"
  }
}
```

```swift id=source1
// HLSCacheBudget: gorav's pinned HLS VOD preparation budget (SUPPORT only).
// Row: GORAV-CACHE-PARITY. HLS in gorav is a download-then-open-local model:
// HLSVODSource.prepare fetches whole segments into a caller-owned private
// directory and the decoder opens the prepared files as LOCAL sources, so
// the mpv-shaped CacheTuningPolicy for .hlsVOD stays at the launch baseline
// (the decode open is a local open) and HLS's per-source cache substance
// lives HERE, at prepare time, in these budget constants.
// Every value is GOR-PINNED from gorav main c1431906
// Sources/GorAVPlaybackCore/HLSVODSource.swift: playlist fetch cap 1 MiB
// (:45 master, :55 variant), init-segment cap min(total, 4 MiB) (:76),
// segment cap min(total, 16 MiB) (:80), total budget default 64 MiB (:37),
// request timeout 10 s / resource timeout 20 s (:108), URLSession cache and
// cookie storage explicitly disabled (:109). Immutable value; no I/O here.
import Foundation

public struct HLSCacheBudget: Equatable, Sendable {
    /// Cap on each playlist fetch (master and chosen variant), bytes.
    public let playlistCapBytes: Int
    /// Cap on the init segment (#EXT-X-MAP), bytes, before the total budget.
    public let initSegmentCapBytes: Int
    /// Cap on each media segment fetch, bytes, before the total budget.
    public let segmentCapBytes: Int
    /// Default total byte budget across all fetched parts.
    public let totalBudgetBytes: Int
    /// URLSession per-request timeout, seconds.
    public let requestTimeoutSecs: Double
    /// URLSession whole-resource timeout, seconds.
    public let resourceTimeoutSecs: Double
    /// gorav pins URLSessionConfiguration.urlCache = nil for these fetches:
    /// no shared HTTP cache participates in HLS preparation.
    public let sharedURLCacheDisabled: Bool

    public init(playlistCapBytes: Int, initSegmentCapBytes: Int, segmentCapBytes: Int,
                totalBudgetBytes: Int, requestTimeoutSecs: Double, resourceTimeoutSecs: Double,
                sharedURLCacheDisabled: Bool) {
        self.playlistCapBytes = playlistCapBytes
        self.initSegmentCapBytes = initSegmentCapBytes
        self.segmentCapBytes = segmentCapBytes
        self.totalBudgetBytes = totalBudgetBytes
        self.requestTimeoutSecs = requestTimeoutSecs
        self.resourceTimeoutSecs = resourceTimeoutSecs
        self.sharedURLCacheDisabled = sharedURLCacheDisabled
    }

    /// Validated construction (199au, W-gdb-199au-in2tinct-02). The memberwise
    /// init accepts anything, including budgets that cannot work at prepare
    /// time; this constructor refuses them typed (nil), matching the
    /// module's validated-value style (CacheTuningPolicy.init?). Checked
    /// invariants, each a real misconfiguration class:
    ///  - every byte cap and the total budget must be positive (a zero cap
    ///    refuses every fetch; a negative one is meaningless);
    ///  - both timeouts must be finite and positive;
    ///  - resourceTimeoutSecs must be at least requestTimeoutSecs (a
    ///    whole-resource timeout shorter than the per-request timeout aborts
    ///    every fetch that legitimately runs longer than the resource limit).
    /// A part cap ABOVE the total budget is NOT refused: prepare applies
    /// min(total, cap) per fetch (HLSVODSource.swift:76/:80), so the
    /// effective cap is well-defined; see effectiveSegmentCapBytes.
    public static func validated(playlistCapBytes: Int, initSegmentCapBytes: Int,
                                 segmentCapBytes: Int, totalBudgetBytes: Int,
                                 requestTimeoutSecs: Double, resourceTimeoutSecs: Double,
                                 sharedURLCacheDisabled: Bool) -> HLSCacheBudget? {
        guard playlistCapBytes > 0, initSegmentCapBytes > 0, segmentCapBytes > 0,
              totalBudgetBytes > 0 else { return nil }
        guard requestTimeoutSecs.isFinite, requestTimeoutSecs > 0,
              resourceTimeoutSecs.isFinite, resourceTimeoutSecs > 0 else { return nil }
        guard resourceTimeoutSecs >= requestTimeoutSecs else { return nil }
        return HLSCacheBudget(playlistCapBytes: playlistCapBytes,
                              initSegmentCapBytes: initSegmentCapBytes,
                              segmentCapBytes: segmentCapBytes,
                              totalBudgetBytes: totalBudgetBytes,
                              requestTimeoutSecs: requestTimeoutSecs,
                              resourceTimeoutSecs: resourceTimeoutSecs,
                              sharedURLCacheDisabled: sharedURLCacheDisabled)
    }

    /// The init-segment cap prepare actually applies: min(total, cap)
    /// (HLSVODSource.swift:76).
    public var effectiveInitSegmentCapBytes: Int { min(totalBudgetBytes, initSegmentCapBytes) }
    /// The per-segment cap prepare actually applies: min(total, cap)
    /// (HLSVODSource.swift:80).
    public var effectiveSegmentCapBytes: Int { min(totalBudgetBytes, segmentCapBytes) }

    /// The exact total-budget admission rule prepare enforces per segment
    /// (HLSVODSource.swift, the guard before each segment write):
    ///     initial.count <= maxTotalBytes - total
    ///     && bytes.count  <= maxTotalBytes - total - initial.count
    /// with the init segment joined in front of EVERY segment and
    /// total += initial.count + bytes.count after each admitted segment.
    /// Negative inputs and an already-over-budget fetchedSoFarBytes are not
    /// admissible. Pure arithmetic; no I/O, no fetch decisions beyond the
    /// byte budget (caps and cancellation stay with the fetch layer).
    public func admitsNextSegment(initSegmentBytes: Int, segmentBytes: Int,
                                  fetchedSoFarBytes: Int) -> Bool {
        guard initSegmentBytes >= 0, segmentBytes >= 0,
              fetchedSoFarBytes >= 0, fetchedSoFarBytes <= totalBudgetBytes else { return false }
        return initSegmentBytes <= totalBudgetBytes - fetchedSoFarBytes
            && segmentBytes <= totalBudgetBytes - fetchedSoFarBytes - initSegmentBytes
    }

    /// The exact constants HLSVODSource.prepare ships with today (citations
    /// in the file header). Pinned so a drift in the source constants fails
    /// a test instead of silently changing the cache behaviour.
    /// The pin goes through validated(...) (199au, W-gdb-199au-in2tinct-02):
    /// the pins satisfy every invariant, so the force unwrap cannot trap;
    /// a future pin edit that breaks an invariant fails here loudly instead
    /// of shipping a budget that refuses every fetch.
    public static let goravPinned = HLSCacheBudget.validated(
        playlistCapBytes: 1 * 1024 * 1024,
        initSegmentCapBytes: 4 * 1024 * 1024,
        segmentCapBytes: 16 * 1024 * 1024,
        totalBudgetBytes: 64 * 1024 * 1024,
        requestTimeoutSecs: 10,
        resourceTimeoutSecs: 20,
        sharedURLCacheDisabled: true)!
}
```

```swift id=fixtures1
import Foundation

// W-gdb-199au-in2tinct-02 semantic tests for HLSCacheBudget validated
// construction, effective caps and the prepare-time admission arithmetic.
// Compiles against the PATCHED production file
// Sources/GorAVPlaybackCore/CacheParity/HLSCacheBudget.swift (same module,
// no source-copy stage). Exit 0 only when every check passes.

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " " + info))
    if !ok { failures += 1 }
}

let M = 1024 * 1024
func budget(playlist: Int = 1 * M, initSeg: Int = 4 * M, segment: Int = 16 * M,
            total: Int = 64 * M, req: Double = 10, res: Double = 20) -> HLSCacheBudget? {
    HLSCacheBudget.validated(playlistCapBytes: playlist, initSegmentCapBytes: initSeg,
                             segmentCapBytes: segment, totalBudgetBytes: total,
                             requestTimeoutSecs: req, resourceTimeoutSecs: res,
                             sharedURLCacheDisabled: true)
}

// V-series: validated construction
check("V1 zero and negative caps refuse",
      budget(playlist: 0) == nil && budget(initSeg: 0) == nil
      && budget(segment: -1) == nil && budget(total: 0) == nil)
check("V2 non-finite and non-positive timeouts refuse",
      budget(req: .nan) == nil && budget(req: 0) == nil
      && budget(res: .infinity) == nil && budget(res: -5) == nil)
check("V3 resource timeout below request timeout refuses", budget(req: 20, res: 10) == nil)
check("V4 equal timeouts admit", budget(req: 10, res: 10) != nil)
check("V5 the gorav pin passes validation and keeps its exact values",
      HLSCacheBudget.goravPinned.playlistCapBytes == 1 * M
      && HLSCacheBudget.goravPinned.initSegmentCapBytes == 4 * M
      && HLSCacheBudget.goravPinned.segmentCapBytes == 16 * M
      && HLSCacheBudget.goravPinned.totalBudgetBytes == 64 * M
      && HLSCacheBudget.goravPinned.requestTimeoutSecs == 10
      && HLSCacheBudget.goravPinned.resourceTimeoutSecs == 20
      && HLSCacheBudget.goravPinned.sharedURLCacheDisabled)

// E-series: effective caps mirror prepare's min(total, cap)
let shrunk = budget(initSeg: 4 * M, segment: 16 * M, total: 2 * M)!
check("E1 caps above the total budget are not refused (min semantics)", shrunk.totalBudgetBytes == 2 * M)
check("E2 effective segment cap is min(total, cap)", shrunk.effectiveSegmentCapBytes == 2 * M)
check("E3 effective init cap is min(total, cap)", shrunk.effectiveInitSegmentCapBytes == 2 * M)
check("E4 effective caps equal the caps when below the budget",
      HLSCacheBudget.goravPinned.effectiveSegmentCapBytes == 16 * M
      && HLSCacheBudget.goravPinned.effectiveInitSegmentCapBytes == 4 * M)

// A-series: admission arithmetic, the exact prepare guard
//   initial <= total - fetched && bytes <= total - fetched - initial
let b = HLSCacheBudget.goravPinned
check("A1 first segment with init fits", b.admitsNextSegment(initSegmentBytes: 3 * M, segmentBytes: 10 * M, fetchedSoFarBytes: 0))
check("A2 exact fit admits", b.admitsNextSegment(initSegmentBytes: 4 * M, segmentBytes: 60 * M, fetchedSoFarBytes: 0))
check("A3 one byte over refuses", !b.admitsNextSegment(initSegmentBytes: 4 * M, segmentBytes: 60 * M + 1, fetchedSoFarBytes: 0))
check("A4 running total is enforced", !b.admitsNextSegment(initSegmentBytes: 4 * M, segmentBytes: 20 * M, fetchedSoFarBytes: 44 * M)
      && b.admitsNextSegment(initSegmentBytes: 4 * M, segmentBytes: 16 * M, fetchedSoFarBytes: 44 * M))
check("A5 init segment alone over the remaining budget refuses",
      !b.admitsNextSegment(initSegmentBytes: 5 * M, segmentBytes: 0, fetchedSoFarBytes: 60 * M))
check("A6 negative and over-budget inputs are not admissible",
      !b.admitsNextSegment(initSegmentBytes: -1, segmentBytes: 1, fetchedSoFarBytes: 0)
      && !b.admitsNextSegment(initSegmentBytes: 0, segmentBytes: 1, fetchedSoFarBytes: 65 * M))
check("A7 zero-byte segment and zero-byte init admit (no-op fetch)",
      b.admitsNextSegment(initSegmentBytes: 0, segmentBytes: 0, fetchedSoFarBytes: 64 * M))

// D-series: hand-computed drift pins against the prepare guard formula
// (HLSVODSource.swift): joined = init + bytes accumulates into total.
do {
    var total = 0
    let initB = 2 * M, segments = [10 * M, 10 * M, 10 * M]
    var admitted = 0
    for s in segments {
        if b.admitsNextSegment(initSegmentBytes: initB, segmentBytes: s, fetchedSoFarBytes: total) {
            total += initB + s; admitted += 1
        }
    }
    // 3 x (2+10) MiB = 36 MiB <= 64 MiB; a fourth joined part needs 12 of the
    // remaining 28 MiB and admits; at 48 MiB fetched, init 2 + segment 14
    // exactly fills 64 MiB (admits) while 15 MiB segment refuses.
    check("D1 joined init-per-segment accumulation matches the guard", admitted == 3 && total == 36 * M)
    check("D2 a fourth 12 MiB joined part still fits", b.admitsNextSegment(initSegmentBytes: initB, segmentBytes: 10 * M, fetchedSoFarBytes: total))
    check("D3 exact fill at the budget admits, one more MiB refuses",
          b.admitsNextSegment(initSegmentBytes: initB, segmentBytes: 14 * M, fetchedSoFarBytes: 48 * M)
          && !b.admitsNextSegment(initSegmentBytes: initB, segmentBytes: 15 * M, fetchedSoFarBytes: 48 * M))
}

if failures == 0 {
    print("SEMANTIC_PASS W-gdb-199au-in2tinct-02 17 checks")
} else {
    print("SEMANTIC_FAIL W-gdb-199au-in2tinct-02 \(failures) failures")
    exit(1)
}
```

```text id=actual_run_log
PASS V1 zero and negative caps refuse
PASS V2 non-finite and non-positive timeouts refuse
PASS V3 resource timeout below request timeout refuses
PASS V4 equal timeouts admit
PASS V5 the gorav pin passes validation and keeps its exact values
PASS E1 caps above the total budget are not refused (min semantics)
PASS E2 effective segment cap is min(total, cap)
PASS E3 effective init cap is min(total, cap)
PASS E4 effective caps equal the caps when below the budget
PASS A1 first segment with init fits
PASS A2 exact fit admits
PASS A3 one byte over refuses
PASS A4 running total is enforced
PASS A5 init segment alone over the remaining budget refuses
PASS A6 negative and over-budget inputs are not admissible
PASS A7 zero-byte segment and zero-byte init admit (no-op fetch)
PASS D1 joined init-per-segment accumulation matches the guard
PASS D2 a fourth 12 MiB joined part still fits
PASS D3 exact fill at the budget admits, one more MiB refuses
SEMANTIC_PASS W-gdb-199au-in2tinct-02 17 checks
```
