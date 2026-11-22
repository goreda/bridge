
var failures: [String] = []
func check(_ name: String, _ cond: Bool) { if !cond { failures.append(name); print("FAIL:", name) } }
typealias R = (Double, Double)
func usableAll(_ ps: [Double], _ ranges: [R]) -> Bool {
    ps.allSatisfy { p in ranges.contains { p >= $0.0 && p <= $0.1 - WTCropSamples.tailMargin } }
}

// ── A. plan: frontier anchoring ──────────────────────────────────────────────
let r1: [R] = [(0.0, 100.0)]
let p = WTCropSamples.plan(ranges: r1, playhead: 50.0, manual: false, widenLevel: 0)
let f = 100.0 - WTCropSamples.tailMargin
check("frontier window upper bound", (p.max() ?? 0) <= f + 1e-9)
check("frontier window lower bound", (p.min() ?? 0) >= f - 24.0 - 1e-9)
check("frontier newest-first seed", abs((p.first ?? 0) - f) == p.map { abs($0 - f) }.min()!)
check("frontier count", p.count == 12 && p.count <= WTCropSamples.sampleCount)
check("frontier ignores playhead", WTCropSamples.plan(ranges: r1, playhead: 50.0, manual: false) == WTCropSamples.plan(ranges: r1, playhead: 0.0, manual: false))
check("no-playhead same plan", WTCropSamples.plan(ranges: r1, playhead: nil, manual: false) == p)
let p1 = WTCropSamples.plan(ranges: r1, playhead: 50.0, manual: false, widenLevel: 1)
check("widen1 reaches backwards only", (p1.min() ?? 0) >= f - 48.0 - 1e-9 && (p1.max() ?? 0) <= f + 1e-9 && (p1.min() ?? 0) < (p.min() ?? 0))

// unsorted / overlapping / hole ranges: every sample inside a usable segment
let messy: [R] = [(90.0, 200.0), (0.0, 40.0), (150.0, 260.0), (10.0, 20.0)]
let pm = WTCropSamples.plan(ranges: messy, playhead: 5.0, manual: false)
check("messy membership", usableAll(pm, messy))
check("messy anchored at max end", (pm.min() ?? 0) > 198.5 && (pm.max() ?? 0) <= 258.5 + 1e-9)
check("messy count", pm.count == 12)

// eviction / frontier retreat: replan reflects actual current ranges
let before = WTCropSamples.plan(ranges: [(0.0, 200.0)], playhead: 100.0, manual: false)
let afterEvict = WTCropSamples.plan(ranges: [(0.0, 60.0)], playhead: 100.0, manual: false)
check("eviction replan", (afterEvict.max() ?? 0) <= 58.5 + 1e-9 && (before.max() ?? 0) > (afterEvict.max() ?? 0))

// nonfinite / reversed / empty / short-tail inputs
check("nonfinite range dropped", WTCropSamples.plan(ranges: [(0.0, Double.nan), (0.0, 50.0)], playhead: nil, manual: false).count == 12)
check("reversed range dropped", WTCropSamples.plan(ranges: [(50.0, 10.0), (0.0, 50.0)], playhead: nil, manual: false).count == 12)
check("empty ranges empty plan", WTCropSamples.plan(ranges: [], playhead: 10.0, manual: false).isEmpty)
check("short range below minRange unusable", WTCropSamples.plan(ranges: [(0.0, 2.0)], playhead: nil, manual: false).isEmpty)
let shortTail = WTCropSamples.plan(ranges: [(0.0, 3.5)], playhead: nil, manual: false)
check("short usable tail keeps margin", shortTail.allSatisfy { $0 <= 3.5 - WTCropSamples.tailMargin + 1e-9 })

// manual parity: pre/post-patch outputs identical
let grids: [([R], Double?)] = [
    ([(0.0, 126.0)], 124.4), ([(0.0, 30.0)], 20.1), ([(0.0, 5.0)], 0.0),
    ([(0.0, 60.0), (80.0, 200.0)], 150.0), ([(10.0, 50.0)], 100.0), ([(0.0, 500.0)], nil),
]
for (g, ph) in grids {
    for w in [0, 1, 3] {
        check("manual parity \(g) w\(w)", WTCropSamples.plan(ranges: g, playhead: ph, manual: true, widenLevel: w) == WTCropSamplesPrepatch.o_plan(ranges: g, playhead: ph, manual: true, widenLevel: w))
    }
}

// ── B. classifier + widen policy (r3/r4: disagreement also resets) ──────────
check("0 members starved", scanStarved(membersCount: 0, sampled: 5, needSamples: 3))
check("2 members starved", scanStarved(membersCount: 2, sampled: 8, needSamples: 3))
check("3 disagreeing not starved", !scanStarved(membersCount: 3, sampled: 12, needSamples: 3))
check("12 disagreeing not starved", !scanStarved(membersCount: 12, sampled: 12, needSamples: 3))
check("no samples starved", scanStarved(membersCount: 0, sampled: 1, needSamples: 3))
check("disagreement holds level 0", widenNextLevel(0, decisive: false, starved: false) == 0)
check("disagreement resets level 7 to narrow frontier", widenNextLevel(7, decisive: false, starved: false) == 0)
check("starvation grows", widenNextLevel(0, decisive: false, starved: true) == 1)
check("decisive resets", widenNextLevel(9, decisive: true, starved: false) == 0)
check("decisive resets even if starved", widenNextLevel(9, decisive: true, starved: true) == 0)
check("plan-unavailable resets to frontier", widenNextLevel(0, decisive: false, starved: false) == 0)

// ── C. carry rules (actual r3/r4 statics) + consensus with measured geometry ─
let planA = WTCropSamples.plan(ranges: [(0.0, 40.0)], playhead: nil, manual: false)
let planB = WTCropSamples.plan(ranges: [(0.0, 41.0)], playhead: nil, manual: false)
check("same exact plan resume kept", SourcePixelCropScanner_carryPlanReusable(undelivered: false, planned: planA, plan: planA))
check("moved-frontier plan dropped", !SourcePixelCropScanner_carryPlanReusable(undelivered: false, planned: planA, plan: planB))
check("frontier-retreat plan dropped", !SourcePixelCropScanner_carryPlanReusable(undelivered: false, planned: planA, plan: WTCropSamples.plan(ranges: [(0.0, 30.0)], playhead: nil, manual: false)))
check("undelivered decisive exempt across plans", SourcePixelCropScanner_carryPlanReusable(undelivered: true, planned: planA, plan: planB))
check("same-end seek resume kept (plan identical)", SourcePixelCropScanner_carryPlanReusable(undelivered: false, planned: planA, plan: WTCropSamples.plan(ranges: [(0.0, 40.0)], playhead: 33.0, manual: false)))
check("completed disagreement clears progress", SourcePixelCropScanner_progressClearedOnCompletion(decisive: false, carryUndelivered: false))
check("completed decisive does not clear", !SourcePixelCropScanner_progressClearedOnCompletion(decisive: true, carryUndelivered: false))
check("decisive undelivered survives completion", !SourcePixelCropScanner_progressClearedOnCompletion(decisive: false, carryUndelivered: true))
let INTRO = SourcePixelBounds.Bounds(x0: 0, y0: 531, x1: 3840, y1: 1658)   // measured intro geometry, owner log
let FILM  = SourcePixelBounds.Bounds(x0: 0, y0: 276, x1: 3840, y1: 1885)   // measured film geometry (= manual decisive rect)
let poisoned = (Array(repeating: INTRO, count: 9) + Array(repeating: FILM, count: 3))
check("RED: carried intro members veto consensus", SourcePixelBounds.consistent(poisoned) == nil)
check("3 fresh agreeing frames converge", SourcePixelBounds.consistent(Array(repeating: FILM, count: 3)) != nil)
check("12 fresh agreeing frames converge", SourcePixelBounds.consistent(Array(repeating: FILM, count: 12)) != nil)

// ── D. r4 dispatch-frontier identity + ACTUAL growth condition (negative control) ──
// Ops bounded execution 2026-11-22 measured plan max 21.5625 for cache [0,24]; cross-check the extraction.
let opsPlan = WTCropSamples.plan(ranges: [(0.0, 24.0)], playhead: nil, manual: false)
check("Ops actual plan max cross-check", abs((opsPlan.max() ?? 0) - 21.5625) < 1e-9)
let rawFE = WTCropSamples.rawFrontierEnd([(0.0, 24.0)])
check("dispatch identity is raw frontier", rawFE == 24.0)
check("coordinate gap exceeds +2 rule margin", (rawFE ?? 0) - (opsPlan.max() ?? 0) > 2)
// The ACTUAL production condition, unchanged-cache negative control: must be false.
check("unchanged cache no immediate redrive", !PPController_cropSearchGrowthRestarts(frontierEnd: 24.0, scannedEnd: rawFE!))
check("growth +1.5 below rule", !PPController_cropSearchGrowthRestarts(frontierEnd: 25.5, scannedEnd: rawFE!))
check("growth +3 redrives exactly once", PPController_cropSearchGrowthRestarts(frontierEnd: 27.0, scannedEnd: rawFE!))
let reFE = WTCropSamples.rawFrontierEnd([(0.0, 27.0)])!
check("after redispatch unchanged no redrive", !PPController_cropSearchGrowthRestarts(frontierEnd: 27.0, scannedEnd: reFE))
check("rawFrontierEnd ignores nonfinite", WTCropSamples.rawFrontierEnd([(0.0, Double.nan), (0.0, 50.0)]) == 50.0)
check("rawFrontierEnd empty is nil", WTCropSamples.rawFrontierEnd([]) == nil)

// ── E. r5 coverage-proof gate (actual extracted CropDetector static) ─────────
check("3 distinct finite prove coverage", CropDetector_planProvesCoverage([1.0, 2.0, 3.0]))
check("2 distinct do not", !CropDetector_planProvesCoverage([1.0, 2.0]))
check("12 same-position do not", !CropDetector_planProvesCoverage(Array(repeating: 7.5, count: 12)))
check("nan excluded from proof", !CropDetector_planProvesCoverage([Double.nan, 1.0, 2.0]))
check("nan among 3 finite rejects (allSatisfy, not filter)", !CropDetector_planProvesCoverage([1.0, 2.0, 3.0, Double.nan]))
check("negative position rejects", !CropDetector_planProvesCoverage([-1.0, 2.0, 3.0]))
check("zero origin positions admissible", CropDetector_planProvesCoverage([0.0, 1.0, 2.0]))
check("empty plan no coverage", !CropDetector_planProvesCoverage([]))

// ── Mutants (Ops: apply each, rebuild, expect at least one FAIL) ─────────────
// M1 playhead-anchored window reintroduced        -> breaks "frontier ignores playhead", "frontier window lower bound"
// M2 widen on disagreement (starved check removed)-> breaks "disagreement holds level 0"
// M3 last-listed end instead of max end           -> breaks "messy anchored at max end"
// M4 starved always true at no-agreement site     -> breaks "3 disagreeing not starved"
// M5 carry plan binding removed (c0 always reused)-> breaks "moved-frontier plan dropped"
// M6 midpoint booking (scannedEnd = plan max)     -> breaks "unchanged cache no immediate redrive" (the actual r3 defect)
// M7 check-before-lock race (r4 defect)           -> covered by the mirror interleaving negative control; the Swift
//    interleaving itself is async and out of bounded-harness scope (locked compare-and-write is in the product diff)
// M8 filter-finite coverage gate (pre-alignment)  -> breaks "nan among 3 finite rejects (allSatisfy, not filter)"
//    and "negative position rejects"; the gate must match scanner admission exactly

if failures.isEmpty { print("ALL PASS (extracted Swift, actual r5 bodies; bounded pure helpers, not PP async acceptance)") } else { print("\(failures.count) FAILURES: \(failures)"); exit(1) }
