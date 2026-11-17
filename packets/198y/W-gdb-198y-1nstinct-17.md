# W-gdb-198y-1nstinct-17
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/PPControllerMenuQueries.swift -> GorUI. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-17",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/PPControllerMenuQueries.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/PPControllerMenuQueries.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: queryMenuPayload, surfaceDrawableReceipt, setSubtitlePositionPreset, nativeAudioDeviceSnapshot, CropInvariant, mayChange, keptLine, transitionLine, fits, logPipCrop",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py",
    "callee": "archive/gor/Sources/gor/PPControllerMenuQueries.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.615279+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/PPControllerMenuQueries.swift",
        "block": "source1",
        "sha256": "e0776408c8ed4c5fd79859fe7a14c65fe632e5e9ddb6f368f0887664dcfb7bd9"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-17.py",
        "block": "fixtures1",
        "sha256": "41e616101d6bc6df26a272c80f840d4a12f8b9a4086b24a1291a46e86f5a8ce0"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "6eb8f5bf05bf7f7b57b4fdb3cc328b956fccac1c77dfcd17baf4a073cb5dd4c3",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-17: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "5a0311179074e092da738285a24029746a0b16aecbf948919e0c85f4174fb16b"
  }
}
```

```swift id=source1
import AppKit

// Menu-driven mpv queries that used to sit in PPController (kept out so PPController stays at its line ceiling).
extension PPController {
    func queryMenuPayload(_ payload:String) -> [String:Any] {
        let lines=ipcClient.queryBatch(payload,timeout:0.3)
        let reply=IPCClient.parseFirst(lines)
        return reply
    }
    func surfaceDrawableReceipt() -> (Double,Double)? {
        // Accepted persistent-feed dimensions only. Never block the main thread on a socket read.
        surfaceDrawableSnapshot
    }
    /// Absolute sub-pos preset (subtitles > position, the shift+1..9 rows).
    /// Same set-then-read plumbing and OSD as adjustSubtitleProperty.
    @discardableResult
    func setSubtitlePositionPreset(_ pos:Int) -> Bool {
        let payload=MPVCommand.make(["set_property","sub-pos",pos])+"\n"+MPVCommand.make(["get_property","sub-pos"])
        let reply=queryMenuPayload(payload)
        guard let value=reply["data"] as? Double,value.isFinite else{
            spineUI.showMPVOSD("subtitle control unavailable",duration:1.5,force:true);return false
        }
        pendingSubtitleModePosition=nil;subtitleView.setSubtitlePosition(value,force:true)
        spineUI.showMPVOSD("subtitle position: "+String(format:"%.0f%%",value),duration:1.5,force:true)
        return true
    }
    /// Output devices mpv itself reports (audio-device-list), with the current
    /// pick. Same one-shot queryBatch pattern as nativeTrackSnapshot.
    func nativeAudioDeviceSnapshot() -> (current:String,devices:[(name:String,label:String)]) {
        let current=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","audio-device"]}"#,timeout:0.15))["data"] as? String ?? "auto"
        let raw=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","audio-device-list"]}"#,timeout:0.15))["data"] as? [[String:Any]] ?? []
        let devices=raw.compactMap { entry -> (name:String,label:String)? in
            guard let name=entry["name"] as? String else{return nil}
            return (name,entry["description"] as? String ?? name)
        }
        return (current,devices)
    }
}

/// Applied-crop invariant (owner): an applied crop may ONLY be changed by the reset menu, an explicit
/// Detect, a manual crop menu choice, or opening a new file. Every automatic path (dims change, aspect or
/// format cycle, pip / fullscreen / resize / screen move, rendition hop, auto re-detect, abandon) keeps it.
enum CropInvariant {
    static func mayChange(manual: Bool) -> Bool { manual }
    static func keptLine(_ cause: String) -> String { "[crop-guard] kept applied crop: \(cause)" }
    static func transitionLine(_ event: String, crop: CGRect?, display: (w: Double, h: Double)) -> String {
        let c = crop.map { String(format: "%.4f,%.4f %.4fx%.4f", $0.minX, $0.minY, $0.width, $0.height) } ?? "none"
        return "[crop-guard] \(event) crop=\(c) disp=\(Int(display.w))x\(Int(display.h))"
    }
    /// Rendition hop: a stored rect that falls outside the new source dims is kept as state but not applied
    /// (never silently dropped); only Detect, reset, a manual choice or a new file resolves it.
    static func fits(x: Int, y: Int, w: Int, h: Int, srcW: Int, srcH: Int) -> Bool {
        let ok = x >= 0 && y >= 0 && x + w <= srcW + 1 && y + h <= srcH + 1
        if !ok { print(keptLine("stored rect \(w)x\(h)+\(x)+\(y) outside new source \(srcW)x\(srcH), not applied; waiting for Detect")) }
        return ok
    }
}

extension PPController {
    /// Aspect of the crop that mpv is showing through `video-crop` (our applied crop). The player window,
    /// pip shaping and every window-size proposal must follow it: pip used to shape the window from the
    /// FULL frame (videoDisplayW/H stay uncropped while video-crop is active), so the cropped picture sat
    /// in a window of the wrong aspect and the crop looked broken the moment pip shrank the window.
    var appliedSourceCropAspect: Double? {
        guard cropRect != nil, sourceCropPropertyActive, let c = SBSGeometry.parseCrop(lastSourceCropValue), c.1 > 0 else { return nil }
        return c.0 / c.1
    }
    /// [pip-crop] line: our applied rect, mpv's own video-crop and dwidth/dheight read back, window frame.
    func logPipCrop(_ event: String, frame: NSRect) {
        let q = ipcClient.queryBatch(MPVCommand.make(["get_property", "video-crop"]) + "\n" + MPVCommand.make(["get_property", "dwidth"]) + "\n" + MPVCommand.make(["get_property", "dheight"]), timeout: 0.3)
        let r = q.compactMap { IPCClient.parseFirst([$0])["data"] }.map { "\($0)" }
        let applied = cropRect.map { String(format: "%.4f,%.4f %.4fx%.4f", $0.minX, $0.minY, $0.width, $0.height) } ?? "none"
        print("[pip-crop] \(event) applied=\(applied) video-crop=\(r.first ?? "?") dwidth/dheight=\(r.dropFirst().joined(separator: "x")) cropAspect=\(appliedSourceCropAspect.map { String(format: "%.4f", $0) } ?? "none") disp=\(Int(videoDisplayW))x\(Int(videoDisplayH)) window=\(frame)")
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/PPControllerMenuQueries.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='e0776408c8ed4c5fd79859fe7a14c65fe632e5e9ddb6f368f0887664dcfb7bd9', 'pinned source changed: rebase and review, never bless silently'
for token in ['queryMenuPayload', 'surfaceDrawableReceipt', 'setSubtitlePositionPreset', 'nativeAudioDeviceSnapshot', 'CropInvariant', 'mayChange', 'keptLine', 'transitionLine', 'fits', 'logPipCrop']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='e0776408c8ed4c5fd79859fe7a14c65fe632e5e9ddb6f368f0887664dcfb7bd9'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-17: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-17: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
