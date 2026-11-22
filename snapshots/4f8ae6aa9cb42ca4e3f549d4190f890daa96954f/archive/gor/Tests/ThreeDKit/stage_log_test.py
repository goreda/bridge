#!/usr/bin/env python3
"""Owner Mac 16:33: --selftest3d sat 13 min at 0% cpu with only the begin line. ThreeDStageLog gives per-stage begin/end lines and a heartbeat naming the open stage;
the clip writer waits are bounded. Swift pure part runs on Linux; the AVFoundation/CoreML calls it wraps are pinned as source."""
import os, pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    with tempfile.TemporaryDirectory() as d:
        exe = pathlib.Path(d) / 'x'
        shutil.copy(root / 'Tests/ThreeDKit/stage_log_main.swift', pathlib.Path(d) / 'main.swift')
        r = subprocess.run([sw, '-O', str(S / 'ThreeDStageLog.swift'), str(pathlib.Path(d) / 'main.swift'), '-o', str(exe)], capture_output=True, text=True)
        check('ThreeDStageLog compiles (Linux)', r.returncode == 0)
        if r.returncode: print(r.stderr[-500:]); sys.exit(1)
        o = subprocess.run([str(exe)], capture_output=True, text=True).stdout.split('\n')
        check('disabled: no line for a stage run while off', not any(' off ' in l for l in o))
        check('begin and end lines for nested stages, in order', [l.split(' t=')[0] for l in o if ' stage ' in l][:4] == ['gor3d-selftest-cli v1 stage outer begin', 'gor3d-selftest-cli v1 stage inner slow begin', 'gor3d-selftest-cli v1 stage inner slow end ms=' + re.search(r'inner slow end ms=(\d+)', '\n'.join(o)).group(1), 'gor3d-selftest-cli v1 stage outer end ms=' + re.search(r'outer end ms=(\d+)', '\n'.join(o)).group(1)])
        check('inner stage wall time measured (>= 600 ms for a 700 ms sleep)', int(re.search(r'inner slow end ms=(\d+)', '\n'.join(o)).group(1)) >= 600)
        al = [l for l in o if ' alive ' in l]
        check('heartbeat while a stage is open names that stage (>= 2 beats during the 0.7 s stage at 0.2 s)', len(al) >= 2 and all('stage=inner slow' in l for l in al[:2]))
        check('externally timed stage becomes one end line', any('stage prepare cuts end ms=12' in l for l in o))
        check('bounded loader returns fast, times out stuck, completes fallback within bound, discards late result', 'bounded true true true true' in o and 'late_discarded true' in o)
else: print('SKIPPED swift (no swiftc)')
st = (S / 'ThreeDSelfTest.swift').read_text(); cli = (S / 'ThreeDSelfTestCLI.swift').read_text()
check('clip writer: readiness loop is bounded and logs status + error', 'writerStallLimit' in st and 'writer not ready for frame' in st and 'w.cancelWriting()' in st)
check('clip writer: finishWriting wait has a timeout (no unbounded DispatchGroup.wait)', 'g.wait(timeout:' in st and 'g.wait()' not in st)
check('CLI turns the stage log on and brackets the whole run', 'ThreeDStageLog.enabled = true; ThreeDStageLog.start()' in cli and 'ThreeDStageLog.time("self-test total")' in cli)
check('every long stage is wrapped: clip write, load models, compile, load per package (both runners), prepare, render', all(x in (S / f).read_text() for f, x in [('NativePrepareRunner.swift', 'ThreeDStageLog.time("load models'), ('KitCompiledCache.swift', 'ThreeDStageLog.time("compile "'), ('VDAStreamRunner.swift', 'KitCompiledCache.model(u)'), ('MoGeKeyframeRunner.swift', 'KitCompiledCache.model(u)'), ('ThreeDSelfTest.swift', 'ThreeDStageLog.time("prepare'), ('ThreeDSelfTest.swift', 'ThreeDStageLog.time("render " + name)')]))
cache = (S / 'KitCompiledCache.swift').read_text()
check('CoreML ordered fallback all -> CPU/GPU -> CPU, bounded30s each and device timeout breaker', '[("all", .all), ("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly)]' in cache and 'BoundedLoad.attempt(seconds: 30)' in cache and 'timedOutDevices.insert(name)' in cache)
check('probe child killed on timeout; only successful child permits parent load; headless before NSApp', 'kill(child.processIdentifier, SIGKILL)' in cache and 'guard probe(compiled, device: name) else' in cache and cache.index('guard probe(compiled, device: name) else') < cache.index('BoundedLoad.attempt(seconds: 30)') and (S/'main.swift').read_text().index('KitCompiledCache.probeCLI') < (S/'main.swift').read_text().index('let app = NSApplication.shared'))
check('acceptance does not reload models just to describe the compute plan', 'ComputeUnitsProbe.summary' not in st)
check('acceptance requires both decoded PNG grabs and FoV before success', 'grabs.count == 2' in st and 'acceptanceComplete && tel.errors.isEmpty' in st and 'saveFrame(out, png: png)' in st)
for name in ('VDAStreamRunner','MoGeKeyframeRunner','VDAWindowRunner','NunifCoreMLRunner'):
    runner=(S/(name+'.swift')).read_text()
    check('all runner loads use bounded/probed fallback '+name, 'KitCompiledCache.model(' in runner and 'MLModel(contentsOf:' not in runner)
print('stage log: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
