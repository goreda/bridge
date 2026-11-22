#!/usr/bin/env python3
"""Actual compiled thermal gate with injected clock/rank plus contract model and wiring pins."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
g = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDThermalGate.swift'+' '):_b.index('// END relocated '+'ThreeDThermalGate.swift'+'\n')])((_threed_split().path(root)).read_text()); sp = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDPrepareSpawn.swift'+' '):_b.index('// END relocated '+'ThreeDPrepareSpawn.swift'+'\n')])((_threed_split().path(root)).read_text())
c = (root / 'tools/depth_analysis/CONTRACT-190v.md').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
class P:
    def __init__(s): s.sus = None; s.clr = None
    def step(s, rank, now):
        if s.sus is None:
            if rank >= 2: s.sus = now; s.clr = None; return 'suspend'
            return 'run'
        if rank >= 1: s.clr = None; return 'hold'
        if s.clr is None: s.clr = now
        if now - s.sus >= 60 and now - s.clr >= 30: s.sus = None; s.clr = None; return 'resume'
        return 'hold'
def run(trace):  # trace: list of (t, rank) -> actions
    p = P(); return [p.step(r, t) for t, r in trace]
check('cool: always run', run([(0, 0), (5, 0)]) == ['run', 'run'])
check('serious suspends once; fair cannot satisfy existing cool dwell', run([(0, 2), (1, 2), (2, 3), (3, 1)]) == ['suspend', 'hold', 'hold', 'hold'])
check('cooling needs 30 s dwell AND 60 s minimum suspend', run([(0, 2), (10, 0), (39, 0), (59, 0), (60, 0), (61, 0)]) == ['suspend', 'hold', 'hold', 'hold', 'resume', 'run'])
check('model: re-heat resets dwell exactly', run([(0, 2), (20, 0), (40, 1), (50, 0), (79, 0), (80, 0)]) == ['suspend', 'hold', 'hold', 'hold', 'hold', 'resume'])
check('192c serious suspend with unchanged nominal60s/30s resume', 'suspendRank = 2, resumeRank = 1, minSuspend = 60.0, dwell = 30.0' in g and 'Minimum suspend 60 s' in c and '30 s dwell' in c)
check('Swift mirrors the model transitions', all(x in g for x in ('rank >= Self.suspendRank { suspendedAt = now; clearSince = nil; return .suspend }', 'now - s >= Self.minSuspend, now - (clearSince ?? now) >= Self.dwell', 'return .hold')))
check('gate: checkpoint once on suspend, polls state per boundary and on thermalStateDidChange, cancel returns false', 'case .suspend: suspends += 1; checkpoint(); paused(true)' in g and 'thermalStateDidChange' in g and 'if cancelled() { return false }' in g)
check('sink exposes boundary + runModel (one model at a time), progress.json carries paused=thermal and finishSource keeps it', 'func boundary(checkpoint:' in sp and 'func runModel<T>' in sp and 'modelLane.lock()' in sp and 'd["paused"] = "thermal"' in sp and 'pd["prepared"]' in sp)
check('prepare runs at .utility QoS (no userInteractive)', 'qos: .utility' in sp and 'userInteractive' not in sp and 'userInteractive' not in g)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', g + sp, re.I))
check('after resume a new heat suspends again', run([(0, 2), (70, 0), (100, 0), (101, 2)]) == ['suspend', 'hold', 'resume', 'suspend'])
# Compile the production blocking loop. Replace only unavailable Linux OS hooks.
import subprocess,tempfile,os
source=g.replace('ProcessInfo.processInfo.thermalState.rawValue','0').replace('ProcessInfo.thermalStateDidChangeNotification','Notification.Name("thermal-test")')
main=r'''import Foundation
var seconds=0.0,checkpoints=0,states:[Bool]=[]
let fair=ThreeDThermalGate(rank:{1},now:{seconds},wait:{_ in preconditionFailure("fair blocked")})
for _ in 0..<48 {precondition(fair.boundary(checkpoint:{preconditionFailure("fair checkpointed")},paused:{_ in preconditionFailure("fair paused")},cancelled:{false}))}
precondition(fair.suspends==0 && fair.resumes==0 && seconds==0)
print("PASS actual Swift injected-fair48frame trace completes with no pause or wait")
let hot=ThreeDThermalGate(rank:{2},now:{seconds},wait:{seconds += $0})
let finished=hot.boundary(checkpoint:{checkpoints += 1},paused:{states.append($0)},cancelled:{seconds >= 1200})
precondition(!finished && seconds==1200 && checkpoints==1 && states==[true])
print("PASS actual Swift serious-rank blocks1200s before depth; one checkpoint; cancellation preserved, not cut-detector work")
seconds=0;checkpoints=0;states=[]
let cooling=ThreeDThermalGate(rank:{seconds<10 ? 2:0},now:{seconds},wait:{seconds += $0})
let resumed=cooling.boundary(checkpoint:{checkpoints += 1},paused:{states.append($0)},cancelled:{false})
precondition(resumed && seconds==60 && states==[true,false] && checkpoints==1)
print("PASS actual Swift cooling resumes60s with30s dwell; thermal protection unchanged")
'''
with tempfile.TemporaryDirectory() as temp:
 p=pathlib.Path(temp);(p/'gate.swift').write_text(source);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'gate.swift'),str(p/'main.swift'),'-o',str(p/'gate')],check=True,capture_output=True,text=True)
 result=subprocess.run([str(p/'gate')],check=True,capture_output=True,text=True,timeout=5);print(result.stdout,end='')
check('actual wait is visible as thermal-pause, not stale completed cuts', 'ThreeDStageLog.progress(p ? "thermal-pause" : "thermal-resumed"' in sp)
runner=(lambda _b: _b[_b.index('// BEGIN relocated '+'NativePrepareRunner.swift'+' '):_b.index('// END relocated '+'NativePrepareRunner.swift'+'\n')])((_threed_split().path(root)).read_text());assembly=(lambda _b: _b[_b.index('// BEGIN relocated '+'ShotPrepareAssembly.swift'+' '):_b.index('// END relocated '+'ShotPrepareAssembly.swift'+'\n')])((_threed_split().path(root)).read_text())
check('cut reader close, persist and depth boundary each have named progress',all('"'+n+'"' in runner for n in ('cuts-reader-close','cuts-persist','depth-setup')) and 'hooks.progress("depth-boundary", ck.nextFrame, n)' in assembly)
sys.exit(1 if fails else 0)
