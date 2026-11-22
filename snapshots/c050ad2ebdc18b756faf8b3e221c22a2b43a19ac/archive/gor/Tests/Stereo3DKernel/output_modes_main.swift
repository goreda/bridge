import Foundation
// Linux driver for OutputModes: prints "mode W H eyeW eyeH stereo sar spherical pack" for a source w x h.
let a = CommandLine.arguments
guard a.count >= 3, let w = Int(a[1]), let h = Int(a[2]) else { exit(2) }
for m in OutputMode.allCases {
    let c = m.canvasSize(srcW: w, srcH: h), e = m.eyeSize(srcW: w, srcH: h)
    print(m.rawValue, c.w, c.h, e.w, e.h, m.mpvStereoMode ?? "-", m.playbackSARStretch, m.sphericalV2, m.packCode)
}
print("parse", OutputMode.parse("sbs")?.rawValue ?? "nil", OutputMode.parse("vr180")?.rawValue ?? "nil", OutputMode.parse("bogus")?.rawValue ?? "nil")
print("default", OutputMode.defaultMode(headset: false).rawValue, OutputMode.defaultMode(headset: true).rawValue)
