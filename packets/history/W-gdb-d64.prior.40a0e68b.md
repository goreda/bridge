# W-gdb-d64: 195b-64 follow-on: transport snapshot witness across a coordinated seek (rev 2)

Rev 2 after the ops semantic gate. active-transport-tests H1..H16 never seek. Rev 2 drives the coordinated seek (SeekRequest, tryBegin, execute, completion), which advances the revision only on nativeReady (GorAVSeekContract.swift), so the revision fence is witnessed non-vacuously: H17 requires nativeReady, H18 requires the new revision to equal expected.advanced() and the receipt's nextRevision, H19 requires the pre-seek revision to be refused stale. H21 no longer fails when the byte counter is unknown before the seek (the contract allows nil); when it is known, it must stay known and not decrease. A 20 s watchdog bounds a seek that never completes. If a check fails, fix ActiveTransportSnapshot.capture or the binding fence in FFmpegSoftwareDecoder.activeTransportSnapshot and return it with the patch.

Not in scope: cache percentage, seconds buffered, paused-for-cache or stall inference (the contract forbids them), HUD/native display, HTTPS provider, the legacy seek(toSeconds:) path. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d64",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/active-transport-tests/main.swift",
      "excerpt_block": "ex_test_setup",
      "lines": "75-78"
    },
    {
      "path": "Sources/active-transport-tests/main.swift",
      "excerpt_block": "ex_test_tail",
      "lines": "115-140"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_snapshot_api",
      "lines": "89-101"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_trybegin",
      "lines": "306-311"
    },
    {
      "path": "Sources/GorAVNativeProbeKit/GorAVSeekContract.swift",
      "excerpt_block": "ex_seek_request",
      "lines": "279-303"
    },
    {
      "path": "Sources/GorAVNativeProbeKit/GorAVSeekContract.swift",
      "excerpt_block": "ex_seek_transaction",
      "lines": "534-547"
    },
    {
      "path": "Sources/GorAVNativeProbeKit/GorAVSeekContract.swift",
      "excerpt_block": "ex_seek_outcome",
      "lines": "470-492"
    },
    {
      "path": "Sources/GorAVNativeProbeKit/GorAVSeekContract.swift",
      "excerpt_block": "ex_seek_admission",
      "lines": "723-732"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift",
      "excerpt_block": "ex_snapshot_type",
      "lines": "10-43"
    }
  ],
  "excerpt_sha256_8": {
    "ex_test_setup": "6f18d4dc",
    "ex_test_tail": "38123e75",
    "ex_snapshot_api": "f62cd5f6",
    "ex_trybegin": "91b388fd",
    "ex_seek_request": "6f8dc560",
    "ex_seek_transaction": "51c176fc",
    "ex_seek_outcome": "f23ffe3e",
    "ex_seek_admission": "ede5e398",
    "ex_snapshot_type": "2f8dd79c"
  },
  "interface": {
    "signatures": "No new product API. Used: FFmpegSoftwareDecoder.tryBegin(_ request: SeekRequest) throws -> any SeekTransaction; SeekTransaction.execute() throws and completion() async -> SeekReceipt; SeekRequest(correlationID:session:source:target:expectedRevision:); SeekTarget(position:rounding:requestedFlags:); SeekCorrelationID(rawValue:queueTurn:) throws; RationalTime(value:timescale:) throws; SeekRevision.advanced() throws; currentBinding(); activeTransportSnapshot(source:session:revision:).",
    "types": "ActiveTransportSnapshot(bytesRead: Int64?, bufferAvailableBytes: Int?, eofObserved: Bool?, errorCode: Int32?), ActiveTransportRefusal.notOpen / .staleBinding, SeekReceipt.Outcome.nativeReady(facts:), SeekRevision Equatable, as in the excerpts. Admission requires rounding .floorToKeyframe, requestedFlags & ~1 == 0, position.value >= 0, correlation rawValue greater than the last one.",
    "ownership_lifetime": "The snapshot is a value copy taken in one native-queue turn and never retains the AVIOContext. A fresh open (session 9603) chooses coordinated mode via tryBegin, and the legacy seek(toSeconds:) is not mixed in. The watchdog is cancelled after completion.",
    "caller": "active-transport-tests top-level script.",
    "callee": "FFmpegSoftwareDecoder.tryBegin/performSeek on the native queue, then activeTransportSnapshot reading AVIOContext.bytes_read, eof_reached and error via ActiveTransportSnapshot.capture."
  },
  "test": {
    "command": "swift run active-transport-tests",
    "expected": "Exit 0. Output has PASS H1 through PASS H16 as before, then PASS H17 through PASS H23, and ends with a line starting \"active-transport-tests: 0 FAIL\". If the seek never completes, the line \"FAIL H17: coordinated seek never completed within 20 s\" is printed and the exit code is 1. Requires the repo fixture fixtures/e1-h264-aac-10s.mp4 and python3.",
    "fixture_block": "fx_transport_seek_tests",
    "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
  },
  "target": {
    "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/active-transport-tests/main.swift",
      "Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift",
      "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/active-transport-tests/main.swift",
        "block": "merged_main"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run active-transport-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:38:15.304400+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "active-transport-tests: 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/active-transport-tests/main.swift",
        "block": "merged_main",
        "sha256": "ed1e074a12d136b95a76708af412935306c3fa154a92d1d8b947489d22b0c768"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "872d102e8288f5c9dcd9135d3898e5d560d3d6a6571c40c39398f5ce10ff38c0",
    "last_5_lines": [
      "PASS H20 snapshot served for the post-seek binding",
      "PASS H21 cumulative byte counter not lost or decreased by a seek (unknown-before allowed)",
      "PASS H22 after a seek EOF is true or unknown, never a manufactured false, and no invented error",
      "PASS H23 close clears the post-seek snapshot",
      "active-transport-tests: 0 FAIL (no buffered-seconds/cache/stall inference)"
    ],
    "receipt_sha256": "8e50df627e36e80cea88c4d1ff3db9164c28cd60ffc2016d8a31d476a5be2f52"
  }
}
```

## Excerpt ex_test_setup

```swift id=ex_test_setup
// Sources/active-transport-tests/main.swift lines 75-78 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
let decoder = FFmpegSoftwareDecoder()
try decoder.pinLocalRoots([root])
decoder.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 5)
let sid = SessionID(uncheckedEpoch: 9601)
```

## Excerpt ex_test_tail

```swift id=ex_test_tail
// Sources/active-transport-tests/main.swift lines 115-140 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
check("H10 real decoded frames and end", frames > 0 && ended)
if case .success(let final) = snapshot() {
    check("H11 cumulative observed reads", final.bytesRead != nil && final.bytesRead! >= first.bytesRead!)
    // EOF may be reached through demux semantics without AVIO observing it.
    // Only true or unknown is permitted, never manufactured false/zero.
    check("H12 EOF no prediction", final.eofObserved == nil || final.eofObserved == true)
} else { check("H11 active at EOF", false) }
_ = await decoder.closeAndReport(session: sid)
check("H13 close clears snapshot", snapshot() == .failure(.notOpen))
let newSID = SessionID(uncheckedEpoch: 9602)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: newSID)
check("H14 old binding after reopen refused", snapshot() == .failure(.staleBinding))
guard let reopened = decoder.currentBinding() else { print("FAIL reopen binding"); stopServer(); exit(2) }
check("H15 new open generation", reopened.token != binding.token)
_ = await decoder.closeAndReport(session: newSID)
check("H16 close new binding", decoder.activeTransportSnapshot(source: reopened.token, session: reopened.session, revision: reopened.revision) == .failure(.notOpen))
stopServer()
try? FileManager.default.removeItem(at: directory)
print("active-transport-tests: \(failures) FAIL (no buffered-seconds/cache/stall inference)")
exit(failures == 0 ? 0 : 1)


```

## Excerpt ex_snapshot_api

```swift id=ex_snapshot_api
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 89-101 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public func activeTransportSnapshot(source: SourceToken, session: SeekSessionID,
                                        revision: SeekRevision) -> Result<ActiveTransportSnapshot, ActiveTransportRefusal> {
        l3OnQueue {
            // EOF ends decoding but the retained AVIO remains observable until close.
            guard currentSid != nil, let fmt,
                  let binding = seekState.currentBinding() else { return .failure(.notOpen) }
            guard currentSid == session.rawValue, binding.token == source,
                  binding.session == session, binding.revision == revision else { return .failure(.staleBinding) }
            return .success(ActiveTransportSnapshot.capture(fmt.pointee.pb.map { UnsafePointer($0) },
                source: source, session: session, revision: revision))
        }
    }
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
```

## Excerpt ex_trybegin

```swift id=ex_trybegin
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 306-311 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction {
        try seekState.tryBegin(request) { [self] record in
            nativeQueue.async { [self] in performSeek(record) }
        }
    }
    private func performSeek(_ record: ProviderSeekReservation) {
```

## Excerpt ex_seek_request

```swift id=ex_seek_request
// Sources/GorAVNativeProbeKit/GorAVSeekContract.swift lines 279-303 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
public struct SeekTarget: Sendable {
    public let position: RationalTime      // media-timeline seconds (the ONE coordinate)
    public let rounding: SeekRounding
    public let requestedFlags: Int32       // whitelisted AVSEEK_FLAG_* bits; actual use recorded in facts
    public init(position: RationalTime, rounding: SeekRounding, requestedFlags: Int32) {
        self.position = position
        self.rounding = rounding
        self.requestedFlags = requestedFlags
    }
}

// MARK: - Request

public struct SeekRequest: Sendable {
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let source: SourceToken
    public let target: SeekTarget
    /// Core's expected current provider revision; provider validates expected == actual at queue-turn
    /// (mismatch => .stale) and computes next = expected.advanced().
    public let expectedRevision: SeekRevision
    public init(correlationID: SeekCorrelationID, session: SeekSessionID, source: SourceToken,
                target: SeekTarget, expectedRevision: SeekRevision) {
        self.correlationID = correlationID
        self.session = session
```

## Excerpt ex_seek_transaction

```swift id=ex_seek_transaction
// Sources/GorAVNativeProbeKit/GorAVSeekContract.swift lines 534-547 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
public protocol SeekTransaction: Sendable {
    var identity: SeekEventIdentity { get }
    var correlationID: SeekCorrelationID { get }
    var session: SeekSessionID { get }
    var request: SeekRequest { get }
    /// Provider-issued reserved revision (= expectedRevision.advanced() as validated at queue-turn).
    /// PINNED HANDSHAKE (finding 2): the provider validates expected and computes next; the core
    /// ADOPTS this issued value before execute and does not hold a separately reserved revision.
    var reservedRevision: SeekRevision { get }
    func execute() throws
    func completion() async -> SeekReceipt
    func requestCancellation()
}

```

## Excerpt ex_seek_outcome

```swift id=ex_seek_outcome
// Sources/GorAVNativeProbeKit/GorAVSeekContract.swift lines 470-492 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public enum Outcome: Sendable {
        /// Provider completion evidence ONLY: native reposition + flush promised, revision advances,
        /// new output permitted. NOT target attainment, NOT a decoded PTS, NOT a global commit/ACK.
        /// The ONLY outcome that advances nextRevision.
        case nativeReady(facts: NativeSeekFacts)
        /// Admitted, then REFUSED at queue-turn before any mutation: position and revision UNCHANGED.
        /// Resume is CORE-GATED (the core decides the next action) - NOT a provider success signal.
        case refusedNoMutation(reason: NoMutationRefusal)
        /// Caller-side settlement before any mutation (requested/abandoned/close). Position and
        /// revision UNCHANGED; resume is CORE-GATED. Exactly-one reservation release.
        case cancelledNoMutation(reason: CancelReason)
        /// Post-mutation cancel: native call ran to its own return, cleanup completed with resources
        /// alive. Poison is MANDATORY and is always closeRequired.
        case cancelledAfterCleanup(facts: NativeSeekFacts, poison: PoisonReport)
        /// Typed staged failure at the ACTUAL stage; poison MANDATORY, closeRequired when mutated.
        case failed(stage: ProviderSeekStage, reason: SeekFailureReason,
                    facts: NativeSeekFacts, poison: PoisonReport)
    }
    public let identity: SeekEventIdentity       // composite source+transaction
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let request: SeekRequest              // original target preserved verbatim
    public let previousRevision: SeekRevision
```

## Excerpt ex_seek_admission

```swift id=ex_seek_admission
// Sources/GorAVNativeProbeKit/GorAVSeekContract.swift lines 723-732 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
            guard request.expectedRevision == b.2 else { throw SeekRefusal.stale(expected: request.expectedRevision, actual: b.2) }
            guard request.correlationID.rawValue > lastCorrelation else { throw SeekRefusal.unsupported("replayed correlation") }
            guard capabilityValue.seekable, capabilityValue.originKnown,
                  request.target.rounding == .floorToKeyframe,
                  request.target.requestedFlags & ~Int32(1) == 0 else { throw SeekRefusal.unsupported("unsupported seek target or flags") }
            guard request.target.position.value >= 0 else { throw SeekTimeError.targetBeforeOrigin }
            let next = try b.2.advanced()
            let id = try mint.issue()
            let value = ProviderSeekReservation(identity: SeekEventIdentity(source: b.0, transactionID: id), request: request, revision: next)
            coordinated = true; lastCorrelation = request.correlationID.rawValue; active = value
```

## Excerpt ex_snapshot_type

```swift id=ex_snapshot_type
// Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift lines 10-43 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public let revision: SeekRevision
    /// FFmpeg AVIO bytes_read counter, cumulative for this open. Includes probe
    /// reads and rereads; not network-only unique bytes or file position.
    public let bytesRead: Int64?
    /// Bytes remaining in AVIO's current user-space input buffer only.
    public let bufferAvailableBytes: Int?
    /// true when AVIO has observed EOF; nil before that or without an AVIOContext.
    /// A seek can clear this observation. No prediction that the remote is finished.
    public let eofObserved: Bool?
    /// Negative FFmpeg AVIO error when present; nil means no error observed,
    /// not an assertion that transport is healthy or unable to stall.
    public let errorCode: Int32?

    // Called only inside the format owner's native queue, never retains pb.
    static func capture(_ pb: UnsafePointer<AVIOContext>?, source: SourceToken,
                        session: SeekSessionID, revision: SeekRevision) -> Self {
        guard let pb else {
            return Self(source: source, session: session, revision: revision,
                        bytesRead: nil, bufferAvailableBytes: nil, eofObserved: nil, errorCode: nil)
        }
        let count = pb.pointee.bytes_read
        let available = gorav_avio_buffer_available(pb)
        return Self(source: source, session: session, revision: revision,
                    bytesRead: count >= 0 ? count : nil,
                    bufferAvailableBytes: available >= 0 ? Int(available) : nil,
                    eofObserved: pb.pointee.eof_reached != 0 ? true : nil,
                    errorCode: pb.pointee.error < 0 ? pb.pointee.error : nil)
    }
}

public enum ActiveTransportRefusal: Error, Equatable, Sendable {
    case notOpen, staleBinding
}

```

## Fixture fx_transport_seek_tests

```swift id=fx_transport_seek_tests
// Insert in Sources/active-transport-tests/main.swift after the line:
//   check("H16 close new binding", ...)
// and before: stopServer()
// Uses the COORDINATED seek path (tryBegin/execute/completion), which advances the seek revision only on nativeReady.
let seekWatchdog = DispatchWorkItem { print("FAIL H17: coordinated seek never completed within 20 s"); fflush(stdout); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: seekWatchdog)
let seekSID = SessionID(uncheckedEpoch: 9603)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: seekSID)
guard let b0 = decoder.currentBinding() else { print("FAIL no binding before seek"); stopServer(); exit(2) }
guard case .success(let before) = decoder.activeTransportSnapshot(source: b0.token, session: b0.session, revision: b0.revision) else {
    print("FAIL no snapshot before seek"); stopServer(); exit(2)
}
let seekRequest = SeekRequest(
    correlationID: try SeekCorrelationID(rawValue: 1, queueTurn: 1),
    session: b0.session, source: b0.token,
    target: SeekTarget(position: try RationalTime(value: 5, timescale: 1), rounding: .floorToKeyframe, requestedFlags: 0),
    expectedRevision: b0.revision)
let transaction = try decoder.tryBegin(seekRequest)
try transaction.execute()
let receipt = await transaction.completion()
seekWatchdog.cancel()
var nativeReady = false
if case .nativeReady = receipt.outcome { nativeReady = true }
check("H17 coordinated seek reached nativeReady (otherwise this witness is invalid)", nativeReady, "\(receipt.outcome)")
guard let b1 = decoder.currentBinding() else { print("FAIL no binding after seek"); stopServer(); exit(2) }
check("H18 revision advanced by exactly one step and matches the receipt",
      b1.revision != b0.revision && b1.revision == receipt.nextRevision && b1.revision == (try b0.revision.advanced()))
check("H19 pre-seek revision is refused as stale after the seek",
      decoder.activeTransportSnapshot(source: b0.token, session: b0.session, revision: b0.revision) == .failure(.staleBinding))
let afterResult = decoder.activeTransportSnapshot(source: b1.token, session: b1.session, revision: b1.revision)
var afterSnap: ActiveTransportSnapshot? = nil
if case .success(let s) = afterResult { afterSnap = s }
check("H20 snapshot served for the post-seek binding", afterSnap != nil)
// Contract: nil means unknown. If the counter was unknown before the seek no ordering is asserted;
// if it was known it must stay known and must not decrease (cumulative AVIO counter).
let bytesOK: Bool
if let b = before.bytesRead { bytesOK = (afterSnap?.bytesRead).map { $0 >= b } ?? false } else { bytesOK = true }
check("H21 cumulative byte counter is not lost or decreased by a seek (unknown-before is allowed)", bytesOK,
      "before=\(String(describing: before.bytesRead)) after=\(String(describing: afterSnap?.bytesRead))")
check("H22 after a seek EOF is true or unknown, never a manufactured false, and no invented error",
      (afterSnap?.eofObserved == nil || afterSnap?.eofObserved == true) && afterSnap?.errorCode == nil)
_ = await decoder.closeAndReport(session: seekSID)
check("H23 close clears the post-seek snapshot", decoder.activeTransportSnapshot(source: b1.token, session: b1.session, revision: b1.revision) == .failure(.notOpen))
```

```swift id=merged_main
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// Real local HTTP -> active decoder AVIO counter. Requires pinned provider with
// http/tcp + mov/h264 support; never silently skip a failed/missing provider.
var failures = 0
func check(_ name: String, _ value: Bool) {
    print("\(value ? "PASS" : "FAIL") \(name)")
    if !value { failures += 1 }
}
let root = FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/e1-h264-aac-10s.mp4"
guard FileManager.default.fileExists(atPath: fixture) else {
    print("FAIL missing local fixture"); exit(2)
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let script = directory.appendingPathComponent("server.py")
let portFile = directory.appendingPathComponent("port")
let countFile = directory.appendingPathComponent("requests")
try #"""
import http.server, sys, threading
fixture, portfile, counterfile = sys.argv[1:]
lock = threading.Lock()
requests = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global requests
        with lock:
            requests += 1
            with open(counterfile, 'w') as f: f.write(str(requests))
        with open(fixture, 'rb') as f: data = f.read()
        begin = 0
        header = self.headers.get('Range', '')
        if header.startswith('bytes='):
            begin = int(header[6:].split('-')[0] or 0)
        if begin >= len(data):
            self.send_response(416); self.end_headers(); return
        self.send_response(206 if begin else 200)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(len(data)-begin))
        if begin: self.send_header('Content-Range', 'bytes %d-%d/%d' % (begin,len(data)-1,len(data)))
        self.end_headers()
        try: self.wfile.write(data[begin:])
        except (BrokenPipeError, ConnectionResetError): pass
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(portfile, 'w') as f: f.write(str(server.server_address[1]))
server.serve_forever()
"""#.write(to: script, atomically: true, encoding: .utf8)
let server = Process()
server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
server.arguments = [script.path, fixture, portFile.path, countFile.path]
try server.run()
func stopServer() { if server.isRunning { kill(server.processIdentifier, SIGKILL); server.waitUntilExit() } }
defer { stopServer() }
var port: String?
for _ in 0..<200 {
    if let p = try? String(contentsOf: portFile), !p.isEmpty { port = p; break }
    try await Task.sleep(nanoseconds: 10_000_000)
}
guard let port else { print("FAIL server startup"); stopServer(); exit(2) }
func requests() -> Int? {
    (try? String(contentsOf: countFile)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
let url = "http://127.0.0.1:\(port)/video.mp4"
let decoder = FFmpegSoftwareDecoder()
try decoder.pinLocalRoots([root])
decoder.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 5)
let sid = SessionID(uncheckedEpoch: 9601)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: sid)
guard let binding = decoder.currentBinding() else { print("FAIL no active binding"); stopServer(); exit(2) }
func snapshot() -> Result<ActiveTransportSnapshot, ActiveTransportRefusal> {
    decoder.activeTransportSnapshot(source: binding.token, session: binding.session, revision: binding.revision)
}
guard case .success(let first) = snapshot() else { print("FAIL no transport snapshot"); stopServer(); exit(2) }
check("H1 real HTTP read count", (first.bytesRead ?? -1) > 0)
check("H2 current-buffer occupancy known", first.bufferAvailableBytes != nil && first.bufferAvailableBytes! >= 0)
check("H3 no invented error", first.errorCode == nil)
check("H4 source identity", first.source == binding.token && first.session == binding.session && first.revision == binding.revision)
let requestCount = requests()
check("H5 server saw real request", (requestCount ?? 0) > 0)
var stable = true
for _ in 0..<100 {
    if case .success(let value) = snapshot() { stable = stable && value == first }
    else { stable = false }
}
check("H6 snapshot no I/O or reopen", stable && requests() == requestCount)
let wrongRevision = try binding.revision.advanced()
check("H7 stale revision refused", decoder.activeTransportSnapshot(source: binding.token, session: binding.session, revision: wrongRevision) == .failure(.staleBinding))
let wrongSession = try SeekSessionID(rawValue: binding.session.rawValue + 1)
check("H8 foreign session refused", decoder.activeTransportSnapshot(source: binding.token, session: wrongSession, revision: binding.revision) == .failure(.staleBinding))
let wrongSource = try SourceToken(instanceID: binding.token.instanceID, openGeneration: binding.token.openGeneration + 1)
check("H9 foreign source refused", decoder.activeTransportSnapshot(source: wrongSource, session: binding.session, revision: binding.revision) == .failure(.staleBinding))
var frames = 0, ended = false
for _ in 0..<2000 {
    guard let event = await decoder.nextEvent(session: sid) else { break }
    switch event {
    case .frameDecoded(let frame):
        frames += 1; await decoder.releaseFrame(handle: frame.handle, session: sid)
    case .endOfStream: ended = true
    case .failed: failures += 1; print("FAIL real decode failed")
    default: break
    }
    if ended { break }
}
check("H10 real decoded frames and end", frames > 0 && ended)
if case .success(let final) = snapshot() {
    check("H11 cumulative observed reads", final.bytesRead != nil && final.bytesRead! >= first.bytesRead!)
    // EOF may be reached through demux semantics without AVIO observing it.
    // Only true or unknown is permitted, never manufactured false/zero.
    check("H12 EOF no prediction", final.eofObserved == nil || final.eofObserved == true)
} else { check("H11 active at EOF", false) }
_ = await decoder.closeAndReport(session: sid)
check("H13 close clears snapshot", snapshot() == .failure(.notOpen))
let newSID = SessionID(uncheckedEpoch: 9602)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: newSID)
check("H14 old binding after reopen refused", snapshot() == .failure(.staleBinding))
guard let reopened = decoder.currentBinding() else { print("FAIL reopen binding"); stopServer(); exit(2) }
check("H15 new open generation", reopened.token != binding.token)
_ = await decoder.closeAndReport(session: newSID)
check("H16 close new binding", decoder.activeTransportSnapshot(source: reopened.token, session: reopened.session, revision: reopened.revision) == .failure(.notOpen))
// Insert in Sources/active-transport-tests/main.swift after the line:
//   check("H16 close new binding", ...)
// and before: stopServer()
// Uses the COORDINATED seek path (tryBegin/execute/completion), which advances the seek revision only on nativeReady.
let seekWatchdog = DispatchWorkItem { print("FAIL H17: coordinated seek never completed within 20 s"); fflush(stdout); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: seekWatchdog)
let seekSID = SessionID(uncheckedEpoch: 9603)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: seekSID)
guard let b0 = decoder.currentBinding() else { print("FAIL no binding before seek"); stopServer(); exit(2) }
guard case .success(let before) = decoder.activeTransportSnapshot(source: b0.token, session: b0.session, revision: b0.revision) else {
    print("FAIL no snapshot before seek"); stopServer(); exit(2)
}
let seekRequest = SeekRequest(
    correlationID: try SeekCorrelationID(rawValue: 1, queueTurn: 1),
    session: b0.session, source: b0.token,
    target: SeekTarget(position: try RationalTime(value: 5, timescale: 1), rounding: .floorToKeyframe, requestedFlags: 0),
    expectedRevision: b0.revision)
let transaction = try decoder.tryBegin(seekRequest)
try transaction.execute()
let receipt = await transaction.completion()
seekWatchdog.cancel()
var nativeReady = false
if case .nativeReady = receipt.outcome { nativeReady = true }
check("H17 coordinated seek reached nativeReady outcome=\(receipt.outcome) (otherwise this witness is invalid)", nativeReady)
guard let b1 = decoder.currentBinding() else { print("FAIL no binding after seek"); stopServer(); exit(2) }
let expectedNextRevision = try b0.revision.advanced()
check("H18 revision advanced by exactly one step and matches the receipt",
      b1.revision != b0.revision && b1.revision == receipt.nextRevision && b1.revision == expectedNextRevision)
check("H19 pre-seek revision is refused as stale after the seek",
      decoder.activeTransportSnapshot(source: b0.token, session: b0.session, revision: b0.revision) == .failure(.staleBinding))
let afterResult = decoder.activeTransportSnapshot(source: b1.token, session: b1.session, revision: b1.revision)
var afterSnap: ActiveTransportSnapshot? = nil
if case .success(let s) = afterResult { afterSnap = s }
check("H20 snapshot served for the post-seek binding", afterSnap != nil)
// Contract: nil means unknown. If the counter was unknown before the seek no ordering is asserted;
// if it was known it must stay known and must not decrease (cumulative AVIO counter).
let bytesOK: Bool
if let b = before.bytesRead { bytesOK = (afterSnap?.bytesRead).map { $0 >= b } ?? false } else { bytesOK = true }
check("H21 cumulative byte counter not lost or decreased by a seek (unknown-before allowed)", bytesOK)
check("H22 after a seek EOF is true or unknown, never a manufactured false, and no invented error",
      (afterSnap?.eofObserved == nil || afterSnap?.eofObserved == true) && afterSnap?.errorCode == nil)
_ = await decoder.closeAndReport(session: seekSID)
check("H23 close clears the post-seek snapshot", decoder.activeTransportSnapshot(source: b1.token, session: b1.session, revision: b1.revision) == .failure(.notOpen))
stopServer()
try? FileManager.default.removeItem(at: directory)
print("active-transport-tests: \(failures) FAIL (no buffered-seconds/cache/stall inference)")
exit(failures == 0 ? 0 : 1)

```

```text id=actual_run_log
Building for debugging...
[0/14] Write sources
[5/14] Compiling GorAVCAtomics gorav_atomics.c
[6/14] Write swift-version--6630B1A18289934C.txt
[8/17] Compiling GorAVCore AdmissionTable.swift
[9/17] Compiling GorAVCore Boundary.swift
[10/17] Emitting module GorAVCore
[11/18] Compiling GorAVCore OpenURLRouter.swift
[12/19] Wrapping AST for GorAVCore for debugging
[14/23] Emitting module GorAVNativeProbeKit
[15/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[16/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[17/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[18/25] Compiling GorAVNativeProbeKit NativeProbe.swift
[19/25] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[20/26] Wrapping AST for GorAVNativeProbeKit for debugging
[22/49] Emitting module GorAVPlaybackCore
[23/70] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[24/70] Compiling GorAVPlaybackCore Lane0Contract.swift
[25/70] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[26/70] Compiling GorAVPlaybackCore ObservationSurface.swift
[27/70] Compiling GorAVPlaybackCore PlayArguments.swift
[28/70] Compiling GorAVPlaybackCore PlaybackCore.swift
[29/70] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[30/70] Compiling GorAVPlaybackCore PlayheadObservers.swift
[31/70] Compiling GorAVPlaybackCore PlayheadPosition.swift
[32/70] Compiling GorAVPlaybackCore PreparedAdoption.swift
[33/70] Compiling GorAVPlaybackCore PreparedShotSession.swift
[34/70] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[35/70] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[36/70] Compiling GorAVPlaybackCore RenderGraph.swift
[37/70] Compiling GorAVPlaybackCore SPSC.swift
[38/70] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[39/70] Compiling GorAVPlaybackCore StageGeometry.swift
[40/70] Compiling GorAVPlaybackCore TapCropDetector.swift
[41/70] Compiling GorAVPlaybackCore TimingLedger.swift
[42/70] Compiling GorAVPlaybackCore UniformPacking.swift
[43/70] Compiling GorAVPlaybackCore WindowModePlan.swift
[44/70] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[45/70] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[46/70] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[47/70] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[48/70] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[49/70] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[50/70] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[51/70] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[52/70] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[53/70] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[54/70] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[55/70] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[56/70] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[57/70] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[58/70] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[59/70] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[60/70] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[61/70] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[62/70] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[63/70] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[64/70] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[65/70] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-g5g_dux3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[66/71] Wrapping AST for GorAVPlaybackCore for debugging
[68/79] Emitting module GorAVFFmpegAdapter
[69/85] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[70/85] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[71/85] Compiling GorAVFFmpegAdapter MediaInventory.swift
[72/85] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[73/85] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[74/85] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[75/85] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[76/85] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[77/85] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[78/85] Compiling GorAVFFmpegAdapter FrameObservation.swift
[79/85] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[80/85] Compiling GorAVFFmpegAdapter L3Admission.swift
[81/85] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[82/86] Wrapping AST for GorAVFFmpegAdapter for debugging
[84/88] Emitting module active_transport_tests
[85/88] Compiling active_transport_tests main.swift
[86/89] Wrapping AST for active-transport-tests for debugging
[87/89] Write Objects.LinkFileList
[88/89] Linking active-transport-tests
Build of product 'active-transport-tests' complete! (12.59s)
PASS H1 real HTTP read count
PASS H2 current-buffer occupancy known
PASS H3 no invented error
PASS H4 source identity
PASS H5 server saw real request
PASS H6 snapshot no I/O or reopen
PASS H7 stale revision refused
PASS H8 foreign session refused
PASS H9 foreign source refused
PASS H10 real decoded frames and end
PASS H11 cumulative observed reads
PASS H12 EOF no prediction
PASS H13 close clears snapshot
PASS H14 old binding after reopen refused
PASS H15 new open generation
PASS H16 close new binding
PASS H17 coordinated seek reached nativeReady outcome=nativeReady(facts: GorAVNativeProbeKit.NativeSeekFacts(avSeekReturn: Optional(0), flagsApplied: 1, resolvedStreamIndex: Optional(0), requestedTicks: Optional(64000), resolvedStreamTimebase: Optional(GorAVNativeProbeKit.RationalTime(value: 1, timescale: 12800)), startOriginTicks: Optional(0), flushObserved: true, packetFeedReset: true, decoderReset: true, packetsReleased: Optional(0), packetAccountingReconciled: true)) (otherwise this witness is invalid)
PASS H18 revision advanced by exactly one step and matches the receipt
PASS H19 pre-seek revision is refused as stale after the seek
PASS H20 snapshot served for the post-seek binding
PASS H21 cumulative byte counter not lost or decreased by a seek (unknown-before allowed)
PASS H22 after a seek EOF is true or unknown, never a manufactured false, and no invented error
PASS H23 close clears the post-seek snapshot
active-transport-tests: 0 FAIL (no buffered-seconds/cache/stall inference)
```
