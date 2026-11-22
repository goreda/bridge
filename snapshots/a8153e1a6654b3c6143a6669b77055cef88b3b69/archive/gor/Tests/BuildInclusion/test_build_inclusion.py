#!/usr/bin/env python3
"""s42 pins: build-inclusion audit over the real repo, plus mutants per rule
(every rule must CATCH the defect it exists for).

Run: python3 Tests/BuildInclusion/test_build_inclusion.py
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import build_inclusion as bi  # noqa: E402

# ---- real repo: clean apart from the documented ffprobe PENDING finding
checks, covered, pending = bi.audit(ROOT)
for name, findings in checks.items():
    assert findings == [], (name, findings)
assert pending == ["ffmpeg/bin/ffprobe"], pending
print("PASS real repo: all 6 rules clean; ffprobe pending exactly as documented")

# the s25-s41 surface the audit exists for is really there and really covered
files = bi.tracked_files(ROOT)
for f in ("Sources/gor/Stereo/Source.swift", "Sources/gor/Stereo/Depth.swift", "Sources/gor/Stereo/Prepare.swift",
          "Sources/gor/Stereo/Render.swift", "Sources/gor/Stereo/Control.swift",
          "Sources/gor/Stereo/RealtimeProbe.swift"):
    assert f in files, f
    assert f.startswith("Sources/gor/"), f  # under the Package.swift target path
print("PASS s25-s41 Swift surface all under the compiled target path")

# ---- mutants: each rule catches its own defect
PKG = 'path: "Sources/gor"'
assert bi.r1_swift_orphans(["Sources/gor/A.swift"], PKG) == []
assert bi.r1_swift_orphans(["Sources/gor/A.swift", "Sources/orphan/B.swift"],
                           PKG) == ["Sources/orphan/B.swift"]
print("PASS mutant R1: swift file outside the target path is an orphan")

src = {"Sources/gor/K.swift": 'let text = """ kernel void s3d_pack() {} """'}
assert bi.r2_metal(["Sources/gor/K.swift"], src) == []
m = bi.r2_metal(["Sources/gor/K.swift", "Sources/gor/K.metal"], src)
assert any(".metal" in f for f in m), m
src2 = {"Sources/gor/K.swift": 'makeFunction(name: "s3d_nope")'}
m = bi.r2_metal(["Sources/gor/K.swift"], src2)
assert any("s3d_nope" in f for f in m), m
print("PASS mutant R2: .metal file and missing embedded kernel both caught")

# R2 product-vs-fixture: only a proven standalone lab fixture is exempt
LAB = "Packages/gorav/Tests/labs/p-b3"
FILES = [LAB + "/Package.swift", LAB + "/Shaders/tone_map.metal",
         LAB + "/Tests/HDRReferenceTests/HDRReferenceTests.swift",
         "Packages/gorav/Package.swift", "Package.swift"]
TEXTS = {LAB + "/Package.swift": "",
         LAB + "/Tests/HDRReferenceTests/HDRReferenceTests.swift":
             'appendingPathComponent("Shaders/tone_map.metal")',
         "Packages/gorav/Package.swift": 'path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"',
         "Package.swift": 'path: "Sources/gor"'}
ex = bi.r2_fixture_exempt(FILES, TEXTS)
assert ex == {LAB + "/Shaders/tone_map.metal"}, ex
assert bi.r2_metal(FILES, {}, ex) == []
# mutant: nothing loads it at test runtime -> finding
t2 = dict(TEXTS); t2[LAB + "/Tests/HDRReferenceTests/HDRReferenceTests.swift"] = ""
assert bi.r2_fixture_exempt(FILES, t2) == set()
assert any("tone_map.metal" in f for f in bi.r2_metal(FILES, {}, bi.r2_fixture_exempt(FILES, t2)))
# mutant: the gorav manifest compiles the lab package -> finding
t3 = dict(TEXTS); t3["Packages/gorav/Package.swift"] += ' path: "Tests/labs/p-b3/Sources/HDRReference"'
assert bi.r2_fixture_exempt(FILES, t3) == set()
# mutant: a shader under a product Sources tree is never exempt, even if a test names it
F4 = ["Sources/gor/Package.swift", "Sources/gor/Tests/T.swift", "Sources/gor/Shaders/k.metal"]
assert bi.r2_fixture_exempt(F4, {"Sources/gor/Tests/T.swift": "Shaders/k.metal"}) == set()
# mutant: a .metal outside any nested package is never exempt
F5 = ["Package.swift", "Tests/X/T.swift", "Tests/X/k.metal"]
assert bi.r2_fixture_exempt(F5, {"Tests/X/T.swift": "k.metal"}) == set()
# mutant: .metal in a Tests dir with no Tests loader inside its own package
F6 = [LAB + "/Package.swift", LAB + "/Shaders/a.metal", "Tests/Other/T.swift"]
assert bi.r2_fixture_exempt(F6, {"Tests/Other/T.swift": "Shaders/a.metal"}) == set()
# mutant: a sibling package reaches the fixture with a relative ../ path
FS = FILES + ["Packages/other/Package.swift"]
t7 = dict(TEXTS); t7["Packages/other/Package.swift"] = 'path: "../gorav/Tests/labs/p-b3/Sources/HDRReference"'
assert bi.r2_fixture_exempt(FS, t7) == set()
# mutant: the top-level manifest uses a non-normalized equivalent path
t8 = dict(TEXTS); t8["Package.swift"] = 'path: "Packages/gorav/Tests/labs/../labs/p-b3"'
assert bi.r2_fixture_exempt(FILES, t8) == set()
# mutant: an ancestor path that covers the package, no package name in the text
t9 = dict(TEXTS); t9["Package.swift"] = 'path: "Packages/gorav/Tests/labs"'
assert bi.r2_fixture_exempt(FILES, t9) == set()
# mutant: a manifest whose text is unreadable cannot prove absence
t10 = dict(TEXTS); t10["Package.swift"] = None
assert bi.r2_fixture_exempt(FILES, t10) == set()
# mutant: an interpolated path cannot be resolved, fails closed
t11 = dict(TEXTS); t11["Package.swift"] = 'path: "Packages/gorav/Tests/labs/\\(name)"'
assert bi.r2_fixture_exempt(FILES, t11) == set()
# real manifest shapes: a package dependency on the ancestor package and a "."
# public-headers path do not reach the nested lab package
TR = dict(TEXTS)
TR["Package.swift"] = ('.package(name: "gorav", path: "Packages/gorav")\n'
                       '.target(name: "gor", dependencies: [], path: "Sources/gor")')
TR["Packages/gorav/Package.swift"] = (
    '.target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: ".")\n'
    '.target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux")')
assert bi.r2_fixture_exempt(FILES, TR) == {LAB + "/Shaders/tone_map.metal"}
# mutants on that shape: each must remove the exemption
def _mut(path, add):
    t = dict(TR); t[path] = t[path] + "\n" + add
    return bi.r2_fixture_exempt(FILES, t)
for mp, ad in [
    ("Package.swift", '.package(path: "Packages/gorav/Tests/labs/p-b3")'),
    ("Package.swift", '.target(name: "X", path: "Packages/gorav/Tests")'),
    ("Package.swift", '.target(name: "X", path: "Packages/gorav/Tests/labs/../labs/p-b3/Sources/HDRReference")'),
    ("Package.swift", '.target(name: "X", path: ".")'),
    ("Package.swift", '.target(name: "X", path: someVariable)'),
    ("Packages/gorav/Package.swift", '.target(name: "X", path: "Tests/labs/p-b3/Sources/HDRReference")'),
    ("Packages/gorav/Package.swift", '.target(name: "X", path: "Tests/labs", sources: ["p-b3"])'),
    ("Packages/gorav/Package.swift", '.target(name: "X", path: "Tests", sources: ["labs/p-b3/Sources"])'),
    ("Packages/gorav/Package.swift", '.package(path: "Tests/labs/p-b3")'),
]:
    assert _mut(mp, ad) == set(), (mp, ad)
# non-literal WHOLE path/sources/resources expressions fail closed
for mp, ad in [
    ("Package.swift", '.target(name: "X", path: "Packages/gorav/Tests/labs/" + "p-" + "b3")'),
    ("Package.swift", '.target(name: "X", path: "." + "/Packages/gorav/Tests/labs/p" + "-b3")'),
    ("Package.swift", '.target(name: "X", path: ("Packages/gorav/Tests/" + "labs"))'),
    ("Package.swift", '.target(name: "X", path: "Sources/gor", resources: [.copy(labPath)])'),
    ("Package.swift", '.target(name: "X", path: "Sources/gor", resources: [.copy("a"), .process(extra)])'),
    ("Package.swift", '.target(name: "X", path: "Sources/gor", sources: ["a"] + more)'),
    ("Package.swift", '.target(name: "X", path: join(base, "Tests"))'),
    ("Package.swift", '.package(path: "Packages/" + "gorav/Tests/labs/" + "p-b3")'),
    ("Packages/gorav/Package.swift", '.target(name: "X", path: someVariable)'),
]:
    assert _mut(mp, ad) == set(), (mp, ad)
# a Swift unicode escape can spell the package name: refuse any escaped literal
for mp, ad in [
    ("Package.swift", '.target(name: "X", path: "Packages/gorav/Tests/labs/p-\\u{62}3")'),
    ("Package.swift", '.target(name: "X", path: "Packages/gorav/Tests/labs/p-\\u0062" )'),
    ("Packages/gorav/Package.swift", '.target(name: "X", path: "Tests/labs/p-\\u{0062}3/Sources")'),
]:
    assert _mut(mp, ad) == set(), (mp, ad)
# a commented-out reference is not a reference
assert _mut("Package.swift", '// .target(name: "X", path: "Packages/gorav/Tests")') == {LAB + "/Shaders/tone_map.metal"}
print("PASS R2 fixture rule: standalone loaded lab fixture exempt; ten mutants plus real-manifest-shape mutants stay findings")

assert bi.r3_lua({"Sources/gor/P.swift": '"vr180-look.lua"'},
                 {"vr180-look.lua"}) == []
m = bi.r3_lua({"Sources/gor/P.swift": '"nope.lua"'}, {"vr180-look.lua"})
assert any("nope.lua" in f for f in m), m
print("PASS mutant R3: lua referenced but not bundled is caught")

SH = "ROOTS=['mpv/bin/mpv','ffmpeg/bin/ffmpeg']"
ok, _, _ = bi.r4_vendor_gate({"Sources/gor/S.swift": 'vendorPath("mpv/bin/mpv")'}, SH)
assert ok == []
m, _, _ = bi.r4_vendor_gate(
    {"Sources/gor/S.swift": 'vendorPath("ffmpeg/bin/ffprobe2")'}, SH)
assert any("ffprobe2" in f for f in m), m
m, _, _ = bi.r4_vendor_gate(  # pending entry that became covered: stale
    {"Sources/gor/S.swift": ""},
    "ROOTS=['mpv/bin/mpv','ffmpeg/bin/ffmpeg','ffmpeg/bin/ffprobe']")
assert any("ffprobe" in f and "stale" not in f or "PENDING" in f for f in m), m
print("PASS mutant R4: ungated vendor binary and stale pending both caught")

assert bi.r5_python_copies('cp "$project_root/tools/gor-periodic-capture.py" "$res/"',
                           ["tools/gor-periodic-capture.py"]) == []
m = bi.r5_python_copies('cp "$project_root/tools/gone.py" "$res/"', [])
assert any("gone.py" in f for f in m), m
m = bi.r5_python_copies("echo kit_log_watch", ["tools/depth_analysis/kit_log_watch.py"])
assert any("kit_log_watch" in f for f in m), m
print("PASS mutant R5: missing copied py and shipped Linux-only tool both caught")

MAN = json.load(open(os.path.join(
    ROOT, "tools/depth_analysis/kit/kit_manifest.json")))
KIT = (lambda _b: _b[_b.index('// BEGIN relocated ThreeDKit.swift '):_b.index('// END relocated ThreeDKit.swift\n')])(_threed_split().path(ROOT).read_text())
assert bi.r6_kit_manifest(MAN, KIT) == []
man2 = json.loads(json.dumps(MAN))
del man2["packages"]["encoder_fp16.mlpackage"]
assert any("encoder_fp16" in f for f in bi.r6_kit_manifest(man2, KIT))
man3 = json.loads(json.dumps(MAN))
man3["packages"]["stream_fp16.mlpackage"]["content_sha256"] = "xyz"
assert any("content_sha256" in f for f in bi.r6_kit_manifest(man3, KIT))
print("PASS mutant R6: missing required package and bad sha both caught")

# CLI smoke on the real repo
import subprocess
p = subprocess.run([sys.executable,
                    os.path.join(ROOT, "tools/build_inclusion.py"),
                    "--root", ROOT], stdout=subprocess.PIPE)
assert p.returncode == 0, p.stdout.decode()
print("PASS CLI rc 0 on the real repo")

print("build_inclusion: all pins hold")
