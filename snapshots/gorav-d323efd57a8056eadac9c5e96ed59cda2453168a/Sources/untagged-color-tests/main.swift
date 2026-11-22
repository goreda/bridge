import Foundation
import GorAVPlaybackCore

// untagged-color-tests (arch-196x item 2, v4.4 amendment, lane b): Linux proof
// of the mpv-parity colour policy for the DIRECT 8-bit lease path, plus the
// matrix-parameterized RGB stage it drives.
//
//   1. guessMatrix boundaries: bt709 at width >= 1280 or height > 576, else
//      bt601 (the default mpv path's guess), both branches and edges.
//   2. resolveDirectMatrix: tagged matrix wins at any resolution; untagged +
//      no HDR side data guesses; HDR side data / HDR transfer / unknown tags /
//      unmapped matrix names stay UNRESOLVED (nil = facade fallback-to-mpv).
//   3. Converter goldens: byte-exact RGBA for known YUV triples under both
//      matrices (golden values computed independently with Python's integer
//      arithmetic on the documented fixed-point formula, 2026-11-16).
//   4. Regression: the refactored converter's .bt601 output is byte-identical
//      to the legacy hard-coded formula, and the defaulted `matrix:` keeps
//      existing callers byte-identical.
//   5. Negative control: a deliberately wrong golden is caught (the suite can
//      fail), then the suite's own totals are reported honestly.
//
// Marker line: `untagged-color-tests: <N> PASS, 0 FAIL`. Exit 0 = all green.

var passCount = 0
var failCount = 0
func check(_ name: String, _ cond: Bool) {
    if cond { passCount += 1; print("PASS \(name)") }
    else { failCount += 1; print("FAIL \(name)") }
}

// MARK: 1. guessMatrix boundaries (mpv: bt709 if w >= 1280 or h > 576 else bt601)
check("guess 1920x1080 -> bt709", UntaggedColorPolicy.guessMatrix(width: 1920, height: 1080) == .bt709)
check("guess 1280x720 -> bt709 (width edge)", UntaggedColorPolicy.guessMatrix(width: 1280, height: 720) == .bt709)
check("guess 1279x720 -> bt709 (height > 576)", UntaggedColorPolicy.guessMatrix(width: 1279, height: 720) == .bt709)
check("guess 1280x576 -> bt709 (width edge, height at 576)", UntaggedColorPolicy.guessMatrix(width: 1280, height: 576) == .bt709)
check("guess 4x577 -> bt709 (height edge)", UntaggedColorPolicy.guessMatrix(width: 4, height: 577) == .bt709)
check("guess 1279x576 -> bt601 (both under)", UntaggedColorPolicy.guessMatrix(width: 1279, height: 576) == .bt601)
check("guess 720x576 -> bt601 (PAL)", UntaggedColorPolicy.guessMatrix(width: 720, height: 576) == .bt601)
check("guess 640x480 -> bt601", UntaggedColorPolicy.guessMatrix(width: 640, height: 480) == .bt601)

// MARK: 2. resolveDirectMatrix
func resolve(_ cs: String?, _ trc: String?, unknown: Bool = false, hdr: Bool = false,
             _ w: Int, _ h: Int) -> YUV420Converter.Matrix? {
    UntaggedColorPolicy.resolveDirectMatrix(colorSpace: cs, transfer: trc,
                                            anyTagUnknown: unknown, hasHDRSideData: hdr,
                                            width: w, height: h)
}
check("tagged bt709 wins at 320x240", resolve("bt709", "bt709", 320, 240) == .bt709)
check("tagged bt470bg wins at 1920x1080", resolve("bt470bg", "bt709", 1920, 1080) == .bt601)
check("tagged smpte170m wins at 1920x1080", resolve("smpte170m", "smpte170m", 1920, 1080) == .bt601)
check("tagged bt2020nc unresolved", resolve("bt2020nc", "bt709", 1920, 1080) == nil)
check("unmapped matrix name unresolved", resolve("fcc", "bt709", 1920, 1080) == nil)
check("untagged + mastering side data unresolved (HD)", resolve(nil, nil, hdr: true, 1920, 1080) == nil)
check("untagged + content-light side data unresolved (SD)", resolve(nil, nil, hdr: true, 640, 480) == nil)
check("decoder-unknown tag unresolved", resolve(nil, nil, unknown: true, 1920, 1080) == nil)
check("PQ transfer unresolved", resolve(nil, "smpte2084", 1920, 1080) == nil)
check("HLG transfer unresolved", resolve(nil, "arib-std-b67", 1920, 1080) == nil)
check("untagged clean 1920x1080 guesses bt709", resolve(nil, nil, 1920, 1080) == .bt709)
check("untagged clean 720x576 guesses bt601", resolve(nil, nil, 720, 576) == .bt601)
check("untagged with SDR transfer tag 1920x1080 guesses bt709", resolve(nil, "bt709", 1920, 1080) == .bt709)

// MARK: 3. Converter goldens (independently computed, both matrices)
func pixel(_ y: UInt8, _ u: UInt8, _ v: UInt8, _ m: YUV420Converter.Matrix) -> (UInt8, UInt8, UInt8, UInt8) {
    let yp = [y], up = [u], vp = [v]
    let rgba = yp.withUnsafeBufferPointer { yb in
        up.withUnsafeBufferPointer { ub in
            vp.withUnsafeBufferPointer { vb in
                YUV420Converter.rgbaFromYUV420p(y: yb.baseAddress!, yStride: 1,
                                                u: ub.baseAddress!, uStride: 1,
                                                v: vb.baseAddress!, vStride: 1,
                                                width: 1, height: 1, matrix: m)
            }
        }
    }
    return (rgba[0], rgba[1], rgba[2], rgba[3])
}
let goldens: [((UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8, UInt8))] = [
    // (Y,U,V)          bt601 RGBA          bt709 RGBA
    ((81, 90, 240),    (255, 0, 0, 255),   (255, 24, 0, 255)),
    ((128, 128, 128),  (130, 130, 130, 255), (130, 130, 130, 255)),
    ((41, 240, 110),   (0, 0, 255, 255),   (0, 15, 255, 255)),
    ((145, 54, 34),    (0, 255, 1, 255),   (0, 216, 0, 255)),
    ((200, 60, 200),   (255, 182, 77, 255), (255, 191, 70, 255)),
    ((16, 128, 128),   (0, 0, 0, 255),     (0, 0, 0, 255)),
    ((235, 128, 128),  (255, 255, 255, 255), (255, 255, 255, 255)),
    ((103, 200, 60),   (0, 128, 246, 255), (0, 122, 253, 255)),
]
for (i, g) in goldens.enumerated() {
    check("golden \(i) bt601", pixel(g.0.0, g.0.1, g.0.2, .bt601) == g.1)
    check("golden \(i) bt709", pixel(g.0.0, g.0.1, g.0.2, .bt709) == g.2)
}

// MARK: 4. bt601 regression: refactored == legacy hard-coded, default == explicit
func legacyRGBA(y: UInt8, u: UInt8, v: UInt8) -> (UInt8, UInt8, UInt8) {
    let c = Int(y) - 16, uv = Int(u) - 128, vv = Int(v) - 128
    func clamp8(_ x: Int) -> UInt8 { UInt8(Swift.max(0, Swift.min(255, x))) }
    return (clamp8((298 * c + 409 * vv + 128) >> 8),
            clamp8((298 * c - 100 * uv - 208 * vv + 128) >> 8),
            clamp8((298 * c + 516 * uv + 128) >> 8))
}
var lcg: UInt64 = 0x1961_DEAD_5EED_CAFE
func nextByte() -> UInt8 {
    lcg = lcg &* 6364136223846793005 &+ 1442695040888963407
    return UInt8(truncatingIfNeeded: lcg >> 33)
}
var regressionOK = true, defaultOK = true
for _ in 0..<4096 {
    let y = nextByte(), u = nextByte(), v = nextByte()
    let legacy = legacyRGBA(y: y, u: u, v: v)
    let refactored = pixel(y, u, v, .bt601)
    if (refactored.0, refactored.1, refactored.2) != legacy { regressionOK = false }
    // Defaulted matrix: the no-argument call must be byte-identical to .bt601.
    let yp = [y], up = [u], vp = [v]
    let defaulted = yp.withUnsafeBufferPointer { yb in
        up.withUnsafeBufferPointer { ub in
            vp.withUnsafeBufferPointer { vb in
                YUV420Converter.rgbaFromYUV420p(y: yb.baseAddress!, yStride: 1,
                                                u: ub.baseAddress!, uStride: 1,
                                                v: vb.baseAddress!, vStride: 1,
                                                width: 1, height: 1)
            }
        }
    }
    if (defaulted[0], defaulted[1], defaulted[2]) != legacy { defaultOK = false }
}
check("bt601 refactored == legacy hard-coded (4096 seeded pixels)", regressionOK)
check("defaulted matrix == explicit bt601 (caller byte-identity)", defaultOK)

// MARK: 5. Negative control: a wrong golden must fail
let wrongGoldenCaught = pixel(81, 90, 240, .bt709) != (255, 0, 0, 255) // that is the bt601 answer
check("negative control: bt601 golden rejected under bt709", wrongGoldenCaught)

// MARK: 6. P30/W2 VT zero-copy shader coefficients (arch-197b)
// The GPU conversion constants must implement the SAME limited-range /256
// family as the CPU oracle (YUV420Converter.rgbaFromYUV420p). The shader
// works on normalized samples, so the check reconstructs the 8-bit answer
// from the coefficients and compares against the CPU converter for a
// seeded pixel sweep; the 10-bit (P010) constants must be the 8-bit ones
// scaled by 255/1023 with 10-bit centers.
func approx(_ a: Float, _ b: Float, _ eps: Float = 0.0001) -> Bool { abs(a - b) <= eps }
let c8_601 = VTYUVToRGBCoefficients.resolve(matrix: .bt601, bitDepth: 8)
check("W2 8-bit yGain == 298/256", approx(c8_601.yGain, 298.0 / 256.0))
check("W2 8-bit bt601 crv == 409/256", approx(c8_601.crvGain, 409.0 / 256.0))
check("W2 8-bit bt601 cgu == 100/256", approx(c8_601.cguGain, 100.0 / 256.0))
check("W2 8-bit bt601 cgv == 208/256", approx(c8_601.cgvGain, 208.0 / 256.0))
check("W2 8-bit bt601 cbu == 516/256", approx(c8_601.cbuGain, 516.0 / 256.0))
check("W2 8-bit yCenter == 16/255", approx(c8_601.yCenter, 16.0 / 255.0))
check("W2 8-bit cCenter == 128/255", approx(c8_601.cCenter, 128.0 / 255.0))
check("W2 8-bit p010Scale == 1", approx(c8_601.p010Scale, 1.0))
let c8_709 = VTYUVToRGBCoefficients.resolve(matrix: .bt709, bitDepth: 8)
check("W2 8-bit bt709 crv == 459/256", approx(c8_709.crvGain, 459.0 / 256.0))
check("W2 8-bit bt709 cgu == 55/256", approx(c8_709.cguGain, 55.0 / 256.0))
check("W2 8-bit bt709 cgv == 136/256", approx(c8_709.cgvGain, 136.0 / 256.0))
check("W2 8-bit bt709 cbu == 541/256", approx(c8_709.cbuGain, 541.0 / 256.0))
let c10 = VTYUVToRGBCoefficients.resolve(matrix: .bt709, bitDepth: 10)
check("W2 10-bit yGain == 298/256 * 255/1023", approx(c10.yGain, (298.0 / 256.0) * (255.0 / 1023.0)))
check("W2 10-bit yCenter == 64/1023", approx(c10.yCenter, 64.0 / 1023.0))
check("W2 10-bit cCenter == 512/1023", approx(c10.cCenter, 512.0 / 1023.0))
check("W2 10-bit p010Scale == 65535/65472", approx(c10.p010Scale, 65535.0 / 65472.0))
// Seeded pixel sweep: coefficients reproduce the CPU oracle within +/-1
// (the oracle rounds via +128 >> 8 fixed-point; the float path rounds).
var coeffMatch = true
var seedW2: UInt32 = 0xC0FFEE
for _ in 0..<4096 {
    seedW2 = seedW2 &* 1664525 &+ 1013904223; let y = UInt8(seedW2 >> 24)
    seedW2 = seedW2 &* 1664525 &+ 1013904223; let u = UInt8(seedW2 >> 24)
    seedW2 = seedW2 &* 1664525 &+ 1013904223; let v = UInt8(seedW2 >> 24)
    for (m, co) in [(YUV420Converter.Matrix.bt601, c8_601), (YUV420Converter.Matrix.bt709, c8_709)] {
        let cpu = pixel(y, u, v, m)
        let yf = Float(y) / 255.0, uf = Float(u) / 255.0, vf = Float(v) / 255.0
        let yc = co.yGain * (yf - co.yCenter)
        let uc = uf - co.cCenter, vc = vf - co.cCenter
        let rf = yc + co.crvGain * vc
        let gf = yc - co.cguGain * uc - co.cgvGain * vc
        let bf = yc + co.cbuGain * uc
        // The shader clamps to [0,1]; the oracle clamps to [0,255]. Compare
        // AFTER the same clamp, else out-of-range inputs differ by design.
        func cl(_ x: Float) -> Int { Int((min(1.0, max(0.0, x)) * 255.0).rounded()) }
        let r = cl(rf), g = cl(gf), b = cl(bf)
        if abs(r - Int(cpu.0)) > 1 || abs(g - Int(cpu.1)) > 1 || abs(b - Int(cpu.2)) > 1 { coeffMatch = false }
    }
}
check("W2 coefficients reproduce CPU oracle within +/-1 (4096 seeded pixels x2 matrices)", coeffMatch)

print("untagged-color-tests: \(passCount) PASS, \(failCount) FAIL")
exit(failCount == 0 ? 0 : 1)
