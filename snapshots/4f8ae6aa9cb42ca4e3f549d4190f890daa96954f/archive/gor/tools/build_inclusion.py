"""s42: build-inclusion audit - every s25-s41 file must be in what
`build.sh --update` compiles/copies, pinned by a Linux test.

Checks (pure functions over repo contents; CLI prints findings):
  R1 swift-target:   every tracked *.swift under Sources/ lives under a
                     Package.swift target path (SwiftPM compiles only those;
                     a file outside is silently NOT built)
  R2 metal-embed:    no tracked *.metal in a product tree (SwiftPM never
                     compiles them); every makeFunction(name: "X") has
                     `kernel void X` embedded in a compiled Swift file
                     (Stereo3DKernelSource pattern). A .metal file is a test
                     fixture, reported as INFO and not as a finding, only when
                     r2_fixture_exempt proves all of: it sits under a Tests/
                     directory, inside a standalone nested Swift package that
                     no other Package.swift references, and a Swift file under
                     that package's Tests/ names its path (loaded at test
                     runtime). Anything else, including every .metal under
                     Sources/, stays a finding.
  R3 lua:            every "<name>.lua" literal referenced in compiled Swift
                     exists in Resources/vendor/mpv/scripts (the dir build.sh
                     bundles wholesale into gor-build-manifest.json)
  R4 vendor-gate:    every GORResources.vendorPath("X") in compiled Swift is
                     an exact entry of build.sh's vendor-gate ROOTS list, or a
                     documented PENDING entry (finding reported to delivery)
  R5 python-copies:  every python file build.sh copies into the bundle
                     ($res/...) exists; Linux-only tools (mac_log_check,
                     kit_log_watch, soak_prepare_play) must NOT be referenced
                     by build.sh (they are receive-side, never shipped)
  R6 kit-manifest:   kit_manifest.json covers every package ThreeDKit.swift
                     requires, with sha256 + size per package

CLI: python3 tools/build_inclusion.py [--root REPO] [--json]
Exit 0 = no findings beyond documented PENDING; 1 = finding.
"""
import argparse
import json
import posixpath
import re
import subprocess
import sys
from pathlib import Path

LUA_SCRIPT_ROOT = "Resources/vendor/mpv/scripts"
# vendorPath literals the build.sh gate does not cover yet; each entry is a
# finding ALREADY reported to the delivery lane. The test fails when one
# becomes covered (remove the entry) and when an unlisted literal appears.
PENDING_VENDOR = {
    "ffmpeg/bin/ffprobe": "s42 finding: used by StereoSourceGate (s37) and "
                          "SourcePixelCrop; absent from build.sh vendor-gate "
                          "ROOTS - its presence/closure is never verified, so "
                          "a missing/broken ffprobe silently degrades stereo "
                          "routing to the filename candidate",
}
LINUX_ONLY_TOOLS = ("mac_log_check", "kit_log_watch", "soak_prepare_play")

VENDOR_PATH_RE = re.compile(r'vendorPath\("([^"]+)"\)')
MAKE_FN_RE = re.compile(r'makeFunction\(name:\s*"([^"]+)"\)')
LUA_RE = re.compile(r'"([A-Za-z0-9_./-]+\.lua)"')
ROOTS_RE = re.compile(r"ROOTS=\[([^\]]*)\]")
TARGET_PATH_RE = re.compile(r'path:\s*"([^"]+)"')
CP_RES_RE = re.compile(
    r'cp\s+(?:-\w+\s+)?"?(?:\$project_root/)?([\w./-]+\.py)"?\s+"\$res/')


def tracked_files(root):
    out = subprocess.run(["git", "-C", str(root), "ls-files"],
                         stdout=subprocess.PIPE, check=True)
    return [p for p in out.stdout.decode().splitlines()
            if not p.startswith(("work/", "archive/"))]


def read(root, path):
    try:
        return (Path(root) / path).read_text(errors="replace")
    except OSError:
        return None


def r1_swift_orphans(files, package_swift):
    targets = TARGET_PATH_RE.findall(package_swift)
    orphans = []
    for f in files:
        if f.endswith(".swift") and f.startswith("Sources/"):
            if not any(f == t or f.startswith(t.rstrip("/") + "/")
                       for t in targets):
                orphans.append(f)
    return sorted(orphans)


_R2_TARGET_CALLS = ("target", "executableTarget", "testTarget", "plugin",
                    "macro", "systemLibrary", "binaryTarget")
_R2_STR = r'"((?:[^"\\\n]|\\.)*)"'


def _r2_strip_comments(text):
    out, i, n, instr = [], 0, len(text), False
    while i < n:
        c = text[i]
        if instr:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                instr = False
        elif c == '"':
            instr = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                return None
            i = j + 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def _r2_calls(text, name):
    """Yield (start, end, body) for every `.name(` call; None when parens do
    not balance (caller fails closed)."""
    res = []
    for m in re.finditer(r"\.%s\s*\(" % name, text):
        depth, i, instr = 1, m.end(), False
        while i < len(text) and depth:
            c = text[i]
            if instr:
                if c == "\\":
                    i += 1
                elif c == '"':
                    instr = False
            elif c == '"':
                instr = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        if depth:
            return None
        res.append((m.start(), i, text[m.end():i - 1]))
    return res


def _r2_overlaps(x, pkg):
    return (x in ("", ".") or x == pkg or x.startswith(pkg + "/")
            or pkg.startswith(x + "/"))


def _r2_pathlike(lit):
    return ("://" not in lit and ("/" in lit or lit in (".", "..")))


_R2_LABELS = ("path", "sources", "exclude", "resources", "publicHeadersPath")
_R2_LIT = re.compile(_R2_STR)
_R2_ELEM = re.compile(
    r'\s*(?:\.(?:copy|process|embedInCode)\(\s*' + _R2_STR + r'\s*\)|' + _R2_STR + r')\s*(?:,|$)')


def _r2_labeled(body):
    """Literals given to path/sources/exclude/resources/publicHeadersPath in
    one call body. Each value must be exactly one string literal, or an array
    whose every element is one string literal or .copy/.process/.embedInCode
    of one string literal. Returns None (fail closed) for anything else:
    variables, concatenation, interpolation, computed elements."""
    lits = []
    for lab in _R2_LABELS:
        for m in re.finditer(r"\b%s\s*:\s*" % lab, body):
            rest = body[m.end():]
            if rest.startswith('"'):
                lm = _R2_LIT.match(rest)
                if not lm or "\\(" in lm.group(1):
                    return None
                tail = rest[lm.end():].lstrip()
                if tail and tail[0] not in ",)":
                    return None
                lits.append(lm.group(1))
            elif rest.startswith("["):
                depth, i, instr = 0, 0, False
                while i < len(rest):
                    c = rest[i]
                    if instr:
                        if c == "\\":
                            i += 1
                        elif c == '"':
                            instr = False
                    elif c == '"':
                        instr = True
                    elif c == "[":
                        depth += 1
                    elif c == "]":
                        depth -= 1
                        if depth == 0:
                            break
                    i += 1
                if depth:
                    return None
                inner = rest[1:i]
                pos = 0
                while pos < len(inner) and inner[pos:].strip():
                    em = _R2_ELEM.match(inner, pos)
                    if not em or em.end() == pos:
                        return None
                    lit = em.group(1) if em.group(1) is not None else em.group(2)
                    if lit is None or "\\(" in lit:
                        return None
                    lits.append(lit)
                    pos = em.end()
                tail = rest[i + 1:].lstrip()
                if tail and tail[0] not in ",)":
                    return None
            else:
                return None
    return lits


def _r2_manifest_reaches(m, body, pkg):
    """True when manifest m can select the nested package directory pkg as a
    SwiftPM source root, or depend on that package. A `.package(path:)`
    dependency reaches only the package it names: depending on an ancestor
    package does not compile its nested Tests packages. Target roots, sources,
    resources and any other path literal, resolved against the target root and
    normalized, reach pkg when they equal it, sit below it or are an ancestor
    of it. Fail closed on anything not provable: unreadable text, unbalanced
    parens, any path-like argument that is not exactly one literal (variable,
    concatenation, interpolation, computed resource), or a string literal
    joined to another expression with +."""
    if body is None:
        return True
    if pkg.rsplit("/", 1)[-1] in body:
        return True
    text = _r2_strip_comments(body)
    if text is None:
        return True
    if re.search(r'"\s*\+|\+\s*"', text):
        return True
    # a backslash escape (\u{62}, \u0062, \n ...) can spell a path the raw text
    # does not show; refusing is the minimal safe rule
    if any("\\" in lit for lit in re.findall(_R2_STR, text)):
        return True
    if re.search(r"\.(?:copy|process|embedInCode)\s*\(\s*[^\s\"\)]", text):
        return True
    mdir = m.rsplit("/", 1)[0] if "/" in m else ""

    def res(base, lit):
        return posixpath.normpath(posixpath.join(base, lit))

    deps = _r2_calls(text, "package")
    if deps is None:
        return True
    cut = []
    for st, en, b in deps:
        cut.append((st, en))
        lits = _r2_labeled(b)
        if lits is None:
            return True
        for lit in lits:
            if res(mdir, lit) == pkg:
                return True
    for call in _R2_TARGET_CALLS:
        tg = _r2_calls(text, call)
        if tg is None:
            return True
        for st, en, b in tg:
            cut.append((st, en))
            lits = _r2_labeled(b)
            if lits is None:
                return True
            pm = re.search(r"\bpath\s*:\s*" + _R2_STR, b)
            if pm:
                root = res(mdir, pm.group(1))
                if _r2_overlaps(root, pkg):
                    return True
            else:
                nm = re.search(r"\bname\s*:\s*" + _R2_STR, b)
                if not nm or "\\(" in nm.group(1):
                    return True
                kind = "Tests" if call == "testTarget" else "Sources"
                root = res(mdir, kind + "/" + nm.group(1))
            for lit in re.findall(_R2_STR, b):
                if "\\(" in lit:
                    return True
            for lit in lits:
                if _r2_overlaps(res(root, lit), pkg):
                    return True
    rest, last = [], 0
    for st, en in sorted(cut):
        rest.append(text[last:st])
        last = max(last, en)
    rest.append(text[last:])
    rest = "".join(rest)
    if _r2_labeled(rest) is None:
        return True
    for lit in re.findall(_R2_STR, rest):
        if "\\(" in lit:
            return True
        if _r2_pathlike(lit) and _r2_overlaps(res(mdir, lit), pkg):
            return True
    return False


def _r2_referenced(pkg, manifests, texts):
    """True unless no other Package.swift in the tree can reach pkg."""
    return any(_r2_manifest_reaches(m, texts.get(m), pkg)
               for m in sorted(manifests))


def r2_fixture_exempt(files, texts):
    """.metal paths proven to be standalone lab test fixtures.

    files: tracked paths. texts: path -> text for every tracked Package.swift
    and every tracked .swift under a Tests/ directory. All conditions must
    hold; a missing text counts as not proven."""
    fileset = set(files)
    manifests = {f for f in files if f.endswith("Package.swift")}
    exempt = set()
    for f in files:
        if not f.endswith(".metal"):
            continue
        parts = f.split("/")
        if "Tests" not in parts[:-1] or "Sources" in parts[:-1]:
            continue
        pkg = None
        for i in range(len(parts) - 1, 0, -1):
            cand = "/".join(parts[:i])
            if cand + "/Package.swift" in fileset:
                pkg = cand
                break
        if pkg is None:
            continue
        own = pkg + "/Package.swift"
        if _r2_referenced(pkg, manifests - {own}, texts):
            continue
        inner = f[len(pkg) + 1:]
        loaders = [t for t, body in texts.items()
                   if t.startswith(pkg + "/Tests/") and t.endswith(".swift")
                   and inner in (body or "")]
        if loaders:
            exempt.add(f)
    return exempt


def r2_metal(files, sources, exempt=frozenset()):
    findings = []
    for f in files:
        if f.endswith(".metal") and f not in exempt:
            findings.append(f"{f}: .metal file is never compiled by "
                            "swift build; embed the MSL source "
                            "(Stereo3DKernelSource pattern)")
    kernels = set()
    for f, text in sources.items():
        if f.endswith(".swift"):
            kernels |= set(re.findall(r"kernel void (\w+)", text))
    for f, text in sources.items():
        if not f.endswith(".swift"):
            continue
        for name in MAKE_FN_RE.findall(text):
            if name not in kernels:
                findings.append(f"{f}: makeFunction(name: \"{name}\") has no "
                                "embedded `kernel void {name}` in any "
                                "compiled Swift file")
    return sorted(findings)


def r3_lua(sources, script_root_files):
    findings = []
    for f, text in sources.items():
        if not f.endswith(".swift"):
            continue
        for name in LUA_RE.findall(text):
            base = name.split("/")[-1]
            if base not in script_root_files:
                findings.append(f"{f}: references {name} but it is not in "
                                f"{LUA_SCRIPT_ROOT} (build.sh bundles only "
                                "that directory)")
    return sorted(findings)


# Data/script payloads loaded through a gated interpreter (node, mpv) or
# bundled wholesale into app Resources: presence is covered by that root plus
# the bundle copy / gor-build-manifest.json, not by the dylib-closure gate.
DATA_EXTS = (".lua", ".mjs", ".js", ".json", ".txt", ".woff2", ".dat")


def r4_vendor_gate(sources, build_sh):
    m = ROOTS_RE.search(build_sh)
    roots = set(re.findall(r"'([^']+)'", m.group(1))) if m else set()
    covered, pending, findings = [], [], []
    for f, text in sources.items():
        if not f.endswith(".swift"):
            continue
        for lit in VENDOR_PATH_RE.findall(text):
            if lit in roots or lit.endswith(DATA_EXTS):
                covered.append(lit)
            elif lit in PENDING_VENDOR:
                pending.append(lit)
            else:
                findings.append(f"{f}: vendorPath(\"{lit}\") is not in "
                                "build.sh vendor-gate ROOTS and has no "
                                "documented PENDING entry")
    stale = [p for p in PENDING_VENDOR if p in roots]
    for p in stale:
        findings.append(f"PENDING_VENDOR entry {p} is now covered by ROOTS; "
                        "remove it from the pending list")
    return sorted(findings), sorted(set(covered)), sorted(set(pending))


def r5_python_copies(build_sh, files):
    findings = []
    for rel in CP_RES_RE.findall(build_sh):
        if rel not in files and rel.split("/")[-1] not in files:
            findings.append(f"build.sh copies {rel} into the bundle but it "
                            "is not tracked")
    for name in LINUX_ONLY_TOOLS:
        if name in build_sh:
            findings.append(f"build.sh references Linux-only tool {name}; "
                            "receive-side tools must not ship to the Mac")
    return sorted(findings)


def r6_kit_manifest(manifest, threedkit):
    findings = []
    packages = set((manifest or {}).get("packages", {}))
    m = re.search(r"static let vda = \[([^\]]*)\]", threedkit or "")
    required = set(re.findall(r'"([^"]+\.mlpackage)"', m.group(1))) if m \
        else set()
    for r in sorted(required - packages):
        findings.append(f"kit_manifest.json lacks ThreeDKit-required {r}")
    for aspect in ("518x294", "518x518"):
        for prec in ("fp16", "fp32"):
            want = f"moge2_vits_{aspect}_{prec}.mlpackage"
            if want not in packages:
                findings.append(f"kit_manifest.json lacks {want}")
    for name, meta in (manifest or {}).get("packages", {}).items():
        sha = meta.get("content_sha256", "")
        if not re.fullmatch(r"[0-9a-f]{64}", sha):
            findings.append(f"{name}: bad content_sha256")
        if not isinstance(meta.get("size_bytes"), int) \
                or meta["size_bytes"] <= 0:
            findings.append(f"{name}: bad size_bytes")
    return sorted(findings)


def audit(root):
    root = Path(root)
    files = tracked_files(root)
    build_sh = read(root, "build.sh") or ""
    package_swift = read(root, "Package.swift") or ""
    sources = {f: read(root, f) for f in files
               if f.endswith(".swift") and f.startswith("Sources/")}
    script_root_files = {p.split("/")[-1] for p in files
                         if p.startswith(LUA_SCRIPT_ROOT + "/")
                         and p.endswith(".lua")}
    manifest = json.loads(read(root, "tools/depth_analysis/kit/"
                               "kit_manifest.json") or "null")
    _b3d = read(root, "Sources/gor/gor/ThreeD.swift")
    if _b3d is None and (Path(root) / "Tests/Structure/threed_split.py").exists():  # arch-199s: ThreeD is five station files
        import importlib.util as _iu
        _sp = _iu.spec_from_file_location("threed_split", Path(root) / "Tests/Structure/threed_split.py")
        _tm = _iu.module_from_spec(_sp); _sp.loader.exec_module(_tm)
        _b3d = _tm.text(root)
    _b3d = _b3d or ""
    threedkit = _b3d[_b3d.index('// BEGIN relocated ThreeDKit.swift '):_b3d.index('// END relocated ThreeDKit.swift\n')] if _b3d else None
    r4, r4_cov, r4_pend = r4_vendor_gate(sources, build_sh)
    r2_texts = {f: read(root, f) for f in files
                if f.endswith("Package.swift")
                or (f.endswith(".swift") and "/Tests/" in "/" + f)}
    r2_exempt = r2_fixture_exempt(files, r2_texts)
    for f in sorted(r2_exempt):
        print(f"INFO R2 test fixture, not a product shader: {f}",
              file=sys.stderr)
    checks = {
        "R1 swift orphans": r1_swift_orphans(files, package_swift),
        "R2 metal embed": r2_metal(files, sources, r2_exempt),
        "R3 lua": r3_lua(sources, script_root_files),
        "R4 vendor gate": r4,
        "R5 python copies": r5_python_copies(build_sh, files),
        "R6 kit manifest": r6_kit_manifest(manifest, threedkit),
    }
    return checks, r4_cov, r4_pend


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    checks, covered, pending = audit(args.root)
    worst = 0
    for name, findings in checks.items():
        if findings:
            worst = 1
            print(f"[FAIL] {name}")
            for f in findings:
                print(f"    {f}")
        else:
            print(f"[ ok ] {name}")
    if covered:
        print(f"vendor-gated: {', '.join(covered)}")
    for p in pending:
        print(f"PENDING (reported to delivery): {p}: {PENDING_VENDOR[p]}")
    if args.json:
        print(json.dumps({"checks": {k: v for k, v in checks.items()},
                          "pending": pending}))
    print("BUILD-INCLUSION " + ("FAIL" if worst else "PASS"))
    return worst


if __name__ == "__main__":
    sys.exit(main())
