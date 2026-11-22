import Foundation

// stereo-transport-tests: B5 metadata transport r2 + P30 stage adapter
// (additive on the qualified v4 composition). Same harness style as the
// qualified stereo-look-tests: plain checks, exit 1 on any failure.
// Covers: context-bound admission (stale-callback refusal), epoch
// monotonicity, validated atomic rebind, replace/cancel semantics,
// explicit-source validation, unbound refusals, feed passthrough,
// adapter epoch ownership, full-identity frame binding, typed
// stale-refusal, invalidation/reset, gate/refusal atomicity.
// T32-T34 replay the Z4C independent boundary adversary (evidence
// 096ac943) against the repaired contract. T37-T41 cover the B6
// FFmpeg side-data map (KNOWN/UNKNOWN mapping, eye-order no-guessing
// asymmetry, spherical projection, transport end-to-end); T42-T47
// cover the P31 stage submission (install/invalidation lifecycle,
// admitted-frame binding, gate clearing, revision freshness).

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

let sel = StereoSelectedStream(track: 1, stream: nil)
let ctx = StereoMetadataBindingContext(sourceID: "src", sourceGeneration: 7, presentationEpoch: 1,
                                       selection: sel)

// T20: presentation-epoch advance clears ONLY the temporal codec slot.
do {
    let t = StereoStreamMetadataTransport()
    var track = StereoStreamMetadata()
    track.layout = StereoStreamFieldMetadata(observations: [
        SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 2, format: 1)])
    try t.rebindSource(to: ctx, track: track)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    try t.applyCodecSEI(context: ctx, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
    try t.applyExplicit(context: ctx, source: 4, field: .projection,
                        observation: SpmetaFieldObs(kind: 2, norm: 0, raw: 9, source: 4, format: 2))
    check("T20.pre", t.observations(.layout).count == 3 && t.observations(.projection).count == 1)
    try t.advanceEpoch(context: ctx, to: 2)
    let layoutSources = t.observations(.layout).map { $0.source }.sorted()
    check("T20.codec-cleared", layoutSources == [1, 2])
    check("T20.nontemporal-persist", t.observations(.projection).count == 1
          && t.context?.presentationEpoch == 2)
} catch { check("T20.threw \(error)", false) }

// T21: re-advancing to the SAME epoch is a no-op (live SEI state kept).
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyCodecSEI(context: ctx, field: .eyeOrder,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 3, format: 3))
    try t.advanceEpoch(context: ctx, to: 1)
    check("T21.same-epoch-noop", t.observations(.eyeOrder).count == 1)
} catch { check("T21.threw \(error)", false) }

// T22: source rebind replaces ALL slot state with the fresh parse.
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    try t.applyCodecSEI(context: ctx, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
    let ctx2 = StereoMetadataBindingContext(sourceID: "src", sourceGeneration: 8, presentationEpoch: 0,
                                              selection: sel)
    var track2 = StereoStreamMetadata()
    track2.projection = StereoStreamFieldMetadata(observations: [
        SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 2, format: 1)])
    try t.rebindSource(to: ctx2, track: track2)
    check("T22.rebind-replaces", t.observations(.layout).isEmpty
          && t.observations(.projection).count == 1 && t.context == ctx2)
} catch { check("T22.threw \(error)", false) }

// T23: applyExplicit replace then cancel; other slots untouched.
do {
    let t = StereoStreamMetadataTransport()
    var track = StereoStreamMetadata()
    track.layout = StereoStreamFieldMetadata(observations: [
        SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 2, format: 1)])
    try t.rebindSource(to: ctx, track: track)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 1, format: 2))
    let after = t.observations(.layout)
    check("T23.replace", after.count == 2
          && after.contains { $0.source == 1 && $0.norm == 2 && $0.format == 2 })
    try t.applyExplicit(context: ctx, source: 1, field: .layout, observation: nil)
    let cleared = t.observations(.layout)
    check("T23.cancel", cleared.count == 1 && cleared.allSatisfy { $0.source == 2 })
} catch { check("T23.threw \(error)", false) }

// T24: applyExplicit validates typed BEFORE mutating; slot stays whole.
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    let before = t.observations(.layout)
    do {
        try t.applyExplicit(context: ctx, source: 2, field: .layout, observation: nil)
        check("T24.track-source-refused", false)
    } catch StereoMetadataTransportError.explicitSourceExpected(2) {
        check("T24.track-source-refused", t.observations(.layout) == before)
    }
    do {
        try t.applyExplicit(context: ctx, source: 3, field: .layout, observation: nil)
        check("T24.codec-source-refused", false)
    } catch StereoMetadataTransportError.explicitSourceExpected(3) {
        check("T24.codec-source-refused", t.observations(.layout) == before)
    }
    do {
        try t.applyExplicit(context: ctx, source: 1, field: .layout,
                            observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 4, format: 1))
        check("T24.source-mismatch", false)
    } catch StereoMetadataTransportError.sourceMismatch {
        check("T24.source-mismatch", t.observations(.layout) == before)
    }
    do {
        try t.applyExplicit(context: ctx, source: 1, field: .layout,
                            observation: SpmetaFieldObs(kind: 3, norm: 1, raw: 0, source: 1, format: 1))
        check("T24.bad-kind", false)
    } catch StereoMetadataTransportError.invalidOrdinal {
        check("T24.bad-kind", t.observations(.layout) == before)
    }
    do {
        try t.applyExplicit(context: ctx, source: 1, field: .layout,
                            observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 0))
        check("T24.bad-format", false)
    } catch StereoMetadataTransportError.invalidOrdinal {
        check("T24.bad-format", t.observations(.layout) == before)
    }
} catch { check("T24.threw \(error)", false) }

// T25: unbound transport refuses typed; reset on unbound is a safe no-op.
do {
    let t = StereoStreamMetadataTransport()
    do { _ = try t.feed(selection: sel); check("T25.feed-unbound", false) }
    catch StereoMetadataTransportError.unbound { check("T25.feed-unbound", true) }
    do { try t.advanceEpoch(context: ctx, to: 9); check("T25.epoch-unbound", false) }
    catch StereoMetadataTransportError.unbound { check("T25.epoch-unbound", true) }
    do {
        try t.applyCodecSEI(context: ctx, field: .layout,
                            observation: SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 3, format: 3))
        check("T25.sei-unbound", false)
    } catch StereoMetadataTransportError.unbound { check("T25.sei-unbound", true) }
    do {
        try t.applyExplicit(context: ctx, source: 1, field: .layout, observation: nil)
        check("T25.explicit-unbound", false)
    } catch StereoMetadataTransportError.unbound { check("T25.explicit-unbound", true) }
    t.reset()
    check("T25.reset-noop", t.context == nil)
} catch { check("T25.threw \(error)", false) }

// T26: feed defers to the qualified bridge: tier mapping, codec
// replace/cancel temporality, OVERRIDE verbatim passthrough.
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 1, format: 1))
    try t.applyCodecSEI(context: ctx, field: .eyeOrder,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 3, format: 3))
    try t.applyExplicit(context: ctx, source: 4, field: .projection,
                        observation: SpmetaFieldObs(kind: 2, norm: 0, raw: 9, source: 4, format: 2))
    let r1 = try t.feed(selection: sel)
    check("T26.tiers", r1.observations[.containerSideData]?.layout == .sideBySide
          && r1.observations[.codecSEI]?.eyeOrder == .leftFirst)
    check("T26.override-verbatim", r1.overrides.count == 1 && r1.overrides[0].raw == 9)
    // A later SEI REPLACES the codec observation (one slot per source).
    try t.applyCodecSEI(context: ctx, field: .eyeOrder,
                        observation: SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 3, format: 3))
    let r2 = try t.feed(selection: sel)
    check("T26.sei-replace", t.observations(.eyeOrder).count == 1
          && r2.observations[.codecSEI]?.eyeOrder == .rightFirst)
    // A cancel CLEARS it; the tier contributes nothing further.
    try t.applyCodecSEI(context: ctx, field: .eyeOrder, observation: nil)
    let r3 = try t.feed(selection: sel)
    check("T26.sei-cancel", t.observations(.eyeOrder).isEmpty
          && r3.observations[.codecSEI]?.eyeOrder == nil)
} catch { check("T26.threw \(error)", false) }

// T32: Z4C adversary replay - a delayed codec callback from source A
// after the rebind to B refuses typed .staleContext and mutates nothing.
do {
    let t = StereoStreamMetadataTransport()
    let a = StereoMetadataBindingContext(sourceID: "A", sourceGeneration: 1, presentationEpoch: 1,
                                       selection: sel)
    let b = StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2, presentationEpoch: 5,
                                       selection: sel)
    try t.rebindSource(to: a)
    try t.rebindSource(to: b)
    do {
        try t.applyCodecSEI(context: a, field: .layout,
                            observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
        check("T32.stale-callback-refused", false)
    } catch StereoMetadataTransportError.staleContext {
        check("T32.stale-callback-refused", t.context == b && t.observations(.layout).isEmpty)
    }
    // The current context's identical event admits.
    try t.applyCodecSEI(context: b, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
    check("T32.current-admits", t.observations(.layout).count == 1)
    // An epoch-older callback under the SAME source is equally stale.
    let bOlder = StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2, presentationEpoch: 4,
                                            selection: sel)
    do {
        try t.applyExplicit(context: bOlder, source: 1, field: .layout, observation: nil)
        check("T32.stale-explicit-refused", false)
    } catch StereoMetadataTransportError.staleContext {
        check("T32.stale-explicit-refused", t.observations(.layout).count == 1)
    }
} catch { check("T32.threw \(error)", false) }

// T33: Z4C adversary replay - epoch regression refuses typed, nothing
// mutates; a strictly greater advance then works.
do {
    let t = StereoStreamMetadataTransport()
    let b = StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2, presentationEpoch: 5,
                                       selection: sel)
    try t.rebindSource(to: b)
    try t.applyCodecSEI(context: b, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
    do {
        try t.advanceEpoch(context: b, to: 1)
        check("T33.regression-refused", false)
    } catch StereoMetadataTransportError.epochRegression(let current, let requested) {
        check("T33.regression-refused", current == 5 && requested == 1
              && t.context == b && t.observations(.layout).count == 1)
    }
    try t.advanceEpoch(context: b, to: 6)
    check("T33.forward-advance", t.context?.presentationEpoch == 6
          && t.observations(.layout).isEmpty)
    // An advance addressed to the PRE-advance context is now stale.
    do {
        try t.advanceEpoch(context: b, to: 7)
        check("T33.stale-advance-refused", false)
    } catch StereoMetadataTransportError.staleContext {
        check("T33.stale-advance-refused", t.context?.presentationEpoch == 6)
    }
} catch { check("T33.threw \(error)", false) }

// T34: Z4C adversary replay - an invalid rebind (empty sourceID, or
// hostile track ordinals) refuses typed; the PREVIOUS binding and its
// slots stay whole (validate-then-commit, never commit-then-reject).
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    let beforeCtx = t.context
    let beforeLayout = t.observations(.layout)
    var hostile = StereoStreamMetadata()
    hostile.layout = StereoStreamFieldMetadata(observations: [
        SpmetaFieldObs(kind: 7, norm: 0, raw: 0, source: 2, format: 1)])
    do {
        try t.rebindSource(to: StereoMetadataBindingContext(sourceID: "", sourceGeneration: 0,
                                                            presentationEpoch: 0, selection: sel),
                           track: hostile)
        check("T34.empty-rebind-refused", false)
    } catch StereoMetadataTransportError.emptySourceID {
        check("T34.empty-rebind-refused", t.context == beforeCtx
              && t.observations(.layout) == beforeLayout)
    }
    do {
        try t.rebindSource(to: StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2,
                                                            presentationEpoch: 0, selection: sel),
                           track: hostile)
        check("T34.hostile-track-refused", false)
    } catch StereoMetadataTransportError.invalidOrdinal {
        check("T34.hostile-track-refused", t.context == beforeCtx
              && t.observations(.layout) == beforeLayout)
    }
    var wrongSource = StereoStreamMetadata()
    wrongSource.layout = StereoStreamFieldMetadata(observations: [
        SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 1, format: 1)])
    do {
        try t.rebindSource(to: StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2,
                                                            presentationEpoch: 0, selection: sel),
                           track: wrongSource)
        check("T34.nontrack-refused", false)
    } catch StereoMetadataTransportError.trackSourceExpected(1) {
        check("T34.nontrack-refused", t.context == beforeCtx)
    }
    // A valid rebind still commits.
    try t.rebindSource(to: StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2,
                                                        presentationEpoch: 0, selection: sel))
    check("T34.valid-rebind-commits", t.context?.sourceID == "B" && t.observations(.layout).isEmpty)
} catch { check("T34.threw \(error)", false) }

// T35: a rebind with an empty selection (both identifiers absent)
// refuses typed; the previous binding and slots stay whole.
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyExplicit(context: ctx, source: 1, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: 1, format: 1))
    let beforeCtx = t.context
    let beforeLayout = t.observations(.layout)
    let empty = StereoMetadataBindingContext(sourceID: "B", sourceGeneration: 2, presentationEpoch: 0,
                                             selection: StereoSelectedStream(track: nil, stream: nil))
    do {
        try t.rebindSource(to: empty)
        check("T35.empty-selection-refused", false)
    } catch StereoMetadataTransportError.emptySelection {
        check("T35.empty-selection-refused", t.context == beforeCtx
              && t.observations(.layout) == beforeLayout)
    }
} catch { check("T35.threw \(error)", false) }

// T36: selection is bound - full exact equality at feed and mutation,
// nil-vs-0 included (Z4C adversary: same stored observations must never
// feed as a different track).
do {
    let t = StereoStreamMetadataTransport()
    try t.rebindSource(to: ctx)
    try t.applyCodecSEI(context: ctx, field: .layout,
                        observation: SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: 3, format: 3))
    // The bound selection feeds.
    let r1 = try t.feed(selection: sel)
    check("T36.bound-feeds", r1.observations[.codecSEI]?.layout == .topBottom)
    // A different track refuses typed; stored state is not relabelled.
    do {
        _ = try t.feed(selection: StereoSelectedStream(track: 2, stream: nil))
        check("T36.other-track-refused", false)
    } catch StereoMetadataTransportError.selectionMismatch {
        check("T36.other-track-refused", t.observations(.layout).count == 1)
    }
    // nil-vs-0 are different identifiers: stream 0 is not absent stream.
    do {
        _ = try t.feed(selection: StereoSelectedStream(track: 1, stream: 0))
        check("T36.nil-vs-zero-refused", false)
    } catch StereoMetadataTransportError.selectionMismatch {
        check("T36.nil-vs-zero-refused", true)
    }
    // A mutation under a context differing ONLY in selection is stale.
    let otherSel = StereoMetadataBindingContext(sourceID: "src", sourceGeneration: 7,
                                                presentationEpoch: 1,
                                                selection: StereoSelectedStream(track: 2, stream: nil))
    do {
        try t.applyCodecSEI(context: otherSel, field: .layout,
                            observation: SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 3, format: 3))
        check("T36.stale-selection-mutation", false)
    } catch StereoMetadataTransportError.staleContext {
        check("T36.stale-selection-mutation", t.observations(.layout).count == 1)
    }
    // A selection change is a validated rebind: fresh state, new feed.
    try t.rebindSource(to: otherSel)
    let r2 = try t.feed(selection: StereoSelectedStream(track: 2, stream: nil))
    check("T36.rebind-new-selection", t.observations(.layout).isEmpty
          && r2.observations.isEmpty && r2.overrides.isEmpty)
} catch { check("T36.threw \(error)", false) }

// Adapter tests. TestFrame carries several identity fields so the
// full-equality flow is exercised; the presenter binds the real
// FrameIdentity (full equality) in the concrete binding file.
struct AdapterTestFrame: Equatable {
    let session: String
    let generation: UInt64
    let sequence: UInt64
    let presentationEpoch: UInt64
}

func makeHost(enabled: Bool = true, yaw: Double = 0.25) -> StereoLookHostState {
    StereoLookHostState(
        session: StereoLookSession(enabled: enabled, toolsActive: false, layout: 3),
        controls: StereoLookControls(yaw: yaw),
        geometry: StereoLookGeometry(),
        tune: StereoLookTune())
}

// T27: pre-install frame and consume refuse typed, no implicit install.
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    do { _ = try adapter.frame(f, host: makeHost()); check("T27.frame-uninstalled", false) }
    catch StereoLookStageConsumeRefusal.uninstalled { check("T27.frame-uninstalled", true) }
    check("T27.no-implicit-install", adapter.installedEpoch == nil)
} catch { check("T27.threw \(error)", false) }

// T28: installed adapter answers frames; ANY single-field identity
// difference is a new frame (full-equality binding, never a projected
// key); host change produces at a new revision.
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let epoch = adapter.installStage()
    check("T28.epoch-minted", adapter.installedEpoch == 1 && epoch == 1)
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let host = makeHost()
    let (p1, o1) = try adapter.frame(f, host: host)
    guard case .produced(let rev1) = o1, let p1 else {
        check("T28.produced", false); throw NSError(domain: "t", code: 1)
    }
    check("T28.produced", p1.stageGeneration == epoch)
    let (p2, o2) = try adapter.frame(f, host: host)
    check("T28.replay-unchanged", p2 == nil && o2 == .unchanged)
    // One-field differences: new frame each time.
    let fSeq = AdapterTestFrame(session: "s", generation: 1, sequence: 2, presentationEpoch: 0)
    let (pSeq, oSeq) = try adapter.frame(fSeq, host: host)
    if case .produced = oSeq { check("T28.seq-differs", pSeq != nil) } else { check("T28.seq-differs", false) }
    let fEp = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 1)
    let (pEp, oEp) = try adapter.frame(fEp, host: host)
    if case .produced = oEp { check("T28.epoch-differs", pEp != nil) } else { check("T28.epoch-differs", false) }
    let fGen = AdapterTestFrame(session: "s", generation: 2, sequence: 1, presentationEpoch: 0)
    let (pGen, oGen) = try adapter.frame(fGen, host: host)
    if case .produced = oGen { check("T28.gen-differs", pGen != nil) } else { check("T28.gen-differs", false) }
    let (p3, o3) = try adapter.frame(f, host: makeHost(yaw: 0.5))
    guard case .produced(let rev3) = o3, p3 != nil else {
        check("T28.changed", false); throw NSError(domain: "t", code: 1)
    }
    check("T28.changed", rev3 != rev1)
} catch { check("T28.threw \(error)", false) }

// T29: consume compares admitted frame + installed epoch + exact
// revision, each refused typed BEFORE decode; refusals mutate nothing.
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let epoch = adapter.installStage()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let host = makeHost()
    let (p1, o1) = try adapter.frame(f, host: host)
    guard case .produced(let rev) = o1, let p1 else {
        check("T29.produced", false); throw NSError(domain: "t", code: 1)
    }
    let fOther = AdapterTestFrame(session: "s", generation: 1, sequence: 2, presentationEpoch: 0)
    do {
        _ = try adapter.consume(p1, admitted: fOther, installed: epoch, revision: rev)
        check("T29.stale-frame", false)
    } catch StereoLookStageConsumeRefusal.staleFrame { check("T29.stale-frame", true) }
    do {
        _ = try adapter.consume(p1, admitted: f, installed: epoch &+ 1, revision: rev)
        check("T29.stale-epoch", false)
    } catch StereoLookStageConsumeRefusal.staleStageEpoch { check("T29.stale-epoch", true) }
    do {
        _ = try adapter.consume(p1, admitted: f, installed: epoch,
                                revision: ParameterBlockRevision(rev.value &+ 1))
        check("T29.stale-revision", false)
    } catch StereoLookStageConsumeRefusal.staleRevision { check("T29.stale-revision", true) }
    // Refusals mutated nothing: the correct triple still consumes.
    let block = try adapter.consume(p1, admitted: f, installed: epoch, revision: rev)
    check("T29.consumed", block != nil && block?.revision == rev)
} catch { check("T29.threw \(error)", false) }

// T30: invalidation clears the installation and the accepted frame
// state; reinstall mints a fresh epoch; stale epochs refuse typed.
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let epoch1 = adapter.installStage()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let host = makeHost()
    let (p1, _) = try adapter.frame(f, host: host)
    guard let p1 else { check("T30.produced", false); throw NSError(domain: "t", code: 1) }
    adapter.invalidate(.streamChange)
    check("T30.invalidated", adapter.installedEpoch == nil)
    do {
        _ = try adapter.consume(p1, admitted: f, installed: epoch1,
                                revision: p1.revision)
        check("T30.consume-uninstalled", false)
    } catch StereoLookStageConsumeRefusal.uninstalled { check("T30.consume-uninstalled", true) }
    do { _ = try adapter.frame(f, host: host); check("T30.frame-uninstalled", false) }
    catch StereoLookStageConsumeRefusal.uninstalled { check("T30.frame-uninstalled", true) }
    let epoch2 = adapter.installStage()
    check("T30.fresh-epoch", epoch2 != epoch1)
    // Frame state was reset: the same frame+host produces again.
    let (p2, o2) = try adapter.frame(f, host: host)
    if case .produced = o2 { check("T30.reproduced", p2 != nil) } else { check("T30.reproduced", false) }
    if let p2 {
        do {
            _ = try adapter.consume(p2, admitted: f, installed: epoch1, revision: p2.revision)
            check("T30.old-epoch-stale", false)
        } catch StereoLookStageConsumeRefusal.staleStageEpoch { check("T30.old-epoch-stale", true) }
    }
    for cause in [StereoLookStageInvalidation.rebind, .retire, .surfaceChange, .sourceChange] {
        adapter.invalidate(cause)
    }
    check("T30.all-causes-reset", adapter.installedEpoch == nil)
} catch { check("T30.threw \(error)", false) }

// T31: gate and refusal semantics pass through the adapter unchanged
// (per-frame consistent .gated; typed producer refusal; accepted state
// untouched so a replay dedupes).
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    _ = adapter.installStage()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let host = makeHost()
    _ = try adapter.frame(f, host: host)
    let (g1, og1) = try adapter.frame(f, host: makeHost(enabled: false))
    check("T31.gated", g1 == nil && og1 == .gated)
    let (g2, og2) = try adapter.frame(f, host: makeHost(enabled: false))
    check("T31.gated-consistent", g2 == nil && og2 == .gated)
    var bad = makeHost()
    bad.session = StereoLookSession(enabled: true, toolsActive: false, layout: 3, pkConv: 1e308)
    do { _ = try adapter.frame(f, host: bad); check("T31.refusal-typed", false) }
    catch is StereoLookProducerError { check("T31.refusal-typed", true) }
    let (p6, o6) = try adapter.frame(f, host: host)
    check("T31.retry-dedupe", p6 == nil && o6 == .unchanged)
} catch { check("T31.threw \(error)", false) }

// T37: side-data map - every AVStereo3DType wire value with an spmeta
// ordinal maps KNOWN; source/format pass through verbatim; a
// non-inverted read emits NO eye-order observation (no guessing).
do {
    let cases: [(Int32, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 7), (6, 5), (7, 6)]
    for (wire, norm) in cases {
        let (layout, eye) = StereoSideDataMap.mapStereo3D(type: wire, inverted: false,
                                                          source: 2, format: 1)
        check("T37.type\(wire)", layout.kind == 1 && layout.norm == norm
              && layout.source == 2 && layout.format == 1 && eye == nil)
    }
} catch { check("T37.threw \(error)", false) }

// T38: quincunx (5) and unrecognized wire values are preserved verbatim
// as kind UNKNOWN, never folded into a known layout.
do {
    let unknownWires: [Int32] = [5, 8, 100, -1]
    for wire in unknownWires {
        let (layout, _) = StereoSideDataMap.mapStereo3D(type: wire, inverted: false,
                                                        source: 3, format: 3)
        check("T38.unknown\(wire)", layout.kind == 2
              && layout.raw == UInt32(bitPattern: wire)
              && layout.source == 3 && layout.format == 3)
    }
    // Inversion still carries an explicit eye order on an UNKNOWN layout.
    let (_, eye) = StereoSideDataMap.mapStereo3D(type: 5, inverted: true, source: 2, format: 2)
    check("T38.inverted-unknown", eye == SpmetaFieldObs(kind: 1, norm: 2, raw: 0,
                                                        source: 2, format: 2))
} catch { check("T38.threw \(error)", false) }

// T39: the eye-order asymmetry - explicit inverted maps RIGHT_FIRST;
// non-inverted emits nothing (FFmpeg normalization cannot distinguish
// explicit left-first from unspecified).
do {
    let (_, e1) = StereoSideDataMap.mapStereo3D(type: 1, inverted: true, source: 3, format: 3)
    let (_, e2) = StereoSideDataMap.mapStereo3D(type: 1, inverted: false, source: 3, format: 3)
    check("T39.right-first", e1 == SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: 3, format: 3))
    check("T39.no-guess", e2 == nil)
} catch { check("T39.threw \(error)", false) }

// T40: spherical map - equirect and half-equirect both map EQUIRECT
// (180/360 stays session-side); cubemap maps CUBEMAP; tiled and
// unrecognized values preserve raw verbatim.
do {
    let eq = StereoSideDataMap.mapSpherical(projection: 0, source: 2, format: 1)
    let half = StereoSideDataMap.mapSpherical(projection: 3, source: 2, format: 1)
    let cube = StereoSideDataMap.mapSpherical(projection: 1, source: 2, format: 1)
    let tiled = StereoSideDataMap.mapSpherical(projection: 2, source: 2, format: 1)
    let other = StereoSideDataMap.mapSpherical(projection: 42, source: 2, format: 1)
    check("T40.equirect", eq.kind == 1 && eq.norm == 2 && half.kind == 1 && half.norm == 2)
    check("T40.cubemap", cube.kind == 1 && cube.norm == 3)
    check("T40.unknown", tiled.kind == 2 && tiled.raw == 2 && other.kind == 2 && other.raw == 42)
} catch { check("T40.threw \(error)", false) }

// T41: mapped observations feed the QUALIFIED v7 transport end to end -
// track observations at rebind, a codec SEI replacing the codec slot,
// and the exact-selection feed answering.
do {
    let t = StereoStreamMetadataTransport()
    let (tl, te) = StereoSideDataMap.mapStereo3D(type: 1, inverted: true, source: 2, format: 1)
    let tp = StereoSideDataMap.mapSpherical(projection: 0, source: 2, format: 1)
    var track = StereoStreamMetadata()
    track.layout = StereoStreamFieldMetadata(observations: [tl])
    track.eyeOrder = StereoStreamFieldMetadata(observations: [te].compactMap { $0 })
    track.projection = StereoStreamFieldMetadata(observations: [tp])
    try t.rebindSource(to: ctx, track: track)
    let (cl, _) = StereoSideDataMap.mapStereo3D(type: 2, inverted: false, source: 3, format: 3)
    try t.applyCodecSEI(context: ctx, field: .layout, observation: cl)
    check("T41.slots", t.observations(.layout).count == 2
          && t.observations(.eyeOrder).count == 1 && t.observations(.projection).count == 1)
    _ = try t.feed(selection: sel)
    check("T41.feed", true)
    do { _ = try t.feed(selection: StereoSelectedStream(track: 2, stream: nil))
         check("T41.wrong-selection", false) }
    catch StereoMetadataTransportError.selectionMismatch { check("T41.wrong-selection", true) }
} catch { check("T41.threw \(error)", false) }

// T42: submission - no install: frame refuses typed, block is nil, and
// the query before any production is nil.
do {
    let sub = StereoLookStageSubmission<AdapterTestFrame>()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    check("T42.no-install-block", sub.block(admitted: f) == nil)
    do { _ = try sub.frame(f, host: makeHost()); check("T42.uninstalled", false) }
    catch StereoLookStageConsumeRefusal.uninstalled { check("T42.uninstalled", true) }
} catch { check("T42.threw \(error)", false) }

// T43: produced submission binds against the ADMITTED frame only; a
// wrong frame answers nil and the submission stays whole.
do {
    let sub = StereoLookStageSubmission<AdapterTestFrame>()
    _ = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let fOther = AdapterTestFrame(session: "s", generation: 1, sequence: 2, presentationEpoch: 0)
    let o = try sub.frame(f, host: makeHost())
    guard case .produced(let rev) = o else { check("T43.produced", false); throw NSError(domain: "t", code: 1) }
    let bound = sub.block(admitted: f)
    check("T43.bound", bound != nil && bound?.revision == rev)
    check("T43.wrong-frame-nil", sub.block(admitted: fOther) == nil)
    check("T43.submission-whole", sub.block(admitted: f) != nil)
} catch { check("T43.threw \(error)", false) }

// T44: .unchanged keeps the submission; .gated clears it AND rebinds
// the stage (while gated no payload can bind - the BINDING-level
// "uninstalled"; the epoch is intentionally live and fresh); a later
// open gate re-produces under the fresh epoch, pre-gate payloads
// refuse typed under both their dead epoch and the rebound one.
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let sub = StereoLookStageSubmission<AdapterTestFrame>(adapter: adapter)
    let e1 = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let o1 = try sub.frame(f, host: makeHost())
    guard case .produced = o1, let preGate = sub.current else { check("T44.produced", false); throw NSError(domain: "t", code: 2) }
    let o2 = try sub.frame(f, host: makeHost())
    check("T44.unchanged", o2 == .unchanged && sub.block(admitted: f) != nil)
    let o3 = try sub.frame(f, host: makeHost(enabled: false))
    check("T44.gated", o3 == .gated && sub.block(admitted: f) == nil)
    let o4 = try sub.frame(f, host: makeHost(enabled: false))
    check("T44.gated-consistent", o4 == .gated && sub.block(admitted: f) == nil)
    // The rebound epoch is intentionally NON-nil mid-gate and differs
    // from the pre-gate one; the pre-gate payload refuses typed under
    // the LIVE rebound epoch (not only under its own dead one).
    let eMid = sub.installedEpoch
    check("T44.gated-epoch-rebound", eMid != nil && eMid != e1)
    if let eMid {
        do {
            _ = try adapter.consume(preGate.payload, admitted: f, installed: eMid,
                                    revision: preGate.revision)
            check("T44.gated-old-payload-refused", false)
        } catch StereoLookStageConsumeRefusal.staleStageEpoch {
            check("T44.gated-old-payload-refused", true)
        } catch { check("T44.gated-old-payload-refused", false) }
    } else { check("T44.gated-old-payload-refused", false) }
    let o5 = try sub.frame(f, host: makeHost())
    if case .produced = o5 { check("T44.reproduced", sub.block(admitted: f) != nil) }
    else { check("T44.reproduced", false) }
    // v11 retained-frame reopen regression (Z4C v10): the REAL invariant
    // is the stage-epoch rebind - same-value writes INTENTIONALLY keep
    // the producer revision, so no revision bump is asserted. The
    // installed epoch must have advanced and the pre-gate payload must
    // refuse under its old epoch (typed, nothing mutates).
    if case .produced = o5, let e5 = sub.installedEpoch {
        check("T44.epoch-rebound", e5 != e1)
        do {
            _ = try adapter.consume(preGate.payload, admitted: f, installed: e1,
                                    revision: preGate.revision)
            check("T44.old-epoch-refused", false)
        } catch StereoLookStageConsumeRefusal.staleStageEpoch {
            check("T44.old-epoch-refused", true)
        } catch { check("T44.old-epoch-refused", false) }
    } else { check("T44.epoch-rebound", false); check("T44.old-epoch-refused", false) }
} catch { check("T44.threw \(error)", false) }

// T45: invalidation clears the submission AND the installation; a fresh
// install mints a new epoch; a payload from the old epoch can never
// bind again.
do {
    let sub = StereoLookStageSubmission<AdapterTestFrame>()
    let epoch1 = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    _ = try sub.frame(f, host: makeHost())
    sub.invalidate(.surfaceChange)
    check("T45.cleared", sub.installedEpoch == nil && sub.block(admitted: f) == nil)
    do { _ = try sub.frame(f, host: makeHost()); check("T45.frame-uninstalled", false) }
    catch StereoLookStageConsumeRefusal.uninstalled { check("T45.frame-uninstalled", true) }
    let epoch2 = sub.install()
    check("T45.fresh-epoch", epoch2 != epoch1)
    let o = try sub.frame(f, host: makeHost())
    if case .produced = o { check("T45.reproduced", sub.block(admitted: f) != nil) }
    else { check("T45.reproduced", false) }
    for cause in [StereoLookStageInvalidation.rebind, .retire, .streamChange, .sourceChange] {
        sub.invalidate(cause)
    }
    check("T45.all-causes", sub.installedEpoch == nil && sub.current == nil)
} catch { check("T45.threw \(error)", false) }

// T46: a host change re-produces at a NEW block revision and the
// submission carries exactly that revision.
do {
    let sub = StereoLookStageSubmission<AdapterTestFrame>()
    _ = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    guard case .produced(let r1) = try sub.frame(f, host: makeHost()) else {
        check("T46.first", false); throw NSError(domain: "t", code: 1) }
    guard case .produced(let r2) = try sub.frame(f, host: makeHost(yaw: 0.5)) else {
        check("T46.second", false); throw NSError(domain: "t", code: 1) }
    check("T46.new-revision", r1 != r2 && sub.block(admitted: f)?.revision == r2)
} catch { check("T46.threw \(error)", false) }

// T47: full-equality frame binding at the submission boundary - ANY
// single-field difference is a new frame, and the previous frame's
// query then answers nil (the submission moved to the new frame).
do {
    let sub = StereoLookStageSubmission<AdapterTestFrame>()
    _ = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let fEp = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 1)
    _ = try sub.frame(f, host: makeHost())
    let o = try sub.frame(fEp, host: makeHost())
    if case .produced = o { check("T47.new-frame", true) } else { check("T47.new-frame", false) }
    check("T47.old-frame-nil", sub.block(admitted: f) == nil)
    check("T47.new-frame-bound", sub.block(admitted: fEp) != nil)
} catch { check("T47.threw \(error)", false) }

// T48: authority change/loss (Z4C v11 RED harness host/): the retained
// submission is cleared and the stage rebound on authorityChanged(),
// the pre-change payload refuses typed under the live rebound epoch,
// and an identical-authority return RE-PRODUCES (the retained accepted
// state is never aliased into a nil wrapper).
do {
    let adapter = StereoLookStageAdapter<AdapterTestFrame>()
    let sub = StereoLookStageSubmission<AdapterTestFrame>(adapter: adapter)
    let e1 = sub.install()
    let f = AdapterTestFrame(session: "s", generation: 1, sequence: 1, presentationEpoch: 0)
    let o1 = try sub.frame(f, host: makeHost())
    guard case .produced = o1, let retained = sub.current else {
        check("T48.produced", false); throw NSError(domain: "t", code: 3) }
    check("T48.bound", sub.block(admitted: f) != nil)
    sub.authorityChanged()
    check("T48.loss-clears", sub.block(admitted: f) == nil)
    check("T48.epoch-rebound", sub.installedEpoch != nil && sub.installedEpoch != e1)
    if let eLive = sub.installedEpoch {
        do {
            _ = try adapter.consume(retained.payload, admitted: f, installed: eLive,
                                    revision: retained.revision)
            check("T48.old-payload-refused", false)
        } catch StereoLookStageConsumeRefusal.staleStageEpoch {
            check("T48.old-payload-refused", true)
        } catch { check("T48.old-payload-refused", false) }
    } else { check("T48.old-payload-refused", false) }
    let o2 = try sub.frame(f, host: makeHost())
    if case .produced = o2 { check("T48.reproduced", sub.block(admitted: f) != nil) }
    else { check("T48.reproduced", false) }
    // Repeated authority change (loss again): another eager rebind,
    // still uninstalled-never, and the drive after it re-produces.
    sub.authorityChanged()
    check("T48.reloss", sub.block(admitted: f) == nil && sub.installedEpoch != nil)
    let o3 = try sub.frame(f, host: makeHost())
    if case .produced = o3 { check("T48.re-reproduced", sub.block(admitted: f) != nil) }
    else { check("T48.re-reproduced", false) }
} catch { check("T48.threw \(error)", false) }

print("stereo-transport-tests: \(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
