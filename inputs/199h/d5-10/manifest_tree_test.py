#!/usr/bin/env python3
"""Delivery manifest == committed tree. Every architecture/delivery.tsv row is compared with the sha256 of the blob COMMITTED at HEAD
(git show, so empty files count as present) and with the working file; any difference, or an uncommitted change to a listed file, fails.
This is the byte check ./build.sh --update runs on the installed source: a commit that edits a listed file without regenerating
delivery.tsv (tools/architecture.py --emit) breaks the owner's update. Run it before every push; never push a commit it fails on."""
import hashlib, pathlib, subprocess, sys
HEAD_ONLY = "--head-only" in sys.argv   # run.py wiring: tolerate uncommitted edits, still fail a committed edit that lacks its emitted row
root = pathlib.Path(__file__).resolve().parents[2]
top = pathlib.Path(subprocess.check_output(["git", "-C", str(root), "rev-parse", "--show-toplevel"]).decode().strip())
prefix = root.relative_to(top).as_posix()
rows = [l.split("\t") for l in (root / "architecture/delivery.tsv").read_text().splitlines()[1:] if l.strip()]
def committed(path):
    p = subprocess.run(["git", "-C", str(top), "show", "HEAD:%s/%s" % (prefix, path)], capture_output=True)
    return p.stdout if p.returncode == 0 else None
bad = []
for r in rows:
    blob, work = committed(r[0]), (root / r[0]).read_bytes() if (root / r[0]).exists() else None
    if blob is None: bad.append((r[0], "not committed")); continue
    if hashlib.sha256(blob).hexdigest() != r[1]: bad.append((r[0], "manifest!=committed", r[1][:8], hashlib.sha256(blob).hexdigest()[:8]))
    elif not HEAD_ONLY and work != blob: bad.append((r[0], "worktree!=committed"))
# An added file without a row is invisible to the update integrity check: every tracked file of the deployed trees must be listed.
listed = {r[0] for r in rows}
tracked = [f for f in subprocess.check_output(["git", "-C", str(root), "ls-files", "Sources", "tools", "Tests", "Resources", "build.sh", "Package.swift"]).decode().split("\n")
           if f and "__pycache__" not in f]
unlisted = [f for f in tracked if f not in listed]
print("tracked files without a delivery row:", unlisted)
bad += [(f, "no delivery row") for f in unlisted]
pyc = subprocess.check_output(["git", "-C", str(root), "ls-files", "*.pyc"]).decode().split()
print("PROPOSAL ONLY (not changed): %d committed .pyc blobs sit outside the integrity envelope; untracking them is the owner/architect's call" % len(pyc))
# Wiring pins: the update path (before gor_install_tree) and the Ubuntu CI both run the gate; the integrity-only check stays first.
bsh = (root / "build.sh").read_text()
wf = pathlib.Path(top / ".github/workflows/gor-architecture.yml")
i_int, i_gate, i_inst = bsh.find("--integrity-only; then"), bsh.find('manifest_tree_test.py" >/dev/null'), bsh.find('gor_install_tree "$src_root" "update"')
if not (0 < i_int < i_gate < i_inst): bad.append(("build.sh", "update path order: integrity-only, manifest gate, install"))
if "--check-delivery" not in bsh: bad.append(("build.sh", "no --check-delivery"))
if wf.exists() and "build.sh --check-delivery" not in wf.read_text(): bad.append((".github/workflows/gor-architecture.yml", "does not run --check-delivery"))
print("wiring: update-path gate and CI step present:", not [b for b in bad if b[0] in ("build.sh", ".github/workflows/gor-architecture.yml")])
print("delivery rows:", len(rows), "mismatches:", bad)
# mutant: a manifest row with one wrong hex digit must be caught by the same comparison
r0 = rows[0]; wrong = ("0" if r0[1][0] != "0" else "1") + r0[1][1:]
mut_caught = hashlib.sha256(committed(r0[0]) or b"").hexdigest() != wrong
print("mutant wrong-hash row caught:", mut_caught)
mut2 = [f for f in tracked + ["Tests/Architecture/new-unlisted.sh"] if f not in listed]
mut_caught = mut_caught and mut2 == unlisted + ["Tests/Architecture/new-unlisted.sh"]
print("mutant added file without a row caught:", mut_caught)
ok = not bad and mut_caught
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
