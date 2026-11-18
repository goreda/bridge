# W-gdb-199h-d5r3b-05 - Prepared-shot session swap (r3: no host-pin dependency)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D3a (r3b, pinned to native50 872dcc32d). Lane c: host r3 cachePin capture already exists in the coordinator (coord_state excerpt). This package must NOT depend on the host budget pin: session-side replacePreparedVideo keeps its own staging guarantees (operation token, cancellation guards, staged source custody, bounded preroll) without referencing DepthCacheBudget. Scope: verify + regression-cover that independence; patch only if a dependency exists.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Evidence that the session swap path never touches the host budget pin; regression tests over the guards.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-05",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "excerpt_block": "sess_replace (lines 1660-1720)"
  },
  {
   "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
   "excerpt_block": "sess_replace (lines 1660-1720)"
  }
 ],
 "interface": {
  "signatures": "Lane c: host r3 cachePin capture already exists in the coordinator (coord_state excerpt). This package must NOT depend on the host budget pin: session-side replacePreparedVideo keeps its own staging g",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Evidence that the session swap path never touches the host budget pin; regression tests over the guards.",
  "callee": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-05.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Evidence that the session swap path never touches the host budget pin; regression tests over the guards.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-05",
  "paths": [
   "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "archive/gor/Sources/gor/gor/ThreeD.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-05.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-05.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.656409+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
    "lines": "1660-1720",
    "block": "Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:1660-1720",
    "sha256": "5cb950c8caf549970f2391831c1aaaade15ed6a948c3e0eba5b3da25d3911cc5"
   },
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "6845-6911",
    "block": "Sources/gor/gor/ThreeD.swift:6845-6911",
    "sha256": "8d87595e84f5cc9591ab8b20311ded987556c43d8d08a17689639b0ac312422f"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-05.py",
    "block": "fixtures1",
    "sha256": "a3ea2ad499b6211adfeb99f4280f9ad0018cc94d1dfadd047b9ce04e9c1104c7"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "a2937c7c77a705bc3b613a56eddc95e5222cadc8cb5240b79008c2b993010681",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-05; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "5b443a7a9cf56f0de7d9bbf29312d7c2e84408cbc835cd2a3aca66ffe2678cc8"
 }
}
```

```swift id=Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:1660-1720
    private func replacePreparedVideo(at filmTime: RationalTime, with video: SourceRef,
                                      preserveAbsoluteFilmPTS: Bool) async throws -> PreparedShotCommitReceipt {
        guard !preparedOperation, let shot = preparedShot, let prior = preparedReceipt,
              !tornDown, !fenced, let issued = session, let pump, let oldDecoder = decoder,
              let adec, let audio, let binding = audioBinding, let flag = audioStopFlag,
              let commit, !commit.isCancelled else {
            throw PreparedShotError.sourceNotPrepared("no live prepared shot")
        }
        guard shot.filmClockEpoch == issued.epoch else {
            throw PreparedShotError.staleEpoch(expected: issued.epoch, found: shot.filmClockEpoch)
        }
        guard video.kind == .local, video.startOffset.value >= 0,
              video.id.hasPrefix("/"), !video.id.contains("://"), filmTime.value >= 0,
              FileManager.default.fileExists(atPath: video.id) else {
            throw PreparedShotError.admissionRefused("replacement must be a seekable local video")
        }
        guard preparedAdoption.beginOperation() else {
            throw PreparedShotError.sourceNotPrepared("prepared operation in flight")
        }
        preparedOperation = true
        let operationID=UUID()
        preparedOperationID=operationID
        var didCommit = false
        defer {
            if preparedOperationID==operationID {preparedOperationID=nil}
            preparedOperation = false
            preparedAdoption.finishOperation(didCommit: didCommit)
        }
        let candidate = FFmpegSoftwareDecoder()
        do {
            try candidate.pinLocalRoots([(video.id as NSString).deletingLastPathComponent])
            try await candidate.open(source: SourceDescriptor(id: video.id, kind: .local, seekable: true), session: issued)
            guard !tornDown, !fenced, !commit.isCancelled,
                  let cb = candidate.currentBinding() else {
                throw PreparedShotError.audioBindingLost(reason: "session closed during staging")
            }
            let descriptor = try candidate.descriptor(for: cb.token)
            guard descriptor.seekable, let tb = descriptor.streamTimebase, tb.value > 0,
                  let origin = descriptor.startOrigin else {
                throw PreparedShotError.admissionRefused("video timebase/origin unavailable")
            }
            let seekPosition = preserveAbsoluteFilmPTS
                ? try filmTime.mediaRelativePosition(streamOrigin: origin, streamTimebase: tb)
                : video.startOffset
            let candidateBridge = ShellSeekBridge()
            guard candidateBridge.attach(to: candidate) else {
                throw PreparedShotError.admissionRefused("replacement bridge refused")
            }
            switch await candidateBridge.seek(on: candidate, position: seekPosition, commitACK: { _, _ in }) {
            case .committedFlushed: break
            default: throw PreparedShotError.admissionRefused("replacement native seek/flush refused")
            }
            // Use the actual stream timebase rather than ShellFrameSource's legacy default.
            let candidateSource = ShellFrameSource(decoder: candidate, session: issued,
                timeBaseDen: Double(tb.timescale) / Double(tb.value))
            candidateSource.seekBridge = candidateBridge
            // P27: the replacement source serves the SAME session, so its tap
            // is created for the same session identity (the previous
            // source's tap closes with it on teardown).
            candidateSource.frameTap = FrameTap.makeForSession(session: issued.epoch)
            stagedLiveStereoSources[operationID]=candidateSource
```

```swift id=Sources/gor/gor/ThreeD.swift:6845-6911
    private var preparedLoadPending = false
    private let prefsReader = RenderPrefsReader()
    private let work = DispatchQueue(label: "gor.3d.render", qos: .utility)
    private var timer: Timer?, presentation = ThreeDPresentation()
    private var decoders: [String]?, writer: RenderShotWriter?, synthTold = false
    private var busy: [Int: UInt64] = [:]
    private let revision = RenderRevision()
    private var renderPrefs: RenderPrefsValue?
    private var showingURL: URL?
    private var lastGood: [Int: (url: URL, prefs: RenderPrefsValue)] = [:]
    private var retired = Set<URL>()
    // mpv loadfile send is not a release receipt. Keep prior files until its
    // observed current path confirms the replacement (or return to source).
    private var mpvRetainedURLs=Set<URL>()
    private var mpvExpectedURL:URL?
    private var retentionPlayhead:Int?
    private var boundFilmID: FilmID?
    private var observedDepthKeys: [Int:String] = [:]
    private var lastPTS: Double?, lastTick = 0.0, showing: Int?       // shot whose render file the player currently plays (nil = 2D)
    private var film2D: URL?                                         // the 2D film's URL (the player's path is the render file while 3D plays)
    private var announced = Set<String>()
    /// s38 degradation FSM: logs every transition (3dfsm lines) and executes only OSD actions; the depth-input swaps it names are already what tick/backTo2D do.
    private(set) lazy var degrade = ThreeDDegrade(exec: { [weak self] a in
        if a.hasPrefix("act_osd("), a.hasSuffix(")") { self?.announce(String(a.dropFirst(8).dropLast())) }
    })
    private var lastFilm: URL?, diskBlocked = false, relaunchChecked = false
    private var duty = ThermalDutyPolicy()      // same suspend/resume rule as the prepare gate, stepped per tick, feeds thermal_trip / thermal_clear
    private var indexCache: (entry: URL, index: DepthShotIndex)?
    /// Frame range of the playhead's shot, kept fresh every tick even while mode is off (the menu reads it to enable sbs/vr180).
    private(set) var shotFrames: (Int, Int)?

    init(send: @escaping (String) -> Void, mpvExecutable: @escaping () -> URL?, playhead: @escaping () -> Double?, film: @escaping () -> URL?,
         activeEngine: @escaping () -> PlayerEngine = { .mpv },
         preparedSession: @escaping @MainActor () -> PreparedShotPlayback? = { nil },
         goravDecoders: @escaping () -> [String] = { [] }) {
        self.send = send; self.mpvExecutable = mpvExecutable; self.playhead = playhead; self.film = film
        self.activeEngine = activeEngine
        self.preparedSession = preparedSession
        self.goravDecoders = goravDecoders
    }

    private var cachePin: DepthCacheBudget.Pin?
    private var cachePinKey: String?
    private var mediaTransitionPending=false
    private func cancelPreparedLoadAndWait() {
        guard let old=preparedLoadTask else {return}
        let retiringPin=cachePin
        old.cancel()
        let retiringID=UUID()
        preparedLoadID=retiringID
        // Do not clear pending here: the old swap may already have committed.
        // Its stale-result recovery must finish before another prepared load.
        preparedLoadPending=true
        preparedLoadTask=Task { @MainActor [weak self] in
            await old.value
            withExtendedLifetime(retiringPin) {}
            guard let self,self.preparedLoadID==retiringID else {return}
            self.preparedLoadPending=false;self.preparedLoadTask=nil
            self.collectRetired()
        }
    }
    func setMediaTransitionPending(_ pending:Bool) {
        mediaTransitionPending=pending
        if pending {
            revision.invalidate();cancelPreparedLoadAndWait()
            cachePin=nil;cachePinKey=nil
            showing=nil;showingURL=nil;film2D=nil;lastFilm=nil;indexCache=nil
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift", 1660, 1720, "5cb950c8caf549970f2391831c1aaaade15ed6a948c3e0eba5b3da25d3911cc5"], ["Sources/gor/gor/ThreeD.swift", 6845, 6911, "8d87595e84f5cc9591ab8b20311ded987556c43d8d08a17689639b0ac312422f"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-05; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-05; baseline only, product change and semantic test still required
```
