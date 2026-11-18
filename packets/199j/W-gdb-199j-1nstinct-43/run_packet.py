#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile

CFG = json.loads(r"""{"source": "archive/gor/Sources/gor/AppDelegate.swift", "markers": ["struct QuitToken", "static func readQuitToken"], "support": "let quitTokenURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(\"gor-quit-token-test.json\")\n", "test_source": "\nfunc writeToken(_ s: String) { try! s.write(to: quitTokenURL, atomically: true, encoding: .utf8) }\nwriteToken(\"{\\\"pid\\\": 4301, \\\"epoch\\\": 7, \\\"wall\\\": 123.5}\")\nguard let t = A43Host.readQuitToken(), t.pid == 4301, t.epoch == 7, t.wall == 123.5 else { print(\"FAIL valid round-trip\"); exit(1) }\nwriteToken(\"{\\\"pid\\\": 1099511627776, \\\"epoch\\\": 7, \\\"wall\\\": 123.5}\")\nif A43Host.readQuitToken() != nil { print(\"FAIL hostile pid accepted\"); exit(1) }\nwriteToken(\"{\\\"pid\\\": 4301, \\\"epoch\\\": -1, \\\"wall\\\": 123.5}\")\nif A43Host.readQuitToken() != nil { print(\"FAIL negative epoch accepted\"); exit(1) }\nprint(\"OK\")\nexit(0)\n", "wrapper": "A43Host"}""")

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
