"""Diff intake queue and merge-order ledger for the multi-writer flow.

Trust model: writers deliver diffs through the bridge; the chief architect alone
intakes, gates and merges. This tool is the architect's book of record. It never
applies, merges or rejects a diff by itself: `intake` stores the diff bytes
verbatim and appends an intake event, `resolve` appends the architect's decision,
`order` replays the merged events in queue sequence. The ledger is append-only;
ordering comes from the integer sequence, never from wall-clock time, so a ledger
is reproducible across machines and timezones.

State layout under the queue directory (both created on first intake):
  ledger.jsonl   one JSON object per line, schema kni-conc-ledger/1
  diffs/<seq>-<writer>.diff   the stored diff bytes

  intake : conc_queue.py intake  --queue DIR --writer WID --base-sha SHA --diff FILE [--note TEXT]
  list   : conc_queue.py list    --queue DIR [--state queued|merged|rejected|superseded]
  resolve: conc_queue.py resolve --queue DIR --seq N --outcome merged|rejected|superseded [--reason TEXT]
  order  : conc_queue.py order   --queue DIR [--json]

Exit codes: 0 success, 1 usage/state error (unknown seq, double resolve, unreadable diff).
"""
import argparse
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diffpaths

SCHEMA = "kni-conc-ledger/1"
OUTCOMES = ("merged", "rejected", "superseded")
_WRITER_SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def die(msg):
    sys.exit("conc_queue: " + msg)


def ledger_path(qdir):
    return os.path.join(qdir, "ledger.jsonl")


def read_ledger(qdir):
    path = ledger_path(qdir)
    events = []
    if not os.path.exists(path):
        return events
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError as exc:
                die(f"ledger line {lineno} is not JSON: {exc}")
            if ev.get("schema") != SCHEMA:
                die(f"ledger line {lineno} has schema {ev.get('schema')!r}, want {SCHEMA!r}")
            events.append(ev)
    return events


def append_event(qdir, ev):
    ev = dict(ev, schema=SCHEMA)
    with open(ledger_path(qdir), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, sort_keys=True) + "\n")


def next_seq(events):
    seqs = [ev["seq"] for ev in events if ev.get("event") == "intake"]
    return (max(seqs) + 1) if seqs else 1


def current_state(events):
    """seq -> latest state ('queued' or one of OUTCOMES), plus intake record."""
    state = {}
    for ev in events:
        if ev["event"] == "intake":
            state[ev["seq"]] = {"state": "queued", "intake": ev, "resolution": None}
        elif ev["event"] == "resolve":
            rec = state.get(ev["seq"])
            if rec is not None:
                rec["state"] = ev["outcome"]
                rec["resolution"] = ev
    return state


def cmd_intake(args):
    if not _WRITER_SAFE.match(args.writer):
        die(f"writer id {args.writer!r} must match {_WRITER_SAFE.pattern}")
    try:
        with open(args.diff, "rb") as fh:
            blob = fh.read()
    except OSError as exc:
        die(f"cannot read diff {args.diff}: {exc}")
    try:
        files = diffpaths.extract_touched_files(blob.decode("utf-8", errors="replace"))
    except ValueError as exc:
        die(str(exc))
    os.makedirs(os.path.join(args.queue, "diffs"), exist_ok=True)
    events = read_ledger(args.queue)
    seq = next_seq(events)
    stored = os.path.join("diffs", f"{seq}-{args.writer}.diff")
    with open(os.path.join(args.queue, stored), "wb") as fh:
        fh.write(blob)
    ev = {
        "event": "intake",
        "seq": seq,
        "writer": args.writer,
        "base_sha": args.base_sha,
        "diff_sha256": hashlib.sha256(blob).hexdigest(),
        "diff_path": stored,
        "files": files,
        "note": args.note or "",
    }
    append_event(args.queue, ev)
    print(json.dumps(ev, indent=2, sort_keys=True))


def cmd_list(args):
    state = current_state(read_ledger(args.queue))
    for seq in sorted(state):
        rec = state[seq]
        if args.state and rec["state"] != args.state:
            continue
        ev = rec["intake"]
        print(f"{seq}\t{rec['state']}\t{ev['writer']}\t{ev['base_sha'][:12]}\t{len(ev['files'])} files\t{ev['note']}")


def cmd_resolve(args):
    events = read_ledger(args.queue)
    state = current_state(events)
    rec = state.get(args.seq)
    if rec is None:
        die(f"unknown seq {args.seq}")
    if rec["state"] != "queued":
        die(f"seq {args.seq} already resolved as {rec['state']}; the ledger is append-only")
    ev = {"event": "resolve", "seq": args.seq, "outcome": args.outcome, "reason": args.reason or ""}
    append_event(args.queue, ev)
    print(json.dumps(ev, indent=2, sort_keys=True))


def cmd_order(args):
    state = current_state(read_ledger(args.queue))
    merged = [state[s]["intake"] for s in sorted(state) if state[s]["state"] == "merged"]
    if args.json:
        for ev in merged:
            print(json.dumps({
                "seq": ev["seq"], "writer": ev["writer"],
                "base_sha": ev["base_sha"], "diff_sha256": ev["diff_sha256"],
                "diff_path": ev["diff_path"], "files": ev["files"],
            }, sort_keys=True))
    else:
        for ev in merged:
            print(f"{ev['seq']}\t{ev['writer']}\t{ev['base_sha'][:12]}\t{ev['diff_sha256'][:12]}\t{ev['diff_path']}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="conc_queue.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("intake", help="store a diff and append an intake event")
    p.add_argument("--queue", required=True, help="queue directory (created on first intake)")
    p.add_argument("--writer", required=True, help="writer id, e.g. W15")
    p.add_argument("--base-sha", required=True, help="base tree sha the diff was produced against")
    p.add_argument("--diff", required=True, help="path to the unified diff file")
    p.add_argument("--note", default="", help="free-text note (optional)")
    p.set_defaults(fn=cmd_intake)

    p = sub.add_parser("list", help="list queue entries with their current state")
    p.add_argument("--queue", required=True)
    p.add_argument("--state", choices=["queued"] + list(OUTCOMES), default=None)
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("resolve", help="append the architect's decision for a queued diff")
    p.add_argument("--queue", required=True)
    p.add_argument("--seq", required=True, type=int)
    p.add_argument("--outcome", required=True, choices=OUTCOMES)
    p.add_argument("--reason", default="")
    p.set_defaults(fn=cmd_resolve)

    p = sub.add_parser("order", help="replay merged diffs in queue sequence (merge-order ledger)")
    p.add_argument("--queue", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_order)

    args = ap.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
