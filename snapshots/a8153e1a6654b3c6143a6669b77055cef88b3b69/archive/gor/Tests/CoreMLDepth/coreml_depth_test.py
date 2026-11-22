#!/usr/bin/env python3
"""195h A: CoreML depth model (DAV2-Small), folded into B's prepare-identity design (Delivery A re-review)."""
import json, pathlib, subprocess, sys

R = pathlib.Path(__file__).resolve().parents[2]
S = R / 'Sources' / 'gor'
T = pathlib.Path(__file__).resolve().parent
fails = []
def check(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok: fails.append(name)

# pinned parity fixture == the lock rows, byte for byte (the fetch keeps only sha-matching files)
fx = json.loads((T / 'dav2_fixture.json').read_text())
lock_rows = {}
for line in (R / 'models' / 'models.lock.tsv').read_text().splitlines():
    c = line.split('\t')
    if len(c) >= 9 and c[0].startswith('dav2-small-coreml-f16'): lock_rows[c[0]] = c
check('three pinned dav2 rows in models.lock.tsv', len(lock_rows) == 3)
ok = True
for r in lock_rows.values():
    match = [f for f in fx['files'] if f['file'] == r[5]]
    ok = ok and r[1] == 'usable' and r[2] == 'Apache-2.0' and r[3] == fx['repo'] and r[4] == fx['revision'] and match and match[0]['sha256'] == r[6] and match[0]['bytes'] == int(r[7])
check('lock rows match the pinned fixture (repo, revision, sha256, bytes, Apache-2.0)', ok)
check('NOTICE documents the package', 'DepthAnythingV2SmallF16.mlpackage' in (R / 'NOTICE-models.md').read_text())

runner = (S / 'CoreMLDepthRunner.swift').read_text()
ema = (S / 'ModelDepthEMA.swift').read_text()
opts = (S / 'ThreeDExperimentOptions.swift').read_text()
support = (S / 'PrepareSupport.swift').read_text()
assembly = (S / 'ShotPrepareAssembly.swift').read_text()
npr = (S / 'NativePrepareRunner.swift').read_text()
menu = (S / 'ThreeDExperimentMenu.swift').read_text()
selftest = (S / 'ThreeDSelfTest.swift').read_text()

check('runner loads only when the mlpackage is present', 'static func available(modelsDir: URL) -> Bool' in runner and 'guard Self.available(modelsDir: modelsDir)' in runner)
check('runner looks in the fetch-script layout (<modelsDir>/<repo>/<package>)', 'apple/coreml-depth-anything-v2-small' in runner)
check('runner is Mac-gated, never a build dependency; DepthModelID is isolated pure (Delivery)', '#if canImport(CoreML) && canImport(Vision)' in runner and 'enum DepthModelID: String' in runner and runner.rindex('#endif') < runner.index('enum DepthModelID: String'))  # 195y G2: DepthModelID is a relocated span in CoreMLDepthRunner.swift, still outside the gate
check('no Depth Pro anywhere in the runner', 'DepthPro' not in runner and 'depth_pro' not in runner)
check('DAV2 backend plugs into the prepared-depth producer (ShotPrepareBackend), not the synth method', 'final class DAV2Backend: ShotPrepareBackend' in runner and 'DAV2Backend' not in (S / 'ThreeDSynthMethod.swift').read_text())
check('DAV2 window carries the EMA accumulator through the checkpoint (exact resume)', 'w.setState(id: 0, list: ema.map { [$0.stateBundles] } ?? [])' in runner)
check('output layout verified, never inferred: only OneComponent32Float/OneComponent16Half, stride from bytesPerRow', 'kCVPixelFormatType_OneComponent32Float' in runner and 'kCVPixelFormatType_OneComponent16Half' in runner and 'HalfFloat.toFloat' in runner and 'x * elemBytes' in runner)
check('selfTest wired into ThreeDSelfTest behind the DAV2 selection', 'dav2_selftest' in selftest and 'r.selfTest(frames: fs)' in selftest and "dav2_small_coreml self-test ms/frame" in runner)
check('self-test reads frames through the REAL nested NativePrepareRunner.FrameReader (native build 13 regression)', 'NativePrepareRunner.FrameReader(url: film, fps: clipFPS, format: kCVPixelFormatType_32BGRA)' in selftest)

# Delivery A-1: model+ema folded into B's prepare identity, one parse function shared across the boundary
check('options carry dav2Depth + dav2TemporalEMA (B identity extended)', 'var dav2Depth = false, dav2TemporalEMA = false' in opts)
check('prepareComponent folds the model tokens into B\'s identity', '("dav2", dav2Depth)' in opts and '("tempema", dav2TemporalEMA)' in opts and 'on.joined(separator: ".")' in opts)
check('ONE real parse function for the worker boundary', 'init(experiments: String)' in opts and 'ThreeDExperimentOptions(experiments: request.experiments)' in npr)
check('live snapshot reads the model + smoother switches (lock-backed)', 'DepthModelID.selected() == .dav2_small_coreml' in opts and 'ModelDepthEMA.enabled' in opts)
ps = (S / 'PrepareSupport.swift').read_text()
check('marker writes model + smoother', '"depth_model": options.dav2Depth ? DepthModelID.dav2_small_coreml.rawValue : DepthModelID.luma_y_prior.rawValue' in ps and '"dav2_temporal_ema": options.dav2TemporalEMA' in ps and 'writeJSON(PrepareSupport.prepareIdentity(expOptions), to: modeMarker)' in assembly)
check('optionsMatch compares model + smoother; absent marker = pre-195h all-off only', 'o["depth_model"] as? String' in support and '!options.depthRangeEMA && !options.dav2Depth && !options.dav2TemporalEMA' in support)

# Delivery A-3: no cross-model resume through shared aux files
check('the mode fence wipes spool+checkpoint with the container BEFORE any checkpoint read (Delivery A-3)', 'the mode fence runs BEFORE any checkpoint or spool is read' in assembly and 'job.dzc.appendingPathExtension("ema.json"), job.spool' in assembly and 'if let cku = job.checkpointURL { stale.append(cku) }' in assembly and assembly.index('the mode fence runs BEFORE') < assembly.index('if let u = job.checkpointURL, let d = try? Data(contentsOf: u)'))
check('rebuild removes the stale align track', 'containerAction(dzc: ShotSink.depthURL(entry, i), options: expOptions) == .rebuild { try? fm.removeItem(at: alignURL) }' in npr)

# Delivery A-5: DAV2-only install runs (no VDA/MoGe requirement on that path)
check('DAV2 path is independent of the VDA/MoGe kit', 'guard expOptions.dav2Depth || (vda != nil && moge != nil)' in npr and 'expOptions.dav2Depth ? nil : moge!.shape' in npr)
check('missing DAV2 package fails loudly under an experimental request (honesty)', 'dav2-small-coreml package missing; run tools/gor-fetch-models.sh or turn off the DAV2 experiment' in npr)
check('backend pick: DAV2 replaces the VDA path only for DAV2 jobs', 'if let dav2 = dav2Runner {' in npr and 'ema: expOptions.dav2TemporalEMA ? ModelDepthEMA() : nil' in npr)

check('menu rows 11/12 under Experiments, default off', '"A depth model: DAV2 CoreML (needs models fetch)"' in menu and '"A DAV2 temporal EMA"' in menu and 'DepthModelID.select(' in menu and 'ModelDepthEMA.toggle()' in menu)
check('item 3 default off, per-shot, boundary reset', 'private static var on = false' in ema and 'func reset() { acc = nil }' in ema)
check('no parallel identity scheme: no DepthShotPaths/GorSHA256 remnants', not (S / 'DepthShotPaths.swift').exists() and 'DepthShotPaths' not in (S / 'DepthContainerWriter.swift').read_text()  # 195y G2: DepthShotIndex folded into the container file and 'DepthShotPaths' not in (S / 'ThreeDRenderCoordinator.swift').read_text())
check('Delivery A-1: request parsed BEFORE loadModels; DAV2 path skips the kit', npr.index('ThreeDExperimentOptions(experiments: request.experiments)') < npr.index('load models (all kit packages)') and 'if expOptions.requiresVDAMoGeKit {' in npr)
check('requiresVDAMoGeKit is a real shared decision', 'var requiresVDAMoGeKit: Bool { !dav2Depth }' in (S / 'ThreeDExperimentOptions.swift').read_text())
check('DAV2-only install registers a runner without the kit (ThreeDKit)', 'depth=DAV2_Small' in (S / 'ThreeDKit.swift').read_text() and 'CoreMLDepthRunner.available(modelsDir: ThreeDModels.modelsDir)' in (S / 'ThreeDKit.swift').read_text())

# Linux numeric driver against the real sources (no shadow copies) - REQUIRED: swiftc must be present
SW = '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
if not pathlib.Path(SW).exists():
    import shutil; SW = shutil.which('swiftc') or SW
check('swiftc present for the real driver', pathlib.Path(SW).exists() or subprocess.run(['bash','-c',f'command -v {SW}'],capture_output=True).returncode == 0)
if not fails or True:
    srcs = [str(T / 'main.swift')] + [str(S / (n + '.swift')) for n in ['CoreMLDepthRunner', 'ModelDepthEMA', 'ThreeDExperimentOptions', 'PrepareSupport', 'FovTrackBuilder', 'VDAStreamRunner', 'DepthGuards']]
    r = subprocess.run([SW, '-O'] + srcs + ['-o', '/tmp/coreml_depth_driver'], capture_output=True, text=True)
    check('swift driver compiles (real sources)', r.returncode == 0)
    if r.returncode != 0: print(r.stderr[-3000:])
    else:
        o = subprocess.run(['/tmp/coreml_depth_driver'], capture_output=True, text=True).stdout
        for line in o.strip().splitlines():
            name, _, res = line.rpartition(' ')
            check('driver: ' + name, res == 'true')
print('RESULT:', 'FAIL' if fails else 'PASS')
sys.exit(1 if fails else 0)
