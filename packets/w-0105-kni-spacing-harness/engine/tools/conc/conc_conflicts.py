"""Module-map conflict check: which writer's diff touches which file.

Reads the module map (see module-map.json) and one or more diffs -- either the
queued diffs of a conc_queue directory or diff files passed directly -- and
reports three classes of finding:

  violation : a writer touches a path outside its own map entry and not shared
  conflict  : two different writers' pending diffs touch the same non-shared path
  shared    : a touch of a path declared shared (architect merges these by hand)

Map format (schema kni-conc-module-map/1):
  {
    "schema": "kni-conc-module-map/1",
    "root_prefix": "kni-kit/out8-runkit-v2/engine/",
    "shared": ["pipeline/src/main.rs"],
    "writers": {
      "W7": {"paths": ["metrics/src/spacing_oohh.rs"], "globs": [], "notes": "..."}
    }
  }

Path matching: diff paths are normalized (a/ b/ prefixes stripped), then
--root-prefix (or the map's own root_prefix, CLI wins) is stripped when present,
then compared against the map: exact match against paths, fnmatch against globs.
A writer whose entry has neither paths nor globs is "unmapped": every touch is
reported as an unmapped finding (severity between shared and violation) so the
architect fills the map instead of silently queueing unowned work.

  conc_conflicts.py --module-map FILE (--queue DIR | --diff W=FILE [--diff W=FILE ...])
                    [--root-prefix PREFIX] [--json]

Exit codes: 0 clean (shared/unmapped findings may still be reported),
1 violations or conflicts found, 2 usage/input error.
"""
import argparse
import fnmatch
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diffpaths

SCHEMA = "kni-conc-module-map/1"


def die(msg):
    sys.exit("conc_conflicts: " + msg)


def load_map(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        die(f"cannot load module map {path}: {exc}")
    if m.get("schema") != SCHEMA:
        die(f"module map schema {m.get('schema')!r}, want {SCHEMA!r}")
    if not isinstance(m.get("writers"), dict):
        die("module map has no writers object")
    return m


def strip_prefix(path, prefix):
    if prefix and path.startswith(prefix):
        return path[len(prefix):]
    return path


def collect_diffs(args):
    """Return {writer: [paths]} from the queue or from --diff W=FILE pairs."""
    out = {}
    if args.queue:
        qdir = args.queue
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import conc_queue
        state = conc_queue.current_state(conc_queue.read_ledger(qdir))
        for seq in sorted(state):
            rec = state[seq]
            if rec["state"] != "queued":
                continue
            ev = rec["intake"]
            out.setdefault(ev["writer"], []).extend(ev["files"])
        return out
    for pair in args.diff or []:
        if "=" not in pair:
            die(f"--diff value {pair!r} must be WRITER=FILE")
        writer, path = pair.split("=", 1)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                files = diffpaths.extract_touched_files(fh.read())
        except (OSError, ValueError) as exc:
            die(f"{pair!r}: {exc}")
        out.setdefault(writer, []).extend(files)
    if not out:
        die("no diffs to check: pass --queue or at least one --diff")
    return out


def check(module_map, diffs, root_prefix):
    shared = list(module_map.get("shared", []))
    writers = module_map["writers"]
    violations, conflicts, shared_touches, unmapped = [], [], [], []
    claims = {}  # path -> first writer claiming it

    for writer in sorted(diffs):
        entry = writers.get(writer)
        if entry is None:
            violations.append({"writer": writer, "path": None,
                               "reason": "writer has no module-map entry"})
            continue
        paths = entry.get("paths", [])
        globs = entry.get("globs", [])
        owned = bool(paths or globs)
        for raw in diffs[writer]:
            p = strip_prefix(raw, root_prefix)
            if p in shared:
                shared_touches.append({"writer": writer, "path": p})
                continue
            mine = p in paths or any(fnmatch.fnmatchcase(p, g) for g in globs)
            if not mine:
                finding = {"writer": writer, "path": p}
                if owned:
                    finding["reason"] = "path outside writer's module-map entry"
                    violations.append(finding)
                else:
                    finding["reason"] = "writer is unmapped; assign paths in the module map"
                    unmapped.append(finding)
            other = claims.get(p)
            if other is not None and other != writer:
                conflicts.append({"path": p, "writers": sorted({other, writer})})
            else:
                claims[p] = writer
    # de-duplicate conflicts (same pair can collide on several paths)
    seen, uniq = set(), []
    for c in conflicts:
        key = (c["path"], tuple(c["writers"]))
        if key not in seen:
            seen.add(key)
            uniq.append(c)
    return {
        "ok": not violations and not uniq,
        "violations": violations,
        "conflicts": uniq,
        "shared_touches": shared_touches,
        "unmapped": unmapped,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(prog="conc_conflicts.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--module-map", required=True)
    ap.add_argument("--queue", help="conc_queue directory; checks its queued diffs")
    ap.add_argument("--diff", action="append", help="WRITER=FILE diff to check; repeatable")
    ap.add_argument("--root-prefix", help="prefix stripped from diff paths before matching "
                                          "(overrides the map's root_prefix)")
    ap.add_argument("--json", action="store_true", help="machine-readable report")
    args = ap.parse_args(argv)
    if bool(args.queue) == bool(args.diff):
        die("pass exactly one of --queue or --diff")

    module_map = load_map(args.module_map)
    prefix = args.root_prefix if args.root_prefix is not None else module_map.get("root_prefix", "")
    report = check(module_map, collect_diffs(args), prefix)

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        for v in report["violations"]:
            print(f"VIOLATION\t{v['writer']}\t{v.get('path') or '-'}\t{v['reason']}")
        for c in report["conflicts"]:
            print(f"CONFLICT\t{c['path']}\t{' vs '.join(c['writers'])}")
        for u in report["unmapped"]:
            print(f"UNMAPPED\t{u['writer']}\t{u['path']}\t{u['reason']}")
        for s in report["shared_touches"]:
            print(f"SHARED\t{s['writer']}\t{s['path']}")
        if report["ok"]:
            print("OK: no violations, no cross-writer conflicts")
    sys.exit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
