#!/usr/bin/env python3
"""arch-196b C3: cooperative prepare pause, no SIGSTOP on model-holding processes.

Three layers, all real:
  1. The PRODUCTION Swift (sections extracted from Sources/gor/gor/ThreeD.swift) is compiled and run here:
     ShotSink's cooperative boundary wait (checkpoint once on the way in, progress.json marker, cancel path),
     ThreeDPrepareLauncher's 30 s pause->cancel->new-job rule with an injected clock, PrepareWorkerJob's flag-path codec.
  2. A real OS process test of the flag protocol with a Python fake worker: the flag dropped mid-step parks the worker
     only AFTER the step returns; ps never shows a T-state child; SIGKILL during the park + a fresh worker resumes from
     the checkpoint byte-equal to an uninterrupted run (same contract as Tests/DepthPrepareMath's shotkill replay).
  3. Text pins: no SIGSTOP/SIGCONT remains in the 3D source; the flag path crosses the process boundary in the job file.
If no swiftc is found the compiled checks are reported SKIPPED (not passed)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, pathlib, re, shutil, signal, subprocess, sys, tempfile, time

root = pathlib.Path(__file__).resolve().parents[2]
BLOB = (_threed_split().path(root)).read_text()
fails = []
skipped = []

def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok:
        fails.append(n)

def sec(n):
    b = '// BEGIN relocated ' + n + '.swift (195y owner-order 3D consolidation, behavior unchanged)\n'
    if b in BLOB:
        return BLOB[BLOB.index(b) + len(b):BLOB.index('// END relocated ' + n + '.swift\n')]
    b = '// BEGIN relocated ' + n + '.swift (195y G2, behavior unchanged)\n'
    return BLOB[BLOB.index(b) + len(b):BLOB.index('// END relocated ' + n + '.swift\n')]

# --- 3. text pins -------------------------------------------------------------------------------------------------
spawn_src = sec('ThreeDPrepareSpawn')
launcher_src = sec('ThreeDPrepareLauncher')
job_src = sec('PrepareWorkerJob')
runner_src = sec('NativePrepareRunner')

code_lines = [l for l in BLOB.split('\n') if not l.strip().startswith('///') and not l.strip().startswith('//')]
code = '\n'.join(code_lines)
check('no SIGSTOP/SIGCONT anywhere in the 3D code (comments may mention the removed mechanism)', 'SIGSTOP' not in code and 'SIGCONT' not in code)
check('app-side pause writes/removes the flag file, never signals the worker or its descendants',
      'if value { try? Data().write(to: URL(fileURLWithPath: flag), options: .atomic) } else { try? FileManager.default.removeItem(atPath: flag) }' in spawn_src
      and 'for pid in PrepareProcessLifetime.descendants' not in spawn_src)
check('the flag path crosses the process boundary inside the job file; pre-C3 job files decode the default ""',
      'pauseFlag: pauseURL.path' in spawn_src and 'pauseFlag = try c.decodeIfPresent(String.self, forKey: .pauseFlag) ?? ""' in job_src)
check('the worker CLI polls the flag into the runner; the runner hands it to the sink',
      'runner.pauseRequested = { FileManager.default.fileExists(atPath: job.pauseFlag) }' in spawn_src
      and 'sink.pauseRequested = pauseRequested' in runner_src)
check('the sink waits cooperatively at the boundary: checkpoint once on the way in, progress.json paused=pause, 0.2 s poll',
      'while pauseRequested() {' in spawn_src and 'd["paused"] = "pause"' in spawn_src and 'Thread.sleep(forTimeInterval: 0.2)' in spawn_src)
check('launcher: 30 s pause limit cancels through the media-transition path; the clock is transition-only',
      'static let pauseCancelSeconds = 30.0' in launcher_src
      and 'clock() - t > Self.pauseCancelSeconds { cancelForMediaTransition() }' in launcher_src
      and 'if pausedAt == nil { pausedAt = clock() }' in launcher_src)
check('stop/cancel paths clear the pause clock', launcher_src.count('pausedAt = nil') >= 3)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', spawn_src + launcher_src, re.I))

# --- 1. compiled production Swift ----------------------------------------------------------------------------------
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swiftc or not os.path.exists(swiftc):
    print('SKIPPED compiled checks: no swiftc')
    skipped.append('compiled')
else:
    tmp = pathlib.Path(tempfile.mkdtemp())
    names = ['ThreeDPrepareLauncher', 'PrepareWorkerJob', 'ThreeDThermalGate', 'ThreeDStageLog',
             'FilmPrepareStatus', 'DepthCacheBudget', 'DepthContainerWriter', 'DepthPrepareMath',
             'PrepareProcessLifetime', 'ThreeDPrepareSpawn',
             'VTShotEncoder']   # self-guards to empty on Linux; the REAL encoder compiles on Darwin (ShotSink's source-proxy branches name it)
    files = [str(root / 'Tests/DepthPrepareMath/DegradeStub.swift'),   # test stub for ThreeDDegradeProbe (shared with DepthPrepareMath; the real probe is not archived)
             str(root / 'Tests/PrepareCooperativePause/DarwinPrepareStub.swift')]   # NativePrepareRunner shape for the spawn section's Darwin branches (inert on Linux)
    for n in names:
        f = tmp / (n + '.swift')
        f.write_text('import Foundation\n' + sec(n))   # some sections carry no import line of their own (single-module app)
        files.append(str(f))
    # Linux corelibs Foundation lacks ProcessInfo.thermalState (same shim shape as Tests/DarwinTypecheck LIN).
    # Guarded: on Darwin the real Foundation member exists and a redeclaration would conflict.
    lin = tmp / 'lin.swift'
    lin.write_text('import Foundation\n'
                   '#if !canImport(Darwin)\n'
                   'extension ProcessInfo { enum ThermalState: Int { case nominal, fair, serious, critical }; var thermalState: ThermalState { .nominal }\n'
                   '  static let thermalStateDidChangeNotification = Notification.Name("x") }\n'
                   '#endif\n')
    exe = tmp / 'pcp'
    r = subprocess.run([swiftc, *files, str(lin), str(root / 'Tests/PrepareCooperativePause/main.swift'), '-o', str(exe)],
                       capture_output=True, text=True)
    check('production sections + driver compile natively (Linux or Darwin)', r.returncode == 0)
    if r.returncode:
        print(r.stderr[-2000:])
        sys.exit(1)
    with tempfile.TemporaryDirectory() as d:
        out = subprocess.run([str(exe), 'sinkpause', d], capture_output=True, text=True, timeout=30)
        print(out.stdout, end='')
        check('actual ShotSink: parks at the boundary while the flag exists (checkpoint once, paused=pause), resumes on removal, cancel returns false',
              out.returncode == 0 and 'sinkpause ok' in out.stdout)
        if out.returncode:
            print(out.stderr[-1500:])
    out = subprocess.run([str(exe), 'launcher'], capture_output=True, text=True, timeout=30)
    print(out.stdout, end='')
    check('actual ThreeDPrepareLauncher: 30 s parked cancels the worker; 3D on starts a new job; a short pause resumes in place',
          out.returncode == 0 and 'launcher ok' in out.stdout)
    if out.returncode:
        print(out.stderr[-1500:])
    out = subprocess.run([str(exe), 'jobflag'], capture_output=True, text=True, timeout=30)
    print(out.stdout, end='')
    check('actual PrepareWorkerJob: pauseFlag round-trips; pre-C3 job files decode the empty default',
          out.returncode == 0 and 'jobflag ok' in out.stdout)
    if out.returncode:
        print(out.stderr[-1500:])

# --- 2. real OS process test of the flag protocol -------------------------------------------------------------------
FAKE = r"""
import os, pathlib, signal, sys, time
d = pathlib.Path(sys.argv[1]); n = int(sys.argv[2]); flag = d / 'job.json.pause'
ck = d / 'shot.ck'; out = d / 'out.bin'
start = int(ck.read_text()) if ck.exists() else 0
data = bytes(((k * 7 + 13) % 256 for k in range(n * 16)))
for k in range(start, n):
    (d / 'step.begin').write_text(str(k))          # in-flight step: the flag may drop at any point inside it
    time.sleep(0.25)                               # the step itself (a model call cannot be interrupted cooperatively)
    (d / 'step.end').write_text(str(k))            # the step RETURNED
    out.write_bytes(data[: (k + 1) * 16])
    while flag.exists():                           # the boundary: park with no in-flight step
        if not (d / 'parked').exists():            # checkpoint on the way in, then poll
            ck.write_text(str(k + 1)); (d / 'parked').write_text('1')
        time.sleep(0.05)
    if (d / 'parked').exists():
        (d / 'parked').unlink()
(d / 'done').write_text('1')
"""

def run_fake(d, n, pause_at=None, kill_while_parked=False):
    """Drive the fake worker through the flag protocol. Returns final output bytes."""
    d = pathlib.Path(d)
    d.mkdir(parents=True, exist_ok=True)
    worker = subprocess.Popen([sys.executable, '-c', FAKE, str(d), str(n)])
    saw_parked = False
    if pause_at is not None:
        deadline = time.monotonic() + 10
        while not (d / 'step.begin').exists() or (d / 'step.begin').read_text() != str(pause_at):
            if time.monotonic() >= deadline:
                check('fake worker reaches the in-flight step', False)
                worker.kill(); worker.wait()
                return b''
            time.sleep(0.02)
        (d / 'job.json.pause').write_text('')      # the flag drops MID-STEP
        # the step must RETURN before the worker parks
        deadline = time.monotonic() + 10
        while not (d / 'parked').exists():
            if time.monotonic() >= deadline:
                check('fake worker parks after the flag', False)
                worker.kill(); worker.wait()
                return b''
            time.sleep(0.02)
        saw_parked = True
        check('the in-flight step returned BEFORE the park (no frozen step)', (d / 'step.end').read_text() == str(pause_at))
        check('checkpoint persisted on the way into the park', (d / 'shot.ck').read_text() == str(pause_at + 1))
        # no child of the worker is ever in T state while parked
        stats = subprocess.run(['ps', '-axo', 'stat=,command='], capture_output=True, text=True).stdout
        mine = [l.split()[0] for l in stats.splitlines() if str(worker.pid) in l or 'job.json.pause' in l]
        for _ in range(6):
            st = subprocess.run(['ps', '-o', 'stat=', '-p', str(worker.pid)], capture_output=True, text=True).stdout.strip()
            mine.append(st)
            time.sleep(0.05)
        check('ps: the parked worker and its children are never in T state', saw_parked and all(not s.startswith('T') for s in mine if s))
        if kill_while_parked:
            os.kill(worker.pid, signal.SIGKILL)
            worker.wait(timeout=5)
            (d / 'job.json.pause').unlink(missing_ok=True)
            (d / 'parked').unlink(missing_ok=True)
            worker = subprocess.Popen([sys.executable, '-c', FAKE, str(d), str(n)])   # the 30 s rule's "new job": a fresh process
        else:
            (d / 'job.json.pause').unlink()
    worker.wait(timeout=30)
    check('fake worker exits cleanly', worker.returncode == 0 and (d / 'done').exists())
    return (d / 'out.bin').read_bytes()

with tempfile.TemporaryDirectory() as t:
    t = pathlib.Path(t)
    ref = run_fake(t / 'plain', 12)
    paused = run_fake(t / 'paused', 12, pause_at=5)
    check('resume after a cooperative park is byte-equal to the uninterrupted run', paused == ref and len(ref) == 12 * 16)
    killed = run_fake(t / 'killed', 12, pause_at=5, kill_while_parked=True)
    check('SIGKILL during the park + fresh process resumes from the checkpoint byte-equal to the uninterrupted run', killed == ref)

sys.exit(1 if fails else 0)
