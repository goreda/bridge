// ThreeD/Source.swift - 3D station "Source": source format, probing, stereo source gate, crop sampling and recognition.
// Move-only split of the former ThreeD.swift (arch-199s). The sections below are byte-identical to their former BEGIN/END spans,
// in their original relative order. The import list is the union of the former file (a deliberate superset; narrow it only with a Darwin compile).
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Accelerate)
import Accelerate
#endif
import AppKit
#if canImport(Compression)
import Compression
#endif
import CoreGraphics
#if canImport(CoreML)
import CoreML
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Darwin
import Foundation
#if canImport(Glibc)
import Glibc
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Metal)
import Metal
#endif
import QuartzCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(Vision)
import Vision
#endif

// BEGIN relocated ThreeDRecognitionBridge.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// Platform evidence and one-time legacy import. No legacy state is used after migrationComplete.
enum ThreeDRecognitionBridge {
    private static var torrentInputs:[String:ThreeDFilmIdentity]=[:]
    @MainActor static func bindTorrent(path:String,infohash:String,index:Int,basename:String,size:Int64) {
        torrentInputs[path]=ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:infohash,fileIndex:index,basename:basename,finalSize:size,normalizedURL:nil)
    }
    @MainActor static func resolveAtOpen(path:String)->FilmID {ThreeDStore.shared.unbindSource(path:path);return filmID(path:path)}
    @MainActor static func filmID(path:String)->FilmID {
        if let bound=ThreeDStore.shared.id(for:path) {return bound}
        if let torrent=torrentInputs[path] {return ThreeDStore.shared.resolveIdentity(path:path,input:torrent)}
        let url=URL(fileURLWithPath:path).resolvingSymlinksInPath().standardizedFileURL
        if !path.contains("://"),!path.lowercased().hasPrefix("magnet:"),
           let values=try? url.resourceValues(forKeys:[.volumeUUIDStringKey]),let volume=values.volumeUUIDString,
           let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),let inode=attrs[.systemFileNumber] as? NSNumber {
            return ThreeDStore.shared.resolveIdentity(path:path,input:ThreeDFilmIdentity(volume:volume,fileID:inode.stringValue,infohash:nil,fileIndex:nil,basename:url.lastPathComponent,finalSize:(attrs[.size] as? NSNumber)?.int64Value,normalizedURL:nil))
        }
        return ThreeDStore.shared.resolveIdentity(path:path,input:ThreeDFilmIdentity(volume:nil,fileID:nil,infohash:nil,fileIndex:nil,basename:url.lastPathComponent,finalSize:nil,normalizedURL:path.contains(":") ? VRRecognition.fileIdentity(path):nil))
    }
    static func source(projection:String?,sbs:Bool,tb:Bool,filename path:String="")->ThreeDSource? {
        // Packing metadata is not a spherical-projection verdict. An explicit
        // VR180 filename survives generic SBS/TB metadata; explicit spherical
        // or unsupported projection metadata still owns its own verdict.
        if projection == nil || projection == "flat-sbs" || projection == "flat-tb",
           let tagged=filename(path), tagged.nativeVR {return tagged}
        switch projection {
        case "vr180": return ThreeDSource(tb ? .vr180TB:.vr180SBS)
        case "vr180-tb": return ThreeDSource(.vr180TB)
        case "vr360-mono": return ThreeDSource(tb ? .vr360TB:.vr360Mono)
        case "vr360-tb": return ThreeDSource(.vr360TB)
        case "unsupported": return nil
        case "flat-sbs": return ThreeDSource(.sbsFull)
        case "flat-tb": return ThreeDSource(.tbFull)
        default: return sbs ? ThreeDSource(.sbsFull):(tb ? ThreeDSource(.tbFull):nil)
        }
    }
    static func filename(_ path:String)->ThreeDSource? {
        let name=URL(fileURLWithPath:path).lastPathComponent.lowercased()
        func tag(_ pattern:String)->Bool {name.range(of:pattern,options:.regularExpression) != nil}
        let tb=tag(#"(?:^|[^a-z0-9])(?:tb|ou|htb|ftb)(?:[^a-z0-9]|$)"#)
        if tag(#"(?:^|[^a-z0-9])(?:vr180|180|3dh)(?:x180|sbs|lr)?(?:[^a-z0-9]|$)"#) {return ThreeDSource(tb ? .vr180TB:.vr180SBS)}
        if tag(#"(?:^|[^a-z0-9])(?:vr360|360)(?:[^a-z0-9]|$)"#) {return ThreeDSource(tb ? .vr360TB:.vr360Mono)}
        if tag(#"(?:^|[^a-z0-9])(?:sbs|hsbs|fsbs|lr)(?:[^a-z0-9]|$)"#) {return ThreeDSource(name.contains("hsbs") ? .sbsHalf:.sbsFull)}
        if tb {return ThreeDSource(.tbFull)}
        return nil
    }
    static func internalMedia(_ path:String)->Bool {
        path.hasPrefix(DepthCachePaths.root.path+"/") && URL(fileURLWithPath:path).lastPathComponent.range(of:#"^(?:render|source)_shot_[0-9]+\.mp4$"#,options:.regularExpression) != nil
    }
    @MainActor static func migrate(_ defaults:UserDefaults = .standard) {
        guard !ThreeDStore.shared.snapshot.migrationComplete else {return}
        var imported:[FilmID:FilmThreeD]=[:]
        // Only provenance-bearing explicit choices are importable. Historical projection caches
        // mixed detection and user writes, so they are deliberately left untouched, not guessed.
        let explicit=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1.explicitMenuOutput.v2") as? [String:String] ?? [:]
        let sources=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1") as? [String:String] ?? [:]
        let outputs=defaults.dictionary(forKey:"gor.3d.sourceByFilm.v1.output") as? [String:String] ?? [:]
        for (path,grant) in explicit {
            let value=outputs[path] ?? "off"
            guard value=="off" || value==grant,let output=ThreeDOutput(rawValue:value),!internalMedia(path) else {continue}
            var film=FilmThreeD();film.source=SourceFormatChoice.source(sources[path] ?? "flat")
            film.output=output;film.lastOutput=output == .off ? (ThreeDOutput(rawValue:grant) ?? .sbs):output;film.userTouched=true
            imported[SourceFormatChoice.filmID(path)]=film
        }
        ThreeDStore.shared.migrateExplicit(imported)
        print("3D-DECISION migration=complete imported=\(imported.count) reason=explicit_provenance_only legacy_values_preserved=true")
    }
}
// END relocated ThreeDRecognitionBridge.swift
// BEGIN relocated StereoSource.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s37 port of tools/depth_analysis/stereo_probe.py (layers 1-3): detect sources that are ALREADY 3D so they never go through 2D->3D depth.
/// Pure Foundation (compiled and run on Linux, Tests/StereoSource). Layer 1 = container metadata (authoritative), layer 2 = filename (a CANDIDATE layout only, never a verdict),
/// layer 3 = pixel confirm: high-passed grey NCC over horizontal shifts, threshold 0.4. The menu override (force 2D->3D / force a layout) wins over all three layers.
enum StereoLayout: String, CaseIterable {
    case sbs, halfSBS = "half_sbs", ou, halfOU = "half_ou", vr180, mvhevc
}

struct StereoSideData: Equatable {
    var type = ""                    // ffprobe side_data_type, e.g. "Stereo 3D" or "Spherical Mapping"
    var kind = ""                    // "Stereo 3D" `type`, e.g. "side by side", "top_bottom"
    var inverted = false
    var sphericalStereoMode: String? = nil   // Spherical Video V2 stereo_mode: "left-right" / "right-left"
}

struct StereoVerdict: Equatable {
    enum Source: String { case metadata, filename }
    var layout: StereoLayout
    var swap: Bool
    var source: Source
}

enum StereoSource {
    static let hpThreshold = 0.4

    static let stereoModeMap: [String: (StereoLayout, Bool)] = [
        "side by side": (.sbs, false), "side by side (quincunx)": (.sbs, false), "top and bottom": (.ou, false), "left_right": (.sbs, false),
        "right_left": (.sbs, true), "top_bottom": (.ou, false), "bottom_top": (.ou, true)]
    static let sphericalMap: [String: (StereoLayout, Bool)] = ["left-right": (.vr180, false), "right-left": (.vr180, true)]
    // Same alternatives and order as stereo_probe.HINT_RE (first match wins). ICU regex: lookbehind is supported.
    static let hints: [(String, StereoLayout)] = [
        ("(?<![a-z])(h[-_.]?sbs|half[-_.]?sbs)(?![a-z])", .halfSBS), ("(?<![a-z])(f[-_.]?sbs|full[-_.]?sbs|sbs|lr[-_.]?3d)(?![a-z])", .sbs),
        ("(?<![a-z])(h[-_.]?ou|half[-_.]?ou|half[-_.]?tb)(?![a-z])", .halfOU), ("(?<![a-z])(ou|over[-_.]?under|tb|top[-_.]?bottom)(?![a-z])", .ou),
        ("(?<![a-z])(vr180|180[-_.]?3d|3d[-_.]?180)(?![a-z])", .vr180)]

    /// Layer 1 (+ weak layer 2): the first metadata match wins; a filename hit is returned with source .filename (a candidate, the caller must pixel-confirm it).
    static func metadataVerdict(path: String, sideData: [StereoSideData], profile: String, codecTag: String) -> StereoVerdict? {
        for sd in sideData {
            if sd.type == "Stereo 3D", let (lay, sw) = stereoModeMap[sd.kind] { return StereoVerdict(layout: lay, swap: sw != sd.inverted, source: .metadata) }
            if sd.type.contains("pherical"), let m = sd.sphericalStereoMode, let (lay, sw) = sphericalMap[m] { return StereoVerdict(layout: lay, swap: sw, source: .metadata) }
        }
        if profile.lowercased().contains("multiview") || codecTag.lowercased().hasPrefix("mv-") { return StereoVerdict(layout: .mvhevc, swap: false, source: .metadata) }
        return filenameCandidate(path)
    }

    /// ffprobe `-show_streams -of json` -> (side data, profile, codec tag) of the first stream: the same fields stereo_probe._ffprobe/metadata_verdict read.
    static func parseFFprobe(_ data: Data) -> (sideData: [StereoSideData], profile: String, codecTag: String)? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let st = (o["streams"] as? [[String: Any]])?.first else { return nil }
        let sd = (st["side_data_list"] as? [[String: Any]] ?? []).map { d -> StereoSideData in
            StereoSideData(type: d["side_data_type"] as? String ?? "", kind: d["type"] as? String ?? "", inverted: ((d["inverted"] as? NSNumber)?.intValue ?? 0) != 0, sphericalStereoMode: d["stereo_mode"] as? String)
        }
        return (sd, st["profile"] as? String ?? "", st["codec_tag_string"] as? String ?? "")
    }

    static func filenameCandidate(_ path: String) -> StereoVerdict? {
        let name = (path as NSString).lastPathComponent.lowercased()
        for (rx, lay) in hints where name.range(of: rx, options: .regularExpression) != nil { return StereoVerdict(layout: lay, swap: false, source: .filename) }
        return nil
    }

    /// Eye rectangles (x, y, w, h) of a frame w x h. Half layouts return the NATIVE half-size halves (the Python reference upsamples them with cv2 cubic first;
    /// the pixel confirm here runs on the native halves, same threshold: not parity-tested for half layouts).
    static func eyeRects(_ layout: StereoLayout, w: Int, h: Int) -> (l: (x: Int, y: Int, w: Int, h: Int), r: (x: Int, y: Int, w: Int, h: Int))? {
        switch layout {
        case .sbs, .vr180, .halfSBS: return ((0, 0, w / 2, h), (w / 2, 0, w / 2, h))
        case .ou, .halfOU: return ((0, 0, w, h / 2), (0, h / 2, w, h / 2))
        case .mvhevc: return nil
        }
    }

    /// cv2.cvtColor(RGB2GRAY) on uint8 (fixed point, round half up) -> Float.
    static func grey(r: UInt8, g: UInt8, b: UInt8) -> Float { Float((UInt32(r) * 4899 + UInt32(g) * 9617 + UInt32(b) * 1868 + 8192) >> 14) }

    /// grey minus a sigma-3 Gaussian blur (19 taps, normalised, reflect-101 borders: cv2.GaussianBlur(g, (0, 0), 3.0) on float32).
    static func highPass(_ g: [Float], w: Int, h: Int, sigma: Double = 3.0) -> [Float] {
        let r = Int((sigma * 6 + 1).rounded()) | 1, half = r / 2
        var k = (0..<r).map { exp(-pow(Double($0 - half), 2) / (2 * sigma * sigma)) }
        let s = k.reduce(0, +); k = k.map { $0 / s }
        let kf = k.map { Float($0) }
        func refl(_ i: Int, _ n: Int) -> Int { var j = i; if n == 1 { return 0 }; while j < 0 || j >= n { j = j < 0 ? -j : 2 * (n - 1) - j }; return j }
        var tmp = [Float](repeating: 0, count: w * h), out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { var a: Float = 0; for t in 0..<r { a += kf[t] * g[y * w + refl(x + t - half, w)] }; tmp[y * w + x] = a } }
        for y in 0..<h { for x in 0..<w { var a: Float = 0; for t in 0..<r { a += kf[t] * tmp[refl(y + t - half, h) * w + x] }; out[y * w + x] = g[y * w + x] - a } }
        return out
    }

    private static func ncc(_ a: [Float], _ b: [Float]) -> Double {
        if a.isEmpty { return -1 }
        let n = Double(a.count)
        var ma = 0.0, mb = 0.0
        for i in 0..<a.count { ma += Double(a[i]); mb += Double(b[i]) }
        ma /= n; mb /= n
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in 0..<a.count { let x = Double(a[i]) - ma, y = Double(b[i]) - mb; cov += x * y; va += x * x; vb += y * y }
        return (cov / n) / ((va / n).squareRoot() * (vb / n).squareRoot() + 1e-6)
    }

    /// stereo_probe.best_shift_ncc on already high-passed halves: (best hp NCC, shift px).
    static func bestShift(hl: [Float], hr: [Float], w: Int, h: Int, maxShift: Int? = nil) -> (ncc: Double, shift: Int) {
        let ms = maxShift ?? w / 5
        var best = -1.0, bd = 0
        for d in -ms...ms {
            let cols = w - abs(d)
            if cols < w / 3 { continue }
            var x = [Float](), y = [Float](); x.reserveCapacity(cols * h); y.reserveCapacity(cols * h)
            for row in 0..<h {
                let lo = d >= 0 ? d : 0, ro = d >= 0 ? 0 : -d
                for c in 0..<cols { x.append(hl[row * w + lo + c]); y.append(hr[row * w + ro + c]) }
            }
            let v = ncc(x, y)
            if v > best { best = v; bd = d }
        }
        return (best, bd)
    }

    /// Layer 3 on RGBA/BGRA-agnostic grey input: `grey` is the w x h grey frame of ONE eye each (already extracted by eyeRects). Returns (isStereo, hpNCC, shift).
    static func confirm(leftGrey: [Float], rightGrey: [Float], w: Int, h: Int) -> (isStereo: Bool, hpNCC: Double, shift: Int) {
        let b = bestShift(hl: highPass(leftGrey, w: w, h: h), hr: highPass(rightGrey, w: w, h: h), w: w, h: h)
        return (b.ncc >= hpThreshold, b.ncc, b.shift)
    }

    /// Final routing. `override` (menu) wins over everything: .flat forces 2D->3D, .layout forces a stereo format.
    enum Override: Equatable { case flat, layout(StereoLayout, swap: Bool) }
    /// playAsIs: a confirmed stereo source we cannot repack yet (half layouts need an upscale pass): never sent to 2D->3D depth, played as the file is.
    enum Route: Equatable { case depth, passthrough(StereoLayout, swap: Bool), nativeNote, playAsIs }
    static func route(verdict: StereoVerdict?, pixelConfirmed: Bool?, override: Override?) -> Route {
        if let o = override { switch o { case .flat: return .depth; case .layout(let l, let s): return l == .mvhevc ? .nativeNote : (l == .halfSBS || l == .halfOU ? .playAsIs : .passthrough(l, swap: s)) } }
        guard let v = verdict else { return .depth }
        if v.layout == .mvhevc { return .nativeNote }
        let confirmed = v.source == .metadata || pixelConfirmed == true      // filename alone never routes
        guard confirmed else { return .depth }
        return v.layout == .halfSBS || v.layout == .halfOU ? .playAsIs : .passthrough(v.layout, swap: v.swap)
    }

    struct Disparity: Equatable {
        var pxP50 = 0.0, pxP99 = 0.0, degP50 = 0.0, degP95 = 0.0, degP99 = 0.0, overBudgetFrac = 0.0, coverage = 0.0, assumeHFOVDeg = 90.0
    }
    static let comfortBudgetDeg = 2.0

    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {      // numpy.percentile, linear interpolation
        let pos = q / 100 * Double(sorted.count - 1), lo = Int(pos.rounded(.down)), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }
    private static func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }

    /// stereo_probe.measure_disparity: WARN-ONLY comfort check of baked-in disparity (32 px blocks, +-W/8 search, high-passed grey, MAD outlier rejection). nil = unmeasurable
    /// (too few blocks lock) or the eye is narrower than 256 px (the Python upscales first with cv2 cubic; not ported: real sources are wider). A warn never blocks the passthrough.
    static func measureDisparity(leftGrey: [Float], rightGrey: [Float], w: Int, h: Int, assumeHFOVDeg: Double = 90, block: Int = 32, nccMin: Double = 0.5) -> Disparity? {
        guard w >= 256, h >= block else { return nil }
        let gl = highPass(leftGrey, w: w, h: h), gr = highPass(rightGrey, w: w, h: h), span = w / 8
        var vals = [Double](), total = 0
        var y = 0
        while y <= h - block {
            var x = 0
            while x <= w - block {
                total += 1
                var bl = [Float](); bl.reserveCapacity(block * block)
                for r in 0..<block { for c in 0..<block { bl.append(gl[(y + r) * w + x + c]) } }
                let m = bl.reduce(0, { $0 + Double($1) }) / Double(bl.count)
                let sd = (bl.reduce(0.0, { $0 + (Double($1) - m) * (Double($1) - m) }) / Double(bl.count)).squareRoot()
                if sd >= 1e-3 {
                    var best = -1.0, bd = 0
                    for d in -span...span {
                        let xs = x + d
                        if xs < 0 || xs + block > w { continue }
                        var rb = [Float](); rb.reserveCapacity(block * block)
                        for r in 0..<block { for c in 0..<block { rb.append(gr[(y + r) * w + xs + c]) } }
                        let v = ncc(bl, rb)
                        if v > best { best = v; bd = d }
                    }
                    if best >= nccMin { vals.append(Double(bd)) }
                }
                x += block / 2
            }
            y += block / 2
        }
        guard Double(vals.count) >= max(8, Double(total) * 0.05) else { return nil }
        let med = median(vals), mad = median(vals.map { abs($0 - med) }) + 1
        let kept = vals.filter { abs($0 - med) <= 4 * mad }.map { abs($0) }.sorted()
        guard !kept.isEmpty else { return nil }
        let dpp = assumeHFOVDeg / Double(w), p50 = percentile(kept, 50), p95 = percentile(kept, 95), p99 = percentile(kept, 99)
        return Disparity(pxP50: p50, pxP99: p99, degP50: p50 * dpp, degP95: p95 * dpp, degP99: p99 * dpp,
                         overBudgetFrac: Double(kept.filter { $0 * dpp > comfortBudgetDeg }.count) / Double(kept.count), coverage: Double(vals.count) / Double(total), assumeHFOVDeg: assumeHFOVDeg)
    }
}
// END relocated StereoSource.swift
// BEGIN relocated StereoSourceGate.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(CoreGraphics)
import AVFoundation
import CoreGraphics

/// 190v s37 wiring: decides per film whether the 2D->3D depth prepare may run. A source that is already 3D never goes through depth (route != .depth): it plays as the file is
/// (the player's flat sbs/tb path) and the OSD says so once. The decision is cached per path and computed off the main thread (ffprobe + at most one frame grab); until it is known
/// `route(for:)` returns nil and the caller treats the film as "not yet": no prepare starts. Override (UserDefaults gor.3d.stereoSource: "auto", "flat" = force 2D->3D, or a layout
/// rawValue = force that stereo format) wins over all three layers. UNCOMPILED on a Mac; the decision logic itself is StereoSource (Linux-tested).
final class StereoSourceGate {
    static let shared = StereoSourceGate()
    static let overrideKey = "gor.3d.stereoSource"
    private let q = DispatchQueue(label: "gor.stereo-source", qos: .utility), lock = NSLock()
    private var cache: [String: (route: StereoSource.Route, note: String)] = [:], pending = Set<String>()
    private var told = Set<String>()
    /// true the first time this (film, note) pair is asked for (the timer ticks every 3 s: the OSD line shows once per film).
    func once(film: URL, note: String) -> Bool { lock.lock(); defer { lock.unlock() }; return told.insert(film.path + "|" + note).inserted }
    var resolvedSource:(URL)->String? = {_ in nil}
    var ffprobe: () -> String = { GORResources.vendorPath("ffmpeg/bin/ffprobe") }

    static func override(_ d: UserDefaults = .standard,source:String?=nil) -> StereoSource.Override? {
        guard let v=source,v != "auto" else{return nil}
        if v == "flat" { return .flat }
        if v.hasSuffix(":swap"), let l = StereoLayout(rawValue: String(v.dropLast(5))) { return .layout(l, swap: true) }
        return StereoLayout(rawValue: v).map { .layout($0, swap: false) }
    }

    /// nil = still deciding. The cache key includes the override so changing it re-decides at once.
    func route(for film: URL, defaults: UserDefaults = .standard) -> (route: StereoSource.Route, note: String)? {
        let manual=SourceFormatChoice.get(film.path,defaults)
        if manual.hasPrefix("vr180") || manual.hasPrefix("vr360") {return (.playAsIs,"3D: native spherical source, no depth conversion")}
        if manual=="auto",let kind=resolvedSource(film),kind != "mono",kind != "2d" {return (.playAsIs,"3D: native stereo source, no depth conversion")}
        let source=SourceFormatChoice.get(film.path,defaults),ov=Self.override(defaults,source:source),key=film.path+"|"+source
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        if let ov, case .flat = ov { let r = (route: StereoSource.Route.depth, note: ""); cache[key] = r; lock.unlock(); return r }
        let started = pending.insert(key).inserted          // review F4: check and insert under ONE lock hold, so two ticks cannot both start a decide
        lock.unlock()
        if !started { return nil }
        q.async { [self] in
            let r = decide(film, ov)
            lock.lock(); cache[key] = r; pending.remove(key); lock.unlock()
        }
        return nil
    }

    private func decide(_ film: URL, _ ov: StereoSource.Override?) -> (route: StereoSource.Route, note: String) {
        if !FileManager.default.isExecutableFile(atPath: ffprobe()), once(film: film, note: "ffprobe-missing") { print("stereo-source: ffprobe not in the vendor tree, metadata layer skipped (file name + pixel check only)"); fflush(stdout) }   // s42: not silent (build.sh does not gate it: it is optional in the owner's vendor)
        let verdict = StereoSourceProbe.verdict(url: film, ffprobe: ffprobe())
        var confirmed: Bool? = nil
        if ov == nil, let v = verdict, v.source == .filename { confirmed = pixelConfirm(film, v.layout) }
        let route = StereoSource.route(verdict: verdict, pixelConfirmed: confirmed, override: ov)
        let name = verdict.map { $0.layout.rawValue } ?? "none"
        switch route {
        case .depth: return (route, "")
        case .passthrough, .playAsIs: return (route, "3D: this file is already stereo (\(ov == nil ? name : "forced")), playing it as is")
        case .nativeNote: return (route, "3D: native 3D source (MV-HEVC), not converted: pick it from the 3d menu")
        }
    }

    /// Layer 3: one frame at ~10% of the duration, 640 px wide, grey eye halves -> StereoSource.confirm. nil = could not grab (unconfirmed, so the filename alone never routes).
    private func pixelConfirm(_ film: URL, _ layout: StereoLayout) -> Bool? {
        let asset = AVURLAsset(url: film), gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 640, height: 640)
        let t = CMTime(seconds: max(1, asset.duration.seconds.isFinite ? asset.duration.seconds * 0.1 : 1), preferredTimescale: 600)
        guard let img = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        let w = img.width, h = img.height
        guard let r = StereoSource.eyeRects(layout, w: w, h: h), let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let base = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = base.assumingMemoryBound(to: UInt8.self)
        func eye(_ q: (x: Int, y: Int, w: Int, h: Int)) -> [Float] {
            var g = [Float](); g.reserveCapacity(q.w * q.h)
            for y in 0..<q.h { for x in 0..<q.w { let i = ((q.y + y) * w + q.x + x) * 4; g.append(StereoSource.grey(r: px[i], g: px[i + 1], b: px[i + 2])) } }
            return g
        }
        return StereoSource.confirm(leftGrey: eye(r.l), rightGrey: eye(r.r), w: r.l.w, h: r.l.h).isStereo
    }
}
#endif
// END relocated StereoSourceGate.swift
// BEGIN relocated StereoSourceProbe.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s37 Mac side of the stereo detection: runs the vendored ffprobe (same fields stereo_probe.py reads: Stereo 3D / Spherical side data, profile, codec tag) and falls back to
/// the filename candidate when ffprobe is missing or fails (a filename never routes without the pixel confirm). UNCOMPILED on a Mac; the JSON parsing and verdict logic are
/// Linux-tested (Tests/StereoSource). A pixel confirm needs decoded frames: the caller grabs eye greys from the proxy and calls StereoSource.confirm.
enum StereoSourceProbe {
    static func verdict(url: URL, ffprobe: String, timeout: TimeInterval = 20) -> StereoVerdict? {
        guard FileManager.default.isExecutableFile(atPath: ffprobe) else { return StereoSource.filenameCandidate(url.path) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: ffprobe)
        p.arguments = ["-v", "error", "-select_streams", "v:0", "-show_streams", "-of", "json", url.path]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return StereoSource.filenameCandidate(url.path) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); killer.cancel()
        guard p.terminationStatus == 0, let f = StereoSource.parseFFprobe(data) else { return StereoSource.filenameCandidate(url.path) }
        return StereoSource.metadataVerdict(path: url.path, sideData: f.sideData, profile: f.profile, codecTag: f.codecTag)
    }
}
// END relocated StereoSourceProbe.swift
// BEGIN relocated SourceFormat.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s34 port of tools/depth_analysis/colorprobe.py. Pure Foundation (compiled and run on Linux against the reference in Tests/SourceFormat); the AVFoundation extraction
/// lives in SourceFormatProbe.swift (Darwin only, uncompiled). Transfer / primaries / matrix use the ffmpeg names the reference uses.
struct SourceFacts: Equatable {
    var width = 0, height = 0                    // storage pixels
    var rotation = 0                             // display-matrix rotation, degrees clockwise: 0 / 90 / 180 / 270
    var sar = 1.0                                // pixel aspect (h spacing / v spacing)
    var bitDepth = 8
    var transfer = "unknown", primaries = "unknown", matrix = "unknown"
    var fullRange: Bool? = nil                   // nil = untagged
    var dolbyVision = false
    var avgFps = 0.0, maxFps = 0.0               // nominalFrameRate, 1 / minFrameDuration
    var sampleDeltasMs: [Double] = []            // consecutive sample PTS deltas, ms; empty = not probed
    var codec = "unknown"
    var firstPTS = 0.0                          // original first presentation timestamp
    var ptsTickMs = 1.0                          // container timestamp quantum (1.0 for ms-muxed MKV/MP4)
}

enum SourceFormat {
    static let hdrTransfers: Set<String> = ["smpte2084", "arib-std-b67", "smpte428"]
    static let vfrRelTol = 0.002
    static let matrixCanon: [String: String] = ["bt709": "bt709", "bt470bg": "bt470bg", "smpte170m": "smpte170m", "fcc": "fcc", "bt2020nc": "bt2020nc", "bt2020_ncl": "bt2020nc", "bt2020c": "bt2020c", "chroma-derived-nc": "bt470bg"]

    /// Display size: square pixels, rotation applied (SAR scales the width first, then a 90/270 rotation swaps the axes).
    static func normalizedSize(_ f: SourceFacts) -> (w: Int, h: Int) {
        var w = Int((Double(f.width) * f.sar).rounded(.toNearestOrEven)), h = f.height
        if f.rotation == 90 || f.rotation == 270 { swap(&w, &h) }
        return (w, h)
    }
    static func needsNormalization(_ f: SourceFacts) -> Bool { f.rotation != 0 || abs(f.sar - 1.0) > 1e-3 }

    /// The YCbCr matrix the chain uses: the tag, else the size rule AVFoundation and mpv apply (HD bt709, SD bt470bg).
    static func matrixKey(_ f: SourceFacts) -> String {
        if let m = matrixCanon[f.matrix] { return m }
        return (f.width >= 1280 || f.height > 576) ? "bt709" : "bt470bg"
    }
    /// Whole-timeline presentation-grid fit, allowing container rounding, never dropped frames.
    /// Frame-indexed readers require one sample per grid point. Interval-only tests can miss
    /// cumulative drift (e.g. a long41ms segment then42ms); check every cumulative timestamp.
    /// nil = insufficient evidence, preserve the metadata guard.
    static func gridCFR(_ deltasMs: [Double], tickMs: Double) -> Bool? {
        guard deltasMs.count >= 30 else { return nil }
        guard tickMs.isFinite,tickMs>=0,deltasMs.allSatisfy({$0.isFinite && $0>0}) else {return false}
        let g = deltasMs.reduce(0,+) / Double(deltasMs.count)
        guard g.isFinite,g>1,g<=1000 else {return false}
        let eps=max(tickMs,1.0) // inherited millisecond mux precision after lossless remux
        var elapsed=0.0
        for (index,d) in deltasMs.enumerated() {
            elapsed += d
            if abs(d-g)>eps || abs(elapsed-Double(index+1)*g)>eps {return false}
        }
        return true
    }
    static func isVFR(_ f: SourceFacts) -> Bool {
        if let grid = gridCFR(f.sampleDeltasMs, tickMs: f.ptsTickMs) { return !grid }
        return f.avgFps > 0 && f.maxFps > 0 && abs(f.maxFps - f.avgFps) / f.avgFps > vfrRelTol
    }

    /// (dimension, status, detail) for the dimensions that gate or steer the port; same names and statuses as colorprobe.verdicts (refuse / fix / ok / note).
    static func verdicts(_ f: SourceFacts) -> [(dim: String, status: String, detail: String)] {
        var o: [(String, String, String)] = []
        o.append(("bit_depth", f.bitDepth >= 10 ? "ok" : "note", "\(f.bitDepth)-bit"))
        o.append(("hdr_transfer", hdrTransfers.contains(f.transfer) ? "refuse" : "ok", hdrTransfers.contains(f.transfer) ? "HDR transfer \(f.transfer): 3D prepare refuses; playing 2D" : "transfer \(f.transfer)"))
        o.append(("dolby_vision", f.dolbyVision ? "refuse" : "ok", f.dolbyVision ? "Dolby Vision: 3D prepare refuses; playing 2D" : "not Dolby Vision"))
        o.append(("sar", abs(f.sar - 1.0) > 1e-3 ? "fix" : "ok", "sar \(f.sar)"))
        o.append(("rotation", f.rotation != 0 ? "fix" : "ok", "rotation \(f.rotation)"))
        let vfrDetail: String
        if let grid = gridCFR(f.sampleDeltasMs, tickMs: f.ptsTickMs) {
            vfrDetail = grid ? "CFR (sample-grid consistent)" : "variable frame rate (sample timestamps off the fitted presentation grid): frame-indexed prepare assumes constant frame rate; playing 2D"
        } else {
            vfrDetail = isVFR(f) ? "variable frame rate (nominal \(f.avgFps) vs max \(f.maxFps)): frame-indexed prepare assumes constant frame rate; playing 2D" : "CFR"
        }
        o.append(("vfr", isVFR(f) ? "refuse" : "ok", vfrDetail))
        return o
    }
    static func refuseReasons(_ f: SourceFacts) -> [String] { verdicts(f).filter { $0.status == "refuse" }.map { $0.detail } }

    /// Affine (a, b, c, d, tx, ty) taking storage pixel coordinates (y down) to display pixels: SAR scale, then the track's preferredTransform, then a translation so the result
    /// fills [0, W] x [0, H] of normalizedSize. Applied by the composition reader, which also resamples to the display size.
    static func displayTransform(preferred p: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double), sar: Double, width: Int, height: Int) -> (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        // row-vector convention as CGAffineTransform: x' = a x + c y + tx, y' = b x + d y + ty. First scale x by sar, then apply p.
        let a = sar * p.a, b = sar * p.b, c = p.c, d = p.d
        let xs = [0.0, Double(width), 0.0, Double(width)], ys = [0.0, 0.0, Double(height), Double(height)]
        var minX = Double.infinity, minY = Double.infinity
        for i in 0..<4 { minX = min(minX, a * xs[i] + c * ys[i] + p.tx); minY = min(minY, b * xs[i] + d * ys[i] + p.ty) }
        return (a, b, c, d, p.tx - minX, p.ty - minY)
    }
    /// Rotation (clockwise degrees) of a preferredTransform; 0 for anything that is not a multiple of 90 (flips and skews are not handled: treated as unrotated plus a note by the caller).
    static func rotation(a: Double, b: Double, c: Double, d: Double) -> Int {
        func eq(_ x: Double, _ y: Double) -> Bool { abs(x - y) < 1e-3 }
        if eq(a, 1) && eq(b, 0) && eq(c, 0) && eq(d, 1) { return 0 }
        if eq(a, 0) && eq(b, 1) && eq(c, -1) && eq(d, 0) { return 90 }
        if eq(a, -1) && eq(b, 0) && eq(c, 0) && eq(d, -1) { return 180 }
        if eq(a, 0) && eq(b, -1) && eq(c, 1) && eq(d, 0) { return 270 }
        return 0
    }

    /// Luma bit depth from the codec configuration record (hvcC byte 17 & 7 + 8; avcC High 10 / 4:2:2 / 4:4:4 profiles with SPS depth not parsed: 110/122/244 = 10-bit assumed).
    static func bitDepth(hvcC: [UInt8]?, avcC: [UInt8]?) -> Int {
        if let h = hvcC, h.count > 17 { return Int(h[17] & 7) + 8 }
        if let a = avcC, a.count > 1, [110, 122, 244].contains(a[1]) { return 10 }
        return 8
    }

    /// 8-bit code -> MSB-aligned 10-bit (v10 << 6) code stored in 16 bits. Video range: exact (v << 8). Full range: v10 = round(v * 1023 / 255) approximated as v * 4 + (v >> 6).
    static func widen8To10(_ v: UInt8, fullRange: Bool) -> UInt16 {
        if !fullRange { return UInt16(v) << 8 }
        return UInt16(UInt16(v) * 4 + UInt16(v >> 6)) << 6
    }
}
// END relocated SourceFormat.swift
// BEGIN relocated SourceFormatProbe.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(CoreMedia)
import AVFoundation
import CoreMedia

/// 190v s34: AVAssetTrack -> SourceFacts (the colorprobe.py equivalent) and the proxy's colour tags. UNCOMPILED (no Mac): CMFormatDescription extension keys are the documented
/// kCMFormatDescriptionExtension_* constants; the string -> ffmpeg-name tables below are from memory of the CoreMedia/AVFoundation constant values (they match 1:1 for the tags the
/// proxy writer takes). A tag that is not in a table maps to "unknown" (never to a refuse verdict); an HDR file whose transfer is missing from the format description would slip
/// through, which is why Dolby Vision is also detected from the dvcC/dvvC atoms.
enum SourceFormatProbe {
    static let transferNames = ["ITU_R_709_2": "bt709", "SMPTE_ST_2084_PQ": "smpte2084", "ITU_R_2100_HLG": "arib-std-b67", "SMPTE_ST_428_1": "smpte428", "ITU_R_2020": "bt2020-10", "IEC_sRGB": "iec61966-2-1", "Linear": "linear", "SMPTE_240M_1995": "smpte240m"]
    static let primariesNames = ["ITU_R_709_2": "bt709", "SMPTE_C": "smpte170m", "EBU_3213": "bt470bg", "P3_D65": "smpte432", "DCI_P3": "smpte431", "ITU_R_2020": "bt2020"]
    static let matrixNames = ["ITU_R_709_2": "bt709", "ITU_R_601_4": "smpte170m", "ITU_R_2020": "bt2020nc", "SMPTE_240M_1995": "smpte240m"]
    static let dvFourCCs: Set<String> = ["dvhe", "dvh1", "dva1", "dvav", "dav1"]

    private static func fourCC(_ v: UInt32) -> String {
        String(bytes: [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)], encoding: .ascii) ?? ""
    }
    private static func ext(_ fd: CMFormatDescription, _ key: String) -> Any? { CMFormatDescriptionGetExtension(fd, extensionKey: key as CFString) }

    static func facts(url: URL) -> SourceFacts? {
        guard let t = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        return facts(track: t)
    }
    static func facts(track t: AVAssetTrack) -> SourceFacts {
        var f = SourceFacts()
        let pt = t.preferredTransform
        f.rotation = SourceFormat.rotation(a: Double(pt.a), b: Double(pt.b), c: Double(pt.c), d: Double(pt.d))
        f.width = Int(abs(t.naturalSize.width).rounded()); f.height = Int(abs(t.naturalSize.height).rounded())
        if f.rotation == 90 || f.rotation == 270 { swap(&f.width, &f.height) }                 // naturalSize is the DISPLAY-rotated size on some SDKs: take storage from the format description below when present
        f.avgFps = Double(t.nominalFrameRate)
        let mfd = t.minFrameDuration; if mfd.isValid, mfd.seconds > 0 { f.maxFps = 1.0 / mfd.seconds }
        // 195k: sample-PTS deltas for the grid-consistency VFR check (the minFrameDuration metadata above quantizes
        // to whole ms after a stream copy and false-refuses known-CFR sources). AVSampleCursor/makeSampleCursor
        // names are the documented AVFoundation API (UNCOMPILED, no Mac - same status as the rest of this file).
        if t.canProvideSampleCursors,let cursor = t.makeSampleCursor(presentationTimeStamp: .zero) {
            var deltas: [Double] = []
            var prev = cursor.presentationTimeStamp.seconds
            while cursor.stepInPresentationOrder(byCount: 1) == 1 {
                let pts = cursor.presentationTimeStamp.seconds
                deltas.append((pts - prev) * 1000.0)
                prev = pts
            }
            f.sampleDeltasMs = deltas
        }
        guard let first = t.formatDescriptions.first else { return f }
        let fd = first as! CMFormatDescription
        let dim = CMVideoFormatDescriptionGetDimensions(fd); if dim.width > 0, dim.height > 0 { f.width = Int(dim.width); f.height = Int(dim.height) }
        if let n = ext(fd, kCMFormatDescriptionExtension_TransferFunction as String) as? String { f.transfer = transferNames[n] ?? "unknown" }
        if let n = ext(fd, kCMFormatDescriptionExtension_ColorPrimaries as String) as? String { f.primaries = primariesNames[n] ?? "unknown" }
        if let n = ext(fd, kCMFormatDescriptionExtension_YCbCrMatrix as String) as? String { f.matrix = matrixNames[n] ?? "unknown" }
        if let fr = ext(fd, kCMFormatDescriptionExtension_FullRangeVideo as String) as? Bool { f.fullRange = fr }
        if let par = ext(fd, kCMFormatDescriptionExtension_PixelAspectRatio as String) as? [String: Any],
           let h = (par[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber)?.doubleValue,
           let v = (par[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber)?.doubleValue, h > 0, v > 0 { f.sar = h / v }
        let atoms = ext(fd, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String) as? [String: Any] ?? [:]
        f.dolbyVision = dvFourCCs.contains(fourCC(CMFormatDescriptionGetMediaSubType(fd))) || atoms["dvcC"] != nil || atoms["dvvC"] != nil
        let hv = (atoms["hvcC"] as? Data).map { [UInt8]($0) }, av = (atoms["avcC"] as? Data).map { [UInt8]($0) }
        f.bitDepth = SourceFormat.bitDepth(hvcC: hv, avcC: av)
        return f
    }

    /// AVVideoColorProperties for the proxy writer: the source's own tags when all three are present and SDR, else nil (untagged proxy, the writer's documented default).
    static func colorProperties(track t: AVAssetTrack) -> [String: String]? {
        guard let first = t.formatDescriptions.first else { return nil }
        let fd = first as! CMFormatDescription
        guard let p = ext(fd, kCMFormatDescriptionExtension_ColorPrimaries as String) as? String, let tf = ext(fd, kCMFormatDescriptionExtension_TransferFunction as String) as? String,
              let m = ext(fd, kCMFormatDescriptionExtension_YCbCrMatrix as String) as? String, !SourceFormat.hdrTransfers.contains(transferNames[tf] ?? "") else { return nil }
        return [AVVideoColorPrimariesKey: p, AVVideoTransferFunctionKey: tf, AVVideoYCbCrMatrixKey: m]
    }
    static func colorProperties(url: URL) -> [String: String]? { AVURLAsset(url: url).tracks(withMediaType: .video).first.flatMap { colorProperties(track: $0) } }
}
#endif
#if canImport(AVFoundation) && canImport(CoreMedia)
// Direct source decoding. The rawvideo pipe never creates a cache-side source copy.
enum PrepareDecodeContract {
    // Shared with the Linux runtime tests. Only placeholders are expanded.
    static let json = #"""
{"arguments":["-hide_banner","-nostdin","-nostats","-loglevel","info","-threads","1","-filter_threads","1","-copyts","-ss","{seek}","-noautorotate","-i","{source}","-map","0:v:0","-an","-sn","-dn","-vf","{filter}","-frames:v","{count}","-vsync","0","-pix_fmt","{pixel}","-f","rawvideo","pipe:1"],"trim":"trim=start={pts},","timestamp":"showinfo"}
"""#
    /// Probe the executable's actual CLI, not a remembered version number.
    /// Modern FFmpeg removed -vsync; old providers do not expose -fps_mode.
    /// Keep passthrough semantics on both without weakening byte/PTS checks.
    static func compatibleArguments(binary: String, arguments: [String], cancelled: @escaping () -> Bool) -> [String]? {
        if cancelled() { return arguments } // frame() owns the established cancellation path.
        guard let at = arguments.firstIndex(of: "-vsync"), at + 1 < arguments.count,
              arguments[at + 1] == "0" else { return arguments }
        var modern = false, legacy = false, total = 0
        let deadline = Date().addingTimeInterval(5)
        let completed = PrepareProbePipe.lines(binary: binary, arguments: ["-hide_banner", "-h", "full"],
            cancelled: { cancelled() || Date() >= deadline }) { line in
            total += line.utf8.count
            guard total <= 2 * 1024 * 1024 else { return false }
            let option = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if option == "-fps_mode" || option.hasPrefix("-fps_mode[") {
                modern = true
                return false // Found the capability; bounded early exit reaps the probe.
            }
            if option == "-vsync" { legacy = true }
            return true
        }
        guard !cancelled(), modern || (completed && legacy) else { return nil }
        guard modern else { return arguments }
        var result = arguments
        result.replaceSubrange(at...at + 1, with: ["-fps_mode", "passthrough"])
        return result
    }
    static func arguments(source: String, first: Int, last: Int, fps: Double, startPTS: Double, pixel: String, filters: [String]) -> [String]? {
        guard first >= 0, last >= first, fps.isFinite, fps > 0, startPTS.isFinite,
              let data = json.data(using: .utf8), let contract = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let args = contract["arguments"] as? [String] else { return nil }
        let pts = startPTS + Double(first) / fps
        // Accurate input seek decodes from the preceding keyframe. trim uses
        // retained source PTS and rejects the seek's preroll, never rough -ss alone.
        let substitutions = ["{source}":source,"{seek}":String(format:"%.9f",max(0,Double(first)/fps-1)),
            "{pts}":String(format:"%.9f",pts-0.0000001),"{count}":String(last-first+1),"{pixel}":pixel]
        let filter = "trim=start=" + substitutions["{pts}"]! + "," + (filters + ["showinfo"]).joined(separator:",")
        return args.map { value in
            if value == "{filter}" { return filter }
            return substitutions[value] ?? value
        }
    }
}

final class PrepareRawPipe {
    let process = Process()
    private let output = Pipe(), diagnostics = Pipe()
    private let condition = NSCondition(), stderrDone = DispatchSemaphore(value: 0)
    private var timestamps: [Double] = [], log = Data(), invalid = false, ended = false, closing = false
    private let cancelled: () -> Bool
    private var active = false
    init?(binary: String, arguments: [String], cancelled: @escaping () -> Bool) {
        guard FileManager.default.isExecutableFile(atPath:binary),
              let arguments = PrepareDecodeContract.compatibleArguments(binary: binary, arguments: arguments, cancelled: cancelled) else {return nil}
        self.cancelled=cancelled
        process.executableURL=URL(fileURLWithPath:binary);process.arguments=arguments
        process.standardInput=FileHandle.nullDevice;process.standardOutput=output;process.standardError=diagnostics
        var env=ProcessInfo.processInfo.environment;env["AV_LOG_FORCE_NOCOLOR"]="1";process.environment=env
        do {try process.run()} catch {return nil}
        active=true
        let fd=output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK)
        DispatchQueue.global(qos:.utility).async { [self] in
            var pending=Data()
            while true {
                let bytes=diagnostics.fileHandleForReading.availableData
                if bytes.isEmpty {break}
                pending.append(bytes)
                while let at=pending.firstIndex(of:10) {
                    let line=String(decoding:pending[..<at],as:UTF8.self);pending.removeSubrange(...at)
                    condition.lock()
                    if let range=line.range(of:#"pts_time:([-+0-9.eE]+)"#,options:.regularExpression),
                       let value=Double(line[range].dropFirst(9)),value.isFinite {
                        while timestamps.count >= 16 && !closing {condition.wait()}
                        if !closing {timestamps.append(value)}
                    }
                    log.append(contentsOf:line.utf8);log.append(10)
                    if log.count>8192 {log.removeFirst(log.count-8192)}
                    condition.broadcast();condition.unlock()
                }
                if pending.count>8192 {condition.lock();invalid=true;condition.unlock();pending.removeAll()}
            }
            condition.lock();ended=true;condition.broadcast();condition.unlock();stderrDone.signal()
        }
    }
    func frame(bytes: Int, expectedPTS: Double, tolerance: Double) -> Data? {
        guard active, bytes>0, bytes<=512*1024*1024 else {return nil}
        let deadline=Date().addingTimeInterval(30),fd=output.fileHandleForReading.fileDescriptor
        var data=Data(count:bytes),count=0
        while count<bytes {
            if cancelled() || Date()>=deadline {close();return nil}
            condition.lock();let bad=invalid;condition.unlock();if bad {close();return nil}
            let n=data.withUnsafeMutableBytes {p in read(fd,p.baseAddress!.advanced(by:count),bytes-count)}
            if n>0 {count+=n;continue}
            if n==0 {close();return nil}
            if errno != EAGAIN && errno != EINTR {close();return nil}
            var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0);_ = poll(&poller,1,20)
        }
        condition.lock()
        while timestamps.isEmpty && !ended && !invalid && Date()<deadline { _ = condition.wait(until:Date().addingTimeInterval(0.05)) }
        let pts=timestamps.isEmpty ? nil:timestamps.removeFirst();condition.broadcast();condition.unlock()
        guard let pts,abs(pts-expectedPTS)<=tolerance else {close();return nil}
        return data
    }
    func close() {
        guard active else {return};active=false
        condition.lock();closing=true;condition.broadcast();condition.unlock()
        if process.isRunning {kill(process.processIdentifier,SIGKILL)}
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
        _=stderrDone.wait(timeout:.now()+2)
        try? diagnostics.fileHandleForReading.close()
    }
    deinit {close()}
}

// Bounded output capture for small stream metadata, and streaming line inspection
// for the full PTS timeline. Neither path buffers a film-sized result.
enum PrepareProbePipe {
    static func lines(binary: String, arguments: [String], cancelled: @escaping () -> Bool, consume: (String) -> Bool) -> Bool {
        let p=Process(),out=Pipe();p.executableURL=URL(fileURLWithPath:binary);p.arguments=arguments
        p.standardInput=FileHandle.nullDevice;p.standardOutput=out;p.standardError=FileHandle.nullDevice
        do {try p.run()} catch {return false}
        let fd=out.fileHandleForReading.fileDescriptor
        _=fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK)
        defer {if p.isRunning {kill(p.processIdentifier,SIGKILL)};p.waitUntilExit();try? out.fileHandleForReading.close()}
        var pending=Data(),buffer=[UInt8](repeating:0,count:4096)
        var idle=Date().addingTimeInterval(30)
        while !cancelled() && Date()<idle {
            let n=read(fd,&buffer,buffer.count)
            if n>0 {
                idle=Date().addingTimeInterval(30);pending.append(contentsOf:buffer.prefix(n))
                while let at=pending.firstIndex(of:10) {
                    let line=String(decoding:pending[..<at],as:UTF8.self);pending.removeSubrange(...at)
                    if !consume(line) {return false}
                }
                if pending.count>1024*1024 {return false}
            } else if n==0 {
                if !pending.isEmpty && !consume(String(decoding:pending,as:UTF8.self)) {return false}
                p.waitUntilExit();return p.terminationStatus==0
            } else {
                if errno != EAGAIN && errno != EINTR {return false}
                var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0);_=poll(&poller,1,20)
            }
        }
        return false
    }
}

extension SourceFormatProbe {
    static func pipeFacts(url: URL, cancelled: @escaping () -> Bool) -> SourceFacts? {
        let binary=GORResources.vendorPath("ffmpeg/bin/ffprobe")
        var text=""
        guard PrepareProbePipe.lines(binary:binary,arguments:["-v","error","-select_streams","v:0","-show_streams","-of","json",url.path],cancelled:cancelled,consume:{line in
            guard text.utf8.count+line.utf8.count<1024*1024 else {return false};text+=line;return true
        }),let data=text.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
            let streams=json["streams"] as? [[String:Any]],streams.count==1 else {return nil}
        let s=streams[0]
        func number(_ key:String)->Double {if let v=s[key] as? NSNumber {return v.doubleValue};return Double(s[key] as? String ?? "") ?? 0}
        func ratio(_ value:String)->Double {let a=value.split(whereSeparator:{$0==":" || $0=="/"}).compactMap {Double($0)};return a.count==2 && a[1]>0 ? a[0]/a[1]:0}
        var f=SourceFacts();f.codec=s["codec_name"] as? String ?? "unknown";f.width=Int(number("width"));f.height=Int(number("height"))
        f.avgFps=ratio(s["avg_frame_rate"] as? String ?? "");f.maxFps=ratio(s["r_frame_rate"] as? String ?? "")
        f.ptsTickMs=ratio(s["time_base"] as? String ?? "")*1000
        guard f.width>0,f.height>0,f.width<=16384,f.height<=16384,f.avgFps>0,f.avgFps<=1000,f.ptsTickMs>0 else {return nil}
        let sar=ratio(s["sample_aspect_ratio"] as? String ?? "1:1");guard sar>0,sar.isFinite else {return nil};f.sar=sar
        let pf=s["pix_fmt"] as? String ?? ""
        // Unknown packed layouts are refused rather than silently called 8-bit.
        if let bits=Int(s["bits_per_raw_sample"] as? String ?? ""),bits>=8,bits<=16 {f.bitDepth=bits}
        else if pf.contains("10") || pf.contains("p010") {f.bitDepth=10}
        else if ["yuv420p","yuv422p","yuv444p","yuvj420p","yuvj422p","yuvj444p","nv12","nv21","bgra","rgba","rgb24","bgr24","gray"].contains(pf) {f.bitDepth=8}
        else {return nil}
        f.transfer=s["color_transfer"] as? String ?? "unknown";f.primaries=s["color_primaries"] as? String ?? "unknown";f.matrix=s["color_space"] as? String ?? "unknown"
        let range=s["color_range"] as? String;f.fullRange=range=="pc" ? true:range=="tv" ? false:nil
        let side=s["side_data_list"] as? [[String:Any]] ?? []
        f.dolbyVision=dvFourCCs.contains(s["codec_tag_string"] as? String ?? "") || side.contains {($0["side_data_type"] as? String ?? "").lowercased().contains("dovi")}
        if let matrix=side.compactMap({$0["displaymatrix"] as? String}).first {
            let rows=matrix.split(separator:"\n").compactMap {line -> [Double]? in
                guard let colon=line.firstIndex(of:":") else {return nil}
                let values=line[line.index(after:colon)...].split(whereSeparator:{$0.isWhitespace}).compactMap {Double($0)}
                return values.count==3 ? values:nil
            }
            guard rows.count==3 else {return nil}
            let a=rows[0][0]/65536,b=rows[0][1]/65536,c=rows[1][0]/65536,d=rows[1][1]/65536
            // The current display normalizer supports orthogonal rotations,
            // not reflected/skewed/perspective matrices. Refuse, never misdraw.
            guard [a,b,c,d].allSatisfy({abs($0-$0.rounded())<0.00001 && abs($0)<=1}),
                  abs(a*d-b*c-1)<0.00001,rows[0][2]==0,rows[1][2]==0 else {return nil}
        }
        if let rotation=side.compactMap({($0["rotation"] as? NSNumber)?.doubleValue}).first {
            // ffprobe display-matrix angles are counterclockwise.
            guard abs(rotation/90-(rotation/90).rounded())<0.001 else {return nil}
            f.rotation=((Int(-rotation)%360)+360)%360
        } else if let tags=s["tags"] as? [String:String],let rotation=Double(tags["rotate"] ?? "") {
            guard abs(rotation/90-(rotation/90).rounded())<0.001 else {return nil};f.rotation=((Int(rotation)%360)+360)%360
        }
        // Demux packet PTS without decoding the full film a fourth time.
        // A bounded reorder window yields presentation order for B-frames.
        // Sources exceeding that window or lacking packet PTS fail closed.
        var first:Double?,previous:Double?,count=0,pending:[Double]=[]
        let epsilon=max(f.ptsTickMs/1000,0.001)+0.0000001,step=1/f.avgFps
        func accept(_ pts:Double)->Bool {
            if first==nil {first=pts}
            if let prev=previous,pts<=prev || abs(pts-prev-step)>epsilon {return false}
            guard abs(pts-first!-Double(count)*step)<=epsilon else {return false}
            previous=pts;count+=1;return true
        }
        let ok=PrepareProbePipe.lines(binary:binary,arguments:["-v","error","-select_streams","v:0","-show_packets","-show_entries","packet=pts_time:side_data=","-of","csv=p=0",url.path],cancelled:cancelled) {line in
            if line.trimmingCharacters(in:.whitespaces).isEmpty {return true}
            guard let raw=line.split(separator:",",omittingEmptySubsequences:false).first,let pts=Double(raw),pts.isFinite else {return false}
            pending.append(pts);pending.sort()
            return pending.count<=64 || accept(pending.removeFirst())
        }
        guard ok else {return nil}
        while !pending.isEmpty {guard accept(pending.removeFirst()) else {return nil}}
        guard count>0,let first else {return nil}
        f.firstPTS=first;f.maxFps=f.avgFps
        return f
    }
    static func pipeColorProperties(_ f:SourceFacts)->[String:String]? {
        guard let p=primariesNames.first(where:{$0.value==f.primaries})?.key,
              let t=transferNames.first(where:{$0.value==f.transfer})?.key,
              let m=matrixNames.first(where:{$0.value==f.matrix})?.key else {return nil}
        return [AVVideoColorPrimariesKey:p,AVVideoTransferFunctionKey:t,AVVideoYCbCrMatrixKey:m]
    }
}

enum PrepareDecodeDiagnostics {
    private static let lock=NSLock()
    private static var capabilities:[String:Bool]=[:]
    private static var firstFrames=Set<String>()
    private static var binaryIdentity:String?
    static func capability(codec:String,pixel:String,filters:[String],cancelled:@escaping ()->Bool)->Bool {
        let key=codec+"|"+pixel+"|"+filters.sorted().joined(separator:",")
        lock.lock();if let ready=capabilities[key] {lock.unlock();return ready};capabilities[key]=false;lock.unlock()
        let binary=GORResources.vendorPath("ffmpeg/bin/ffmpeg")
        var version="",decoder=false,pixelOK=false,found=Set<String>()
        _=PrepareProbePipe.lines(binary:binary,arguments:["-version"],cancelled:cancelled) {line in
            if version.isEmpty {version=String(line.prefix(160))};return true
        }
        let decoderRun=PrepareProbePipe.lines(binary:binary,arguments:["-hide_banner","-decoders"],cancelled:cancelled) {line in
            let fields=line.split(whereSeparator:{$0.isWhitespace})
            if fields.count>1 && (fields[1]==codec || line.contains("(codec "+codec+")")) {decoder=true};return true
        }
        let pixelRun=PrepareProbePipe.lines(binary:binary,arguments:["-hide_banner","-pix_fmts"],cancelled:cancelled) {line in
            let fields=line.split(whereSeparator:{$0.isWhitespace})
            if fields.count>1 && fields[1]==pixel {pixelOK=true};return true
        }
        let required=Set(filters+["trim","showinfo"])
        let filterRun=PrepareProbePipe.lines(binary:binary,arguments:["-hide_banner","-filters"],cancelled:cancelled) {line in
            let fields=line.split(whereSeparator:{$0.isWhitespace})
            if fields.count>1 && required.contains(String(fields[1])) {found.insert(String(fields[1]))};return true
        }
        lock.lock()
        if binaryIdentity==nil {
            #if canImport(CryptoKit)
            var hash=SHA256()
            #else
            var hash=SHA256Pure.Hasher()
            #endif
            if let handle=try? FileHandle(forReadingFrom:URL(fileURLWithPath:binary)) {
                while let data=try? handle.read(upToCount:65536),!data.isEmpty {
                    #if canImport(CryptoKit)
                    hash.update(data:data)
                    #else
                    hash.update([UInt8](data))
                    #endif
                }
                try? handle.close()
                #if canImport(CryptoKit)
                binaryIdentity=hash.finalize().map {String(format:"%02x",$0)}.joined()
                #else
                binaryIdentity=hash.hex()
                #endif
            } else {binaryIdentity="unreadable"}
        }
        let identity=binaryIdentity!;lock.unlock()
        let okay=decoderRun && pixelRun && filterRun && decoder && pixelOK && found==required
        print("3d-decode capability binary=vendor/ffmpeg sha256=\(identity) version=\(version) codec=\(String(codec.prefix(32))) decoder=\(decoder) pixel=\(pixel):\(pixelOK) filters=\(found.sorted().joined(separator:",")) result=\(okay ? "ready":"unavailable_staying_2D")");fflush(stdout)
        lock.lock();capabilities[key]=okay;lock.unlock();return okay
    }
    static func firstFrame(container:String,okay:Bool,reason:String) {
        let safe=String(container.lowercased().filter {$0.isASCII && ($0.isLetter || $0.isNumber)}.prefix(16))
        lock.lock();let first=firstFrames.insert(safe).inserted;lock.unlock()
        if first {print("3d-decode first-frame container=\(safe) result=\(okay ? "decoded":"failed_staying_2D") reason=\(String(reason.prefix(96)))");fflush(stdout)}
    }
}

#endif
// END relocated SourceFormatProbe.swift
// BEGIN relocated SphericalTag.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// s36 (1): Spherical Video V2 + stereo-mode (left-right) tag for a finished vr180 render_shot mp4, so any other player that opens the cache file reads it as
/// 180x180 side-by-side equirect. Pure byte work on the mp4 box tree, no AVFoundation. Default OFF (UserDefaults gor.3d.sphericalTag, SphericalTag.defaultsKey): it changes the file bytes,
/// never a decoded frame, and the player-side look no longer depends on it (vr180-look-plan-lock). Mirrors Tests/SphericalTag/spherical_tag_test.py, which runs the
/// same layout on a real mp4. UNCOMPILED on a Mac; AVAssetWriter's own moov placement is unverified (both placements are handled).
enum SphericalTag {
    static let defaultsKey = "gor.3d.sphericalTag"
    private static func box(_ type: String, _ body: [UInt8]) -> [UInt8] { be32(UInt32(8 + body.count)) + Array(type.utf8) + body }
    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
    }
    private static func rd32(_ d: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i + 1]) << 16) | (UInt32(d[i + 2]) << 8) | UInt32(d[i + 3])
    }
    private static func rd64(_ d: [UInt8], _ i: Int) -> UInt64 {
        (UInt64(rd32(d, i)) << 32) | UInt64(rd32(d, i + 4))
    }

    /// st3d (stereo_mode 2 = left-right) + sv3d (svhd, proj > prhd, equi with 180 x 180 bounds: left = right = 90 deg of 360).
    static func tagBoxes() -> [UInt8] {
        let st3d = box("st3d", be32(0) + [UInt8(2)])
        let svhd = box("svhd", be32(0) + Array("gor".utf8) + [0])
        let prhd = box("prhd", be32(0) + be32(0) + be32(0) + be32(0))
        let equi = box("equi", be32(0) + be32(0) + be32(0) + be32(0x4000_0000) + be32(0x4000_0000))
        return st3d + box("sv3d", svhd + box("proj", prhd + equi))
    }

    private struct B { let type: String; let start: Int; let end: Int; let body: Int }
    private static func children(_ d: [UInt8], _ from: Int, _ to: Int) -> [B]? {
        var out: [B] = [], i = from
        while i + 8 <= to {
            let size = Int(rd32(d, i)), type = String(decoding: d[(i + 4)..<(i + 8)], as: UTF8.self)
            if size == 0 || size == 1 || size < 8 || i + size > to { return nil }          // 64-bit and to-end boxes are not handled: leave the file alone
            out.append(B(type: type, start: i, end: i + size, body: i + 8)); i += size
        }
        return out
    }

    /// The patched bytes, or nil on any doubt (unknown layout, 64-bit box size). Already tagged = same bytes.
    static func patched(_ d: [UInt8]) -> [UInt8]? {
        guard let top = children(d, 0, d.count), let moov = top.first(where: { $0.type == "moov" }) else { return nil }
        if containsTag(Array(d[moov.start..<moov.end])) { return d }
        var chain: [B] = [moov], cur = moov
        for name in ["trak", "mdia", "minf", "stbl", "stsd"] {
            guard let kids = children(d, cur.body, cur.end), let n = kids.first(where: { $0.type == name }) else { return nil }
            chain.append(n); cur = n
        }
        let stsd = cur, stbl = chain[chain.count - 2]
        guard let entries = children(d, stsd.body + 8, stsd.end), let entry = entries.first(where: { ["hvc1", "hev1", "avc1", "avc3"].contains($0.type) }) else { return nil }
        let add = tagBoxes()
        var o = Array(d[0..<entry.end]) + add + Array(d[entry.end...])
        for b in chain + [entry] {
            let at = b.start, sz = rd32(d, at) + UInt32(add.count)
            o.replaceSubrange(at..<(at + 4), with: be32(sz))
        }
        if let mdatOffset = top.first(where: { $0.type == "mdat" })?.start, case let moovOffset = moov.start, moovOffset < mdatOffset {   // moov before mdat: every chunk offset moves
            guard let kids = children(o, stbl.body, stbl.end + add.count) else { return nil }
            for k in kids where k.type == "stco" || k.type == "co64" {
                let n = Int(rd32(o, k.body + 4)), wide = k.type == "co64"
                for j in 0..<n {
                    let p = k.body + 8 + j * (wide ? 8 : 4)
                    if wide { let v = rd64(o, p) + UInt64(add.count); o.replaceSubrange(p..<(p + 8), with: be32(UInt32(v >> 32)) + be32(UInt32(v & 0xFFFF_FFFF))) }
                    else { o.replaceSubrange(p..<(p + 4), with: be32(rd32(o, p) + UInt32(add.count))) }
                }
            }
        }
        return o
    }
    private static func containsTag(_ m: [UInt8]) -> Bool {
        let t = Array("st3d".utf8)
        return m.indices.dropLast(3).contains { Array(m[$0..<($0 + 4)]) == t }
    }

    /// After a finished render: tags `url` in place (write to a sibling, then replace). false = left untouched (flag off, not vr180, or any failure): the file plays exactly as before.
    @discardableResult static func apply(to url: URL, plan: RenderedShotPlan) -> Bool {
        guard plan.output == .vr180, UserDefaults.standard.bool(forKey: SphericalTag.defaultsKey), let data = try? Data(contentsOf: url), let out = patched([UInt8](data)), out.count != data.count else { return false }
        let tmp = url.appendingPathExtension("tagging")
        guard (try? DepthCacheIO.write(Data(out),to:tmp,atomic:false)) != nil else { try? FileManager.default.removeItem(at: tmp); return false }
        return (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) != nil
    }
}
// END relocated SphericalTag.swift
// BEGIN relocated SourcePixelCrop.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
import CoreGraphics
import Darwin

/// Original software-decoded samples, never a rendered screenshot. No user media is saved.
/// cropdetect is advisory: its line average can miss a single bright bar pixel. The exact luma
/// bounding union below vetoes every crop that would discard a sampled nonblack pixel.
enum SourcePixelBounds {
    struct Bounds: Equatable {
        var x0: Int; var y0: Int; var x1: Int; var y1: Int
        func union(_ b: Bounds) -> Bounds {
            Bounds(x0:min(x0,b.x0),y0:min(y0,b.y0),x1:max(x1,b.x1),y1:max(y1,b.y1))
        }
    }
    /// Early-apply rule for stream scans: at least `minCount` non-black frames whose bounds all agree with their union
    /// within `tol` px on every edge. Returns the union, else nil. The final scan result is never narrower than this
    /// (later frames can only widen the union), so refining after an early apply never cuts more.
    static let earlyMinCount = 3
    static let earlyTolerance = 8
    static func consistent(_ members: [Bounds], tol: Int = earlyTolerance, minCount: Int = earlyMinCount) -> Bounds? {
        guard members.count >= minCount, let first = members.first else { return nil }
        let u = members.dropFirst().reduce(first) { $0.union($1) }
        for m in members where abs(m.x0-u.x0) > tol || abs(m.y0-u.y0) > tol || abs(m.x1-u.x1) > tol || abs(m.y1-u.y1) > tol { return nil }
        return u
    }
    /// Diagnostic only: luma mean/max (8-bit-equivalent, relative to black) of rows near the measured top and bottom bound, so a log shows the
    /// real bar level. Reads the first plane of little-endian 16-bit samples (luma for yuv444p16le and gray16le).
    static func edgeRows(_ bytes: Data, width: Int, height: Int, bounds b: Bounds, black: Int, bits: Int, gray: Bool) -> String {
        let planeBytes = width * height * 2
        guard width > 0, height > 0, bytes.count >= planeBytes else { return "unavailable" }
        let shift = max(0, 16 - bits), unit = 1 << max(0, bits - 8)
        var out: [String] = []
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            func stat(_ y: Int) -> String {
                guard y >= 0, y < height else { return "-" }
                var sum = 0, mx = 0, x = 0
                while x < width { let i = (y * width + x) * 2; let v = Int(UInt16(p[i]) | UInt16(p[i + 1]) << 8) >> shift; sum += v; mx = max(mx, v); x += 1 }
                let mean = Double(sum) / Double(width) - Double(black), top = mx - black
                return String(format: "y%d=%.1f/%d", y, mean / Double(unit), top / unit)
            }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("T" + stat(b.y0 + d)) }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("B" + stat(b.y1 - 1 - d)) }
        }
        return out.joined(separator: " ")
    }
    /// Exact bounding box of every sample above `threshold` (identical result to a full per-pixel scan).
    /// Rows are visited top-down until the first bright row and bottom-up until the last; middle rows only
    /// look for a bright sample left of the current x0 or right of the current x1, so a full frame costs
    /// a few rows instead of every pixel. Little-endian UInt16 samples.
    ///
    /// Edge rows tolerate isolated specks: when `speck` > 0 a row at the top or bottom edge is content only if more than `speck`
    /// samples exceed `threshold`, or any sample exceeds `strong` (clearly non-black). Encode noise and stray bright pixels inside
    /// a letterbox bar then no longer move the bound (the owner saw a 26-row band above and 10 rows below the picture). With
    /// speck 0 the result is the exact one-sample veto as before.
    static func scan(_ bytes: Data, width: Int, height: Int, threshold: UInt16, speck: Int = 0, strong: UInt16 = 0) -> Bounds? {
        guard width > 0, height > 0, bytes.count >= width * height * 2 else { return nil }
        var result: Bounds?
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            @inline(__always) func sample(_ y: Int, _ x: Int) -> UInt16 {
                let i = (y * width + x) * 2
                return UInt16(p[i]) | UInt16(p[i + 1]) << 8
            }
            // First bright x in [from, to) or -1; last bright x in [from, to) or -1.
            func first(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = from
                while x < to { if sample(y, x) > threshold { return x }; x += 1 }
                return -1
            }
            func last(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = to - 1
                while x >= from { if sample(y, x) > threshold { return x }; x -= 1 }
                return -1
            }
            func rowIsContent(_ y: Int) -> Bool {
                if speck <= 0 || strong <= threshold { return first(y, 0, width) >= 0 }
                var n = 0
                var x = 0
                while x < width {
                    let v = sample(y, x)
                    if v > strong { return true }
                    if v > threshold { n += 1; if n > speck { return true } }
                    x += 1
                }
                return false
            }
            var top = -1
            var y = 0
            while y < height { if rowIsContent(y) { top = y; break }; y += 1 }
            guard top >= 0 else { return }
            var bottom = top
            y = height - 1
            while y > top { if rowIsContent(y) { bottom = y; break }; y -= 1 }
            var x0 = width, x1 = 0
            for row in [top, bottom] {
                x0 = min(x0, first(row, 0, width))
                x1 = max(x1, last(row, 0, width) + 1)
            }
            if top + 1 < bottom {
                y = top + 1
                while y < bottom {
                    if x0 == 0 && x1 == width { break }
                    if x0 > 0 { let f = first(y, 0, x0); if f >= 0 { x0 = f } }
                    if x1 < width { let l = last(y, x1, width); if l >= 0 { x1 = l + 1 } }
                    y += 1
                }
            }
            result = Bounds(x0: x0, y0: top, x1: x1, y1: bottom + 1)
        }
        return result
    }
    static func scanHalves(_ bytes:Data,width:Int,height:Int,threshold:UInt16,topBottom:Bool=false)->[Bounds]? {
        guard width%2==0,height%2==0,bytes.count>=width*height*2 else{return nil}
        if topBottom {
            var eyes:[Bounds]=[]
            for eye in 0...1 {
                let a=eye*width*height
                let bound=scan(bytes.subdata(in:a..<(a+width*height)),width:width,height:height/2,threshold:threshold)
                    ?? Bounds(x0:width,y0:height/2,x1:0,y1:0)
                eyes.append(bound)
            }
            return eyes
        }
        var halves:[Bounds]=[]
        for eye in 0...1 {
            var half=Data();half.reserveCapacity(width*height)
            for y in 0..<height {
                let a=(y*width+eye*width/2)*2
                half.append(bytes.subdata(in:a..<(a+width)))
            }
            let bound=scan(half,width:width/2,height:height,threshold:threshold)
                ?? Bounds(x0:width/2,y0:height,x1:0,y1:0)
            halves.append(bound)
        }
        return halves
    }
    /// A display viewport may crop the common local eye rectangle without touching a packed seam.
    static func eyeViewport(_ eyes:[Bounds],width:Int,height:Int,topBottom:Bool) -> CGRect? {
        guard eyes.count==2 else {return nil}
        let w=topBottom ? width:width/2,h=topBottom ? height/2:height
        let common=eyes[0].union(eyes[1])
        guard common.x1>common.x0,common.y1>common.y0 else {return nil}
        let b=outward(common,width:w,height:h,stereo:false)
        return CGRect(x:Double(b.x0)/Double(w),y:Double(b.y0)/Double(h),width:Double(b.x1-b.x0)/Double(w),height:Double(b.y1-b.y0)/Double(h))
    }
    static func outward(_ b: Bounds, width: Int, height: Int, stereo: Bool,topBottom:Bool=false) -> Bounds {
        // A rectangular video-crop cannot remove each eye's inner horizontal edge without cutting
        // the seam. Keep all SBS columns; top/bottom bounds are the union of both complete halves.
        if topBottom {
            return Bounds(x0:(b.x0/2)*2,y0:0,x1:min(width,((b.x1+1)/2)*2),y1:height)
        }
        return Bounds(x0:stereo ? 0 : (b.x0 / 2) * 2, y0:(b.y0 / 2) * 2,
               x1:stereo ? width : min(width,((b.x1 + 1) / 2) * 2),
               y1:min(height,((b.y1 + 1) / 2) * 2))
    }
}

final class SourcePixelCropScanner {
    private let lock = NSLock()
    private var epoch = 0
    private var freshnessFloor = 0 // only an explicit measurement boundary forbids cancelled carry reuse
    private var active: Process?
    /// Work already measured on a stream (wt) survives a cancel: bars are a static property of the file, so the union of
    /// samples from an interrupted scan stays valid for the next scan of the same file, and a decisive rect that was
    /// computed but dropped by a cancel is handed to the next scan of that file instead of being thrown away.
    /// key = path|stereo|topBottom|rounded duration of the scan that wrote it; dims = "WxH pix range" once the stream was probed ("" if never).
    private struct Carry { var key: String; var dims: String; var at: Double; var bounds: SourcePixelBounds.Bounds?; var members: [SourcePixelBounds.Bounds]; var sampled: Int; var undelivered: Bool; var rect: CGRect?; var done: [Double]; var ep: Int; var planned: [Double] }   // ep = epoch of the scan that wrote it: an older scan never overwrites it; planned = the exact sample plan the progress belongs to
    /// Interrupted-scan progress may seed a later scan only when it is the exact same sample plan:
    /// identical planned seconds mean the same usable cache window produced them. A plan computed
    /// from an older cache frontier (or before a seek, or after eviction changed the ranges)
    /// planned different seconds, and its members must not join a fresh window's consensus, where
    /// they would veto agreement (owner session 2026-11-22: intro members carried into all 31
    /// later scans). Completed indecisive scans leave no progress at all - see finish.
    static func carryPlanReusable(undelivered: Bool, planned: [Double], plan: [Double]) -> Bool {
        undelivered || planned == plan
    }
    /// Whether a finished scan leaves its progress carry behind. finish runs only for completed
    /// scans, so completed indecisive evidence never seeds the next scan; a decisive-but-undelivered
    /// rect stays for handback, and an interrupted (cancelled) scan never reaches here.
    static func progressClearedOnCompletion(decisive: Bool, carryUndelivered: Bool) -> Bool {
        !decisive && !carryUndelivered
    }
    private var carry: Carry?
    /// Scan context: the current measurement key and a generation that advances ONLY when the key
    /// changes. Established synchronously at every scan start - any source kind, valid plan or
    /// not - under the same lock the cancelled-store check runs under; each scan captures the
    /// token and a late finish of a superseded scan can never store into a newer context.
    /// (F4/ABA: a wt-only key record restored by a fresh same-file scan admitted the old store.)
    private var contextKey: String?
    private var contextGeneration: Int = 0
    /// Synchronous at scan start, before dispatch; caller holds no lock. Returns the token the
    /// starting scan captures; an unchanged key keeps the generation so an ordinary
    /// cancel-and-rescan of the same file stays one context (the intended handback).
    private func establishScanContext(key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if contextKey != key { contextKey = key; contextGeneration += 1 }
        return contextGeneration
    }
    private static let carryTTL: Double = 180   // seconds; older measurements are re-measured, never replayed
    private(set) var decodedWidth=0
    private(set) var decodedHeight=0
    private(set) var perEyeAspect:Double?
    private var lastDeliveredEpoch = -1   // epoch of the scan that last delivered a decisive result: an older scan may not store after it
    /// Forget everything carried (explicit manual Detect re-measures from scratch).
    /// Samples decoded so far by the scan now running (0 when none started or none decoded yet).
    private(set) var liveSamples = 0
    /// Set by every finished scan before its completion runs on main: true when an indecisive
    /// stream scan ended starved of non-black frames (fewer than the early-apply minimum, or no
    /// decodable samples), false when bright frames disagreed or the scan was decisive. The crop
    /// detector grows its automatic window level only on starvation; on disagreement the window
    /// stays at the cache frontier, which keeps advancing into fresh content on its own.
    private(set) var lastScanStarved = false
    /// True when a scan for the file on screen is already producing samples: a manual Detect then lets it finish
    /// instead of killing it (the capture showed repeated clicks cancelling every scan at 19-27 s of ~57 s).
    private var scanStartedAt:Double=0, scanDeadlineAt:Double=0, lastProgressAt:Double=0
    /// A single old sample is not proof that the worker is still making progress.
    func hasProgress() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now=ProcessInfo.processInfo.systemUptime
        return liveSamples > 0 && now-lastProgressAt <= 20 && now-scanStartedAt <= 90 && scanDeadlineAt-now > 12
    }
    func dropCarry() { lock.lock(); if carry?.undelivered != true { carry = nil }; lock.unlock() }   // a decisive rect that was never delivered stays as the fallback for an indecisive manual scan
    // Caller holds lock. Ordinary cancel retains carry reuse; explicit freshness boundaries do not.
    private func mayStoreCancelledCarry(_ e:Int,_ key:String,_ context:Int)->Bool {
        return context == contextGeneration && contextKey == key && e >= freshnessFloor && e > lastDeliveredEpoch && (carry == nil || (carry?.key == key && (carry?.sampled ?? 0) == 0 && (carry?.ep ?? -1) < e))
    }
    /// A seek changes the measurement context, unlike an ordinary scan restart.
    /// Old cancelled finish callbacks cannot refill carry after this boundary.
    func invalidateMeasurementContext() {
        lock.lock();epoch += 1;freshnessFloor=epoch;carry=nil;contextKey=nil;contextGeneration += 1;let p=active;lock.unlock()
        if let p,p.isRunning {kill(p.processIdentifier,SIGKILL)}
    }
    func cancel() {
        lock.lock(); epoch += 1; let p = active; lock.unlock()
        if let p, p.isRunning { kill(p.processIdentifier,SIGKILL) }
    }
    private func valid(_ e: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return epoch == e }
    // Typed execution seam. stderr is diagnostic data, never interpreted as commands.
    private enum ReadFailure:String {case cancelled,deadline,launch,oversized,exitStatus,incomplete}
    private struct ReadResult {
        let stdout:Data,stderr:Data,status:Int32
        let failure:ReadFailure?
    }
    private func run(_ binary: String, _ args: [String], epoch e: Int, cap: Int, killAfter: Double = 20) -> ReadResult {
        guard valid(e) else { return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.cancelled) }
        guard killAfter > 0 else { return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.deadline) }
        let readerArgs = CropHTTPReader.arguments(args)
        let args = URL(fileURLWithPath: binary).lastPathComponent == "ffmpeg" ? FFmpegAnalysisThreads.arguments(readerArgs) : readerArgs
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath:binary); p.arguments = args
        // Background work: lowest priority (nice execs, same pid, so kill still hits ffmpeg).
        if FileManager.default.isExecutableFile(atPath:"/usr/bin/nice") { p.executableURL = URL(fileURLWithPath:"/usr/bin/nice"); p.arguments = ["-n","19",binary] + args }
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        lock.lock(); guard epoch == e else { lock.unlock(); return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.cancelled) }; active = p
        do { try p.run() } catch { active = nil; lock.unlock(); return ReadResult(stdout:Data(),stderr:Data(String(describing:error).utf8),status: -1,failure:.launch) }; lock.unlock()
        let timedOut=LockedData()
        let deadline = DispatchWorkItem { if p.isRunning { timedOut.append(Data([1]),cap:1); kill(p.processIdentifier,SIGKILL) } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+killAfter,execute:deadline)
        let g = DispatchGroup(); let stderr = LockedData()
        g.enter(); DispatchQueue.global(qos:.utility).async {
            while true { let c = err.fileHandleForReading.availableData; if c.isEmpty { break }; stderr.append(c,cap:262144) }
            g.leave()
        }
        var data = Data(); var oversized = false
        while true {
            let c = out.fileHandleForReading.availableData; if c.isEmpty { break }
            if data.count + c.count <= cap { data.append(c) } else { oversized = true; if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
        }
        p.waitUntilExit(); g.wait(); deadline.cancel()
        lock.lock(); if active === p { active = nil }; lock.unlock()
        let reason:ReadFailure? = !valid(e) ? .cancelled : oversized ? .oversized : !timedOut.value().isEmpty ? .deadline : p.terminationStatus != 0 ? .exitStatus:nil
        return ReadResult(stdout:data,stderr:stderr.value(),status:p.terminationStatus,failure:reason)
    }
    private final class LockedData {
        let lock = NSLock(); var data = Data()
        func append(_ c: Data, cap: Int) { lock.lock(); if data.count+c.count <= cap { data.append(c) }; lock.unlock() }
        func value() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
    func scan(path: String, duration: Double, stereo: Bool,topBottom:Bool=false, viewportOnly:Bool=false, caller: String = "", fresh: Bool = false, positions samplePositions:(()->[Double]?)?=nil, interim: ((CGRect, Double)->Void)? = nil, completion: @escaping (CGRect?,Bool,Double)->Void) {
        cancel(); perEyeAspect=nil; lastScanStarved=false
        let started=ProcessInfo.processInfo.systemUptime
        let stream=CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)
        let expires=started + (stream ? 90:240)
        let key = "\(path)|\(stereo)|\(topBottom)|\(Int(duration.rounded()))"
        let scanContext = establishScanContext(key: key)
        lock.lock(); let e = epoch; liveSamples = 0;scanStartedAt=started;scanDeadlineAt=expires;lastProgressAt=0; lock.unlock()
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self else { return }
            var lastFailure="none"
            func failure(_ reason:String) {
                lastFailure=reason
                print("[cropdetect] read failure epoch=\(e) reason=\(reason)")
            }
            // Only transfer relay probes wait. The worker is cancellable throughout;
            // no process exists and no upstream range is opened while deferred.
            func decode(_ binary: String, _ args: [String], epoch: Int, cap: Int, killAfter: Double) -> (Data,Data,Int32)? {
                var deferred = false
                while !TransferProbeAdmission.admits(path) {
                    guard self.valid(e) else { failure("cancelled");return nil }
                    guard ProcessInfo.processInfo.systemUptime < expires else { failure("deadline: admission");return nil }
                    if !deferred { print("[cropdetect] transfer probe deferred: forward buffer below 15s or stale/stalled"); deferred = true }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if deferred { print("[cropdetect] transfer probe admitted: forward buffer healthy") }
                let remaining=expires-ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { failure("deadline: before open");return nil }
                let result=self.run(binary,args,epoch:epoch,cap:cap,killAfter:min(killAfter,remaining))
                if let why=result.failure {
                    let diagnostic=String(decoding:result.stderr.prefix(2048),as:UTF8.self).replacingOccurrences(of:"\n",with:" ")
                    failure("\(why.rawValue) status=\(result.status) stderr=\(diagnostic)")
                    return nil
                }
                return (result.stdout,result.stderr,result.status)
            }
            let ffmpeg = GORResources.vendorPath("ffmpeg/bin/ffmpeg")
            let ffprobe = GORResources.vendorPath("ffmpeg/bin/ffprobe")
            let wt: Bool = stream   // explicit source identity, never closure existence
            let rwTimeout: String = wt ? "10000000" : "5000000"   // allow a slow cached piece, bounded below the12s open watchdog
            let killAfter: Double = wt ? 12 : 20
            var idDims = ""   // set once the stream is probed
            func carryUsable(_ c: Carry?) -> Carry? { guard let c, c.key == key, ProcessInfo.processInfo.systemUptime - c.at <= SourcePixelCropScanner.carryTTL else { return nil }; return c }
            print("[cropdetect] scan start caller=\(caller.isEmpty ? "?" : caller) wt=\(wt) stereo=\(stereo) file=\((path as NSString).lastPathComponent)")
            func finish(_ rect: CGRect?, _ decisive: Bool, _ why: String = "", starved: Bool = false) {
                DispatchQueue.main.async {
                    if self.valid(e) {
                        self.lastScanStarved = !decisive && starved
                        self.lock.lock(); let c = self.carry; if decisive { self.carry = nil; self.lastDeliveredEpoch = e }; self.lock.unlock()
                        if !decisive, wt, let c = carryUsable(c), c.undelivered {
                            print("[cropdetect] scan ended without a result (\(why)); delivering the decisive rect measured earlier")
                            self.lock.lock(); self.carry = nil; self.lock.unlock(); completion(c.rect,true,1); return
                        }
                        if wt { self.lock.lock(); if SourcePixelCropScanner.progressClearedOnCompletion(decisive: decisive, carryUndelivered: self.carry?.undelivered == true) { self.carry = nil }; self.lock.unlock() }   // a completed indecisive scan leaves no progress behind; only an interrupted scan's exact same-plan progress may seed a later scan
                        if !decisive { print("[cropdetect] scan finished indecisive: \(why.isEmpty ? "no reason recorded" : why)") }
                        completion(rect,decisive,decisive ? 1 : 0)
                    } else if decisive, wt, !stereo {
                        self.lock.lock()
                        let mine = self.mayStoreCancelledCarry(e,key,scanContext)   // never overwrite another file's or a newer scan's carry
                        if mine { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: nil, members: [], sampled: 0, undelivered: true, rect: rect, done: [], ep: e, planned: []) }
                        self.lock.unlock()
                        print(mine ? "[cropdetect] decisive result was cancelled before delivery; kept for the next scan of this file" : "[cropdetect] decisive result was cancelled before delivery and a newer scan owns the state; dropped")
                    }
                }
            }
            // A partial stream must never fall back to the local whole-file plan.
            // Resolve cache admission before opening ffprobe/ffmpeg or reading metadata.
            let overridePositions: [Double]? = samplePositions?()
            let planPositions: [Double] = overridePositions ?? []
            if wt {
                let admitted = overridePositions ?? []
                guard admitted.count >= SourcePixelBounds.earlyMinCount,
                      admitted.allSatisfy({ $0.isFinite && $0 >= 0 }),
                      Set(admitted).count >= SourcePixelBounds.earlyMinCount else {
                    finish(nil,false,"downloaded sample plan unavailable; no source probe opened")
                    return
                }
            }
            self.lock.lock(); guard self.epoch==e else {self.lock.unlock();return}; var c0: Carry? = wt ? carryUsable(self.carry) : nil; let keepFallback: Bool = fresh && c0?.undelivered == true; if fresh { c0 = nil }; if let c = c0, !SourcePixelCropScanner.carryPlanReusable(undelivered: c.undelivered, planned: c.planned, plan: planPositions) { c0 = nil }; if wt { if c0 == nil && !keepFallback { self.carry = nil } }; self.lock.unlock()
            guard FileManager.default.isExecutableFile(atPath:ffmpeg) else { finish(nil,false,"ffmpeg not executable"); return }
            var w=0,h=0,d=duration,pix="",range="",sar=1.0
            var rangeExplicit=false
            if FileManager.default.isExecutableFile(atPath:ffprobe),
               let probe=decode(ffprobe,["-v","error","-rw_timeout",rwTimeout,"-select_streams","v:0","-show_streams","-show_format","-of","json",path],epoch:e,cap:262144,killAfter:killAfter),probe.2==0,
               let root=try? JSONSerialization.jsonObject(with:probe.0) as? [String:Any],
               let stream=(root["streams"] as? [[String:Any]])?.first {
                w=stream["width"] as? Int ?? 0;h=stream["height"] as? Int ?? 0
                let format=root["format"] as? [String:Any]
                d=Double(format?["duration"] as? String ?? "") ?? duration
                let parts=(stream["sample_aspect_ratio"] as? String ?? "1:1").split(separator:":").compactMap{Double($0)}
                if parts.count==2,parts[1]>0 {sar=parts[0]/parts[1]}
                pix=stream["pix_fmt"] as? String ?? "";range=stream["color_range"] as? String ?? ""
                rangeExplicit = range == "tv" || range == "pc"
            } else {
                // ffprobe is optional in the owner's vendor. ffmpeg itself supplies decoder metadata,
                // without installing another binary or using post-render video params.
                guard let meta=decode(ffmpeg,["-hide_banner","-nostdin","-hwaccel","none","-rw_timeout",rwTimeout,"-i",path,"-map","0:v:0","-frames:v","0","-an","-sn","-f","null","-"],epoch:e,cap:4096,killAfter:killAfter) else { finish(nil,false,"probe and metadata open failed: \(lastFailure)");return }
                let text=String(data:meta.1,encoding:.utf8) ?? ""
                guard let line=text.components(separatedBy:"\n").first(where:{$0.contains("Stream #") && $0.contains("Video:")}) else {finish(nil,false,"no video stream line in metadata");return}
                func captures(_ pattern:String,_ text:String) -> [String] {
                    guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return []}
                    return (1..<m.numberOfRanges).compactMap {Range(m.range(at:$0),in:text).map{String(text[$0])}}
                }
                let size=captures(#"(?:,| )([0-9]{2,5})x([0-9]{2,5})(?:[ ,\[])"#,line)
                guard size.count==2 else {finish(nil,false,"no frame size in metadata");return}
                w=Int(size[0]) ?? 0;h=Int(size[1]) ?? 0
                pix=captures(#", ([a-z0-9]+)(?:\(|,)"#,line).first ?? ""
                range=line.contains("(pc") ? "pc" : "tv"
                rangeExplicit = line.contains("(pc") || line.contains("(tv")
                if d<=0 {
                    let times=captures(#"Duration: ([0-9]+):([0-9]+):([0-9.]+)"#,text)
                    if times.count==3 {d=(Double(times[0]) ?? 0)*3600+(Double(times[1]) ?? 0)*60+(Double(times[2]) ?? 0)}
                }
            }
            guard w>0,h>0,w<=16384,h<=16384,w*h<=50000000 else {finish(nil,false,"unusable frame size \(w)x\(h)");return}
            idDims = "\(w)x\(h) \(pix) \(range)"
            if let c = c0, c.dims != "" , c.dims != idDims {   // same path/duration but a different stream: nothing carried applies
                print("[cropdetect] carried measurement is for a different stream (\(c.dims) vs \(idDims)); discarded")
                c0 = nil; self.lock.lock(); self.carry = nil; self.lock.unlock()
            }
            if let c = c0, c.undelivered { print("[cropdetect] replaying the decisive rect measured earlier (same file, \(idDims), probed just now)"); finish(c.rect,true); return }
            let decodedW=w,decodedH=h
            DispatchQueue.main.async { if self.valid(e) { self.decodedWidth=decodedW;self.decodedHeight=decodedH } }
            let bits:Int = pix.contains("16") ? 16 : pix.contains("14") ? 14 : pix.contains("12") ? 12 : pix.contains("10") ? 10 : pix.contains("9") ? 9 : 8
            let full=range=="pc" || pix.hasPrefix("yuvj") || pix.hasPrefix("rgb") || pix.hasPrefix("gbr") || pix.hasPrefix("gray")
            let black=full ? 0 : 16*(1 << max(0,bits-8))
            // Margins are 8-bit-equivalent luma levels: +2 / +12 levels at ANY bit depth. They used to be raw codes, which at 10 bit
            // is only 0.5 / 3 levels, so a dithered or HDR->SDR near-black letterbox bar (a few codes above black) read as picture.
            let levelUnit = 1 << max(0,bits-8)
            let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))
            let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))   // clearly non-black: never ignored as a speck
            // Bar floor test: a bar row stays near-black over the floor. A row is content when any pixel is clearly
            // above the floor (strong, +12 levels) or more than ~0.2% of it exceeds the +2-level margin, so isolated
            // encode-noise pixels inside a bar never move the bound and it lands exactly at the bar/picture step.
            // Dark HDR picture rows (8-bit-eq mean ~30, max ~61 8-bit-eq) are content by both tests, never bar.
            let speckTolerance = max(1, w / 512)
            // Split into typed statements: one nil-coalescing + ternary + map-closure expression made the compiler time out.
            var positions: [Double] = [0.0]
            if let op = overridePositions { positions = op }
            else if d > 0 { positions = [0.0] + (1..<40).map { (i: Int) -> Double in let x: Double = d * Double(i); let y: Double = x / 40.0; return max(0.0, min(d - 0.001, y)) } }
            // Opening phase: frame0 starts immediately, followed by distant confirmations.
            // Reorder the same whole-file targets, never infer bars from an adjacent dark intro.
            // Three agreeing source frames can publish before the remaining37 finish.
            let localOpening = !wt && !fresh && !stereo && overridePositions == nil
            if localOpening, positions.count >= 3 {
                let openingIndices = [0, positions.count - 1, positions.count / 2]
                positions = openingIndices.map { positions[$0] } + positions.enumerated().filter { !openingIndices.contains($0.offset) }.map { $0.element }
            }
            if wt, let c = c0, c.sampled > 0 {
                let unseen: [Double] = positions.filter { (p: Double) -> Bool in !c.done.contains { (d: Double) -> Bool in abs(d - p) < 4 } }   // new frames, not repeats of carried ones
                let pool: [Double] = unseen.count >= 3 ? unseen : positions
                positions = Array(pool.prefix(max(3, positions.count - c.sampled)))
            }
            let transferBatching = TransferProbeAdmission.isSource(path)
            var wtBatching = CropDetector.isWTPlayback(path) // same bounded cached source, not a rendered screenshot
            if transferBatching { positions.sort() } // same exact positions, bounded chronological container reuse
            var batchedFrames: [Double: Data] = [:]
            var done: [Double] = c0?.done ?? []
            let window: Double = (positions.max() ?? 0) - (positions.min() ?? 0)   // samples carried from a cancelled scan count: repeated restarts converge instead of re-measuring everything
            var all: SourcePixelBounds.Bounds? = c0?.bounds; var sampled: Int = c0?.sampled ?? 0   // carried samples from an interrupted scan of the same stream
            var halves:[SourcePixelBounds.Bounds]?
            var members: [SourcePixelBounds.Bounds] = c0?.members ?? []; var interimSent = false; var publishedLocalBounds: SourcePixelBounds.Bounds?; let scanStart = ProcessInfo.processInfo.systemUptime; var sampleSum = 0.0, sampleN = 0
            let rgbVeto = pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty
            let scanDeadline=expires // includes queue, admission, probing and every decode
            for (positionIndex, t) in positions.enumerated() {
                guard self.valid(e) else { print("[cropdetect] scan cancelled mid-run after \(sampled) of \(positions.count) samples (new scan or cancel)"); return }
                if ProcessInfo.processInfo.systemUptime>=scanDeadline { break }
                // Software decode only. cropdetect runs on original decoded samples, no crop/scale/shader.
                // yuv444p16le preserves full-resolution luma code values for the exact safety veto.
                let vf = "cropdetect=limit=\(black+2):round=2:reset=0:skip=0"
                let sourceGray=pix.hasPrefix("gray")
                // The exact veto, stereo bounds and edge diagnostics read ONLY Y.
                // First make the very same YUV16 samples as the old output, then
                // extract Y without range expansion or downscale. RGB stays on
                // the old path and remains vetoed, never guessed from luma.
                let extractLuma = !sourceGray && !rgbVeto
                let outputGray = sourceGray || extractLuma
                let rawPixelFormat=outputGray ? "gray16le" : "yuv444p16le"
                // Limited-range YUV only. Extract Y before conversion so the
                // discarded chroma is not upsampled to 4:4:4/16-bit first.
                // Explicit limited->limited conversion preserves the old Y
                // codes only when source range and tested pixel format are explicit.
                // Full-range retains the old path: its direct-gray codes differ.
                let fastLuma = rangeExplicit && range == "tv" && ["yuv420p","yuv422p","yuv444p","yuv420p10le","yuv422p12le","yuv444p16le"].contains(pix)
                let lumaTail = fastLuma ? ",extractplanes=y,scale=in_range=tv:out_range=tv,format=gray16le" : ",format=yuv444p16le,extractplanes=y"
                let outputFilter = extractLuma ? vf + lumaTail : vf
                let expectedBytes=w*h*(outputGray ? 2 : 6)
                let args = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(t),"-i",path,"-map","0:v:0","-an","-sn","-dn","-vf",outputFilter,"-frames:v","1","-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                let sampleBegan = ProcessInfo.processInfo.systemUptime
                if transferBatching, batchedFrames[t] == nil {
                    let batch = TransferProbeAdmission.cropBatch(positions,index:positionIndex,frameBytes:expectedBytes)
                    if batch.count > 1, let first = batch.first, let last = batch.last {
                        let select = TransferProbeAdmission.cropSelection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded = decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter), decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i, at) in batch.enumerated() { batchedFrames[at] = decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes) }
                            print("[cropdetect] transfer container batch frames=\(batch.count) span_s=\(last-first) opens=1")
                        } else { print("[cropdetect] transfer container batch incomplete; bounded single-frame fallback") }
                    }
                }
                if wtBatching, batchedFrames[t] == nil {
                    let cachedBytes = batchedFrames.values.reduce(0) { $0 + $1.count }
                    let pending = Array(positions[positionIndex...]).filter { batchedFrames[$0] == nil }
                    let batch = BoundedCropFrameBatch.plan(pending, current:t,
                        frameBytes:expectedBytes, cachedBytes:cachedBytes)
                    if batch.count > 1, let first=batch.first, let last=batch.last {
                        let select = BoundedCropFrameBatch.selection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded=decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter),
                           decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i,at) in batch.enumerated() {
                                batchedFrames[at]=decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes)
                            }
                            print("[cropdetect] wt bounded batch frames=\(batch.count) span_s=\(last-first) opens=1 cache_bytes=\(cachedBytes+expectedBytes*batch.count)")
                        } else {
                            wtBatching = false // at most one failed batch; never repeated speculative opens
                            print("[cropdetect] wt batch incomplete; original single-target fallback for rest of scan")
                        }
                    }
                }
                let decoded: (Data,Data,Int32)?
                if let frame = batchedFrames.removeValue(forKey:t) { decoded = (frame,Data(),0) }
                else { decoded = decode(ffmpeg,args,epoch:e,cap:expectedBytes+65536,killAfter:killAfter) }
                guard let decoded, decoded.2 == 0, decoded.0.count == expectedBytes else {
                    if let decoded { failure("\(ReadFailure.incomplete.rawValue) expected=\(expectedBytes) received=\(decoded.0.count) status=\(decoded.2)") }
                    print("[cropdetect] sample failed epoch=\(e) position=\(t) reason=\(lastFailure)")
                    continue
                }
                sampleSum += ProcessInfo.processInfo.systemUptime - sampleBegan; sampleN += 1
                done.append(t); sampled += 1; self.lock.lock(); if self.epoch == e { self.liveSamples = sampled;self.lastProgressAt=ProcessInfo.processInfo.systemUptime }; self.lock.unlock()
                // A fully black sampled frame adds no content. An unreadable frame is not claimed sampled.
                if stereo,let current=SourcePixelBounds.scanHalves(decoded.0,width:w,height:h,threshold:threshold,topBottom:topBottom) {
                    halves=halves.map{[$0[0].union(current[0]),$0[1].union(current[1])]} ?? current
                }
                if let b = SourcePixelBounds.scan(decoded.0,width:w,height:h,threshold:threshold,speck:speckTolerance,strong:strongThreshold) {
                    all = all.map { $0.union(b) } ?? b
                    print("[cropdetect] edge rows sample=\(sampled) t=\(Int(t))s bounds y=\(b.y0)..\(b.y1) (8-bit-eq mean/max, black=\(black), levelUnit=\(levelUnit)): \(SourcePixelBounds.edgeRows(decoded.0,width:w,height:h,bounds:b,black:black,bits:bits,gray:outputGray))")
                    if wt || localOpening, !stereo, !rgbVeto { members.append(b); if members.count > 12 { members.removeFirst() } }
                }
                // Speed: apply as soon as three frames agree, then keep refining (the union only widens).
                // An early apply needs agreement, never a time budget: fewer than earlyMinCount agreeing non-black
                // frames is no early decision. The scan keeps refining and the final union over all frames decides.
                let consensus: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)
                // Overcut guard: the frames behind an early apply must span at least half of the planned window, so one quiet corner of the cache cannot define the crop.
                let covered: Double = (done.max() ?? 0) - (done.min() ?? 0)
                let best: SourcePixelBounds.Bounds? = window > 0 && covered < 0.5 * window ? nil : consensus
                if wt || localOpening, !stereo, !rgbVeto, !interimSent, let interim, let u0 = best {
                    let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0   // never narrower than everything measured so far (members is capped at 12, all is not)
                    let ci = SourcePixelBounds.outward(u,width:w,height:h,stereo:stereo,topBottom:topBottom)
                    if !(ci.x0 == 0 && ci.y0 == 0 && ci.x1 == w && ci.y1 == h) {
                        interimSent = true
                        if localOpening { publishedLocalBounds = ci }
                        let ir = CGRect(x:Double(ci.x0)/Double(w),y:Double(ci.y0)/Double(h),width:Double(ci.x1-ci.x0)/Double(w),height:Double(ci.y1-ci.y0)/Double(h))
                        print("[cropdetect] early apply after \(sampled) samples (\(members.count) non-black, agree): bounds=\(ci.x0),\(ci.y0)-\(ci.x1),\(ci.y1) of \(w)x\(h); refining on the remaining samples")
                        DispatchQueue.main.async { if self.valid(e) { interim(ir, -1) } }   // confidence < 0 marks an early apply (the final result still follows)
                    }
                }
                // Once opening bars are shown, any later sampled picture outside them widens
                // immediately. No new consensus can delay restoration of measured picture pixels.
                if localOpening, let previous = publishedLocalBounds, let all, let interim {
                    let widened = SourcePixelBounds.outward(all.union(previous),width:w,height:h,stereo:false)
                    if widened != previous {
                        publishedLocalBounds = widened
                        let rect = CGRect(x:Double(widened.x0)/Double(w),y:Double(widened.y0)/Double(h),width:Double(widened.x1-widened.x0)/Double(w),height:Double(widened.y1-widened.y0)/Double(h))
                        DispatchQueue.main.async { if self.valid(e) { interim(rect,-1) } }
                    }
                }
                if wt, !stereo { self.lock.lock(); if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: all, members: members, sampled: sampled, undelivered: false, rect: nil, done: done, ep: e, planned: planPositions) }; self.lock.unlock() }   // progress survives a cancel
            }
            let needSamples: Int = samplePositions == nil ? 1 : min(3, positions.count)
            guard sampled >= needSamples, let b = all else { print("[cropdetect] scan produced no samples: positions=\(positions.count) \(w)x\(h) \(pix)"); finish(nil,false,"\(sampled) of \(needSamples) needed samples decoded; lastFailure=\(lastFailure) deadline=\(ProcessInfo.processInfo.systemUptime >= expires)",starved:true); return }
            // RGB -> luma conversion can hide a chromatic nonblack source pixel. Until exact RGB
            // bounds are supported, veto crop rather than claim original-pixel preservation there.
            if pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty {
                finish(nil,true);return
            }
            // An automatic stream scan decides like the early path: fewer than earlyMinCount agreeing non-black
            // frames is no decision. The file stays at the full frame (the frame is sacred); the player-side
            // persistent search re-scans +2s, +5s, +10s, then every 30s while playing, and restarts at once on
            // seek, resolution/aspect change, track switch and cache growth past the scanned range (199az).
            // Manual Detect (fresh) keeps the union rule, and non-stream sources are unchanged.
            if wt, !stereo, !rgbVeto, !fresh, SourcePixelBounds.consistent(members) == nil {
                print("[cropdetect] no agreement among \(members.count) non-black frames - full picture kept, search continues")
                finish(nil,false,"no agreement among \(members.count) non-black frames",starved: members.count < SourcePixelBounds.earlyMinCount);return
            }
            if let eyes=halves {
                let common=eyes[0].union(eyes[1])
                let sx=topBottom ? 1.0 : (Double(w)/Double(h)>=3 ? 1.0:2.0)
                let aspect=Double(common.x1-common.x0)*sx*sar/Double(common.y1-common.y0)
                DispatchQueue.main.async {if self.valid(e){self.perEyeAspect=aspect}}
            }
            let c = SourcePixelBounds.outward(b,width:w,height:h,stereo:stereo,topBottom:topBottom)
            let rect = CGRect(x:Double(c.x0)/Double(w),y:Double(c.y0)/Double(h),
                              width:Double(c.x1-c.x0)/Double(w),height:Double(c.y1-c.y0)/Double(h))
            print("[cropdetect] scan done: sampled=\(sampled)/\(positions.count) bounds=\(c.x0),\(c.y0)-\(c.x1),\(c.y1) of \(w)x\(h) override=\(samplePositions != nil)")
            GeomTrace.log("sourceCrop", "{\"k\":\"sourceCrop\",\"samples\":\(sampled),\"requested\":40,\"unsampledMayBeCut\":true,\"sbs\":\(stereo),\"sbsHorizontalPreserved\":true}")
            if viewportOnly,stereo,let eyes=halves,let viewport=SourcePixelBounds.eyeViewport(eyes,width:w,height:h,topBottom:topBottom) {
                print("[cropdetect] verified per-eye viewport \(viewport) source pixels unchanged")
                finish(viewport == CGRect(x:0,y:0,width:1,height:1) ? nil:viewport,true)
            } else {finish(c.x0 == 0 && c.y0 == 0 && c.x1 == w && c.y1 == h ? nil : rect,true)}
        }
    }
}

// BEGIN relocated CropHTTPReader.swift (195w 2a, behavior unchanged)
import Foundation

/// A source-pixel reader is not the player. Label only gor's loopback WT
/// inputs; leave the URL, seek, frames, decoder and every output byte alone.
enum CropHTTPReader {
    static func arguments(_ args: [String]) -> [String] {
        let input = args.firstIndex(of: "-i").map { $0 + 1 } ?? (args.count - 1)
        guard args.indices.contains(input), let url = URLComponents(string: args[input]),
              url.scheme == "http", ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
              url.queryItems?.contains(where: { $0.name == "gor_stream" }) == true else { return args }
        var result = args
        result.insert(contentsOf: ["-headers", "X-Gor-Reader: analysis\r\n"], at: args.firstIndex(of: "-i") ?? input)
        return result
    }
}
// END relocated CropHTTPReader.swift

// BEGIN relocated FFmpegAnalysisThreads.swift (195w 2a, behavior unchanged)
import Foundation

/// Analysis-only FFmpeg worker pools. Input decoder options and every filter,
/// selected frame, pixel format and crop vote remain unchanged. FFmpeg's
/// decoder -threads option does not bound its separate filter/output pools.
enum FFmpegAnalysisThreads {
    static func arguments(_ args: [String]) -> [String] {
        var result = ["-filter_threads", "1", "-filter_complex_threads", "1"] + args
        if let f = result.lastIndex(of: "-f"), f + 1 < result.count,
           result[f + 1] == "rawvideo", result.last == "pipe:1" {
            result.insert(contentsOf: ["-threads", "1"], at: result.count - 1)
        }
        return result
    }
}
// END relocated FFmpegAnalysisThreads.swift

// BEGIN relocated BoundedCropFrameBatch.swift (195y G2, behavior unchanged)

// One scan's bounded raw-luma cache. This changes neither requested timestamps nor
// their processing order. It only shares a short container decode among targets.
// On incomplete output the scanner retains its existing single-target path.
enum BoundedCropFrameBatch {
    static let byteLimit = 64 * 1024 * 1024
    static let spanLimit = 2.0
    static func plan(_ remaining: [Double], current: Double, frameBytes: Int,
                     cachedBytes: Int = 0) -> [Double] {
        guard current.isFinite, current >= 0, frameBytes > 0,
              cachedBytes >= 0, cachedBytes <= byteLimit,
              frameBytes <= byteLimit - cachedBytes else { return [] }
        let capacity = (byteLimit - cachedBytes) / frameBytes
        var selected = [current]
        for p in remaining.filter({ $0.isFinite && $0 >= 0 }).sorted(by: {
            abs($0-current) == abs($1-current) ? $0 < $1 : abs($0-current) < abs($1-current)
        }) {
            if selected.count >= capacity { break }
            if selected.contains(p) { continue }
            let low = min(selected.min()!, p), high = max(selected.max()!, p)
            if high - low <= spanLimit { selected.append(p) }
        }
        return selected.sorted()
    }
    static func selection(_ positions: [Double]) -> String {
        guard let first = positions.first else { return "0" }
        return positions.map { position in
            let delta = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), position-first)
            return "gte(t,\(delta))*(isnan(prev_selected_t)+lt(prev_selected_t,\(delta)))"
        }.joined(separator: "+")
    }
}
// END relocated BoundedCropFrameBatch.swift

// BEGIN relocated CropAcceptPolicy.swift (195y G2, behavior unchanged)

/// Gate for an automatic crop result (owner VR report 03:19: an SBS film got video-crop=8000x722+0+1636 from a stream scan that sampled the dark
/// intro near playhead 244 s and finished with the playhead at ~1632 s, and the same rect fed the per-eye aspect into the VR180 projection).
/// A result is dropped before anything is applied (no UI crop, no video-crop, no eye aspect) when
///  - it comes from a stream (wt) scan and the playhead moved more than `maxPlayheadDrift` seconds since the scan began (the sampled frames
///    belong to a different part of the film), unless the user asked for it (manual redetect), or
///  - the film is stereo/VR and the crop would keep less than `minKeptFraction` of the frame in either direction (a real letterbox on a
///    side-by-side or VR180 frame never removes that much; cutting it removes film pixels).
enum CropAcceptPolicy {
    static let maxPlayheadDrift: Double = 60
    static let minKeptFraction: Double = 0.55
    static func plausible(rect: CGRect?, stereo: Bool) -> Bool {
        guard let r = rect, stereo else { return true }
        return Double(r.width) >= minKeptFraction && Double(r.height) >= minKeptFraction
    }
    static func accepts(rect: CGRect?, stereo: Bool, startPlayhead: Double?, nowPlayhead: Double, stream: Bool, manual: Bool) -> Bool {
        if rect != nil, stream, !manual, let s = startPlayhead, abs(nowPlayhead - s) > maxPlayheadDrift {
            print("[cropdetect] result dropped: stream scan began at \(Int(s)) s, playhead now \(Int(nowPlayhead)) s (stale samples)")
            return false
        }
        if !plausible(rect: rect, stereo: stereo) {
            print("[cropdetect] result dropped: crop would remove most of a stereo frame \(String(describing: rect))")
            return false
        }
        return true
    }
}

/// Playhead at the moment the current automatic scan was started.
final class CropScanGuard {
    static let shared = CropScanGuard()
    private(set) var startPlayhead: Double?
    func begin(playhead: Double) { startPlayhead = playhead }
}
// END relocated CropAcceptPolicy.swift
// END relocated SourcePixelCrop.swift
// BEGIN relocated WTCropSamples.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// Where the original-pixel crop scan may sample a magnet (wt server) stream.
///
/// A torrent stream has no complete file. The scanner used to seek 40 points spread over the whole duration
/// (and the duration of a buffering stream is a guess), so almost every seek landed on pieces that were never
/// downloaded: every ffmpeg sample failed, `sampled == 0`, and the result was "indecisive" forever. Only time
/// the player itself has already read through the wt server is known to be on disk, and mpv publishes that as
/// demuxer-cache-state seekable-ranges. Sample inside those ranges only. Pixels, thresholds and the veto are
/// untouched: this changes which seconds are decoded, nothing about how.
///
/// Failure this fixes (owner capture 22:18-22:28, 4K magnet stream): "[cropdetect] indecisive result" four times,
/// about 130 s apart, and the menu Detect button answering "no decision yet". The live-capture path for wt
/// playback (runWTAccumulation) is no longer called, so the file scanner is the only detector for a stream.
/// Tests/CropDetect/wt_stream_crop_test.py measures it against a server that only has the first part of the file.
enum WTCropSamples {
    static let sampleCount = 12
    /// Distance kept from the end of a range so the one frame decoded after the seek is also downloaded.
    static let tailMargin = 1.5
    static let minRange = 3.0

    /// Cache tail used when the player cannot report a playhead: the newest downloaded seconds. Film start and end
    /// credits are usually black; what was downloaded last is the part most likely to show the real picture.
    static let tailWindow = 240.0
    /// Manual Detect looks this far either side of the frame on screen.
    static let manualHalfSpan = 12.0
    /// Automatic scans cover the newest `2 * autoBaseHalfSpan * 2^widenLevel` seconds of the downloaded
    /// cache, anchored at its frontier (the furthest downloaded second): 24 s, then 48 s, 96 s, ... reaching
    /// backwards. Narrowest window first: the newest seconds are the freshest evidence, and while they
    /// disagree the frontier itself keeps advancing into new content, so the level grows only when the
    /// newest window was starved of bright frames - never because mixed old/new content disagreed, since
    /// reaching further back is what fed intro cards into the sample set. The applied crop only ever
    /// widens and a seek restarts the search (199az), so an early apply from a narrow window cannot
    /// permanently cut a wider geometry that is buffered behind it. The sample count never grows with the window.
    static let autoBaseHalfSpan = 12.0

    /// Usable seconds of each downloaded range (tail margin kept), sorted by start.
    static func usable(_ ranges: [(Double, Double)]) -> [(Double, Double)] {
        ranges.filter { $0.0.isFinite && $0.1.isFinite && $0.1 - $0.0 >= minRange }
            .map { (max(0, $0.0), $0.1 - tailMargin) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
    }

    /// Evenly spaced positions over the union length of the given segments (chronological order).
    static func spread(_ segs: [(Double, Double)], count: Int) -> [Double] {
        let total = segs.reduce(0.0) { $0 + ($1.1 - $1.0) }
        guard total > 0, count > 0 else { return [] }
        var out: [Double] = []
        for i in 0..<count {
            var u = total * (Double(i) + 0.5) / Double(count)
            for r in segs {
                let len = r.1 - r.0
                if u <= len { out.append(r.0 + u); break }
                u -= len
            }
        }
        return out
    }

    /// Pure: evenly spaced positions over the union length of the usable ranges. Empty when no range is usable.
    static func positions(ranges: [(Double, Double)], count: Int = sampleCount) -> [Double] {
        spread(usable(ranges), count: count)
    }

    /// Sampling order: start at the sample nearest `seed` (newest frame for automatic scans, the frame on screen for manual), then
    /// always take the sample farthest from those already taken. The first three frames therefore span the whole window, so an early
    /// apply cannot be decided by one quiet corner of the cache.
    static func spreadOrder(_ ps: [Double], seed: Double) -> [Double] {
        var rest: [Double] = ps
        var out: [Double] = []
        guard let si = rest.indices.min(by: { (a: Int, b: Int) -> Bool in abs(rest[a] - seed) < abs(rest[b] - seed) }) else { return [] }
        out.append(rest.remove(at: si))
        while !rest.isEmpty {
            let taken: [Double] = out
            let gaps: [Double] = rest.map { (p: Double) -> Double in taken.map { (t: Double) -> Double in abs(t - p) }.min() ?? 0 }
            guard let fi = gaps.indices.max(by: { (a: Int, b: Int) -> Bool in gaps[a] < gaps[b] }) else { break }
            out.append(rest.remove(at: fi))
        }
        return out
    }

    /// Pure plan for a stream scan. Manual: around the playhead (the frame the user sees), inside the downloaded range
    /// nearest to it, nearest samples first. Automatic: the newest `2 * autoBaseHalfSpan * 2^widenLevel` seconds of the
    /// downloaded cache, anchored at the frontier (the furthest downloaded second), intersected with the downloaded
    /// ranges, newest samples first; no playhead needed. Manual with no reported playhead: the last `tailWindow`
    /// seconds of the downloaded ranges, newest first. Every position
    /// is inside a downloaded range with the tail margin kept. Empty when nothing is usable.
    static func plan(ranges: [(Double, Double)], playhead: Double?, manual: Bool, count: Int = sampleCount, widenLevel: Int = 0) -> [Double] {
        let segs = usable(ranges)
        guard !segs.isEmpty, count > 0 else { return [] }
        if manual, let now = playhead, now.isFinite {
            func dist(_ r: (Double, Double)) -> Double { now < r.0 ? r.0 - now : (now > r.1 ? now - r.1 : 0) }
            guard let r = segs.min(by: { dist($0) < dist($1) }) else { return [] }
            let c = min(max(now, r.0), r.1)
            let lo = max(r.0, c - manualHalfSpan), hi = min(r.1, c + manualHalfSpan)
            guard hi > lo else { return [] }
            return spreadOrder(spread([(lo, hi)], count: count), seed: c)
        }
        if !manual {
            // Automatic: anchor at the cache frontier, the furthest actually usable downloaded
            // second, and look backwards from it; the playhead is not consulted. The newest
            // content is the freshest evidence about the file's bars - intro cards sit at the old
            // end of the cache, and a playhead-anchored window kept spreading samples across them
            // (owner session 2026-11-22: 31 indecisive automatic scans while the cache grew to
            // 120 s; manual Detect around the playhead was decisive within seconds).
            // The frontier end is the MAXIMUM usable end, never merely the last listed range.
            guard let frontier = segs.map({ $0.1 }).max(), frontier > 0 else { return [] }
            let span = 2 * autoBaseHalfSpan * pow(2.0, Double(max(0, widenLevel)))
            let lo = frontier - span
            let win: [(Double, Double)] = segs.compactMap { (s: (Double, Double)) -> (Double, Double)? in
                let a = max(s.0, lo), b = min(s.1, frontier)
                return b > a ? (a, b) : nil
            }
            guard !win.isEmpty else { return [] }
            return spreadOrder(spread(win, count: count), seed: frontier)
        }
        var tail: [(Double, Double)] = []
        var left = tailWindow
        for r in segs.reversed() {
            let take = min(r.1 - r.0, left)
            tail.append((r.1 - take, r.1)); left -= take
            if left <= 0 { break }
        }
        let picked: [Double] = spread(tail.reversed(), count: count)
        return spreadOrder(picked, seed: picked.max() ?? 0)
    }

    /// Raw frontier identity of a dispatch: the furthest range end the player reported, in the SAME
    /// coordinate PPController's cache poll uses (maximum raw `end`, no tail margin, no minRange
    /// filter). Never a sample midpoint: at 24 s/12 samples/tail 1.5 the newest midpoint sits more
    /// than 2 s behind the raw end, so booking the midpoint as the scanned end makes the +2 s growth
    /// rule fire on an unchanged cache (Ops bounded execution 2026-11-22: ranges [0,24] -> plan max
    /// 21.5625, 24 > 23.5625 true with zero growth).
    static func rawFrontierEnd(_ ranges: [(Double, Double)]) -> Double? {
        ranges.compactMap { $0.0.isFinite && $0.1.isFinite ? $0.1 : nil }.max()
    }

    /// Positions for a wt playback path from the running player; plan nil for any other source (scanner keeps its
    /// whole-file positions) or when the player cannot say anything about what is downloaded. The raw frontier
    /// end is the dispatch coverage identity for PPController's growth rule, in the poll's own coordinate.
    static func positions(path: String, mainIPCPath: String?, manual: Bool = false, widenLevel: Int = 0) -> (plan: [Double]?, rawFrontierEnd: Double?) {
        guard (CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)), let ipc = mainIPCPath else { return (nil, nil) }
        let client = IPCClient(path: ipc)
        func property(_ name: String) -> Any? {
            IPCClient.parseFirst(client.queryBatch(MPVCommand.make(["get_property", name]), timeout: 0.5))["data"]
        }
        var ranges: [(Double, Double)] = []
        if let state = property("demuxer-cache-state") as? [String: Any],
           let list = state["seekable-ranges"] as? [[String: Any]] {
            ranges = list.compactMap {
                guard let a = ($0["start"] as? NSNumber)?.doubleValue, let b = ($0["end"] as? NSNumber)?.doubleValue else { return nil }
                return (a, b)
            }
        }
        let playhead = (property("time-pos") as? NSNumber)?.doubleValue
        let frontier = rawFrontierEnd(ranges)
        let spread = plan(ranges: ranges, playhead: playhead, manual: manual, widenLevel: widenLevel)
        // One line per scan so a capture shows what the player said was on disk and where the scan will look.
        let span = ranges.map { String(format: "%.0f-%.0f", $0.0, $0.1) }.joined(separator: ",")
        let hasPlayhead = (playhead ?? .nan).isFinite
        let mode = manual ? (hasPlayhead ? "manual-around-playhead" : "cache-tail") : "auto-cache-frontier"
        print("[cropdetect] wt samples: ranges=[\(span)] positions=\(spread.count) mode=\(mode) playhead=\(playhead.map { String(format: "%.1f", $0) } ?? "?") widen=\(manual ? 0 : max(0, widenLevel))")
        if !spread.isEmpty { return (spread, frontier) }
        if let now = (property("time-pos") as? NSNumber)?.doubleValue, now.isFinite, now >= 0 { return (playedFallback(now: now), frontier) }
        return (nil, frontier)
    }
}


extension WTCropSamples {
    /// No seekable range reported: the seconds just played were read through the server, so sample those.
    /// Up to three distinct seconds (now-4, now-2, now-0.5 clamped at 0); the scanner needs min(3, count) frames.
    static func playedFallback(now: Double) -> [Double] {
        var out: [Double] = []
        for back in [4.0, 2.0, 0.5] {
            let t = max(0, now - back)
            if !out.contains(where: { abs($0 - t) < 0.25 }) { out.append(t) }
        }
        return out
    }

    /// Pure summary used by diagnostics and tests: the first and last sampled second, or nil when none.
    static func span(of positions: [Double]) -> (first: Double, last: Double)? {
        guard let a = positions.min(), let b = positions.max() else { return nil }
        return (a, b)
    }

    /// True when every position lies inside one of the ranges with the tail margin kept, i.e. the whole
    /// sample set is time the player already read through the wt server.
    static func allDownloaded(_ positions: [Double], in ranges: [(Double, Double)]) -> Bool {
        positions.allSatisfy { p in ranges.contains { p >= $0.0 && p <= $0.1 - tailMargin } }
    }
}
// END relocated WTCropSamples.swift
