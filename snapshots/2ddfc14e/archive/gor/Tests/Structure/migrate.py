#!/usr/bin/env python3
"""Retire only the owner-approved domain consolidation inputs, backup first.

Runs after source overlay and before Swift compilation, including when the
previous build.sh did the overlay. The normal rollback command restores the
complete pre-update source/test tree, not a duplicate-declaration hybrid.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import sys

OLD = {'Sources/gor/VRRecognition.swift': 'f1138c0e6028596694f334620ecc3ef04e6c18ab1c8e7c55d05164aedfbe62ee',
 'Sources/gor/SBSPairEvidence.swift': '3bef6cddb9b60c1468098bdda8abbe1ce4369cb904b9d7a7c4d50d3e0eaedcf4',
 'Sources/gor/VRProjectionProbe.swift': '715cb09181be3106c4ff38e07a0ea25718c3b8bc2d410c23c2dbc01dd297688a',
 'Sources/gor/SBSGeometry.swift': 'f130f8979433e125c871d810496613c3b40f78aba5eeb75499cb0e2c1b9d9caa',
 'Sources/gor/SBSEyeCrop.swift': '9102547cf670d1260f631405774a04bc6a54a4803e784b1103af042337c0867a',
 'Sources/gor/StereoDepth.swift': '8b09c496bdc3864a955bfb3000dc043b9ad91fda61a8cc1cfff34c8e14af6b01',
 'Sources/gor/PoseContinuity.swift': 'd6e2feab4c123571310160d3961b2c60d3eb13c22f366bb0580793baadd13b41',
 'Sources/gor/LatestPoseSlot.swift': '28eec1d4609ecde7ccdd646fedd6109381b60ee1bac2889dea4ba3a7671a0d7e',
 'Sources/gor/BlinkControl.swift': '9bec9f09fe3e08c593277511822ca34e53c4bf4a0295f17bbaf3a4de66149d8d',
 'Sources/gor/SubtitleModeScale.swift': 'fae3a34ff5ad7aa95747d9009dac02028d410fc9fb98ce0af6117e52e7f560b6',
 'Sources/gor/SubtitleSizePreference.swift': '6b0c1824aa7cb33e008b5238304a0463d5bcd7bda9a3597d1af5843f51435fae',
 'Sources/gor/AVSessionTrace.swift': 'ea4ac90650b6ffb58ffc25184fb2cd42e307b75dd04485bce2126cf623b6ac10',
 'Sources/gor/ArchiveStreamManager.swift': '561da8f99df1bad86cca6b8aac6d6f2526f0994dfe67e1b63317fd84a90afd6b'}

NEW = {'Sources/gor/Stereo/StereoDetection.swift': 'b6bf2e7596d228058f4aabb0ef52729467de7b09f4bf0e7c07906fffb97b8bbc',
 'Sources/gor/Stereo/StereoGeometry.swift': '716b488f8d1e7d90e4a3aa7c94cab886d2e8fb953f26e7405d4e6254593bd25d',
 'Sources/gor/Stereo/HeadPose.swift': '511fad5f20a39649d7324f561e92151c37199af90cf408d3e54c3d9efc7309ca',
 'Sources/gor/Subtitles/SubtitlePreferences.swift': '30a18c62fe652cb4ecb10326654d09e45cc19c98ea479a8a68ba27d567c06786',
 'Sources/gor/GorCore/Diag.swift': '76921f4035bf3808352553de325b5c062db7ed798cb825e4eb699c7b92d157ae'}

OLD_DIAG = 'e21c61c244bd44191c67a49ef84cc2715b3048007d6274ba987b4c26aa5225f7'

def digest(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("consolidation: expected regular file: " + str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entries(path):
    rows = []
    for line in path.read_text().splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2 or parts[0] not in {"added", "changed", "deleted"}:
            raise RuntimeError("consolidation: invalid backup manifest")
        kind, relative = parts
        p = Path(relative)
        if p.is_absolute() or ".." in p.parts:
            raise RuntimeError("consolidation: unsafe backup path")
        rows.append((kind, relative))
    return rows


def restore(project, backup, rows, parked):
    # Same restore/move-aside contract as build.sh --rollback. No wildcard deletes.
    for kind, relative in rows:
        target = project / relative
        if kind in {"changed", "deleted"}:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup / relative, target)
        elif target.is_file():
            aside = parked / relative
            aside.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), str(aside))


def retire(project, backups, external):
    project, backups, external = map(Path, (project, backups, external))
    present = [name for name in OLD if (project / name).exists() or (project / name).is_symlink()]
    if not present:
        print("domain consolidation: no retired sources remain")
        return None
    # Finish every validation before making any backup or removing any input.
    for relative in present:
        if digest(project / relative) != OLD[relative]:
            raise RuntimeError("consolidation: local edits preserved: " + relative)
    for relative, expected in NEW.items():
        if digest(project / relative) != expected:
            raise RuntimeError("consolidation: replacement bytes not verified: " + relative)
    prior = None
    # The old updater has just installed these additions. Reuse its full rollback
    # inventory so the new diagnostic source and every changed harness revert too.
    for candidate in sorted(backups.glob("*-pre-update"), reverse=True):
        if not (candidate / "changes.txt").is_file():
            continue
        rows = entries(candidate / "changes.txt")
        inventory = set(rows)
        if not all(("added", relative) in inventory for relative in NEW if relative != "Sources/gor/GorCore/Diag.swift"):
            continue
        if ("changed", "Sources/gor/GorCore/Diag.swift") not in inventory:
            continue
        if digest(candidate / "Sources/gor/GorCore/Diag.swift") != OLD_DIAG:
            continue
        for kind, relative in rows:
            if kind in {"changed", "deleted"}:
                digest(candidate / relative)
        prior = candidate
        break
    if prior is None:
        raise RuntimeError("consolidation: exact pre-update rollback backup missing; no sources removed")
    name = datetime.datetime.now().strftime("%y%m%d-%H%M%S") + "-domain-consolidation"
    backup = external / name
    pointer = backups / name
    if backup.exists() or pointer.exists() or pointer.is_symlink():
        raise RuntimeError("consolidation: backup name collision; no sources removed")
    external.mkdir(parents=True, exist_ok=True)
    shutil.copytree(prior, backup)
    rows = entries(backup / "changes.txt")
    for relative in present:
        target = backup / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(project / relative, target)
        if digest(target) != OLD[relative]:
            raise RuntimeError("consolidation: backup readback failed; no sources removed")
        if ("deleted", relative) not in rows:
            rows.append(("deleted", relative))
    (backup / "changes.txt").write_text("".join(kind + "\t" + relative + "\n" for kind, relative in rows))
    (backup / "consolidation.json").write_text(json.dumps({"prior_update": str(prior), "removed": present}, indent=2))
    pointer.symlink_to(backup.resolve(), target_is_directory=True)
    try:
        for relative in present:
            (project / relative).unlink()
    except OSError:
        restore(project, backup, rows, backup / "failed-install-new-sources")
        raise RuntimeError("consolidation: retirement failed; restored pre-update source tree; backup=" + str(backup))
    print("domain consolidation: retired " + str(len(present)) + " exact inputs; backup=" + str(backup))
    print("domain consolidation: rollback with ./build.sh --rollback " + name)
    return backup


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: migrate.py PROJECT BACKUPS EXTERNAL_BACKUPS")
    try:
        retire(*sys.argv[1:])
    except (OSError, RuntimeError) as error:
        raise SystemExit(str(error))
