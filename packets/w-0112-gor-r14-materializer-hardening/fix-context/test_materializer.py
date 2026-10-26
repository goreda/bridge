"""Unit regressions for gor-r14 materialize_verified_zip (W-0109).

Synthetic fixtures are generated in temp dirs; no credentials, no network.
The optional actual-official-archive case runs only when GOR_OFFICIAL_ZIP
points at a local copy of yt-dlp_macos.zip (release 2026.08.19); it is
skipped otherwise and is clearly labeled. Nothing here mocks the actual
134-file archive: synthetic fixtures are small by design and labeled as such.
"""

import hashlib
import json
import os
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import materializer
from materializer import MaterializationError, materialize_verified_zip

HERE = Path(__file__).resolve().parent


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_zip(path: Path, members):
    """members: list of (name, data, unix_mode). unix_mode includes type bits."""
    with zipfile.ZipFile(path, "w") as zf:
        for name, data, mode in members:
            info = zipfile.ZipInfo(name, date_time=(2026, 8, 19, 0, 0, 0))
            info.create_system = 3  # unix
            info.external_attr = (mode & 0xFFFF) << 16
            if stat.S_ISREG(mode):
                info.compress_type = zipfile.ZIP_DEFLATED
                zf.writestr(info, data)
            else:
                zf.writestr(info, b"")
    return sha256_bytes(path.read_bytes())


REG = stat.S_IFREG
DIR = stat.S_IFDIR
LNK = stat.S_IFLNK
FIFO = stat.S_IFIFO


class MaterializerTests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.base = Path(self._td.name)
        self.archive = self.base / "fixture.zip"
        # Small synthetic fixture: 3 files, two executable. NOT the actual
        # 134-file archive; it exercises the same checks at fixture scale.
        self.files = {
            "yt-dlp_macos": b"#!/bin/sh\necho synthetic fixture\n",
            "_internal/libssl.3.dylib": b"synthetic-libssl-bytes",
            "_internal/certifi/cacert.pem": b"synthetic-pem",
        }
        self.modes = {
            "yt-dlp_macos": REG | 0o755,
            "_internal/libssl.3.dylib": REG | 0o755,
            "_internal/certifi/cacert.pem": REG | 0o644,
        }
        self.manifest = {rel: sha256_bytes(d) for rel, d in self.files.items()}
        self.zip_sha = make_zip(
            self.archive,
            [(rel, d, self.modes[rel]) for rel, d in self.files.items()])
        self.dest = self.base / "out" / "yt-dlp-standalone"
        self.dest.parent.mkdir()

    def run_materialize(self, **overrides):
        args = dict(archive_path=self.archive, destination_path=self.dest,
                    expected_zip_sha=self.zip_sha, manifest_dict=self.manifest)
        args.update(overrides)
        return materialize_verified_zip(**args)

    # ---- happy path -----------------------------------------------------

    def test_happy_path_atomic_materialization(self):
        result = self.run_materialize()
        self.assertEqual(result, str(self.dest))
        for rel, data in self.files.items():
            out = self.dest / rel
            self.assertTrue(out.is_file(), rel)
            self.assertEqual(out.read_bytes(), data, rel)

    def test_executable_mode_preserved(self):
        self.run_materialize()
        exe = self.dest / "yt-dlp_macos"
        lib = self.dest / "_internal/libssl.3.dylib"
        pem = self.dest / "_internal/certifi/cacert.pem"
        self.assertEqual(stat.S_IMODE(exe.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(lib.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(pem.stat().st_mode), 0o644)

    # ---- whole-archive verification -------------------------------------

    def test_wrong_zip_sha_rejected(self):
        with self.assertRaises(MaterializationError):
            self.run_materialize(expected_zip_sha="0" * 64)
        self.assertFalse(self.dest.exists())

    # ---- entry-table rejections ------------------------------------------

    def _zip_with(self, members):
        make_zip(self.archive, members)
        self.zip_sha = sha256_bytes(self.archive.read_bytes())

    def assert_rejected(self, members, manifest=None, needle=""):
        self._zip_with(members)
        with self.assertRaises(MaterializationError) as ctx:
            self.run_materialize(manifest_dict=manifest or self.manifest)
        if needle:
            self.assertIn(needle, str(ctx.exception))
        self.assertFalse(os.path.lexists(self.dest),
                         "rejected run must leave no destination")

    def test_traversal_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("../evil", b"x", REG | 0o644))
        manifest = dict(self.manifest, **{"../evil": sha256_bytes(b"x")})
        self.assert_rejected(members, manifest, "traversal")

    def test_traversal_nested_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("_internal/../../evil", b"x", REG | 0o644))
        manifest = dict(self.manifest, **{"_internal/../../evil": sha256_bytes(b"x")})
        self.assert_rejected(members, manifest, "traversal")

    def test_absolute_path_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("/abs/evil", b"x", REG | 0o644))
        manifest = dict(self.manifest, **{"/abs/evil": sha256_bytes(b"x")})
        self.assert_rejected(members, manifest, "absolute")

    def test_duplicate_entry_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("yt-dlp_macos", b"second copy", REG | 0o755))
        self.assert_rejected(members, None, "duplicate")

    def test_symlink_entry_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("_internal/link", b"target", LNK | 0o777))
        manifest = dict(self.manifest, **{"_internal/link": sha256_bytes(b"target")})
        self.assert_rejected(members, manifest, "symlink")

    def test_nonregular_entry_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("_internal/fifo", b"", FIFO | 0o644))
        manifest = dict(self.manifest, **{"_internal/fifo": sha256_bytes(b"")})
        self.assert_rejected(members, manifest, "non-regular")

    def test_extra_file_rejected(self):
        members = [(rel, d, self.modes[rel]) for rel, d in self.files.items()]
        members.append(("_internal/extra.so", b"extra", REG | 0o755))
        self.assert_rejected(members, None, "extra")

    def test_missing_file_rejected(self):
        members = [(rel, d, self.modes[rel])
                   for rel, d in self.files.items() if rel != "_internal/certifi/cacert.pem"]
        self.assert_rejected(members, None, "missing")

    def test_file_hash_mismatch_rejected(self):
        members = [("yt-dlp_macos", b"tampered bytes", self.modes["yt-dlp_macos"])]
        members += [(rel, d, self.modes[rel]) for rel, d in self.files.items()
                    if rel != "yt-dlp_macos"]
        self.assert_rejected(members, None, "hash mismatch")

    # ---- destination safety ----------------------------------------------

    def test_existing_destination_dir_rejected_and_untouched(self):
        self.dest.mkdir(parents=True)
        sentinel = self.dest / "KEEP"
        sentinel.write_text("precious")
        with self.assertRaises(MaterializationError):
            self.run_materialize()
        self.assertEqual(sentinel.read_text(), "precious")

    def test_existing_empty_destination_dir_rejected_and_preserved(self):
        """Negative control: even an EMPTY pre-existing dir is never replaced
        or deleted (exclusive rename must return EEXIST semantics)."""
        self.dest.mkdir(parents=True)
        with self.assertRaises(MaterializationError):
            self.run_materialize()
        self.assertTrue(self.dest.is_dir())
        self.assertEqual(list(self.dest.iterdir()), [],
                         "foreign empty dir was modified or replaced")

    def test_existing_destination_file_rejected_and_preserved(self):
        self.dest.write_text("precious file")
        with self.assertRaises(MaterializationError):
            self.run_materialize()
        self.assertEqual(self.dest.read_text(), "precious file")

    def test_existing_destination_symlink_rejected(self):
        real = self.base / "elsewhere"
        real.mkdir()
        self.dest.symlink_to(real, target_is_directory=True)
        with self.assertRaises(MaterializationError):
            self.run_materialize()
        self.assertTrue(self.dest.is_symlink())

    def test_path_ancestor_symlink_rejected(self):
        real = self.base / "real-parent"
        real.mkdir()
        link = self.base / "linked-parent"
        link.symlink_to(real, target_is_directory=True)
        dest = link / "yt-dlp-standalone"
        with self.assertRaises(MaterializationError) as ctx:
            self.run_materialize(destination_path=dest)
        self.assertIn("symlink", str(ctx.exception))
        self.assertFalse(os.path.lexists(real / "yt-dlp-standalone"))

    # ---- race negative controls -------------------------------------------

    def test_concurrent_creator_between_check_and_publish(self):
        """Adversarial: a foreign EMPTY dir appears at the destination after
        validation but before publish. Exclusive rename must fail closed and
        the foreign dir must survive untouched."""
        foreign_created = []

        original_probe = materializer._probe_exclusive_rename

        def adversarial_probe(call, flags, staging_dir):
            # Simulate the race at the last moment before publish.
            self.dest.mkdir()
            (self.dest / "FOREIGN").write_text("not ours")
            foreign_created.append(True)
            return original_probe(call, flags, staging_dir)

        with mock.patch.object(materializer, "_probe_exclusive_rename",
                               adversarial_probe):
            with self.assertRaises(MaterializationError) as ctx:
                self.run_materialize()
        self.assertTrue(foreign_created, "adversarial hook did not run")
        self.assertIn("appeared", str(ctx.exception))
        self.assertEqual((self.dest / "FOREIGN").read_text(), "not ours")

    def test_parent_inode_swap_detected_fail_closed(self):
        """Adversarial: the validated parent directory is replaced between
        validation and publish. The inode compare must fail closed."""
        original_open = os.open
        swapped = []

        def adversarial_open(path, flags, mode=0o777, *, dir_fd=None):
            if (not swapped and isinstance(path, str)
                    and path == os.path.realpath(self.dest.parent)
                    and not (flags & os.O_CREAT)):
                swapped.append(True)
                victim = Path(path)
                staging = victim.parent / (victim.name + ".swapped-away")
                os.rename(victim, staging)
                victim.mkdir()
                self.addCleanup(lambda: os.path.lexists(staging)
                                and os.rename(staging, victim)
                                if not os.path.lexists(victim) else None)
            return original_open(path, flags, mode, dir_fd=dir_fd)

        with mock.patch.object(materializer.os, "open", adversarial_open):
            with self.assertRaises(MaterializationError) as ctx:
                self.run_materialize()
        self.assertTrue(swapped, "adversarial hook did not run")
        self.assertIn("parent directory changed", str(ctx.exception))

    def test_fail_closed_when_exclusive_rename_unavailable(self):
        """Platform without a verified exclusive rename: fail closed, no
        destination, staging cleaned up."""
        with mock.patch.object(materializer, "_exclusive_rename",
                               side_effect=materializer._ExclusiveRenameUnavailable(
                                   "simulated unsupported platform")):
            with self.assertRaises(MaterializationError) as ctx:
                self.run_materialize()
        self.assertIn("failing closed", str(ctx.exception))
        self.assertFalse(os.path.lexists(self.dest))
        leftovers = [p.name for p in self.dest.parent.iterdir()
                     if p.name.startswith(f".{self.dest.name}.tmp-")]
        self.assertEqual(leftovers, [], "staging tree not cleaned up")

    # ---- interruption ------------------------------------------------------

    def test_clean_interruption_leaves_no_half_visible_tree(self):
        original_open = zipfile.ZipFile.open

        def flaky_open(zf, info, mode="r", **kw):
            src = original_open(zf, info, mode, **kw)
            if info.filename == "yt-dlp_macos":
                src.close()
                raise RuntimeError("simulated interruption mid-extraction")
            return src

        try:
            zipfile.ZipFile.open = flaky_open
            with self.assertRaises(RuntimeError):
                self.run_materialize()
        finally:
            zipfile.ZipFile.open = original_open
        self.assertFalse(os.path.lexists(self.dest),
                         "interrupted run left a half-visible final tree")
        leftovers = [p.name for p in self.dest.parent.iterdir()
                     if p.name.startswith(f".{self.dest.name}.tmp-")]
        self.assertEqual(leftovers, [], "staging tree not cleaned up")

    # ---- manifest validation -----------------------------------------------

    def test_manifest_hash_mismatch_rejected(self):
        bad = dict(self.manifest)
        bad["yt-dlp_macos"] = "f" * 64
        with self.assertRaises(MaterializationError):
            self.run_materialize(manifest_dict=bad)
        self.assertFalse(self.dest.exists())

    def test_empty_manifest_rejected(self):
        with self.assertRaises(MaterializationError):
            self.run_materialize(manifest_dict={})

    # ---- optional actual official archive -----------------------------------

    @unittest.skipUnless(os.environ.get("GOR_OFFICIAL_ZIP"),
                         "optional: set GOR_OFFICIAL_ZIP to a local copy of the "
                         "official yt-dlp_macos.zip (release 2026.08.19) to run")
    def test_optional_actual_official_archive(self):
        """OPTIONAL actual-archive case: real 134-file official ZIP on disk.

        Uses the packet's pinned sha256 and the packet's GOR-CLOSURE.json as
        the manifest. Not a mock: the real archive bytes are verified.
        """
        archive = Path(os.environ["GOR_OFFICIAL_ZIP"])
        self.assertEqual(archive.stat().st_size, 53923637, "official archive size")
        manifest = json.loads((HERE / "GOR-CLOSURE.json").read_text())
        self.assertEqual(len(manifest), 134)
        dest = self.base / "official" / "yt-dlp-standalone"
        dest.parent.mkdir()
        materialize_verified_zip(
            archive, dest,
            "07e54b0865303c864006925913bce2604f8ee8cc6f18699bac9c309f9328a6d8",
            manifest)
        exe = dest / "yt-dlp_macos"
        self.assertTrue(exe.is_file())
        self.assertTrue(exe.stat().st_mode & 0o111, "executable bit preserved")
        count = sum(1 for p in dest.rglob("*") if p.is_file())
        self.assertEqual(count, 134, "all 134 manifest files materialized")


class ArchiveAndStagingIdentityTests(unittest.TestCase):
    """Negative controls for archive identity pinning, staging identity and
    probe semantics (threat model: another actor with write access to the
    archive path or the destination parent)."""

    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.base = Path(self._td.name)
        self.archive = self.base / "fixture.zip"
        self.files = {
            "yt-dlp_macos": b"#!/bin/sh\necho synthetic fixture\n",
            "_internal/libssl.3.dylib": b"synthetic-libssl-bytes",
            "_internal/certifi/cacert.pem": b"synthetic-pem",
        }
        self.modes = {
            "yt-dlp_macos": REG | 0o755,
            "_internal/libssl.3.dylib": REG | 0o755,
            "_internal/certifi/cacert.pem": REG | 0o644,
        }
        self.manifest = {rel: sha256_bytes(d) for rel, d in self.files.items()}
        self.zip_sha = make_zip(
            self.archive,
            [(rel, d, self.modes[rel]) for rel, d in self.files.items()])
        self.dest = self.base / "out" / "yt-dlp-standalone"
        self.dest.parent.mkdir()

    def run_materialize(self, **overrides):
        args = dict(archive_path=self.archive, destination_path=self.dest,
                    expected_zip_sha=self.zip_sha, manifest_dict=self.manifest)
        args.update(overrides)
        return materialize_verified_zip(**args)

    def test_archive_identity_pinned_through_open_fd(self):
        """The module opens the archive ONCE and reads the ZIP through the
        same descriptor it hashed. Replacing the archive path AFTER the open
        must not substitute different bytes: the run still succeeds from the
        pinned inode."""
        original_open = os.open
        tampered = []

        def adversarial_open(path, flags, mode=0o777, *, dir_fd=None):
            fd = original_open(path, flags, mode, dir_fd=dir_fd)
            if (not tampered and isinstance(path, str)
                    and os.path.abspath(path) == str(self.archive)):
                # Replace the INODE at the archive path; the pinned
                # descriptor must keep reading the original bytes.
                decoy = self.base / "decoy.bin"
                decoy.write_bytes(b"GARBAGE replaced after open")
                os.replace(decoy, self.archive)
                tampered.append(True)
            return fd

        with mock.patch.object(materializer.os, "open", adversarial_open):
            result = self.run_materialize()
        self.assertTrue(tampered, "adversarial hook did not run")
        self.assertEqual(result, str(self.dest))
        for rel, data in self.files.items():
            self.assertEqual((self.dest / rel).read_bytes(), data, rel)

    def test_archive_replaced_before_open_rejected(self):
        """A swap that lands BEFORE the open is caught by the whole-archive
        hash: same file set and manifest, different container bytes."""
        with zipfile.ZipFile(self.archive, "w") as zf:
            for rel, data in self.files.items():
                info = zipfile.ZipInfo(rel, date_time=(2026, 8, 19, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (self.modes[rel] & 0xFFFF) << 16
                info.compress_type = zipfile.ZIP_STORED  # different bytes
                zf.writestr(info, data)
        self.assertNotEqual(sha256_bytes(self.archive.read_bytes()),
                            self.zip_sha)
        with self.assertRaises(MaterializationError) as ctx:
            self.run_materialize()
        self.assertIn("ZIP sha256 mismatch", str(ctx.exception))
        self.assertFalse(os.path.lexists(self.dest))

    def test_staging_replacement_detected_foreign_never_deleted(self):
        """Adversary with write access to the destination parent swaps the
        staging tree for a foreign directory before publish. The identity
        check must fail closed AND cleanup must refuse to delete the foreign
        replacement."""
        original_fsync_dir = materializer._fsync_dir
        swapped = []

        def adversarial_fsync_dir(path):
            # First fsync-dir call happens after extraction, before publish:
            # swap the staging tree for a foreign replacement now.
            if not swapped and ".tmp-" in os.path.basename(path):
                os.rename(path, path + ".stolen")
                os.mkdir(path)  # foreign replacement: different inode
                (Path(path) / "FOREIGN").write_text("not ours")
                swapped.append(path)
                return
            return original_fsync_dir(path)

        with mock.patch.object(materializer, "_fsync_dir",
                               adversarial_fsync_dir):
            with self.assertRaises(MaterializationError) as ctx:
                self.run_materialize()
        self.assertTrue(swapped, "adversarial hook did not run")
        self.assertIn("staging tree identity", str(ctx.exception))
        foreign = Path(swapped[0])
        self.assertEqual((foreign / "FOREIGN").read_text(), "not ours",
                         "cleanup deleted a foreign replacement")
        self.assertFalse(os.path.lexists(self.dest))
        # test teardown of adversarial artifacts
        import shutil as _sh
        _sh.rmtree(foreign, ignore_errors=True)
        _sh.rmtree(str(foreign) + ".stolen", ignore_errors=True)

    def test_directory_probe_semantics_enforced(self):
        """A rename shim with file-only no-replace semantics (silently
        replaces empty directories) must be caught by the directory probe:
        fail closed, nothing published."""
        import errno as _errno

        def wrong_semantics_call(ofd, old, nfd, new, flags):
            base_o = os.readlink(f"/proc/self/fd/{ofd}")
            base_n = os.readlink(f"/proc/self/fd/{nfd}")
            src = os.path.join(base_o, old)
            dst = os.path.join(base_n, new)
            if os.path.lexists(dst):
                if os.path.isdir(dst):
                    os.rmdir(dst)  # WRONG: silently replaces empty dirs
                else:
                    raise OSError(_errno.EEXIST, "File exists")
            os.rename(src, dst)

        with mock.patch.object(materializer, "_exclusive_rename",
                               lambda: (wrong_semantics_call, 1)):
            with self.assertRaises(MaterializationError) as ctx:
                self.run_materialize()
        self.assertIn("failing closed", str(ctx.exception))
        self.assertFalse(os.path.lexists(self.dest))



if __name__ == "__main__":
    unittest.main(verbosity=2)
