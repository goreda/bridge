"""Kit package content_sha256: canonical algorithm + verifier (contract s13).

Algorithm (used by the kit builder for every kit_manifest.json
content_sha256 value, and recomputed by consumers after unpack):

  For one .mlpackage directory:
  1. Walk the package recursively. Symlinks are FORBIDDEN (error).
     Dotfiles are ordinary files and are included (none expected).
     Directories contribute no bytes of their own.
  2. Take each regular file's path relative to the package root,
     UTF-8 encoded, '/'-separated, no leading './'.
  3. Sort the relative paths BYTEWISE.
  4. Feed sha256, per file in order:
         path_bytes + b'\\0' + file_bytes + b'\\0'
     (the NUL separators make the record boundaries unambiguous).
  The hex digest is the content_sha256.

CLI:
  python3 kit_hash.py PACKAGE.mlpackage [...]   # print hash per package
  python3 kit_hash.py --verify KIT_DIR          # check every package in
      # KIT_DIR against KIT_DIR/kit_manifest.json (content_sha256 and
      # size_bytes); exits non-zero on any mismatch
"""
import hashlib
import json
import os
import sys


def content_sha256(package_dir):
    h = hashlib.sha256()
    records = []
    for root, dirs, files in os.walk(package_dir):
        for name in dirs:
            p = os.path.join(root, name)
            if os.path.islink(p):
                raise ValueError(f"symlink forbidden in kit package: {p}")
        for name in files:
            p = os.path.join(root, name)
            if os.path.islink(p) or not os.path.isfile(p):
                raise ValueError(f"non-regular file forbidden: {p}")
            rel = os.path.relpath(p, package_dir).replace(os.sep, "/")
            records.append((rel, p))
    for rel, p in sorted(records, key=lambda r: r[0].encode("utf-8")):
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        with open(p, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        h.update(b"\0")
    return h.hexdigest()


def package_size(package_dir):
    total = 0
    for root, _, files in os.walk(package_dir):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total


def verify(kit_dir, manifest=None, archive_id=None):
    """Verify package contents, never trust an installed-marker alone.
    A split VDA/MoGe archive may carry a combined build manifest: check
    only the packages owned by this archive, matching install_kit."""
    manifest = manifest or os.path.join(kit_dir, "kit_manifest.json")
    try:
        man = json.load(open(manifest))
        pk = man["packages"]
        if not isinstance(pk, dict) or not pk:
            raise ValueError("empty or invalid packages")
    except (OSError, ValueError, KeyError) as e:
        print(f"FAIL manifest={manifest} reason={e}")
        return False
    ok, checked = True, 0
    for name, entry in pk.items():
        if archive_id and (name.startswith("moge2_") != archive_id.startswith("moge2")):
            continue
        checked += 1
        p = os.path.join(kit_dir, name)
        want, want_size = entry.get("content_sha256"), entry.get("size_bytes")
        try:
            if not os.path.isdir(p) or os.path.islink(p):
                raise ValueError("missing or symlink package")
            digest, size = content_sha256(p), package_size(p)
            good = digest == want and size == want_size
            if not good:
                print(f"FAIL package={name} expected_sha={want} actual_sha={digest} expected_bytes={want_size} actual_bytes={size}")
        except (OSError, ValueError) as e:
            print(f"FAIL package={name} expected_sha={want} actual_sha=unreadable expected_bytes={want_size} actual_bytes=unknown reason={e}")
            good = False
        ok = ok and good
    if checked == 0:
        print(f"FAIL manifest={manifest} reason=no packages for archive {archive_id}")
    return ok and checked > 0


if __name__ == "__main__":
    if sys.argv[1] == "--verify-archive":
        sys.exit(0 if verify(sys.argv[3], sys.argv[4], sys.argv[2]) else 1)
    if sys.argv[1] == "--verify":
        sys.exit(0 if verify(sys.argv[2]) else 1)
    for d in sys.argv[1:]:
        print(content_sha256(d), d)
