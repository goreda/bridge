"""Schema-independent completeness audit.

The audit knows nothing about the sweep's record format. The caller supplies:
  expected   the list of expected keys (one per font);
  key_regex  how a file path maps to a key (named group "key", else group 1);
  result / refusal patterns that say which files are records and of which kind.
It then counts, per expected key, the record files found, and lists what is missing,
doubled, contradictory, unclassified or unexpected. It reports counts and lists only.
"""
import filecmp
import hashlib
import json
import os
import re
import signal
import threading
from dataclasses import asdict, dataclass, field
from typing import List, Optional

RECEIPT_VERSION = "sweepaudit-receipt-v1"
MAX_READ_DEFAULT = 1 << 20
# CONVENTION (no theory behind the number): wall-clock limit for one pattern match. A match that takes longer
# is reported as kind=pattern_timeout and the run goes on; nothing is truncated or sampled.
PATTERN_TIMEOUT_DEFAULT = 2.0
_NUMBER = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)")


class PatternTimeout(Exception):
    pass


_TIMEOUT = [PATTERN_TIMEOUT_DEFAULT]


def _on_alarm(signum, frame):
    raise PatternTimeout()


def _search(rx, text):
    """rx.search with a wall-clock limit (setitimer). Raises PatternTimeout."""
    old = signal.signal(signal.SIGALRM, _on_alarm)
    signal.setitimer(signal.ITIMER_REAL, _TIMEOUT[0])
    try:
        return rx.search(text)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


def _finite_number(v):
    if not _NUMBER.fullmatch(v):
        return False
    try:
        x = float(v)
    except (ValueError, OverflowError):
        return False
    return x - x == 0


@dataclass
class Config:
    key_regex: Optional[str] = None
    key_from_expected: bool = False                               # key = longest expected key that prefixes the path, followed by . or - (never /)
    result_patterns: List[str] = field(default_factory=list)     # "content:RE" or "path:RE"; bare RE means content
    refusal_patterns: List[str] = field(default_factory=list)
    refusal_type_regex: Optional[str] = None                      # group "type" or group 1, applied to a refusal record's content
    exclude_regex: Optional[str] = None                           # relative paths to leave out (for example receipts of this audit)
    max_read: int = MAX_READ_DEFAULT
    expected_count: Optional[int] = None
    sweep_level_regex: Optional[str] = None                       # files that belong to the sweep, not to one key (listed, not counted as unkeyed)
    empty_ok_regex: Optional[str] = None                          # files that are empty by design (for example completion markers)
    required_templates: List[str] = field(default_factory=list)   # per key with a record file; "{key}" is replaced, paths are relative to the root
    required_exceptions: dict = field(default_factory=dict)       # template -> keys for which that file is not expected (listed in the receipt)
    pattern_timeout_seconds: float = PATTERN_TIMEOUT_DEFAULT      # wall-clock limit per pattern match, must be > 0
    allowed_templates: List[str] = field(default_factory=list)    # files that may exist next to the required ones ("{key}" form); with key_from_expected
                                                                 # every keyed file must match a required or allowed template, else it is listed as unexpected
    pair_checks: List[dict] = field(default_factory=list)         # byte equality of two copies, see README
    tsv_checks: List[dict] = field(default_factory=list)          # row counts of tab separated files, see README


class RootError(ValueError):
    """The audit root is missing or cannot be listed."""


def _ch(c):
    o = ord(c)
    return "\\x%02x" % o if o < 256 else "\\u%04x" % o if o < 65536 else "\\U%08x" % o


def _esc(text):
    """Control characters, unpaired surrogates (undecodable file names) and other non-printable characters
    are written as escapes, so one receipt line is always one line."""
    return "".join(c if (c.isprintable() or c == " ") else _ch(c) for c in text)


def config_from_dict(c, **override):
    """Config from the JSON config object; override values that are not None win."""
    keys = ("key_regex", "key_from_expected", "sweep_level_regex", "empty_ok_regex", "required_templates", "required_exceptions",
            "allowed_templates", "tsv_checks", "pair_checks", "result_patterns", "refusal_patterns", "refusal_type_regex",
            "exclude_regex", "max_read", "expected_count", "pattern_timeout_seconds")
    unknown = sorted(set(c) - set(keys))
    if unknown:
        raise ValueError("unknown config keys: %s" % ", ".join(unknown))
    d = {k: c[k] for k in keys if k in c}
    d.update(override)
    return Config(**d)


def _no_duplicate_keys(pairs):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            raise ValueError("DUPLICATE_JSON_KEY:" + k)
        seen.add(k)
    return dict(pairs)


def _bad_constant(value):
    raise ValueError("NONFINITE_JSON:" + value)


def load_json_strict(data):
    """The one JSON loader for configs and schemas: bytes or text, a leading UTF-8 BOM is removed, duplicate object
    keys and NaN/Infinity are refused."""
    if isinstance(data, (bytes, bytearray)):
        data = bytes(data).decode("utf-8-sig")
    return json.loads(data, object_pairs_hook=_no_duplicate_keys, parse_constant=_bad_constant)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _split(p):
    if p.startswith("path:"):
        return "path", re.compile(p[5:])
    if p.startswith("content:"):
        return "content", re.compile(p[8:])
    return "content", re.compile(p)


def _key(rx, rel):
    """Key of a path from the key pattern (time-limited like every other config pattern; raises PatternTimeout)."""
    m = _search(rx, rel)
    if not m:
        return None
    gd = m.groupdict()
    if "key" in gd and gd["key"] is not None:
        return gd["key"]
    if m.re.groups >= 1 and m.group(1) is not None:
        return m.group(1)
    return None


def read_expected(text):
    if text.startswith("\ufeff"):
        text = text[1:]
    keys, seen, dup = [], set(), []
    for line in text.splitlines():
        k = line.strip()
        if not k or k.startswith("#"):
            continue
        if k in seen:
            dup.append(k)
        seen.add(k)
        keys.append(k)
    return keys, dup


def _pair_checks(files, checks, timeouts):
    """Byte equality of paired files. a_regex has named groups; b_template is filled from them (for example
    "{key}-out-b/{rest}"). Each pair is compared byte for byte (filecmp, shallow off) and listed with both
    sha256 values. Descriptive: counts and lists only. Returns (summary lines, differing, b_missing, b_only)."""
    out, differ, b_missing, b_only = [], [], [], []
    present = {rel: full for rel, full in files if not os.path.islink(full)}
    for chk in checks:
        rx = re.compile(chk["a_regex"])
        used_b, pairs, equal = set(), 0, 0
        for rel in sorted(present):
            try:
                m = _search(rx, rel)
            except PatternTimeout:
                timeouts.append("%s pair_a_regex" % rel)
                continue
            if not m:
                continue
            pairs += 1
            brel = chk["b_template"].format(**m.groupdict())
            used_b.add(brel)
            if brel not in present:
                b_missing.append("%s %s" % (rel, brel))
                out.append("pair a=%s b=%s result=b_missing" % (rel, brel))
                continue
            try:
                same = filecmp.cmp(present[rel], present[brel], shallow=False)
                ha, hb = _sha_file(present[rel]), _sha_file(present[brel])
            except OSError as e:
                differ.append("%s %s unreadable" % (rel, brel))
                out.append("pair a=%s b=%s result=unreadable detail=%s" % (rel, brel, e))
                continue
            equal += same
            if not same:
                differ.append("%s %s" % (rel, brel))
            out.append("pair a=%s b=%s result=%s a_sha256=%s b_sha256=%s" % (rel, brel, "equal" if same else "differ", ha, hb))
        b_rx = re.compile(chk["b_regex"]) if chk.get("b_regex") else None
        if b_rx:
            for rel in sorted(present):
                try:
                    hit = _search(b_rx, rel)
                except PatternTimeout:
                    timeouts.append("%s pair_b_regex" % rel)
                    continue
                if hit and rel not in used_b:
                    b_only.append(rel)
                    out.append("pair a=none b=%s result=b_without_a" % rel)
        out.insert(0, "pair_check a_regex=%s pairs=%d equal=%d" % (chk["a_regex"], pairs, equal))
    return out, differ, b_missing, b_only


def _sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def _tsv_checks(root, files, checks, keyof, timeouts):
    """Row counts for tab separated files. Descriptive: a refusal row is a row whose label column holds the
    refusal value (compared case-sensitively); its metric columns should be empty and it should carry a note.
    A metric cell is filled when it is not the empty string; a filled cell must be a finite ASCII decimal number
    ([+-]digits[.digits] or .digits), anything else (spaces only, NaN, text) is counted as metric_invalid.
    Lines starting with # are skipped and counted; blank lines are skipped.
    Returns (lines, total rows, anomalies, skipped # lines). Every anomaly is also an entry in `anomalies`."""
    out, total, anomalies, hash_total = [], 0, [], 0
    for chk in checks:
        rx = re.compile(chk["path_regex"])
        label_c, refusal_v = chk["label_column"], chk["refusal_value"]
        metrics, note_c = chk.get("metric_columns", []), chk.get("note_column")
        for rel, full in files:
            try:
                if not _search(rx, rel) or os.path.islink(full):
                    continue
            except PatternTimeout:
                timeouts.append("%s tsv_path_regex" % rel)
                continue
            try:
                with open(full, "r", encoding="utf-8", errors="replace", newline="") as f:
                    lines = [ln.rstrip("\r\n") for ln in f]
            except OSError as e:
                out.append("tsv path=%s unreadable=%s" % (rel, e))
                anomalies.append("%s unreadable" % rel)
                continue
            hashes = sum(1 for ln in lines if ln.startswith("#"))
            hash_total += hashes
            if hashes:
                anomalies.append("%s hash_lines_skipped=%d" % (rel, hashes))
            rows = [ln for ln in lines if ln.strip() and not ln.startswith("#")]
            if not rows:
                out.append("tsv path=%s rows=0 header=missing hash_lines_skipped=%d" % (rel, hashes))
                anomalies.append("%s header_missing" % rel)
                continue
            head = rows[0].split("\t")
            dup = sorted({c for c in head if head.count(c) > 1})
            if dup:
                out.append("tsv path=%s rows=%d duplicate_header=%s hash_lines_skipped=%d" % (rel, len(rows) - 1, ",".join(dup), hashes))
                anomalies.append("%s duplicate_header %s" % (rel, ",".join(dup)))
                continue
            need = [label_c] + list(metrics) + ([note_c] if note_c else [])
            absent = [c for c in need if c not in head]
            if absent:
                out.append("tsv path=%s rows=%d missing_columns=%s hash_lines_skipped=%d" % (rel, len(rows) - 1, ",".join(absent), hashes))
                anomalies.append("%s missing_columns %s" % (rel, ",".join(absent)))
                continue
            ix = {c: head.index(c) for c in need}
            n = ref = ref_no_note = ref_metric = non_ref_empty = short = long_ = invalid = 0
            notes = {}
            for ln in rows[1:]:
                cells = ln.split("\t")
                if len(cells) < len(head):
                    cells += [""] * (len(head) - len(cells))
                    short += 1
                elif len(cells) > len(head):
                    long_ += 1
                n += 1
                mvals = [cells[ix[c]] for c in metrics]
                invalid += sum(1 for v in mvals if v != "" and not _finite_number(v))
                if cells[ix[label_c]] == refusal_v:
                    ref += 1
                    note = cells[ix[note_c]] if note_c else ""
                    if note_c and not note:
                        ref_no_note += 1
                    elif note:
                        notes[note] = notes.get(note, 0) + 1
                    if any(v != "" for v in mvals):
                        ref_metric += 1
                elif any(v == "" for v in mvals):
                    non_ref_empty += 1
            total += n
            out.append("tsv path=%s key=%s rows=%d refusal_rows=%d refusal_rows_without_note=%d refusal_rows_with_metric=%d non_refusal_rows_with_empty_metric=%d short_rows=%d long_rows=%d metric_invalid=%d hash_lines_skipped=%d notes=%s" % (
                rel, keyof(rel) or "none", n, ref, ref_no_note, ref_metric, non_ref_empty, short, long_, invalid, hashes,
                ",".join("%s:%d" % kv for kv in sorted(notes.items())) or "none"))
            for code, cnt in (("refusal_without_note", ref_no_note), ("refusal_with_metric", ref_metric),
                              ("non_refusal_empty_metric", non_ref_empty), ("short_rows", short), ("long_rows", long_),
                              ("metric_invalid", invalid)):
                if cnt:
                    anomalies.append("%s %s=%d" % (rel, code, cnt))
    return out, total, anomalies, hash_total


def audit(root, expected_text, cfg):
    """Returns (receipt_text, summary_dict). Never raises on bad file content; unreadable files are listed."""
    if not isinstance(cfg.max_read, int) or isinstance(cfg.max_read, bool) or cfg.max_read < 1:
        raise ValueError("max_read must be an integer >= 1")
    if isinstance(cfg.pattern_timeout_seconds, bool) or not isinstance(cfg.pattern_timeout_seconds, (int, float)) or not cfg.pattern_timeout_seconds > 0:
        raise ValueError("pattern_timeout_seconds must be a number > 0")
    if not hasattr(signal, "setitimer") or not hasattr(signal, "SIGALRM"):
        raise ValueError("pattern_timeout_unsupported: this platform has no setitimer, the audit refuses to run patterns without a time limit")
    if threading.current_thread() is not threading.main_thread():
        raise ValueError("pattern_timeout_unsupported: the time limit needs the main thread")
    _TIMEOUT[0] = float(cfg.pattern_timeout_seconds)
    timeouts = []
    expected, expected_dup = read_expected(expected_text)
    exp_set = set(expected)
    if cfg.key_from_expected:
        if not expected:
            raise ValueError("key_from_expected needs a non-empty expected list")
        if not any(t.startswith("{key}") for t in list(cfg.required_templates) + list(cfg.allowed_templates)):
            raise ValueError("key_from_expected needs templates: required_templates or allowed_templates with at least one entry that starts with {key}")
        key_rx = re.compile("^(?P<key>" + "|".join(re.escape(k) for k in sorted(exp_set, key=lambda k: (-len(k), k))) + ")(?=[.-])")
    else:
        if not cfg.key_regex:
            raise ValueError("key_regex or key_from_expected is required")
        key_rx = re.compile(cfg.key_regex)
        if key_rx.groups < 1:
            raise ValueError("key_regex needs a group (named 'key' or the first group)")
    sweep_rx = re.compile(cfg.sweep_level_regex) if cfg.sweep_level_regex else None
    empty_ok = re.compile(cfg.empty_ok_regex) if cfg.empty_ok_regex else None
    res_pats = [_split(p) for p in cfg.result_patterns]
    ref_pats = [_split(p) for p in cfg.refusal_patterns]
    if not res_pats and not ref_pats:
        raise ValueError("at least one result or refusal pattern is required")
    type_rx = re.compile(cfg.refusal_type_regex) if cfg.refusal_type_regex else None
    excl = re.compile(cfg.exclude_regex) if cfg.exclude_regex else None
    if not os.path.isdir(root):
        raise RootError("root is not a directory: %s" % _esc(str(root)))
    try:
        os.listdir(root)
    except OSError as e:
        raise RootError("root cannot be listed: %s" % _esc(str(e)))
    files, dir_errors, dir_links = [], [], []

    def safe(rx, text, rel, what):
        try:
            return _search(rx, text)
        except PatternTimeout:
            timeouts.append("%s %s" % (rel, what))
            return None

    key_cache = {}
    key_timed_out = set()

    def keyof(rel):
        if rel not in key_cache:
            try:
                key_cache[rel] = _key(key_rx, rel)
            except PatternTimeout:
                timeouts.append("%s key_regex" % rel)
                key_timed_out.add(rel)
                key_cache[rel] = None
        return key_cache[rel]

    def _walk_error(e):
        dir_errors.append((os.path.relpath(e.filename, root).replace(os.sep, "/") if e.filename else "?", "unreadable_dir %s" % e.strerror))

    for dp, dn, fn in os.walk(root, followlinks=False, onerror=_walk_error):
        dn.sort()
        for d in dn:
            full = os.path.join(dp, d)
            if os.path.islink(full):
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                if not (excl and safe(excl, rel, rel, "exclude_regex")):
                    dir_links.append((rel, full))
        for n in sorted(fn):
            full = os.path.join(dp, n)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if excl and safe(excl, rel, rel, "exclude_regex"):
                continue
            files.append((rel, full))
    files.sort()
    cfg_sha = hashlib.sha256(json.dumps(asdict(cfg), sort_keys=True, ensure_ascii=True).encode()).hexdigest()
    known = {t[len("{key}"):] for t in list(cfg.required_templates) + list(cfg.allowed_templates) if t.startswith("{key}")}

    L = [RECEIPT_VERSION]
    L.append("config_sha256=%s (canonical JSON of the effective config)" % cfg_sha)
    L.append("config key_regex=%s result_patterns=%d refusal_patterns=%d refusal_type_regex=%s max_read=%d required_templates=%d tsv_checks=%d" % (
        "from_expected_list" if cfg.key_from_expected else cfg.key_regex, len(res_pats), len(ref_pats),
        cfg.refusal_type_regex or "none", cfg.max_read, len(cfg.required_templates), len(cfg.tsv_checks)))
    L.append("expected keys=%d unique=%d duplicate_in_list=%d expected_count_given=%s" % (
        len(expected), len(exp_set), len(expected_dup), cfg.expected_count if cfg.expected_count is not None else "none"))
    L.append("expected_list_sha256=%s" % hashlib.sha256(expected_text.encode()).hexdigest())

    per = {}              # key -> {"records": [(rel, kind, type)], "aux": [rel]}
    unkeyed, empty, unreadable, links, changed, truncated, sweep_level = [], [], [], [], [], [], []
    unexpected_files = []
    unreadable_files = []   # unreadable entries (a directory read error is listed in unreadable but is not an entry)
    unreadable.extend(dir_errors)
    for rel, full in dir_links:
        links.append(rel)
    relset = {rel for rel, full in files if not os.path.islink(full)}
    file_lines = []
    for rel, full in dir_links:
        file_lines.append("file path=%s kind=symlink_dir" % rel)
    for rel, detail in dir_errors:
        file_lines.append("file path=%s kind=%s" % (rel, detail))
    for rel, full in files:
        if os.path.islink(full):
            links.append(rel)
            file_lines.append("file path=%s kind=symlink" % rel)
            continue
        try:
            st1 = os.stat(full)
            digest = sha256_file(full)
            with open(full, "rb") as f:
                head = f.read(cfg.max_read)
            st2 = os.stat(full)
        except OSError as e:
            unreadable.append((rel, str(e)))
            unreadable_files.append(rel)
            file_lines.append("file path=%s kind=unreadable detail=%s" % (rel, e))
            continue
        if (st1.st_size, st1.st_mtime_ns) != (st2.st_size, st2.st_mtime_ns):
            changed.append(rel)
        if st1.st_size == 0 and not (empty_ok and safe(empty_ok, rel, rel, "empty_ok_regex")):
            empty.append(rel)
        if st1.st_size > cfg.max_read:
            truncated.append(rel)
        text = head.decode("utf-8", errors="replace")
        if sweep_rx and safe(sweep_rx, rel, rel, "sweep_level_regex"):
            sweep_level.append(rel)
            file_lines.append("file path=%s bytes=%d sha256=%s key=none kind=sweep_level" % (rel, st1.st_size, digest))
            continue
        key = keyof(rel)
        if rel in key_timed_out:
            unkeyed.append(rel)
            file_lines.append("file path=%s bytes=%d sha256=%s key=none kind=pattern_timeout" % (rel, st1.st_size, digest))
            continue
        if cfg.key_from_expected and known and key is not None and rel[len(key):] not in known:
            unexpected_files.append(rel)
            file_lines.append("file path=%s bytes=%d sha256=%s key=%s kind=unexpected_suffix" % (rel, st1.st_size, digest, key))
            continue
        n_timeouts = len(timeouts)
        is_res = any(safe(rx, rel if w == "path" else text, rel, "result_pattern") for w, rx in res_pats)
        is_ref = any(safe(rx, rel if w == "path" else text, rel, "refusal_pattern") for w, rx in ref_pats)
        timed_out = len(timeouts) > n_timeouts
        kind = "pattern_timeout" if timed_out and not (is_res or is_ref) else "conflict" if (is_res and is_ref) else "result" if is_res else "refusal" if is_ref else "other"
        rtype = None
        if is_ref and type_rx:
            m = safe(type_rx, text, rel, "refusal_type_regex")
            if m:
                rtype = (m.groupdict().get("type") if "type" in m.groupdict() else (m.group(1) if m.re.groups else m.group(0)))
        file_lines.append("file path=%s bytes=%d sha256=%s key=%s kind=%s%s" % (
            rel, st1.st_size, digest, key if key is not None else "none", kind,
            (" refusal_type=%s" % rtype) if rtype else ""))
        if key is None:
            unkeyed.append(rel)
            continue
        d = per.setdefault(key, {"records": [], "aux": []})
        if kind in ("other", "pattern_timeout"):
            d["aux"].append(rel)
        else:
            d["records"].append((rel, kind, rtype))

    missing, doubled, conflict, unclassified = [], [], [], []
    res_only = ref_only = 0
    types = {}
    untyped = []
    for k in expected:
        d = per.get(k)
        if d is None:
            missing.append(k)
            continue
        recs = d["records"]
        if not recs:
            unclassified.append(k)
            continue
        kinds = [r[1] for r in recs]
        if "conflict" in kinds or ("result" in kinds and "refusal" in kinds):
            conflict.append(k)
        elif len(recs) > 1:
            doubled.append(k)
        elif kinds[0] == "result":
            res_only += 1
        else:
            ref_only += 1
        for rel, kind, rtype in recs:
            if kind == "refusal":
                if rtype:
                    types[rtype] = types.get(rtype, 0) + 1
                elif type_rx:
                    untyped.append(rel)
    unexpected = sorted(k for k in per if k not in exp_set)
    required_missing, exceptions = [], []
    for k in expected:
        if per.get(k) and per[k]["records"]:
            for t in cfg.required_templates:
                path = t.replace("{key}", k)
                if k in cfg.required_exceptions.get(t, []):
                    exceptions.append("%s %s" % (k, path))
                    continue
                if path not in relset:
                    required_missing.append("%s %s" % (k, path))
    tsv_lines, tsv_rows, tsv_anomalies, tsv_hash_lines = _tsv_checks(root, files, cfg.tsv_checks, keyof, timeouts)
    pair_lines, pair_differ, pair_b_missing, pair_b_only = _pair_checks(files, cfg.pair_checks, timeouts) if cfg.pair_checks else ([], [], [], [])
    unmatched = []
    for t, ks in sorted(cfg.required_exceptions.items()):
        if t not in cfg.required_templates:
            unmatched.append("%s matches no required template" % t)
        for k in ks:
            if k not in exp_set:
                unmatched.append("%s %s key is not in the expected list" % (t, k))
            elif not (per.get(k) and per[k]["records"]):
                unmatched.append("%s %s key has no record file, the exception was not used" % (t, k))
    exact = len(expected_dup) == 0 and sorted(exp_set) == sorted(expected) and not (missing or doubled or conflict or unclassified)
    count_ok = cfg.expected_count is None or cfg.expected_count == len(exp_set)

    # Entry classes are disjoint: symlinks (to files or directories), unreadable files, sweep_level files, unkeyed files, keyed files.
    files_total = len(files) + len(dir_links)
    keyed_n = files_total - len(links) - len(unreadable_files) - len(sweep_level) - len(unkeyed)
    L.append("files total=%d keyed=%d unkeyed=%d sweep_level=%d unreadable_files=%d symlinks=%d unreadable=%d empty=%d truncated_read=%d changed_during_audit=%d" % (
        files_total, keyed_n, len(unkeyed), len(sweep_level), len(unreadable_files), len(links),
        len(unreadable), len(empty), len(truncated), len(changed)))
    L.append("per_expected_key one_result=%d one_refusal=%d missing=%d doubled=%d result_and_refusal=%d no_record_file=%d" % (
        res_only, ref_only, len(missing), len(doubled), len(conflict), len(unclassified)))
    L.append("keys_not_expected=%d unexpected_files=%d sweep_level_files=%d" % (len(unexpected), len(unexpected_files), len(sweep_level)))
    L.append("required_files missing=%d exceptions=%d (checked for keys with a record file, %d templates)" % (
        len(required_missing), len(exceptions), len(cfg.required_templates)))
    L.append("tsv_files checked=%d rows=%d anomalies=%d skipped_hash_lines=%d" % (len(tsv_lines), tsv_rows, len(tsv_anomalies), tsv_hash_lines))
    L.append("pattern_timeouts=%d limit_seconds=%s limit_class=CONVENTION unmatched_exceptions=%d" % (len(timeouts), cfg.pattern_timeout_seconds, len(unmatched)))
    if cfg.pair_checks:
        L.append("pairs differ=%d b_missing=%d b_without_a=%d" % (len(pair_differ), len(pair_b_missing), len(pair_b_only)))
    L.append("expected_count_matches_list=%s" % str(count_ok).lower())
    if type_rx:
        L.append("refusal_types " + (" ".join("%s=%d" % kv for kv in sorted(types.items())) or "none") + " untyped_refusal_records=%d" % len(untyped))
    for tag, items in (("missing", missing), ("doubled", doubled), ("result_and_refusal", conflict), ("no_record_file", unclassified),
                       ("not_expected", unexpected), ("unexpected_file", unexpected_files), ("unkeyed", unkeyed), ("empty", empty), ("symlink", links),
                       ("truncated_read", truncated), ("changed_during_audit", changed), ("untyped_refusal", untyped),
                       ("expected_duplicate", expected_dup),
                       ("sweep_level", sweep_level), ("required_missing", required_missing),
                       ("required_exception", exceptions), ("pair_differ", pair_differ),
                       ("pair_b_missing", pair_b_missing), ("pair_b_without_a", pair_b_only),
                       ("tsv_anomaly", tsv_anomalies), ("pattern_timeout", timeouts), ("unmatched_exception", unmatched)):
        for it in items:
            L.append("list %s %s" % (tag, it))
    for rel, e in unreadable:
        L.append("list unreadable %s %s" % (rel, e))
    for k in expected:
        d = per.get(k)
        if d:
            L.append("key %s records=%d aux=%d" % (k, len(d["records"]), len(d["aux"])))
    L += tsv_lines
    L += pair_lines
    L += file_lines
    complete = (exact and not unexpected and not unexpected_files and not unkeyed and not unreadable and not changed and not links
                and not empty and not truncated and not tsv_anomalies and not timeouts and not unmatched and not required_missing and not pair_differ and not pair_b_missing and not pair_b_only and count_ok
                and len(exp_set) == len(expected))
    L.append("complete=%s (descriptive: every expected key has exactly one record file, nothing else flagged)" % str(complete).lower())
    summary = dict(complete=complete, missing=missing, doubled=doubled, conflict=conflict, unclassified=unclassified,
                   unexpected=unexpected, unkeyed=unkeyed, one_result=res_only, one_refusal=ref_only, empty=empty,
                   unreadable=[u[0] for u in unreadable], changed=changed, types=types, untyped=untyped,
                   required_missing=required_missing, sweep_level=sweep_level,
                   expected_keys=len(expected), expected_list_sha256=hashlib.sha256(expected_text.encode()).hexdigest(),
                   unexpected_files=unexpected_files, symlinks=links, tsv_anomalies=tsv_anomalies, tsv_skipped_hash_lines=tsv_hash_lines,
                   pattern_timeout=timeouts, unmatched_exceptions=unmatched, truncated=truncated, config_sha256=cfg_sha,
                   files_total=files_total, keyed=keyed_n, unreadable_files=len(unreadable_files), pair_differ=pair_differ, pair_b_missing=pair_b_missing, pair_b_without_a=pair_b_only)
    return "\n".join(_esc(x) for x in L) + "\n", summary
