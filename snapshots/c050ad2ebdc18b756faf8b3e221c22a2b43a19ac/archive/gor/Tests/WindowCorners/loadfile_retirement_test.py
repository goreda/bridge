#!/usr/bin/env python3
"""Execute the actual PPController loadfile interception: replace retires the active file
(transition + live anchor + pose/WT/camera/dimming retirement), append/append-play/insert-*
touch nothing, stop/quit always retire. The branch code and isReplacingLoadfile are extracted
verbatim from the shipped source and compiled with swiftc; absence of swiftc is a failure,
never a skipped PASS. A guard-removal mutant must be caught. Whole-AppKit compile and native
runtime remain NOT_RUN."""
import os, re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = (ROOT / "Sources/gor/Player/PPController.swift").read_text()
SWIFTC = os.environ.get("SWIFTC", "swiftc")

def extract(start_marker, open_indent):
    """Slice one Swift block verbatim: from the line containing start_marker to its closing
    brace at the given indentation."""
    i = SWIFT.index(start_marker)
    j = SWIFT.index("\n" + " " * open_indent + "}\n", i)
    return SWIFT[i:j + open_indent + 3]

CLASSIFIER = extract("static func isReplacingLoadfile", 4)
STOP_LINE = 'if name == "stop" {beginMediaTransition()}'
assert STOP_LINE in SWIFT
BRANCH_TRANSITION = extract('if name == "loadfile",command.count>1', 12)
BRANCH_RETIRE = extract('if ["stop","loadfile","quit","quit-watch-later"].contains(name) {', 12)
assert "retiresActive" in BRANCH_RETIRE, "retirement guard missing from the actual source"
assert "Self.isReplacingLoadfile(command)" in BRANCH_TRANSITION

TEMPLATE = """
import Foundation
final class Client { var cancellations=0, closures=0; func closeLatestPose(){closures+=1}; func cancelLatestPose(){cancellations+=1} }
enum ThreeDRecognitionBridge { static var internalSet:Set<String>=[]; static func internalMedia(_ p:String)->Bool { internalSet.contains(p) } }
final class Probe {
    var ipcClient=Client(); var cameraFileGeneration:UInt64=0; var ambientPlaybackFileEnded=false; var cameraActive=true
    var events:[String]=[]; var transitions=0; var anchors=0
    var currentFilePath:String = "/playing.mkv"; var sourceFilmPath:String = ""
    func sendWTPlaybackEvent(_ name:String){events.append(name)}
    func setCameraPlaybackActive(_ active:Bool){cameraActive=active}
    func beginMediaTransition(){transitions+=1}
    func pushLiveFitAnchor(){anchors+=1}
    func pushFitMetrics(){}
    __CLASSIFIER__
    func apply(_ command:[Any]) {
        guard let name=command.first as? String else { return }
        __STOP_LINE__
__BRANCH_TRANSITION__
__BRANCH_RETIRE__
    }
}
func retired(_ p:Probe)->Bool { p.ipcClient.cancellations+p.ipcClient.closures>0 && p.cameraFileGeneration==1 && p.ambientPlaybackFileEnded && !p.cameraActive && p.events.count==1 }
func fresh(_ c:[Any])->Probe { let p=Probe(); p.apply(c); return p }
// replacing forms retire everything and arm transition+anchor
for c in [["loadfile","/movie.mkv"],["loadfile","/movie.mkv","replace"],["loadfile","/movie.mkv","replace",-1,["start":"3"]]] as [[Any]] {
    let p=fresh(c)
    precondition(p.transitions==1 && p.anchors==1 && retired(p), "replace must transition+anchor+retire: \\(c)")
}
// queued forms touch nothing on the active file
for c in [["loadfile","/q.mkv","append"],["loadfile","/q.mkv","append-play"],["loadfile","/q.mkv","append-play",-1,["start":"3"]],["loadfile","/q.mkv","insert-next-play"]] as [[Any]] {
    let p=fresh(c)
    precondition(p.transitions==0 && p.anchors==0 && p.ipcClient.cancellations==0 && p.ipcClient.closures==0 && p.cameraFileGeneration==0 && !p.ambientPlaybackFileEnded && p.cameraActive && p.events.isEmpty, "queued loadfile must not touch the active file: \\(c)")
}
// stop/quit always retire; quit closes pose, stop cancels it
let ps=fresh(["stop"]); precondition(ps.transitions==1 && ps.ipcClient.cancellations==1 && ps.ipcClient.closures==0 && ps.cameraFileGeneration==1 && ps.ambientPlaybackFileEnded && !ps.cameraActive, "stop retires")
let pq=fresh(["quit-watch-later"]); precondition(pq.ipcClient.closures==1 && pq.ipcClient.cancellations==1-1 && pq.cameraFileGeneration==1 && pq.ambientPlaybackFileEnded, "quit closes pose and retires")
// internal-media replacing loadfile: no transition/anchor, but still a real replacement retirement
ThreeDRecognitionBridge.internalSet=["/internal.mkv"]
let pi=fresh(["loadfile","/internal.mkv"])
precondition(pi.transitions==0 && pi.anchors==0 && retired(pi), "internal media: retired without transition/anchor")
print("PASS actual Swift loadfile interception: replace retires+transitions+anchors; append/append-play/insert-next-play untouched; stop/quit retire; internal-media retired without fence")
"""

def build_and_run(branch_retire_text, label):
    src = (TEMPLATE
           .replace("__CLASSIFIER__", CLASSIFIER)
           .replace("__STOP_LINE__", STOP_LINE)
           .replace("__BRANCH_TRANSITION__", BRANCH_TRANSITION)
           .replace("__BRANCH_RETIRE__", branch_retire_text))
    with tempfile.TemporaryDirectory() as d:
        main = Path(d) / "main.swift"
        main.write_text(src)
        binp = Path(d) / "probe"
        c = subprocess.run([SWIFTC, "-O", str(main), "-o", str(binp)], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"FAIL {label}: swiftc did not compile the actual extracted code\n{c.stderr[:2000]}")
            return None
        r = subprocess.run([str(binp)], capture_output=True, text=True)
        return r

if subprocess.run(["bash", "-c", f"command -v {SWIFTC}"], capture_output=True).returncode != 0:
    print(f"FAIL swiftc ({SWIFTC}) unavailable: extraction test cannot run; never a skipped PASS")
    sys.exit(1)

r = build_and_run(BRANCH_RETIRE, "actual")
assert r is not None
if r.returncode != 0:
    print(r.stdout); print(r.stderr[:2000]); print("FAIL actual interception matrix")
    sys.exit(1)
print(r.stdout.strip())

# mutant: drop the retiresActive guard -> queued append-play retires the active file -> must be caught
mut = BRANCH_RETIRE.replace(
    'let retiresActive = name != "loadfile" || Self.isReplacingLoadfile(command)\n                if retiresActive {',
    "if true {")
assert mut != BRANCH_RETIRE, "guard-removal mutant did not change the branch"
rm = build_and_run(mut, "mutant")
assert rm is not None
if rm.returncode == 0:
    print("FAIL guard-removal mutant accepted (append-play no longer retires nothing)")
    sys.exit(1)
print("PASS mutant refused: without retiresActive a queued append-play retires the active file")
