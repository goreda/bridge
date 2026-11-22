import Foundation
// Linux driver for StereoSource. hint <name> | meta <path> <type> <kind> <inverted 0/1> <sphericalStereo|-> <profile|-> <tag|-> | confirm <layout> <w> <h> <rgbfile>
let a = CommandLine.arguments
func show(_ v: StereoVerdict?) { print(v.map { "\($0.layout.rawValue) \($0.swap) \($0.source.rawValue)" } ?? "none") }
switch a.count > 1 ? a[1] : "" {
case "hint": show(StereoSource.filenameCandidate(a[2]))
case "meta":
    let sd = StereoSideData(type: a[3], kind: a[4], inverted: a[5] == "1", sphericalStereoMode: a[6] == "-" ? nil : a[6])
    show(StereoSource.metadataVerdict(path: a[2], sideData: [sd], profile: a[7] == "-" ? "" : a[7], codecTag: a[8] == "-" ? "" : a[8]))
case "confirm":
    guard let lay = StereoLayout(rawValue: a[2]), let w = Int(a[3]), let h = Int(a[4]), let d = FileManager.default.contents(atPath: a[5]), let r = StereoSource.eyeRects(lay, w: w, h: h) else { exit(2) }
    let px = [UInt8](d)
    func eye(_ q: (x: Int, y: Int, w: Int, h: Int)) -> [Float] {
        var g = [Float](); for y in 0..<q.h { for x in 0..<q.w { let i = ((q.y + y) * w + q.x + x) * 3; g.append(StereoSource.grey(r: px[i], g: px[i + 1], b: px[i + 2])) } }; return g
    }
    let c = StereoSource.confirm(leftGrey: eye(r.l), rightGrey: eye(r.r), w: r.l.w, h: r.l.h)
    print(c.isStereo, String(format: "%.6f", c.hpNCC), c.shift)
case "ffprobe":
    guard let d = FileManager.default.contents(atPath: a[3]), let f = StereoSource.parseFFprobe(d) else { print("parsefail"); exit(0) }
    show(StereoSource.metadataVerdict(path: a[2], sideData: f.sideData, profile: f.profile, codecTag: f.codecTag))
case "disp":
    guard let w = Int(a[2]), let h = Int(a[3]), let d = FileManager.default.contents(atPath: a[4]) else { exit(2) }
    let px = [UInt8](d), half = w / 2
    func eye(_ x0: Int) -> [Float] { var g = [Float](); for y in 0..<h { for x in 0..<half { let i = (y * w + x0 + x) * 3; g.append(StereoSource.grey(r: px[i], g: px[i + 1], b: px[i + 2])) } }; return g }
    if let m = StereoSource.measureDisparity(leftGrey: eye(0), rightGrey: eye(half), w: half, h: h) {
        print(String(format: "%.6f %.6f %.6f %.6f %.6f", m.pxP50, m.pxP99, m.degP99, m.overBudgetFrac, m.coverage))
    } else { print("nil") }
default:
    // route table
    let v = StereoVerdict(layout: .sbs, swap: false, source: .filename)
    let hv = StereoVerdict(layout: .halfSBS, swap: false, source: .metadata)
    print(StereoSource.route(verdict: hv, pixelConfirmed: nil, override: nil), StereoSource.route(verdict: nil, pixelConfirmed: nil, override: .layout(.halfOU, swap: false)))
    print(StereoSource.route(verdict: v, pixelConfirmed: nil, override: nil), StereoSource.route(verdict: v, pixelConfirmed: true, override: nil),
          StereoSource.route(verdict: v, pixelConfirmed: true, override: .flat), StereoSource.route(verdict: nil, pixelConfirmed: nil, override: .layout(.ou, swap: true)),
          StereoSource.route(verdict: StereoVerdict(layout: .mvhevc, swap: false, source: .metadata), pixelConfirmed: nil, override: nil))
}
