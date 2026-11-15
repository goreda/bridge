# W-gdb-053 spatial 190d: e2 foundation contract pin (Types.swift full-file pin)
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-053

```packet-json
{
 "packet_id": "W-gdb-053",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/BridgeVTDecode/Types.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "DecodedFrame/PresentationFrame/PresentationBuffer/CodecConfiguration/FrameDecoder vends DecodedFrame (full-file pinned excerpt below); nine optional color/HDR/stereo/projection fields default nil",
  "types": "DecodedFrame { pts: RationalTime?, width, height, digest + 9 optional fields }; PresentationFrame { pixelBuffer: PresentationBuffer, pixelFormat: String + same optional fields, NO digest }; PresentationBuffer final class wrapping elsewhere-owned AnyObject, read-only by contract; CodecConfiguration adds dovi(Data) = actual container configuration bytes, never inferred packet payload",
  "ownership_lifetime": "PresentationBuffer is reference-typed because the buffer is owned elsewhere; read-only consumption by contract; no presentation vending interface added",
  "caller": "spatial lab module consuming the e2 contract (decode/present seams)",
  "callee": "BridgeVTDecode Types.swift (pinned full file)"
 },
 "test": {
  "command": "python3 kits/spatial-190d-e2-pin/check.py kits/spatial-190d-e2-pin/fixtures.json",
  "expected": "exit 0; stdout 'spatial-190d-e2-pin: 4/4 contract rows PASS'; nil-default rows stay nil; a guessed non-nil optional fails its row",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/BridgeVTDecode/",
   "kits/spatial-190d-e2-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the spatial lab (190d) was blocked on the unrecovered e2 foundation contract; the contract is recovered and byte-identical at the pin (Types.swift sha256 15d90863 at both goreda/gorav ae92fcc3 and pin 2112af0d), so the lab needs the exact full-file pin to build against.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: the FULL Types.swift pinned inline below (verified byte-identical against the pin checkout).

## expected behaviour
modules consume the e2 contract exactly as pinned: DecodedFrame stays the measurement/oracle shape with unchanged digest semantics (per-machine digest, asserted stable across two runs on the same host, NOT across hosts); the nine optional fields default nil (nil = not signaled, never an invented value); PresentationFrame requires PresentationBuffer + pixelFormat, carries the same optional fields and NO digest (measurement never rides the presentation path); FrameDecoder keeps vending DecodedFrame; CodecConfiguration.dovi(Data) holds actual container configuration bytes, never inferred packet payload; unsupported backends refuse typed; no HDR/EDR/FEL/native-rendering acceptance follows from these data types.

## exact call site and interface
Sources/BridgeVTDecode/Types.swift full file (pinned excerpt source1). Delivery: spatial module code against this contract + kits/spatial-190d-e2-pin/ checker.

## behaviour that must not change
digest semantics, nil-default rule and the DecodedFrame/PresentationFrame split are pinned; additive defaulted fields only.

## acceptance test (from the product repo)
python3 kits/spatial-190d-e2-pin/check.py kits/spatial-190d-e2-pin/fixtures.json exits 0; every contract row matches the pinned rule; a guessed non-nil optional fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/BridgeVTDecode/Types.swift (sha256 15d90863, lines 1-128 of 128, full file)
```swift id=source1
import Foundation
import BridgeDemux

/// One decoded video frame. `pts` uses the P-A1 RationalTime contract
/// (nil is preserved, never zero). `digest` is the deterministic
/// per-machine pixel digest (PixelDigest); it is recorded, asserted stable
/// across two runs on the same host, and NOT asserted across hosts.
public struct DecodedFrame: Sendable {
    public let pts: RationalTime?      // from the P-A1 RationalTime contract
    public let width: Int
    public let height: Int
    public let digest: String          // deterministic pixel digest, recorded
    // e2 foundation (plan/E2-FOUNDATION-CONTRACT.md, owner block 190 queue
    // item 5): additive defaulted fields only. nil means "not signaled",
    // never an invented value; digest semantics are unchanged.
    public let colorPrimaries: String?      // e.g. "bt709", "bt2020"
    public let transferFunction: String?    // e.g. "bt1886", "pq", "hlg"
    public let colorMatrix: String?
    public let colorRange: String?          // "limited"/"full"
    public let chromaLocation: String?
    public let hdrStaticMetadata: Data?     // opaque; interpreted only by tests that name its format
    public let hdrDynamicMetadata: Data?    // opaque; the dovi RPU oracle consumes it in its own lane
    public let stereoView: String?          // e.g. "mono", "left", "right"
    public let projection: String?          // e.g. "flat", "vr180", "equirect"
    public init(pts: RationalTime?, width: Int, height: Int, digest: String,
                colorPrimaries: String? = nil, transferFunction: String? = nil,
                colorMatrix: String? = nil, colorRange: String? = nil,
                chromaLocation: String? = nil, hdrStaticMetadata: Data? = nil,
                hdrDynamicMetadata: Data? = nil, stereoView: String? = nil,
                projection: String? = nil) {
        self.pts = pts
        self.width = width
        self.height = height
        self.digest = digest
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.chromaLocation = chromaLocation
        self.hdrStaticMetadata = hdrStaticMetadata
        self.hdrDynamicMetadata = hdrDynamicMetadata
        self.stereoView = stereoView
        self.projection = projection
    }
}

/// Opaque presentation buffer reference: a CVPixelBuffer on Darwin, an
/// equivalent opaque handle off-Darwin. Reference-typed because the buffer
/// is owned elsewhere; Sendable by contract of read-only consumption, the
/// same rule the presenter path already applies to frame data.
public final class PresentationBuffer: @unchecked Sendable {
    public let object: AnyObject
    public init(object: AnyObject) { self.object = object }
}

/// e2 presentation frame (plan/E2-FOUNDATION-CONTRACT.md section 1.2): the
/// shape a presenter consumes. It carries NO digest - measurement never
/// rides the presentation path. DecodedFrame stays the measurement/oracle
/// shape; FrameDecoder keeps vending DecodedFrame and no presentation
/// vending interface is added here.
public struct PresentationFrame: Sendable {
    public let pixelBuffer: PresentationBuffer
    public let pixelFormat: String          // e.g. "yuv420p8", "nv12-8", "p010le"
    public let colorPrimaries: String?
    public let transferFunction: String?
    public let colorMatrix: String?
    public let colorRange: String?
    public let chromaLocation: String?
    public let hdrStaticMetadata: Data?
    public let hdrDynamicMetadata: Data?
    public let stereoView: String?
    public let projection: String?
    public init(pixelBuffer: PresentationBuffer, pixelFormat: String,
                colorPrimaries: String? = nil, transferFunction: String? = nil,
                colorMatrix: String? = nil, colorRange: String? = nil,
                chromaLocation: String? = nil, hdrStaticMetadata: Data? = nil,
                hdrDynamicMetadata: Data? = nil, stereoView: String? = nil,
                projection: String? = nil) {
        self.pixelBuffer = pixelBuffer
        self.pixelFormat = pixelFormat
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.chromaLocation = chromaLocation
        self.hdrStaticMetadata = hdrStaticMetadata
        self.hdrDynamicMetadata = hdrDynamicMetadata
        self.stereoView = stereoView
        self.projection = projection
    }
}

/// Typed decoder errors. A backend that cannot run refuses with
/// `.unsupportedBackend` and never fabricates frames.
public enum DecoderError: Error, Equatable, Sendable {
    case unsupportedBackend(String)
    case missingConfiguration(String)
    case malformedConfiguration(String)
    case unknownCodec(String)
    case decodeFailed(String)
}

/// Packet-in, frame-out decoder. `codec` is "h264" or "hevc"; packets
/// arrive in decode (demux) order. `flush` drains reorder; the stream is
/// at EOS afterwards.
public protocol FrameDecoder {
    mutating func open(codec: String, configuration: CodecConfiguration) throws
    mutating func decode(_ packet: DemuxPacket) throws -> [DecodedFrame]
    mutating func flush() throws -> [DecodedFrame]
}

/// Container decoder records are bytes, never inferred from packet payloads.
public enum CodecConfiguration: Equatable, Sendable {
    case avcC(Data)
    case hvcC(Data)
    case inBand
    /// e2 (spec section 3): the dovi configuration record bytes, as container
    /// records are bytes - never inferred from packet payloads. A decoder
    /// that cannot run dovi refuses with .unsupportedBackend, never
    /// fabricates frames.
    case dovi(Data)
}

public extension FrameDecoder {
    mutating func open(codec: String) throws {
        try open(codec: codec, configuration: .inBand)
    }
}
```


## roles and state
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"row": "DecodedFrame minimal init (digest only)", "expect": "all nine optional fields nil; digest recorded verbatim"}, {"row": "PresentationFrame requires pixelBuffer + pixelFormat", "expect": "typed construction; carries NO digest field"}, {"row": "CodecConfiguration.dovi(bytes)", "expect": "bytes are the actual container configuration bytes; inferred packet payload is refused typed"}, {"row": "guessed optional (stereoView set without signalling)", "expect": "row FAILS: nil means not signaled, never an invented value"}]
```
