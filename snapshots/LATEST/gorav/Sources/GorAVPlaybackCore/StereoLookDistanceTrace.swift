import StereoLookNativeContract

/// full182 (block182 owner order phonemsg-01M6PEZ10K9Y7Q3SGBNAVWTTQJ item 2,
/// owner channel 2026-11-05 21:19): "log d, s, the clamp flag and each
/// fallback reason in the geom trace." This payload carries the native input
/// owner's per-pull distance evaluation (StereoLookBaseEvaluation, owner
/// file StereoLookNativeInputOwner.swift) across the host-input boundary so
/// the presenter can emit the NATIVE geom-trace line. Transport only: every
/// value is the owner's evaluation VERBATIM, never recomputed or repaired at
/// this layer (no second distance authority; the producer's one-euro fD stays
/// the single filter authority, Sensing.swift l.220-221). A nil field is
/// rendered null exactly like the Lua trace (pin c455d945 l.406-413); the
/// four s_total/s_requested/offset/ipd_eff slots stay null until the owner
/// surfaces them (boundary decision D3) - they are never derived here.
// arch facade r1 (no-delete form): the declaration moved byte-verbatim into
// the StereoLookNativeContract module so the app target can consume it
// without a GorAVPlaybackCore edge. This file is RETAINED (no file
// deletion) as the module-local alias: every existing GorAVPlaybackCore
// reference keeps resolving to the SAME type identity.
public typealias StereoLookDistanceTrace = StereoLookNativeContract.StereoLookDistanceTrace
