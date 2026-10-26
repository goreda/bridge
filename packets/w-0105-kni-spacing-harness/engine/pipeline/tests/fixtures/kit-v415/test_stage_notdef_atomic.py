#!/usr/bin/env python3
"""Staging-atomic delta tests for stage_notdef.py (K3, 2026-10-19).
Scenarios: v3 happy (byte-equal to the golden staged-expected), v3 mid-flow
refusal + retry, v2 happy, v2 mid-flow refusal + retry, OrphanStage exit 3,
NotdefStageExists parity, no-temp-leftovers. stdlib only; runs the stager as
a subprocess and asserts EXIT codes, refusal class, and byte-level state."""
import hashlib, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "notdef-v3")
STAGER = os.environ.get("KNI_STAGE_NOTDEF", os.path.join(HERE, "stage_notdef.py"))

def shabytes(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()

def tree_sha(root):
    h = hashlib.sha256()
    for d, ds, fs in sorted(os.walk(root)):
        ds.sort()
        for f in sorted(fs):
            p = os.path.join(d, f)
            h.update(os.path.relpath(p, root).encode()); h.update(b"\0"); h.update(open(p, "rb").read()); h.update(b"\0")
    return h.hexdigest()

def mk_case(t, v2=False):
    R = os.path.join(t, "run"); S = os.path.join(t, "src")
    shutil.copytree(os.path.join(FIX, "run"), R)
    shutil.copytree(os.path.join(FIX, "producer-input"), S)
    if v2:
        # v2 evidence: style/frame/scale/capture + selected + one witness;
        # tiles are the same pinned w41/w42, capture manifest unchanged.
        cap = open(os.path.join(S, "capture-manifest.tsv")).read()
        pins = {l.split("\t")[2]: l.split("\t")[3] for l in cap.splitlines() if l.startswith("source\t")}
        ev = ("style\tMarq/Regular\nframe\tframe-test\nscale\t2.4377\ncapture\tPLACEHOLDER\n"
              f"selected\tw41.png\t{pins['w41.png']}\n"
              f"witness\t0x42\trepeated-form\tw42.png\t{pins['w42.png']}\t-\n")
        open(os.path.join(S, "evidence.tsv"), "w").write(ev)
    return R, S

def run_stager(R, S):
    return subprocess.run([sys.executable, STAGER, "--run-dir", R, "--notdef-dir", S,
                           "--manifest", os.path.join(R, "manifest.txt")],
                          capture_output=True, text=True)

def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else " :: " + detail))
    return bool(cond)

def corrupt_cap_pin(S):
    p = os.path.join(S, "capture-manifest.tsv")
    lines = open(p).read().splitlines()
    for i, l in enumerate(lines):
        f = l.split("\t")
        if len(f) == 4 and f[0] == "source" and f[2] == "w42.png":
            f[3] = "0" * 64; lines[i] = "\t".join(f)
    open(p, "w").write("\n".join(lines) + "\n")

def restore_cap(S):
    shutil.copyfile(os.path.join(FIX, "producer-input", "capture-manifest.tsv"),
                    os.path.join(S, "capture-manifest.tsv"))

def golden_ok(R):
    exp = os.path.join(FIX, "staged-expected")
    for f in ("capture-manifest.tsv", "evidence.tsv", "w41.png", "w42.png"):
        if shabytes(os.path.join(R, "notdef", f)) != shabytes(os.path.join(exp, f)): return f
        if shabytes(os.path.join(R, "manifest.txt")) != shabytes(os.path.join(exp, "manifest.txt")): return "manifest.txt"
    return None

def main():
    ok = True
    # T1 v3 happy: byte-equal to the golden staged-expected, no staging left
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t)
        r = run_stager(R, S)
        ok &= check("T1 v3 happy exit 0", r.returncode == 0, r.stdout)
        ok &= check("T1 stdout winner group", "winner group 0x41,0x42" in r.stdout, r.stdout.strip())
        bad = golden_ok(R)
        ok &= check("T1 byte-equal to staged-expected", bad is None, f"first mismatch: {bad}")
        ok &= check("T1 no staging left", not os.path.exists(os.path.join(R, ".notdef.staging")))
        ok &= check("T1 no manifest temp left", not any(f.startswith("manifest.txt.staging-") for f in os.listdir(R)))
    # T2 v3 mid-flow refusal + retry
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t)
        man0 = shabytes(os.path.join(R, "manifest.txt"))
        corrupt_cap_pin(S)
        r = run_stager(R, S)
        ok &= check("T2 v3 refusal exit 3", r.returncode == 3, str(r.returncode))
        ok &= check("T2 refusal class NotdefTileShaMismatch", "NotdefTileShaMismatch" in r.stdout, r.stdout.strip())
        ok &= check("T2 R has no notdef/", not os.path.exists(os.path.join(R, "notdef")))
        ok &= check("T2 R has no staging", not os.path.exists(os.path.join(R, ".notdef.staging")))
        ok &= check("T2 manifest byte-identical", shabytes(os.path.join(R, "manifest.txt")) == man0)
        restore_cap(S)
        r2 = run_stager(R, S)
        ok &= check("T2 retry exit 0", r2.returncode == 0, r2.stdout)
        bad = golden_ok(R)
        ok &= check("T2 retry byte-equal to golden", bad is None, f"first mismatch: {bad}")
    # T3 v2 happy
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t, v2=True)
        r = run_stager(R, S)
        ok &= check("T3 v2 happy exit 0", r.returncode == 0, r.stdout)
        man = open(os.path.join(R, "manifest.txt")).read()
        ok &= check("T3 manifest rows", "capture_manifest notdef/capture-manifest.tsv " in man and "\nnotdef evidence notdef/evidence.tsv " in man)
        ev = open(os.path.join(R, "notdef", "evidence.tsv")).read()
        ok &= check("T3 capture row rewritten", "capture\tPLACEHOLDER" not in ev and ev.count("capture\t") == 1)
        ok &= check("T3 no staging left", not os.path.exists(os.path.join(R, ".notdef.staging")))
    # T4 v2 mid-flow refusal + retry (chief item)
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t, v2=True)
        man0 = shabytes(os.path.join(R, "manifest.txt"))
        corrupt_cap_pin(S)
        r = run_stager(R, S)
        ok &= check("T4 v2 refusal exit 3", r.returncode == 3, str(r.returncode))
        ok &= check("T4 refusal class NotdefTileShaMismatch", "NotdefTileShaMismatch" in r.stdout, r.stdout.strip())
        ok &= check("T4 R has no notdef/", not os.path.exists(os.path.join(R, "notdef")))
        ok &= check("T4 R has no staging", not os.path.exists(os.path.join(R, ".notdef.staging")))
        ok &= check("T4 manifest byte-identical", shabytes(os.path.join(R, "manifest.txt")) == man0)
        restore_cap(S)
        r2 = run_stager(R, S)
        ok &= check("T4 retry exit 0", r2.returncode == 0, r2.stdout)
        ok &= check("T4 retry staged v2 evidence", os.path.isfile(os.path.join(R, "notdef", "evidence.tsv")))
    # T5 OrphanStage exit 3: leftover staging refuses, retry after removal works
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t)
        os.makedirs(os.path.join(R, ".notdef.staging"))
        open(os.path.join(R, ".notdef.staging", "marker"), "w").write("killed-run leftover")
        man0 = shabytes(os.path.join(R, "manifest.txt"))
        r = run_stager(R, S)
        ok &= check("T5 orphan exit 3", r.returncode == 3, str(r.returncode))
        ok &= check("T5 refusal class NotdefOrphanStage", "NotdefOrphanStage" in r.stdout, r.stdout.strip())
        ok &= check("T5 marker untouched", open(os.path.join(R, ".notdef.staging", "marker")).read() == "killed-run leftover")
        ok &= check("T5 R has no notdef/", not os.path.exists(os.path.join(R, "notdef")))
        ok &= check("T5 manifest byte-identical", shabytes(os.path.join(R, "manifest.txt")) == man0)
        shutil.rmtree(os.path.join(R, ".notdef.staging"))
        r2 = run_stager(R, S)
        ok &= check("T5 retry after removal exit 0", r2.returncode == 0, r2.stdout)
    # T6 NotdefStageExists parity: refuses BEFORE any staging is created
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t)
        os.makedirs(os.path.join(R, "notdef"))
        open(os.path.join(R, "notdef", "marker"), "w").write("existing")
        man0 = shabytes(os.path.join(R, "manifest.txt"))
        r = run_stager(R, S)
        ok &= check("T6 existing notdef exit 3", r.returncode == 3, str(r.returncode))
        ok &= check("T6 refusal class NotdefStageExists", "NotdefStageExists" in r.stdout, r.stdout.strip())
        ok &= check("T6 marker untouched", open(os.path.join(R, "notdef", "marker")).read() == "existing")
        ok &= check("T6 no staging created", not os.path.exists(os.path.join(R, ".notdef.staging")))
        ok &= check("T6 manifest byte-identical", shabytes(os.path.join(R, "manifest.txt")) == man0)
    # T7: failed atomic manifest replacement rolls back the committed directory.
    with tempfile.TemporaryDirectory() as t:
        R, S = mk_case(t)
        before = tree_sha(R)
        driver = "import os,runpy,sys; os.replace=lambda *a: (_ for _ in ()).throw(OSError('injected manifest failure')); sys.argv=sys.argv[1:]; runpy.run_path(sys.argv[0],run_name='__main__')"
        r = subprocess.run([sys.executable, "-c", driver, STAGER, "--run-dir", R,
                            "--notdef-dir", S, "--manifest", os.path.join(R, "manifest.txt")],
                           capture_output=True, text=True)
        ok &= check("T7 injected replace failure", r.returncode != 0 and "injected manifest failure" in r.stderr, r.stderr)
        ok &= check("T7 entire run tree byte-identical after rollback", tree_sha(R) == before)
        ok &= check("T7 no notdef or staging remains", not any(n.startswith(".notdef") or n == "notdef" for n in os.listdir(R)))
    print("RESULT: " + ("ALL PASS" if ok else "FAILURES PRESENT"))
    sys.exit(0 if ok else 1)

main()
