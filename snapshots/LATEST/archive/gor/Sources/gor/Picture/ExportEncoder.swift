// Picture/ExportEncoder.swift
// Uses: ExportProviderPin, StreamInventoryProbe, ExportCapabilitySource
// Engine: none
// Merged (199ee, pure concatenation, bodies unchanged) from: ExportEncoderCapability.swift, ExportEncoderCapabilityBinding.swift, ExportEncoderConfig.swift, ExportEncoderSettings.swift, ExportCapability.swift, ExportCapabilityDerived.swift, ExportEncodePipeline.swift, ExportPipeline.swift, ExportRunConstruction.swift
import Foundation

// ===== BEGIN merged ExportEncoderCapability.swift =====
// Picture/ExportEncoderCapability.swift
// Lane A: the encoder leg of the Export As Seen capability seam. Present only when the build-bound render-stack declaration, the exact artifact and the really linked provider all agree.
// Uses: ExportProviderPin, StreamInventoryProbe, ExportCapabilitySource
// Engine: none

/// provider/render-stack-v1.json: generated from the real build output by tools/export_render_stack.py (never hand-written, never a constant in the app).
/// It binds one artifact (SHA-256 of the executable), the provider identity the build linked (read from the linked libraries by a probe built from the same archives),
/// the admitted encoder set and the admitted colour tuple. The app re-reads the provider from the libraries it really linked and compares; a declaration that
/// disagrees with the artifact or with the linked libraries is a wrong or stale declaration and the leg is absent.
public struct ExportRenderStackDeclaration: Codable, Equatable {
    public static let schemaID = "gor.render-stack.v1"
    /// Where the declaration lives, relative to a resource root: <root>/provider/render-stack-v1.json. GORResources.renderStackDeclarationURL resolves the root (release set, then sibling Resources);
    /// tools/package_render_stack.py writes the same relative path. Never inside the signed bundle: the declaration binds the signed executable's hash.
    public static let directoryName = "provider"
    public static let fileName = "render-stack-v1.json"
    public struct Artifact: Codable, Equatable { public var name: String; public var sha256: String; public var size: Int64 }
    public struct Provider: Codable, Equatable {
        public var ffmpegVersion: String
        public var avcodecVersion: UInt32, avformatVersion: UInt32, avutilVersion: UInt32, swscaleVersion: UInt32, swresampleVersion: UInt32
        public var x264Build: Int
        public var x265Version: String
        public var license: String
        public var avcodecConfigurationSHA256: String
    }
    public struct Encoder: Codable, Equatable { public var codec: String; public var bitDepth: Int; public var containers: [String] }
    public struct Colour: Codable, Equatable { public var primaries: Int; public var transfer: Int; public var matrix: Int; public var range: String }
    public var schema: String
    public var artifact: Artifact
    public var provider: Provider
    public var encoders: [Encoder]
    public var colour: Colour
    /// Informational build evidence (archive SHA-256 under the prefix). Not compared at run time: the linked libraries are what the app can read.
    public var archives: [String: String]?
}

/// Everything the encoder leg is decided from. Pure data plus two closures so the decision is testable without libav and never reads a constant for "linked".
public struct ExportEncoderEvidence {
    public var declarationData: Data?
    public var pin: ExportProviderPin?
    /// Reasons the linked provider is not the measured one (ExportLibavBackend.providerMismatch); empty = measured provider.
    public var providerMismatch: [String]
    /// nil = the (codec, container) pair is linked and muxable; otherwise the reason.
    public var availability: (String, String) -> String?
    public var artifactSHA256: String?
    public var artifactSize: Int64?
    public init(declarationData: Data?, pin: ExportProviderPin?, providerMismatch: [String], availability: @escaping (String, String) -> String?, artifactSHA256: String?, artifactSize: Int64?) {
        self.declarationData = declarationData; self.pin = pin; self.providerMismatch = providerMismatch; self.availability = availability
        self.artifactSHA256 = artifactSHA256; self.artifactSize = artifactSize
    }
}

public enum ExportEncoderVerdict: Equatable {
    case present([String: String])
    case absent(String)
}

public enum ExportEncoderCapabilityCore {
    /// The admitted encoder set: x264 8-bit and x265 10-bit into matroska, limited SDR BT.709/709/709 (standing decisions; any other declaration is refused, not widened).
    static let admittedEncoders: [(codec: String, depth: Int)] = [("libx264", 8), ("libx265", 10)]
    static let admittedContainers = ["matroska"]

    static func configSHA256(_ s: String) -> String { var h = SHA256Core(); h.update(Array(s.utf8)); return h.finishHex() }

    /// Provider side of a declaration for a pin (used by tests and by the Swift-side declaration check; the generator derives the same fields from the C probe).
    static func providerFields(_ p: ExportProviderPin) -> ExportRenderStackDeclaration.Provider {
        .init(ffmpegVersion: p.ffmpegVersion, avcodecVersion: p.libavcodecVersion, avformatVersion: p.libavformatVersion, avutilVersion: p.libavutilVersion,
              swscaleVersion: p.libswscaleVersion, swresampleVersion: p.libswresampleVersion, x264Build: p.x264Build, x265Version: p.x265Version,
              license: p.license, avcodecConfigurationSHA256: configSHA256(p.avcodecConfiguration))
    }

    /// First failing check wins; reasons are lowercase fragments in the panel's "Not available yet:" style.
    public static func evaluate(_ e: ExportEncoderEvidence) -> ExportEncoderVerdict {
        guard let pin = e.pin else { return .absent("encoder library not linked") }
        guard let data = e.declarationData else { return .absent("render-stack declaration missing") }
        guard let d = try? JSONDecoder().decode(ExportRenderStackDeclaration.self, from: data) else { return .absent("render-stack declaration unreadable") }
        guard d.schema == ExportRenderStackDeclaration.schemaID else { return .absent("render-stack declaration schema not supported") }
        guard let sha = e.artifactSHA256, let size = e.artifactSize else { return .absent("artifact hash could not be read") }
        guard d.artifact.sha256 == sha, d.artifact.size == size else { return .absent("render-stack declaration is for a different build") }
        guard e.providerMismatch.isEmpty else { return .absent("linked encoder library is not the measured provider") }
        guard d.provider == providerFields(pin) else { return .absent("render-stack declaration does not match the linked encoder library") }
        guard d.encoders.count == admittedEncoders.count else { return .absent("render-stack declaration lists an encoder set this build does not admit") }
        for (i, want) in admittedEncoders.enumerated() {
            let got = d.encoders[i]
            guard got.codec == want.codec, got.bitDepth == want.depth, got.containers == admittedContainers else {
                return .absent("render-stack declaration lists an encoder set this build does not admit")
            }
            for c in got.containers { if let why = e.availability(got.codec, c) { return .absent("\(got.codec) into \(c) not available: \(why)") } }
        }
        guard d.colour == .init(primaries: 1, transfer: 1, matrix: 1, range: "limited") else { return .absent("render-stack declaration colour tuple is not limited BT.709") }
        return .present(["declaration": String(sha.prefix(8)), "artifact": String(sha.prefix(8)), "ffmpeg": pin.ffmpegVersion, "x264": String(pin.x264Build),
                         "x265": pin.x265Version, "license": pin.license, "encoders": "libx264/8,libx265/10"])
    }
}

/// The encoder lane's seam conformer. It reports the encoder leg from real evidence and only that leg: the other three legs belong to other lanes and read absent
/// here, so the composition root must merge per leg (take this source's encoderLinked, the others from their lanes) and never present this source alone as readiness.
/// The cache is an immutable snapshot swapped under a lock; reading it never does I/O. refresh hops to a utility queue (hashing the artifact and reading the declaration are I/O) and delivers on main.
public final class LinkedEncoderCapabilitySource: ExportCapabilitySource {
    public static let otherLanes = "not reported by the encoder lane"
    private let lock = NSLock()
    private var cache: ExportCapability
    private let evidence: () -> ExportEncoderEvidence
    private let queue: DispatchQueue
    public init(queue: DispatchQueue = DispatchQueue(label: "gor.export.encoder-capability", qos: .utility), evidence: @escaping () -> ExportEncoderEvidence) {
        self.queue = queue; self.evidence = evidence
        cache = Self.snapshot(.absent("encoder capability not evaluated yet"))
    }
    static func snapshot(_ v: ExportEncoderVerdict) -> ExportCapability {
        let leg: ExportCapabilityLeg
        switch v { case .present(let ev): leg = .present(ev); case .absent(let r): leg = .absent(r) }
        return ExportCapability(encoderLinked: leg, startProviderAssigned: .absent(otherLanes), frameSealChannel: .absent(otherLanes), framesBakedChain: .absent(otherLanes))
    }
    public var cachedSnapshot: ExportCapability { lock.lock(); defer { lock.unlock() }; return cache }
    public func refresh(deliverOnMain: @escaping (ExportCapability) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let snap = Self.snapshot(ExportEncoderCapabilityCore.evaluate(self.evidence()))
            self.lock.lock(); self.cache = snap; self.lock.unlock()
            DispatchQueue.main.async { deliverOnMain(snap) }
        }
    }
}

/// Artifact identity read off-main: SHA-256 of the file (bounded, cancellable) and its size. nil on any failure; the leg then reads absent.
public enum ExportArtifactIdentity {
    public static func read(path: String, seconds: TimeInterval = 120) -> (sha256: String, size: Int64)? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        guard let h = try? StreamInventoryProbe.sha256Hex(fd: fd, budget: InventoryBudget(seconds: seconds), cancel: InventoryCancel()) else { return nil }
        return (h, Int64(st.st_size))
    }
}
// ===== END merged ExportEncoderCapability.swift =====

// ===== BEGIN merged ExportEncoderCapabilityBinding.swift =====
// Picture/ExportEncoderCapabilityBinding.swift
// Lane A -> the capability source: the encoder evidence reader that BoundExportCapability.bind takes. linked is true only when the packaged declaration matches the signed executable and the linked provider.
// Uses: ExportEncoderCapabilityCore, ExportEncoderDeclaration, ExportLibavBackend
// Engine: none

public enum ExportEncoderCapabilityBinding {
    /// The verdict as the source's declaration. `linked` is the verdict's presence, never a constant; an absent verdict keeps its own reason (the panel shows it).
    public static func declaration(_ v: ExportEncoderVerdict) -> ExportEncoderDeclaration {
        switch v {
        case .present(let ev): return ExportEncoderDeclaration(linked: true, evidence: ev)
        case .absent(let r): return ExportEncoderDeclaration(linked: false, reason: r)
        }
    }
    /// Reader over any evidence supplier (tests, or the real one below). Runs only inside the source's off-main refresh: the evidence supplier does the I/O.
    public static func reader(evidence: @escaping () -> ExportEncoderEvidence) -> () -> ExportEncoderDeclaration? {
        { declaration(ExportEncoderCapabilityCore.evaluate(evidence())) }
    }
#if canImport(CGorExport)
    /// The product reader: the linked libraries, the running executable's hash and the declaration file that `declaration()` names (GORResources.renderStackDeclarationURL in the app).
    /// Bind with: ctrl.exportCapabilitySource.bind { $0.encoder = ExportEncoderCapabilityBinding.reader(declaration: { GORResources.renderStackDeclarationURL() }) }
    public static func reader(declaration url: @escaping () -> URL?, artifactPath: String? = nil) -> () -> ExportEncoderDeclaration? {
        reader(evidence: { ExportLibavBackend.encoderEvidence(declaration: url(), artifactPath: artifactPath) })
    }
#else
    /// No provider linked into this build: the honest answer is a typed not-linked, not nil and not a guess.
    public static func reader(declaration url: @escaping () -> URL?, artifactPath: String? = nil) -> () -> ExportEncoderDeclaration? {
        { ExportEncoderDeclaration(linked: false, reason: "encoder library not linked") }
    }
#endif
}
// ===== END merged ExportEncoderCapabilityBinding.swift =====

// ===== BEGIN merged ExportEncoderConfig.swift =====
// Picture/ExportEncoderConfig.swift
// Typed in-process encoder settings translated from the planner's ExportEncoderArgs. Pure Foundation; no libav calls, no CLI.
// Uses: ExportEncoderSettings, ExportJob
// Engine: none

public enum ExportEncoderConfigError: Error, Equatable {
    case unknownArgument(String)
    case missingValue(String)
    case badValue(flag: String, value: String)
    case missing(String)
    case hdrWithX264
    case pixelFormatMismatch(String)
}

public struct ExportMasterDisplayText: Equatable { public var text: String }

public struct ExportEncoderConfig: Equatable {
    public var codec: ExportCodec
    public var width: Int, height: Int
    public var bitDepth: Int
    public var pixelFormat: String
    public var crf: Int
    public var preset: String
    public var tune: String?
    public var h264Profile: String?
    public var vbvMaxrateKbps: Int64
    public var vbvBufsizeKbps: Int64
    public var transfer: ExportTransfer
    public var colorPrimaries: String?
    public var colorMatrix: String?
    public var repeatHeaders: Bool
    public var hdr10Opt: Bool
    public var masterDisplay: String?       // x265 string, passed to the encoder as-is
    public var maxCLL: Int?, maxFALL: Int?
    /// VUI full-range flag as the plan stated it ("limited"/"full"); nil = not stated. Carried, never dropped.
    public var colorRange: String? = nil
    public var hvc1Tag: Bool
    /// Any param the planner emitted that this translator does not model. Refused, never dropped.
}

public enum ExportEncoderTranslator {
    /// Translate the planner args. Every argument must be understood: an unknown flag or x26x param throws.
    public static func translate(_ a: ExportEncoderArgs) throws -> ExportEncoderConfig {
        var w = 0, h = 0, codec: ExportCodec?, pix: String?, preset: String?, tune: String?, prof: String?, crf: Int?, hvc1 = false
        var params: [(String, String)] = []
        var i = 0
        let v = a.arguments
        func value(_ f: String) throws -> String { i += 1; guard i < v.count else { throw ExportEncoderConfigError.missingValue(f) }; return v[i] }
        while i < v.count {
            let f = v[i]
            switch f {
            case "-s":
                let s = try value(f); let p = s.split(separator: "x")
                guard p.count == 2, let ww = Int(p[0]), let hh = Int(p[1]), ww > 0, hh > 0 else { throw ExportEncoderConfigError.badValue(flag: f, value: s) }
                w = ww; h = hh
            case "-c:v":
                let s = try value(f)
                switch s { case "libx264": codec = .x264; case "libx265": codec = .x265; default: throw ExportEncoderConfigError.badValue(flag: f, value: s) }
            case "-profile:v": prof = try value(f)
            case "-pix_fmt": pix = try value(f)
            case "-preset": preset = try value(f)
            case "-tune": tune = try value(f)
            case "-crf":
                let s = try value(f); guard let c = Int(s) else { throw ExportEncoderConfigError.badValue(flag: f, value: s) }; crf = c
            case "-x264-params", "-x265-params":
                for kv in try value(f).split(separator: ":") {
                    let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    guard p.count == 2, !p[0].isEmpty else { throw ExportEncoderConfigError.badValue(flag: f, value: String(kv)) }
                    params.append((p[0], p[1]))
                }
            case "-tag:v":
                let s = try value(f); guard s == "hvc1" else { throw ExportEncoderConfigError.badValue(flag: f, value: s) }; hvc1 = true
            default: throw ExportEncoderConfigError.unknownArgument(f)
            }
            i += 1
        }
        guard let c = codec else { throw ExportEncoderConfigError.missing("-c:v") }
        guard w > 0, h > 0 else { throw ExportEncoderConfigError.missing("-s") }
        guard let px = pix else { throw ExportEncoderConfigError.missing("-pix_fmt") }
        guard let pr = preset else { throw ExportEncoderConfigError.missing("-preset") }
        guard let q = crf else { throw ExportEncoderConfigError.missing("-crf") }
        let depth: Int
        switch (c, px) {
        case (.x264, "yuv420p"): depth = 8
        case (.x265, "yuv420p10le"): depth = 10
        default: throw ExportEncoderConfigError.pixelFormatMismatch("\(c.rawValue) with \(px)")
        }
        var cfg = ExportEncoderConfig(codec: c, width: w, height: h, bitDepth: depth, pixelFormat: px, crf: q, preset: pr, tune: tune, h264Profile: prof,
                                      vbvMaxrateKbps: 0, vbvBufsizeKbps: 0, transfer: .sdr, colorPrimaries: nil, colorMatrix: nil,
                                      repeatHeaders: false, hdr10Opt: false, masterDisplay: nil, maxCLL: nil, maxFALL: nil, colorRange: nil, hvc1Tag: hvc1)
        var sawMax = false, sawBuf = false
        for (k, val) in params {
            switch k {
            case "vbv-maxrate": guard let n = Int64(val), n > 0 else { throw ExportEncoderConfigError.badValue(flag: k, value: val) }; cfg.vbvMaxrateKbps = n; sawMax = true
            case "vbv-bufsize": guard let n = Int64(val), n > 0 else { throw ExportEncoderConfigError.badValue(flag: k, value: val) }; cfg.vbvBufsizeKbps = n; sawBuf = true
            case "colorprim": cfg.colorPrimaries = val
            case "colormatrix": cfg.colorMatrix = val
            case "transfer":
                switch val { case "smpte2084": cfg.transfer = .pq; case "arib-std-b67": cfg.transfer = .hlg; case "bt709": cfg.transfer = .sdr; default: throw ExportEncoderConfigError.badValue(flag: k, value: val) }
            case "range":
                guard val == "limited" || val == "full" else { throw ExportEncoderConfigError.badValue(flag: k, value: val) }
                cfg.colorRange = val
            case "repeat-headers": cfg.repeatHeaders = val == "1"
            case "hdr10-opt": cfg.hdr10Opt = val == "1"
            case "master-display": cfg.masterDisplay = val
            case "max-cll":
                let p = val.split(separator: ",").compactMap { Int($0) }
                guard p.count == 2, p[0] > 0, p[1] > 0, p[1] <= p[0] else { throw ExportEncoderConfigError.badValue(flag: k, value: val) }
                cfg.maxCLL = p[0]; cfg.maxFALL = p[1]
            default: throw ExportEncoderConfigError.unknownArgument("x26x param \(k)")
            }
        }
        guard sawMax, sawBuf else { throw ExportEncoderConfigError.missing("vbv-maxrate/vbv-bufsize") }
        // HDR means the stated signal is HDR: an explicitly stated SDR BT.709 tuple (the plan's
        // source-approved explicit SDR VUI) is not HDR; bt2020 primaries/matrix or HDR static
        // metadata are. A hand-built HDR-on-x264 or 8-bit HDR arg set still refuses here.
        let hdr = cfg.transfer != .sdr || cfg.masterDisplay != nil || cfg.maxCLL != nil ||
                  (cfg.colorPrimaries != nil && cfg.colorPrimaries != "bt709") ||
                  (cfg.colorMatrix != nil && cfg.colorMatrix != "bt709") ||
                  (cfg.colorRange != nil && cfg.colorRange != "limited")
        if hdr && c == .x264 { throw ExportEncoderConfigError.hdrWithX264 }
        if hdr && depth < 10 { throw ExportEncoderConfigError.pixelFormatMismatch("HDR needs 10-bit") }
        return cfg
    }
}
// ===== END merged ExportEncoderConfig.swift =====

// ===== BEGIN merged ExportEncoderSettings.swift =====
// Picture/ExportEncoderSettings.swift
// Owns the planner-shaped x264 and x265 settings for a profile.
// Uses: none
// Engine: none

/// CLI-shaped settings for the PLANNER only. Item 5 must translate these into libavcodec/x26x settings
/// in-process and test that translation; it must not spawn a second ffmpeg encode from this list.
public struct ExportEncoderArgs: Equatable {
    public var arguments: [String]
    public var notes: [String]          // limitations the UI must show
    public var pixelFormat: String
}

public enum ExportEncoderSettings {
    /// vbv values in kbit/s, floored so rounding never raises the rate above R.
    static func kbps(_ bps: Int64) -> Int64 { max(1, bps / 1000) }

    /// `colour` is the ColorPlan computed for this exact job (CP1: the pipeline/preflight calls
    /// ExportColorWiring.planColor with the decoded source signal, the look snapshot and the render
    /// statement). The hand-written colour table is deleted: every colour parameter is the plan's
    /// own rendering. Explicit SDR VUI on both codecs is a deliberate behaviour delta, not a
    /// native pixel qualification.
    public static func build(profile: ExportProfile, crf: Int, source: ExportSource, budget: ExportBudget, raster: (w: Int, h: Int), mux: ExportMuxPlan, colour: ColorPlan) throws -> ExportEncoderArgs {
        try budget.revalidate(for: source)
        guard ExportQuality.allowedCRF.contains(crf) else { throw ExportRefusal.invalidQuality("CRF \(crf)") }
        guard raster.w >= 2, raster.h >= 2, raster.w % 2 == 0, raster.h % 2 == 0 else { throw ExportRefusal.invalidRaster }
        guard colour.codec.rawValue == profile.codec.rawValue else { throw ExportRefusal.invalidLook("colour plan is for \(colour.codec), profile asks \(profile.codec)") }
        // Equivalent effective plan->frame-path guard, from plan fields only (never bare Source.isHDR):
        // ColorPlan.plan already refuses HDR on <10-bit at the resolved signal (ColorPlan.swift:576-578);
        // this keeps the invariant at the args boundary for any hand-built plan.
        if colour.signal.isHighDynamicRange, colour.mapping.codecContext.bitDepth < 10 {
            throw ExportRefusal.hdrNeedsTenBitFramePath(bits: colour.mapping.codecContext.bitDepth)
        }
        let maxrate = kbps(budget.videoRateBps)
        let (bufsize, ov) = maxrate.multipliedReportingOverflow(by: 2)
        guard !ov else { throw ExportRefusal.numericOverflow("vbv-bufsize") }
        let vbv = "vbv-maxrate=\(maxrate):vbv-bufsize=\(bufsize)"
        var notes: [String] = ["VBV bounds rate, not total muxed bytes; the measured .partial size is the final 2x gate",
                               "settings are planner-shaped; the in-process encoder must translate and test them"]
        notes.append(contentsOf: colour.notes)
        notes.append(contentsOf: colour.dispositions.map(ExportEncoderSettings.dispositionNote))
        var args: [String] = ["-s", "\(raster.w)x\(raster.h)"]
        switch profile.codec {
        case .x264:
            let colourParams = colour.mapping.vuiParameterPairs.map { "\($0.key)=\($0.value)" }
            args += ["-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-preset", "slow", "-tune", "grain",
                     "-crf", String(crf), "-x264-params", ([vbv] + colourParams).joined(separator: ":")]
            return ExportEncoderArgs(arguments: args, notes: notes, pixelFormat: "yuv420p")
        case .x265:
            var p = [vbv]
            p += colour.mapping.vuiParameterPairs.map { "\($0.key)=\($0.value)" }
            p += colour.mapping.x265Params.map { "\($0.key)=\($0.value)" }
            for sd in colour.mapping.sideData {
                switch sd {
                case .attachMasteringDisplay(let md): p.append("master-display=\(md.x265String)")
                case .attachContentLightLevel(let stats): p.append("max-cll=\(stats.x265Value)")
                case .dropDolbyVisionConfigurationRecord, .dropDolbyVisionRPUFrames, .dropDynamicHDRPlusFrames: break  // drop plans have no CLI shape; the dispositions carry the note
                }
            }
            args += ["-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-preset", "slow", "-tune", "grain",
                     "-crf", String(crf), "-x265-params", p.joined(separator: ":")]
            if ExportContainerPlan.mp4Family.contains(mux.ext) { args += ["-tag:v", "hvc1"] }   // QuickTime tag, mp4/mov only
            return ExportEncoderArgs(arguments: args, notes: notes, pixelFormat: "yuv420p10le")
        }
    }

    /// Plain-words rendering of a plan disposition for the UI notes list.
    static func dispositionNote(_ d: MetadataDisposition) -> String {
        switch d {
        case .retainMasteringDisplay(let r): return "mastering display written: \(r)"
        case .omitMasteringDisplay(let r): return "mastering display not written: \(r)"
        case .writeMeasuredLight(let m): return "MaxCLL/MaxFALL written from the whole-output measurement (\(m.maxCLL)/\(m.maxFALL))"
        case .retainSourceLight(let m, let r): return "source MaxCLL/MaxFALL retained (\(m.maxCLL)/\(m.maxFALL)): \(r)"
        case .omitLightStatistics(let r): return "MaxCLL/MaxFALL not written: \(r)"
        case .invalidateDolbyVisionRPU(let r): return "Dolby Vision: \(r)"
        case .invalidateHDR10Plus(let r): return "HDR10+: \(r)"
        }
    }
}
// ===== END merged ExportEncoderSettings.swift =====

// ===== BEGIN merged ExportCapability.swift =====
// Picture/ExportCapability.swift
// The typed capability seam for Export As Seen: every readiness leg is present-or-reason, never a static true.
// Uses: none
// Engine: none

/// One capability leg. `.present` carries a small evidence map from the lane that proved it (empty when the
/// lane has nothing to cite); `.absent` always carries the real reason. A reason-less absent is a bug.
public enum ExportCapabilityLeg: Equatable {
    case present([String: String])
    case absent(String)
    public var isPresent: Bool { if case .present = self { return true }; return false }
    public var reason: String? { if case .absent(let r) = self { return r }; return nil }
    public var evidence: [String: String] { if case .present(let e) = self { return e }; return [:] }
}

/// An immutable snapshot of the four legs (ruling 2026-11-26 + Lane A amendment). The UI reads only snapshots;
/// computing one (probe/declaration I/O) happens off-main in the source's refresh, never on a UI read.
/// The snapshot type names the file (structure gate F1).
public struct ExportCapability: Equatable {
    public let encoderLinked: ExportCapabilityLeg
    public let startProviderAssigned: ExportCapabilityLeg
    public let frameSealChannel: ExportCapabilityLeg
    public let framesBakedChain: ExportCapabilityLeg
    public init(encoderLinked: ExportCapabilityLeg, startProviderAssigned: ExportCapabilityLeg,
                frameSealChannel: ExportCapabilityLeg, framesBakedChain: ExportCapabilityLeg) {
        self.encoderLinked = encoderLinked; self.startProviderAssigned = startProviderAssigned
        self.frameSealChannel = frameSealChannel; self.framesBakedChain = framesBakedChain
    }
    /// Start is offered only when ALL FOUR legs are present (Lane A amendment): encoder really linked, real
    /// Start provider assigned, native frame/seal channel composed, verified frames-baked chain. No static true.
    public var startCapable: Bool {
        encoderLinked.isPresent && startProviderAssigned.isPresent && frameSealChannel.isPresent && framesBakedChain.isPresent
    }
    /// The absent legs as (name, reason) pairs, in display order. Reasons are lowercase fragments, matching
    /// the panel's existing "Not available yet:" item style.
    public var absentLegs: [(name: String, reason: String)] {
        var out: [(String, String)] = []
        if let r = encoderLinked.reason { out.append(("encoder linked", r)) }
        if let r = startProviderAssigned.reason { out.append(("start provider assigned", r)) }
        if let r = frameSealChannel.reason { out.append(("frame/seal channel", r)) }
        if let r = framesBakedChain.reason { out.append(("frames-baked verified chain", r)) }
        return out
    }
}

/// The seam Lane E defines and the lanes conform to (Lane A: encoder/declaration evidence, Lane B: frame/seal
/// channel, Lane C: frames-baked chain). UI reads are I/O-free by contract: the source computes once off-main
/// into the immutable cached snapshot, the panel reads only the cache, and a refresh replaces it.
public protocol ExportCapabilitySource {
    /// The cached immutable snapshot. Reading it is I/O-free and non-blocking; the UI reads only this.
    var cachedSnapshot: ExportCapability { get }
    /// Recompute the state off-main (all probe/declaration I/O belongs here), replace the cache, and deliver
    /// the new snapshot on main.
    func refresh(deliverOnMain: @escaping (ExportCapability) -> Void)
}

/// Today's truthful state until the lanes bind their evidence: every leg absent with its real reason, except
/// the provider-assignment leg, which reflects the composition root's actual assignment. The default holds no
/// I/O, so its refresh delivers inline; conformers with real probes must hop off-main first.
public struct UnboundExportCapability: ExportCapabilitySource {
    public let providerAssigned: Bool
    public init(providerAssigned: Bool) { self.providerAssigned = providerAssigned }
    public var cachedSnapshot: ExportCapability {
        ExportCapability(encoderLinked: .absent("no build-bound capability declaration yet"),
                         startProviderAssigned: providerAssigned ? .present(["assignment": "composition root"]) : .absent("no start provider assigned at the composition root"),
                         frameSealChannel: .absent("no native frame/seal channel composed yet"),
                         framesBakedChain: .absent("no verified frames-baked chain yet"))
    }
    public func refresh(deliverOnMain: @escaping (ExportCapability) -> Void) { deliverOnMain(cachedSnapshot) }
}
// ===== END merged ExportCapability.swift =====

// ===== BEGIN merged ExportCapabilityDerived.swift =====
// Picture/ExportCapabilityDerived.swift
// The capability source built from the evidence the lanes bind: each leg is present only when its evidence says so, else absent with a reason.
// Uses: Foundation, Picture/ExportCapability
// Engine: none

/// What the build declares about the encoder (Lane D). `linked` is a statement the build makes, not a probe result.
public struct ExportEncoderDeclaration: Equatable {
    public let linked: Bool
    public let evidence: [String: String]
    /// Why the encoder is not linked, when the reader knows (lowercase fragment). nil falls back to the generic reason.
    public let reason: String?
    public init(linked: Bool, evidence: [String: String] = [:], reason: String? = nil) { self.linked = linked; self.evidence = evidence; self.reason = reason }
}

/// What the player reports about the native frame/seal channel (Lane B/C): `composed` is true only when a channel object really exists.
public struct ExportChannelEvidence: Equatable {
    public let composed: Bool
    public let evidence: [String: String]
    public init(composed: Bool, evidence: [String: String] = [:]) { self.composed = composed; self.evidence = evidence }
}

/// What the frames-baked chain reports: `verified` is true only when the chain's own verification passed.
public struct ExportFramesBakedEvidence: Equatable {
    public let verified: Bool
    public let evidence: [String: String]
    public init(verified: Bool, evidence: [String: String] = [:]) { self.verified = verified; self.evidence = evidence }
}

/// The evidence readers. Each returns nil when its lane has not bound anything (that is "absent", never a guess). The readers may do I/O:
/// they are called only from the source's off-main refresh, never from a UI read.
public struct ExportCapabilityEvidence {
    public var encoder: () -> ExportEncoderDeclaration?
    public var channel: () -> ExportChannelEvidence?
    public var framesBaked: () -> ExportFramesBakedEvidence?
    public init(encoder: @escaping () -> ExportEncoderDeclaration? = { nil },
                channel: @escaping () -> ExportChannelEvidence? = { nil },
                framesBaked: @escaping () -> ExportFramesBakedEvidence? = { nil }) {
        self.encoder = encoder; self.channel = channel; self.framesBaked = framesBaked
    }
    /// Nothing bound: every evidence leg is absent.
    public static let unbound = ExportCapabilityEvidence()
}

/// Derives the four legs from evidence. Pure, no I/O of its own. A leg is present only on affirmative evidence;
/// every absent leg carries the reason a person can act on (lowercase fragment, panel item style).
public enum ExportCapabilityDerivation {
    public static let reasonNoDeclaration = "no build-bound capability declaration yet"
    public static let reasonNotLinked = "the encoder is not linked in this build"
    public static let reasonNoProvider = "no start provider assigned at the composition root"
    public static let reasonNoChannel = "no native frame/seal channel composed yet"
    public static let reasonChannelNotComposed = "the native frame/seal channel is not composed"
    public static let reasonNoChain = "no verified frames-baked chain yet"
    public static let reasonChainNotVerified = "the frames-baked chain is not verified"

    public static func encoderLeg(_ d: ExportEncoderDeclaration?) -> ExportCapabilityLeg {
        guard let d else { return .absent(reasonNoDeclaration) }
        return d.linked ? .present(d.evidence) : .absent(d.reason ?? reasonNotLinked)
    }
    public static func providerLeg(assigned: Bool) -> ExportCapabilityLeg {
        assigned ? .present(["assignment": "composition root"]) : .absent(reasonNoProvider)
    }
    public static func channelLeg(_ c: ExportChannelEvidence?) -> ExportCapabilityLeg {
        guard let c else { return .absent(reasonNoChannel) }
        return c.composed ? .present(c.evidence) : .absent(reasonChannelNotComposed)
    }
    public static func framesBakedLeg(_ f: ExportFramesBakedEvidence?) -> ExportCapabilityLeg {
        guard let f else { return .absent(reasonNoChain) }
        return f.verified ? .present(f.evidence) : .absent(reasonChainNotVerified)
    }
    public static func derive(evidence e: ExportCapabilityEvidence, providerAssigned: Bool) -> ExportCapability {
        ExportCapability(encoderLinked: encoderLeg(e.encoder()), startProviderAssigned: providerLeg(assigned: providerAssigned),
                         frameSealChannel: channelLeg(e.channel()), framesBakedChain: framesBakedLeg(e.framesBaked()))
    }
}

/// The real capability source. `cachedSnapshot` is a lock-protected read with no I/O: the three evidence legs come from the last refresh
/// (all absent until the first refresh finishes), and the provider leg is read live through `providerAssigned` (a lock-protected flag).
/// `refresh` runs the evidence readers on `computeQueue`, replaces the cache, then delivers the new snapshot on `deliverQueue` (main by default).
/// Lanes bind their readers with `bind`; a later refresh picks them up.
public final class BoundExportCapability: ExportCapabilitySource {
    private let lock = NSLock()
    private var evidence: ExportCapabilityEvidence
    private var cache: ExportCapability
    private let providerAssigned: () -> Bool
    private let computeQueue: DispatchQueue
    private let deliverQueue: DispatchQueue

    public init(evidence: ExportCapabilityEvidence = .unbound, providerAssigned: @escaping () -> Bool,
                computeQueue: DispatchQueue = DispatchQueue(label: "gor.export.capability", qos: .utility),
                deliverQueue: DispatchQueue = .main) {
        self.evidence = evidence; self.providerAssigned = providerAssigned
        self.computeQueue = computeQueue; self.deliverQueue = deliverQueue
        // First state: nothing computed, so no evidence leg may claim anything.
        self.cache = ExportCapabilityDerivation.derive(evidence: .unbound, providerAssigned: false)
    }

    /// A lane binds (or replaces) its evidence readers. Takes effect at the next refresh.
    public func bind(_ update: (inout ExportCapabilityEvidence) -> Void) {
        lock.lock(); update(&evidence); lock.unlock()
    }

    public var cachedSnapshot: ExportCapability {
        lock.lock(); let c = cache; lock.unlock()
        return ExportCapability(encoderLinked: c.encoderLinked,
                                startProviderAssigned: ExportCapabilityDerivation.providerLeg(assigned: providerAssigned()),
                                frameSealChannel: c.frameSealChannel, framesBakedChain: c.framesBakedChain)
    }

    public func refresh(deliverOnMain: @escaping (ExportCapability) -> Void) {
        computeQueue.async { [self] in
            lock.lock(); let readers = evidence; lock.unlock()
            let fresh = ExportCapabilityDerivation.derive(evidence: readers, providerAssigned: providerAssigned())
            lock.lock(); cache = fresh; lock.unlock()
            let delivered = cachedSnapshot
            deliverQueue.async { deliverOnMain(delivered) }
        }
    }
}
// ===== END merged ExportCapabilityDerived.swift =====

// ===== BEGIN merged ExportEncodePipeline.swift =====
// Picture/ExportEncodePipeline.swift
// ExportPipeline adapter: raw frames from a producer go to an in-process encoder/muxer backend; muxed bytes go to the runner sink.
// Uses: ExportPipeline, ExportEncoderConfig, ExportJob
// Engine: none

public enum ExportFrameError: Error, Equatable {
    case format(String)       // pixel format, depth or raster differs from the encoder config
    case layout(String)       // plane count, stride or plane length cannot hold the raster
    case pts(String)          // negative (a source with negative PTS is refused, not shifted), duplicate or going backwards
}

/// One raw planar 4:2:0 frame plus a receipt of what the feed says it is. The backend re-validates before any encode;
/// RGB-to-YUV conversion is NOT done here (the C backend / libswscale owns it, with explicit colour metadata).
/// 8-bit: 1 byte per sample; 10-bit: 2 bytes little-endian. Planes Y, U, V; chroma is (w+1)/2 x (h+1)/2.
public struct ExportRawFrame {
    public var planes: [Data]
    public var strides: [Int]
    public var width: Int, height: Int, bitDepth: Int
    public var pixelFormat: String
    /// Presentation time in the feed's time base. Frames arrive in presentation (PTS) order, strictly increasing; VFR is carried as given,
    /// never resampled. Reordered DTS / B-frame delay is the encoder's job, not the feed's.
    public var pts: Int64
    /// The producer's (A) rational duration of THIS frame in the feed time base (decoded frame/packet duration). nil = the source did not say. Never guessed here.
    public var duration: Int64?
    /// The producer's own delivery ordinal: 0-based, contiguous, one per DELIVERED frame. Order evidence, never a timestamp (a retry may reuse a presentation request, every delivered frame takes the next ordinal). The pipeline refuses a duplicate or skipped ordinal before any encode; required, so a producer that cannot name it cannot construct a frame.
    public var ordinal: Int64
    public init(planes: [Data], strides: [Int], width: Int, height: Int, bitDepth: Int, pixelFormat: String, pts: Int64, duration: Int64? = nil, ordinal: Int64) {
        self.ordinal = ordinal; self.planes = planes; self.strides = strides; self.width = width; self.height = height
        self.bitDepth = bitDepth; self.pixelFormat = pixelFormat; self.pts = pts; self.duration = duration
    }

    /// Checks the frame against the encoder config and the previous PTS. Throws before anything reaches the encoder.
    public func validate(against c: ExportEncoderConfig, lastPTS: Int64?) throws {
        guard width == c.width, height == c.height else { throw ExportFrameError.format("raster \(width)x\(height) vs \(c.width)x\(c.height)") }
        guard bitDepth == c.bitDepth, pixelFormat == c.pixelFormat else { throw ExportFrameError.format("\(pixelFormat)/\(bitDepth) vs \(c.pixelFormat)/\(c.bitDepth)") }
        guard planes.count == 3, strides.count == 3 else { throw ExportFrameError.layout("needs 3 planes and 3 strides") }
        let bps = bitDepth > 8 ? 2 : 1
        let rows = [height, (height + 1) / 2, (height + 1) / 2], cols = [width, (width + 1) / 2, (width + 1) / 2]
        for i in 0..<3 {
            guard strides[i] >= cols[i] * bps else { throw ExportFrameError.layout("stride \(i) \(strides[i]) < \(cols[i] * bps)") }
            let (need, ov) = strides[i].multipliedReportingOverflow(by: rows[i])
            guard !ov, planes[i].count >= need else { throw ExportFrameError.layout("plane \(i) holds \(planes[i].count) B, needs \(need)") }
        }
        guard pts >= 0 else { throw ExportFrameError.pts("negative \(pts)") }
        if let d = duration, d <= 0 { throw ExportFrameError.pts("duration \(d) must be > 0 or nil") }
        if let l = lastPTS, pts <= l { throw ExportFrameError.pts("\(pts) after \(l)") }
    }
}

public struct ExportTimeBase: Equatable { public var num: Int32; public var den: Int32; public init(num: Int32, den: Int32) { self.num = num; self.den = den } }

/// What the finished container must contain. The backend checks it against the real file.
public struct ExportCopyStream: Equatable {
    public var sourceIndex: Int               // index in ExportSource.streams
    public var stream: ExportSourceStream
}

public struct ExportMuxExpectation: Equatable {
    public var ext: String
    public var videoCodec: ExportCodec
    public var width: Int, height: Int
    public var durationSeconds: Double
    public var primaryVideoIndex: Int         // the one re-encoded stream
    /// Every other source stream (audio, other video, attached pictures, data, subtitles, attachments). Chapters and global metadata
    /// are always expected too. A stream the muxer cannot carry makes the backend refuse; nothing is dropped silently.
    public var copiedStreams: [ExportCopyStream]
}

public enum ExportBackendAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

/// Frame source (producer A). Pushes frames in PRESENTATION (PTS) order, strictly increasing; `deliver` throws when the encoder stops.
/// `interrupt()` is the cancel point for the producer itself (decode, render, wait): it must make a blocked `frames` return or throw promptly.
/// The pipeline forwards its own interrupt() here, so one cancel reaches producer and encoder.
/// Identity of the source file as the planner/A recorded it (NOT read by the encoder from its own open). dev/ino/size/mtime must all be real values.
public struct ExportSourceIdentity: Equatable {
    public var dev: UInt64, ino: UInt64, size: Int64, mtimeNs: Int64
    /// The caller's already-open read descriptor for exactly this file (retained by A / the playing source). When set the encoder dups it and never re-resolves a path, and verify reads the source through it. The caller keeps it open until verify returned. Not part of equality.
    public var fd: Int32?
    public init(dev: UInt64, ino: UInt64, size: Int64, mtimeNs: Int64, fd: Int32? = nil) { self.dev = dev; self.ino = ino; self.size = size; self.mtimeNs = mtimeNs; self.fd = fd }
    public static func == (a: ExportSourceIdentity, b: ExportSourceIdentity) -> Bool { a.dev == b.dev && a.ino == b.ino && a.size == b.size && a.mtimeNs == b.mtimeNs }
    public var isComplete: Bool { ino != 0 && mtimeNs != 0 && size >= 0 }
}

public protocol ExportFrameFeed: AnyObject {
    var timeBase: ExportTimeBase { get }
    /// Source identity captured by the producer/planner when it opened the source. The encoder pins to it.
    var sourceIdentity: ExportSourceIdentity { get }
    /// Ground truth frame count the producer will deliver (decoded-to-EOF count from A). Never derived from duration x fps.
    var expectedFrameCount: Int64 { get }
    /// The producer run this feed delivers under. nil = the feed cannot name its run: construction refuses (no default, never guessed).
    var runContext: ExportProducerRunContext? { get }
    /// Terminal, idempotent release of the producer's resources. Called at most once by the pipeline on every terminal path after the runner took ownership; never called when construction refuses.
    /// true from a release() request until the producer has actually finished it (an asynchronous release may outlive the call). The pipeline reports closePending until this is false.
    var releasePending: Bool { get }
    func release()
    func interrupt()
    func frames(job: ExportJob, deliver: (ExportRawFrame) throws -> Void) throws
}

/// The libav binding: open encoder + muxer, copy audio/subtitle/chapters/attachments/metadata from the source, return muxed bytes.
/// The real implementation is the C bridge; tests use a double.
public protocol ExportEncodeBackend: AnyObject {
    /// Resolved before the UI enables Export. `.unavailable` disables the button and shows the reason.
    var availability: ExportBackendAvailability { get }
    /// Opens encoder and muxer. The muxer writes through the runner's seekable `sink` (write at position, seek within 0...extent). The backend refuses an incomplete identity or expectedFrames <= 0.
    func open(config: ExportEncoderConfig, timeBase: ExportTimeBase, sourcePath: String, identity: ExportSourceIdentity, expectedFrames: Int64, expect: ExportMuxExpectation, sink: ExportSink) throws
    func encode(_ frame: ExportRawFrame) throws
    /// Flushes the encoder, copies the remaining streams, writes the trailer. Throws the libav error text.
    /// Returns the real packet byte counts (encoded video, copied streams) counted at the packet layer before the muxer.
    func finish() throws -> ExportPacketReceipt
    /// Asks a running open/encode/finish/verify to stop. Safe from any thread, must not block.
    func interrupt()
    func close()
    /// Opens the finished file and checks streams, duration and index against `expect`.
    func verify(partialPath: String, expect: ExportMuxExpectation) throws
    /// Evidence of the last verify (see the extension default). Declared here so the existential dispatches to the real backend.
    var videoEndVerified: Bool? { get }
    var videoEndEvidence: String? { get }
    /// Identity of the encoder/muxer libraries this backend actually runs (read from the loaded libraries, never a constant). nil = the backend cannot tell (test doubles).
    var providerPin: ExportProviderPin? { get }
    /// true while close() was requested but a native call is still running (the handle is intentionally not freed yet). Default false; the real backend overrides it.
    var closePending: Bool { get }
}

/// Exact rational (no rounding). den > 0, reduced.
public struct ExportRational: Equatable, Hashable { public let num: Int64, den: Int64; public init(num: Int64, den: Int64) { self.num = num; self.den = den } }

/// One timeline read together with the provider pin of the SAME backend instance that did the read, and the common time base used. D never pairs a pin and a read from different sources.
public struct ExportTimelineReceipt: Equatable {
    public let providerPin: ExportProviderPin?
    public let path: String
    public let commonTbNum: Int, commonTbDen: Int
    public let streams: [ExportPacketTimeline]
    public init(providerPin: ExportProviderPin?, path: String, commonTbNum: Int, commonTbDen: Int, streams: [ExportPacketTimeline]) { self.providerPin = providerPin; self.path = path; self.commonTbNum = commonTbNum; self.commonTbDen = commonTbDen; self.streams = streams }
}
/// Stream inventory and length-framed payload digest of one stream, from the same demux pass as its packet timeline (evidence for E; E owns copy-proof policy).
public struct ExportSourceStreamReading: Equatable {
    public let index: Int, mediaType: Int, codecName: String, codecID: Int, codecTag: UInt32, extradataSize: Int, width: Int, height: Int, sampleRate: Int, channels: Int, disposition: Int
    public let packets: Int64, bytes: Int64, firstPTS: Int64?, lastPTS: Int64?
    public let payloadSHA256: String, extradataSHA256: String
    public init(index: Int, mediaType: Int, codecName: String, codecID: Int, codecTag: UInt32, extradataSize: Int, width: Int, height: Int, sampleRate: Int, channels: Int, disposition: Int, packets: Int64, bytes: Int64, firstPTS: Int64?, lastPTS: Int64?, payloadSHA256: String, extradataSHA256: String) {
        self.index = index; self.mediaType = mediaType; self.codecName = codecName; self.codecID = codecID; self.codecTag = codecTag; self.extradataSize = extradataSize; self.width = width; self.height = height; self.sampleRate = sampleRate; self.channels = channels; self.disposition = disposition
        self.packets = packets; self.bytes = bytes; self.firstPTS = firstPTS; self.lastPTS = lastPTS; self.payloadSHA256 = payloadSHA256; self.extradataSHA256 = extradataSHA256
    }
}
/// Metadata fingerprints of one file (chapters, global tags, per stream tags + disposition + codec identity; volatile muxer tags skipped). Same values gor_export_meta_digest gives.
public struct ExportMetaDigestReading: Equatable {
    public let nbStreams: Int, nbChapters: Int64
    public let chaptersSHA256: String, globalSHA256: String, streamSHA256: [String]
    public init(nbStreams: Int, nbChapters: Int64, chaptersSHA256: String, globalSHA256: String, streamSHA256: [String]) { self.nbStreams = nbStreams; self.nbChapters = nbChapters; self.chaptersSHA256 = chaptersSHA256; self.globalSHA256 = globalSHA256; self.streamSHA256 = streamSHA256 }
}
/// One digest read of ONE demux pass, from either a borrowed descriptor (`path` nil, `before`/`after` = fstat identity at the start and end, equal) or a path (the stage leaf: `path` set, identities nil).
/// Carries the provider pin of the SAME backend instance, the common time base, per stream inventory + payload digest, the packet timelines and the metadata fingerprints.
public struct ExportDigestReceipt: Equatable {
    public let providerPin: ExportProviderPin?
    public let path: String?
    public let before: ExportSourceIdentity?, after: ExportSourceIdentity?
    public let commonTbNum: Int, commonTbDen: Int
    public let streams: [ExportSourceStreamReading]
    public let timelines: [ExportPacketTimeline]
    public let meta: ExportMetaDigestReading
    public init(providerPin: ExportProviderPin?, path: String?, before: ExportSourceIdentity?, after: ExportSourceIdentity?, commonTbNum: Int, commonTbDen: Int, streams: [ExportSourceStreamReading], timelines: [ExportPacketTimeline], meta: ExportMetaDigestReading) {
        self.providerPin = providerPin; self.path = path; self.before = before; self.after = after; self.commonTbNum = commonTbNum; self.commonTbDen = commonTbDen; self.streams = streams; self.timelines = timelines; self.meta = meta
    }
}
public protocol ExportTimelineReading: AnyObject {
    func read(path: String, commonTimeBase: ExportTimeBase) throws -> ExportTimelineReceipt
}
/// Single-pass digest reads (separate protocol so existing ExportTimelineReading conformers are unaffected). Provider pin, inventory, payload digests, timelines and metadata fingerprints come from ONE reader instance.
public protocol ExportDigestReading: AnyObject {
    /// Reads through a BORROWED descriptor (the retained source fd): no path, no re-open, no change to the caller's file offset; the caller keeps the fd open until this returns. Throws when the descriptor's
    /// dev/ino/size/mtime differ from `expected` (the identity A/D hold) or change during the read.
    func readDigest(descriptor: Int32, expected: ExportSourceIdentity, commonTimeBase: ExportTimeBase) throws -> ExportDigestReceipt
    /// Same single pass over a path (the stage leaf, read-only).
    func readDigest(path: String, commonTimeBase: ExportTimeBase) throws -> ExportDigestReceipt
}

/// Packet timeline evidence of one stream (counters + SHA-256, bounded, no arrays). All times are in the stream's own time base unless the name says common.
/// Hashes are hex SHA-256 over 8-byte little-endian fields per packet (see gor_export.h): timeline = (pts, dts, flags), duration = (duration) as a separate hash. `inexactRescales` > 0 means some pts/dts/duration is NOT exactly representable in the common time base
/// (the common hash then holds nearest-rounded values and must not be used as an exactness claim). `lastDuration` is the demuxer's raw last-packet duration (0 = unknown), NOT proof of the exact final duration.
public struct ExportPacketTimeline: Equatable {
    public let index: Int, mediaType: Int
    /// The STREAM'S native time base (what startTime, firstDTS, lastDTS, lastDuration are in). NOT the common time base.
    public let tbNum: Int, tbDen: Int
    /// The common time base the "common" hashes and the inexact/overflow counters were computed in (as passed by the caller). Different from tbNum/tbDen unless the caller chose the stream's own base.
    public let commonTbNum: Int, commonTbDen: Int
    public let startTime: Int64, initialPadding: Int
    public let packets: Int64, noPTSPackets: Int64, noDTSPackets: Int64, keyframePackets: Int64, discardPackets: Int64, corruptPackets: Int64, zeroDurationPackets: Int64
    public let sideDataPackets: Int64, sideDataBytes: Int64, firstDTS: Int64?, lastDTS: Int64?, lastDuration: Int64, inexactRescales: Int64, overflowRescales: Int64, durationInexactRescales: Int64, durationOverflowRescales: Int64, dtsMonotonic: Bool
    public let timelineRawSHA256: String, timelineCommonSHA256: String, sideDataSHA256: String, durationRawSHA256: String, durationCommonSHA256: String
    /// `startTime` is a real value (not libav's "no start time" marker).
    public var startTimeKnown: Bool { startTime != Int64.min }
    /// Native start_time as an EXACT rational number of seconds (startTime * tbNum / tbDen, reduced); nil when unknown or when it does not fit Int64. Not rounded into any time base.
    public var startTimeSeconds: ExportRational? {
        guard startTimeKnown, tbDen > 0 else { return nil }
        let (n, o) = startTime.multipliedReportingOverflow(by: Int64(tbNum)); if o { return nil }
        var a = n.magnitude, b = UInt64(tbDen); while b != 0 { (a, b) = (b, a % b) }
        let g = Int64(max(a, 1)); return ExportRational(num: n / g, den: Int64(tbDen) / g)
    }
    /// The common-time-base hash may be compared for equality ONLY when this is true (every field exact, nothing overflowed), and only with matching source/output identity and stream mapping.
    public var commonHashIsExact: Bool { inexactRescales == 0 && overflowRescales == 0 }
    /// Same for the duration hash alone (demuxer-derived; a stream can have exact timestamps and an inexact or unknown duration).
    public var durationCommonHashIsExact: Bool { durationInexactRescales == 0 && durationOverflowRescales == 0 }
    public init(index: Int, mediaType: Int, tbNum: Int, tbDen: Int, commonTbNum: Int, commonTbDen: Int, startTime: Int64, initialPadding: Int, packets: Int64, noPTSPackets: Int64, noDTSPackets: Int64, keyframePackets: Int64, discardPackets: Int64,
                corruptPackets: Int64, zeroDurationPackets: Int64, sideDataPackets: Int64, sideDataBytes: Int64, firstDTS: Int64?, lastDTS: Int64?, lastDuration: Int64, inexactRescales: Int64, overflowRescales: Int64, durationInexactRescales: Int64, durationOverflowRescales: Int64, dtsMonotonic: Bool,
                timelineRawSHA256: String, timelineCommonSHA256: String, sideDataSHA256: String, durationRawSHA256: String, durationCommonSHA256: String) {
        self.index = index; self.mediaType = mediaType; self.tbNum = tbNum; self.tbDen = tbDen; self.commonTbNum = commonTbNum; self.commonTbDen = commonTbDen; self.startTime = startTime; self.initialPadding = initialPadding; self.packets = packets
        self.noPTSPackets = noPTSPackets; self.noDTSPackets = noDTSPackets; self.keyframePackets = keyframePackets; self.discardPackets = discardPackets; self.corruptPackets = corruptPackets
        self.zeroDurationPackets = zeroDurationPackets; self.sideDataPackets = sideDataPackets; self.sideDataBytes = sideDataBytes; self.firstDTS = firstDTS; self.lastDTS = lastDTS
        self.lastDuration = lastDuration; self.inexactRescales = inexactRescales; self.overflowRescales = overflowRescales; self.durationInexactRescales = durationInexactRescales; self.durationOverflowRescales = durationOverflowRescales; self.durationRawSHA256 = durationRawSHA256; self.durationCommonSHA256 = durationCommonSHA256; self.dtsMonotonic = dtsMonotonic
        self.timelineRawSHA256 = timelineRawSHA256; self.timelineCommonSHA256 = timelineCommonSHA256; self.sideDataSHA256 = sideDataSHA256
    }
}

/// Typed provider pin from the real linked libraries. Versions are libav's packed `(major << 16) | (minor << 8) | micro`. Linux/Darwin builds are NOT expected to share the same values or a hash of them.
public struct ExportProviderPin: Equatable, Hashable {
    public let libavcodecVersion: UInt32, libavformatVersion: UInt32, libavutilVersion: UInt32, libswscaleVersion: UInt32, libswresampleVersion: UInt32
    /// The header versions the bridge was compiled against; a mismatch with the runtime versions means the headers and libraries differ.
    public let headerAvcodecVersion: UInt32, headerAvformatVersion: UInt32, headerAvutilVersion: UInt32
    public let ffmpegVersion: String          // av_version_info()
    public let avcodecConfiguration: String, avformatConfiguration: String, license: String
    public let x264Build: Int                 // X264_BUILD of the linked x264 (names x264_encoder_open_<build>)
    public let x265Version: String, x265BuildInfo: String
    public init(libavcodecVersion: UInt32, libavformatVersion: UInt32, libavutilVersion: UInt32, libswscaleVersion: UInt32, libswresampleVersion: UInt32,
                headerAvcodecVersion: UInt32, headerAvformatVersion: UInt32, headerAvutilVersion: UInt32, ffmpegVersion: String,
                avcodecConfiguration: String, avformatConfiguration: String, license: String, x264Build: Int, x265Version: String, x265BuildInfo: String) {
        self.libavcodecVersion = libavcodecVersion; self.libavformatVersion = libavformatVersion; self.libavutilVersion = libavutilVersion; self.libswscaleVersion = libswscaleVersion; self.libswresampleVersion = libswresampleVersion
        self.headerAvcodecVersion = headerAvcodecVersion; self.headerAvformatVersion = headerAvformatVersion; self.headerAvutilVersion = headerAvutilVersion
        self.ffmpegVersion = ffmpegVersion; self.avcodecConfiguration = avcodecConfiguration; self.avformatConfiguration = avformatConfiguration; self.license = license
        self.x264Build = x264Build; self.x265Version = x265Version; self.x265BuildInfo = x265BuildInfo
    }
    public var headersMatchLibraries: Bool { headerAvcodecVersion == libavcodecVersion && headerAvformatVersion == libavformatVersion && headerAvutilVersion == libavutilVersion }
}

extension ExportEncodeBackend {
    public var providerPin: ExportProviderPin? { nil }
    public var closePending: Bool { false }
    public var availability: ExportBackendAvailability { .available }
    /// Evidence of the LAST verify() of this backend instance: nil = verify has not completed successfully (never ran, threw, or timed out); false = completed but no video-end proof; true = the output video end matched the producer end. Read only after verify returned.
    public var videoEndVerified: Bool? { nil }
    public var videoEndEvidence: String? { nil }
}

public enum ExportMuxPlanner {
    /// Primary video = the only `.video` stream. More than one video stream: the plan has no selected index yet, so refuse rather than guess
    /// (guessing would lose or mis-encode the unselected one).
    public static func expectation(job: ExportJob) throws -> ExportMuxExpectation {
        let st = job.source.streams
        let videos = st.indices.filter { st[$0].kind == .video }
        guard videos.count == 1 else {
            throw ExportPipelineError.backend("source has \(videos.count) video streams and the plan carries no selected primary index")
        }
        let p = videos[0]
        let copied = st.indices.filter { $0 != p }.map { ExportCopyStream(sourceIndex: $0, stream: st[$0]) }
        return ExportMuxExpectation(ext: job.mux.ext, videoCodec: job.profile.codec, width: job.raster.w, height: job.raster.h,
                                    durationSeconds: job.source.durationSeconds, primaryVideoIndex: p, copiedStreams: copied)
    }
}

/// One RGBA64LE frame: 4 channels x UInt16 little-endian, byte order R,G,B,A per pixel, full range, straight alpha (ignored), already encoded in the
/// target primaries/TRC (not verified). `stride` is in BYTES. The Data only has to stay valid until deliver() returns (C copies into its own frame).
/// What the producer says the RGBA64 RGB pixels are (A's verified statement; never auto-filled from the C config). RGB has no YUV matrix: the target YUV matrix/range
/// come from the C config and are checked in effective(for:), separately. Only the SDR BT.709 RGB tuple is qualified.
public struct ExportRGBA64ColorTuple: Equatable {
    public var primaries: String, transfer: String, range: String
    public var alpha: String       // "straight" (ignored by C) or other (refused)
    public var byteOrder: String   // "little" (RGBA64LE) or other (refused)
    public init(primaries: String, transfer: String, range: String, alpha: String, byteOrder: String) { self.primaries = primaries; self.transfer = transfer; self.range = range; self.alpha = alpha; self.byteOrder = byteOrder }
    public static let sdr709 = ExportRGBA64ColorTuple(primaries: "bt709", transfer: "bt709", range: "full", alpha: "straight", byteOrder: "little")
    /// The RGB tuple C can convert for this config (target YUV matrix 709 limited, tagged bt709), or nil when the config is outside the qualified route (HDR, 2020, 601, tagged otherwise; 10-bit only as SDR x265).
    public static func effective(for c: ExportEncoderConfig) -> ExportRGBA64ColorTuple? {
        guard c.transfer == .sdr, c.bitDepth == 8 || (c.bitDepth == 10 && c.codec == .x265), c.masterDisplay == nil, c.maxCLL == nil, c.maxFALL == nil, c.hdr10Opt == false else { return nil }
        guard c.colorPrimaries == nil || c.colorPrimaries == "bt709", c.colorMatrix == nil || c.colorMatrix == "bt709" else { return nil }
        return .sdr709
    }
}

public struct ExportRGBA64Frame {
    public var data: Data
    public var stride: Int
    public var width: Int, height: Int
    public var pts: Int64            // source PTS in the feed time base, unchanged
    public var duration: Int64?      // this frame's own source duration in the same time base (> 0, or nil)
    public var colorTuple: ExportRGBA64ColorTuple?   // producer's statement of the pixel colour; nil is refused
    public var ordinal: Int64        // the producer's own delivery ordinal (see ExportRawFrame.ordinal)
    public init(data: Data, stride: Int, width: Int, height: Int, pts: Int64, duration: Int64? = nil, colorTuple: ExportRGBA64ColorTuple? = nil, ordinal: Int64) {
        self.ordinal = ordinal; self.data = data; self.stride = stride; self.width = width; self.height = height; self.pts = pts; self.duration = duration; self.colorTuple = colorTuple
    }
    public func validate(against c: ExportEncoderConfig, lastPTS: Int64?) throws {
        guard width == c.width, height == c.height else { throw ExportFrameError.format("raster \(width)x\(height) vs \(c.width)x\(c.height)") }
        guard let eff = ExportRGBA64ColorTuple.effective(for: c) else { throw ExportFrameError.format("colour config is outside the qualified RGBA64 route (SDR BT.709 only (8-bit x264, 10-bit x265))") }
        guard let t = colorTuple else { throw ExportFrameError.format("RGBA64 frame carries no colour tuple") }
        guard t == eff else { throw ExportFrameError.format("RGBA64 colour tuple \(t) differs from the encoder colour \(eff)") }
        guard stride >= width * 8 else { throw ExportFrameError.layout("stride \(stride) < \(width * 8)") }
        let (need, ov) = stride.multipliedReportingOverflow(by: height)
        guard !ov, data.count >= need else { throw ExportFrameError.layout("buffer holds \(data.count) B, needs \(need)") }
        guard pts >= 0 else { throw ExportFrameError.pts("negative \(pts)") }
        if let d = duration, d <= 0 { throw ExportFrameError.pts("duration \(d) must be > 0 or nil") }
        if let l = lastPTS, pts <= l { throw ExportFrameError.pts("\(pts) after \(l)") }
    }
}

/// Same contract as ExportFrameFeed (source identity, A's decoded-EOF count, own durations, interrupt) with RGBA64 frames.
public protocol ExportRGBA64FrameFeed: AnyObject {
    var timeBase: ExportTimeBase { get }
    var sourceIdentity: ExportSourceIdentity { get }
    var expectedFrameCount: Int64 { get }
    /// The producer run this feed delivers under. nil = the feed cannot name its run: construction refuses (no default, never guessed).
    var runContext: ExportProducerRunContext? { get }
    /// Terminal, idempotent release of the producer's resources. Called at most once by the pipeline on every terminal path after the runner took ownership; never called when construction refuses.
    /// true from a release() request until the producer has actually finished it (an asynchronous release may outlive the call). The pipeline reports closePending until this is false.
    var releasePending: Bool { get }
    func release()
    func interrupt()
    func frames(job: ExportJob, deliver: (ExportRGBA64Frame) throws -> Void) throws
}

/// A backend that converts RGBA64 itself. SDR BT.709 / BT.2020nc only; anything else is a typed refusal from the backend.
public protocol ExportRGBA64Backend: ExportEncodeBackend {
    func encodeRGBA64(_ data: Data, stride: Int, pts: Int64, duration: Int64?) throws
}

extension ExportUnavailableBackend: ExportRGBA64Backend {
    public func encodeRGBA64(_ data: Data, stride: Int, pts: Int64, duration: Int64?) throws { throw ExportPipelineError.backend(Self.reason) }
}

public final class ExportEncodePipeline: ExportPipeline {
    public var availability: ExportBackendAvailability { backend.availability }
    /// Forwards the real backend's deferred-close state: true while close() was requested but a native call is still running. The runner keeps admission and resources until it is false.
    private let backend: ExportEncodeBackend
    /// One pipeline, two pixel-format routes (YUV planar frames, or RGBA64 converted by the backend). Same open/complete/interrupt/verify behaviour for both.
    private enum Route { case yuv(ExportFrameFeed), rgba64(ExportRGBA64FrameFeed, ExportRGBA64Backend) }
    private let route: Route
    private let lock = NSLock(); private var interrupted = false; private var backendClosed = false
    private var terminalRequested = false; private var running = false
    /// Immutable contract read from the feed ONCE at construction: a mutable feed cannot change its declared count, time base, source or run after admission.
    private let declaredCount: Int64, declaredTimeBase: ExportTimeBase, declaredIdentity: ExportSourceIdentity, declaredRun: ExportProducerRunContext?
    /// The run context this pipeline was constructed for (the capture fence's). run() refuses a feed that does not name exactly this run, so a direct run does not rely on make()'s one-time comparison.
    private let boundRun: ExportProducerRunContext
    /// The backend's close() is called at most once from this pipeline, from run()'s own exit or from release(), whichever comes first (no double-close assumption about the backend).
    private func closeBackendOnce() { lock.lock(); let first = !backendClosed; backendClosed = true; lock.unlock(); if first { backend.close() } }
    private enum FeedRelease { case idle, claimed, called }
    private var feedRelease = FeedRelease.idle
    private var feed: (release: () -> Void, pending: () -> Bool) {
        switch route { case .yuv(let f): return ({ f.release() }, { f.releasePending }); case .rgba64(let f, _): return ({ f.release() }, { f.releasePending }) }
    }
    /// The feed's resources are released only when nothing borrows them: no run() delivery in flight and no backend native call still pending. Otherwise the request stays recorded and is completed from a
    /// later closePending poll (the runner polls it until false). Three separate states: requested (terminalRequested), claimed (one caller owns the call, under the lock), called (f.release() returned);
    /// "completed" additionally needs the producer's own releasePending to be false. The producer's release runs outside the lock. Never blocks the lock.
    private func settleFeedRelease() {
        let backendPending = backend.closePending   // read BEFORE taking pipeline.lock: the backend's own lock is never acquired while this one is held
        lock.lock()
        let go = terminalRequested && feedRelease == .idle && !running && !backendPending
        if go { feedRelease = .claimed }
        lock.unlock()
        if go { feed.release(); lock.lock(); feedRelease = .called; lock.unlock() }
    }
    /// Terminal release request: close the backend (native work; may stay pending), then release the feed once nothing borrows it. Non-blocking and idempotent.
    public func release() { lock.lock(); terminalRequested = true; lock.unlock(); closeBackendOnce(); settleFeedRelease() }
    /// True while the backend close is pending, or the feed release is requested but not completed (waiting for borrowers, claimed and running, or still pending in the producer). The runner keeps admission and resources until false. Polling completes a waiting feed release.
    public var closePending: Bool {
        settleFeedRelease()
        lock.lock(); let requested = terminalRequested; let st = feedRelease; lock.unlock()
        let feedBusy = requested && (st != .called || feed.pending())
        return backend.closePending || feedBusy
    }
    public init(backend: ExportEncodeBackend, feed: ExportFrameFeed, boundTo run: ExportProducerRunContext) {
        self.backend = backend; self.route = .yuv(feed); self.boundRun = run
        declaredCount = feed.expectedFrameCount; declaredTimeBase = feed.timeBase; declaredIdentity = feed.sourceIdentity; declaredRun = feed.runContext
    }
    public init(backend: ExportRGBA64Backend, rgba64Feed feed: ExportRGBA64FrameFeed, boundTo run: ExportProducerRunContext) {
        self.backend = backend; self.route = .rgba64(feed, backend); self.boundRun = run
        declaredCount = feed.expectedFrameCount; declaredTimeBase = feed.timeBase; declaredIdentity = feed.sourceIdentity; declaredRun = feed.runContext
    }
    public var feedRunContext: ExportProducerRunContext? { declaredRun }
    private var timeBase: ExportTimeBase { declaredTimeBase }
    private var identity: ExportSourceIdentity { declaredIdentity }
    private var expectedCount: Int64 { declaredCount }

    public func interrupt() {
        lock.lock(); interrupted = true; lock.unlock()
        switch route { case .yuv(let f): f.interrupt(); case .rgba64(let f, _): f.interrupt() }
        backend.interrupt()
    }
    private var isInterrupted: Bool { lock.lock(); defer { lock.unlock() }; return interrupted }

    public func run(job: ExportJob, sink: ExportSink) throws -> ExportPacketReceipt {
        let cfg: ExportEncoderConfig
        do { cfg = try ExportEncoderTranslator.translate(job.args) } catch { throw ExportPipelineError.backend("encoder settings: \(error)") }
        guard cfg.width == job.raster.w, cfg.height == job.raster.h else { throw ExportPipelineError.backend("encoder raster differs from the job raster") }
        if case .unavailable(let r) = backend.availability { throw ExportPipelineError.backend(r) }
        let expect: ExportMuxExpectation
        do { expect = try ExportMuxPlanner.expectation(job: job) } catch let e as ExportPipelineError { throw e }
        if isInterrupted { throw ExportPipelineError.stopped }   // interrupted before open: no backend work
        guard declaredCount > 0 else { throw ExportPipelineError.backend("the producer declared no positive frame count") }
        guard let run = declaredRun, run == boundRun else { throw ExportPipelineError.backend("the producer does not deliver under the run this pipeline is bound to") }
        lock.lock()
        if terminalRequested || backendClosed { lock.unlock(); throw ExportPipelineError.backend("this pipeline was already released; it cannot run") }
        if running { lock.unlock(); throw ExportPipelineError.backend("this pipeline is already running; a second run is refused") }
        running = true; lock.unlock()
        defer { lock.lock(); running = false; terminalRequested = true; lock.unlock(); closeBackendOnce(); settleFeedRelease() }
        var receipt: ExportPacketReceipt?
        do {
            try backend.open(config: cfg, timeBase: timeBase, sourcePath: job.source.path, identity: identity, expectedFrames: expectedCount, expect: expect, sink: sink)
            var last: Int64?; var delivered: Int64 = 0
            switch route {
            case .yuv(let feed):
                try feed.frames(job: job) { f in
                    if isInterrupted { throw ExportPipelineError.stopped }
                    guard f.ordinal == delivered else { throw ExportPipelineError.backend("frame ordinal \(f.ordinal) is not the next contiguous \(delivered)") }
                    try f.validate(against: cfg, lastPTS: last)
                    try backend.encode(f); last = f.pts; delivered += 1
                }
            case .rgba64(let feed, let rb):
                try feed.frames(job: job) { f in
                    if isInterrupted { throw ExportPipelineError.stopped }
                    guard f.ordinal == delivered else { throw ExportPipelineError.backend("frame ordinal \(f.ordinal) is not the next contiguous \(delivered)") }
                    try f.validate(against: cfg, lastPTS: last)
                    try rb.encodeRGBA64(f.data, stride: f.stride, pts: f.pts, duration: f.duration); last = f.pts; delivered += 1
                }
            }
            if isInterrupted { throw ExportPipelineError.stopped }
            // The producer's own decoded-to-EOF count is the truth: fewer or more delivered frames than it declared is a typed failure before the encoder is finished (no padding, no fps arithmetic).
            guard delivered == expectedCount else { throw ExportPipelineError.backend("frame count: delivered \(delivered), producer expected \(expectedCount)") }
            receipt = try backend.finish()
        } catch ExportPipelineError.stopped { throw ExportPipelineError.stopped }
        catch let e as ExportPipelineError { throw e }
        catch let e as ExportFrameError { throw ExportPipelineError.backend("frame rejected: \(e)") }
        catch { throw ExportPipelineError.backend("\(error)") }
        guard let r = receipt else { throw ExportPipelineError.backend("encoder returned no packet receipt") }
        return r
    }

    /// Post-verify evidence (see the backend protocol). Valid only after verifyMux returned without throwing.
    public var videoEndVerified: Bool? { backend.videoEndVerified }
    public var videoEndEvidence: String? { backend.videoEndEvidence }

    public func verifyMux(partialPath: String, job: ExportJob) throws {
        try backend.verify(partialPath: partialPath, expect: try ExportMuxPlanner.expectation(job: job))
    }
}

/// Backend used until the FFmpeg 7.1 export provider (libx264/libx265 + muxers) is linked: every run refuses with a typed reason, nothing is written.
public final class ExportUnavailableBackend: ExportEncodeBackend {
    public static let reason = "in-process encoder not available: the linked FFmpeg provider has no libx264/libx265 or muxers"
    public init() {}
    public var availability: ExportBackendAvailability { .unavailable(reason: Self.reason) }
    public func open(config: ExportEncoderConfig, timeBase: ExportTimeBase, sourcePath: String, identity: ExportSourceIdentity, expectedFrames: Int64, expect: ExportMuxExpectation, sink: ExportSink) throws {
        throw ExportPipelineError.backend(Self.reason)
    }
    public func encode(_ frame: ExportRawFrame) throws { throw ExportPipelineError.backend(Self.reason) }
    public func finish() throws -> ExportPacketReceipt { throw ExportPipelineError.backend(Self.reason) }
    public func interrupt() {}
    public func close() {}
    public func verify(partialPath: String, expect: ExportMuxExpectation) throws { throw ExportPipelineError.backend(Self.reason) }
}
// ===== END merged ExportEncodePipeline.swift =====

// ===== BEGIN merged ExportPipeline.swift =====
// Picture/ExportPipeline.swift
// The producer-plus-encoder side of an export run: it pushes muxed file bytes to the runner and reports its own packet byte counts.
// Uses: none
// Engine: none

public enum ExportPipelineError: Error, Equatable {
    case stopped                 // the runner refused further bytes (cancel, overrun, finished)
    case backend(String)         // producer or encoder failed
}

/// Raw packet byte counts, counted by the encoder/packet layer on real packets before muxing. Never estimates, never tags muxed chunks.
public struct ExportPacketReceipt: Equatable {
    public let videoPacketBytes: Int64
    public let copiedPacketBytes: Int64
    public init(videoPacketBytes: Int64, copiedPacketBytes: Int64) { self.videoPacketBytes = videoPacketBytes; self.copiedPacketBytes = copiedPacketBytes }
}

/// The runner-owned, bounded, seekable output of one run (what an AVIO writer with seek support needs). The runner owns the descriptor; the pipeline never sees it.
/// Writes go at the current position. Seeks are absolute and may only land inside the bytes already written (0...extent): a seek past the end
/// would create a hole and is refused, which halts the run. `extent` is the high-water mark (max end offset ever written): overwriting
/// earlier bytes (mp4 moov/trailer rewrite) never grows it and is never counted as new bytes. The hard 2x cap applies to extent and to the real file size.
public protocol ExportSink: AnyObject {
    /// Writes `data` at the current position; position advances. Throws .stopped after cancel, overrun, a refused seek or a writer failure.
    func write(_ data: Data) throws
    /// Moves the write position to an absolute offset in 0...extent. Anything else throws .stopped and halts the run.
    func seek(to offset: Int64) throws
    /// Current write position.
    var position: Int64 { get }
    /// High-water mark of written bytes (the file's logical size).
    var extent: Int64 { get }
}

/// One contract, two counters. The pipeline (C) counts raw packets and returns them in the receipt. The runner (D) counts every muxed
/// byte that extends the file through `sink` and enforces the hard 2x total on that. Container overhead is derived: whole file - packet bytes. A chunk
/// from the muxer is never tagged video/copied/container: AVIO chunks mix headers and packets.
public protocol ExportPipeline: AnyObject {
    /// Push the file bytes through `sink` (it may be kept; it throws .stopped once the runner has stopped). Seeking back to rewrite a header/trailer is allowed.
    /// Returns when everything is pushed, with the packet receipt.
    func run(job: ExportJob, sink: ExportSink) throws -> ExportPacketReceipt
    /// Asks a running `run` or `verifyMux` to stop. Safe from any thread, must not block. The runner does not trust it: it waits a bounded grace.
    func interrupt()
    /// Container check of the finished .partial (streams, duration, index). Throws a reason when it is not a valid mux.
    func verifyMux(partialPath: String, job: ExportJob) throws
    /// Evidence from the LAST completed verifyMux only: true = the muxed video end was checked against the producer's own end and matched; false = checked and not provable;
    /// nil = no verify ran or the pipeline gives no evidence. The receipt of `run` exists before verifyMux, so this is the only place the proof can come from. Default nil.
    var videoEndVerified: Bool? { get }
    /// true while a close was requested but a native call is still running, so the handle is not freed yet. The runner keeps the scope and admission and reports backendHung. Default false.
    var closePending: Bool { get }
    /// Terminal release of the pipeline's backend/feed resources after the runner has taken the one-shot lifecycle:
    /// called once by the runner on EVERY terminal path. Must be idempotent; a second call is a no-op. A construction
    /// that refuses never calls it: borrowed inputs stay the caller's to close. Default no-op is only for pipelines
    /// holding no external resources; a pipeline owning a backend or feed overrides with its real terminal release.
    func release()
    /// The producer run the pipeline's feed is bound to, frozen at construction. The runner compares it against the
    /// capture fence's verified run context at admission: a feed bound to another run (or to none) is refused there,
    /// never trusted from the construction seam's one-shot comparison. Default nil (fakes without a feed).
    var feedRunContext: ExportProducerRunContext? { get }
}

public extension ExportPipeline { var videoEndVerified: Bool? { nil }; var closePending: Bool { false }; func release() {}; var feedRunContext: ExportProducerRunContext? { nil } }
// ===== END merged ExportPipeline.swift =====

// ===== BEGIN merged ExportRunConstruction.swift =====
// Picture/ExportRunConstruction.swift
// Builds the one guarded export runner from a planned preflight result, or answers a typed unavailable; it starts nothing.
// Uses: ExportOpenGuard, ExportAsSeenPreflight, ExportJobRunner, ExportEncodePipeline, ExportSnapshotAdapter, ExportCaptureFence, ExportLibavBackend
// Engine: gorav

/// Why no runner was built. Every case means nothing was created, admitted or written. There is no default feed and no default backend.
public enum ExportRunUnavailable: Error, Equatable, CustomStringConvertible {
    case noPlan                              // the preflight gave no job, or no typed capture to bind it to
    case noEncodeBackend                     // no backend was supplied (the linked provider is not connected)
    case backendUnavailable(String)          // a backend exists and says it cannot run; its own reason
    case noFrameFeed                         // no producer: never a made-up feed
    case startFence(ExportRefusal)           // the playing source is not proven to be the planned file
    case feedRunMismatch                     // the feed names no run, or a different producer run than the capture the plan is bound to
    case feedSourceMismatch                  // the feed was opened on a different file than the one planned
    case recheck(ExportRefusal)              // disk, source or output names changed since the plan preview
    case captureNotBound(String)             // the capture does not prove the job: other path, raster or look, unverified producer run, or a receipt for another load
    case heldRoute(String)                   // container, copied-stream or colour/pixel format outside the qualified technical set (ExportOpenGuard)
    case muxPlan(String)                     // the job's stream layout has no mux expectation (for example more than one video stream)

    public var description: String {
        switch self {
        case .noPlan: return "no export plan to run"
        case .noEncodeBackend: return "no encoder backend is connected"
        case .backendUnavailable(let r): return "encoder backend unavailable: \(r)"
        case .noFrameFeed: return "no frame producer is connected"
        case .startFence(let r): return "start refused: \(r)"
        case .feedRunMismatch: return "the frame producer does not deliver under the run the capture is bound to"
        case .feedSourceMismatch: return "the frame producer was opened on a different source file than the plan"
        case .recheck(let r): return "start refused after recheck: \(r)"
        case .captureNotBound(let m): return "capture does not match the planned job: \(m)"
        case .heldRoute(let m): return "route is held: \(m)"
        case .muxPlan(let m): return "no mux plan for this source: \(m)"
        }
    }
}

public enum ExportRunConstruction {
    /// The smallest step between the plan-only preflight and the guarded ExportJobRunner. Order, each step refusing before the next:
    /// plan + capture present, backend present and available, feed present, start fence (playing identity == planned file), feed identity
    /// == planned file, recheckBeforeCommit (disk and output names, run here because the .partial does not exist yet), mux expectation, then the runner.
    /// The capture is bound to the job before anything else by ExportCaptureFence.verifyStored (not duplicated here), and the same fence is passed to the runner.
    /// It binds the capture to this job and path only: it does NOT prove the producer load had settled (the accepted identity is a reply-epoch binding), so construction is not run-bound.
    /// requireVideoEndProof, copyProof and copyProofInterrupt have no defaults: the caller decides, and a nil copyProof keeps the runner fail-closed for jobs with copied streams.
    /// The runner's commit-time `sourceUnchanged` compares the full file identity to the one proven here; it does NOT call
    /// recheckBeforeCommit, because at the commit point our own .partial exists and that recheck would refuse every run.
    /// YUV frame route.
    public static func make(result: ExportPreflightResult, adapter: ExportSnapshotAdapter, currentRunToken: @escaping () -> ExportProducerRunContext?, prepared: ExportPreparedRun? = nil, ownedCommit: ((() -> Void) -> ExportOwnedCommitRefusal?)? = nil, backend: ExportEncodeBackend?, feed: ExportFrameFeed?,
                            fileSystem: ExportFileSystem, admission: ExportAdmission,
                            requireVideoEndProof: Bool, copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<ExportJobRunner, ExportRunUnavailable> {
        build(result: result, adapter: adapter, currentRunToken: currentRunToken, prepared: prepared, ownedCommit: ownedCommit, backend: backend, feedIdentity: feed.map { f in { f.sourceIdentity } }, feedRunContext: feed.map { f in { f.runContext } }, makePipeline: { ExportEncodePipeline(backend: $0, feed: feed!, boundTo: $1) },
              fileSystem: fileSystem, admission: admission, requireVideoEndProof: requireVideoEndProof, copyProof: copyProof, copyProofInterrupt: copyProofInterrupt)
    }

    /// RGBA64 frame route (DRAFT, preparation: the measured path in which the backend converts RGBA64 itself; whether it is the product route is the architect's decision, and a second conversion is unmeasured).
    /// Same fences, order and refusals as the YUV route; only the pipeline differs. The backend must be an ExportRGBA64Backend.
    public static func makeRGBA64(result: ExportPreflightResult, adapter: ExportSnapshotAdapter, currentRunToken: @escaping () -> ExportProducerRunContext?, prepared: ExportPreparedRun? = nil, ownedCommit: ((() -> Void) -> ExportOwnedCommitRefusal?)? = nil, backend: ExportRGBA64Backend?, feed: ExportRGBA64FrameFeed?,
                                  fileSystem: ExportFileSystem, admission: ExportAdmission,
                                  requireVideoEndProof: Bool, copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<ExportJobRunner, ExportRunUnavailable> {
        build(result: result, adapter: adapter, currentRunToken: currentRunToken, prepared: prepared, ownedCommit: ownedCommit, backend: backend, feedIdentity: feed.map { f in { f.sourceIdentity } }, feedRunContext: feed.map { f in { f.runContext } },
              makePipeline: { _, run in ExportEncodePipeline(backend: backend!, rgba64Feed: feed!, boundTo: run) },
              fileSystem: fileSystem, admission: admission, requireVideoEndProof: requireVideoEndProof, copyProof: copyProof, copyProofInterrupt: copyProofInterrupt)
    }

    /// Ownership. Construction never closes what it borrowed: on ANY refusal the caller still owns the backend and the feed and closes them. On success the backend is handed to the runner,
    /// whose single run() closes it on every terminal path (through ExportPipeline.release, idempotent), including a refusal before the pipeline starts. A runner that is built and never run keeps it open: do not discard one.
    private static func build(result: ExportPreflightResult, adapter: ExportSnapshotAdapter, currentRunToken: @escaping () -> ExportProducerRunContext?, prepared: ExportPreparedRun? = nil, ownedCommit: ((() -> Void) -> ExportOwnedCommitRefusal?)? = nil, backend: ExportEncodeBackend?, feedIdentity: (() -> ExportSourceIdentity)?, feedRunContext: (() -> ExportProducerRunContext?)?,
                              makePipeline: (ExportEncodeBackend, ExportProducerRunContext) -> ExportPipeline, fileSystem: ExportFileSystem, admission: ExportAdmission,
                              requireVideoEndProof: Bool, copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<ExportJobRunner, ExportRunUnavailable> {
        let r = construct(result: result, adapter: adapter, currentRunToken: currentRunToken, prepared: prepared, ownedCommit: ownedCommit, backend: backend, feedIdentity: feedIdentity, feedRunContext: feedRunContext, makePipeline: makePipeline, fileSystem: fileSystem, admission: admission,
                          requireVideoEndProof: requireVideoEndProof, copyProof: copyProof, copyProofInterrupt: copyProofInterrupt)
        return r
    }

    private static func construct(result: ExportPreflightResult, adapter: ExportSnapshotAdapter, currentRunToken: @escaping () -> ExportProducerRunContext?, prepared: ExportPreparedRun? = nil, ownedCommit: ((() -> Void) -> ExportOwnedCommitRefusal?)? = nil, backend: ExportEncodeBackend?, feedIdentity: (() -> ExportSourceIdentity)?, feedRunContext: (() -> ExportProducerRunContext?)?,
                                  makePipeline: (ExportEncodeBackend, ExportProducerRunContext) -> ExportPipeline, fileSystem: ExportFileSystem, admission: ExportAdmission,
                                  requireVideoEndProof: Bool, copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<ExportJobRunner, ExportRunUnavailable> {
        guard let job = result.job, let capture = result.capture else { return .failure(.noPlan) }
        // The capture bond is the Photon fence's (single API); it is not copied here. The fence also re-reads the live capture before frames and at commit.
        let fence = ExportCaptureFence(capture: capture, liveCapture: {
            try? adapter.lookSnapshot(for: job.source.path, deadlineSeconds: ExportAsSeenPreflight.captureDeadlineSeconds,
                                      expectedEncodeRaster: PhotonEncodeRaster(width: job.raster.w, height: job.raster.h)) },
                                      currentRunToken: currentRunToken, prepared: prepared, ownedCommit: ownedCommit)
        if let r = fence.verifyStored(job: job) { return .failure(.captureNotBound("\(r)")) }
        guard let backend = backend else { return .failure(.noEncodeBackend) }
        if case .unavailable(let reason) = backend.availability { return .failure(.backendUnavailable(reason)) }
        guard let feedIdentity = feedIdentity else { return .failure(.noFrameFeed) }
        if let r = ExportAsSeenPreflight.startFence(job: job, adapter: adapter) { return .failure(.startFence(r)) }
        // The baseline is the file read now, and it must equal the playing identity read now and the planned bytes/mtime: two reads that differ cannot set a new baseline.
        guard let planned = adapter.fileIdentity(job.source.path), let playing = adapter.playingSourceIdentity(),
              planned.device == playing.device, planned.inode == playing.inode, planned.bytes == playing.bytes, planned.mtimeNs == playing.mtimeNs,
              planned.bytes == job.source.bytes, planned.mtimeNs == job.source.mtimeNs else { return .failure(.startFence(.mediaChangedDuringCapture)) }
        let f = feedIdentity()
        guard f.isComplete, f.dev == planned.device, f.ino == planned.inode, f.size == job.source.bytes, f.mtimeNs == job.source.mtimeNs else {
            return .failure(.feedSourceMismatch)
        }
        // The feed must name the same producer run the capture is bound to (equality of the typed run context; one fence, one run). This is identity, not settlement or a lease.
        guard let feedRun = feedRunContext?(), feedRun == fence.runContext else { return .failure(.feedRunMismatch) }
        if let r = ExportAsSeenPreflight.recheckBeforeCommit(job: job, adapter: adapter) { return .failure(.recheck(r)) }
        // The planned copied-stream set comes from the immutable plan, as the runner requires. A nil copyProof is passed through unchanged:
        // the runner then refuses any job that copies streams (typed muxInvalid), it is never defaulted to a pass here.
        let copied: Int
        do { copied = try ExportMuxPlanner.expectation(job: job).copiedStreams.count }
        catch { return .failure(.muxPlan("\(error)")) }
        // The same single guard a backend's open() consumes; it runs before any pipeline, sink or native state exists.
        let cc = job.colour.mapping.codecContext
        do { try ExportOpenGuard.check(expect: ExportMuxPlanner.expectation(job: job), codec: job.profile.codec, pixelFormat: cc.pixelFormat, bitDepth: cc.bitDepth, colour: cc) }
        catch { return .failure(.heldRoute("\(error)")) }
        let pipeline = makePipeline(backend, feedRun)
        let runner = ExportJobRunner(job: job, fileSystem: fileSystem, pipeline: pipeline, admission: admission,
                                     sourceUnchanged: { adapter.fileIdentity(job.source.path) == planned },
                                     captureFence: fence,
                                     requireVideoEndProof: requireVideoEndProof, copyProof: copyProof, plannedCopiedStreams: copied,
                                     copyProofInterrupt: copyProofInterrupt)
        return .success(runner)
    }
}

#if canImport(CGorExport)
extension ExportRunConstruction {
    /// One libav backend per job, its colour tuple verbatim from the job's plan (no table, no default). Ownership: see the make() doc (the caller closes it on a refusal; a successful hand-off closes it in the runner).
    /// Only compiled when the provider target exists (GOR_EXPORT_PREFIX/GOR_EXPORT_LINK set); otherwise there is no backend to pass and make() answers .noEncodeBackend.
    public static func libavBackend(for job: ExportJob) -> ExportRGBA64Backend {
        ExportLibavBackend(colour: job.colour.mapping.codecContext)
    }
}
#endif

extension ExportRunConstruction {
    /// (2) The panel's encoder state from the REAL job, never a constant (design ruling, relayed 2026-11-26):
    /// nil provider = .notConnected (the provider module is not compiled in); a provider refusal is
    /// .failed(reason); .ready only when the provider answers available AND the job itself passes the ONE
    /// existing admission gate: ExportOpenGuard.check with the job's real mux expectation and codec context
    /// (Matroska, no copied streams, exact codec format/depth, plan/config colour agreement, limited SDR
    /// BT.709). No route table is copied here. The Start-time construction recheck stays.
    public static func encoderState(for job: ExportJob, providerAvailability: () -> ExportBackendAvailability?) -> ExportEncoderState {
        guard let a = providerAvailability() else { return .notConnected }
        if case .unavailable(let r) = a { return .failed(r) }
        let cc = job.colour.mapping.codecContext
        let expect: ExportMuxExpectation
        do { expect = try ExportMuxPlanner.expectation(job: job) }
        catch { return .failed("mux plan: \(error)") }
        do { try ExportOpenGuard.check(expect: expect, codec: job.profile.codec, pixelFormat: cc.pixelFormat, bitDepth: cc.bitDepth, colour: cc) }
        catch { return .failed("\(error)") }
        return .ready
    }
}
// ===== END merged ExportRunConstruction.swift =====
