#!/usr/bin/env python3
"""ThreeDKit: Python model of missing(listing:) against kit_manifest.json + wiring pins (Swift uncompiled; no kit exists in the repo, nothing run on a Mac)."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]; S = root / 'Sources/gor'
sw = (S / 'ThreeDKit.swift').read_text(); wi = (S / 'ThreeDWiring.swift').read_text(); nr = (S / 'NativePrepareRunner.swift').read_text()
man = json.loads((root / 'tools/depth_analysis/kit/kit_manifest.json').read_text())['packages']
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
VDA = ['encoder_fp16.mlpackage', 'bootstrap_fp16.mlpackage', 'stream_fp16.mlpackage']
def missing(listing):
    m = [n for n in VDA if n not in listing]
    if not any(n.startswith('moge2_vits_') and n.endswith('.mlpackage') for n in listing): m.append('moge2_vits_*.mlpackage')
    return m
check('model: full manifest listing is complete', missing(list(man)) == [])
check('model: empty dir misses all four', len(missing([])) == 4)
check('model: one moge shape is enough; a missing vda piece is named', missing(VDA + ['moge2_vits_518x294_fp32.mlpackage']) == [] and missing(['encoder_fp16.mlpackage', 'moge2_vits_518x518_fp16.mlpackage']) == ['bootstrap_fp16.mlpackage', 'stream_fp16.mlpackage'])
check('Swift package names equal the runner loader and the manifest', all(n in sw and n in nr for n in VDA) and all(n in man for n in VDA) and 'moge2_vits_' in nr)
check('registers NativePrepareRunner(kitDir:) into the registry, idempotent, one OSD line', 'NativePrepareRunner(kitDir: dir)' in sw and 'ThreeDRunnerRegistry.runner = r' in sw and 'if ThreeDRunnerRegistry.runner != nil { return true }' in sw and 'if !told' in sw)
check('wiring: after models verify, before the launcher; reason "CoreML kit missing" keeps the film 2D', 'ThreeDKit.register(report: osd)' in wi and 'CoreML kit missing' in wi and wi.index('ThreeDKit.register') < wi.index('l.update('))
check('default dir next to the models, GOR_KIT_DIR override', 'appendingPathComponent("kit"' in sw and 'GOR_KIT_DIR' in sw)
check('no player-socket words', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', sw + wi, re.I))
sm = (S / 'ThreeDModels.swift').read_text()
check('ThreeDModels also needs the kit marker for coreml-kit rows (installed-<id> == row sha)', 'static func kitInstalled' in sm and '.installed-' in sm and '|| !Self.kitInstalled($0)' in sm)
check('MoGe-only gap gets the not-downloaded-yet line (licence approved 190w W1), other gaps the missing list', 'is not downloaded yet' in sw and 'CoreML kit missing' in sw)
lk = (root / 'models/models.lock.tsv').read_text().split('\n'); kr = [l.split('\t') for l in lk if 'coreml-kit' in l.split('\t')[0]]
check('real lock: VDA kit and MoGe kit usable (190w W1), both on one https github release URL the script maps to gh', len(kr) == 3 and {r[0]: r[1] for r in kr} == {'vda-coreml-kit': 'usable', 'vda-windowed-coreml-kit': 'usable', 'moge2-coreml-kit': 'usable'} and all(r[3] == 'https://github.com/goreda/gorav' for r in kr))
check('Swift Row.repo strips https:// like the script (lrepo), so the archive path matches', 'dropFirst(8)' in sm and 'lrepo="${repo#https://}"' in (root / 'tools/gor-fetch-models.sh').read_text())
check('registered runner gets modelsDir (compiled cache) ', 'r.modelsDir = ThreeDModels.modelsDir' in sw)
check('self-test hook: policy gate, marker name from manifest sha + build, one start per launch, utility queue, runs only after kit+models+no preparing film', 'ThreeDSelfTest.shouldRun(enabled: enabled, kitPresent: missing(dir: kit).isEmpty' in sw and 'markerName(manifestSha: sha, build: build)' in sw and 'selfTestStarted = true' in sw and 'qos: .utility' in sw and 'ThreeDKit.maybeSelfTest(enabled: true, filmPreparing: l.isPreparing)' in wi and 'var isPreparing: Bool { running != nil }' in (S / 'ThreeDPrepareLauncher.swift').read_text())
check('self-test emit reaches the log: default emit is print+fflush(stdout) and AppDelegate dup2s stdout into gor-log-writer, unbuffered, same path as the build-id line', 'print($0) }; fflush(stdout)' in (S / 'ThreeDSelfTest.swift').read_text() and 'dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)' in (S / 'AppDelegate.swift').read_text() and 'setbuf(stdout, nil)' in (S / 'AppDelegate.swift').read_text() and 'print(BuildID.logLine(' in (S / 'AppDelegate.swift').read_text())
sys.exit(1 if bad else 0)
