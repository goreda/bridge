#!/bin/bash
# install-r62.sh — one-time bootstrap (block 176c): the installed r6.1 build.sh
# has no --update yet; this installs the r6.2 build.sh from the pulled sidecar
# into the project, with backup + hash verification, using only what already
# exists on this Mac (git, the sidecar clone, the source lock).
# AFTER this succeeds, run:  cd ~/Downloads/gor && ./build.sh --update
set -euo pipefail

# r6.2 build.sh pin (qualified bytes; the update route verifies this exact hash)
EXPECTED_R62_BUILD_SHA="a5a094dea1018c29302ef6adcdf1eab72c1d70f8fc3c437ed5803329cc1a430d"

src_dir="${GOR_SRC:-$HOME/Downloads/gor}"
sync_dir="${GOR_DST:-$HOME/Downloads/gor-repo-sync}"
branch="${GOR_BRANCH:-mac-source-sync-20261103}"
lock="$src_dir/.gor-source.lock"

say() { printf '%s\n' "$*"; }
die() { say "install-r62: $*" >&2; exit 1; }

[ -d "$sync_dir/.git" ] || die "no sidecar clone at $sync_dir"
[ -f "$src_dir/build.sh" ] || die "no installed build.sh at $src_dir/build.sh"

# ff-only sync of the sidecar; divergence: print state, change nothing, stop.
git -C "$sync_dir" fetch origin "$branch" || die "fetch failed (network or auth)"
if ! git -C "$sync_dir" merge-base --is-ancestor HEAD "origin/$branch"; then
    say "install-r62: sidecar and origin/$branch have diverged — NOT installing; nothing changed" >&2
    git -C "$sync_dir" log --oneline --graph --max-count=8 HEAD "origin/$branch" >&2 || true
    exit 1
fi
git -C "$sync_dir" pull --ff-only origin "$branch" >/dev/null || die "ff-only pull failed — nothing changed"

new="$sync_dir/archive/gor/build.sh"
[ -f "$new" ] || die "no archive/gor/build.sh in the pulled branch"
actual=$(shasum -a 256 "$new" | awk '{print $1}')
[ "$actual" = "$EXPECTED_R62_BUILD_SHA" ] || die "pulled build.sh sha256 $actual != pinned r6.2 $EXPECTED_R62_BUILD_SHA — NOT installing; nothing changed"

current=$(shasum -a 256 "$src_dir/build.sh" | awk '{print $1}')
if [ "$current" = "$EXPECTED_R62_BUILD_SHA" ]; then
    say "install-r62: r6.2 build.sh already installed; nothing to do"
    say "next: cd $src_dir && ./build.sh --update"
    exit 0
fi

# backup (owner convention: ~/Downloads/gor-bbu/<timecode>-<op>)
bdir="$HOME/Downloads/gor-bbu/$(date +%y%m%d-%H%M%S)-r62-bootstrap"
mkdir -p "$bdir"
cp -p "$src_dir/build.sh" "$bdir/build.sh" || die "backup failed — nothing changed"
printf 'old %s\nnew %s\n' "$current" "$EXPECTED_R62_BUILD_SHA" > "$bdir/SHA256.txt"
say "install-r62: backup at $bdir"

# bounded source-lock acquire (v7.6 semantics: fail-closed, never steal,
# never delete another holder's lock). held=true only after OUR mkdir lands;
# the EXIT trap releases only our own acquisition.
held=false
trap 'if [ "$held" = true ]; then rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true; fi' EXIT
t=0
while ! mkdir "$lock" 2>/dev/null; do
    t=$((t+1)); [ "$t" -ge 120 ] && die "source lock held for 60s — a capture or installer is running; try again later, nothing changed past the backup"
    sleep 0.5
done
held=true
printf '%s\n' $$ > "$lock/pid"

# atomic same-directory swap, then verify; on any failure restore the backup.
if ! cp -p "$new" "$src_dir/build.sh.r62-tmp.$$"; then die "copy failed — nothing swapped"; fi
if ! mv "$src_dir/build.sh.r62-tmp.$$" "$src_dir/build.sh"; then
    rm -f "$src_dir/build.sh.r62-tmp.$$"; die "swap failed — nothing changed"
fi
installed=$(shasum -a 256 "$src_dir/build.sh" | awk '{print $1}')
if [ "$installed" != "$EXPECTED_R62_BUILD_SHA" ]; then
    cp -p "$bdir/build.sh" "$src_dir/build.sh"
    die "post-install verify failed; restored the backup ($bdir)"
fi
say "install-r62: r6.2 build.sh installed and verified ($installed)"
say "next: cd $src_dir && ./build.sh --update"
