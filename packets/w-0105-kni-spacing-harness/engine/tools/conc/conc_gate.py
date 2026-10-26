"""Per-diff gate: apply one writer diff onto a pristine base tree, compile, test.

The gate never touches the intake tree itself. It copies --engine-root into a
fresh work directory (excluding build artifacts and VCS data), applies the diff
there, runs the check command and the test command, and writes a receipt. The
receipt is the only verdict; a diff without a PASS receipt is NOT RUN, whatever
its author reports.

  conc_gate.py --engine-root DIR --diff FILE --work-dir DIR
               [--base-sha SHA] [--check-cmd CMD] [--test-cmd CMD]
               [--receipt FILE] [--keep-work]

Defaults: --check-cmd "cargo check --workspace", --test-cmd "cargo test --workspace".
Both run with the work copy as cwd, shell-split, unmodified. Pass explicit
commands to gate a single crate or a non-Rust tree.

Base verification: when --engine-root is a git work tree and --base-sha is
given, HEAD must equal it; when it is not a git work tree the sha is recorded
as declared (the intake ledger is the book of record for what the diff was
produced against). Diff application uses git apply when available, else patch
-p1; both are content tools, neither mutates any repository state.

Receipt schema kni-conc-gate/1, written to --receipt (default
<work-dir>/gate-receipt.json). Exit 0 on PASS, 1 on FAIL, 2 on usage error.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

SCHEMA = "kni-conc-gate/1"
DEFAULT_CHECK_CMD = "cargo check --workspace"
DEFAULT_TEST_CMD = "cargo test --workspace"
IGNORE = shutil.ignore_patterns("target", ".git", "__pycache__", ".DS_Store")


def die(msg, code=2):
    sys.exit("conc_gate: " + msg)
    # unreachable; sys.exit raises


def run(cmd, cwd):
    proc = subprocess.run(cmd, cwd=cwd, shell=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return {"cmd": cmd, "exit": proc.returncode,
            "output_tail": proc.stdout.decode("utf-8", errors="replace")[-4000:]}


def head_of(root):
    try:
        proc = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    out = proc.stdout.decode().strip()
    return out if proc.returncode == 0 and out else None


def apply_diff(work, diff_path):
    for cmd in (["git", "apply", "--whitespace=nowarn", diff_path],
                ["patch", "-p1", "-d", work, "-i", os.path.abspath(diff_path)]):
        try:
            proc = subprocess.run(cmd, cwd=work if cmd[0] == "git" else None,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        except OSError:
            continue  # tool not installed; try the next one
        if proc.returncode == 0:
            return cmd[0]
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(prog="conc_gate.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine-root", required=True, help="pristine base tree")
    ap.add_argument("--diff", required=True, help="writer diff to gate")
    ap.add_argument("--work-dir", required=True, help="scratch dir for the gated copy (must not exist or be empty)")
    ap.add_argument("--base-sha", help="base tree sha the diff claims; verified against git HEAD when possible")
    ap.add_argument("--check-cmd", default=DEFAULT_CHECK_CMD)
    ap.add_argument("--test-cmd", default=DEFAULT_TEST_CMD)
    ap.add_argument("--receipt", help="receipt path (default <work-dir>/gate-receipt.json)")
    ap.add_argument("--keep-work", action="store_true", help="keep the work copy on FAIL too")
    args = ap.parse_args(argv)

    if not os.path.isdir(args.engine_root):
        die(f"engine root {args.engine_root} is not a directory")
    try:
        with open(args.diff, "rb") as fh:
            blob = fh.read()
    except OSError as exc:
        die(f"cannot read diff: {exc}")
    diff_sha = hashlib.sha256(blob).hexdigest()

    base_sha = args.base_sha or ""
    base_verified = "declared"
    head = head_of(args.engine_root)
    if base_sha and head is not None:
        if head != base_sha:
            die(f"engine root HEAD {head} != declared base {base_sha}")
        base_verified = "git-head"
    elif head is None and base_sha:
        base_verified = "declared"

    if os.path.exists(args.work_dir) and os.listdir(args.work_dir):
        die(f"work dir {args.work_dir} is not empty")
    shutil.copytree(args.engine_root, args.work_dir, ignore=IGNORE, dirs_exist_ok=True)

    receipt = {
        "schema": SCHEMA,
        "diff_sha256": diff_sha,
        "base_sha": base_sha,
        "base_verified": base_verified,
        "check_cmd": args.check_cmd,
        "test_cmd": args.test_cmd,
    }

    applier = apply_diff(args.work_dir, os.path.abspath(args.diff))
    if applier is None:
        receipt.update(outcome="FAIL", stage="apply",
                       detail="neither git apply nor patch -p1 accepted the diff")
    else:
        receipt["apply_tool"] = applier
        check = run(args.check_cmd, args.work_dir)
        receipt["check"] = {"cmd": check["cmd"], "exit": check["exit"]}
        if check["exit"] != 0:
            receipt.update(outcome="FAIL", stage="check", detail=check["output_tail"])
        else:
            test = run(args.test_cmd, args.work_dir)
            receipt["test"] = {"cmd": test["cmd"], "exit": test["exit"]}
            if test["exit"] != 0:
                receipt.update(outcome="FAIL", stage="test", detail=test["output_tail"])
            else:
                receipt["outcome"] = "PASS"

    receipt_path = args.receipt or os.path.join(args.work_dir, "gate-receipt.json")
    os.makedirs(os.path.dirname(os.path.abspath(receipt_path)), exist_ok=True)
    with open(receipt_path, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(json.dumps(receipt, indent=2, sort_keys=True))

    if receipt["outcome"] != "PASS" and not args.keep_work:
        shutil.rmtree(args.work_dir, ignore_errors=True)
    sys.exit(0 if receipt["outcome"] == "PASS" else 1)


if __name__ == "__main__":
    main()
