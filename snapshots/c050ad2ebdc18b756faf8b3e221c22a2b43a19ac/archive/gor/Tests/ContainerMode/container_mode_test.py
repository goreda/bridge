#!/usr/bin/env python3
"""195h r3 B lane: the container mode lifecycle through the REAL functions (Delivery r3-2/3/4): containerAction decided before the
writer opens, mismatched existing container rebuilt to exactly the flag-off bytes, EMA state persisted after append with frame
count + primed, coordinator mismatch branch wired to the prepare launcher. Linux swiftc (SWIFTC env or PATH); SKIPPED without it."""
import os, pathlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
sw = os.environ.get('SWIFTC') or shutil.which('swiftc')
if sw and os.path.exists(sw):
    exe = pathlib.Path(tempfile.mkdtemp()) / 'cm'
    srcs = ['DepthPrepareMath', 'DepthGuards', 'ShotComfort', 'FovTrackBuilder', 'MoGeKeyframeRunner', 'DepthContainerWriter',
            'VDAStreamRunner', 'ShotPrepareAssembly', 'SourceFormat', 'PrepareSupport',  # 195y G2: ShotCuts folded into ShotComfort.swift
            'KitCompiledCache', 'PrepareTelemetry', 'ThreeDSelfTest', 'ThreeDExperimentOptions', 'ThreeDPrepareLauncher', 'CoreMLDepthRunner']
    r = subprocess.run([sw, '-O'] + [str(S / (s + '.swift')) for s in srcs]
                       + [str(root / 'Tests/DepthPrepareMath/DegradeStub.swift'), str(root / 'Tests/ContainerMode/main.swift'), '-o', str(exe)],
                       capture_output=True, text=True)
    check('container-mode driver compiles (Linux)', r.returncode == 0)
    if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
    o = subprocess.run([str(exe), str(pathlib.Path(tempfile.mkdtemp()) / 'cm')], capture_output=True, text=True).stdout
    print(o)
    check('containerAction through the real function: fresh / no-marker (ema request) rebuild / no-marker (off request) resume / match resume / mismatch rebuild',
          'action fresh fresh' in o and 'action no-marker-ema-request rebuild' in o and 'action no-marker-off-request resume' in o
          and 'action match resume' in o and 'action mismatch rebuild' in o)
    check('ema-on run: mode marker true, state persisted with frames=n and primed=true (r3-3)', 'A marker ema true' in o and 'A ema state frames 30 primed true' in o)
    check('the EMA actually changes the container bytes (the feature is real)', 'ema changes output true' in o)
    check('flag-off run leaves no EMA state file', 'B has no ema state true' in o)
    check('same-mode re-run resumes; container bytes unchanged', 'resume same mode bytes unchanged true' in o)
    check('MISMATCHED existing container is rebuilt to exactly the flag-off bytes (r3-2)', 'mismatch rebuild equals flag-off fresh true' in o)
    check('rebuild relabels the marker and removes the stale EMA state', 'rebuild marker ema false' in o and 'rebuild ema state removed true' in o)
    check('Delivery block 2: render-only switches (E/G/hole) never mark a legacy or ema-off container mismatched; only EMA does',
          'legacy no-marker render-only-on match true' in o and 'legacy no-marker render-only-on action resume' in o
          and 'legacy no-marker ema-on mismatch true' in o and 'marker-off render-only-on match true' in o)
    check('Delivery block 1: the nudge stops only an old-mode job; repeated ticks never cancel the current-mode rebuild',
          'old-mode job started true' in o and 'same-mode nudge keeps the job true' in o and 'old-mode nudge stops the job true' in o
          and 'current-mode rebuild started true' in o and 'repeated nudges never stop the current-mode rebuild true' in o)
    check('Delivery A-3: the mode fence runs BEFORE checkpoint decode (old-model spool/ck never read)',
          'fence setup left a checkpoint and spool true' in o and 'mismatched resume lands on the fresh-mode bytes (old spool/checkpoint never read) true' in o and 'fence resume marker is the new mode true' in o)
    check('Delivery A-4: phase-1-interrupted job resumed in another mode restarts at frame 0 via the pre-phase-1 identity marker (Delivery repro read 11)',
          '2d setup: interrupted in phase 1 (no container, checkpoint and spool left) true' in o
          and '2d setup: the pre-phase-1 identity marker says the old model true' in o
          and 'DAV2 resume of an interrupted luma job restarts at frame 0 (Delivery repro read 11) true' in o
          and '2d resume relabels the identity marker true' in o)
    check('legacy markerless spool under the all-off default still resumes (pre-195h behavior preserved)', 'legacy markerless spool resumes at frame 11 true' in o)
    check('Delivery boundary: worker Job Codable roundtrip carries the mode; a legacy job file decodes to the default mode',
          'worker job roundtrip keeps the mode true' in o and 'legacy job file decodes to the default mode true' in o)
    check('Delivery 4: a stopped job s late completion is generation-guarded (cannot clear/fail the new job)',
          'stale completion neither cleared nor failed the new job true' in o)
    check('Delivery 7: interrupted phase 2 + lost EMA state resumes through the exact replay to the uninterrupted bytes',
          'interrupted at 12 appended true' in o and 'lost-state resume replays to the exact uninterrupted bytes true' in o)
else: print('SKIPPED numeric (no swiftc)')
sa = (S / 'ShotPrepareAssembly.swift').read_text()
check('the job carries the frozen snapshot (default all-off)', 'var experiments = ThreeDExperimentOptions()' in sa)
check('container action decided BEFORE the writer opens (r3-2)', sa.index('containerAction(dzc: job.dzc') < sa.index('DZCWriter(url: job.dzc'))
check('rebuild removes container+state before the writer and ABORTS without marking on failure (Delivery 6)', 'try fm.removeItem(at: job.dzc)' in sa and 'cannot remove the mismatched container for rebuild' in sa and 'try? fm.removeItem(at: job.dzc)' not in sa)
check('mode marker written only AFTER the writer holds the container (never relabels existing content)', sa.index('DZCWriter(url: job.dzc') < sa.index('writeJSON(PrepareSupport.prepareIdentity(expOptions), to: modeMarker'))
check('EMA state persisted only AFTER the append landed, with frame count and primed (r3-3)', sa.index('w.append(zMetres: metres)') < sa.index('writeJSON(["lo": rangeEMA.lo, "hi": rangeEMA.hi, "primed": rangeEMA.primed, "frames": fi + 1]'))
check('restore requires the exact frame count and restores primed as persisted (r3-3)', '(st["frames"] as? Int) == w.framesWritten' in sa and 'primed: pr)' in sa)
check('no approximate re-prime anywhere: missing state -> exact spool replay (Delivery 7)', 'spool short in the EMA replay' in sa and 'deterministic prime from the spool' not in sa)
check('assembly never reads the raw statics', 'DepthTemporalEMA.enabled' not in sa and 'DepthTemporalEMA.isEnabled()' not in sa)
nr = (S / 'NativePrepareRunner.swift').read_text()
check('runner uses the REQUEST\'s frozen prepare identity, never a live read (Delivery 5)', (('ThreeDExperimentOptions(depthRangeEMA: request.experiments.split' in nr or 'ThreeDExperimentOptions(experiments: request.experiments)' in nr) and 'ThreeDExperimentOptions.live' not in nr and 'job.experiments = expOptions' in nr))   # 195h A: the frozen-request parse is one shared real function
check('a mismatched complete container is NOT ready and gets re-prepared', nr.count('optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions)') >= 2)
pl = (S / 'ThreeDPrepareLauncher.swift').read_text()
check('the prepare request carries the experiment mode; a flip stops the old-mode job', 'var experiments = ""' in pl and 'runningExperiments' in pl)
check('prepare identity compares EMA alone, absent marker = EMA off (Delivery block 2)', 'return !options.depthRangeEMA' in (S / 'PrepareSupport.swift').read_text())
sp = (S / 'ThreeDPrepareSpawn.swift').read_text()
pj = (S / 'PrepareSupport.swift').read_text().split('// BEGIN relocated PrepareWorkerJob.swift (195y G2, behavior unchanged)')[1].split('// END relocated PrepareWorkerJob.swift')[0]  # 195y G2
check('spawn passes the request mode into the worker Job (boundary)', 'experiments: req.experiments' in sp and 'experiments: experiments)' in pj)
check('the worker job contract is one Foundation-only span of PrepareSupport.swift shared by production and the test (no shadow copy)', 'typealias Job = PrepareWorkerJob' in sp and 'struct PrepareWorkerJob: Codable' in pj)
asm = (S / 'ShotPrepareAssembly.swift').read_text()
fence_at = asm.find('the mode fence runs BEFORE any checkpoint or spool is read')
decode_at = asm.find('if let u = job.checkpointURL, let d = try? Data(contentsOf: u), let c = ShotCheckpoint.decode(d)')
check('the fence precedes the checkpoint decode in runResumable', 0 < fence_at < decode_at)
check('the fence wipes container+marker+ema state+spool+checkpoint, aborting on any failure', 'appendingPathExtension("options.json"), job.dzc.appendingPathExtension("ema.json"), job.spool' in asm and 'cannot remove' in asm and 'for rebuild' in asm)
check('legacy decode default for pre-195h job files', 'decodeIfPresent(String.self, forKey: .experiments) ?? ""' in pj)
check('launcher exposes the mismatch nudge with mode identity (r3-4 + Delivery block 1)', 'func noteModeMismatch(current experiments: String)' in pl and 'runningExperiments != experiments' in pl)
check('completion is generation-guarded (Delivery 4)', 'g == self.generation' in pl and pl.count('generation += 1') >= 3)
co = (S / 'ThreeDRenderCoordinator.swift').read_text()
check('coordinator mismatch branch wires the REAL re-prepare path (r3-4)', 'ThreeDPrepareRuntime.launcher?.noteModeMismatch(current: expOpts.prepareComponent)' in co and 'PrepareSupport.optionsMatch(dzc: hit.depth, options: expOpts)' in co)
check('exactly one options snapshot per request', co.count('let expOpts = ThreeDExperimentOptions.live') == 1)
w = (S / 'ThreeDWiring.swift').read_text()
check('wiring passes the PREPARE identity (never render-only switches) into the prepare request', 'experiments: ThreeDExperimentOptions.live.prepareComponent' in w)
menu = (S / 'ThreeDExperimentMenu.swift').read_text()
check('menu row tag 10 wired and validated', '(10,"B depth range EMA")' in menu and 'case 10: DepthTemporalEMA.toggleEnabled();onExperimentChange();' in menu and 'receipt("row-\(row.tag)");return' in menu and 'case 10:row.state=DepthTemporalEMA.isEnabled() ? .on:.off' in menu)
print('container mode: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
