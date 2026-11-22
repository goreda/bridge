#!/usr/bin/env python3
"""2026-11-17 hover preview mpv Dock/CPU leak (owner order): failing-first
regression for the PreviewGuard fix.

Without the fix this FAILS: Sources/gor/GorPlatformMac/PreviewGuard.swift does not exist and
FileBrowser.swift's preview spawn carries no --macos-app-activation-policy
(every preview mpv takes a Dock icon) and no terminate path (a missed exit
event leaves the muted mpv playing forever).

With the fix: the preview argument list carries the prohibited activation
policy (no Dock icon, same mechanism as the main playback spawn), and a
rapid-hover simulation (8 spawn+register cycles of real child processes,
then teardown) leaves ZERO live preview processes, with spawn/exit pid
counts logged. Two teardown legs are exercised against real processes:
EOF-lifeline exit (cat ends on stdin EOF, no signal needed) and SIGTERM
escalation (python sleeps through the EOF and must be signaled)."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
import os, pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[2]
fails = []
def check(n, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + n + ((' -- ' + detail) if (detail and not ok) else ''))
    if not ok: fails.append(n)

guard = _plat_compile_input(root / 'Sources/gor/GorPlatformMac/QuitChildKiller.swift')
fb = _plat_read(root / 'Sources/gor/Media/FileBrowser.swift')
check('PreviewGuard exact folded section present', guard.is_file() and '// BEGIN station-move PreviewGuard.swift' in _plat_read(guard))
check('FileBrowser preview spawn goes through PreviewGuard.arguments (one arg list, Dock policy included)',
      'PreviewGuard.arguments(' in fb)
check('FileBrowser teardown goes through PreviewGuard.terminate (exit/click/deinit/re-entry)',
      fb.count('stopPreview()') >= 4 and 'PreviewGuard.terminate(' in fb)
if not guard.is_file():
    print('FAIL cannot continue without the fix file'); sys.exit(1)

swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc):
    print('SKIPPED: no swiftc'); sys.exit(1 if fails else 0)

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / 'main.swift').write_text(r'''import Foundation
#if os(Linux)
import Glibc
#endif

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

var lines: [String] = []
let linesLock = NSLock()
PreviewGuard.log = { s in linesLock.lock(); lines.append(s); linesLock.unlock() }
func logLines() -> [String] { linesLock.lock(); defer { linesLock.unlock() }; return lines }

// (a) Dock policy + argument preservation
let args = PreviewGuard.arguments(geometry: "640x360+10+10", socketPath: "/tmp/t.sock", path: "/tmp/movie file.mkv")
check("args carry --macos-app-activation-policy=prohibited", args.contains("--macos-app-activation-policy=prohibited"))
check("args keep geometry/ipc-server/file and muted idle flags",
      args.contains("--geometry=640x360+10+10") && args.contains("--input-ipc-server=/tmp/t.sock")
      && args.last == "/tmp/movie file.mkv" && args.contains("--volume=0") && args.contains("--mute=yes")
      && args.contains("--idle=no") && args.contains("--keep-open=no") && args.contains("--no-config"))

func spawn(_ pair: [String]) -> Process? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: pair[0])
    p.arguments = Array(pair[1...])
    do { try MPVLifeline.run(p); return p } catch { print("spawn failed: \(error)"); return nil }
}
func pidGone(_ pid: pid_t) -> Bool { kill(pid, 0) != 0 }
func until(_ seconds: TimeInterval, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { if cond() { return true }; usleep(20_000) }
    return cond()
}

let py = CommandLine.arguments[1]      // EOF-ignoring stand-in: needs SIGTERM
let pyEofArgs = ["-c", "import sys;sys.stdin.read()"]  // cooperative: exits on stdin EOF

// (b) rapid hover: 8 spawn+register cycles, hard cap 1
var procs: [Process] = []
for _ in 0..<8 {
    if let p = spawn([py, "-c", "import time;time.sleep(30)"]) { procs.append(p); PreviewGuard.register(p) }
}
check("8 preview stand-ins spawned and registered", procs.count == 8)
check("hard cap converges to exactly one live preview", until(10) { PreviewGuard.liveCount == 1 })
let last = procs.last!
check("cap evictions leave only the newest pid alive",
      until(10) { procs.dropLast().allSatisfy { pidGone($0.processIdentifier) } })
check("cap eviction escalated with sigterm for EOF-ignoring helpers",
      until(3) { logLines().filter { $0.contains("preview mpv sigterm pid=") }.count >= 7 })

// (c) teardown of the survivor: zero live preview processes
PreviewGuard.terminate(last)
check("rapid hover ends with zero live previews", until(10) { PreviewGuard.liveCount == 0 })
check("every preview pid reaped-and-gone", until(10) { procs.allSatisfy { pidGone($0.processIdentifier) } })

// (d) EOF-lifeline leg: a cooperative helper exits on the EOF close
// inside grace, no signal needed
if let c = spawn([py] + pyEofArgs) {
    PreviewGuard.register(c)
    let before = logLines().filter { $0.contains("sigterm pid=") || $0.contains("sigkill pid=") }.count
    PreviewGuard.terminate(c)
    let gone = until(10) { pidGone(c.processIdentifier) }
    let after = logLines().filter { $0.contains("sigterm pid=\(c.processIdentifier)") || $0.contains("sigkill pid=\(c.processIdentifier)") }.count
    check("EOF lifeline ends a cooperative helper with no signal", gone && after == 0 && before >= 0)
    check("live count back to zero after EOF exit", until(10) { PreviewGuard.liveCount == 0 })
} else { check("EOF lifeline leg spawned", false) }

// (e) terminate of an already-dead process is a no-op
if let d = spawn([py, "-c", "import time;time.sleep(30)"]) {
    PreviewGuard.register(d)
    kill(d.processIdentifier, SIGKILL)
    d.waitUntilExit()
    PreviewGuard.terminate(d)
    check("terminating a dead helper does not hang or crash", true)
    check("dead helper not double-counted live", until(5) { PreviewGuard.liveCount == 0 })
} else { check("dead-terminate leg spawned", false) }

// (f) diagnostics: spawn/exit pid counts prove the zero
let ls = logLines()
let spawns = ls.filter { $0.hasPrefix("preview mpv spawn pid=") }
let exits = ls.filter { $0.hasPrefix("preview mpv exit pid=") }
check("every spawn logged with pid and live count", spawns.count == 10 && spawns.allSatisfy { $0.contains(" live=") && $0.contains(" spawned=") })
check("every exit logged with pid and live count", exits.count == 10 && exits.allSatisfy { $0.contains(" live=") && $0.contains(" exited=") })
check("final logged live count is zero", exits.last.map { $0.contains(" live=0 ") } ?? false)


// Actual launch/cancel path, real process stand-ins, not mpv/AppKit timing.
let unrelated = Process(); unrelated.executableURL = URL(fileURLWithPath: py)
unrelated.arguments = ["-c", "import time;time.sleep(30)"]; try unrelated.run()
var churn: [Process] = []; var tickets: [PreviewWork] = []
let completions = DispatchGroup(); let resultLock = NSLock(); var offMain = true
for _ in 0..<24 {
    tickets.last?.cancel()
    let w = PreviewWork(); tickets.append(w)
    let p = Process(); p.executableURL = URL(fileURLWithPath: py)
    p.arguments = ["-c", "import time;time.sleep(30)"]; churn.append(p)
    completions.enter()
    PreviewGuard.launch(p, work: w) { _ in
        resultLock.lock(); offMain = offMain && !Thread.isMainThread; resultLock.unlock()
        completions.leave()
    }
}
tickets.last?.cancel()
check("24 rapid launch/cancel completions bounded", completions.wait(timeout: .now() + 12) == .success)
check("launch completion runs off main", offMain)
check("rapid cancel leaves zero registered previews", until(12) { PreviewGuard.liveCount == 0 })
check("all spawned churn children gone", until(12) { churn.allSatisfy { $0.processIdentifier <= 0 || pidGone($0.processIdentifier) } })
check("unrelated child untouched", unrelated.isRunning)
unrelated.terminate(); unrelated.waitUntilExit()
// Pin latest-only IPC while the first send is deliberately held in flight.
let work = PreviewWork(); let began = DispatchSemaphore(value: 0); let release = DispatchSemaphore(value: 0)
let sentLock = NSLock(); var sent: [Int] = []
work.sendLatest { began.signal(); _ = release.wait(timeout: .now() + 4); sentLock.lock(); sent.append(0); sentLock.unlock() }
check("first IPC starts", began.wait(timeout: .now() + 4) == .success)
for n in 1...100 { work.sendLatest { sentLock.lock(); sent.append(n); sentLock.unlock() } }
release.signal()
check("IPC queue retains latest only", until(4) { sentLock.lock(); defer { sentLock.unlock() }; return sent == [0,100] })
work.cancel(); work.sendLatest { sentLock.lock(); sent.append(999); sentLock.unlock() }
usleep(100_000); sentLock.lock(); let cancelledIPC = !sent.contains(999); sentLock.unlock()
check("cancel rejects further IPC", cancelledIPC)

if failures > 0 { print("HARNESS FAILS \(failures)"); exit(1) }
print("HARNESS FAILS 0")
''')
exe = tmp / 'pg'
sources = [str(guard), str(tmp / 'main.swift')]
r = subprocess.run([swiftc, '-O', *sources, '-o', str(exe)], capture_output=True, text=True)
check('compiles actual Foundation guard on host', r.returncode == 0)
if r.returncode:
    print(r.stderr[-1200:]); sys.exit(1)
cat = None
py = shutil.which('python3') or '/usr/bin/python3'
r = subprocess.run([str(exe), py], capture_output=True, text=True, timeout=120)
sys.stdout.write(r.stdout)
if r.returncode != 0 or 'HARNESS FAILS 0' not in r.stdout:
    check('harness FAILS 0', False, r.stderr[-400:])
else:
    check('harness FAILS 0', True)

if fails:
    print('TEST FAILURES: %d' % len(fails)); sys.exit(1)
print('ALL PASS')
