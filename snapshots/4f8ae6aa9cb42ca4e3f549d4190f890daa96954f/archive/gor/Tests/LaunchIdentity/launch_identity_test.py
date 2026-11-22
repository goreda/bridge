#!/usr/bin/env python3
"""arch-199b launch identity line: Linux unit test of the emitted line.

gor emits one bounded line at each launch:
    [GOR] build-id <installed-sha> tree=<archive/gor-tree-sha> launch=<utc-iso>
The test compiles the real Sources/gor/GorCore/BuildID.swift on Linux, drives its pure
parsers and line builder, then passes the emitted line through the real
extract() of tools/gor-periodic-capture.py to prove the line rides the
existing capture route (gor-capture-mac branch). Darwin compile: NOT_RUN on
Linux - BuildID.swift is Foundation-only and compiles here; the app target
(AppDelegate.swift callsite) compiles only on the Mac.

Run: python3 Tests/LaunchIdentity/launch_identity_test.py
Env: SWIFTC overrides the swiftc path. Exit code 0 means every pin passed.
"""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import datetime, os, re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFTC = os.environ.get("SWIFTC", "swiftc")

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

EPOCH = 1794775732  # fixed launch instant for a deterministic line
EXPECTED_ISO = datetime.datetime.fromtimestamp(EPOCH, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
BUILD = "f699ed0c" + "0" * 56
TREE = "bb3e0ea0" + "0" * 32

MAIN = r'''
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ extra: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok ? "" : "\n" + extra))
    failures += ok ? 0 : 1
}

let sample = "commit=BUILD_SHA\nidentity_kind=source-manifest-sha256\ntree=TREE_SHA\n"
check("parseCommit reads the commit value", BuildID.parseCommit(sample) == "BUILD_SHA")
check("parseTree reads the tree value", BuildID.parseTree(sample) == "TREE_SHA")
check("parseCommit tolerates a missing tree line", BuildID.parseCommit("commit=BUILD_SHA\n") == "BUILD_SHA")
check("parseTree tolerates a legacy file without tree", BuildID.parseTree("commit=BUILD_SHA\nidentity_kind=source-manifest-sha256\n") == nil)
check("parseCommit rejects an empty value", BuildID.parseCommit("commit=\n") == nil)
check("parseCommit rejects whitespace in the value", BuildID.parseCommit("commit=BUILD_SHA extra\n") == nil)
check("parseTree rejects a short value", BuildID.parseTree("tree=abc\n") == nil)
check("parseTree rejects uppercase hex", BuildID.parseTree("tree=TREE_UPPER\n") == nil)
check("parseTree rejects whitespace in the value", BuildID.parseTree("tree=TREE_SHA x\n") == nil)

let at = Date(timeIntervalSince1970: LAUNCH_EPOCH)
let line = BuildID.launchLine(value: "BUILD_SHA", tree: "TREE_SHA", at: at)
let expected = "[GOR] build-id BUILD_SHA tree=TREE_SHA launch=EXPECTED_LAUNCH"
check("launch line exact composition", line == expected, line)
check("launch timestamp UTC seconds", BuildID.launchTimestamp(at) == "EXPECTED_LAUNCH")
check("launch line is ASCII only", line.allSatisfy { $0.isASCII })
check("launch line is a single line", !line.contains("\n"))
let shape = try! NSRegularExpression(pattern: #"^\[GOR\] build-id ([0-9a-f]{64}|unknown) tree=([0-9a-f]{40}|unknown) launch=(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)$"#)
check("launch line matches the capture family shape",
      shape.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil, line)

let degraded = BuildID.launchLine(value: BuildID.unknown, tree: BuildID.unknown, at: at)
check("unknown fallbacks stay in shape", degraded == "[GOR] build-id unknown tree=unknown launch=EXPECTED_LAUNCH", degraded)
let guarded = BuildID.launchLine(value: "bad value", tree: "", at: at)
check("whitespace/empty inputs degrade to unknown", guarded == "[GOR] build-id unknown tree=unknown launch=EXPECTED_LAUNCH", guarded)

print("SWIFT_FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
'''

main = (MAIN
        .replace("BUILD_SHA", BUILD)
        .replace("TREE_UPPER", TREE.upper())
        .replace("TREE_SHA", TREE)
        .replace("LAUNCH_EPOCH", str(EPOCH))
        .replace("EXPECTED_LAUNCH", EXPECTED_ISO))

with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / "main.swift").write_text(main)
    binary = d / "launch-id-test"
    build = subprocess.run(
        [SWIFTC, "-O", "-o", str(binary), str(_core_materialize(ROOT / "Sources/gor/GorCore/BuildID.swift", d / "BuildID.swift")), str(d / "main.swift")],
        capture_output=True, text=True, timeout=600)
    check("swiftc compiles BuildID.swift plus the test main on Linux", build.returncode == 0, build.stderr[-2000:])
    if build.returncode == 0:
        run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
        sys.stdout.write(run.stdout)
        check("swift unit pins all pass", run.returncode == 0, run.stdout[-2000:] + run.stderr[-2000:])
    else:
        check("swift unit pins all pass", False, "compile failed")

    # Route proof: the emitted line must survive the real capture extract().
    sys.path.insert(0, str(ROOT / "tools"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("capture", ROOT / "tools/gor-periodic-capture.py")
    capture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(capture)
    line = "[GOR] build-id %s tree=%s launch=%s" % (BUILD, TREE, EXPECTED_ISO)
    rows = capture.extract("gor_diag.log", "noise before\n" + line + "\nnoise after\n")
    want = "%s GOR-LAUNCH v1 build=%s tree=%s launch=%s" % (EXPECTED_ISO, BUILD, TREE, EXPECTED_ISO)
    check("capture extract carries the launch line as GOR-LAUNCH v1", rows == [want], rows)

    # Backward compatibility: a legacy line without tree/launch is simply not a
    # launch-identity row, and the build-id header reader is untouched.
    legacy = capture.extract("gor_diag.log", "[GOR] build-id %s\n" % BUILD)
    check("legacy build-id line stays out of the launch family", legacy == [], legacy)
    res = d / "Resources"
    res.mkdir()
    (res / "build-id.txt").write_text("commit=%s\nidentity_kind=source-manifest-sha256\ntree=%s\n" % (BUILD, TREE))
    header = capture.build_evidence(res)
    check("build-id header reader still reports source_manifest_sha256",
          "installed-build source_manifest_sha256=" + BUILD in header, header)

print("FAILURES: %d" % fails)
sys.exit(1 if fails else 0)
# Notes for the next reader:
# 1. The Swift half is the unit test of the emitted line: it compiles the real
#    shipping BuildID.swift, never a copy, so a format drift fails here.
# 2. The Python half proves the route: extract() is imported from the real
#    gor-periodic-capture.py, so a capture-side drift also fails here.
# 3. Darwin compile is NOT_RUN on Linux: AppDelegate.swift (the callsite) needs
#    the Mac app target. BuildID.swift itself is Foundation-only and compiles
#    here, which is what this test exercises.
# 4. The fixed epoch makes the expected line byte-exact; EXPECTED_ISO is derived
#    from the same epoch, not hardcoded.
# 5. gor-ci is not used; nothing here costs money.
