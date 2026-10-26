"""Hard gate: derive(train_manifest) must not read a held-out file (protocol section 2).
ReadRecorder logs the sha256 of every file opened inside its context through builtins.open / io.open
(this covers pathlib, numpy.load, json, csv). Reads through other means (C extensions that open
files by themselves, mmap, subprocesses) are NOT seen: such derive code must read only via
`ReadRecorder.read_bytes`. The gate fails if a held-out hash appears in the read set."""
import builtins, hashlib, io, os, pathlib


class ReadRecorder:
    def __init__(self, ignore_prefixes=()):
        self.reads = {}            # abs path -> sha256
        self._ignore = tuple(os.path.abspath(p) for p in ignore_prefixes)
        self._orig_builtin = None
        self._orig_io = None

    def _wrap(self, orig):
        def opener(file, mode='r', *a, **k):
            f = orig(file, mode, *a, **k)
            try:
                if isinstance(file, (str, bytes, os.PathLike)) and 'r' in mode and '+' not in mode \
                        and 'w' not in mode and 'a' not in mode:
                    path = os.path.abspath(os.fsdecode(file))
                    if not any(path.startswith(p) for p in self._ignore) and os.path.isfile(path):
                        h = hashlib.sha256()
                        with orig(path, 'rb') as g:
                            for c in iter(lambda: g.read(1 << 20), b''):
                                h.update(c)
                        self.reads[path] = h.hexdigest()
            except OSError:
                pass
            return f
        return opener

    def __enter__(self):
        self._orig_builtin, self._orig_io = builtins.open, io.open
        self._orig_path_open = pathlib.Path.open
        builtins.open = self._wrap(self._orig_builtin)
        io.open = self._wrap(self._orig_io)
        orig_po = self._orig_path_open; rec_open = self._wrap(self._orig_io)
        # pathlib on some Python versions binds io.open at import time; record through Path.open as well
        def path_open(p, mode='r', *a, **k):
            f = orig_po(p, mode, *a, **k)
            rec_open_probe(p, mode)
            return f
        def rec_open_probe(p, mode):
            if 'r' in mode and '+' not in mode:
                try:
                    with rec_open(os.fspath(p), 'rb'):
                        pass
                except OSError:
                    pass
        pathlib.Path.open = path_open
        return self

    def __exit__(self, *exc):
        builtins.open, io.open = self._orig_builtin, self._orig_io
        pathlib.Path.open = self._orig_path_open
        return False

    def read_bytes(self, path):
        with open(path, 'rb') as f:
            return f.read()

    def log(self):
        return {'reads': [{'path': p, 'sha256': s} for p, s in sorted(self.reads.items())]}


def check_no_heldout_reads(read_log, heldout_hashes):
    """Return (ok, offending list). A held-out hash in the read set is a hard failure."""
    hs = set(heldout_hashes)
    bad = [r for r in read_log.get('reads', []) if r.get('sha256') in hs]
    return (not bad), bad
