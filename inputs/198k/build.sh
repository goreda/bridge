#!/bin/bash
set -e
# Local runner lifecycle is separate from build logging, locks, update and bridge.
# Registration uses only the Mac's local credential; no secret enters build logging.
case "${1:-}" in
    --install-runner|--remove-runner)
        set +x
        runner_root="$(cd "$(dirname "$0")" && pwd -P)"
        runner_action=install
        [ "$1" = --remove-runner ] && runner_action=remove
        exec /usr/bin/python3 "$runner_root/Tests/Runner/runner.py" "$runner_action"
        ;;
esac
# Every Git invocation, including embedded Python children, is noninteractive and bounded.
_gor_git_bin=${GOR_REAL_GIT:-$(command -v git)}
_gor_git_guard=$(mktemp -d "${TMPDIR:-/tmp}/gor-git-guard.XXXXXXXX")
export GOR_REAL_GIT="$_gor_git_bin" GIT_PAGER=cat GIT_TERMINAL_PROMPT=0
cat > "$_gor_git_guard/git" <<'GOR_GIT_GUARD'
#!/usr/bin/python3
import os,subprocess,sys
try:raise SystemExit(subprocess.run([os.environ['GOR_REAL_GIT'],'-c','core.pager=cat']+sys.argv[1:],env=dict(os.environ,GIT_PAGER='cat',GIT_TERMINAL_PROMPT='0'),timeout=45).returncode)
except subprocess.TimeoutExpired:print('git timeout; local state preserved',file=sys.stderr);raise SystemExit(124)
GOR_GIT_GUARD
chmod 700 "$_gor_git_guard/git"
export PATH="$_gor_git_guard:$PATH"

# block 175: manual repo-sync push entry point. Runs BEFORE the build lock,
# the build, and launch; performs no build/lock/launch side effects.
if [ "${1:-}" = "--push" ]; then
    sync_helper="$HOME/Downloads/gor-repo-sync/sync.sh"
    if [ ! -x "$sync_helper" ]; then
        echo "repo sync helper not installed: $sync_helper (run the stage-2 install first)" >&2
        exit 1
    fi
    echo 'source push from this Mac is disabled (block185); captures are sent by --update.'
    exit 0
fi

# Source-side delivery gate (no build/lock/install; the update's integrity check is untouched): a push whose listed file lacks its emitted row fails.
if [ "${1:-}" = "--check-delivery" ]; then
    exec /bin/sh -c 'cd "$(dirname "$0")" && bash tools/arch-check.sh --freeze-only && python3 Tests/Architecture/structure_freeze_test.py && python3 Tests/Architecture/manifest_tree_test.py && python3 Tests/Architecture/push_delivery_test.py && python3 Tests/Harness/ScreenCamera/signal_test.py --r1-only && python3 tools/build/test_characterization.py && python3 Tests/Harness/AudioFont/test_cache_fanout.py && python3 Tests/SessionLogs/session_logs_test.py && python3 Tests/SessionLogs/camera_helper_sample_test.py && python3 Tests/Harness/ScreenCamera/handle_helper_frame_test.py && python3 Tests/Harness/ScreenCamera/watchdog_recovery_test.py && python3 Tests/Harness/ScreenCamera/vision_worker_test.py && python3 Tests/Harness/ScreenCamera/camera_effects_test.py && python3 Tests/Harness/ScreenCamera/subtitle_face_watchdog_test.py && python3 Tests/Architecture/run.py >/dev/null && echo "delivery gate: PASS"' "$0"
fi

# Bootstrap a newer updater directly from the fetched sidecar without overwriting project files.
# The explicit destination must already be a gor project; ordinary snapshot/lock/install rules follow.
if [ "${1:-}" = "--update-project" ]; then
    [ "$#" = 2 ] && [ -f "$2/Package.swift" ] && [ -f "$2/build.sh" ] && [ -d "$2/Sources/gor" ] || { echo 'invalid existing gor project'; exit 1; }
    GOR_PROJECT_ROOT="$(cd "$2" && pwd -P)"
    export GOR_PROJECT_ROOT
    set -- --update
fi

# block 176c: staged snapshot re-exec. --update (and any rollback) can replace
# this file mid-run; never execute bytes that may be swapped underfoot. The
# real project root and the original path survive in env; the snapshot is a
# private 0700 temp file, removed on real process exit. --push above never
# mutates this file, so it stays unsnapshotted.
if [ -z "${GOR_SNAPSHOT:-}" ] || [ "$0" != "${GOR_SNAPSHOT_PATH:-}" ]; then
    _gor_snap_root="$(cd "$(dirname "$0")" && pwd -P)"
    _gor_snap="$(mktemp "${TMPDIR:-/tmp}/gor-build-snap.XXXXXXXX")" || { echo 'cannot create snapshot temp' >&2; exit 1; }
    if ! cp "$_gor_snap_root/$(basename "$0")" "$_gor_snap"; then
        rm -f "$_gor_snap"; echo 'cannot snapshot build.sh' >&2; exit 1
    fi
    chmod 700 "$_gor_snap"
    GOR_SNAPSHOT=1 GOR_SNAPSHOT_PATH="$_gor_snap" GOR_SNAPSHOT_ORIG="$_gor_snap_root/$(basename "$0")" \
        GOR_PROJECT_ROOT="${GOR_PROJECT_ROOT:-$_gor_snap_root}" exec bash "$_gor_snap" "$@"
    echo 'snapshot exec failed' >&2; exit 1
fi
trap 'rm -f "${GOR_SNAPSHOT_PATH:-}" "${GOR_SNAPSHOT_OLD:-}" 2>/dev/null' EXIT

# block 174 item 1: keep the old clear, but only on a real terminal.
if [ -t 1 ]; then clear && printf '\033[3J'; fi

# gor-fix: hash of this build.sh, measured once at start (status checked before any parsing), validated, recorded in the app later.
GOR_BUILD_SH_SHA256_AT_START=$(shasum -a 256 "${GOR_SNAPSHOT_ORIG:-$0}") || { echo 'cannot hash build.sh' >&2; exit 1; }
GOR_BUILD_SH_SHA256_AT_START=${GOR_BUILD_SH_SHA256_AT_START%% *}
case "$GOR_BUILD_SH_SHA256_AT_START" in
    *[!0-9a-f]*) echo 'build.sh hash malformed' >&2; exit 1 ;;
esac
[ "${#GOR_BUILD_SH_SHA256_AT_START}" = 64 ] || { echo 'build.sh hash not 64 hex' >&2; exit 1; }

GOR_BUILD_SH_SERIAL=2   # block 174 item 12: serial 1 -> 2

# GOR_BUILD_SCOPE_BEGIN
# Lock the physical project before touching shared logs, staging or processes.
if [ -n "${GOR_PROJECT_ROOT:-}" ]; then
    # 176c snapshot re-exec: "$0" is the temp copy; the real root comes from env.
    project_root="$GOR_PROJECT_ROOT"
else
    project_root="$(cd "$(dirname "$0")" && pwd -P)"
fi
build_lock="$project_root/.gor-build.lock"
if [ -n "${GOR_BUILD_LOCK_HELD:-}" ]; then
    # Inherited across the --update re-exec: same PID, the lock is already ours.
    if [ "$(cat "$build_lock/pid" 2>/dev/null)" != "$$" ]; then
        echo "inherited build lock pid mismatch — stopping, nothing changed" >&2
        exit 1
    fi
elif ! mkdir "$build_lock" 2>/dev/null; then
    echo "Another build or an interrupted-build lock exists: $build_lock" >&2
    echo 'Nothing changed. Do not remove a lock while its build is running.' >&2
    exit 1
else
    printf '%s\n' "$$" > "$build_lock/pid"
fi
gor_release_build_lock() {
    # Remove only the lock acquired by this invocation, not another build's.
    if [ "$(cat "$build_lock/pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$build_lock/pid"
        rmdir "$build_lock" 2>/dev/null || true
    fi
}
# 176c: snapshot temp files go only at REAL process exit (never mid-run: the
# shell reads the snapshot lazily). Called from both EXIT traps.
gor_cleanup_snapshot() { rm -f "${GOR_SNAPSHOT_PATH:-}" "${GOR_SNAPSHOT_OLD:-}" 2>/dev/null || true; }
trap 'gor_release_build_lock; gor_cleanup_snapshot' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$project_root"
# GOR_BUILD_SCOPE_END

start_time=$(date +%s)

playback_marker="/tmp/gor-build-playback-start.marker"
rm -f "$playback_marker"

# ── config ────────────────────────────────────────────────────────────────────
open_app=true          # launch after build
exit_log_zip=true      # install post-exit log watcher and next-launch recovery
log_timestamp=true     # true/false: timestamp on every captured log line
log_cpu_info=true      # true/false: cached system CPU percent and CPU sensor temperature
log_mode="direct"      # log mode after launch (see LOG MODES below)
show_warnings=false    # show swift compiler warnings (can be noisy)
separate_build_log=false # true: retain all printed build/sign/install output plus unfiltered Swift in /tmp/gor_build.log
create_dmg=false       # package as .dmg
clean_build=false      # delete .build/ before compiling
signing_enabled=true   # stable MacDev identity preferred for local TCC grants; there is no ad-hoc app fallback
build_whisper=false    # also build whisper-live before the swift build (see WHISPER-LIVE below)

# ── whisper-live ──────────────────────────────────────────────────────────────
# whisper_src_dir (set below, after project_root): the whisper.cpp checkout
# with examples/whisper-live/main.cpp. cmake --build is incremental (~1s no-op).

# ── LOG MODES ─────────────────────────────────────────────────────────────────
#   off      no log output. direct   exec in terminal, raw stdout+stderr (may
#            hit TCC -3801 without a screen-recording grant; falls back to
#            filter). filter   [GOR]-prefixed NSLog only. stream   gor NSLog.
#   broad    gor + mpv + Python os_log. full   no predicate; last resort.

# ── source backups (block 174): mirror + per-build backup, nothing is deleted ─
# Tracked: Sources/, Package.swift, build.sh, Resources/. Not tracked:
# .build, whisper-cpp-src, gor.xcworkspace, .gor-*, gor.app*.
mirror_dir="$project_root/.gor-mirror"
backups_dir="$project_root/.gor-backups"
big_file_bytes=209715200   # 200 MB
big_file_prompt_printed=false

gor_tree_files() {  # relative paths of the tracked tree under $1, sorted
    ( cd "$1" && find Sources Package.swift build.sh gor-capture-channel.py Tests Resources Packages scripts tools architecture docs ARCHITECTURE.md VENDOR.md ffmpeg-provider.lock .swift-format plan models -type f 2>/dev/null | sort )
}

# Confirm backup of a changed/deleted file over 200 MB (174a: applies to the
# 3 whisper models). No tty: stop and change nothing.
gor_big_file_confirm() {
    local rel="$1" ans
    if [ "$big_file_prompt_printed" != true ]; then
        echo "      note: deleting a model from source does not free disk while the mirror or a backup still holds it."
        big_file_prompt_printed=true
    fi
    if [ ! -t 0 ]; then
        echo "source backup: $rel is over 200 MB and needs a y/n answer, but there is no terminal; stopping, nothing changed." >&2
        exit 1
    fi
    printf '      back up large file %s (>200 MB)? [y/n] ' "$rel"
    read -r ans
    case "$ans" in y|Y|yes) return 0 ;; *) echo "source backup: declined $rel; stopping, nothing changed." >&2; exit 1 ;; esac
}

# Diff the tracked tree against the mirror; fills sb_changed/sb_added/
# sb_deleted. One python3 pass: the bash loop's per-file stat forks are the
# suspected cost behind the 42s/46s mirror-diff intervals measured on the
# 261103-003150 and -003455 builds (10,112 tracked files; the zero-change
# build proves the scan alone can take 46s because the backup write
# early-returns; the run-1 split between scan and copy is not measured).
# Identical 174d semantics: size + ns mtime equal means unchanged, no read;
# different falls back to a full byte compare, so a touch-only change stays
# unchanged. Accepted risk (owner, 174d): same size + same ns mtime +
# different bytes needs a deliberate touch -r.
# find -type f parity: regular files only, symlinks never followed or listed.
# Types come from lstat: isfile/isdir hide stat failures as "absent", which
# could misclassify an unreadable subtree as deletions/additions. Only a
# MISSING tracked root (ENOENT on Sources/Package.swift/build.sh/Resources)
# is skipped silently, matching find 2>/dev/null; every other readdir/stat/
# read error - including a file vanishing mid-scan - stops the build before
# anything is written. The exchange file is NUL-delimited, so filenames with
# tabs or newlines are carried verbatim; an unknown record kind stops loudly.
gor_mirror_diff() {
    sb_changed=(); sb_added=(); sb_deleted=()
    local sb_lists kind rel
    [ -x /usr/bin/python3 ] || { echo "mirror diff: /usr/bin/python3 is missing or not executable; stopping, nothing changed" >&2; exit 1; }
    sb_lists=$(mktemp /tmp/gor-mirror-diff.XXXXXX) || { echo "mirror diff: mktemp failed; stopping, nothing changed" >&2; exit 1; }
    /usr/bin/python3 - "$project_root" "$mirror_dir" "$sb_lists" <<'PY_DIFF' || { echo "mirror diff failed; stopping, nothing changed" >&2; rm -f "$sb_lists"; exit 1; }
import os, stat as statmod, sys
root, mirror, out = sys.argv[1], sys.argv[2], sys.argv[3]
TRACKED = ["Sources", "Package.swift", "build.sh", "Resources", "Packages", "gor-capture-channel.py", "Tests", "scripts", "tools", "architecture", "docs", "ARCHITECTURE.md", "VENDOR.md", "ffmpeg-provider.lock", ".swift-format", "plan", "models"]

def fail(err):
    raise err

def tree_files(base):
    rels = []
    for item in TRACKED:
        p = os.path.join(base, item)
        try:
            st = os.lstat(p)
        except FileNotFoundError:
            continue  # optional tracked root absent - same as find 2>/dev/null
        if statmod.S_ISLNK(st.st_mode):
            continue
        if statmod.S_ISREG(st.st_mode):
            rels.append(item)
        elif statmod.S_ISDIR(st.st_mode):
            for dirpath, dirnames, filenames in os.walk(p, followlinks=False, onerror=fail):
                for name in filenames:
                    full = os.path.join(dirpath, name)
                    st = os.lstat(full)  # any failure (incl. mid-scan removal) stops the build
                    if statmod.S_ISREG(st.st_mode):
                        rels.append(os.path.relpath(full, base))
                    elif statmod.S_ISDIR(st.st_mode):
                        # os.walk puts an entry here when its internal type
                        # check failed; never silently skip what may be a tree.
                        raise OSError("walk misclassified a directory: " + full)
    return sorted(rels)

def stat_key(path):
    st = os.lstat(path)
    return (st.st_size, st.st_mtime_ns)

def same_bytes(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        while True:
            ca, cb = fa.read(1 << 20), fb.read(1 << 20)
            if ca != cb:
                return False
            if not ca:
                return True

def main():
    src, mir = tree_files(root), tree_files(mirror)
    mir_set, src_set = set(mir), set(src)
    changed, added, deleted = [], [], []
    for rel in src:
        if rel not in mir_set:
            added.append(rel)
        elif stat_key(os.path.join(mirror, rel)) != stat_key(os.path.join(root, rel)):
            if not same_bytes(os.path.join(mirror, rel), os.path.join(root, rel)):
                changed.append(rel)
    for rel in mir:
        if rel not in src_set:
            deleted.append(rel)
    with open(out, "wb") as f:
        for kind, lst in (("changed", changed), ("added", added), ("deleted", deleted)):
            for rel in lst:
                f.write(kind.encode() + b"\0" + rel.encode() + b"\0")

try:
    main()
except Exception as err:
    sys.stderr.write("mirror diff error: %s: %s\n" % (type(err).__name__, err))
    sys.exit(1)
PY_DIFF
    while IFS= read -r -d '' kind && IFS= read -r -d '' rel; do
        case "$kind" in
            changed) sb_changed+=("$rel");;
            added)   sb_added+=("$rel");;
            deleted) sb_deleted+=("$rel");;
            *) echo "mirror diff: corrupt record from scanner; stopping, nothing changed" >&2; rm -f "$sb_lists"; exit 1 ;;
        esac
    done < "$sb_lists"
    rm -f "$sb_lists"
}

# Write .gor-backups/<ts>/ with the mirror's old copy of each changed/deleted
# file (cp -c clones, same relative path) plus changes.txt. Runs BEFORE the
# swift build. Sets sb_backup_dir; empty when there is nothing to back up.
sb_backup_dir=""
gor_backup_write() {
    local ts rel src
    ts=$(date +%y%m%d-%H%M%S)
    sb_backup_dir=""
    if [ ${#sb_changed[@]} -eq 0 ] && [ ${#sb_added[@]} -eq 0 ] && [ ${#sb_deleted[@]} -eq 0 ]; then return 0; fi
    for rel in "${sb_changed[@]}" "${sb_deleted[@]}"; do
        if [ -f "$mirror_dir/$rel" ] && [ "$(stat -f %z "$mirror_dir/$rel")" -gt "$big_file_bytes" ]; then
            gor_big_file_confirm "$rel"
        fi
    done
    sb_backup_dir="$backups_dir/$ts"
    # 174c: one timestamp name; a same-second collision stops loudly.
    [ -e "$sb_backup_dir" ] && { echo "exists: $sb_backup_dir — stopping, nothing moved" >&2; exit 1; }
    mkdir -p "$sb_backup_dir"
    for rel in "${sb_changed[@]}" "${sb_deleted[@]}"; do
        src="$mirror_dir/$rel"; mkdir -p "$sb_backup_dir/$(dirname "$rel")"
        cp -c "$src" "$sb_backup_dir/$rel" || { echo "source backup: cp -c failed for $rel" >&2; exit 1; }
    done
    : > "$sb_backup_dir/changes.txt"
    for rel in "${sb_changed[@]}";  do printf 'changed\t%s\n'  "$rel" >> "$sb_backup_dir/changes.txt"; done
    for rel in "${sb_added[@]}";    do printf 'added\t%s\n'    "$rel" >> "$sb_backup_dir/changes.txt"; done
    for rel in "${sb_deleted[@]}";  do printf 'deleted\t%s\n'  "$rel" >> "$sb_backup_dir/changes.txt"; done
    echo "      source backup: $sb_backup_dir (${#sb_changed[@]} changed, ${#sb_added[@]} added, ${#sb_deleted[@]} deleted)"
}

# First run only: clone the whole tracked tree into the mirror (one-time,
# APFS cp -c; 174a: time it and report the number).
gor_mirror_init() {
    local t0 t1 n
    echo "      first source mirror: cloning the tracked tree with cp -c..."
    t0=$(date +%s)
    ( cd "$project_root" && gor_tree_files "$project_root" | while IFS= read -r rel; do
        mkdir -p "$mirror_dir/$(dirname "$rel")"
        cp -c -p "$rel" "$mirror_dir/$rel" || { echo "source mirror: cp -c failed for $rel" >&2; exit 1; }
      done ) || exit 1
    t1=$(date +%s)
    n=$(gor_tree_files "$mirror_dir" | wc -l | tr -d ' ')
    echo "      source mirror: $n files cloned in $((t1-t0))s (APFS clones; no real copy cost until a file changes)"
}

# After a successful swap only: clone changed/added files in, take deleted out.
# The mirror's old copies are already in the backup, so nothing is lost.
# The old changed bytes are already retained by gor_backup_write. Mirror
# leaves preserve source modes, including 0444. Force only this exact temp
# rename so BSD mv never asks an invisible tty question through the log pipe.
# No source file or backup is changed; cp failure still refuses the rename.
gor_mirror_update() {
    local rel
    for rel in "${sb_changed[@]}" "${sb_added[@]}"; do
        mkdir -p "$mirror_dir/$(dirname "$rel")"
        cp -c -p "$project_root/$rel" "$mirror_dir/$rel.tmp" && mv -f "$mirror_dir/$rel.tmp" "$mirror_dir/$rel" || { echo "mirror update: cp -c failed for $rel" >&2; exit 1; }
    done
    for rel in "${sb_deleted[@]}"; do
        rm -f "$mirror_dir/$rel"
    done
}

gor_mirror_note_failure() {
    if [ -n "$sb_backup_dir" ] && [ -f "$sb_backup_dir/changes.txt" ]; then
        echo "build failed" >> "$sb_backup_dir/changes.txt"
    fi
}

gor_backups_size_report() {
    if [ -d "$backups_dir" ]; then
        echo "      .gor-backups total: $(du -sh "$backups_dir" 2>/dev/null | awk '{print $1}') (backups are never deleted by build.sh; pruning waits for the owner's word)"
    fi
}

# ── --rollback [yymmdd-hhmmss] (block 174): restore a backup, undoably ───────
gor_rollback() {
    local ts="${1:-}" target line kind rel rb_dir
    if [ -z "$ts" ]; then
        target=$(ls -1d "$backups_dir"/*/ 2>/dev/null | sort | tail -1)
    else
        target="$backups_dir/$ts/"
    fi
    if [ -z "$target" ] || [ ! -f "${target}changes.txt" ]; then
        echo "rollback: no backup folder found${ts:+ for $ts} in $backups_dir" >&2; exit 1
    fi
    target="${target%/}"
    echo "rollback: restoring from $target"
    # First back up the CURRENT versions of the files about to be restored -
    # rollback is itself undoable.
    rb_dir="$backups_dir/$(date +%y%m%d-%H%M%S)-pre-rollback"
    # 174c: one timestamp name; a same-second collision stops loudly.
    [ -e "$rb_dir" ] && { echo "exists: $rb_dir — stopping, nothing moved" >&2; exit 1; }
    mkdir -p "$rb_dir"
    : > "$rb_dir/changes.txt"
    while IFS=$'\t' read -r kind rel; do
        case "$kind" in
            changed|deleted)
                if [ -f "$project_root/$rel" ]; then
                    mkdir -p "$rb_dir/$(dirname "$rel")"
                    cp -c "$project_root/$rel" "$rb_dir/$rel" || { echo "rollback: cp -c failed for current $rel" >&2; exit 1; }
                    printf 'changed\t%s\n' "$rel" >> "$rb_dir/changes.txt"
                fi ;;
        esac
    done < "$target/changes.txt"
    # Restore old bytes; move "added" files into the pre-rollback folder
    # instead of removing them.
    while IFS=$'\t' read -r kind rel; do
        case "$kind" in
            changed|deleted)
                mkdir -p "$project_root/$(dirname "$rel")"
                cp -c "$target/$rel" "$project_root/$rel.tmp" && mv "$project_root/$rel.tmp" "$project_root/$rel" || { echo "rollback: restore failed for $rel" >&2; exit 1; }
                echo "      restored $rel" ;;
            added)
                if [ -f "$project_root/$rel" ]; then
                    mkdir -p "$rb_dir/$(dirname "$rel")"
                    mv "$project_root/$rel" "$rb_dir/$rel"
                    printf 'added\t%s\n' "$rel" >> "$rb_dir/changes.txt"
                    echo "      moved aside (was added) $rel"
                fi ;;
        esac
    done < "$target/changes.txt"
    echo "      pre-rollback state saved at $rb_dir"
    echo "rollback: source restored; running a normal build now."
    # fall through to the normal build path
}

# ── block 176 item 3: gor-verified tag flags (local sidecar tag; pushed only
#    by the owner's word — never by these commands) ─────────────────────────
gor_verified_tag() { printf '%s' "${GOR_VERIFIED_TAG:-gor-verified}"; }
gor_sidecar() { printf '%s' "${GOR_DST:-$HOME/Downloads/gor-repo-sync}"; }
gor_sidecar_branch() { printf '%s' "${GOR_BRANCH:-mac-source-sync-20261103}"; }

gor_mark_verified() {
    local sync_dir tag
    sync_dir="$(gor_sidecar)"; tag="$(gor_verified_tag)"
    [ -d "$sync_dir/.git" ] || { echo "--verified: no sidecar clone at $sync_dir" >&2; exit 1; }
    git -C "$sync_dir" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "--verified: sidecar has no HEAD commit" >&2; exit 1; }
    git -C "$sync_dir" tag -f "$tag" HEAD || { echo "--verified: tag failed" >&2; exit 1; }
    echo "verified: $tag -> $(git -C "$sync_dir" rev-parse --short HEAD) (local tag only)"
}

gor_print_unverified() {
    local sync_dir tag
    sync_dir="$(gor_sidecar)"; tag="$(gor_verified_tag)"
    if ! git -C "$sync_dir" rev-parse --verify "$tag" >/dev/null 2>&1; then
        echo "unverified: no $tag tag set" >&2
        exit 1
    fi
    local n
    n=$(git -C "$sync_dir" log --oneline "$tag..HEAD" -- archive/gor | wc -l | tr -d ' ')
    if [ "$n" = "0" ]; then
        echo "unverified: nothing since $tag ($(git -C "$sync_dir" rev-parse --short "$tag"))"
    else
        git -C "$sync_dir" log --oneline "$tag..HEAD" -- archive/gor
    fi
}

# Shared backup-first tree installer (176c): makes the project's tracked tree
# match $1 exactly - additions, changes, deletions - with the pre-state saved
# under .gor-backups/<ts>-pre-<label> using the shipped changes.txt kinds.
# Safe to run from a snapshot: build.sh itself may be among the replaced files.
# Called both by the installer and the new continuation. An old installer can install this
# build.sh without knowing fixtures, so --update-build repairs that first-upgrade gap before tests.
gor_install_selftest_fixtures() {
    local src="$1" rb_dir="$2"
    # Test fixtures ship outside capture roots, like the test entry point. Add/change only,
    # backed up with the same rollback contract; absent overlay fixtures never imply deletion.
    local fixture rel
    for fixture in vr180-look-pre-fill.lua vr180-look-pre-param.lua; do
        rel="selftest-fixtures/$fixture"
        [ -f "$src/$rel" ] || { echo "      install: missing required fixture $rel" >&2; exit 1; }
        if [ ! -f "$project_root/$rel" ] || ! cmp -s "$src/$rel" "$project_root/$rel"; then
            mkdir -p "$rb_dir" || exit 1
            if [ -f "$project_root/$rel" ]; then
                mkdir -p "$rb_dir/selftest-fixtures" || exit 1
                cp -p "$project_root/$rel" "$rb_dir/$rel" || exit 1
                printf 'changed\t%s\n' "$rel" >> "$rb_dir/changes.txt"
            else
                printf 'added\t%s\n' "$rel" >> "$rb_dir/changes.txt"
            fi
            mkdir -p "$project_root/selftest-fixtures" || exit 1
            cp -p "$src/$rel" "$project_root/$rel.tmp" && mv "$project_root/$rel.tmp" "$project_root/$rel" || exit 1
        fi
    done
    for fixture in vr180-look-pre-fill.lua vr180-look-pre-param.lua; do
        cmp -s "$src/selftest-fixtures/$fixture" "$project_root/selftest-fixtures/$fixture" || {
            echo "fixture readback failed: $fixture" >&2; exit 1;
        }
    done
}

gor_install_tree() {
    local src="$1" label="$2" rel rb_dir pf enum_dir enum_rc=0 op
    local it_changed=() it_added=() it_deleted=() ops=()
    [ -d "$src" ] || { echo "      source tree missing at $src; nothing changed." >&2; exit 1; }
    [ -d "$src/Sources" ] || { echo "      source tree at $src has no Sources/; nothing changed." >&2; exit 1; }
    [ -d "$project_root/Sources" ] || { echo "      project root has no Sources/; nothing changed." >&2; exit 1; }
    # Enumerate both trees with error-checked finds BEFORE any mutation, so a
    # decline, a missing tty, or an enumeration failure leaves the project
    # byte-identical. Only operands that exist are enumerated (build.sh or
    # Resources may be absent in a legitimate tree shape); any real find error
    # fails closed instead of silently producing a partial list.
    enum_dir=$(mktemp -d /tmp/gor-install-enum.XXXXXX) || { echo "      cannot enumerate trees; nothing changed." >&2; exit 1; }
    for op in Sources Package.swift build.sh gor-capture-channel.py Tests Resources Packages scripts tools architecture docs ARCHITECTURE.md VENDOR.md ffmpeg-provider.lock .swift-format plan models; do [ -e "$project_root/$op" ] && ops+=("$op"); done
    if [ ${#ops[@]} -eq 0 ]; then echo "      project tree is empty; nothing changed." >&2; rm -rf "$enum_dir"; exit 1; fi
    ( cd "$project_root" && find "${ops[@]}" -type f ) > "$enum_dir/proj.txt" 2>"$enum_dir/proj.err" || enum_rc=1
    ops=()
    for op in Sources Package.swift build.sh gor-capture-channel.py Tests Resources Packages scripts tools architecture docs ARCHITECTURE.md VENDOR.md ffmpeg-provider.lock .swift-format plan models; do [ -e "$src/$op" ] && ops+=("$op"); done
    ( cd "$src" && find "${ops[@]}" -type f ) > "$enum_dir/src.txt" 2>"$enum_dir/src.err" || enum_rc=1
    if [ "$enum_rc" != 0 ] || [ -s "$enum_dir/proj.err" ] || [ -s "$enum_dir/src.err" ]; then
        echo "      source enumeration failed; nothing changed." >&2
        rm -rf "$enum_dir"; exit 1
    fi
    while IFS= read -r rel; do
        if [ -f "$project_root/$rel" ]; then
            if ! cmp -s "$src/$rel" "$project_root/$rel" ||
               [ "$(stat -f%Lp "$src/$rel" 2>/dev/null || stat -c %a "$src/$rel")" != "$(stat -f%Lp "$project_root/$rel" 2>/dev/null || stat -c %a "$project_root/$rel")" ]; then it_changed+=("$rel"); fi
        else
            it_added+=("$rel")
        fi
    done < "$enum_dir/src.txt"
    # 176c-fix: the delivered tree is a code-only OVERLAY, never an
    # authoritative full tree: vendor models under Resources/ are too large to
    # be captured to the branch, so they can never appear in src - and any
    # project file absent from src must NOT be classified as deleted. The
    # deletion class is disabled entirely; a future delivery that needs a file
    # removed must carry an explicit removal list (none does today).
    # Owner's explicit Nov1 consolidation: retire ONLY these two known logger
    # sources when the complete combined replacement is present. Overlay
    # omissions still NEVER imply deletion. Unknown local edits fail closed.
    if [ -f "$src/Sources/gor/Diag.swift" ]; then
        if grep -q '^enum ThreadCpuDiag {' "$src/Sources/gor/Diag.swift" &&
           grep -q '^enum MainThreadDiag {' "$src/Sources/gor/Diag.swift"; then
            local old_diag expected_diag actual_diag
            for old_diag in ThreadCpuDiag MainThreadDiag; do
                rel="Sources/gor/$old_diag.swift"
                [ ! -f "$src/$rel" ] || { echo "diag consolidation: duplicate delivered source $rel" >&2; exit 1; }
                [ -e "$project_root/$rel" ] || continue
                [ -f "$project_root/$rel" ] && [ ! -L "$project_root/$rel" ] || { echo "diag consolidation: unexpected local file $rel" >&2; exit 1; }
                case "$old_diag" in
                    ThreadCpuDiag) expected_diag=aebe13945e48180d0e2c9554b7a342bfbaa421a92a57286ea530aa9c11a6db46 ;;
                    MainThreadDiag) expected_diag=0596077bd76cd8341999fa60eff4185b5ed112bb849d073fa76a0630a3a8e2c9 ;;
                esac
                actual_diag=$(shasum -a 256 "$project_root/$rel") || exit 1
                actual_diag=${actual_diag%% *}
                [ "$actual_diag" = "$expected_diag" ] || { echo "diag consolidation: local edits in $rel; nothing changed" >&2; exit 1; }
                it_deleted+=("$rel")
            done
        fi
    fi
    # Viewport S4a relocation: GorFit.swift moved byte-identical to
    # Sources/gor/Viewport/Viewport.swift. The overlay never deletes, so the
    # stale copy must be retired explicitly or both files compile and every
    # GorCropFilter/GorVideoFit/GorCropPlan/GorClampFence use is ambiguous.
    # Same fail-closed rule as the diag consolidation: retire only the exact
    # delivered byte stream; any local edit stops the install untouched.
    if [ -f "$src/Sources/gor/Viewport/Viewport.swift" ]; then
        if grep -q '^enum GorVideoFit {' "$src/Sources/gor/Viewport/Viewport.swift" &&
           grep -q '^struct GorCropFilter' "$src/Sources/gor/Viewport/Viewport.swift"; then
            local old_gorfit expected_gorfit actual_gorfit
            rel="Sources/gor/GorFit.swift"
            [ ! -f "$src/$rel" ] || { echo "viewport relocation: duplicate delivered source $rel" >&2; exit 1; }
            if [ -e "$project_root/$rel" ]; then
                [ -f "$project_root/$rel" ] && [ ! -L "$project_root/$rel" ] || { echo "viewport relocation: unexpected local file $rel" >&2; exit 1; }
                expected_gorfit=53752e4797fc2d252e0e813665b775d385c7aa960aa50209214b37f197ca3e65
                actual_gorfit=$(shasum -a 256 "$project_root/$rel") || exit 1
                actual_gorfit=${actual_gorfit%% *}
                [ "$actual_gorfit" = "$expected_gorfit" ] || { echo "viewport relocation: local edits in $rel; nothing changed" >&2; exit 1; }
                it_deleted+=("$rel")
            fi
        fi
    fi
    rm -rf "$enum_dir"
    # ALL confirmations run here, BEFORE the backup and any project mutation:
    # one prompt per big file the install will overwrite or delete. Lists are
    # arrays, so the prompt's stdin is the real terminal, not a list file.
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_deleted[@]+"${it_deleted[@]}"}; do
        [ -f "$project_root/$rel" ] || continue
        pf=$(stat -f%z "$project_root/$rel" 2>/dev/null || stat -c %s "$project_root/$rel" 2>/dev/null || echo 0)
        case "$pf" in ''|*[!0-9]*) pf=0 ;; esac
        if [ "$pf" -gt "$big_file_bytes" ]; then gor_big_file_confirm "$rel"; fi
    done
    # Mutation point. Backup first (shipped changes.txt kinds so --rollback can
    # undo it), then apply.
    rb_dir="$backups_dir/$(date +%y%m%d-%H%M%S)-pre-$label"
    # 174c: one timestamp name; a same-second collision stops loudly.
    [ -e "$rb_dir" ] && { echo "exists: $rb_dir — stopping, nothing moved" >&2; exit 1; }
    mkdir -p "$rb_dir" || exit 1
    : > "$rb_dir/changes.txt"
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_deleted[@]+"${it_deleted[@]}"}; do
        mkdir -p "$rb_dir/$(dirname "$rel")"
        cp -p "$project_root/$rel" "$rb_dir/$rel" || { echo "      source backup: cp failed for $rel" >&2; exit 1; }
    done
    for rel in ${it_changed[@]+"${it_changed[@]}"}; do printf 'changed\t%s\n' "$rel" >> "$rb_dir/changes.txt"; done
    for rel in ${it_added[@]+"${it_added[@]}"};   do printf 'added\t%s\n'   "$rel" >> "$rb_dir/changes.txt"; done
    for rel in ${it_deleted[@]+"${it_deleted[@]}"}; do printf 'deleted\t%s\n' "$rel" >> "$rb_dir/changes.txt"; done
    if [ "$label" = diag-consolidation ] && [ "${#it_deleted[@]}" -gt 0 ]; then
        # The previous overlay already added this file. Undo of THIS migration
        # must park it too when it restores the two original enum definitions.
        printf 'added\tSources/gor/Diag.swift\n' >> "$rb_dir/changes.txt"
    fi
    gor_install_selftest_fixtures "$src" "$rb_dir"
    # The pinned entry-point file ships outside the capture find set (the Mac's
    # capture/push gates never see it); back it up when the install changes it.
    if [ -f "$project_root/gor-selftest.sh" ] && [ -f "$src/gor-selftest.sh" ] && ! cmp -s "$project_root/gor-selftest.sh" "$src/gor-selftest.sh"; then
        cp -p "$project_root/gor-selftest.sh" "$rb_dir/gor-selftest.sh" || { echo "      source backup: cp failed for gor-selftest.sh" >&2; exit 1; }
        printf 'changed\t%s\n' "gor-selftest.sh" >> "$rb_dir/changes.txt"
    fi
    echo "      source backup: $rb_dir ($label)"
    # Apply: per-file .tmp+mv (the snapshot re-exec guard covers build.sh itself).
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_added[@]+"${it_added[@]}"}; do
        mkdir -p "$project_root/$(dirname "$rel")"
        cp -p "$src/$rel" "$project_root/$rel.tmp" && mv "$project_root/$rel.tmp" "$project_root/$rel" || { echo "      install: copy failed for $rel" >&2; exit 1; }
    done
    if [ -f "$src/gor-selftest.sh" ]; then
        if [ ! -f "$project_root/gor-selftest.sh" ] || ! cmp -s "$src/gor-selftest.sh" "$project_root/gor-selftest.sh"; then
            cp -p "$src/gor-selftest.sh" "$project_root/gor-selftest.sh.tmp" && mv "$project_root/gor-selftest.sh.tmp" "$project_root/gor-selftest.sh" || { echo "      install: copy failed for gor-selftest.sh" >&2; exit 1; }
        fi
    fi
    # Only explicit, hash-checked logger consolidation removals, already backed
    # up in changes.txt as deleted. No arbitrary absent-overlay file is removed.
    for rel in ${it_deleted[@]+"${it_deleted[@]}"}; do
        if ! rm -f "$project_root/$rel"; then
            echo "diag consolidation: retirement failed; restoring both originals" >&2
            local restore_rel restore_failed=false
            for restore_rel in ${it_deleted[@]+"${it_deleted[@]}"}; do
                cp -p "$rb_dir/$restore_rel" "$project_root/$restore_rel" || restore_failed=true
            done
            if [ "$restore_failed" = false ]; then
                # Avoid duplicate enums after restoring old files. Preserve the
                # newly installed replacement in this run's backup, never delete it.
                mv "$project_root/Sources/gor/Diag.swift" "$rb_dir/Diag.swift.failed-install" || {
                    echo "diag consolidation: replacement could not be parked; build refused" >&2; exit 1;
                }
            else
                echo "diag consolidation: rollback incomplete; backup=$rb_dir; build refused" >&2
            fi
            exit 1
        fi
    done
}

gor_rollback_verified() {
    local sync_dir tag tmp
    sync_dir="$(gor_sidecar)"; tag="$(gor_verified_tag)"
    git -C "$sync_dir" rev-parse --verify "$tag" >/dev/null 2>&1 || { echo "--rollback verified: no $tag tag set" >&2; exit 1; }
    tmp="$(mktemp -d /tmp/gor-rollback-verified.XXXXXX)" || exit 1
    if ! git -C "$sync_dir" archive "$tag" archive/gor | tar -x -C "$tmp"; then
        rm -rf "$tmp"; echo "--rollback verified: cannot extract the tag tree" >&2; exit 1
    fi
    [ -d "$tmp/archive/gor" ] || { rm -rf "$tmp"; echo "--rollback verified: tag tree has no archive/gor" >&2; exit 1; }
    echo "rollback verified: restoring $tag ($(git -C "$sync_dir" rev-parse --short "$tag"))"
    gor_install_tree "$tmp/archive/gor" "rollback-verified"
    rm -rf "$tmp"
    echo "rollback verified: source restored; running a normal build now."
}

# ── block 176c: --update (ff-only) + selftest + result capture ─────────────
# Syncs the sidecar fast-forward-only, installs archive/gor into the project
# (backup-first; this file may be among the replaced bytes - the snapshot
# re-exec above keeps the run safe), then re-execs the freshly installed
# build.sh for build + selftest + result push. Divergence: print state,
# change nothing, stop. Never rebases, never forces, never touches main.
gor_update_run() {
    export GOR_UPDATE_T0=$(date +%s)
    [ -z "${GOR_SELFTEST:-}" ] || { echo "--update inside the selftest is not allowed" >&2; exit 1; }
    local sync_dir branch
    sync_dir="$(gor_sidecar)"; branch="$(gor_sidecar_branch)"
    [ -d "$sync_dir/.git" ] || { echo "update: no sidecar clone at $sync_dir" >&2; exit 1; }
    case "$(git -C "$sync_dir" remote get-url origin)" in
        https://github.com/goreda/instinct.git|git@github.com:goreda/instinct.git) ;;
        *) echo 'update: unexpected sidecar origin; stopped'; exit 1;;
    esac
    git -C "$sync_dir" fetch origin "$branch" || { echo "update: fetch failed (network or auth)" >&2; exit 1; }
    [ "$(git -C "$sync_dir" symbolic-ref --quiet --short HEAD)" = "$branch" ] || { echo 'update: wrong sidecar branch'; exit 1; }
    /usr/bin/python3 - "$sync_dir" "origin/$branch" <<'GOR_LOCAL_FILES'
import os,sys,subprocess,stat
r,remote=sys.argv[1:]
def git(*a):return subprocess.check_output(['git','-C',r,*a])
if subprocess.run(['git','-C',r,'diff','--quiet','--']).returncode or subprocess.run(['git','-C',r,'diff','--cached','--quiet','--']).returncode:
 raise SystemExit('STOP: tracked sidecar files changed')
allowed={b'build-r6-candidate.sh',b'capture.log',b'sync.sh',b'sync.sh.install-prev',b'sync.sh.pre-r61-backup'}
others=[x for x in git('ls-files','--others','-z').split(b'\0') if x]
tracked=[x for x in git('ls-tree','-r','--name-only','-z',remote).split(b'\0') if x]
for p in others:
 if p not in allowed:raise SystemExit('STOP: unexpected untracked sidecar file (preserved)')
 full=os.path.join(r,os.fsdecode(p))
 if not stat.S_ISREG(os.lstat(full).st_mode):raise SystemExit('STOP: untracked sidecar entry is not a regular file')
 if any(t==p or t.startswith(p+b'/') or p.startswith(t+b'/') for t in tracked):raise SystemExit('STOP: incoming tracked tree collides with local file (preserved)')
print('PASS: tracked sidecar clean; known local operational files preserved, no incoming collision')
GOR_LOCAL_FILES
    local capture_helper="$project_root/gor-capture-channel.py"
    if [ ! -f "$capture_helper" ]; then
        capture_helper=$(mktemp "${TMPDIR:-/tmp}/gor-capture-helper.XXXXXXXX")
        git -C "$sync_dir" show "origin/$branch:archive/gor/gor-capture-channel.py" > "$capture_helper" || exit 1
    fi
    /usr/bin/python3 "$capture_helper" --repo "$sync_dir" update --source "$branch" --queue "$sync_dir/.git/gor-capture-pending" || exit 1
    local src_root="$sync_dir/archive/gor"
    [ -d "$src_root" ] || { echo "update: no archive/gor in the fetched branch" >&2; exit 1; }
    cp -p "$project_root/build.sh" "$project_root/.gor-last-working-build.sh" || exit 1
    echo "update: installing $(git -C "$sync_dir" rev-parse --short HEAD) from $branch"
    if ! /usr/bin/python3 "$src_root/tools/architecture.py" --root "$src_root" --integrity-only; then
        echo 'update integrity: release bytes verification failed; prior source/app retained; no build or launch' >&2
        exit 1
    fi
    if [ -f "$src_root/Tests/Architecture/manifest_tree_test.py" ] && ! /usr/bin/python3 "$src_root/Tests/Architecture/manifest_tree_test.py" >/dev/null 2>&1; then
        echo 'update delivery gate: a listed file differs from the committed tree or a tracked file has no delivery row; prior source/app retained' >&2; exit 1
    fi
    gor_install_tree "$src_root" "update"
    cmp -s "$src_root/gor-capture-channel.py" "$project_root/gor-capture-channel.py" || { echo 'update: capture helper install/readback failed; build not started' >&2; exit 1; }
    echo "update: installed; restarting in the new build.sh for build + selftest"
    GOR_SNAPSHOT_OLD="${GOR_SNAPSHOT_PATH:-}" GOR_SNAPSHOT= GOR_SNAPSHOT_PATH= GOR_SNAPSHOT_ORIG= \
        GOR_BUILD_LOCK_HELD=1 exec bash "$project_root/build.sh" --update-build
    echo "update: re-exec failed" >&2
    exit 1
}

gor_install_architecture_assets() {
    local source_root="$1" staged relative
    [ -f "$source_root/ARCHITECTURE.md" ] || { echo "architecture map missing from source" >&2; exit 1; }
    staged=$(mktemp -d /tmp/gor-architecture-assets.XXXXXXXX) || exit 1
    mkdir -p "$staged/Sources" || exit 1
    for relative in Packages scripts tools architecture docs selftest-fixtures ARCHITECTURE.md VENDOR.md ffmpeg-provider.lock .swift-format plan models; do
        [ -e "$source_root/$relative" ] || { echo "architecture asset missing: $relative" >&2; exit 1; }
        cp -Rp "$source_root/$relative" "$staged/$relative" || exit 1
    done
    /usr/bin/python3 - "$source_root" "$staged" <<'GOR_ARCH_STAGE' || exit 1
from pathlib import Path
import sys
source, staged = map(Path, sys.argv[1:])
for path in staged.rglob('*'):
    if path.is_file():
        original = source / path.relative_to(staged)
        if path.read_bytes() != original.read_bytes() or path.stat().st_mode & 0o777 != original.stat().st_mode & 0o777:
            raise SystemExit('architecture staging bytes/mode mismatch')
GOR_ARCH_STAGE
    if ! /usr/bin/python3 "$staged/scripts/arch_check.py" --root "$source_root" --integrity-only; then
        echo 'architecture bootstrap: staged gate warning; no architecture assets changed' >&2
        rm -rf "$staged"
        return 1
    fi
    gor_install_tree "$staged" "architecture-bootstrap"
    [ -d "$project_root/Packages" ] || mkdir -p "$project_root/Packages"
    printf '%s\n' 'Packages installed (M1 empty fixture; no GorKit target)' >> "$project_root/.gor-architecture-last.txt"
    for relative in scripts/arch-check.sh scripts/arch_check.py scripts/linux-model-tests.py ARCHITECTURE.md .swift-format plan/QUEUE.md; do
        cmp -s "$source_root/$relative" "$project_root/$relative" || { echo "architecture asset readback failed: $relative" >&2; exit 1; }
    done
    rm -rf "$staged" # this invocation's private staged overlay only
}
# ── gor_selftest (176b): the kit tests itself on the Mac. One command, no
#    eyes needed; every result is a PASS/FAIL line; ends with one paste-back
#    line and the one manual check. Child builds are ordinary build.sh runs
#    (no recursion: GOR_SELFTEST guards --selftest/--update). ───────────────
gor_st_wait_source_lock() {
    local n=0
    while [ -d "${GOR_SRC:-$project_root}/.gor-source.lock" ] && [ "$n" -lt 360 ]; do sleep 0.5; n=$((n+1)); done
    [ ! -d "${GOR_SRC:-$project_root}/.gor-source.lock" ]
}
gor_selftest() {
    local selftest_mode="${1:-lifetime}"
    # The delivery legs always qualify the shipping mpv backend. Optional GorAV
    # evidence is separate and can never change t1/l1-l4 or block an update.
    local requested_test_engine="${GOR_ENGINE:-mpv}"
    export GOR_ENGINE=mpv
    [ -z "${GOR_SELFTEST:-}" ] || { echo "selftest: recursive invocation refused" >&2; exit 1; }
    export GOR_SELFTEST=1
    gor_release_build_lock   # child builds take the build lock individually (176 item 1)
    # --update-build inherited this flag across an exec with the SAME pid.
    # Selftest children have new pids and must acquire their own locks.
    unset GOR_BUILD_LOCK_HELD
    local app="$project_root/gor.app" bin="$project_root/gor.app/Contents/MacOS/gor"
    local qlog="$HOME/Library/Logs/gor/quit-debug.log"
    local buildlog="$project_root/.gor-selftest-build.log"
    local results="$project_root/.gor-selftest-last.txt"
    local pass=0 fail=0 t0 s
    t0=$(date +%s)
    # Keep previous feature failures visible as historical evidence, never as this run's verdict.
    local prior_features=""
    if [ -f "$results" ]; then
        prior_features=$(sed -n -E 's/^HISTORICAL (FAIL .*)/\1/p; /^FAIL (r[1-4]-|v[1-3]-|vr-|av-|ipd-)/p' "$results" | sort -u)
    fi
    : > "$results"
    if [ -f "$project_root/.gor-architecture-last.txt" ]; then cat "$project_root/.gor-architecture-last.txt" >> "$results"; fi
    if [ -n "$prior_features" ]; then
        printf '%s\n' 'HISTORICAL open feature failures from previous run (not rerun in lifecycle-only mode):' >> "$results"
        printf '%s\n' "$prior_features" | sed 's/^/HISTORICAL /' >> "$results"
    fi
    update_results_fresh=true
    : > "$buildlog"
    { printf 'Swift toolchain: '; swift --version; } >> "$buildlog" 2>&1 || true
    local uid pattern vpat
    uid=$(id -u)
    pattern="^$(printf '%s' "$bin" | sed 's/[][\.^$*+?(){}|]/\\&/g')([[:space:]]|$)"
    vpat="$(printf '%s' "$project_root/Resources/vendor" | sed 's/[][\.^$*+?(){}|]/\\&/g')"
    local store_not_run=false
    st_note() { echo "$*"; printf '%s\n' "$*" >> "$results"; }
    st_pass() { st_note "PASS $1${2:+  ($2)}"; pass=$((pass+1)); }
    st_fail() { st_note "FAIL $1: $2"; fail=$((fail+1)); }
    st_running() { local p; p=$(/usr/bin/python3 "$project_root/tools/axes_acceptance.py" --list-interactive "$bin") || return 0; [ -n "$p" ]; }
    st_wait_running() { local n=0; while [ "$n" -lt $(( $1 * 2 )) ]; do st_running && return 0; sleep 0.5; n=$((n+1)); done; return 1; }
    st_wait_gone()    { local n=0; while [ "$n" -lt $(( $1 * 2 )) ]; do st_running || return 0; sleep 0.5; n=$((n+1)); done; return 1; }
    st_helpers_alive() { pgrep -u "$uid" -f "$vpat" >/dev/null 2>&1; }
    st_quit() { local out rc=0; out=$(/usr/bin/python3 "$project_root/tools/axes_acceptance.py" --stop-interactive "$bin" 2>&1) || rc=$?; st_note "$out"; return "$rc"; }

    # 176d: stop before any lifecycle launch if the actual vendor rejects EOF IPC.
    local mpv_options
    if ! mpv_options=$("$project_root/Resources/vendor/mpv/bin/mpv" --list-options 2>>"$buildlog") ||
       ! grep -Eq '^[[:space:]]*--input-ipc-client([[:space:]]|$)' <<< "$mpv_options"; then
        st_fail lifeline-vendor-option "input-ipc-client unavailable; stopped, no fallback"
        return 1
    fi

    # --update already completed its build before entering this function.
    # Standalone selftests build once; never double-build an update.
    s=$(date +%s)
    local t1_build_ok=true
    if [ "${update_mode:-false}" != true ]; then
        /usr/bin/python3 "$project_root/tools/gor_step.py" "selftest build" bash "$project_root/build.sh" --no-launch >>"$buildlog" 2>&1 || t1_build_ok=false
    fi
    if [ "$t1_build_ok" = true ]; then
        st_quit || return 1
        # arch196e E1 collection runs inside this release's normal update, before gor launches.
        if [ "${update_mode:-false}" = true ]; then
            local e1_rc=0 e1_out
            e1_out=$(/usr/bin/python3 "$project_root/tools/vision_e1_probe.py" 2>&1) || e1_rc=$?
            printf '%s\n' "$e1_out" | while IFS= read -r line; do st_note "$line"; done
            st_note "E1 collector_exit=$e1_rc (independent from application acceptance)"
        fi
        open -g -n "$app" --args --gor-no-activate || true
        if st_wait_running 120; then st_pass t1-build-launch "$(( $(date +%s) - s ))s"
        else st_fail t1-build-launch "app did not start after the build"; fi
    else st_fail t1-build-launch "build failed (see .gor-selftest-build.log)"; fi

    # capture health after t1: no new capture-failed flags in the sidecar
    local sync_dir_st; sync_dir_st="$(gor_sidecar)"
    if [ -d "$sync_dir_st" ]; then
        gor_st_wait_source_lock || true
        if ls "$sync_dir_st"/capture-failed.* >/dev/null 2>&1; then
            st_fail capture-after-t1 "capture-failed flag present in $sync_dir_st (see capture.log)"
        else
            st_pass capture-after-t1
        fi
    fi

    if [ "$selftest_mode" = full ]; then
    # Optional E1 has its own verdict; never increment lifecycle pass/fail counters.
    if [ "$requested_test_engine" = gorav ]; then
        if GOR_ENGINE=gorav bash "$project_root/Tests/PlayerBackend/selftest.sh" >>"$results" 2>&1; then :
        else st_note "FAIL gorav-e1 (optional; delivery-gate183 unchanged)"; fi
    fi
    # Block184 new feature legs are explicit full-only, never part of automatic lifecycle delivery.
    if sh "$project_root/Tests/Block185/run.sh" >>"$results" 2>&1; then st_pass 185-production-contracts; else st_fail 185-production-contracts "see fixture output"; fi
    if /usr/bin/python3 "$project_root/Tests/Block185/render-mpv.py" "$project_root/.gor-selftest-185-pngs" >>"$results" 2>&1; then st_pass 185a-production-render; else st_fail 185a-production-render "see fixture output and retained PNGs"; fi
    if sh "$project_root/Tests/VRProjection/run.sh" >>"$results" 2>&1; then st_pass 184-2-recognition; else st_fail 184-2-recognition "see fixture output"; fi
    if sh "$project_root/Tests/Block184/run.sh" >>"$results" 2>&1; then st_pass 184-3-5-7-contracts; else st_fail 184-3-5-7-contracts "see fixture output"; fi
    # t3: a launched build releases the build lock; a second build runs while
    # the app is still open (176 item 1), timed.
    s=$(date +%s)
    bash "$project_root/build.sh" --log off >>"$buildlog" 2>&1 &
    local a=$! n=0 lockfree=false saw_a_lock=false
    while [ "$n" -lt 36000 ]; do
        if [ "$(cat "$project_root/.gor-build.lock/pid" 2>/dev/null)" = "$a" ]; then saw_a_lock=true; fi
        if [ "$saw_a_lock" = true ] && [ ! -d "$project_root/.gor-build.lock" ] && st_running; then lockfree=true; break; fi
        kill -0 "$a" 2>/dev/null || break
        sleep 0.05; n=$((n+1))
    done
    if [ "$lockfree" != true ]; then
        st_fail t3-rebuild-while-open "first build's launch did not release the lock in time"
        kill "$a" 2>/dev/null || true; wait "$a" 2>/dev/null || true
    else
        if /usr/bin/python3 "$project_root/tools/gor_step.py" "selftest build" bash "$project_root/build.sh" --no-launch >>"$buildlog" 2>&1; then
            st_pass t3-rebuild-while-open "$(( $(date +%s) - s ))s"
        else
            st_fail t3-rebuild-while-open "second build failed while the app was open"
        fi
        wait "$a" 2>/dev/null || true
    fi

    # t3b: actual build + shipped --rollback while the real app stays open.
    # Isolate source/app/backups: rollback must never revert the current update.
    local rbtest rbcopy
    rbtest=$(mktemp -d "${TMPDIR:-/tmp}/gor-selftest-rollback.XXXXXXXX")
    rbcopy="$rbtest/proj"
    if /usr/bin/python3 - "$project_root" "$rbcopy" <<'GOR_ROLLBACK_COPY'
import os,shutil,sys,ctypes
from pathlib import Path
src,dst=map(Path,sys.argv[1:])
# clonefile provides cp -c cloning semantics, but unlike cp it NEVER falls back to
# byte copying on unsupported filesystems. Refuse before any large copy.
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True)
clone=lib.clonefile;clone.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int];clone.restype=ctypes.c_int
cloned_bytes=0
def clone_only(source,target):
    global cloned_bytes
    if clone(os.fsencode(source),os.fsencode(target),0)!=0:
        raise OSError(ctypes.get_errno(),'APFS clone refused; no byte-copy fallback')
    cloned_bytes+=os.stat(source).st_size
    return target
dst.mkdir()
shutil.copytree(src/'Sources',dst/'Sources',symlinks=True,copy_function=clone_only)
if (src/'Packages').exists():shutil.copytree(src/'Packages',dst/'Packages',symlinks=True,copy_function=clone_only)
if (src/'selftest-fixtures').exists():shutil.copytree(src/'selftest-fixtures',dst/'selftest-fixtures',symlinks=True,copy_function=clone_only)
for name in ['Package.swift','build.sh','gor-selftest.sh']:
    if (src/name).exists():clone_only(src/name,dst/name)
if (src/'Resources').exists():
    shutil.copytree(src/'Resources',dst/'Resources',symlinks=True,copy_function=clone_only,ignore=lambda p,n:['vendor'] if Path(p)==src/'Resources' else [])
    if (src/'Resources/vendor').exists():
        shutil.copytree((src/'Resources/vendor').resolve(),dst/'Resources/vendor',symlinks=True,copy_function=clone_only)
print('t3b APFS clone-only logical-bytes='+str(cloned_bytes)+'; zero byte-copy fallback',flush=True)
backup=dst/'.gor-backups/000000-000000-selftest';backup.mkdir(parents=True)
shutil.copy2(dst/'Package.swift',backup/'Package.swift')
(backup/'changes.txt').write_text('changed\tPackage.swift\n')
with (dst/'Package.swift').open('a') as f:f.write('\n// selftest rollback marker\n')
GOR_ROLLBACK_COPY
    then
        st_quit || return 1; open -g -n "$app" --args --gor-no-activate || true
        if st_wait_running 120; then
            s=$(date +%s)
            local rb_rc=0
            GOR_SNAPSHOT= GOR_SNAPSHOT_PATH= GOR_SNAPSHOT_ORIG= GOR_PROJECT_ROOT= \
               bash "$rbcopy/build.sh" --no-launch --rollback 000000-000000-selftest >"$rbtest/rollback.log" 2>&1 || rb_rc=$?
            cat "$rbtest/rollback.log" >>"$buildlog"
            if [ "$rb_rc" -ne 0 ]; then
                st_fail t3b-rollback-open "isolated build/rollback rc=$rb_rc; see bounded result diagnostics"
                /usr/bin/python3 - "$rbtest/rollback.log" <<'GOR_ROLLBACK_DIAG' | tee -a "$results"
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
with p.open('rb') as f:
    f.seek(0,2);size=f.tell();f.seek(max(0,size-65536));lines=f.read(65536).decode('utf-8','replace').splitlines()
for name,pattern in [
 ('asset-containment',r'external assets preflight:'),
 ('compile-error',r'error:'),
 ('signing',r'(?:signing|signature).*(?:failed|refused|cannot|invalid)'),
 ('vendor-gate',r'lifeline:|mpv gate:'),
 ('rollback',r'rollback:.*(?:failed|missing|no backup)'),
 ('source-lock',r'lock.*(?:held|mismatch|exists)'),
]:
    count=sum(bool(re.search(pattern,l,re.I)) for l in lines)
    if count:print('t3b-diagnostic '+name+' count='+str(count))
GOR_ROLLBACK_DIAG
            elif ! cmp -s "$project_root/Package.swift" "$rbcopy/Package.swift"; then
                st_fail t3b-rollback-open "isolated rollback did not restore exact Package.swift"
            elif ! st_running; then
                st_fail t3b-rollback-open "real app closed during test; lifetime/rollback outcome not qualified"
            else
                st_pass t3b-rollback-open "$(( $(date +%s) - s ))s isolated actual source/build/rollback; real app stayed open"
            fi
        else st_fail t3b-rollback-open "real app not running before isolated rollback"; fi
    else st_fail t3b-rollback-open "could not create isolated source copy"; fi
    rm -rf "$rbtest" # only this test's mktemp tree, never real project/source.

    # verified-tag flow on a SCRATCH tag, SCRATCH sidecar, SCRATCH project:
    # the real gor-verified tag, sidecar and project tree are never touched.
    local sc scp scs stag
    sc=$(mktemp -d "${TMPDIR:-/tmp}/gor-selftest-scratch.XXXXXXXX")
    scp="$sc/proj"
    scs="$sc/sidecar"
    stag="scratch-verified-$$"
    mkdir -p "$scp/Sources/gor" "$scs/archive/gor/Sources/gor"
    cp "$project_root/build.sh" "$scp/build.sh"
    cp "$project_root/Package.swift" "$scp/Package.swift" 2>/dev/null || true
    echo '// scratch' > "$scp/Sources/gor/Scratch.swift"
    cp "$scp/build.sh" "$scs/archive/gor/build.sh"
    cp "$scp/Package.swift" "$scs/archive/gor/Package.swift" 2>/dev/null || true
    cp "$scp/Sources/gor/Scratch.swift" "$scs/archive/gor/Sources/gor/Scratch.swift"
    local ok=true unv orig_sha
    git -C "$scs" init -q && git -C "$scs" add -A && git -C "$scs" -c user.name=gor-selftest -c user.email=gor-selftest@localhost commit -qm scratch || ok=false
    orig_sha=$(shasum -a 256 "$scp/Sources/gor/Scratch.swift" | awk '{print $1}')
    GOR_DST="$scs" GOR_VERIFIED_TAG="$stag" bash "$scp/build.sh" --no-build --verified >>"$buildlog" 2>&1 || ok=false
    echo '// touched' >> "$scp/Sources/gor/Scratch.swift"
    cp "$scp/Sources/gor/Scratch.swift" "$scs/archive/gor/Sources/gor/Scratch.swift"
    git -C "$scs" add -A && git -C "$scs" -c user.name=gor-selftest -c user.email=gor-selftest@localhost commit -qm touch || ok=false
    unv=$(GOR_DST="$scs" GOR_VERIFIED_TAG="$stag" bash "$scp/build.sh" --no-build --unverified 2>&1) || ok=false
    [ "$(printf '%s\n' "$unv" | grep -c .)" = "1" ] || { ok=false; echo "      selftest: --unverified printed $(printf '%s\n' "$unv" | grep -c .) lines, expected 1"; }
    GOR_DST="$scs" GOR_VERIFIED_TAG="$stag" bash "$scp/build.sh" --no-build --rollback verified >>"$buildlog" 2>&1 || ok=false
    [ "$(shasum -a 256 "$scp/Sources/gor/Scratch.swift" | awk '{print $1}')" = "$orig_sha" ] || { ok=false; echo "      selftest: scratch file sha mismatch after --rollback verified"; }
    # restore the touched state via the shipped undo of the pre-rollback backup
    bash "$scp/build.sh" --no-build --rollback >>"$buildlog" 2>&1 || ok=false
    grep -q '^// touched' <(tail -1 "$scp/Sources/gor/Scratch.swift") || { ok=false; echo "      selftest: shipped --rollback did not restore the touched file"; }
    # the source backup holds the touched file
    local bb; bb=$(ls -1d "$scp"/.gor-backups/*-pre-rollback-verified 2>/dev/null | head -1)
    [ -n "$bb" ] && grep -q '^changed	Sources/gor/Scratch.swift$' "$bb/changes.txt" && tail -1 "$bb/Sources/gor/Scratch.swift" | grep -q '^// touched' || { ok=false; echo "      selftest: pre-rollback-verified backup does not hold the touched file"; }
    git -C "$scs" tag -d "$stag" >/dev/null 2>&1 || true
    rm -rf "$sc"
    if [ "$ok" = true ]; then st_pass verified-tag-scratch; else st_fail verified-tag-scratch "scratch tag flow broke (see .gor-selftest-build.log)"; fi

    fi

    st_quit || true
    if st_wait_gone 30; then
        if GOR_LIFETIME_FULL=$([ "$selftest_mode" = full ] && echo 1 || echo 0) /usr/bin/python3 "$project_root/tools/gor_step.py" "lifecycle selftest" bash "$project_root/gor-selftest.sh" --lifeline-only; then
            st_pass lifecycle-external
        else
            st_fail lifecycle-external "external checks include lifecycle and feature legs; inspect individual verdicts"
        fi
        # 191a A acceptance: real installed-menu walk; the pixel verdict is computed, never claimed by the runner.
        if [ "$selftest_mode" = full ] && [ -f "$project_root/tools/store_acceptance.py" ]; then echo "store acceptance: every 3D source x output pair plus sequences 1-5 through the real menu and store; about 10 min; hard cap 15 min"; store_rc=0; store_out=$(GOR_STEP_LIMIT=900 /usr/bin/python3 "$project_root/tools/gor_step.py" "store acceptance" /usr/bin/python3 "$project_root/tools/store_acceptance.py" "$project_root" 2>&1) || store_rc=$?; printf '%s\n' "$store_out" | { grep 3D-STORE || true; } | while read -r l; do st_note "store: $l"; done; if [ "$store_rc" = 0 ]; then st_pass store-acceptance; elif [ "$store_rc" = 2 ] && printf '%s\n' "$store_out" | grep -q '3D-STORE v1 verdict=NOT_RUN'; then store_not_run=true; st_note "NOT_RUN store-acceptance: $(printf '%s\n' "$store_out" | grep '3D-STORE v1 verdict=NOT_RUN' | tail -1)"; else st_fail store-acceptance "store/menu/keys case failed; the 3D-STORE lines above name the case and reason"; fi; fi
    else st_fail lifecycle-external "prior gor did not quit; refused extra test instance"; fi

    if [ "$selftest_mode" = full ] && [ -f "$project_root/tools/owner_action_acceptance.py" ]; then
        st_note "KNOWN-RESIDUAL base02004a518: cinema_pose ShiftR pin; preview_pack two text pins; row_wiring ShiftD pin; old onBack2D test API; gpu_pose D3_TITLE_tex; surface_anchor old output pin; axes_gpu killed on base and candidate, incomplete"; st_quit || true; if st_wait_gone 30; then for owner_kind in ordinary native; do owner_rc=0; owner_arg=""; [ "$owner_kind" != native ] || owner_arg="--native"; owner_out=$(GOR_STEP_LIMIT=90 /usr/bin/python3 "$project_root/tools/gor_step.py" "owner action $owner_kind" /usr/bin/python3 "$project_root/tools/owner_action_acceptance.py" "$project_root" $owner_arg 2>&1) || owner_rc=$?; printf '%s\n' "$owner_out" | while IFS= read -r line; do st_note "$line"; done; st_note "3D-OWNER-ACTION leg=$owner_kind rc=$owner_rc"; if [ "$owner_rc" = 2 ]; then store_not_run=true; elif [ "$owner_rc" != 0 ]; then st_fail "owner-action-$owner_kind" "applied-state acceptance failed; see receipts"; fi; done; else st_note "NOT_RUN owner-actions prior interactive process still running"; store_not_run=true; fi
    fi
    if [ "$selftest_mode" != full ]; then st_note "3D acceptance: NOT_RUN"; fi
    st_quit || true; if st_wait_gone 30; then st_note "RELAUNCH prior_exact_path_processes=gone requested_epoch=$(date +%s)"; open -g -n "$app" --args --gor-background-start 2>/dev/null || st_fail t1-relaunch-open "explicit app launch failed"; else st_fail t1-relaunch-fresh "prior exact-path process did not quit"; fi
    if st_wait_running 60; then for fresh_pid in $(/usr/bin/python3 "$project_root/tools/axes_acceptance.py" --list-interactive "$bin"); do st_note "RELAUNCH pid=$fresh_pid started=$(ps -p "$fresh_pid" -o lstart=) $(tr '\n' ' ' < "$app/Contents/Resources/build-id.txt")"; done; echo "gor left running."; else st_fail t1-relaunch-stay "app not running after final relaunch"; fi
    if [ "$fail" -eq 0 ] && [ "$store_not_run" = true ]; then st_note "SELFTEST PARTIAL $pass passed; store-acceptance NOT_RUN"; elif [ "$fail" -eq 0 ]; then
        st_note "SELFTEST PASS $pass/$((pass+fail)) $(( $(date +%s) - t0 ))s"
    else
        st_note "SELFTEST FAIL $pass/$((pass+fail)) $(( $(date +%s) - t0 ))s"
    fi
    [ "$fail" -eq 0 ]
}

# Result recording never calls the selftest in an if/|| context: doing so
# would disable errexit throughout its body. A bare failing call reaches EXIT.
update_stage=build
update_result_attempted=false
update_results_fresh=false
update_compile_detail=""
update_t0=0
update_timer_scope="full invocation"
update_against=""
gor_update_finish() {
    update_stage=selftest
    gor_selftest
    update_stage=result
    gor_update_result_commit 0 || true
    echo "update total ($update_timer_scope, including result push): $(( $(date +%s) - update_t0 ))s"
    exit 0
}

gor_update_result_commit() {
    local rc="$1" sync_dir branch build_sha ts msg elapsed detail=""
    update_result_attempted=true  # exactly one attempt, even if commit fails
    sync_dir="$(gor_sidecar)"; branch="$(gor_sidecar_branch)"
    [ -d "$sync_dir/.git" ] || { echo "update: result not recorded (no sidecar)" >&2; return 1; }
    gor_st_wait_source_lock || { echo "update: result not recorded (source lock held)" >&2; return 1; }
    [ "$(git -C "$sync_dir" symbolic-ref --quiet --short HEAD)" = "$branch" ] || { echo "update: result not recorded (wrong sidecar branch)" >&2; return 1; }
    git -C "$sync_dir" diff --cached --quiet || { echo "update: result not recorded (staged changes present)" >&2; return 1; }
    build_sha="$GOR_BUILD_SH_SHA256_AT_START"
    ts=$(date +%y%m%d-%H%M%S) || return 1
    elapsed=$(( $(date +%s) - update_t0 ))
    if [ "$update_results_fresh" = true ]; then
        detail=$(cat "$project_root/.gor-selftest-last.txt") || return 1
    fi
    for ud in "${update_compile_detail:-}" "${update_restore_detail:-}"; do [ -n "$ud" ] && detail="$detail"$'\n'"$ud"; done
    if [ "$rc" -ne 0 ]; then
        detail="$detail
FAIL update-$update_stage: rc=$rc after ${elapsed}s"
    fi
    # Block183 delivery eligibility is independent of feature/harness failures.
    if [ "$update_results_fresh" = true ]; then
        local delivery_gate
        delivery_gate=$(/usr/bin/python3 - "$project_root/.gor-selftest-last.txt" <<'GOR_DELIVERY_GATE'
import re,sys
from pathlib import Path
lines=Path(sys.argv[1]).read_text().splitlines()
def passed(prefix):return any(l.startswith('PASS '+prefix) for l in lines)
checks={'t1':passed('t1-build-launch'),'l1':passed('l1 '),'l2':passed('l2 '),'l3':passed('l3-normal-1x '),
        'l4':all(passed('l4-'+n+' ') for n in ['l1','l2','l3-normal-1x'])}
print(('PASS' if all(checks.values()) else 'FAIL')+' delivery-gate183 '+','.join(k+'='+('PASS' if v else 'MISSING/FAIL') for k,v in checks.items())+'; other verdicts remain open')
GOR_DELIVERY_GATE
        ) || delivery_gate='FAIL delivery-gate183 unreadable verdicts'
        detail="$detail
$delivery_gate"
    fi
    # Two fixed read-only script pins accompany every fresh selftest result.
    if [ "$update_results_fresh" = true ]; then
        local script_pins
        script_pins=$(/usr/bin/python3 - "$project_root" <<'GOR_SCRIPT_PINS'
import hashlib,sys
from pathlib import Path
p=Path(sys.argv[1])
for name in ['photon.lua','photon-grain.lua']:
    item=p/'Resources/vendor/mpv/scripts'/name
    try:
        if not item.is_file():value='ABSENT'
        elif item.stat().st_size>2*1024*1024:value='UNREAD oversized'
        else:value='sha256:'+hashlib.sha256(item.read_bytes()).hexdigest()
    except OSError as error:value='UNREAD '+type(error).__name__
    print('READONLY vendor/mpv/scripts/'+name+' '+value)
GOR_SCRIPT_PINS
        ) || script_pins='READONLY script pins unavailable'
        detail="$detail
$script_pins"
    fi
    # Always capture live-caption startup/audio evidence, including failed/no-toggle states.
    # Read only, bounded, appended to this immutable update capture; never truncates app logs.
    if [ "${GOR_UPDATE_FEATURE_EVIDENCE:-0}" = 1 ]; then
    local caption_evidence
    caption_evidence=$(GOR_STEP_LIMIT=180 /usr/bin/python3 "$project_root/tools/gor_step.py" "live-caption evidence" /usr/bin/python3 "$project_root/Tests/LiveCaptionStartup/capture.py" "$project_root" 2>&1) || caption_evidence='live-caption evidence unavailable (capture helper failed)'
    detail="$detail
$caption_evidence"
    local subtitle_evidence
    subtitle_evidence=$(GOR_STEP_LIMIT=180 /usr/bin/python3 "$project_root/tools/gor_step.py" "subtitle evidence" /usr/bin/python3 "$project_root/Tests/LiveCaptionStartup/subtitle-capture.py" "$project_root" 2>&1) || subtitle_evidence='subtitle probe unavailable'; [ "$update_results_fresh" = true ] && [ -z "${GOR_SKIP_3D_CHECK:-}" ] && [ -f "$project_root/tools/update_3d_check.py" ] && subtitle_evidence="$subtitle_evidence"$'\n'"$(GOR_STEP_LIMIT=180 /usr/bin/python3 "$project_root/tools/gor_step.py" "start background 3D check" /usr/bin/python3 "$project_root/tools/update_3d_check.py" "$project_root" --background 2>&1 || :)"; [ -f "$project_root/tools/gor_state_dump.py" ] && subtitle_evidence="$subtitle_evidence"$'\n'"$(GOR_STEP_LIMIT=90 /usr/bin/python3 "$project_root/tools/gor_step.py" "gor state dump" /usr/bin/python3 "$project_root/tools/gor_state_dump.py" "$project_root" 2>&1 || echo 'gor state dump unavailable')"  # 3D work is detached; this capture records launch status, result arrives later in the log; the state dump rides every update
    detail="$detail
$subtitle_evidence"
    else
        detail="$detail"$'\n'"3D acceptance: NOT_RUN; feature probes explicit only"
    fi
    if [ -f "$project_root/tools/owner_action_capture_grep.py" ]; then detail="$detail"$'\n'"$(/usr/bin/python3 "$project_root/tools/owner_action_capture_grep.py" /tmp/gor_diag.log /tmp/gor_direct.log 2>&1 || echo 'NOT_RUN routing_grep_unavailable')"; fi
    # Failure custody travels in the same empty result commit. Never require
    # a second owner paste for the local-only dependency/startup evidence.
    if [ "$rc" -ne 0 ] && [ "$update_results_fresh" = true ]; then
        local diagnostics
        diagnostics=$(/usr/bin/python3 - "$project_root/.gor-selftest-build.log" <<'GOR_FAILURE_DIAGNOSTICS'
import os,re,sys
from pathlib import Path
p=Path(sys.argv[1])
try:
    with p.open('rb') as f:
        f.seek(max(0,p.stat().st_size-32768));data=f.read(32768)
    text=data.decode('utf-8','replace')
    text=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',text)
    text=''.join(c for c in text if c in '\n\t' or ord(c)>=32)
    text=text.replace(os.path.expanduser('~'),'~')
    text='\n'.join(text.splitlines()[-128:])
    print('BEGIN bounded failure diagnostics (last 32KiB / 128 lines)')
    print(text)
    print('END bounded failure diagnostics')
except OSError as e:
    print('Failure diagnostics unavailable: '+type(e).__name__)
GOR_FAILURE_DIAGNOSTICS
        ) || diagnostics='Failure diagnostics capture failed'
        detail="$detail
$diagnostics"
    fi
    if [ -f "$project_root/.gor-vendor-audit-last.txt" ]; then
        detail="$detail
BEGIN complete vendor audit
$(cat "$project_root/.gor-vendor-audit-last.txt")
END complete vendor audit"
    fi
    # Read-only, bounded contract discovery. No sidecar policy changes or artifact staging.
    local sync_gate_diagnostics
    sync_gate_diagnostics=$(/usr/bin/python3 - "$sync_dir/sync.sh" <<'GOR_SYNC_GATE_DIAGNOSTICS'
import hashlib,json,re,sys
from pathlib import Path
try:
    p=Path(sys.argv[1])
    if p.is_symlink() or not p.is_file() or p.stat().st_size>256*1024:raise ValueError('helper not bounded regular file')
    data=p.read_bytes();text=data.decode('utf-8');lines=text.splitlines()
    print('SYNC_GATE sha256='+hashlib.sha256(data).hexdigest()+' bytes='+str(len(data)))
    # Only literal path/type gate rules, never auth/config/environment/helper commands.
    relevant=re.compile(r'allowlist|allowed_paths|allowed_ext|binary|\.png|archive/gor|Resources/|Sources/')
    forbidden=re.compile(r'credential|password|passwd|secret|token|authorization|cookie|auth|ASKPASS|helper|https?://|/Users/|/home/|\benv\b',re.I)
    secret=re.compile(r'github_pat_|gh[pousr]_[A-Za-z0-9]|AKIA[0-9A-Z]{16}|-----BEGIN|[A-Za-z0-9_+/=-]{48,}')
    selected=[]
    for n,line in enumerate(lines,1):
        if relevant.search(line) and not forbidden.search(line) and not secret.search(line) and len(line)<=240:
            selected.append((n,line))
    selected=selected[:24]
    payload='\n'.join('SYNC_GATE_RULE '+str(n)+' '+json.dumps(line,ensure_ascii=True) for n,line in selected)
    if secret.search(payload) or len(payload)>8192:raise ValueError('selected payload secret scan refused')
    print(payload if payload else 'SYNC_GATE_RULE unavailable: no safely selectable literal rules')
    print('SYNC_GATE contract remains unverified until reviewer inspects rules; no artifact staged')
except Exception as e:print('SYNC_GATE unavailable: '+type(e).__name__+'; no helper source disclosed')
GOR_SYNC_GATE_DIAGNOSTICS
    ) || sync_gate_diagnostics='SYNC_GATE unavailable: diagnostic failed'
    detail="$detail
$sync_gate_diagnostics"
    msg="gor-update $ts rc=$rc
against: $update_against ($branch)
build.sh: sha256:$build_sha
$detail
update elapsed ($update_timer_scope, through result capture before push): ${elapsed}s"
    local queue="$sync_dir/.git/gor-capture-pending" capture_file
    mkdir -p "$queue"
    capture_file="$queue/$ts.txt"
    [ ! -e "$capture_file" ] || { echo 'capture timestamp collision; existing file preserved' >&2; return 1; }
    { printf '%s\n' "$msg"; /usr/bin/python3 "$project_root/tools/gor_step.py" --history; } > "$capture_file"
    /usr/bin/python3 "$project_root/tools/gor_step.py" "capture upload" /usr/bin/python3 "$project_root/gor-capture-channel.py" --repo "$sync_dir" send --file "$capture_file" || { echo 'capture retained locally for next update' >&2; return 1; }

}

gor_update_exit_trap() {
    local rc="$1"
    trap - EXIT
    # Bare-call failures retain errexit and arrive here with their real status.
    # A selftest abort includes only lines written after this run's truncation.
    if [ "$rc" -ne 0 ] && [ "$update_stage" != result ]; then update_restore_detail="update red at $update_stage: NO auto-restore (191l owner order: only he rolls back); installed app left as-is; previous app intact at $stage_dir/gor.app.last when this run swapped - restore only by hand: bash build.sh --no-build --rollback"; echo "$update_restore_detail"; fi; if [ "$rc" -ne 0 ] && [ "$update_result_attempted" != true ]; then
        gor_update_result_commit "$rc" || true
    fi
    if [ "$rc" -ne 0 ]; then echo "update total ($update_timer_scope, including result push): $(( $(date +%s) - update_t0 ))s"; fi
    if declare -F cleanup_build_run >/dev/null; then
        cleanup_build_run || true
    else
        gor_release_build_lock || true
        gor_cleanup_snapshot || true
    fi
    exit "$rc"
}

# 63c8f6282 follow-up: the retire rule inside gor_install_tree only runs when
# the RUNNING build.sh already carries it, so the update that delivered the
# rule could never apply it (the old build.sh installs the overlay, then
# re-execs the new build.sh only for --update-build, which compiled the stale
# duplicate - owner capture 261115-134541, rc=1). Close the bootstrap gap:
# retire relocated sources again before the build phase compiles Sources.
# Same fail-closed contract as the install-tree rule: exact sha match of the
# pre-relocation byte stream or stop untouched; the file is parked in a
# timestamped backup, never deleted outright. Old tree shape (no Viewport
# directory) means there is nothing to retire.
gor_retire_relocated_sources() {
    local rel="Sources/gor/GorFit.swift" expected=53752e4797fc2d252e0e813665b775d385c7aa960aa50209214b37f197ca3e65 actual park
    [ -e "$project_root/$rel" ] || return 0
    [ -f "$project_root/Sources/gor/Viewport/Viewport.swift" ] || return 0
    grep -q '^enum GorVideoFit {' "$project_root/Sources/gor/Viewport/Viewport.swift" 2>/dev/null || return 0
    grep -q '^struct GorCropFilter' "$project_root/Sources/gor/Viewport/Viewport.swift" 2>/dev/null || return 0
    [ -f "$project_root/$rel" ] && [ ! -L "$project_root/$rel" ] || { echo "viewport relocation: unexpected local file $rel" >&2; exit 1; }
    actual=$(shasum -a 256 "$project_root/$rel") || exit 1
    actual=${actual%% *}
    [ "$actual" = "$expected" ] || { echo "viewport relocation: local edits in $rel; nothing changed" >&2; exit 1; }
    park="$backups_dir/$(date +%y%m%d-%H%M%S)-viewport-retire"
    [ -e "$park" ] && { echo "viewport relocation: backup dir exists: $park - stopping, nothing moved" >&2; exit 1; }
    mkdir -p "$park/$(dirname "$rel")" || exit 1
    mv "$project_root/$rel" "$park/$rel" || { echo "viewport relocation: could not park $rel" >&2; exit 1; }
    echo "viewport relocation: retired stale $rel to $park (sha-verified pre-move copy)"
}

# block 176c dispatch: --update syncs + installs + re-execs; --update-build is
# the continuation inside the freshly installed build.sh (build lock inherited
# across the exec: same PID). Runs before the normal build flow.
case "${1:-}" in
    --update) gor_update_run ;;    # re-execs or exits; never falls through
    --update-build)
        [ -z "${GOR_SELFTEST:-}" ] || { echo "--update inside the selftest is not allowed" >&2; exit 1; }; /usr/bin/python3 "$project_root/tools/update_playing_guard.py" "$project_root" "$(id -u)" || exit $?; ( /usr/bin/python3 "$project_root/tools/gor_step.py" --beat $$ "$project_root" </dev/null >/dev/null 2>&1 & )
        update_mode=true
        update_t0=${GOR_UPDATE_T0:-$(date +%s)}
        if [ -z "${GOR_UPDATE_T0:-}" ]; then
            # Upgrade from an older runner: all snapshot/re-execs keep this
            # PID. ps etime recovers invocation age without a second run.
            local_age=$(/bin/ps -p $$ -o etime=) || local_age=""
            elapsed_age=$(/usr/bin/python3 - "$local_age" <<'GOR_INVOCATION_AGE'
import re,sys
s=sys.argv[1].strip()
m=re.fullmatch(r'(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)',s)
if not m:raise SystemExit(1)
d,h,mi,se=[int(v or 0) for v in m.groups()]
print(d*86400+h*3600+mi*60+se)
GOR_INVOCATION_AGE
            ) || elapsed_age=""
            if [ -n "$elapsed_age" ]; then
                update_t0=$(( $(date +%s) - elapsed_age ))
                update_timer_scope="full invocation, ps elapsed seconds"
            else
                update_timer_scope="installed continuation only; preinstall unmeasured"
            fi
        fi
        if ! ( gor_install_architecture_assets "$(gor_sidecar)/archive/gor" ); then
            echo 'update integrity: architecture release incomplete; prior app/updater retained; no build or launch' >&2
            exit 1
        fi
        # Bootstrap old -> new installer: only missing/changed fixtures cause a backed-up add/change.
        fixture_rb="$project_root/.gor-backups/$(date +%y%m%d-%H%M%S)-fixtures-update-$$"
        gor_install_selftest_fixtures "$(gor_sidecar)/archive/gor" "$fixture_rb"
        # Bootstrap gap close: an installer older than 63c8f6282 delivered the
        # Viewport relocation without retiring the stale source; park it now,
        # before the build compiles Sources (fail-closed, sha-verified).
        gor_retire_relocated_sources
        # 190a R1: only the installed update continuation registers, once per update.
        # The helper is idempotent; scope/network failures never block gor's update.
        ( set +x; /usr/bin/python3 "$project_root/Tests/Runner/runner.py" install ) || :
        update_against=$(git -C "$(gor_sidecar)" rev-parse HEAD)
        trap 'gor_update_exit_trap "$?"' EXIT
        open_app=false   # the selftest owns every launch
        shift ;;
esac

# Exactly one writer owns gor_build.log. Both printed output and unfiltered
# compiler records enter its FIFO; nobody else opens the destination file.
separate_log_dir=""
separate_log_pid=""
exec 4>&1
if [ "$separate_build_log" = true ]; then
    separate_log_dir=$(mktemp -d /tmp/gor-build-capture.XXXXXX)
    mkfifo "$separate_log_dir/input"
    tee /tmp/gor_build.log < "$separate_log_dir/input" >/dev/null &
    separate_log_pid=$!
    exec 5>"$separate_log_dir/input"
    exec > >(tee /dev/fd/5 >&4) 2>&1
else
    rm -f /tmp/gor_build.log
fi

# 174 item 2: while/shift parser; --fast-dev/--distribution removed, --rollback added.
# 176 item 3 adds --verified/--unverified/--rollback verified; 176c adds
# --no-build (source-only runs) and --selftest.
rollback_ts=""
skip_build=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-log-timestamp) log_timestamp=false ;;
        --no-log-cpu-info) log_cpu_info=false ;;
        --log-timestamp) log_timestamp=true ;;
        --log-cpu-info) log_cpu_info=true ;;
        --no-launch) open_app=false ;;
        --clean)     clean_build=true ;;
        --dmg)       create_dmg=true ;;
        --no-sign)   signing_enabled=false ;;
        --warnings)  show_warnings=true ;;
        --whisper)   build_whisper=true ;;
        --rollback)
            shift
            if [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; then rollback_ts="$1"; shift; fi
            if [ "$rollback_ts" = "verified" ]; then gor_rollback_verified; else gor_rollback "$rollback_ts"; fi
            break ;;
        --verified)
            gor_mark_verified
            exit $? ;;
        --unverified)
            gor_print_unverified
            exit $? ;;
        --no-build)
            skip_build=true ;;
        --selftest)
            gor_selftest lifetime
            exit $? ;;
        --selftest-full)
            gor_selftest full
            exit $? ;;
        --log)
            shift
            if [ "$#" -eq 0 ]; then echo "--log needs a mode" >&2; exit 2; fi
            log_mode="$1" ;;
        *) echo "unknown build option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$log_mode" in
    off|direct|filter|stream|broad|full) ;;
    *) echo "unknown log mode: $log_mode" >&2; exit 2 ;;
esac

case "$exit_log_zip" in true|false) ;; *) echo 'exit_log_zip must be true or false' >&2; exit 2;; esac

# First upgrade is installed by the previous overlay-only build.sh. It cannot
# retire old logger filenames itself, so the NEW script performs the same
# hash-checked backup-first consolidation before any Swift compilation/swap.
if [ -f "$project_root/Sources/gor/Diag.swift" ] &&
   { [ -e "$project_root/Sources/gor/ThreadCpuDiag.swift" ] || [ -e "$project_root/Sources/gor/MainThreadDiag.swift" ]; }; then
    diag_transition=$(mktemp -d /tmp/gor-diag-consolidate.XXXXXXXX) || exit 1
    mkdir -p "$diag_transition/Sources/gor" || exit 1
    cp -p "$project_root/Sources/gor/Diag.swift" "$diag_transition/Sources/gor/Diag.swift" || exit 1
    gor_install_tree "$diag_transition" "diag-consolidation"
    rm -rf "$diag_transition" # only this run's private temporary overlay.
fi

# Domain consolidation must also run after an older updater's source overlay.
# The helper accepts only the approved hash-pinned inputs and exact replacements.
# It preserves a complete pre-update rollback, with a normal --rollback pointer.
if [ -f "$project_root/Tests/Structure/migrate.py" ]; then /usr/bin/python3 "$project_root/Tests/Structure/migrate.py" "$project_root" "$backups_dir" "$HOME/Downloads/gor-bbu" || exit 1; fi
# Explicit absorbed-file inventory, validated and moved before any compiler runs.
if [ -f "$project_root/Tests/Structure/retire-overlay.py" ]; then /usr/bin/python3 "$project_root/Tests/Structure/retire-overlay.py" "$project_root" "$backups_dir" "$HOME/Downloads/gor-bbu" || exit 1; fi
if [ -f "$project_root/Sources/gor/ThreeDAxesAcceptance.swift" ]; then axes_rb="$backups_dir/$(date +%y%m%d-%H%M%S)-axes-retire"; [ ! -e "$axes_rb" ] || { echo "exists: $axes_rb - stopping, nothing moved" >&2; exit 1; }; mkdir -p "$axes_rb/Sources/gor" || exit 1
    cp -p "$project_root/Sources/gor/ThreeDAxesAcceptance.swift" "$axes_rb/Sources/gor/ThreeDAxesAcceptance.swift" && printf 'deleted\tSources/gor/ThreeDAxesAcceptance.swift\n' > "$axes_rb/changes.txt" && rm -f "$project_root/Sources/gor/ThreeDAxesAcceptance.swift" || { echo "191b axes retirement failed; stale file left in place; build refused" >&2; exit 1; }
    echo "191b: retired stale Sources/gor/ThreeDAxesAcceptance.swift (replaced by the store acceptance; overlay installs never delete); backup=$axes_rb"; fi

if [ "$skip_build" = true ]; then
    echo "no-build: source operations done; skipping the build."
    exit 0
fi

# ── paths ─────────────────────────────────────────────────────────────────────
app_name="gor"
bundle_id="com.gokcebalkan.gor"
# project_root is already fixed and locked before any shared side effects.
icon_source="$project_root/Resources/icon/_icon.png"

build_dir="$project_root/.build"
debug_bin=""  # Resolved from SwiftPM after a successful product build.
# block 174 item 5: the app is built into .gor-stage; the installed app is
# not touched until the swap. vendor and fonts stay outside the app.
app_bundle="$project_root/$app_name.app"
stage_dir="$project_root/.gor-stage"
stage_app="$stage_dir/gor.app"
dest="$stage_app/Contents/MacOS"
res="$stage_app/Contents/Resources"
icon_cache="$build_dir/AppIcon.icns"
whisper_src_dir="$project_root/whisper-cpp-src"

total_steps=8
if [ "$build_whisper" = true ]; then
    total_steps=9
fi
step=0
next_step() { step=$((step + 1)); printf "[%d/%d] " $step $total_steps; }

gor_phase_marks=()
gor_mark() { local now; now=$(date +%s); gor_phase_marks+=("$1=$now"); printf '[GOR-t] %s %s\n' "$1" "$now"; }
gor_mark preflight-start
gor_pids() {  # Exact executable argv, never all applications named gor.
    local out p args
    out=$(pgrep -u "$build_uid" -x "$app_name" 2>/dev/null) || {
        local rc=$?; [ "$rc" -eq 1 ] && return 0
        echo "cannot enumerate gor processes" >&2; return "$rc"
    }
    for p in $out; do
        args=$(ps -ww -p "$p" -o command=) || continue
        case "$args" in *" --selftest3d"*|*" --gor-model-load-probe"*|*" --gor-prepare-worker"*) continue ;; "$app_bundle/Contents/MacOS/$app_name"|"$app_bundle/Contents/MacOS/$app_name "*) printf '%s\n' "$p" ;; esac
    done
}

# 174 items 3+11: TERM, wait, KILL, wait; still running -> refuse the swap.
stop_running_gor() {
    local pids attempt
    pids=$(gor_pids)
    [ -n "$pids" ] || return 0
    echo "      stopping gor PID(s): $pids"
    echo "[GOR-signal] sender=build.sh sender_pid=$$ target_pids=$pids signal=SIGTERM reason=replace_ui_bundle"; kill -TERM $pids 2>/dev/null || true
    for ((attempt = 0; attempt < 50; attempt++)); do
        pids=$(gor_pids); [ -n "$pids" ] || return 0
        sleep 0.2
    done
    echo "      gor did not exit after SIGTERM; sending SIGKILL to: $pids"
    kill -KILL $pids 2>/dev/null || true
    for ((attempt = 0; attempt < 10; attempt++)); do
        pids=$(gor_pids); [ -n "$pids" ] || return 0
        sleep 0.2
    done
    echo "      gor is still running; refusing bundle replacement/launch" >&2
    return 1
}

# ── vendor leaf signing in place (174 item 9): only leaves changed vs mirror ─
gor_sign_vendor_leaves() {
    # 174d: a leaf counts as changed only if it is in sb_changed/sb_added - the
    # mirror diff already read the tree; no second cmp here.
    local vendor="$project_root/Resources/vendor" rel leaf changed=0 verified=0 signed=0
    while IFS= read -r rel; do
        case "$rel" in
            */mpv|mpv|*/ffmpeg|ffmpeg|*/gifsicle|gifsicle|*/mus2|mus2|*/node|node|*/chrome-headless-shell|chrome-headless-shell|*/whisper-live|whisper-live|*/yt-dlp|yt-dlp|*.dylib) ;;
            *) continue ;;
        esac
        leaf="$vendor/$rel"
        changed=$((changed+1))
        if codesign --verify --strict "$leaf" 2>/dev/null; then
            verified=$((verified+1)); continue
        fi
        case "$rel" in
            */node|node) codesign --force --sign - --preserve-metadata=entitlements,flags "$leaf" || { echo "vendor leaf sign failed: $rel" >&2; return 1; } ;;
            *)           codesign --force --sign - "$leaf" || { echo "vendor leaf sign failed: $rel" >&2; return 1; } ;;
        esac
        signed=$((signed+1))
        echo "      vendor leaf signed ad-hoc: $rel"
    done < <( printf '%s\n' "${sb_changed[@]}" "${sb_added[@]}" | sed -n 's|^Resources/vendor/||p' | sort )
    echo "      vendor leaves: $changed changed since last good build, $verified already valid, $signed re-signed in place"
}

# ── 174b 2(d): report node's LC_RPATH lines; STOP only outside vendor/node ───
gor_rpath_norm() {  # string-normalize . and .. (no disk access)
    printf '%s' "$1" | awk -F/ '{out=""; for(i=1;i<=NF;i++){ if($i==".."){sub(/\/[^\/]*$/,"",out)} else if($i!="."&&$i!=""){out=out"/"$i} }; print out}'
}
gor_node_rpath_check() {
    local node line base anchor norm dep found d bad=0
    node=$(find "$project_root/Resources/vendor/node" -maxdepth 2 -name node -type f 2>/dev/null | head -1)
    [ -f "$node" ] || { echo "node rpath check: node binary missing under vendor/node" >&2; return 1; }
    base=$(dirname "$node"); anchor="$project_root/Resources/vendor/node"
    rpath_dirs=()
    while IFS= read -r line; do
        echo "      node LC_RPATH: $line"
        case "$line" in
            @loader_path|@executable_path)   norm="$base" ;;
            @loader_path/*|@executable_path/*) norm=$(gor_rpath_norm "$base/${line#@*_path/}") ;;
            /*)                              norm=$(gor_rpath_norm "$line") ;;
            *)                               norm="" ;;
        esac
        case "$norm" in
            "$anchor"|"$anchor"/*) rpath_dirs+=("$norm") ;;
            *) echo "      STOP (d): LC_RPATH outside vendor/node: $line" >&2; bad=1 ;;
        esac
    done < <(otool -l "$node" | grep -A2 LC_RPATH | grep 'path ' | sed 's/^[[:space:]]*path //; s/ (offset.*$//')
    [ "$bad" -eq 0 ] || return 1
    # resolved proof: every @rpath dependency must exist in an accepted dir
    while IFS= read -r dep; do
        found=0
        for d in "${rpath_dirs[@]}"; do [ -f "$d/$dep" ] && { found=1; break; }; done
        [ "$found" -eq 1 ] || { echo "STOP (d): node dependency $dep not found under the vendor/node rpaths" >&2; return 1; }
    done < <(otool -L "$node" | sed -n 's/^[[:space:]]*@rpath\/\([^ ]*\) (.*$/\1/p')
    echo "      node rpath: every LC_RPATH inside vendor/node"
}

# 176d: capability is a pre-install gate for every plain/update build.
# A missing/unsupported vendor must never replace the working installed app.
gor_require_mpv_lifeline() {
    local mpv_options
    [ -x "$project_root/Resources/vendor/mpv/bin/mpv" ] || {
        echo "lifeline: vendor mpv unavailable; app swap refused" >&2; return 1;
    }
    mpv_options=$("$project_root/Resources/vendor/mpv/bin/mpv" --list-options) || {
        echo "lifeline: vendor option check failed; app swap refused" >&2; return 1;
    }
    grep -Eq '^[[:space:]]*--input-ipc-client([[:space:]]|$)' <<< "$mpv_options" || {
        echo "lifeline: input-ipc-client unsupported; app swap refused" >&2; return 1;
    }
}

# ── the swap (block 174 item 11): small app only, no vendor ──────────────────
stage_dir="$project_root/.gor-stage"
stage_app="$stage_dir/gor.app"
installed_app="$project_root/gor.app"; [ "${update_mode:-false}" = true ] && rm -f "$stage_dir/.swap-done" # 191e-red-restore: run-scope the swap marker; a red update restores only this run's swap

gor_swap_install() {
    gor_require_mpv_lifeline || exit 1
    local first_run=false ts
    stop_running_gor   # called only here - a failed build never closes the app
    # Sealed-app detection is by CONTENT (a real vendor dir, not a symlink),
    # so an undo-restored sealed app is moved aside again. The aside name is
    # recorded so undo can name it exactly (no wildcards).
    if [ -e "$installed_app/Contents/Resources/vendor" ] && [ ! -L "$installed_app/Contents/Resources/vendor" ]; then
        ts=$(date +%y%m%d-%H%M%S)
        [ ! -e "$project_root/gor.app.instinct-$ts" ] || { echo "swap: aside name collision: gor.app.instinct-$ts" >&2; exit 1; }
        mv "$installed_app" "$project_root/gor.app.instinct-$ts" || { echo "swap: could not move the sealed gor.app aside" >&2; exit 1; }
        printf '%s\n' "$ts" > "$stage_dir/.first-aside"
        first_run=true
        echo "      first run: sealed gor.app moved to gor.app.instinct-$ts (left in place; owner decides)"
        echo "      gor.app.previous left exactly where it is. nothing deleted."
    fi
    # installed -> .gor-stage/gor.app.last (replacing the previous one)
    if [ -e "$installed_app" ]; then
        rm -rf "$stage_dir/gor.app.last.tmp"
        mv "$installed_app" "$stage_dir/gor.app.last.tmp" || { echo "swap: could not move installed app aside" >&2; exit 1; }
    fi
    # stage -> installed; on failure move the old app back
    if ! mv "$stage_app" "$installed_app"; then
        # v10.1 (peer finding F-A): EVERY manual instruction on this branch
        # names real paths and stays SAFE - or says plainly that no previous
        # app exists. Two traps removed: the fixed gor.app.last.tmp path was
        # wrong on a first sealed run (that slot is empty there; the backup
        # is gor.app.instinct-$ts), and any printed "mv backup target" while
        # the target still exists would NEST under BSD mv - so the park
        # failure/collision paths print paths + stop, never a blind mv.
        # A failed mv can leave a PARTIAL destination; never nest a restore
        # into it - park it aside first. 174c: one seconds-timestamp name;
        # a collision stops loudly, no retry loop.
        local restore_src=""
        if [ -e "$stage_dir/gor.app.last.tmp" ]; then
            restore_src="$stage_dir/gor.app.last.tmp"
        elif [ "$first_run" = true ] && [ -e "$project_root/gor.app.instinct-$ts" ]; then
            restore_src="$project_root/gor.app.instinct-$ts"
        fi
        if [ -n "$restore_src" ]; then
            echo "swap: install failed; moving the previous app back" >&2
        else
            echo "swap: install failed; no previous app exists - nothing to restore" >&2
        fi
        if [ -e "$installed_app" ]; then
            local p_aside="$stage_dir/gor.app.partial-$(date +%y%m%d-%H%M%S)"
            if [ -e "$p_aside" ]; then
                echo "exists: $p_aside — stopping; the partial install is at $installed_app" >&2
                if [ -n "$restore_src" ]; then
                    echo "      the previous app is safe at $restore_src - a verified non-destructive restore is needed (a plain mv would nest it inside the partial; do not move anything by hand without verifying both paths)" >&2
                else
                    echo "      no previous app exists - nothing to restore" >&2
                fi
                exit 1
            fi
            if ! mv "$installed_app" "$p_aside"; then
                echo "swap: cannot clear a partial install — stopping; the partial install is still at $installed_app" >&2
                if [ -n "$restore_src" ]; then
                    echo "      the previous app is safe at $restore_src - a verified non-destructive restore is needed (a plain mv would nest it inside the partial; do not move anything by hand without verifying both paths)" >&2
                else
                    echo "      no previous app exists - nothing to restore" >&2
                fi
                exit 1
            fi
            echo "      partial install parked at $p_aside (not deleted)" >&2
        fi
        if [ -e "$stage_dir/gor.app.last.tmp" ]; then
            mv "$stage_dir/gor.app.last.tmp" "$installed_app" || { echo "swap: restore failed; restore by hand: mv '$stage_dir/gor.app.last.tmp' '$installed_app'" >&2; exit 1; }
        elif [ "$first_run" = true ] && [ -e "$project_root/gor.app.instinct-$ts" ]; then
            mv "$project_root/gor.app.instinct-$ts" "$installed_app" || { echo "swap: restore failed; restore by hand: mv '$project_root/gor.app.instinct-$ts' '$installed_app'" >&2; exit 1; }
            rm -f "$stage_dir/.first-aside"
        fi
        exit 1
    fi
    if [ -e "$stage_dir/gor.app.last.tmp" ]; then
        rm -rf "$stage_dir/gor.app.last"
        mv "$stage_dir/gor.app.last.tmp" "$stage_dir/gor.app.last"
    fi
    touch "$stage_dir/.swap-done"
    if [ "$first_run" = true ]; then
        ls -ld "$project_root/gor.app.previous" "$project_root"/gor.app.instinct-* 2>/dev/null || true
    fi
}

gor_vendor_gate() {
    /usr/bin/python3 - "$project_root" "${1:-}" <<'GOR_VENDOR_GATE'
# Embedded 176g build preflight. Never execute on any platform but Darwin.
import os,sys,json,subprocess,tempfile,shutil,re,time,hashlib
from pathlib import Path
root=Path(sys.argv[1]);vendor=root/'Resources/vendor';cachepath=root/'.gor-vendor-gate.json'
full='--full' in sys.argv
if sys.platform!='darwin':raise SystemExit('176g requires native macOS tools')
report=[];edits={};extra={};pending={}
(root/'.gor-vendor-audit-last.txt').write_text('')
def fail_evidence(kind,error,tb):
    text='176g GATE FAIL '+str(error)
    print(text,file=sys.stderr)
    try:
        with (root/'.gor-vendor-audit-last.txt').open('a') as f:f.write(text+'\n')
    except OSError:pass
    sys.__excepthook__(kind,error,tb)
sys.excepthook=fail_evidence
def run(args):
    p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=20)
    if p.returncode:raise RuntimeError('command failed: '+str(args[0])+' '+p.stderr[-2048:])
    return p.stdout
def note(s):
    report.append(s);print(s,flush=True)
    with (root/'.gor-vendor-audit-last.txt').open('a') as f:f.write(s+'\n')
def tree_files(base):
    # Follow directory links once by physical identity, including frameworks.
    # Paths stay in vendor namespace for @loader_path and exact audit records.
    seen_dirs=set();seen_files=set();out=[]
    for directory,dirs,names in os.walk(base,followlinks=True):
        current=Path(directory);st=current.stat();key=(st.st_dev,st.st_ino)
        if key in seen_dirs:dirs[:]=[];continue
        seen_dirs.add(key)
        dirs[:]=sorted(dirs)
        for name in sorted(names):
            item=current/name
            if not item.is_file():continue
            st=item.stat();key=(st.st_dev,st.st_ino)
            if key in seen_files:continue
            seen_files.add(key);out.append(item)
    return sorted(out)
def macho(p):return 'Mach-O' in run(['/usr/bin/file','-b',p])
def deps(p):
    # dylib install ID is not a load dependency. -L lists it first, so
    # remove only the exact ID reported independently by -D.
    identity=run(['/usr/bin/otool','-D',p]).splitlines()[1:]
    ids={q.strip() for q in identity if q.strip()}
    return [l.strip().split(' (compatibility version',1)[0] for l in run(['/usr/bin/otool','-L',p]).splitlines()[1:] if l[:1].isspace() and l.strip().split(' (compatibility version',1)[0] not in ids]
def rpaths(p):
    lines=run(['/usr/bin/otool','-l',p]).splitlines();out=[]
    for i,l in enumerate(lines):
        if l.strip()=='cmd LC_RPATH':
            for q in lines[i+1:i+5]:
                m=re.match(r'\s*path (.+) \(offset \d+\)',q)
                if m:out.append(m.group(1));break
    return out
def system(edge):return edge.startswith(('/System/Library/','/usr/lib/'))
def expanded(edge,p):return edge.replace('@loader_path',str(p.parent)).replace('@executable_path',str(p.parent))
def effective_exists(p):return str(p) in pending or str(p) in extra or p.exists()
def validate(p,edges,rp):
    for edge in edges:
        if system(edge):continue
        if edge.startswith('/opt/homebrew/Cellar/'):raise RuntimeError('vendor gate: '+str(p.relative_to(vendor))+' forbidden edge '+edge)
        if edge.startswith('@rpath/'):
            paths=[Path(expanded(r,p))/edge[len('@rpath/'):] for r in rp if not r.startswith('@rpath')]
        elif edge.startswith(('@loader_path/','@executable_path/','/')):paths=[Path(expanded(edge,p))]
        else:raise RuntimeError('vendor gate: '+str(p.relative_to(vendor))+' unsupported edge '+edge)
        if not paths or not any(effective_exists(q) for q in paths):raise RuntimeError('vendor gate: '+str(p.relative_to(vendor))+' unresolved edge '+edge)
try:
    old={} if full else json.loads(cachepath.read_text())
except (OSError,ValueError):old={}
ROOTS=['mpv/bin/mpv','ffmpeg/bin/ffmpeg','node/node','gifsicle/bin/gifsicle','yt-dlp','chromium/chrome-headless-shell-mac-arm64/chrome-headless-shell','whisper/whisper-live','mus2/mus2']
def closure_records(inventory):
    closure=set();errors=[];seen=set()
    def read(p):
        if str(p) in inventory:return inventory[str(p)]
        actual=pending.get(str(p),p)
        if not isinstance(actual,Path):actual=p
        if not actual.is_file():return None
        return deps(actual),rpaths(actual)
    def walk(p,executable,inherited):
        p=Path(os.path.normpath(p));key=(str(p),str(executable))
        if key in seen:return
        seen.add(key);closure.add(str(p))
        record=read(p)
        if record is None:errors.append('closure missing file '+str(p));return
        edges,ownrp=record
        def expand(value):return value.replace('@loader_path',str(p.parent)).replace('@executable_path',str(executable.parent))
        search=list(dict.fromkeys([expand(q) for q in ownrp]+list(inherited)))
        for edge in edges:
            if system(edge):continue
            if edge.startswith('@rpath/'):
                choices=[Path(q)/edge[len('@rpath/'):] for q in search if not q.startswith('@')]
            elif edge.startswith(('@loader_path/','@executable_path/','/')):choices=[Path(expand(edge))]
            else:choices=[]
            selected=next((q for q in choices if effective_exists(q)),None)
            # For repair planning only, traverse verified same-loader sibling
            # as well; final closure still reports the original broken edge.
            missing_original=selected is None
            if selected is None and edge.startswith('/opt/homebrew/'):
                sibling=p.parent/Path(edge).name
                if sibling.is_file() and macho(sibling):selected=sibling
            # 178 narrows the gate to broken dependencies. A Homebrew-owned
            # library may reference its existing versioned sibling. Never
            # mutate it or reject that resolved edge as vendor packaging.
            if p.is_relative_to(vendor) and edge.startswith('/opt/homebrew/Cellar/'):
                errors.append('closure forbidden vendor Cellar edge '+str(p)+' '+edge)
            if missing_original:errors.append('closure unresolved edge '+str(p)+' '+edge)
            if selected is None:continue
            walk(selected,executable,search)
    for rel in ROOTS:
        p=vendor/rel
        walk(p,p,[])
    return closure,errors
ffbin=vendor/'ffmpeg/bin';ff=ffbin/'ffmpeg'
# Complete read-only inventory first. Do not stop at the first bad edge and
# make the owner discover the next file on another run.
files=tree_files(vendor);inventory={};audit_errors=[]
for p in files:
    st=p.stat();rel=str(p.relative_to(vendor));rec=old.get(rel)
    if rec and rec.get('stat')==[st.st_size,st.st_mtime_ns]:
        if rec.get('not_macho'):continue
        edges,rp=rec['deps'],rec['rpaths']
    else:
        if not macho(p):continue
        edges,rp=deps(p),rpaths(p)
    inventory[str(p)]=(edges,rp)
    note('176g INVENTORY '+rel+' '+json.dumps(edges))
    for edge in edges:
        try:validate(p,[edge],rp)
        except RuntimeError as error:audit_errors.append(str(error))
hard_closure,closure_errors=closure_records(inventory)
for path in sorted(hard_closure):note('178 HARD CLOSURE '+path)
for error in closure_errors:note('178 BEFORE CLOSURE ISSUE '+error)
# Non-closure issues are warnings only, emitted once per file below.
# The actual Mac named a historical ffmpeg-family directory under mpv/bin.
# Retain and repair it too, never omit it from the all-vendor gate. Only
# directories physically carrying libavcodec + libavutil qualify as ffmpeg.
ffdirs={ffbin}
for p in files:
    if p.name.startswith('libavcodec.') and any(q.name.startswith('libavutil.') for q in p.parent.iterdir()):ffdirs.add(p.parent)
for p in files:
    if str(p) not in hard_closure or p.parent not in ffdirs or str(p) not in inventory:continue
    edges=inventory[str(p)][0]
    note('176g ffmpeg BEFORE '+str(p.relative_to(vendor))+' '+json.dumps(edges))
    for edge in edges:
        cellar=edge.startswith('/opt/homebrew/Cellar/')
        broken_opt=edge.startswith('/opt/homebrew/opt/') and not Path(edge).exists()
        if not cellar and not broken_opt:continue
        if p.is_symlink():raise RuntimeError('ffmpeg repair symlink requires verified canonical layout: '+str(p))
        target=p.parent/Path(edge).name
        if broken_opt:
            if not target.is_file() or not macho(target):
                raise RuntimeError('missing stable edge without verified exact bundled Mach-O sibling: '+str(p)+' '+edge)
            edits.setdefault(str(p),{})[edge]='@loader_path/'+target.name
            continue
        parts=Path(edge).parts
        if len(parts)<7:raise RuntimeError('unrecognized Cellar edge '+edge)
        if not target.exists():
            if p.parent!=ffbin:
                raise RuntimeError('historical ffmpeg-family edge lacks SAME-directory exact ABI sibling; no cross-directory/current-version borrowing: '+str(p)+' '+edge)
            stable=Path('/opt/homebrew/opt')/parts[4]/Path(*parts[6:])
            if not stable.is_file():raise RuntimeError('missing bundled and current stable dependency: '+str(target)+' / '+str(stable))
            if str(target) in extra and extra[str(target)]!=str(stable):raise RuntimeError('conflicting dependency destination '+str(target))
            extra[str(target)]=str(stable)
        elif not target.is_file() or not macho(target):raise RuntimeError('bundled dependency is not exact Mach-O sibling: '+str(target))
        edits.setdefault(str(p),{})[edge]='@loader_path/'+target.name
# Recursively inspect newly copied leaves; no unresolved absolute Cellar edge escapes.
queue=list(extra)
for target in queue:
    source=Path(extra[target]);p=Path(target)
    if not macho(source):raise RuntimeError('not Mach-O dependency '+str(source))
    for edge in deps(source):
        if edge.startswith('/opt/homebrew/opt/') and not Path(edge).exists():
            other=p.parent/Path(edge).name
            if not other.is_file() or not macho(other):
                raise RuntimeError('missing imported stable edge without exact bundled Mach-O sibling: '+str(p)+' '+edge)
            edits.setdefault(target,{})[edge]='@loader_path/'+other.name
        if edge.startswith('/opt/homebrew/Cellar/'):
            parts=Path(edge).parts;other=p.parent/Path(edge).name
            if not other.exists() and str(other) not in extra:
                stable=Path('/opt/homebrew/opt')/parts[4]/Path(*parts[6:])
                if not stable.is_file():raise RuntimeError('missing transitive stable dependency '+str(stable))
                extra[str(other)]=str(stable);queue.append(str(other))
            edits.setdefault(target,{})[edge]='@loader_path/'+other.name
# Preserve 174/174a mpv hardening in addition to the expanded generic gate.
mpv=vendor/'mpv/bin/mpv'
placebo='/opt/homebrew/opt/libplacebo/lib/libplacebo.360.dylib'
vulkan='/opt/homebrew/opt/vulkan-loader/lib/libvulkan.1.dylib'
if not mpv.is_file() or not Path(placebo).is_file() or not Path(vulkan).is_file():
    raise RuntimeError('mpv policy: required mpv/Homebrew libplacebo/Vulkan file missing')
mpv_edges=deps(mpv)
if mpv_edges.count(placebo)!=1 or mpv_edges.count(vulkan)!=1:
    raise RuntimeError('mpv policy: expected exactly one stable Homebrew libplacebo and Vulkan edge')
for edge in mpv_edges:
    if ('p162b-deps' in edge or '@loader_path/../lib/' in edge or
        (('libplacebo' in edge or 'libvulkan' in edge) and edge not in [placebo,vulkan])):
        raise RuntimeError('mpv policy: forbidden bundled/unexpected edge '+edge)
placebo_edges=deps(Path(placebo))
if placebo_edges.count(vulkan)!=1 or any('libvulkan' in edge and edge!=vulkan for edge in placebo_edges):
    raise RuntimeError('mpv policy: Homebrew libplacebo must use the single expected Vulkan loader')
note('176g mpv policy OK stable Homebrew libplacebo/Vulkan edges, bundled alternatives refused')
# Stage only changed leaves and the ffmpeg executable, not the vendor tree.
with tempfile.TemporaryDirectory(prefix='gor-176g-vendor.') as td:
    stage=Path(td);stagebin=stage/ffbin.relative_to(vendor);stagebin.mkdir(parents=True)
    changed=set(edits)|set(extra)
    staged={}
    total=sum(Path(extra.get(p,p)).stat().st_size for p in changed)
    if ff.exists() and str(ff) not in changed:total+=ff.stat().st_size
    if shutil.disk_usage(stage).free<total*2+64*1024*1024:raise RuntimeError('insufficient staging/backup space for measured repair bytes')
    # A flat ffmpeg bin is the authorized dependency repair boundary. Refuse
    # collisions rather than flattening a different layout by guess.
    for p in sorted(changed):
        if Path(p).parent not in ffdirs:raise RuntimeError('repair outside verified ffmpeg-family directory: '+p)
        dest=stage/Path(p).relative_to(vendor);dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():raise RuntimeError('duplicate staged dependency destination '+str(dest))
        shutil.copyfile(extra.get(p,p),dest);shutil.copymode(extra.get(p,p),dest);staged[p]=dest;pending[p]=dest
        for oldedge,newedge in edits.get(p,{}).items():
            run(['/usr/bin/install_name_tool','-change',oldedge,newedge,dest])
            note('176g FIX '+str(Path(p).relative_to(vendor))+' '+oldedge+' -> '+newedge)
        if p in extra or dest.suffix=='.dylib':run(['/usr/bin/install_name_tool','-id','@loader_path/'+dest.name,dest])
    # Full audit on first run. Later unchanged size+mtime files reuse last-good
    # parsed load commands, but EVERY edge still resolves on disk each run.
    files=tree_files(vendor)
    files+= [Path(p) for p in extra if not Path(p).exists()]
    final_inventory={};records={}
    for p in files:
        rel=str(p.relative_to(vendor));actual=staged.get(str(p),p)
        st=actual.stat();stamp=[st.st_size,st.st_mtime_ns]
        rec=old.get(rel)
        if str(p) in staged or not rec or rec.get('stat')!=stamp:
            if not macho(actual):records[rel]={'stat':stamp,'not_macho':True};continue
            rec={'stat':stamp,'deps':deps(actual),'rpaths':rpaths(actual)}
        records[rel]=rec
        if not rec.get('not_macho'):final_inventory[str(p)]=(rec['deps'],rec['rpaths'])
    final_closure,final_errors=closure_records(final_inventory)
    for p in files:
        rel=str(p.relative_to(vendor));rec=records.get(rel)
        if not rec or rec.get('not_macho'):continue
        if str(p) in final_closure:
            note('178 HARD OK '+rel+' '+json.dumps(rec['deps']))
        else:
            note('178 WARNING outside spawned dependency closure: '+rel+'; retained unchanged')
    for error in final_errors:note('178 HARD FAIL '+error)
    if final_errors:raise RuntimeError('spawned dependency closure refused '+str(len(final_errors))+' broken/forbidden edges; complete issues listed above')
    pending.update(records)
    # Validate the repaired ffmpeg executable before publishing source leaves.
    if changed:
        for directory in ffdirs:
            staged_dir=stage/directory.relative_to(vendor);staged_dir.mkdir(parents=True,exist_ok=True)
            for p in directory.iterdir():
                if not (staged_dir/p.name).exists():
                    if p==ff:shutil.copy2(p,staged_dir/p.name)
                    else:(staged_dir/p.name).symlink_to(p)
        for p in staged.values():run(['/usr/bin/codesign','--force','--sign','-',p])
        run(['/usr/bin/codesign','--force','--sign','-',stagebin/'ffmpeg'])
        version=run([stagebin/'ffmpeg','-version']);note('176g ffmpeg staged version '+version.splitlines()[0])
        # Only after whole-vendor validation and standalone proof: preserve all
        # old changed leaves in the source backup, then atomically publish.
        backup=root/'.gor-backups'/(time.strftime('%y%m%d-%H%M%S')+'-'+str(os.getpid())+'-176g-vendor')
        backup.mkdir(parents=True,exist_ok=False);changes=[]
        for p in sorted(changed):
            dst=Path(p);rel=dst.relative_to(root);saved=backup/rel
            if dst.exists():saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,saved);changes.append('changed\t'+str(rel))
            else:changes.append('added\t'+str(rel))
        (backup/'changes.txt').write_text('\n'.join(changes)+'\n')
        published=[]
        try:
            for p in sorted(changed):
                dst=Path(p);tmp=dst.with_name(dst.name+'.176g-tmp')
                if tmp.exists():raise RuntimeError('stale repair temp exists '+str(tmp))
                shutil.copy2(staged[p],tmp);os.replace(tmp,dst);published.append(dst)
            version=run([ff,'-version']);note('176g ffmpeg PROOF '+version.splitlines()[0])
        except Exception:
            # Roll back only leaves published by this repair, old bytes safe.
            for dst in reversed(published):
                saved=backup/dst.relative_to(root)
                if saved.exists():shutil.copy2(saved,dst)
                else:dst.unlink()
            raise
        note('176g source backup '+str(backup))
    else:
        version=run([ff,'-version']);note('176g ffmpeg PROOF '+version.splitlines()[0])
    # Do not promote cache until the build's normal last-good mirror promotion.
    records={k:v for k,v in pending.items() if isinstance(v,dict)}
    for rel,rec in records.items():
        st=(vendor/rel).stat();rec['stat']=[st.st_size,st.st_mtime_ns]
    (root/'.gor-vendor-gate.pending.json').write_text(json.dumps(records,sort_keys=True))
    (root/'.gor-vendor-audit-last.txt').write_text('\n'.join(report)+'\n')
    note('176g AUDIT '+('FULL' if not old else 'incremental')+' Mach-O='+str(sum(not v.get('not_macho') for v in records.values()))+' repaired-leaves='+str(len(changed)))

GOR_VENDOR_GATE
}

# Identity record. Write-only; call ONLY before codesign of the staged bundle.
gor_write_build_id() {
    local brew_ref='/opt/homebrew/opt/libplacebo/lib/libplacebo.360.dylib'
    printf 'serial=%s\nbuild_sh_sha256=%s\nmpv_libplacebo=%s\n' "$GOR_BUILD_SH_SERIAL" "$GOR_BUILD_SH_SHA256_AT_START" "$brew_ref" > "$res/.gor-build-sh-id" || return 1
}

# The updater stages a Google-signed Chromium tree outside source. 174: vendor
# is a symlink; the stage is VALIDATED here and promoted only after a good swap.
chromium_stage="$build_dir/chromium-update"
chromium_stage_active=false
if [ -d "$chromium_stage" ]; then
    staged_rel="$(cat "$chromium_stage/binary-relative-path.txt")"
    case "$staged_rel" in
        chrome-headless-shell|*/chrome-headless-shell) ;;
        *) echo "invalid chromium stage path" >&2; exit 1 ;;
    esac
    case "$staged_rel" in ../*|*/../*|/*) echo "invalid chromium stage path" >&2; exit 1 ;; esac
    staged_dir="$(dirname "$staged_rel")"
    staged_binary="$chromium_stage/payload/$staged_rel"
    test -f "$staged_binary" || { echo "incomplete chromium stage" >&2; exit 1; }
    # Only replace the tree containing the existing browser, never guess a path.
    test -f "$project_root/Resources/vendor/chromium/$staged_rel" || { echo "chromium bundled path differs from stage" >&2; exit 1; }
    staged_version="$(cat "$chromium_stage/version.txt")"
    actual_version="$("$staged_binary" --version 2>/dev/null)"
    case "$actual_version" in
        *"$staged_version") ;;
        *) echo "staged chromium version mismatch" >&2; exit 1 ;;
    esac
    if [ "$staged_dir" = . ]; then
        echo "root-level chromium stage unsupported" >&2
        exit 1
    fi
    chromium_stage_active=true
    echo "      chromium stage validated: $staged_version (promoted to source after a successful swap)"
fi

# 176g: validate/stage/repair vendor before cleaning, compiling, or app swap.
# A gate failure preserves vendor/app bytes; full inventory stays in project.
gor_vendor_gate || exit 1

# ── cleaning (block 174 item 3: the running app is NOT stopped here) ─────────
next_step; echo "cleaning..."
build_uid=$(id -u)
if [ "$clean_build" = true ]; then
    rm -rf "$project_root/.build"
fi
# Only the stage app is reset at start; the installed app is untouched.
rm -rf "$stage_app"

# Compile before installing capture; failure is explicit, never silently raw.
# ── gor-log-writer build cache (174 cache direction; prep r1) ─────────────────
# Provenance: PERFORMANCE CACHE, NOT a security boundary. A cache-internal
# failure NEVER fails the build and NEVER weakens an existing gate; every
# failure logs a reason and falls back to the plain path. Growth UNBOUNDED
# (one dir per distinct key); cleanup is owner-only; no entry is ever deleted
# or replaced (the only removal anywhere is rmdir of this run's own empty .pub-* scratch). Exclusive publication: mkdir <keydir> is the atomic claim; no
# dir-over-dir mv (no nesting); hit contract needs payload AND meta, so a
# partial publish always validates false and is neither used nor modified.
gor_cache_root="$project_root/.gor-cache/gor-log-writer"

gor_cache_key() { # $1 = materialized main.swift (written once, read once here)
    local src="$1"
    {
      printf 'src=%s\n' "$(shasum -a 256 "$src" | awk '{print $1}')"
      printf 'swiftc_path=%s\n' "$(xcrun -f swiftc 2>/dev/null || echo unresolved)"
      printf 'swiftc_ver=%s\n' "$(xcrun swiftc --version 2>&1 || echo unresolved)"
      printf 'sdk_path=%s\n' "$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo unresolved)"
      printf 'sdk_ver=%s\n' "$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo unresolved)"
      printf 'developer_dir=%s\n' "${DEVELOPER_DIR-unset}"
      printf 'sdkroot=%s\n' "${SDKROOT-unset}"
      printf 'deployment_target=%s\n' "${MACOSX_DEPLOYMENT_TARGET-unset}"
      printf 'xcode_select=%s\n' "$(xcode-select -p 2>/dev/null || echo unresolved)"
      printf 'arch=%s\n' "$(uname -m)"
      printf 'argv=%s\n' 'xcrun swiftc <src> -o <out>'
      printf 'sign=%s\n' 'codesign --force --sign -'
    } | shasum -a 256 | awk '{print $1}'
}

gor_cache_parent_ok() { # every level, before any mkdir; symlink/perms guarded
    local d
    for d in "$project_root/.gor-cache" "$gor_cache_root"; do
        if [ -L "$d" ]; then echo "[GOR] log writer cache: parent symlink $d" >&2; return 1; fi
        if [ -e "$d" ]; then
            [ -d "$d" ] || { echo "[GOR] log writer cache: parent not a dir $d" >&2; return 1; }
        else
            mkdir "$d" 2>/dev/null || { echo "[GOR] log writer cache: mkdir failed $d" >&2; return 1; }
            { [ -d "$d" ] && [ ! -L "$d" ]; } || { echo "[GOR] log writer cache: post-mkdir invalid $d" >&2; return 1; }
        fi
        [ $(( 0$(stat -f %Lp "$d") & 022 )) -eq 0 ] || { echo "[GOR] log writer cache: permissive parent $d" >&2; return 1; }
    done
}

gor_cache_contained() { # $1 = file; literal byte prefix, no case folding
    local rp_base rp_f
    rp_base=$(cd "$gor_cache_root" 2>/dev/null && pwd -P) || return 1
    rp_f=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1") || return 1
    case "$rp_f" in "$rp_base"/*) return 0 ;; *) return 1 ;; esac
}

gor_cache_hit_valid() { # $1 = keydir, $2 = key; prints miss reason or nothing
    local bin="$1/gor-log-writer" meta="$1/meta"
    { [ -f "$bin" ] && [ ! -L "$bin" ]; } || { echo 'no-entry'; return 1; }
    { [ -f "$meta" ] && [ ! -L "$meta" ] && grep -q "^key=$2\$" "$meta"; } || { echo 'meta'; return 1; }
    [ "$(stat -f %u "$bin")" = "$EUID" ] || { echo 'owner'; return 1; }
    [ $(( 0$(stat -f %Lp "$bin") & 022 )) -eq 0 ] || { echo 'perms'; return 1; }
    gor_cache_contained "$bin" || { echo 'containment'; return 1; }
    codesign --verify --strict "$bin" 2>/dev/null || { echo 'codesign'; return 1; }
    return 0
}

gor_cache_publish() { # $1 = keydir (absent), $2 = built binary, $3 = key
    local pub
    mkdir "$1" 2>/dev/null || return 1   # exclusive claim; an existing dir is never ours
    pub=$(mktemp -d "$gor_cache_root/.pub-XXXXXX") || return 1   # same volume: atomic mv
    cp "$2" "$pub/gor-log-writer" 2>/dev/null || return 1
    codesign --verify --strict "$pub/gor-log-writer" 2>/dev/null || return 1
    mv "$pub/gor-log-writer" "$1/gor-log-writer" 2>/dev/null || return 1
    printf 'key=%s\npublished=%s\n' "$3" "$(date +%s)" > "$1/meta" 2>/dev/null || return 1
    rmdir "$pub" 2>/dev/null || true   # scratch created by THIS run; retained cache entries are never deleted
}

gor_mark writer-start
log_writer_dir=$(mktemp -d /tmp/gor-log-writer.XXXXXX)
log_writer="$log_writer_dir/gor-log-writer"
log_writer_enabled=false
# Writer source is embedded here on purpose: it has top-level code, so it must
# never sit as a .swift file inside Sources/gor (SwiftPM would reject it).
cat > "$log_writer_dir/main.swift" <<'GOR_LOG_WRITER_EOF'
// Standalone line writer shared by build.sh and the app. No privileged tools.
import Foundation
import Darwin
import IOKit

private let args = CommandLine.arguments
private func value(_ key: String, _ fallback: String) -> String {
    guard let i = args.firstIndex(of: key), i + 1 < args.count else { return fallback }
    return args[i + 1]
}
private let timestampEnabled = value("--timestamp", "true") == "true"
private let cpuEnabled = value("--cpu-info", "true") == "true"
private let echoEnabled = !args.contains("--quiet")
private let destination = value("--output", "/tmp/gor_direct.log")
private let output = open(destination, O_RDWR | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
guard output >= 0 else { exit(1) }
private let sampleLock = NSLock()
private var sampledAt: UInt64 = 0
private var cpuPercent: Double?
private var cpuTemperature: Double?
private var previousTicks: [UInt32]?
private let hostPort = mach_host_self()
private let clock = ISO8601DateFormatter()
clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

// Private HID API is optional. Missing symbols/sensors never become zero C.
private final class CPUThermometer {
    typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias Match = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    typealias Property = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    typealias Event = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double
    var lastMax = 0.0; private let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
    func read() -> Double? {
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let match = symbol("IOHIDEventSystemClientSetMatching", Match.self),
              let services = symbol("IOHIDEventSystemClientCopyServices", Services.self),
              let property = symbol("IOHIDServiceClientCopyProperty", Property.self),
              let event = symbol("IOHIDServiceClientCopyEvent", Event.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", FloatValue.self),
              let client = create(nil)?.takeRetainedValue() else { return nil }
        _ = match(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let list = services(client)?.takeRetainedValue() else { return nil }
        var temperatures = [Double]()
        for service in list as [AnyObject] {
            guard let product = property(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  product.hasPrefix("eACC MTR Temp Sensor") || product.hasPrefix("pACC MTR Temp Sensor"),
                  let reading = event(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            let degrees = floatValue(reading, 15 << 16)
            if degrees.isFinite && degrees > 0 && degrees < 150 { temperatures.append(degrees) }
        }
        lastMax = temperatures.max() ?? 0; return temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count)
    }
}
private let thermometer = CPUThermometer()
private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "gor.log.sample", qos: .utility))
if cpuEnabled {
    timer.schedule(deadline: .now(), repeating: 1)
    timer.setEventHandler {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        var percent: Double?
        if status == KERN_SUCCESS {
            let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let previous = previousTicks {
                let deltas = zip(ticks, previous).map { UInt64($0.0 &- $0.1) }
                let total = deltas.reduce(0, +)
                if total > 0 { percent = 100 * Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) }
            }
            previousTicks = ticks
        }
        let temperature = thermometer.read()
        sampleLock.lock()
        cpuPercent = percent
        cpuTemperature = temperature
        sampledAt = DispatchTime.now().uptimeNanoseconds
        sampleLock.unlock()
    }
    timer.resume()
}
private func number(_ value: Double?) -> String {
    value.map { String(format: "%.1f", $0) } ?? "unavailable"
}
private func writeAll(_ fd: Int32, _ bytes: Data) -> Bool {
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return true }
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}
private func emit(_ body: Data, partial: Bool = false) {
    var fields = [String]()
    if timestampEnabled { fields.append("ts=" + clock.string(from: Date())) }
    if cpuEnabled {
        sampleLock.lock()
        let age = sampledAt == 0 ? nil : Double(DispatchTime.now().uptimeNanoseconds - sampledAt) / 1e9
        let fresh = age.map { $0 <= 3 } ?? false
        let cpu = fresh ? cpuPercent : nil
        let temperature = fresh ? cpuTemperature : nil
        sampleLock.unlock()
        fields += ["cpu_system_pct=" + number(cpu), "cpu_temp_c=" + number(temperature), "cpu_temp_max_c=" + number(temperature == nil ? nil : thermometer.lastMax),
                   "sample_age_s=" + number(age), "temp_source=hid_cpu_average"]
    }
    var row = Data((fields.isEmpty ? "" : "[" + fields.joined(separator: " ") + "] ").utf8)
    row.append(body)
    if !partial { row.append(10) }
    // Build compiler capture and runtime writers can append concurrently.
    // Serialize the complete record, including any short-write retries.
    guard flock(output, LOCK_EX) == 0 else { exit(1) }
    let cap=10*1024*1024; var st=stat(); guard fstat(output,&st)==0 else {_ = flock(output,LOCK_UN);exit(1)}
    let written = st.st_size+off_t(row.count)>off_t(cap) || writeAll(output,row) //195w W4: cap same file; no .prev rotation
    _ = flock(output, LOCK_UN)
    if !written { exit(1) }
    if echoEnabled { _ = writeAll(STDOUT_FILENO, row) }
}
var pending = Data()
var buffer = [UInt8](repeating: 0, count: 8192)
while true {
    let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
    if count < 0 && errno == EINTR { continue }
    if count <= 0 { break }
    pending.append(contentsOf: buffer.prefix(count))
    while let newline = pending.firstIndex(of: 10) {
        emit(Data(pending[..<newline]))
        pending.removeSubrange(...newline)
    }
    // Bound unbroken binary/no-newline output, retaining bytes as partial fragments.
    if pending.count >= 1_048_576 { emit(pending, partial: true); pending.removeAll(keepingCapacity: true) }
}
if !pending.isEmpty { emit(pending, partial: true) }
mach_port_deallocate(mach_task_self_, hostPort)
close(output)
GOR_LOG_WRITER_EOF
writer_key=$(gor_cache_key "$log_writer_dir/main.swift" 2>/dev/null || echo none)
if [ "$writer_key" != none ] && gor_cache_parent_ok; then
    # set -e (L2): the miss rc=1 branches explicitly in the if condition; no
    # failure suppression. $cache_miss_reason carries the diagnostic on miss.
    if cache_miss_reason=$(gor_cache_hit_valid "$gor_cache_root/$writer_key" "$writer_key"); then
        log_writer="$gor_cache_root/$writer_key/gor-log-writer"
        log_writer_enabled=true
        echo "[GOR] log writer cache hit"
    else
        echo "[GOR] log writer cache miss: $cache_miss_reason (entry retained)"
    fi
fi
if [ "$log_writer_enabled" != true ]; then
    if xcrun swiftc "$log_writer_dir/main.swift" -o "$log_writer"; then
        echo "[GOR] signing log writer"
        if codesign --force --sign - "$log_writer"; then
            echo "[GOR] log writer signature ready"
            log_writer_enabled=true
            # Best-effort publish. Publish failure never disables the writer and
            # never fails the build.
            if [ "$writer_key" != none ] && gor_cache_parent_ok; then
                if [ -e "$gor_cache_root/$writer_key" ]; then
                    echo "[GOR] log writer cache publish skipped: key exists"
                else
                    gor_cache_publish "$gor_cache_root/$writer_key" "$log_writer" "$writer_key"                         || echo "[GOR] log writer cache publish failed (run continues uncached)"
                fi
            fi
        else
            echo "[GOR] log writer signing failed: raw log, no timestamp/cpu"
        fi
    else
        echo "[GOR] log writer compile failed: raw log, no timestamp/cpu"
    fi
fi
gor_mark writer-end

unset GOR_LOG_SESSION_DIR #195w W4: original shared raw paths
GOR_LOG_SESSION_DIR=/tmp
append_direct_log() {
    # Compiler output bypasses the normal stdout filter. Feed the same full
    # record to the sole separate-log writer, never a second file writer.
    if [ "$separate_build_log" = true ]; then cat "$1" >&5; fi
    if [ "$log_writer_enabled" = true ]; then
        "$log_writer" --quiet --timestamp "$log_timestamp" --cpu-info "$log_cpu_info" < "$1"
    else
        cat "$1" >> "$GOR_LOG_SESSION_DIR/gor_direct.log"
    fi
}
# Capture all build output in the direct log regardless of launch/log mode.
# AppDelegate appends its runtime output to this same file after launch.
: > "$GOR_LOG_SESSION_DIR/gor_direct.log"
gor_mark handover
exec 3>&1
if [ "$log_writer_enabled" = true ]; then
    exec > >("$log_writer" --timestamp "$log_timestamp" --cpu-info "$log_cpu_info" >&3) 2>&1
else
    exec > >(tee -a "$GOR_LOG_SESSION_DIR/gor_direct.log" >&3) 2>&1
fi
for m in "${gor_phase_marks[@]}"; do echo "[GOR-t] $m"; done

# One EXIT cleanup owns scratch files and this build's log viewer.
# Dock launches write the same log, so never leave a tail attached to this tty.
whisper_build_log=""
temporary_build_log=""
source_snapshot=""
exclude_file=""
manifest_tmp=""
metadata_tmp=""
TAILPID=""
stop_log_viewer() {
    if [ -n "$TAILPID" ]; then
        kill "$TAILPID" 2>/dev/null || true
        # Viewer has no state to save. KILL also covers an exit-before-exec
        # race where its background shell has not reset inherited traps yet.
        kill -KILL "$TAILPID" 2>/dev/null || true
        wait "$TAILPID" 2>/dev/null || true
        TAILPID=""
    fi
}
cleanup_build_run() {
    stop_log_viewer
    if [ -n "$separate_log_dir" ]; then rm -rf "$separate_log_dir" || true; fi
    rm -rf "$log_writer_dir"
    local scratch
    for scratch in "$whisper_build_log" "$temporary_build_log" \
        "$exclude_file" "$manifest_tmp" "$metadata_tmp" "$source_snapshot"; do
        if [ -n "$scratch" ]; then rm -f "$scratch" || true; fi
    done
    gor_release_build_lock
    gor_cleanup_snapshot
}
if [ "${update_mode:-false}" = true ]; then
    trap 'gor_update_exit_trap "$?"' EXIT
else
    trap cleanup_build_run EXIT
fi
trap 'exit 130' INT
trap 'exit 143' TERM

# ── paths ─────────────────────────────────────────────────────────────────────
app_name="gor"
bundle_id="com.gokcebalkan.gor"
# project_root is already fixed and locked before any shared side effects.
icon_source="$project_root/Resources/icon/_icon.png"

build_dir="$project_root/.build"
debug_bin=""  # Resolved from SwiftPM after a successful product build.

# ── whisper-live (optional) ────────────────────────────────────────────────────
if [ "$build_whisper" = true ]; then
    next_step whisper-live; echo "building whisper-live..."
    if [ ! -d "$whisper_src_dir" ]; then
        echo "      ✗ whisper_src_dir not found: $whisper_src_dir"
        echo "        (edit whisper_src_dir near the top of this script if it moved)"
        exit 1
    fi
    whisper_build_log=$(mktemp /tmp/gor-whisper-build.XXXXXX)
    if ! (cd "$whisper_src_dir" && cmake --build build --target whisper-live) \
        > "$whisper_build_log" 2>&1; then
        append_direct_log "$whisper_build_log"
        echo "      ✗ whisper-live build failed - see $GOR_LOG_SESSION_DIR/gor_direct.log"
        exit 1
    fi
    append_direct_log "$whisper_build_log"
    whisper_bin="$whisper_src_dir/build/bin/whisper-live"
    whisper_dest="$project_root/Resources/vendor/whisper/whisper-live"
    if [ ! -f "$whisper_bin" ]; then
        echo "      ✗ build reported success but binary missing: $whisper_bin"
        exit 1
    fi
    cp "$whisper_bin" "$whisper_dest"
    echo "      done → $whisper_dest"
fi

# ── source backup before the swift build (block 174) ─────────────────────────
if [ ! -d "$mirror_dir" ]; then
    gor_mirror_init
fi
gor_mark mirror-diff-start
gor_mirror_diff
gor_backup_write
gor_mark backup-end

# GOR_SOURCE_SNAPSHOT_BEGIN
source_snapshot=$(mktemp /tmp/gor-source-snapshot.XXXXXX)
/usr/bin/python3 - "$project_root" "$source_snapshot" <<'PY_SOURCE'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
paths = [root / 'Package.swift', root / 'build.sh'] + sorted((root / 'Sources/gor').rglob('*.swift')) + sorted(p for p in (root / 'Packages').rglob('*') if p.is_file() and '.build' not in p.parts)
if len(paths) < 3:
    raise SystemExit('No Swift sources found; refusing build')
records = {}
for path in paths:
    if path.is_symlink() or not path.is_file():
        raise SystemExit('Non-regular build input: ' + str(path))
    records[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
pathlib.Path(sys.argv[2]).write_text(json.dumps(records, indent=2, sort_keys=True) + '\n')
print('      source snapshot sha256: ' + hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest())
PY_SOURCE
# GOR_SOURCE_SNAPSHOT_END

if [ -f "$project_root/scripts/arch_check.py" ]; then
    if ! /usr/bin/python3 "$project_root/scripts/arch_check.py" --root "$project_root" --report > "$project_root/.gor-architecture-last.txt" 2>&1; then
        echo 'architecture: recoverable warning; gate could not run; prior install retained until normal swap'
    fi
    cat "$project_root/.gor-architecture-last.txt"
else
    echo 'architecture: recoverable warning; gate asset missing; continuing normal build' | tee "$project_root/.gor-architecture-last.txt"
fi
# ── swift build — touches the stage app only on success ──────────────────────
next_step; echo "building..."
build_start=$(date +%s)
temporary_build_log=$(mktemp /tmp/gor-swift-build.XXXXXX)
build_log="$temporary_build_log"
# block 174 item 4: pipefail; pass or fail comes from the exit status.
set -o pipefail
exec 6>&3
if [ "$separate_build_log" = true ]; then exec 6>&4; fi
swift_status=0
/usr/bin/python3 "$project_root/tools/build-with-gorav-provider.py" --package-path "$project_root" --scratch-path "$build_dir" -c debug --product "$app_name" > "$build_log" 2>&1 || swift_status=$?
append_direct_log "$build_log"
if [ "$show_warnings" = true ] || [ "$swift_status" -ne 0 ]; then
    cat "$build_log" >&6
else
    grep -E 'error:|Build complete|Build of product .* complete!' "$build_log" >&6 || true
fi
build_end=$(date +%s)
build_elapsed=$((build_end - build_start))
if [ "$swift_status" -ne 0 ]; then
    # Preserve only bounded compiler diagnostics in the existing empty result
    # commit. Scrubbed bounded tail only; never raw logs, media paths or URLs.
    if [ "${update_mode:-false}" = true ]; then
        update_compile_detail=$(/usr/bin/python3 - "$build_log" <<'GOR_COMPILE_ERRORS'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
data=p.read_bytes()
lines=data.decode('utf-8','replace').splitlines()
def scrub(s):
    s=re.sub(r'(?:/[^\s:]+)+/([^/\s:]+\.swift)(:\d+:\d+:)',r'\1\2',s)
    s=re.sub(r'https?://\S+','[URL]',s)
    return re.sub(r'(?<!\w)/(?:[^\s:]+/)*[^\s:]*','[path]',s)[:600]
# Full-log scan: an early error (e.g. 48s into a 195s build) is pushed past
# any tail bound by later parallel-job warnings; error lines are rare, so the
# whole log is scanned and repeats (same diagnostic per target) are deduped.
print('current-update-compiler-errors (full-log scan, max 12 unique diagnostics):')
n=0;total=0;seen=set()
for line in lines:
    if 'error:' not in line:continue
    total+=1
    s=scrub(line)
    if s in seen:continue
    seen.add(s)
    print(s);n+=1
    if n>=12:break
print('compiler-error-lines='+str(total)+' unique-shown='+str(n))
if n==0:
    tail=lines[-200:] if len(data)<=131072 else data[-131072:].decode('utf-8','replace').splitlines()[-200:]
    print('current-update-build-tail (stage=swift build, no diagnostics matched; last 200 lines scrubbed):')
    for line in tail:print(scrub(line))
GOR_COMPILE_ERRORS
        ) || update_compile_detail="current-update-compiler-errors: extraction failed"
    fi
    echo ""
    echo "      ✗ build failed (${build_elapsed}s) — previous bundle preserved"
    gor_mirror_note_failure
    exit "$swift_status"
fi
echo "      done (${build_elapsed}s swift)"
debug_bin="$build_dir/debug/$app_name"
if [ ! -x "$debug_bin" ]; then echo "SwiftPM product missing: $debug_bin" >&2; gor_mirror_note_failure; exit 1; fi
# ── bundle (block 174 items 5-8) ──────────────────────────────────────────────
next_step; echo "linking resources..."
mkdir -p "$dest" "$res"
# item 6 (amended 2026-11-02, owner direction relayed by Main from original
# phonemsg-01M6EZRZXW7J2QWWXFCCWY1M2M): vendor and fonts stay outside the app.
# The observed build-created aliases are removed (owner diagnostic 2026-11-02,
# relayed); the strict verify gate is unchanged. The installed app resolves both
# folders from the sibling source Resources directory at runtime (production
# resolver, Swift side).
gor_external_assets_preflight() {
    local name dir base resolved
    base=$(cd "$project_root" 2>/dev/null && pwd -P) || {
        echo "external assets preflight: project_root unresolvable; installed app unchanged." >&2; return 1; }
    for name in vendor fonts; do
        dir="$project_root/Resources/$name"
        if [ -L "$dir" ] || [ ! -d "$dir" ]; then
            echo "external assets preflight: Resources/$name is missing or not a real directory; installed app unchanged." >&2
            return 1
        fi
        resolved=$(cd "$dir" 2>/dev/null && pwd -P) || {
            echo "external assets preflight: Resources/$name unresolvable; installed app unchanged." >&2; return 1; }
        case "$resolved/" in
            "$base"/*) : ;;
            *) echo "external assets preflight: Resources/$name resolves outside the project tree; installed app unchanged." >&2
               return 1 ;;
        esac
    done
}
gor_external_assets_preflight || { gor_mirror_note_failure; exit 1; }
# item 7: the source file is the authority, as in the current build.
entitlements_path="$project_root/Resources/gor.entitlements"
cp -p "$entitlements_path" "$res/gor.entitlements"
echo "      done"
next_step; echo "creating bundle..."
cp "$debug_bin" "$dest/$app_name"
chmod u+w "$dest/$app_name"
rm -f "$dest/gor-log-writer"
if [ "$log_writer_enabled" = true ]; then
    cp "$log_writer" "$dest/gor-log-writer"
fi
printf '{"timestamp":%s,"cpu_info":%s}\n' "$log_timestamp" "$log_cpu_info" > "$res/gor-log-config.json"
cp "$project_root/tools/gor-periodic-capture.py" "$res/gor-periodic-capture.py"; cp "$project_root/tools/bounded_log_archives.py" "$res/bounded_log_archives.py"; cp "$project_root/tools/session_log_paths.py" "$res/session_log_paths.py"; cp "$project_root/gor-capture-channel.py" "$res/gor-capture-channel.py"; /usr/bin/python3 -c 'import json,sys;from pathlib import Path;Path(sys.argv[1]).write_text(json.dumps(dict(repo=sys.argv[2],project=sys.argv[3],source=sys.argv[4])))' "$res/gor-periodic-config.json" "$(gor_sidecar)" "$project_root" "$(shasum -a 256 "$project_root/build.sh" | cut -d ' ' -f1)"; /usr/bin/python3 "$res/gor-periodic-capture.py" --write-build-provenance "$project_root" "$(gor_sidecar)" "$res" "$source_snapshot"
if [ "$exit_log_zip" = true ]; then
# Install the detached exit watcher before bundle signing; do not collect here.
cat > "$res/gor-session-log-helper.py" <<'GOR_SESSION_HELPER'
#!/usr/bin/python3
import datetime, hashlib, json, os, pathlib, subprocess, sys, tempfile, time, zipfile
STATE = pathlib.Path.home() / 'Library/Application Support/gor/log-sessions'
def identity(pid):
    try:
        return subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'lstart='], stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError:
        return ''
def camera_helper_evidence(record):
    # On-demand, exact direct child only. No process-name sampling or signals.
    result={}; status=[]
    owner=int(record['pid'])
    if not record.get('identity') or identity(owner)!=record['identity']:
        return result,['CAMERA-HELPER NOT_RUN owner-not-live-or-reused']
    expected=str(pathlib.Path(record['bundle'])/'Contents/MacOS/gor')+' --camera-helper --gor-owner-pid '+str(owner)
    try:
        table=subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,command='],stderr=subprocess.DEVNULL,timeout=3).decode()
        candidates=[]
        for line in table.splitlines():
            fields=line.strip().split(None,2)
            if len(fields)==3 and fields[0].isdigit() and fields[1].isdigit() and int(fields[1])==owner and fields[2]==expected:
                candidates.append(int(fields[0]))
        if len(candidates)!=1:
            return result,['CAMERA-HELPER NOT_RUN exact-owned-count='+str(len(candidates))]
        child=candidates[0]; birth=identity(child)
        def still_owned():
            if not birth or identity(owner)!=record['identity'] or identity(child)!=birth:return False
            row=subprocess.check_output(['/bin/ps','-p',str(child),'-o','ppid=,command='],stderr=subprocess.DEVNULL,timeout=3).decode().strip().split(None,1)
            executable=subprocess.check_output(['/bin/ps','-p',str(child),'-o','comm='],stderr=subprocess.DEVNULL,timeout=3).decode().strip()
            return len(row)==2 and row[0]==str(owner) and row[1]==expected and executable==str(pathlib.Path(record['bundle'])/'Contents/MacOS/gor')
        if not still_owned():return result,['CAMERA-HELPER NOT_RUN ownership-changed-before-sample']
        with tempfile.TemporaryDirectory(prefix='gor-helper-evidence-') as folder:
            sample=pathlib.Path(folder)/'sample.txt'
            run=subprocess.run(['/usr/bin/sample',str(child),'2','-file',str(sample)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=8)
            if not still_owned():return result,['CAMERA-HELPER NOT_RUN ownership-changed-during-sample']
            if run.returncode!=0 or not sample.is_file():return result,['CAMERA-HELPER NOT_RUN system-sample-failed']
            with sample.open('rb') as stream:data=stream.read(16*1024*1024+1)
            if len(data)>16*1024*1024:return result,['CAMERA-HELPER NOT_RUN sample-byte-cap']
            result['gor_camera_helper_sample.txt']=data
            status.append('CAMERA-HELPER sampled pid='+str(child)+' owner_pid='+str(owner)+' seconds=2 birth='+birth)
    except (OSError,ValueError,subprocess.SubprocessError):status.append('CAMERA-HELPER NOT_RUN collection-error')
    return result,status
def archive(record, reason, final=True):
    import session_log_paths
    root=record.get('log_root')
    session={'started':record.get('started'),'pid':record.get('pid')}
    entries,receipts,cut_status=session_log_paths.entries(root,session=session) if root else ({},{},[])
    config=pathlib.Path(record['config']); sources=[(config/n,n) for n in ['photon-grain-size.log','photon-grain-doc.log']]; sources += [(pathlib.Path.home()/'Library/Logs/gor/quit-debug.log','gor-quit-debug.log')]
    if pathlib.Path('/tmp/gor_build.log').is_file():sources.append((pathlib.Path('/tmp/gor_build.log'),'gor_build.log'))
    resources=pathlib.Path(record['bundle'])/'Contents/Resources'; sources += [(resources/n,n) for n in ['gor-build-manifest.json','gor-build-provenance.json','build-id.txt']]; relay=resources/'vendor/mega_relay/mega_relay.mjs'
    status=['SESSION '+record['id']+' '+reason, '195t shared original paths; session-cut logs (owner order 2026-11-15); raw logs retained']+cut_status; hashes=[]
    if not final:
        extra,helper_status=camera_helper_evidence(record);entries.update(extra);status+=helper_status
    for path,name in sources:
        try:data=path.read_bytes()
        except OSError: status.append('MISSING '+name);continue
        if session['started'] is not None and name=='gor_build.log':
            try:mtime=path.stat().st_mtime
            except OSError:status.append('MISSING gor_build.log stat');continue
            if mtime<session['started']-5:status.append('EXCLUDED gor_build.log (mtime before session start)');continue
        elif name in ('photon-grain-size.log','photon-grain-doc.log','gor-quit-debug.log'):
            data,note=session_log_paths.cut_named(name,data,session)
            if data is None:status.append(note);continue
            if note:status.append(note)
        entries[name]=data
    try: entries['relay-at-collection-sha256.txt']=('collection_time_only=true sha256='+hashlib.sha256(relay.read_bytes()).hexdigest()+'\n').encode()
    except OSError: status.append('MISSING relay-at-collection-sha256')
    try:
        scripts=config/'scripts'
        for path in sorted(scripts.rglob('*.lua')):
            if not path.is_file():continue
            name=path.relative_to(scripts).as_posix()
            try: hashes.append(hashlib.sha256(path.read_bytes()).hexdigest()+'\t'+name)
            except OSError:status.append('MISSING installed-script-hash '+name)
        if not hashes:status.append('MISSING installed scripts/*.lua')
    except OSError:status.append('MISSING installed scripts/*.lua')
    entries['installed-script-sha256.txt']=('\n'.join(hashes)+'\n').encode(); entries['collection-status.txt']=('\n'.join(status)+'\n').encode()
    import bounded_log_archives
    output=bounded_log_archives.publish(entries,session=record['id'],started=record.get('started',0))
    if root and final:session_log_paths.cleanup(root,receipts)
    return output
def finish(path,reason):
    claim=path.with_suffix('.collecting')
    try:path.rename(claim)
    except FileNotFoundError:return
    try:
        record=json.loads(claim.read_text());output=archive(record,reason)
        print(output,flush=True);claim.unlink()
    except Exception:
        if claim.exists():claim.rename(path)
        raise
if sys.argv[1]=='arm':
    pid=int(sys.argv[2]);bundle=sys.argv[3];config=sys.argv[4]
    STATE.mkdir(parents=True,exist_ok=True)
    for claim in STATE.glob('*.collecting'):
        try:
            r=json.loads(claim.read_text())
            if identity(r['pid'])!=r['identity'] and time.time()-claim.stat().st_mtime>60:claim.rename(claim.with_suffix('.json'))
        except (OSError,ValueError):pass
    for pending in STATE.glob('*.json'):
        try:
            r=json.loads(pending.read_text())
            if identity(r['pid'])!=r['identity']:finish(pending,'next-launch-recovery')
        except (OSError,ValueError):pass
    start=identity(pid)
    if not start:raise SystemExit('cannot bind owner process')
    record={'id':str(pid)+'-'+hashlib.sha256(start.encode()).hexdigest()[:16],'pid':pid,'identity':start,'bundle':bundle,'config':config,'log_root':sys.argv[5],'started':time.time()}
    pending=STATE/(record['id']+'.json')
    try:
        fd=os.open(pending,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError:
        raise SystemExit(0)
    with os.fdopen(fd,'w') as f:json.dump(record,f)
    subprocess.Popen(['/usr/bin/python3',__file__,'watch',str(pending)],start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=None,close_fds=True)
elif sys.argv[1]=='snapshot-current':
    bundle=pathlib.Path(__file__).resolve().parents[2]
    matches=[]
    for pending in STATE.glob('*.json'):
        try:
            record=json.loads(pending.read_text())
            if pathlib.Path(record['bundle']).resolve()==bundle and record.get('identity') and identity(record['pid'])==record['identity']:matches.append(record)
        except (OSError,ValueError,KeyError):pass
    if len(matches)!=1:raise SystemExit('need exactly one live gor session for this bundle; found '+str(len(matches)))
    print(archive(matches[0],'on-demand',final=False),flush=True)
elif sys.argv[1]=='snapshot':
    print(archive(json.loads(pathlib.Path(sys.argv[2]).read_text()),'on-demand',final=False),flush=True)
elif sys.argv[1]=='watch':
    pending=pathlib.Path(sys.argv[2]);record=json.loads(pending.read_text())
    subprocess.Popen(['/usr/bin/python3',str(pathlib.Path(__file__).with_name('gor-periodic-capture.py')),str(pathlib.Path(__file__).with_name('gor-periodic-config.json')),str(record['pid']),record['config']],env=dict(os.environ,GOR_LOG_SESSION_DIR=record.get('log_root','')),start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,close_fds=True)
    while identity(record['pid'])==record['identity']:time.sleep(1)
    time.sleep(1)
    finish(pending,'owner-process-exited')
else:raise SystemExit('unknown helper mode')
GOR_SESSION_HELPER
fi
if [ -f "$icon_source" ]; then
    src_mod=$(stat -f "%m" "$icon_source" 2>/dev/null || echo "0")
    cache_mod=$(stat -f "%m" "$icon_cache" 2>/dev/null || echo "0")
    if [ ! -f "$icon_cache" ] || [ "$src_mod" -gt "$cache_mod" ]; then
        iconset="/tmp/gor.iconset"; mkdir -p "$iconset"
        for s in 16 32 128 256 512; do
            sips -z $s $s "$icon_source" --out "$iconset/icon_${s}x${s}.png" > /dev/null 2>&1
            sips -z $((s*2)) $((s*2)) "$icon_source" --out "$iconset/icon_${s}x${s}@2x.png" > /dev/null 2>&1
        done
        iconutil -c icns "$iconset" -o "$icon_cache" 2>/dev/null; rm -rf "$iconset"
    fi
    cp "$icon_cache" "$res/AppIcon.icns"
fi

# 177d2: daily media telemetry ON; distribution (--dmg) OFF.
# Written before signing; no runtime environment override.
media_telemetry_plist=true
if [ "$create_dmg" = true ]; then media_telemetry_plist=false; fi
cat > "$stage_app/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GORMediaTelemetry</key><$media_telemetry_plist/>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>Gor uses screen capture audio to drive dynamic subtitle font weight based on audio levels.</string>
    <key>NSMicrophoneUsageDescription</key><string>Gor reads system audio levels for subtitle animation.</string>
    <key>NSAudioCaptureUsageDescription</key><string>Gor captures player audio levels to animate variable fonts. Audio is processed on this Mac.</string>
    <key>NSCameraReactionEffectGesturesEnabledDefault</key><false/>
    <key>NSCameraUsageDescription</key><string>Gor uses your camera to track head position for VR180 look-around. Video is processed on-device and never recorded or transmitted.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
PLISTEOF

# Manifest covers the source Lua scripts before app signing. The app's vendor
# is a symlink, so the manifest is generated from the real source tree; the
# v2.2.17 pruning pass is NOT carried (it would write into vendor through the
# symlink). Required-lua regular-file checks kept.
script_root="$project_root/Resources/vendor/mpv/scripts"
test -d "$script_root" || { echo 'mpv scripts directory missing' >&2; exit 1; }
/usr/bin/python3 - "$script_root" "$res/gor-build-manifest.json" <<'PY'
import datetime, hashlib, json, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
required = ['photon.lua', 'photon-common.lua', 'photon-grain.lua', 'photon-hud.lua', 'autoload.lua']
for name in required:
    original = root / name
    if not stat.S_ISREG(original.lstat().st_mode):
        raise SystemExit('required Lua missing/non-regular: ' + name)
scripts = {}
for path in sorted(root.rglob('*.lua')):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise SystemExit('source Lua non-regular: ' + str(path))
    scripts[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
if not scripts:
    raise SystemExit('no Lua scripts for build manifest')
manifest = {'version': '2.2.22', 'build_time': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'scripts': scripts}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
PY

/usr/bin/python3 - "$source_snapshot" "$res/build-id.txt" <<'PY_BUILD_ID'
import hashlib, pathlib, sys
snapshot, output = map(pathlib.Path, sys.argv[1:])
identity = hashlib.sha256(snapshot.read_bytes()).hexdigest()
output.write_text('commit=' + identity + '\nidentity_kind=source-manifest-sha256\n')
assert output.read_text().splitlines()[0] == 'commit=' + identity
print('      build-id (source manifest): ' + identity)
PY_BUILD_ID
# GOR_BUILD_ID_END

gor_write_build_id || exit 1

# ── signing (block 174 items 9-10) ────────────────────────────────────────────
if [ "$signing_enabled" = true ]; then
    next_step; echo "signing..."
    # item 9: sign vendor leaves in place, only leaves changed since the last
    # good build. The old bytes are already in the backup above.
    gor_sign_vendor_leaves || { gor_mirror_note_failure; exit 1; }
    gor_node_rpath_check || { gor_mirror_note_failure; exit 1; }
    # item 10: first sign MacOS/gor-log-writer, then the app - MacDev,
    # --options runtime, entitlements, NO --deep, NO ad-hoc fallback.
    if [ -f "$dest/gor-log-writer" ]; then
        codesign --force --options runtime --sign "MacDev" "$dest/gor-log-writer" || { echo "MacDev failed on gor-log-writer; installed app unchanged." >&2; gor_mirror_note_failure; exit 1; }
    fi
    if ! codesign --force --options runtime --entitlements "$entitlements_path" --sign "MacDev" "$stage_app"; then
        echo "Stable MacDev signing failed; there is no ad-hoc fallback. The installed app is unchanged." >&2
        gor_mirror_note_failure
        exit 1
    fi
    echo "      signed: MacDev"
    codesign --verify --strict "$stage_app" || { gor_mirror_note_failure; exit 1; }
    GOR_SIGNING_CONTINUITY_CALL=1
else
    next_step; echo "signing skipped"
fi

# GOR_SIGNING_CONTINUITY_BEGIN
# t6: the new app must satisfy the INSTALLED app's designated requirement - a
# certificate's display name alone is not identity. Never touch TCC.
gor_read_designated_requirement() {
    local details requirement
    details=$(codesign --display --requirements - "$1" 2>&1) || return 1
    requirement=$(printf '%s\n' "$details" | sed -n 's/^designated => //p')
    [ -n "$requirement" ] || return 1
    printf '%s\n' "$requirement"
}
gor_verify_signing_continuity() {
    local candidate="$1" installed="$2" details old_requirement new_requirement
    codesign --verify --strict "$candidate" || return 1
    details=$(codesign --display --verbose=4 "$candidate" 2>&1) || return 1
    case "$details" in
        *Signature=adhoc*) echo 'Signing continuity: ad-hoc app refused; installed app unchanged.' >&2; return 1 ;;
    esac
    case "$details" in
        *Authority=*) ;;
        *) echo 'Signing continuity: certificate identity unavailable; installed app unchanged.' >&2; return 1 ;;
    esac
    new_requirement=$(gor_read_designated_requirement "$candidate") || return 1
    printf '      candidate designated requirement: %s\n' "$new_requirement"
    if [ -d "$installed" ]; then
        codesign --verify --strict "$installed" || {
            echo 'Signing continuity: installed signature cannot be verified; preserving it for inspection.' >&2
            return 1
        }
        old_requirement=$(gor_read_designated_requirement "$installed") || return 1
        printf '      installed designated requirement: %s\n' "$old_requirement"
        codesign --verify --strict --test-requirement "=$old_requirement" "$candidate" || {
            echo 'Signing continuity: new app does not satisfy installed identity; install refused.' >&2
            return 1
        }
        echo '      signing continuity: candidate satisfies installed designated requirement'
    else
        echo '      signing continuity: first install, certificate signature verified (no prior grant inferred)'
    fi
}
# GOR_SIGNING_CONTINUITY_END
if [ "$signing_enabled" = true ]; then
    gor_verify_signing_continuity "$stage_app" "$app_bundle" || { gor_mirror_note_failure; exit 1; }
    signed_executable_sha=$(shasum -a 256 "$dest/$app_name" | awk '{print $1}')
    [ -n "$signed_executable_sha" ] || exit 1
    echo "      signed executable sha256: $signed_executable_sha"
fi

# ── the swap (block 174 item 11) ──────────────────────────────────────────────
next_step; echo "installing..."
gor_swap_install
echo "      mpv processes still running: $(pgrep -x mpv 2>/dev/null | wc -l | tr -d ' ') (read-only; no kill - 174d)"
# item 11: check the installed executable sha against the verified candidate.
if [ "$signing_enabled" = true ]; then
    installed_executable_sha=$(shasum -a 256 "$app_bundle/Contents/MacOS/$app_name" | awk '{print $1}')
    [ "$installed_executable_sha" = "$signed_executable_sha" ] || { echo 'Installed executable hash differs from verified candidate; refusing launch.' >&2; exit 1; }
    echo "      installed executable sha256: $installed_executable_sha"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_bundle" 2>/dev/null || true; for _dup in "$stage_dir/gor.app.last" "$project_root"/gor.app.instinct-* "$HOME/Downloads/gor-bbu"/*/gor.app; do [ -e "$_dup" ] && { /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$_dup" 2>/dev/null || true; }; done; true
# Successful swap only: the mirror moves to the new source state.
gor_mirror_update
if [ -f "$project_root/.gor-vendor-gate.pending.json" ]; then
    mv "$project_root/.gor-vendor-gate.pending.json" "$project_root/.gor-vendor-gate.json"
fi

# After a successful swap, promote the staged browser to source as one rename.
# Old source kept for rollback; a failed build never mutates source.
if [ "$chromium_stage_active" = true ]; then
    source_dir="$project_root/Resources/vendor/chromium/$staged_dir"
    source_backup="$build_dir/chromium-previous"
    if [ -e "$source_backup" ]; then
        echo "      chromium source promotion skipped: $source_backup exists; stage retained" >&2
    else
        if mv "$source_dir" "$source_backup"; then
            if mv "$chromium_stage/payload/$staged_dir" "$source_dir"; then
                rm -rf "$chromium_stage"
                echo "      chromium source promoted; old tree retained at $source_backup"
            else
                # A failed mv can leave a PARTIAL destination (cross-volume is
                # copy+delete). 174c: one rule - park the partial aside, move
                # the old tree back; anything resists -> stop and print the
                # real paths. No cp fallback for app bundles. v10.1 (F-A): no
                # blind mv command while the partial target exists - BSD mv
                # would nest the backup inside it.
                if [ -e "$source_dir" ]; then
                    # top-level code: no local. One seconds-timestamp name; a
                    # collision stops loudly - no retry loop.
                    partial_aside="$build_dir/chromium-partial-$(date +%y%m%d-%H%M%S)"
                    if [ -e "$partial_aside" ]; then
                        echo "exists: $partial_aside — stopping; the partial chromium payload is at $source_dir" >&2
                        echo "      the previous source tree is safe at $source_backup - a verified non-destructive restore is needed (a plain mv would nest it inside the partial; do not move anything by hand without verifying both paths)" >&2
                        exit 1
                    fi
                    if ! mv "$source_dir" "$partial_aside"; then
                        echo "      chromium promotion FAILED — stopping; cannot clear the partial destination, it is still at $source_dir" >&2
                        echo "      the previous source tree is safe at $source_backup - a verified non-destructive restore is needed (a plain mv would nest it inside the partial; do not move anything by hand without verifying both paths)" >&2
                        exit 1
                    fi
                    echo "      chromium partial payload parked at $partial_aside (not deleted)" >&2
                fi
                # destination is now absent: a plain rename, no nesting possible
                mv "$source_backup" "$source_dir" || { echo "      chromium promotion FAILED and restore failed; restore by hand: mv '$source_backup' '$source_dir'" >&2; exit 1; }
                echo "      chromium source promotion failed; restored source, stage retained" >&2
            fi
        else
            echo "      chromium source promotion failed; stage retained" >&2
        fi
    fi
fi

end_time=$(date +%s)
elapsed=$((end_time - start_time))
if [ "$open_app" = true ]; then
    # Lua reads this only on its first playback-restart after file-loaded.
    printf '%s\n' "$end_time" > "$playback_marker"
    echo "      build-complete epoch: $end_time (waiting for first mpv playback)"
fi
next_step; echo "build complete. (${elapsed}s total)"

# Block185: no detached source capture or sidecar mutation on Mac.
# Update result bytes are queued under .git and published only to gor-capture-mac.

gor_backups_size_report

# ── DMG (block 174: the only vendor-copying path; never run by daily builds) ─
next_step; echo "DMG..."
if [ "$create_dmg" = true ]; then
    dmg_stage=$(mktemp -d /tmp/gor-dmg-stage.XXXXXX)
    ditto "$app_bundle" "$dmg_stage/gor.app"
    rm -f "$dmg_stage/gor.app/Contents/Resources/vendor" "$dmg_stage/gor.app/Contents/Resources/fonts"
    ditto "$project_root/Resources/vendor" "$dmg_stage/gor.app/Contents/Resources/vendor"
    ditto "$project_root/Resources/fonts" "$dmg_stage/gor.app/Contents/Resources/fonts"
    codesign --force --options runtime --entitlements "$entitlements_path" --sign "MacDev" "$dmg_stage/gor.app" || { echo "DMG stage signing failed" >&2; rm -rf "$dmg_stage"; exit 1; }
    hdiutil create -volname "Gor" -srcfolder "$dmg_stage/gor.app" -ov -format UDZO "$build_dir/$app_name.dmg" 2>/dev/null
    rm -rf "$dmg_stage"
    echo "      DMG ready: $build_dir/$app_name.dmg"
else
    echo "      skipped"
fi


# ── launch + log ──────────────────────────────────────────────────────────────
if [ "$open_app" = true ]; then
    echo ""; echo "starting... [log: $log_mode]"
    echo "      log ZIP: /tmp/YYMMDD-HHMMSS-gor-log.zip (on-demand/exit only; periodic ZIP off)"
    # Escape the full executable path as an ERE, then anchor argv[0].
    # Do not let an unrelated gor.app elsewhere satisfy launch/exit checks.
    gor_process_pattern="^$(printf '%s' "$app_bundle/Contents/MacOS/$app_name" | sed 's/[][\.^$*+?(){}|]/\\&/g')([[:space:]]|$)"
    gor_is_running() {
        pgrep -u "$build_uid" -f "$gor_process_pattern" >/dev/null 2>&1
    }
    launch_open() {
        local open_started=$(date +%s)
        # Ask LaunchServices for a new instance of this exact bundle.
        open -n "$app_bundle" --args "--gor-log-session=$GOR_LOG_SESSION_DIR"
        echo "      timing: macOS open returned in $(( $(date +%s) - open_started ))s"
        # open returns before Gatekeeper finishes. A process start timestamp
        # locates the extra delay, but is not proof that playback is ready.
        local deadline=$(( $(date +%s) + 120 ))
        while ! gor_is_running; do
            if [ "$(date +%s)" -ge "$deadline" ]; then
                echo "      timing: no gor process after $(( $(date +%s) - open_started ))s (verification/cancel may be pending)"
                return 1
            fi
            sleep 1
        done
        echo "      timing: macOS launch to gor process $(( $(date +%s) - open_started ))s (not playback-ready)"
    }

    wait_for_exit() {
        while gor_is_running; do sleep 1; done
    }

    if [ "$log_mode" = "direct" ]; then
        echo "      note: direct - $GOR_LOG_SESSION_DIR/gor_direct.log (SCE enabled)"
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        sleep 1
        # The shared EXIT cleanup stops only this build's viewer PID.
        # Bypass the tee for tail output; otherwise tail feeds its own log.
        tail -n 0 -F "$GOR_LOG_SESSION_DIR/gor_direct.log" >&3 &
        TAILPID=$!
        wait_for_exit
        sleep 0.5
        stop_log_viewer
    fi

    if [ "$log_mode" = "off" ]; then
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        wait_for_exit

    elif [ "$log_mode" = "filter" ]; then
        # [GOR]-prefixed NSLog only. Add NSLog(@"[GOR] ...") to code under test.
        # Produces AI-pasteable output — no noise, only your signal.
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        sleep 1
        log stream --predicate 'process == "gor"' --level debug 2>/dev/null \
            | grep --line-buffered '\[GOR\]' &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "stream" ]; then
        # Standard NSLog output scoped to gor process.
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        sleep 1
        log stream --predicate 'process == "gor"' --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "broad" ]; then
        # gor + mpv + Python (mus2). os_log from subprocesses.
        # raw print()/mpv stderr not capturable via open -a — TCC constraint.
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        sleep 1
        log stream --predicate 'process == "gor" OR process == "mpv" OR process BEGINSWITH "Python"' \
            --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "full" ]; then
        # No predicate — entire system log. Last resort only.
        launch_open
        gor_release_build_lock   # 176 item 1: the build is done; the app may stay open
        sleep 1
        log stream --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null
    fi
fi

# block 176c: --update continuation. After the (no-launch) build above, run
# the selftest, record PASS/FAIL + source association in an empty sidecar
# commit and push it through the existing gated sync push.
if [ "${update_mode:-false}" = true ]; then
    gor_update_finish
fi
