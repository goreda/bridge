import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

// Witness for the R1 render graph contracts: uniform block layout, per-stage
// field ownership, full-graph encode, session fencing, HostTransform consumed
// through the interface only.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func frame(_ session: UInt64, _ w: Int = 1920, _ h: Int = 1080) -> NativeFrame {
    NativeFrame(session: session, handle: 1, pts: 0, duration: 33_333,
                width: w, height: h, pixelFormatName: "yuv420p", isKeyFrame: true)
}

struct FixedHost: HostTransformSource {
    let t: HostTransform
    var currentHostTransform: HostTransform { t }
}

// T1: explicit wire layout, independent of Swift struct storage.
check("T1-size", FrameUniformABI.payloadBytes == 64 && FrameUniformABI.packetBytes == 88)
check("T1-lanes", FrameUniformABI.Lane.allCases.count == 16)

// T2: identity defaults are renderer-safe
let u0 = FrameUniforms()
check("T2-defaults", u0.cropW == 1 && u0.cropH == 1 && u0.saturation == 1
      && u0.srcPeakNits == 100 && u0.log2Zoom == 0 && u0.flags == 0)

// T3: control stage writes only its fields
var u3 = FrameUniforms()
var st = ControlState(); st.fit = nil
ControlStageEncoder.encode(into: &u3, frame: frame(7, 1280, 720), state: st) { _ in 0 }
check("T3-control", u3.frameWidth == 1280 && u3.frameHeight == 720 && u3.fitModeID == 0
      && u3.cropW == 1 && u3.saturation == 1 && u3.flags == 0)

// T4: fit id comes from the caller's table
var u4 = FrameUniforms()
var st4 = ControlState(); _ = ModeToken("fill").map { st4.fit = $0 }
ControlStageEncoder.encode(into: &u4, frame: frame(7), state: st4) { $0 == nil ? 0 : 7 }
check("T4-fitid", u4.fitModeID == 7)

// T5: crop stage resolves and normalizes
var crop = CropController(session: 7, autoThreshold: 0.9)!
crop.set(NormalizedRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!)
var u5 = FrameUniforms()
let ok5 = CropStageEncoder.encode(into: &u5, frame: frame(7), controller: crop)
check("T5-crop", ok5 && abs(u5.cropX - 0.25) < 1e-6 && abs(u5.cropW - 0.5) < 1e-6)

// T6: refused crop leaves fields untouched
var c6 = CropController(session: 8, autoThreshold: 0.9)! // wrong session
var u6 = FrameUniforms(); u6.cropX = 0.123
check("T6-crop-refused", !CropStageEncoder.encode(into: &u6, frame: frame(7), controller: c6)
      && u6.cropX == 0.123)

// T7: host transform passes through the contract verbatim
var u7 = FrameUniforms()
HostTransformStageEncoder.encode(into: &u7, source: FixedHost(t: HostTransform(panX: 0.5, panY: -0.25, log2Zoom: 2)!))
check("T7-host", u7.panX == 0.5 && u7.panY == -0.25 && u7.log2Zoom == 2)
check("T7b-host-guard", HostTransform(panX: .nan, panY: 0, log2Zoom: 0) == nil
      && HostTransform(panX: 0, panY: 0, log2Zoom: .infinity) == nil)

// T8: color stage maps the plan, fallback + gamut in flags
var u8 = FrameUniforms()
let plan = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 4000),
                           target: DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 0.8, gamut: .relativeColorimetric)!,
                           hardwareToneMapper: false)
ColorStageEncoder.encode(into: &u8, plan: plan)
check("T8-color", u8.toneCurveID == FrameUniforms.curveID(.mobius) && u8.srcPeakNits == 4000
      && u8.dstPeakNits == 100 && abs(u8.saturation - 0.8) < 1e-6
      && u8.flags & 1 == 1 && u8.flags & 2 == 2)

// T9: full graph encode
var crop9 = CropController(session: 7, autoThreshold: 0.9)!; crop9.set(NormalizedRect(x: 0, y: 0.1, w: 1, h: 0.8)!)
let r9 = RenderGraph.encode(session: 7, frame: frame(7), control: ControlState(),
                            crop: crop9, host: FixedHost(t: .identity), color: plan)
if let r9 {
    check("T9-graph", r9.cropEncoded && r9.uniforms.frameWidth == 1920
          && abs(r9.uniforms.cropY - 0.1) < 1e-5 && r9.uniforms.toneCurveID == FrameUniforms.curveID(.mobius)
          && r9.uniforms.log2Zoom == 0)
} else { check("T9-graph", false) }

// T10: session fence
check("T10-fence", RenderGraph.encode(session: 7, frame: frame(9), control: ControlState(),
                                      crop: crop9, host: FixedHost(t: .identity), color: plan) == nil)

// T11: curve ids are stable across all cases (contract with the shader table)
check("T11-curve-ids", ToneMapCurve.allCases.enumerated().allSatisfy { FrameUniforms.curveID($1) == UInt32($0) })

let tooBright = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: .greatestFiniteMagnitude), target: .sdr100, hardwareToneMapper: false)
check("T12-float-overflow-refused", RenderGraph.encode(session: 7, frame: frame(7), control: ControlState(), crop: crop9, host: FixedHost(t: .identity), color: tooBright) == nil)


// Wire ABI checks do not depend on the Swift struct's storage layout.
var wireState = ControlState(); wireState.look = ParameterBlockRevision(0x1122334455667788)
let wireRevision = wireState.look!
let packet = RenderGraph.serialized(session: 7, revision: wireRevision, frame: frame(7),
    control: wireState, crop: crop9, host: FixedHost(t: HostTransform(panX: 0.5, panY: -0.25, log2Zoom: 2)!), color: plan)!
check("W1-size", packet.count == 88)
check("W2-header-endian", Array(packet.prefix(8)) == [0x47, 0x46, 0x55, 0x31, 1, 0, 0, 0]
      && Array(packet[16..<24]) == [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
check("W3-offsets", FrameUniformABI.Lane.allCases.map(\.payloadByteOffset) == Array(stride(from: 0, to: 64, by: 4))
      && FrameUniformABI.Lane.panX.packetByteOffset == 56 && FrameUniformABI.Lane.toneCurveID.packetByteOffset == 72)
check("W4-float-bits", Array(packet[56..<60]) == [0, 0, 0, 0x3f] && Array(packet[72..<76]) == [2, 0, 0, 0])
if case .success(let block) = PresenterUniformConsumer.consume(packet, session: 7, revision: wireRevision) {
    check("W5-decode", block.uniforms.panX == 0.5 && block.uniforms.panY == -0.25 && block.uniforms.log2Zoom == 2
          && block.uniforms.toneCurveID == 2 && block.session == 7 && block.revision == wireRevision)
    check("W6-exact-consumed-bytes", block.shaderBytes == Data(packet.suffix(64)))
} else { check("W5-decode", false); check("W6-exact-consumed-bytes", false) }
check("W7-wrong-session", PresenterUniformConsumer.consume(packet, session: 8, revision: wireRevision) == .failure(.sessionMismatch))
check("W8-wrong-revision", PresenterUniformConsumer.consume(packet, session: 7, revision: ParameterBlockRevision(0)) == .failure(.revisionMismatch))
check("W9-producer-revision", RenderGraph.serialized(session: 7, revision: ParameterBlockRevision(0), frame: frame(7), control: wireState, crop: crop9, host: FixedHost(t: .identity), color: plan) == nil)
check("W10-producer-crop", RenderGraph.serialized(session: 7, revision: wireRevision, frame: frame(7), control: wireState, crop: c6, host: FixedHost(t: .identity), color: plan) == nil)
check("W11-producer-session", RenderGraph.serialized(session: 9, revision: wireRevision, frame: frame(7), control: wireState, crop: crop9, host: FixedHost(t: .identity), color: plan) == nil)
check("W12-conversion-overflow", RenderGraph.serialized(session: 7, revision: wireRevision, frame: frame(7), control: wireState, crop: crop9, host: FixedHost(t: .identity), color: tooBright) == nil)
func modified(_ lane: FrameUniformABI.Lane, _ word: UInt32) -> Data {
    var copy = packet
    for i in 0..<4 { copy[lane.packetByteOffset + i] = UInt8(truncatingIfNeeded: word >> (8 * i)) }
    return copy
}
for (label, bytes) in [("nan", modified(.panX, Float.nan.bitPattern)),
                       ("crop", modified(.cropW, Float(2).bitPattern)),
                       ("curve", modified(.toneCurveID, 5)), ("flags", modified(.flags, 4)),
                       ("reserved", modified(.reserved, 1)), ("host-range", modified(.log2Zoom, Float(9).bitPattern))] {
    check("W13-refuse-\(label)", PresenterUniformConsumer.consume(bytes, session: 7, revision: wireRevision) == .failure(.invalidPayload))
}
check("W14-truncated", PresenterUniformConsumer.consume(Data(packet.dropLast()), session: 7, revision: wireRevision) == .failure(.malformed))
var unsupported = packet; unsupported[4] = 2
check("W15-version", PresenterUniformConsumer.consume(unsupported, session: 7, revision: wireRevision) == .failure(.unsupportedVersion))
check("W16-fit-ids", FrameUniformABI.fitID(nil)?.rawValue == 0
      && FrameUniformABI.fitID(ModeToken("fit"))?.rawValue == 1
      && FrameUniformABI.fitID(ModeToken("fill"))?.rawValue == 2
      && FrameUniformABI.fitID(ModeToken("stretch"))?.rawValue == 3)
wireState.fit = ModeToken("unregistered")
check("W17-unknown-fit-refused", RenderGraph.serialized(session: 7, revision: wireRevision, frame: frame(7), control: wireState, crop: crop9, host: FixedHost(t: .identity), color: plan) == nil)
check("W18-wire-unknown-fit-refused", PresenterUniformConsumer.consume(modified(.fitModeID, 4), session: 7, revision: wireRevision) == .failure(.invalidPayload))
// P21 (198a-5b): canonical ordered stage list and order-driven encode.
// DR-0017: sourceMeasurement inserted after decode, before colorToneMap and the
// photon sharp/grain passes - the GPU measurement reads the decoded source.
check("S1-canonical-list", RenderGraphStage.allCases.map(\.rawValue) == ["decode", "sourceMeasurement", "colorToneMap", "crop", "stereoProjection", "photon", "surround", "output", "bitmapSubtitles", "present"])
check("S2-encoder-mapping", RenderStageID.color.graphStage == .colorToneMap && RenderStageID.crop.graphStage == .crop
      && RenderStageID.control.graphStage == .output && RenderStageID.hostTransform.graphStage == .output)
check("S3-application-order", RenderGraph.encoderApplicationOrder == [.color, .crop, .control, .hostTransform])
check("S4-encoder-coverage", RenderGraphStage.allCases.filter(\.hasEncoder).map(\.rawValue) == ["colorToneMap", "crop", "output"]
      && RenderStageID.allCases.allSatisfy { $0.graphStage.hasEncoder })
// Order-driven encode produces the identical block as the fixed sequence did.
let r9b = RenderGraph.encode(session: 7, frame: frame(7), control: ControlState(),
                             crop: crop9, host: FixedHost(t: .identity), color: plan)
check("S5-encode-stable", r9b == r9)

// P22 (198a-5b): typed 127-parameter live look block.
check("L1-count", LookParameterTable.all.count == 127 && LookParameterTable.count == 127)
check("L2-family-counts", LookParameterFamily.allCases.allSatisfy { fam in
    LookParameterTable.all.filter { $0.family == fam }.count == fam.expectedCount
} && LookParameterFamily.allCases.map(\.expectedCount) == [68, 5, 3, 29, 3, 19])
check("L3-offsets", LookParameterTable.all.indices.allSatisfy { LookParameterTable.all[$0].offset == $0 })
check("L4-names-unique", Set(LookParameterTable.all.map(\.name)).count == 127)
// Digest pins the table to the measured live universe at goreda/instinct c54467887
check("L5-manifest-digest", LookParameterTable.manifestDigest() == 0x6c88c1b6baf184b4)
var block = LookParameterBlock()
check("L6-default-pins", block.value("vr_pack") == 0 && block.value("vr_pk_conv") == 0.5
      && block.value("vr_pk_zoom") == 1 && block.value("vr_pk_soft") == 1 && block.value("vr_pk_surround_invert") == 0
      && block.value("vr_parallax_disparity") == -0.4 && block.value("vr_vignette_blur") == 0.0015
      && block.value("STOCK_PRESET") == 5 && block.value("nonexistent") == nil)
check("L7-set", block.set("vr_head_roll", 1.5) == .success(ParameterBlockRevision(1)) && block.value("vr_head_roll") == 1.5)
check("L7b-same-value-no-bump", block.set("vr_head_roll", 1.5) == .success(ParameterBlockRevision(1)))
check("L7c-unknown", block.set("vr_nope", 1) == .failure(.unknownName))
check("L7d-nonfinite", block.set("vr_head_roll", .nan) == .failure(.nonFinite) && block.set("vr_head_roll", .infinity) == .failure(.nonFinite))
check("L7e-define-refused", block.set("PHOTON_SHARP_ALGO", 1) == .failure(.requiresVariant))
check("L7f-int-fractional", block.set("RES_ADAPT", 1.5) == .failure(.notIntegral)
      && block.set("RES_ADAPT", 2) == .success(ParameterBlockRevision(2)))
let packetL = LookParameterABI.serialize(block)
check("L8-wire-size", packetL.count == LookParameterABI.packetBytes && LookParameterABI.packetBytes == 24 + 127 * 4)
if case .success(let decoded) = LookParameterABI.consume(packetL, revision: block.revision) {
    check("L8b-wire-roundtrip", decoded.revision == block.revision && decoded.values.count == 127
          && decoded.values[LookParameterTable.index(of: "vr_head_roll")!] == 1.5
          && decoded.values[LookParameterTable.index(of: "RES_ADAPT")!] == 2
          && decoded.values[LookParameterTable.index(of: "vr_pk_conv")!] == 0.5
          && decoded.shaderBytes == packetL.suffix(127 * 4))
} else { check("L8b-wire-roundtrip", false) }
check("L9-wire-truncated", LookParameterABI.consume(packetL.dropLast(), revision: block.revision) == .failure(.malformed))
var badVer = packetL; badVer[4] = 2
check("L9b-wire-version", LookParameterABI.consume(badVer, revision: block.revision) == .failure(.unsupportedVersion))
check("L9c-wire-revision", LookParameterABI.consume(packetL, revision: ParameterBlockRevision(99)) == .failure(.revisionMismatch))
var badCount = packetL; badCount[16] = 126
check("L9d-wire-lanecount", LookParameterABI.consume(badCount, revision: block.revision) == .failure(.laneCountMismatch))
var nanLane = packetL
let nanOff = LookParameterABI.headerBytes + LookParameterTable.index(of: "vr_head_roll")! * 4
for i in 0..<4 { nanLane[nanOff + i] = UInt8(truncatingIfNeeded: Float.nan.bitPattern >> (8 * i)) }
check("L9e-wire-nan", LookParameterABI.consume(nanLane, revision: block.revision) == .failure(.invalidPayload))
check("L10-revision-monotonic", block.set("vr_fov", 90) == .success(ParameterBlockRevision(3))
      && block.set("GR_AMOUNT", 0.75) == .success(ParameterBlockRevision(4)))

// P22 routing (198a-5b): every parameter consumed by exactly one P21 stage.
check("R1-total-routed", RenderGraphStage.allCases.map { LookParameterRouting.count(for: $0) }.reduce(0, +) == 127)
check("R2-stage-counts", LookParameterRouting.count(for: .stereoProjection) == 33
      && LookParameterRouting.count(for: .surround) == 29 && LookParameterRouting.count(for: .crop) == 2
      && LookParameterRouting.count(for: .output) == 9 && LookParameterRouting.count(for: .photon) == 54
      && LookParameterRouting.count(for: .decode) == 0 && LookParameterRouting.count(for: .colorToneMap) == 0
      && LookParameterRouting.count(for: .bitmapSubtitles) == 0 && LookParameterRouting.count(for: .present) == 0)
check("R3-photon-families", LookParameterFamily.allCases.filter { $0.rawValue.hasPrefix("photon") }.allSatisfy { fam in
    LookParameterTable.all.filter { $0.family == fam }.allSatisfy { $0.stage == .photon }
} && LookParameterRouting.parameters(for: .photon).count == 54)
check("R4-routing-digest", LookParameterRouting.routingDigest() == 0xc6684e869ace3449)
check("R5-spot-pins", LookParameterTable.parameter("vr_crop_x")?.stage == .crop
      && LookParameterTable.parameter("vr_surface_w")?.stage == .output
      && LookParameterTable.parameter("blink_upper")?.stage == .surround
      && LookParameterTable.parameter("vr_fov")?.stage == .stereoProjection
      && LookParameterTable.parameter("GR_AMOUNT")?.stage == .photon
      && LookParameterTable.parameter("vr_pk_surround_invert")?.stage == .surround
      && LookParameterTable.parameter("vr_pk_conv")?.stage == .stereoProjection)
check("R6-blink-family", LookParameterTable.all.filter { $0.name.hasPrefix("blink_") }.count == 22
      && LookParameterTable.all.filter { $0.name.hasPrefix("blink_") }.allSatisfy { $0.stage == .surround })

print("render-graph-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
