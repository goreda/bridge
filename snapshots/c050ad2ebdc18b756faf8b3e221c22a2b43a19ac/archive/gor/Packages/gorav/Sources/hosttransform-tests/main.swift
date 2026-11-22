// Sources/hosttransform-tests/main.swift  (exit 0 = all pass)
import GorAVPlaybackCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var failures = 0
func check(_ n: String, _ ok: Bool) { print(ok ? "PASS \(n)" : "FAIL \(n)"); if !ok { failures += 1 } }
func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
func nearF(_ a: [Float], _ b: [Float], _ eps: Float = 1e-6) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= eps } }
func T(_ x: Double, _ y: Double, _ z: Double) -> HostTransform { HostTransform(panX: x, panY: y, log2Zoom: z)! }

// Validation
check("H1 identity accepted", HostTransform(panX: 0, panY: 0, log2Zoom: 0) == HostTransform.identity)
check("H2 NaN and inf refused", HostTransform(panX: .nan, panY: 0, log2Zoom: 0) == nil && HostTransform(panX: 0, panY: .infinity, log2Zoom: 0) == nil && HostTransform(panX: 0, panY: 0, log2Zoom: -.infinity) == nil)
check("H3 out of range refused, not clamped", HostTransform(panX: 16.01, panY: 0, log2Zoom: 0) == nil && HostTransform(panX: 0, panY: 0, log2Zoom: 8.01) == nil && HostTransform(panX: 0, panY: 0, log2Zoom: -8.01) == nil)
check("H4 range edges accepted", HostTransform(panX: -16, panY: 16, log2Zoom: 8) != nil && HostTransform(panX: 0, panY: 0, log2Zoom: -8) != nil)
check("H5 zoom is 2^log2Zoom", near(T(0, 0, 1).zoom, 2) && near(T(0, 0, -1).zoom, 0.5) && near(T(0, 0, 0).zoom, 1))

// Quad (same layout as MetalRenderer.quad): sx 0.5, sy 1
let base: [Float] = [-0.5, 1, 0, 0, -0.5, -1, 0, 1, 0.5, 1, 1, 0, 0.5, -1, 1, 1]
check("Q1 identity transform reproduces the existing aspect-fit quad exactly", hostTransformQuad(scaleX: 0.5, scaleY: 1, .identity) == base)
check("Q2 zoom +1 doubles the half extents about the center", nearF(hostTransformQuad(scaleX: 0.5, scaleY: 1, T(0, 0, 1)), [-1, 2, 0, 0, -1, -2, 0, 1, 1, 2, 1, 0, 1, -2, 1, 1]))
check("Q3 pan +0.25 moves the quad right by 0.5 NDC", nearF(hostTransformQuad(scaleX: 0.5, scaleY: 1, T(0.25, 0, 0)), [0, 1, 0, 0, 0, -1, 0, 1, 1, 1, 1, 0, 1, -1, 1, 1]))
check("Q4 pan +0.25 in y moves the quad up by 0.5 NDC", nearF(hostTransformQuad(scaleX: 0.5, scaleY: 1, T(0, 0.25, 0)), [-0.5, 1.5, 0, 0, -0.5, -0.5, 0, 1, 0.5, 1.5, 1, 0, 0.5, -0.5, 1, 1]))
check("Q5 pan is applied after zoom (not scaled by it)", nearF(hostTransformQuad(scaleX: 0.5, scaleY: 1, T(0.25, 0, 1)), [-0.5, 2, 0, 0, -0.5, -2, 0, 1, 1.5, 2, 1, 0, 1.5, -2, 1, 1]))
check("Q6 uv layout untouched by any transform", {
    let q = hostTransformQuad(scaleX: 0.3, scaleY: 0.9, T(-3, 2, -2))
    return [q[2], q[3], q[6], q[7], q[10], q[11], q[14], q[15]] == [0, 0, 0, 1, 1, 0, 1, 1]
}())
check("Q7 zoom out shrinks, extreme values stay finite", hostTransformQuad(scaleX: 1, scaleY: 1, T(16, -16, -8)).allSatisfy { $0.isFinite } && hostTransformQuad(scaleX: 1, scaleY: 1, T(-16, 16, 8)).allSatisfy { $0.isFinite })

// Effective rect: 1920x1080 frame in a 1000x1000 drawable -> fit 1000 x 562.5, y 218.75
let r0 = effectiveVideoRect(drawableW: 1000, drawableH: 1000, frameW: 1920, frameH: 1080, .identity)!
check("R1 identity is the aspect-fit letterbox", near(r0.x, 0) && near(r0.y, 218.75) && near(r0.w, 1000) && near(r0.h, 562.5))
let r1 = effectiveVideoRect(drawableW: 1000, drawableH: 1000, frameW: 1920, frameH: 1080, T(0, 0, 1))!
check("R2 zoom 2x about the center, rect extends past the drawable", near(r1.w, 2000) && near(r1.h, 1125) && near(r1.x, -500) && near(r1.y, 500 - 562.5))
let r2 = effectiveVideoRect(drawableW: 1000, drawableH: 1000, frameW: 1920, frameH: 1080, T(0.1, 0.1, 0))!
check("R3 pan +x right, +y up (y down in pixels)", near(r2.x, 100) && near(r2.y, 218.75 - 100))
check("R4 invalid sizes give nil", effectiveVideoRect(drawableW: 0, drawableH: 10, frameW: 1, frameH: 1, .identity) == nil && effectiveVideoRect(drawableW: 10, drawableH: 10, frameW: 1, frameH: 0, .identity) == nil && effectiveVideoRect(drawableW: -1, drawableH: 10, frameW: 1, frameH: 1, .identity) == nil)
// Cross-check: the pixel rect and the NDC quad describe the same rectangle
func crossCheck(_ t: HostTransform) -> Bool {
    let dw = 1280, dh = 720, fw = 1920, fh = 1080
    let s = min(Double(dw) / Double(fw), Double(dh) / Double(fh))
    let sx = Double(fw) * s / Double(dw), sy = Double(fh) * s / Double(dh)
    let q = hostTransformQuad(scaleX: sx, scaleY: sy, t)
    let r = effectiveVideoRect(drawableW: dw, drawableH: dh, frameW: fw, frameH: fh, t)!
    let leftPx = (Double(q[0]) + 1) / 2 * Double(dw)
    let rightPx = (Double(q[8]) + 1) / 2 * Double(dw)
    let topPx = (1 - Double(q[1])) / 2 * Double(dh)
    let botPx = (1 - Double(q[5])) / 2 * Double(dh)
    return near(leftPx, r.x, 1e-2) && near(rightPx, r.x + r.w, 1e-2) && near(topPx, r.y, 1e-2) && near(botPx, r.y + r.h, 1e-2)
}
check("X1 quad and rect agree: identity", crossCheck(.identity))
check("X2 quad and rect agree: zoom + pan", crossCheck(T(0.2, -0.15, 1.5)))
check("X3 quad and rect agree: zoom out + negative pan", crossCheck(T(-0.4, 0.3, -1)))
let g = effectiveVideoGeometry(drawableW: 1000, drawableH: 1000, frameW: 1920, frameH: 1080, .identity)
check("G1 geometry carries frame size, drawable size and rect", g?.frameWidth == 1920 && g?.frameHeight == 1080 && g?.drawableWidth == 1000 && g?.rect == r0)
check("G2 geometry nil without a frame", effectiveVideoGeometry(drawableW: 1000, drawableH: 1000, frameW: 0, frameH: 0, .identity) == nil)

// N6: portable geometry oracle. Native binding uses exactly these vertices.
func U(_ fit: FrameUniformABI.FitID = .fit, _ t: HostTransform = .identity) -> FrameUniforms {
    var u = FrameUniforms(); u.frameWidth = 1920; u.frameHeight = 1080
    u.fitModeID = fit.rawValue; u.panX = Float(t.panX); u.panY = Float(t.panY); u.log2Zoom = Float(t.log2Zoom)
    return u
}
func G(_ u: FrameUniforms, _ dw: Int = 1000, _ dh: Int = 1000) -> [Float] {
    StageGeometry.quad(uniforms: u, drawableWidth: dw, drawableHeight: dh)!
}
check("N6 fit matches original HostTransform oracle", nearF(G(U()), hostTransformQuad(scaleX: 1, scaleY: 0.5625, .identity)))
check("N6 unset is fit, not stretch", G(U(.unset)) == G(U(.fit)))
check("N6 fill preserves source aspect, not stretch", nearF(G(U(.fill)), hostTransformQuad(scaleX: 16.0/9, scaleY: 1, .identity)))
check("N6 stretch only when explicit", nearF(G(U(.stretch)), hostTransformQuad(scaleX: 1, scaleY: 1, .identity)))
let pan = T(0.25, 0.125, 1)
check("N6 pan is screen-space post-zoom right/up", nearF(G(U(.fit, pan)), hostTransformQuad(scaleX: 1, scaleY: 0.5625, pan)))
check("N6 pan zoom-out has same translation", near(Double(G(U(.fit, T(0.25, 0.125, -1)))[0] - G(U(.fit, T(0, 0, -1)))[0]), 0.5))
var cropped = U(); cropped.cropX = 0.25; cropped.cropY = 0.25; cropped.cropW = 0.5; cropped.cropH = 0.5
check("N6 crop retains aspect and exact UV", nearF(G(cropped), [-1, 0.5625, 0.25, 0.25, -1, -0.5625, 0.25, 0.75, 1, 0.5625, 0.75, 0.25, 1, -0.5625, 0.75, 0.75]))
cropped.cropW = 0.25
check("N6 asymmetric crop changes fitted aspect", near(Double(G(cropped)[0]), -8.0/9, 1e-6) && near(Double(G(cropped)[1]), 1))
check("N6 bad drawable refuses", StageGeometry.quad(uniforms: U(), drawableWidth: 0, drawableHeight: 1) == nil)
var invalid = U(); invalid.fitModeID = 55
check("N6 unknown fit refuses", StageGeometry.quad(uniforms: invalid, drawableWidth: 1, drawableHeight: 1) == nil)
func admitted(_ u: FrameUniforms) -> Bool { if case .success = StageColorAdmission.identity(u) { return true }; return false }
var hdrOff = U(); hdrOff.srcPeakNits = 4000; hdrOff.dstPeakNits = 100
check("N6 off HDR plan not inferred as a down-map", admitted(hdrOff))
var software = U(); software.flags = 1
check("N6 software request not ignored", { if case .failure(.softwareToneMapperUnavailable) = StageColorAdmission.identity(software) { return true }; return false }())
var gamut = U(); gamut.flags = 2
check("N6 relative gamut not ignored", { if case .failure(.gamutConversionUnavailable) = StageColorAdmission.identity(gamut) { return true }; return false }())
var tone = U(); tone.toneCurveID = 2
check("N6 mobius refuses invented knee", { if case .failure(.p12PixelMappingUnavailable) = StageColorAdmission.identity(tone) { return true }; return false }())
check("N6 P12 HDR policy is shipped profile", P12Profile.hdr.toneMapping == "mobius" && P12Profile.hdr.targetTransfer == "bt.1886" && P12Profile.hdr.saturationAdjustment == -10 && P12Profile.hdr.gamutMapping == "perceptual" && !P12Profile.hdr.computeDynamicPeak && P12Profile.hdr.requiresICC)
check("N6 P12 DV not generic HDR mobius", P12Profile.dolbyVision.toneMapping == "auto" && P12Profile.dolbyVision.targetTransfer == "pq" && !P12Profile.dolbyVision.requiresICC)

print(failures == 0 ? "hosttransform-tests: all pass" : "hosttransform-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
