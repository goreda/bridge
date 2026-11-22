from pathlib import Path
import importlib.util
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("migration", root / "Tests/Structure/migrate.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
BASE = "faa9d2ab369fbc179e1298639d0005a3101a852e"


def original(relative):
    return subprocess.check_output(["git", "-C", str(root), "show", BASE + ":archive/gor/" + relative])


def snapshot(project):
    return {str(p.relative_to(project)): p.read_bytes() for p in project.rglob("*") if p.is_file() and ".gor-backups" not in p.parts}


with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    project, backups, external = base / "project", base / "backups", base / "gor-bbu"
    prior = backups / "261107-020000-pre-update"
    prior.mkdir(parents=True)
    project.mkdir()
    for relative in migration.OLD:
        p = project / relative
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(original(relative))
    diag = "Sources/gor/GorCore/Diag.swift"
    (project / diag).write_bytes(original(diag))
    sentinel = project / "Sources/gor/keep-local.swift"
    sentinel.write_text("// untracked user source stays\n")
    old_tree = snapshot(project)
    # Execute the ACTUAL shipped overlay installer (all boundaries outside the
    # installer are stubs). This is the first update using the old updater.
    source = base / "overlay"
    for relative in migration.NEW:
        p = source / relative
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / relative, p)
    script = (root / "build.sh").read_text()
    installer = script[script.index("gor_install_tree() {"):script.index("gor_rollback_verified() {")]
    shell = base / "install.sh"
    shell.write_text('set -e\nproject_root="$1"\nbackups_dir="$2"\nbig_file_bytes=209715200\n'
                     'gor_install_selftest_fixtures() { :; }\ngor_big_file_confirm() { return 0; }\n'
                     + installer + '\ngor_install_tree "$3" update\n')
    # Remove the synthetic empty backup before real installer makes its own.
    prior.rmdir()
    subprocess.run(["bash", str(shell), str(project), str(backups), str(source)], check=True)
    assert all((project / p).is_file() for p in migration.OLD), "overlay must preserve old inputs before retirement"
    installed = snapshot(project)
    # Any local edit fails closed before all removals and leaves the entire tree.
    edited = project / next(iter(migration.OLD))
    edited.write_bytes(edited.read_bytes() + b"\n// local edit\n")
    blocked_tree = snapshot(project)
    try:
        migration.retire(project, backups, external)
        raise AssertionError("local edits not blocked")
    except RuntimeError as error:
        assert "local edits preserved" in str(error)
    assert snapshot(project) == blocked_tree
    edited.write_bytes(installed[str(edited.relative_to(project))])
    # Replacement tamper is separately rejected without deleting originals.
    replacement = project / next(iter(migration.NEW))
    replacement.write_bytes(replacement.read_bytes() + b"\n// wrong replacement\n")
    blocked_tree = snapshot(project)
    try:
        migration.retire(project, backups, external)
        raise AssertionError("bad replacement not blocked")
    except RuntimeError as error:
        assert "replacement bytes not verified" in str(error)
    assert snapshot(project) == blocked_tree
    replacement.write_bytes(installed[str(replacement.relative_to(project))])
    # A mid-retirement filesystem failure restores the pre-update working tree.
    from unittest.mock import patch
    real_unlink = Path.unlink
    calls = [0]
    def fail_second(path, *args, **kwargs):
        if str(path.relative_to(project)) in migration.OLD:
            calls[0] += 1
            if calls[0] == 2:
                raise OSError("fixture removal failure")
        return real_unlink(path, *args, **kwargs)
    with patch.object(Path, "unlink", fail_second):
        try:
            migration.retire(project, backups, external)
            raise AssertionError("removal failure not surfaced")
        except RuntimeError as error:
            assert "restored pre-update source tree" in str(error)
    assert snapshot(project) == old_tree
    # Replay the overlay after that successful rollback, retaining failure evidence.
    for relative, data in installed.items():
        p = project / relative
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    # Names are second-resolution and deliberately fail on collision.
    import time
    time.sleep(1.05)
    backup = migration.retire(project, backups, external)
    assert backup.parent == external and backup.is_dir()
    assert not any((project / p).exists() for p in migration.OLD)
    assert sentinel.read_bytes() == old_tree[str(sentinel.relative_to(project))]
    for relative in migration.OLD:
        assert (backup / relative).read_bytes() == original(relative)
    assert migration.retire(project, backups, external) is None
    # Execute the actual normal rollback function. cp -c is Mac clone-copy;
    # replace only that platform boundary with Linux cp in this fixture.
    rollback = script[script.index("gor_rollback() {"):script.index("# ── block 176 item 3:")]
    rollback = rollback.replace("cp -c", "cp")
    shell.write_text('set -e\nproject_root="$1"\nbackups_dir="$2"\n' + rollback + '\ngor_rollback "$3"\n')
    subprocess.run(["bash", str(shell), str(project), str(backups), backup.name], check=True)
    assert snapshot(project) == old_tree, "rollback must restore full working source shape, no duplicates"
    print("PASS actual old overlay installer -> pinned retirement -> actual normal rollback: exact original source tree, unknown local file preserved, idempotent repeat, hash and replacement tamper fail closed")
