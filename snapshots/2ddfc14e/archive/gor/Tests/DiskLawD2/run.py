#!/usr/bin/env python3
"""DISK-LAW D2 (199h) regression guards. Source-level: operates on the rebuilt ThreeD monolith
(threed_split), so the split-manifest pins are verified as a side effect. Native NOT_RUN.
Default: all guards green on the patched tree. --mutants: discrimination controls, each must go RED.
"""
import importlib.util as _iu, pathlib as _pl, hashlib, json, sys, tempfile

def _threed_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

ROOT = _pl.Path(__file__).resolve().parents[2]

def decl(text, marker, after=None):
    start = text.index(marker); opening = text.index(after or '{', start) + (len(after) - 1 if after else 0); level = 1; i = opening + 1
    while level:
        if text[i] == '{': level += 1
        elif text[i] == '}': level -= 1
        i += 1
    return text[start:i]
MUTANTS = '--mutants' in sys.argv
s = _threed_split().text(ROOT)

GUARDS = [
 ('G17 selftest-original-film-consumer',lambda t:'sourceProxy: source' not in t and 'sourceProxy: film, frames: testFrames' in t and 'tel.note("decoder_source", "original-film")' in t),
 ('G1 no-proxy-encoder-call', lambda t: 'VTShotEncoder(' not in t),
 ('G2 no-proxy-sink-api', lambda t: 'beginSource' not in t and 'finishSource' not in t and 'func finishShot(' in t),
 ('G3 readiness-depth-only', lambda t: '"source_ready"' not in t),
 ('G4 proxy-name-sweep-only', lambda t: all(('let pattern=' in ln) or ('legacy proxy name' in ln) or ('190t A: in-app HEVC' in ln) or ('static func sourceURL(' in ln) for ln in t.splitlines() if 'source_shot_' in ln)),
 ('G5 original-film-writer', lambda t: 'func write(film: URL, startFrame: Int, endFrame: Int, fps: Double, firstPTS: Double' in t and 'sr.timeRange = CMTimeRange(' in t),
 ('G6 transient-shot-law', lambda t: 'private static func transientShotCopy(film: URL, to out: URL' in t and '"-c", "copy", "-copyts"' in t and 'NSTemporaryDirectory' in t
    and 'defer { if let t = transient { try? FileManager.default.removeItem(at: t) } }' in t
    and t.index('defer { if let t = transient { try? FileManager.default.removeItem(at: t) } }') < t.index('transientShotCopy(film: film, to:')
    and all(x in decl(t, 'private static func transientShotCopy(', ') -> Bool {') for x in ('deadline', 'p.terminate()', 'p.isRunning', 'cancelled()'))),
 ('G7 deterministic-and-real-pts-pairing', lambda t: 'ShotEncoding.pts(frame: startFrame + completedFrames, fps: fpsR)' in t
    and 'expPTS = filmStart + Double(completedFrames) / fps' in t and 'abs(srcPTS - expPTS)' in t),
 ('G11 first-pts-fail-closed', lambda t: 'self.firstPTS = (f["first_pts"] as? NSNumber)?.doubleValue ?? 0' in t and 'let filmStart = firstPTS + Double(startFrame) / fps' in t),
 ('G8 first-pts-plumbing', lambda t: '"first_pts"' in t and 'self.firstPTS' in t and 'firstPts: facts.firstPTS' in t),
 ('G9 frame-count-termination', lambda t: 'while completedFrames < shotFrames' in t and 'guard completedFrames == shotFrames' in t),
 ('G10 by-index-original-readers', lambda t: t.count('FrameReader(url: readableFilm,') == 2),
 ('G12 stderr-async-drain', lambda t: (lambda h: '.readabilityHandler = {' in h and 'err.fileHandleForReading.availableData' not in h)(decl(t, 'private static func transientShotCopy(', ') -> Bool {'))),
 ('G13 bounded-reap', lambda t: (lambda h: 'killpg(p.processIdentifier, SIGKILL)' in h and h.index('p.terminate()') < h.index('killpg(p.processIdentifier, SIGKILL)'))(decl(t, 'private static func transientShotCopy(', ') -> Bool {'))),
 ('G14 nonfinite-pts-fail-closed', lambda t: 'guard srcPTS.isFinite, expPTS.isFinite, abs(srcPTS - expPTS)' in t and 'guard depthDelta.isFinite, abs(depthDelta)' in t),
 ('G15 process-group-kill', lambda t: (lambda h: 'setpgid(p.processIdentifier, p.processIdentifier)' in h and h.count('killpg(') >= 2)(decl(t, 'private static func transientShotCopy(', ') -> Bool {'))),
 ('G16 eof-independent-return', lambda t: (lambda h: 'try? err.fileHandleForReading.close()' in h and h.index('try? err.fileHandleForReading.close()') < h.index('p.waitUntilExit()'))(decl(t, 'private static func transientShotCopy(', ') -> Bool {'))),
]

MUTATIONS = {
 'M-stale-selftest-source': ('sourceProxy: film, frames: testFrames','sourceProxy: source, frames: testFrames'),
 'M-proxy-encode': ('sink.finishShot(shot: i, depthSize:', '_ = sink.beginSource; sink.finishShot(shot: i, depthSize:'),
 'M-source-ready': ('"depth_ready": d, "ready": d,', '"depth_ready": d, "source_ready": d, "ready": d,'),
 'M-find-proxy-gate': ('guard DZCFile.isComplete(dz) else { return nil }', 'guard DZCFile.isComplete(dz), FileManager.default.fileExists(atPath: entry.appendingPathComponent(String(format: "source_shot_%05d.mp4", i)).path) else { return nil }'),
 'M-transient-leak': ('defer { if let t = transient { try? FileManager.default.removeItem(at: t) } }', '// mutant: transient copy left behind'),
 'M-no-deadline': ('if cancelled() || Date() > deadline {\n                p.terminate()\n                killpg(p.processIdentifier, SIGTERM)\n                let grace = Date().addingTimeInterval(2)\n                while p.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }\n                if p.isRunning { kill(p.processIdentifier, SIGKILL); killpg(p.processIdentifier, SIGKILL) }\n                break\n            }', '// mutant: no deadline, no cancel'),
 'M-gap-duplicate-passes': ('guard srcPTS.isFinite, expPTS.isFinite, abs(srcPTS - expPTS) <= 0.5 / 24.0 else { throw fail(.pairing) }', '// mutant: gap/duplicate source frames pass'),
 'M-firstpts-failopen': ('let filmStart = firstPTS + Double(startFrame) / fps', 'let filmStart = Double(startFrame) / fps // mutant: first_pts dropped'),
 'M-passthrough-pts': ('let t = ShotEncoding.pts(frame: startFrame + completedFrames, fps: fpsR)', 'let t = ShotEncoding.pts(frame: startFrame, fps: fpsR) // mutant: not the per-frame shot PTS'),
 'M-no-async-drain': ('err.fileHandleForReading.readabilityHandler = { h in _ = h.availableData }', '// mutant: stderr not drained asynchronously'),
 'M-unbounded-reap': ('if p.isRunning { kill(p.processIdentifier, SIGKILL); killpg(p.processIdentifier, SIGKILL) }', '// mutant: unbounded reap after SIGTERM'),
 'M-nan-failopen': ('guard srcPTS.isFinite, expPTS.isFinite, abs(srcPTS - expPTS) <= 0.5 / 24.0', 'guard abs(srcPTS - expPTS) <= 0.5 / 24.0 // mutant: NaN passes'),
 'M-depth-nan-failopen': ('guard depthDelta.isFinite, abs(depthDelta) <= 0.5 / 24.0', 'guard abs(depthDelta) <= 0.5 / 24.0 // mutant: NaN depth PTS passes'),
 'M-no-process-group': ('setpgid(p.processIdentifier, p.processIdentifier)   // own process group: cancel/timeout kills the whole tree, descendants included', '// mutant: child stays in the parent group'),
 'M-direct-kill-only': ('killpg(p.processIdentifier, SIGTERM)', 'p.terminate() // mutant: direct child only'),
 'M-eof-wait': ('try? err.fileHandleForReading.close()', '// mutant: return waits on pipe EOF'),
}

def run_guards(text):
    return [name for name, g in GUARDS if not g(text)]

rows = []
if not MUTANTS:
    fails = run_guards(s)
    for name, _ in GUARDS:
        rows.append(dict(guard=name, ok=name not in fails))
        print(('PASS ' if name not in fails else 'FAIL ') + name)
    out = ROOT / 'Tests/DiskLawD2/RESULTS.json'
    out.write_text(json.dumps(dict(source_sha256=hashlib.sha256(s.encode()).hexdigest(), rows=rows,
                                   scope='source guards over the pin-verified rebuilt monolith; native NOT_RUN'), indent=2) + '\n')
    assert not fails, fails
    print('PASS all DISK-LAW D2 guards (structural; native behavior unverified)')
else:
    for name, (old, new) in MUTATIONS.items():
        assert s.count(old) >= 1, (name, 'marker absent')
        mt = s.replace(old, new, 1)
        fails = run_guards(mt)
        ok = len(fails) > 0
        rows.append(dict(mutant=name, discriminates=ok, tripped=fails))
        print(('PASS ' if ok else 'FAIL ') + name + ' tripped: ' + ','.join(fails))
    assert all(r['discriminates'] for r in rows)
    print('PASS all mutants discriminated')
