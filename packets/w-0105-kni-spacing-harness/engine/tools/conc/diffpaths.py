"""Touched-file extraction from unified diffs. Shared by conc_queue and conc_conflicts.

A path is recorded once per file the diff touches, in first-appearance order.
Deleted files are reported with their pre-delete path; a pure rename reports both
sides so a conflict check sees the old path released and the new path claimed.
Paths are normalized to forward slashes with any leading a/ or b/ prefix stripped;
no other rewriting happens here (see conc_conflicts --root-prefix for tree rooting).
"""
import re

_GIT_HDR = re.compile(r"^diff --git a/(\S+) b/(\S+)\s*$")
_OLD = re.compile(r"^--- (.+?)\s*$")
_NEW = re.compile(r"^\+\+\+ (.+?)\s*$")
_RENAME_FROM = re.compile(r"^rename from (.+?)\s*$")
_RENAME_TO = re.compile(r"^rename to (.+?)\s*$")


def _clean(path):
    path = path.strip()
    if path == "/dev/null":
        return None
    if path.startswith('"') and path.endswith('"') and len(path) > 1:
        path = path[1:-1]
    # unified headers may carry a trailing timestamp after a tab; split it off
    path = path.split("\t")[0].strip()
    for prefix in ("a/", "b/"):
        if path.startswith(prefix):
            path = path[len(prefix):]
    return path.replace("\\", "/")


def extract_touched_files(diff_text):
    """Return the ordered list of paths a unified diff touches.

    Raises ValueError when no file header is found, so an empty or non-diff
    intake is refused instead of being queued as a zero-file no-op.
    """
    files = []
    seen = set()
    pending_old = None  # --- line awaiting its +++ partner

    def add(p):
        if p and p not in seen:
            seen.add(p)
            files.append(p)

    for line in diff_text.splitlines():
        m = _GIT_HDR.match(line)
        if m:
            pending_old = None
            # trust the ---/+++ pair when it follows; the git header is a hint
            continue
        m = _RENAME_FROM.match(line)
        if m:
            add(_clean(m.group(1)))
            continue
        m = _RENAME_TO.match(line)
        if m:
            add(_clean(m.group(1)))
            continue
        m = _OLD.match(line)
        if m:
            pending_old = _clean(m.group(1))
            continue
        m = _NEW.match(line)
        if m:
            new = _clean(m.group(1))
            # new file: --- /dev/null, record the +++ path
            # deleted file: +++ /dev/null, record the --- path
            # modified file: record the +++ path (== --- path modulo a/ b/)
            add(new if new is not None else pending_old)
            pending_old = None
    if not files:
        raise ValueError("no file headers found; not a unified diff or empty diff")
    return files
