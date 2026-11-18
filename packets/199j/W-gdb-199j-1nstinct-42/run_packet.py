#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile

CFG = json.loads(r"""{"source": "archive/gor/Sources/gor/gor/PPController_Features.swift", "markers": ["enum CaptureConsumerRules"], "support": "", "test_source": "\nif CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: false, loadedVideoActive: true, cameraAllowed: true) { print(\"RED: blink camera leg starts while VR is off\"); exit(1) }\nif !CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: true, loadedVideoActive: true, cameraAllowed: true) { print(\"FAIL: blink on in VR with loaded video must run\"); exit(1) }\nif CaptureConsumerRules.blinkShouldRun(blinkOn: false, vrEnabled: true, loadedVideoActive: true, cameraAllowed: true) { print(\"FAIL: blink off must not run\"); exit(1) }\nif CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: true, loadedVideoActive: false, cameraAllowed: true) { print(\"FAIL: no loaded video must not run\"); exit(1) }\nif !CaptureConsumerRules.headShouldRun(headTrackingEnabled: true, playbackActive: true) { print(\"FAIL head leg\"); exit(1) }\nprint(\"OK\")\nexit(0)\n"}""")

def declaration(lines, marker):
    start = None
    for i, l in enumerate(lines):
        if marker in l:
            start = i
            break
    if start is None:
        raise SystemExit("marker not found: " + marker)
    depth = 0
    seen = False
    for j in range(start, len(lines)):
        depth += lines[j].count("{") - lines[j].count("}")
        if "{" in lines[j]: seen = True
        if seen and depth <= 0:
            return lines[start:j+1]
    raise SystemExit("unbalanced: " + marker)

def main():
    swiftc = os.environ.get("SWIFTC")
    if not swiftc:
        print("NOT_RUN: SWIFTC not set")
        return 77
    root = os.environ.get("GOR_SOURCE_ROOT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "source"))
    flags = os.environ.get("SWIFTFLAGS", "").split()
    src_path = os.path.join(root, CFG["source"])
    lines = open(src_path).read().split("\n")
    decls = []
    for m in CFG["markers"]:
        decls.extend(declaration(lines, m))
    decl_text = "\n".join(decls)
    if CFG.get("wrapper"):
        decl_text = "enum %s {\n%s\n}\n" % (CFG["wrapper"], decl_text)
    body = "import Foundation\n\n" + CFG.get("support", "") + "\n" + decl_text + "\n" + CFG["test_source"]
    td = tempfile.mkdtemp(prefix="packet-")
    main_swift = os.path.join(td, "main.swift")
    binary = os.path.join(td, "main")
    with open(main_swift, "w") as f:
        f.write(body)
    c = subprocess.run([swiftc] + flags + ["-o", binary, main_swift], capture_output=True, text=True)
    print("compile_exit=%d" % c.returncode)
    if c.returncode != 0:
        print(c.stderr[-4000:])
        return 1
    r = subprocess.run([binary], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.stderr: sys.stderr.write(r.stderr[-2000:])
    print("semantic_exit=%d" % r.returncode)
    return 0

if __name__ == "__main__":
    sys.exit(main())
