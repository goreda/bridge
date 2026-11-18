# W-gdb-199h-d5r3b-02 - Shot stream-copy segment (r3: native50 bounded route)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D2b (r3b, pinned to native50 872dcc32d). Rebase onto the native50 D2b route, already reviewed: ShotCopySegment (excerpt below) - one private synchronous MKV stream-copy, never a durable proxy, budget pin + owned-entry guard, exclusive shot-copy lock, caller-retained until FrameReader closes, deinit removes the file, cancellation + idle deadline. r3 scope: writer/helper lifetime and the disk-bound mechanism around it (byte cap, no whole-film intermediate, join before read). Lane c: no relaxation of the disk bound or whole-film staging. 'verified-not-needed with evidence' is an accepted outcome.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Evidence over the pinned route: lifetime (retain/close/deinit removal), disk bound enforcement, cancellation/deadline path; patch only if a gap is found.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-02",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
   "excerpt_block": "shotcopy_segment (lines 9155-9242)"
  }
 ],
 "interface": {
  "signatures": "Rebase onto the native50 D2b route, already reviewed: ShotCopySegment (excerpt below) - one private synchronous MKV stream-copy, never a durable proxy, budget pin + owned-entry guard, exclusive shot-c",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Evidence over the pinned route: lifetime (retain/close/deinit removal), disk bound enforcement, cancellation/deadline path; patch only if a gap is found.",
  "callee": "archive/gor/Sources/gor/gor/ThreeD.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-02.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Evidence over the pinned route: lifetime (retain/close/deinit removal), disk bound enforcement, cancellation/deadline path; patch only if a gap is found.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-02",
  "paths": [
   "archive/gor/Sources/gor/gor/ThreeD.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-02.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-02.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.545529+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "9155-9242",
    "block": "Sources/gor/gor/ThreeD.swift:9155-9242",
    "sha256": "99a90d9e0f28f0314468fb5d82e43c5cc345024a20df44c6f232163d3e1fc9e3"
   },
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "2747-2760",
    "block": "Sources/gor/gor/ThreeD.swift:2747-2760",
    "sha256": "f0c68aabc153efb5b65f0a14d693d2970c65252218b82fa6f6badc92b824d25d"
   },
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "2856-2869",
    "block": "Sources/gor/gor/ThreeD.swift:2856-2869",
    "sha256": "027dcf52e0567b53e04708055b962b12257b6734a9ae6d8085536542aad81527"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-02.py",
    "block": "fixtures1",
    "sha256": "a33a7ea0719f613aba6701ecc080cd682fcaebfe904a64119521a223d3c30db0"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "81a9fff58566d36bd103615fc3156405832aa8e6e96f51ec2caa3940d0cb1294",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-02; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "d5cf42aa12d9c5746def874363e895675eeebca5eab21e1c1e780aa40261a90d"
 }
}
```

```swift id=Sources/gor/gor/ThreeD.swift:9155-9242
/// One private, synchronous MKV shot stream-copy. Never a durable source proxy.
/// Caller retains this object until FrameReader closes; deinit removes the file.
final class ShotCopySegment {
    enum Failure:Error {case unsafe,copyFailed,cancelled,io}
    let url:URL
    private let entryPin:DepthCacheBudget.Pin
    private let lockFD:Int32
    private var removed=false
    private init(url:URL,pin:DepthCacheBudget.Pin,lockFD:Int32) {self.url=url;self.entryPin=pin;self.lockFD=lockFD}
    func remove()throws {
        if removed {return}
        guard DepthCacheBudget.plainFile(url) else {throw Failure.unsafe}
        try FileManager.default.removeItem(at:url);removed=true
    }
    deinit {if !removed {try? FileManager.default.removeItem(at:url)};close(lockFD)}
    static func arguments(source:String,map:OriginalFilmShot,sourceFirstPTS:Double)->[String]? {
        guard sourceFirstPTS.isFinite else {return nil}
        let rate=Double(map.timeline.fps.numerator)/Double(map.timeline.fps.denominator)
        let seek=Double(map.firstFrame)/rate,end=sourceFirstPTS+Double(map.firstFrame+map.timeline.frameCount)/rate
        guard seek.isFinite,end.isFinite else {return nil}
        return ["-hide_banner","-nostdin","-loglevel","error","-copyts","-ss",String(format:"%.9f",seek),"-i",source,
                "-to",String(format:"%.9f",end),"-map","0:v:0","-an","-sn","-dn","-c:v","copy",
                "-avoid_negative_ts","disabled","-use_editlist","1","-movflags","frag_keyframe+delay_moov+default_base_moof","-frag_duration","1000000","-f","mp4","pipe:1"]
    }
    static func create(source:URL,entry:URL,map:OriginalFilmShot,sourceFirstPTS:Double,binary:String,cancelled:@escaping ()->Bool)throws->ShotCopySegment {
        guard source.pathExtension.lowercased()=="mkv",map.sourceKey==entry.lastPathComponent,
              let args=arguments(source:source.path,map:map,sourceFirstPTS:sourceFirstPTS) else {throw Failure.unsafe}
        let root=entry.deletingLastPathComponent()
        let pin=try DepthCacheBudget.pin(root:root,key:map.sourceKey)
        guard DepthCacheBudget.owned(entry) else {throw Failure.unsafe}
        let lockFD=open(root.appendingPathComponent(".shot-copy-"+map.sourceKey+".lock").path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard lockFD>=0 else {throw Failure.unsafe}
        var success=false
        defer {if !success {close(lockFD)}}
        var ls=stat()
        guard fstat(lockFD,&ls)==0,(ls.st_mode&S_IFMT)==S_IFREG,ls.st_nlink==1,
              flock(lockFD,LOCK_EX|LOCK_NB)==0 else {throw Failure.unsafe}
        let url=entry.appendingPathComponent(String(format:".tmp-shot-%05d.mp4",map.shot))
        // An earlier crashed copy is retired only under the stable exclusive
        // shot-copy lock. Active reader retains that lock through object lifetime.
        if FileManager.default.fileExists(atPath:url.path) {
            guard DepthCacheBudget.plainFile(url) else {throw Failure.unsafe}
            try FileManager.default.removeItem(at:url)
        }
        let fd=open(url.path,O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else {throw Failure.unsafe}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        var closed=false
        defer {if !closed {try? handle.close()};if !success {try? FileManager.default.removeItem(at:url)}}
        let process=Process(),pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:binary);process.arguments=args
        process.standardInput=FileHandle.nullDevice;process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {kill(process.processIdentifier,SIGKILL)}
            process.waitUntilExit();try? pipe.fileHandleForReading.close()
        }
        let input=pipe.fileHandleForReading.fileDescriptor
        guard PreparePipeNonblocking.enable(input) else {throw Failure.io}
        var buffer=[UInt8](repeating:0,count:65536),bytes:UInt64=0
        var idle=Date().addingTimeInterval(30)
        while true {
            guard !cancelled(),Date()<idle else {throw Failure.cancelled}
            let n=read(input,&buffer,buffer.count)
            if n>0 {
                idle=Date().addingTimeInterval(30)
                let data=Data(buffer.prefix(n))
                // Same real synchronous byte-hard sink as every other cache file.
                try DepthCacheIO.append(data,to:handle,url:url);bytes+=UInt64(n)
            } else if n==0 {break}
            else {
                guard errno==EAGAIN || errno==EINTR else {throw Failure.io}
                var waiter=pollfd(fd:input,events:Int16(POLLIN),revents:0);_=poll(&waiter,1,20)
            }
        }
        while process.isRunning {
            guard !cancelled(),Date()<idle else {throw Failure.cancelled}
            Thread.sleep(forTimeInterval:0.02)
        }
        guard !cancelled(),Date()<idle else {throw Failure.cancelled}
        process.waitUntilExit()
        guard process.terminationReason == .exit,process.terminationStatus==0,bytes>0 else {throw Failure.copyFailed}
        try handle.synchronize();try handle.close();closed=true
        success=true
        return ShotCopySegment(url:url,pin:pin,lockFD:lockFD)
    }
}
```

```swift id=Sources/gor/gor/ThreeD.swift:2747-2760
enum DepthCacheBudget {
    struct Policy {
        // Optional absolute override is for tests, never the production default.
        var quota: UInt64? = nil
        var volumePercent: UInt64 = 5
        var usablePercent: UInt64 = 10
        var reserve: UInt64 = 5 * 1024 * 1024 * 1024
        var writeHeadroom: UInt64 = 256 * 1024 * 1024
    }
    static var policy = Policy()
    static let marker = ".gor-cache-owned-v1"
    static func validKey(_ s: String) -> Bool { s.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func plainDirectory(_ u: URL) -> Bool {
        var s = stat(); return lstat(u.path, &s) == 0 && (s.st_mode & S_IFMT) == S_IFDIR
```

```swift id=Sources/gor/gor/ThreeD.swift:2856-2869
    static func owned(_ entry: URL) -> Bool {
        let m = entry.appendingPathComponent(marker)
        return validKey(entry.lastPathComponent) && plainDirectory(entry) && plainFile(m) && (try? String(contentsOf: m, encoding: .utf8)) == entry.lastPathComponent
    }
    static func deletable(_ entry: URL) -> Bool {
        guard owned(entry),let files=try? FileManager.default.contentsOfDirectory(at:entry,includingPropertiesForKeys:nil) else {return false}
        let fixed:Set<String>=[marker,"cuts.json","fov_track.json","progress.json","render-ready.json","prepare-input.mp4","prepare-input.part.mp4"]
        let pattern="^(depth_shot_[0-9]{5}\\.(dzc(\\.(options|ema)\\.json)?|json)|source_shot_[0-9]{5}\\.mp4|shot_[0-9]{5}\\.(spool(\\.identity\\.json)?|ck|align\\.json)|render_shot_[0-9]{5}(_[a-f0-9]{64})?\\.(mp4|json)|\\.render-[A-Fa-f0-9-]{36}\\.mp4)$"
        return files.allSatisfy {u in
            guard plainFile(u) else {return false}
            let n=u.lastPathComponent.hasPrefix(".tmp-") ? String(u.lastPathComponent.dropFirst(5)) : u.lastPathComponent
            return u.lastPathComponent.range(of:"^\\.tmp-shot-[0-9]{5}\\.mp4$",options:.regularExpression) != nil || ShotGenerationStore.recognized(u.lastPathComponent) || fixed.contains(n) || n.range(of:pattern,options:.regularExpression) != nil
        }
    }
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/gor/ThreeD.swift", 9155, 9242, "99a90d9e0f28f0314468fb5d82e43c5cc345024a20df44c6f232163d3e1fc9e3"], ["Sources/gor/gor/ThreeD.swift", 2747, 2760, "f0c68aabc153efb5b65f0a14d693d2970c65252218b82fa6f6badc92b824d25d"], ["Sources/gor/gor/ThreeD.swift", 2856, 2869, "027dcf52e0567b53e04708055b962b12257b6734a9ae6d8085536542aad81527"]]
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
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-02; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-02; baseline only, product change and semantic test still required
```
