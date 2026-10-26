"""gor r14 whole-resource safe materializer (proposed new kit helper).

W-0109 scope: lab writes ONLY this proposed new stdlib-only Python module plus
its unit regressions. No AppDelegate/build.sh/product-repo edits. The
integrator owns the final owner-local kit; this module never applies the
result itself (the caller controls the final apply after a full kit backup).

materialize_verified_zip(archive_path, destination_path, expected_zip_sha,
manifest_dict)

Contract (derived from packets/w-0109-gor-r14-resource-materializer/PACKET.md):
  * stdlib only; fully offline after the explicit archive input. No network,
    no user paths, no default install location.
  * destination_path must NOT already exist: never overwrite and never delete
    an existing tree.
  * no ancestor component of destination_path may be a symlink.
  * the archive's whole-file sha256 must equal expected_zip_sha.
  * the archive's regular-file entries must match manifest_dict exactly:
    traversal, absolute paths, duplicate entries, symlinks, non-regular
    entries, extra files, missing files and per-file hash mismatches are all
    rejected.
  * the new directory is produced atomically; a clean interruption leaves no
    half-visible final tree.
  * ZIP executable permission bits are preserved (setuid/setgid/sticky
    stripped).

Guarantees and threat model (stated precisely, not overclaimed):

  ARCHIVE IDENTITY. The archive is opened ONCE (os.open, O_NOFOLLOW where
  the platform offers it); the whole-file sha256 is hashed from that open
  descriptor and the ZIP is read back through the SAME descriptor. Replacing
  the archive path after the hash therefore cannot substitute different
  bytes: extraction reads exactly the inode that was hashed. A swap that
  lands before the open is caught by the hash itself.

  PUBLISH. The verified staging tree is published with an EXCLUSIVE rename:
  Linux renameat2(RENAME_NOREPLACE), macOS renameatx_np(RENAME_EXCL), both
  reached through ctypes (Python stdlib). The shim is probed at runtime
  inside our own staging tree before use, for BOTH a file entry and a
  directory entry: rename onto an existing name must fail with EEXIST and
  rename onto a fresh name must succeed, or the call fails closed with
  MaterializationError and nothing is published. (The probe verifies the
  no-replace semantic for file and directory entries; other entry types are
  never published.) Platforms without a known exclusive-rename shim fail
  closed the same way. Where the probe passes, publish is atomic in
  visibility AND hard no-overwrite against any existing destination name,
  including empty directories. No caller-exclusivity precondition is assumed
  for this guarantee.

  ANCESTORS. The ancestor symlink check runs at validation time. At publish
  time the parent directory's (st_dev, st_ino) is re-compared against the
  validated inode and the rename is issued relative to the pinned parent
  descriptor, so a post-validation ancestor symlink swap cannot redirect the
  final tree; a swapped parent inode fails closed. Residual, disclosed: an
  ancestor replaced AFTER the parent descriptor is opened can publish the
  tree into the detached old inode; the live destination path then has no
  tree - never a foreign or half-visible tree.

  STAGING IDENTITY. The staging directory's (st_dev, st_ino) is recorded at
  creation. At publish, the staging name is re-stat'ed through the pinned
  parent descriptor WITHOUT following symlinks and must match the recorded
  identity and be a real directory, so a staging tree swapped out by another
  actor with write access to the parent fails closed instead of publishing a
  foreign tree. Cleanup deletes the staging tree only while its identity
  still matches the recorded inode; a foreign replacement is never deleted.
  Residual, disclosed: rename and rmtree are name-based syscalls, so a
  micro-window remains between each identity check and its syscall under an
  adversary actively mutating the destination parent; no portable stdlib
  rename-by-inode exists.

  PLATFORM BOUNDS. Executed and tested on Linux (renameat2 path). The macOS
  renameatx_np branch is written but NOT executed in this lab and is labeled
  untested. Other platforms fail closed by design.
"""

from __future__ import annotations

import ctypes
import errno
import hashlib
import os
import platform
import shutil
import stat
import sys
import tempfile
import zipfile

__all__ = ["MaterializationError", "materialize_verified_zip"]


class MaterializationError(Exception):
    """Any safety check failed. The destination was never created,
    overwritten, or deleted."""


class _ExclusiveRenameUnavailable(Exception):
    """No verified exclusive-rename semantic on this platform; fail closed."""


_CHUNK = 1024 * 1024
_HEX64 = frozenset("0123456789abcdef")

_RENAME_NOREPLACE = 0x00000001  # Linux renameat2 flag
_RENAME_EXCL = 0x00000004       # Darwin renameatx_np flag

# renameat2 syscall numbers where the libc wrapper may be absent.
_RENAMEAT2_SYSCALL = {
    "x86_64": 316, "amd64": 316,
    "aarch64": 276, "arm64": 276,
    "i386": 353, "i686": 353,
    "riscv64": 276,
}


def _require(cond, message):
    if not cond:
        raise MaterializationError(message)


def _check_sha256_literal(value, what):
    _require(isinstance(value, str), f"{what} must be a sha256 hex string")
    v = value.strip().lower()
    _require(len(v) == 64 and all(c in _HEX64 for c in v),
             f"{what} must be 64 hex characters: {value!r}")
    return v


def _hash_stream(fh):
    h = hashlib.sha256()
    for chunk in iter(lambda: fh.read(_CHUNK), b""):
        h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------
# Exclusive rename shims (ctypes is Python stdlib).
# --------------------------------------------------------------------------

def _linux_exclusive_rename(libc):
    fn = getattr(libc, "renameat2", None)
    if fn is not None:
        def call(ofd, old, nfd, new, flags):
            if fn(ofd, os.fsencode(old), nfd, os.fsencode(new), flags) != 0:
                e = ctypes.get_errno()
                raise OSError(e, os.strerror(e))
        return call, _RENAME_NOREPLACE
    nr = _RENAMEAT2_SYSCALL.get(platform.machine().lower())
    if nr is None:
        raise _ExclusiveRenameUnavailable(
            f"no renameat2 wrapper and unknown syscall number for "
            f"machine {platform.machine()!r}")
    syscall = libc.syscall

    def call(ofd, old, nfd, new, flags):
        if syscall(nr, ofd, os.fsencode(old), nfd, os.fsencode(new),
                   flags) == -1:
            e = ctypes.get_errno()
            raise OSError(e, os.strerror(e))
    return call, _RENAME_NOREPLACE


def _darwin_exclusive_rename(libc):
    # NOTE: written for the macOS kit target but NOT executed in this lab.
    fn = getattr(libc, "renameatx_np", None)
    if fn is None:
        raise _ExclusiveRenameUnavailable("renameatx_np not available")
    def call(ofd, old, nfd, new, flags):
        if fn(ofd, os.fsencode(old), nfd, os.fsencode(new), flags) != 0:
            e = ctypes.get_errno()
            raise OSError(e, os.strerror(e))
    return call, _RENAME_EXCL


def _exclusive_rename():
    if sys.platform.startswith("linux"):
        return _linux_exclusive_rename(ctypes.CDLL(None, use_errno=True))
    if sys.platform == "darwin":
        return _darwin_exclusive_rename(ctypes.CDLL(None, use_errno=True))
    raise _ExclusiveRenameUnavailable(
        f"no exclusive-rename shim for platform {sys.platform!r}")


def _touch(dir_fd, name):
    fd = os.open(name, os.O_CREAT | os.O_WRONLY, 0o644, dir_fd=dir_fd)
    os.close(fd)


def _probe_exclusive_rename(call, flags, staging_dir):
    """Prove the no-replace semantic inside our own staging tree, for BOTH a
    file entry and a directory entry (the publish target is a directory).

    Fails closed (_ExclusiveRenameUnavailable) unless rename-onto-existing
    verifiably fails with EEXIST and rename-onto-fresh-name succeeds.
    """
    fd = os.open(staging_dir, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        # File-onto-file must refuse; file-onto-fresh must succeed.
        _touch(fd, "._probe_a")
        _touch(fd, "._probe_b")
        try:
            call(fd, "._probe_a", fd, "._probe_b", flags)
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise _ExclusiveRenameUnavailable(
                    f"exclusive rename file probe failed with {exc!r}")
        else:
            raise _ExclusiveRenameUnavailable(
                "exclusive rename probe silently replaced an existing file")
        try:
            call(fd, "._probe_a", fd, "._probe_c", flags)
        except OSError as exc:
            raise _ExclusiveRenameUnavailable(
                f"exclusive rename probe plain rename failed: {exc!r}")
        # Directory-onto-existing-empty-directory must refuse (the publish
        # case); directory-onto-fresh must succeed.
        os.mkdir("._probe_da", dir_fd=fd)
        os.mkdir("._probe_db", dir_fd=fd)
        try:
            call(fd, "._probe_da", fd, "._probe_db", flags)
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise _ExclusiveRenameUnavailable(
                    f"exclusive rename directory probe failed with {exc!r}")
        else:
            raise _ExclusiveRenameUnavailable(
                "exclusive rename probe silently replaced an existing "
                "empty directory")
        try:
            call(fd, "._probe_da", fd, "._probe_dc", flags)
        except OSError as exc:
            raise _ExclusiveRenameUnavailable(
                f"exclusive rename probe plain directory rename failed: "
                f"{exc!r}")
    finally:
        for name in ("._probe_a", "._probe_b", "._probe_c"):
            try:
                os.unlink(name, dir_fd=fd)
            except OSError:
                pass
        for name in ("._probe_da", "._probe_db", "._probe_dc"):
            try:
                os.rmdir(name, dir_fd=fd)
            except OSError:
                pass
        os.close(fd)


# --------------------------------------------------------------------------
# Path and entry validation.
# --------------------------------------------------------------------------

def _validate_destination(destination_path):
    """Reject existing destinations and symlink ancestors.

    Returns (parent_real, final, parent_dev, parent_ino): the validated
    parent inode identity, re-checked at publish time.
    """
    dest = os.path.abspath(os.fspath(destination_path))
    parent, final = os.path.split(dest)
    _require(final not in ("", ".", ".."),
             f"destination final component unusable: {final!r}")
    # Never overwrite/delete an existing tree (lexists covers symlinks).
    _require(not os.path.lexists(dest),
             f"destination already exists; refusing to overwrite: {dest}")
    _require(os.path.isdir(parent) or not os.path.lexists(parent),
             f"destination parent exists but is not a directory: {parent}")
    components = []
    cursor = parent
    while True:
        head, tail = os.path.split(cursor)
        if tail:
            components.append(tail)
            cursor = head
        else:
            root = head
            break
    walk = root if root else os.sep
    for comp in reversed(components):
        walk = os.path.join(walk, comp)
        if os.path.islink(walk):
            raise MaterializationError(
                f"destination ancestor is a symlink: {walk}")
        if not os.path.lexists(walk):
            break
    parent_real = os.path.realpath(parent)
    st = os.stat(parent_real)
    _require(stat.S_ISDIR(st.st_mode),
             f"destination parent is not a directory: {parent_real}")
    return parent_real, final, st.st_dev, st.st_ino


def _validate_member_name(name):
    """Return the normalized relative path or raise MaterializationError."""
    _require(isinstance(name, str) and name, "empty ZIP member name")
    _require("\\" not in name, f"backslash in ZIP member name: {name!r}")
    _require(not name.startswith("/"), f"absolute ZIP member path: {name!r}")
    _require(not (len(name) >= 2 and name[1] == ":"),
             f"drive-letter ZIP member path: {name!r}")
    parts = name.split("/")
    for part in parts:
        _require(part not in ("", "."),
                 f"empty or dot component in ZIP member path: {name!r}")
        _require(part != "..",
                 f"traversal component in ZIP member path: {name!r}")
    return "/".join(parts)


def _entry_mode(info):
    """(kind, perm_bits) from unix external attributes; reject non-regular."""
    mode = (info.external_attr >> 16) & 0xFFFF
    kind = stat.S_IFMT(mode)
    if kind == 0:
        # Non-unix archiver with no type bits: plain regular file, default
        # permissions.
        return "file", 0o644
    if stat.S_ISDIR(mode):
        return "dir", 0
    if stat.S_ISLNK(mode):
        raise MaterializationError(
            f"symlink ZIP entry rejected: {info.filename!r}")
    if stat.S_ISREG(mode):
        # Preserve rwx bits; strip setuid/setgid/sticky from untrusted input.
        return "file", stat.S_IMODE(mode) & 0o777 & ~0o6000
    raise MaterializationError(
        f"non-regular ZIP entry rejected (mode {oct(mode)}): {info.filename!r}")


def _fsync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


# --------------------------------------------------------------------------
# Publish.
# --------------------------------------------------------------------------

def _publish(tmp, parent_real, final, parent_dev, parent_ino, staging_key):
    call, flags = _exclusive_rename()
    pfd = os.open(parent_real, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        st_fd = os.fstat(pfd)
        _require((st_fd.st_dev, st_fd.st_ino) == (parent_dev, parent_ino),
                 "destination parent directory changed during materialization")
        tmp_name = os.path.basename(tmp)
        # Re-stat the staging name through the pinned parent WITHOUT
        # following symlinks; it must still be the exact directory this
        # module created. A swapped-in foreign tree or symlink fails closed.
        st_tmp = os.stat(tmp_name, dir_fd=pfd, follow_symlinks=False)
        _require(stat.S_ISDIR(st_tmp.st_mode) and
                 (st_tmp.st_dev, st_tmp.st_ino) == staging_key,
                 "staging tree identity changed during materialization")
        _probe_exclusive_rename(call, flags, tmp)
        try:
            call(pfd, tmp_name, pfd, final, flags)
        except OSError as exc:
            if exc.errno == errno.EEXIST:
                raise MaterializationError(
                    f"destination appeared during extraction: {final!r}")
            raise
        os.fsync(pfd)
    finally:
        os.close(pfd)
    return os.path.join(parent_real, final)


# --------------------------------------------------------------------------
# Public interface.
# --------------------------------------------------------------------------

def materialize_verified_zip(archive_path, destination_path, expected_zip_sha,
                             manifest_dict):
    """Verify *archive_path* and materialize it atomically at
    *destination_path*. Returns destination_path on success; raises
    MaterializationError on any failed check, leaving the destination
    untouched.
    """
    archive = os.path.abspath(os.fspath(archive_path))
    _require(os.path.isfile(archive) and not os.path.islink(archive),
             f"archive is not a regular file: {archive}")
    expected_zip = _check_sha256_literal(expected_zip_sha, "expected_zip_sha")
    _require(isinstance(manifest_dict, dict) and manifest_dict,
             "manifest_dict must be a non-empty {relpath: sha256} mapping")
    manifest = {}
    for rel, sha in manifest_dict.items():
        _require(isinstance(rel, str) and rel,
                 "manifest key must be a relpath")
        norm = _validate_member_name(rel)
        _require(norm not in manifest, f"duplicate manifest path: {rel!r}")
        manifest[norm] = _check_sha256_literal(
            sha, f"manifest hash for {rel!r}")

    parent_real, final, parent_dev, parent_ino = _validate_destination(
        destination_path)

    # Open the archive ONCE: the hash and the ZIP read share one descriptor,
    # so replacing the path after hashing cannot substitute different bytes.
    afd = os.open(archive, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(afd, "rb") as afh:
        st_arc = os.fstat(afh.fileno())
        _require(stat.S_ISREG(st_arc.st_mode),
                 f"archive is not a regular file: {archive}")
        actual_zip = _hash_stream(afh)
        _require(actual_zip == expected_zip,
                 f"ZIP sha256 mismatch: expected {expected_zip}, "
                 f"got {actual_zip}")
        afh.seek(0)
        try:
            zf = zipfile.ZipFile(afh)
        except zipfile.BadZipFile as exc:
            raise MaterializationError(
                f"not a ZIP archive: {archive}: {exc}")
        with zf:
            files = {}
            dirs = set()
            for info in zf.infolist():
                name = info.filename
                is_dir_entry = name.endswith("/")
                if is_dir_entry:
                    name = name.rstrip("/")
                    _require(name, "empty directory entry in ZIP")
                rel = _validate_member_name(name)
                _require(rel not in files and rel not in dirs,
                         f"duplicate ZIP entry: {rel!r}")
                kind, perm = _entry_mode(info)
                if is_dir_entry:
                    _require(kind in ("dir", "file"),
                             f"directory entry with non-directory type: "
                             f"{rel!r}")
                    dirs.add(rel)
                    continue
                _require(kind == "file",
                         f"directory-only entry used as file: {rel!r}")
                _require(rel in manifest,
                         f"extra ZIP file not in manifest: {rel!r}")
                files[rel] = (info, perm)
            missing = sorted(set(manifest) - set(files))
            _require(not missing,
                     "manifest files missing from ZIP: " + ", ".join(missing))

            # Extract + verify into a hidden sibling staging dir, then
            # publish with an exclusive rename (fail closed when
            # unavailable). The staging directory's inode identity is
            # recorded at creation; publish re-verifies it and cleanup
            # deletes only that identity - never a foreign replacement.
            tmp = tempfile.mkdtemp(prefix=f".{final}.tmp-", dir=parent_real)
            st_created = os.lstat(tmp)
            staging_key = (st_created.st_dev, st_created.st_ino)
            try:
                for rel in sorted(files):
                    info, perm = files[rel]
                    out = os.path.join(tmp, *rel.split("/"))
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    h = hashlib.sha256()
                    with zf.open(info, "r") as src, open(out, "wb") as dst:
                        for chunk in iter(lambda: src.read(_CHUNK), b""):
                            h.update(chunk)
                            dst.write(chunk)
                        dst.flush()
                        os.fsync(dst.fileno())
                    os.chmod(out, perm)
                    got = h.hexdigest()
                    _require(got == manifest[rel],
                             f"file hash mismatch for {rel}: expected "
                             f"{manifest[rel]}, got {got}")
                for root, _subdirs, _files in os.walk(tmp):
                    _fsync_dir(root)
                return _publish(tmp, parent_real, final, parent_dev,
                                parent_ino, staging_key)
            except _ExclusiveRenameUnavailable as exc:
                raise MaterializationError(
                    f"exclusive rename unavailable, failing closed: {exc}")
            finally:
                try:
                    st_now = os.lstat(tmp)
                except OSError:
                    st_now = None
                if (st_now is not None
                        and stat.S_ISDIR(st_now.st_mode)
                        and (st_now.st_dev, st_now.st_ino) == staging_key):
                    # Same identity this module created: safe to remove.
                    # A published tree no longer exists under this name; a
                    # foreign replacement is deliberately left untouched.
                    shutil.rmtree(tmp, ignore_errors=True)
