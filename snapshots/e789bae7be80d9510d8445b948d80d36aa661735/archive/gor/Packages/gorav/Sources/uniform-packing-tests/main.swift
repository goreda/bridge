import Foundation
import GorAVPlaybackCore

// Witness for 195c-N6 uniform packing: exact 64-byte stream, field offsets,
// little-endian encoding, Float bit patterns - the contract the Metal upload
// and the MSL struct both follow.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func readF(_ b: [UInt8], _ off: Int) -> Float {
    let v = UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24
    return Float(bitPattern: v)
}
func readU(_ b: [UInt8], _ off: Int) -> UInt32 {
    UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24
}

var u = FrameUniforms()
u.frameWidth = 1920; u.frameHeight = 1080; u.fitModeID = 7
u.cropX = 0.25; u.cropY = 0.125; u.cropW = 0.5; u.cropH = 0.75
u.panX = -0.5; u.panY = 0.25; u.log2Zoom = 2; u.flags = 3
u.toneCurveID = 2; u.srcPeakNits = 4000; u.dstPeakNits = 100; u.saturation = 0.8
let b = u.packedBytes()

check("T1-count", b.count == 64)
check("T2-control", readF(b, 0) == 1920 && readF(b, 4) == 1080 && readU(b, 8) == 7 && readU(b, 12) == 0)
check("T3-crop", readF(b, 16) == 0.25 && readF(b, 20) == 0.125 && readF(b, 24) == 0.5 && readF(b, 28) == 0.75)
check("T4-host", readF(b, 32) == -0.5 && readF(b, 36) == 0.25 && readF(b, 40) == 2 && readU(b, 44) == 3)
check("T5-color", readU(b, 48) == 2 && readF(b, 52) == 4000 && readF(b, 56) == 100 && abs(readF(b, 60) - 0.8) < 1e-6)

// T6: offsets table matches the packer (guard against drift)
check("T6-offsets", FrameUniforms.Offsets.cropX == 16 && FrameUniforms.Offsets.panX == 32
      && FrameUniforms.Offsets.flags == 44 && FrameUniforms.Offsets.saturation == 60)

// T7: identity block packs deterministically (two packs equal)
check("T7-deterministic", FrameUniforms().packedBytes() == FrameUniforms().packedBytes()
      && FrameUniforms().packedBytes().count == 64)

// T8: little-endian sanity on a known value: 1.0f = 0x3F800000 -> bytes 00 00 80 3F
var u8 = FrameUniforms(); u8.frameWidth = 1
let b8 = u8.packedBytes()
check("T8-endian", b8[0] == 0x00 && b8[1] == 0x00 && b8[2] == 0x80 && b8[3] == 0x3F)

// T9: flags bits survive (software fallback bit0, gamut bit1)
var u9 = FrameUniforms(); u9.flags = 1
check("T9-flags", readU(u9.packedBytes(), 44) == 1)

print("uniform-packing-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
