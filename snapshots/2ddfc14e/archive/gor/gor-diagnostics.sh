#!/bin/bash
# Read-only local diagnostic extraction; one empty result commit + gated push.
# No build, app launch/quit, debug env, source install or log truncation.
set -e
project_root="${GOR_SRC:-$HOME/Downloads/gor}"
sidecar="${GOR_DST:-$HOME/Downloads/gor-repo-sync}"
branch="${GOR_BRANCH:-mac-source-sync-20261103}"
[ -d "$sidecar/.git" ] || { echo 'diagnostic: sidecar missing' >&2; exit 1; }
[ "$(git -C "$sidecar" symbolic-ref --quiet --short HEAD)" = "$branch" ] || { echo 'diagnostic: wrong branch; no commit' >&2; exit 1; }
[ ! -d "$project_root/.gor-build.lock" ] || { echo 'diagnostic: build/test still active or interrupted lock remains; no commit' >&2; exit 1; }
[ ! -d "$project_root/.gor-source.lock" ] || { echo 'diagnostic: source capture active; no commit' >&2; exit 1; }
git -C "$sidecar" diff --cached --quiet || { echo 'diagnostic: staged content present; no commit' >&2; exit 1; }
[ -x "$sidecar/sync.sh" ] || { echo 'diagnostic: gated push helper missing' >&2; exit 1; }
head_sha=$(git -C "$sidecar" rev-parse HEAD)
# Data goes directly into a shell variable, not a new source/result file.
detail=$(/usr/bin/python3 - "$project_root" "$HOME/Library/Logs/gor/quit-debug.log" <<'PY'
import collections, os, re, sys
root, quitlog = sys.argv[1:]
# Read bounded tail only. No full log content, URLs, paths, file names or media.
def tail(path, cap=65536):
    try:
        with open(path, 'rb') as f:
            f.seek(0, 2); size=f.tell(); f.seek(max(0, size-cap))
            return f.read(cap).decode('utf-8','replace').splitlines()[-400:]
    except FileNotFoundError:
        return []
# Fixed categories publish no captured text. Counts expose exact observed class.
classes = [
 ('build-lock-refused', r'Another build or an interrupted-build lock exists'),
 ('inherited-lock-pid-mismatch', r'inherited build lock pid mismatch'),
 ('source-lock-refused', r'source lock.*(?:held|timeout|timed out)'),
 ('compile-error', r'error:|SwiftPM product missing'),
 ('build-failed', r'build failed|build \+ --rollback failed'),
 ('rollback-backup-missing', r'no.*backup|backup.*not found|rollback.*missing'),
 ('dyld-missing-library', r'Library not loaded:|library not loaded:'),
 ('dyld-symbol-missing', r'Symbol not found:|symbol not found:'),
 ('dyld-incompatible-architecture', r'incompatible architecture|wrong architecture'),
 ('dyld-code-signature', r'code signature.*(?:invalid|not valid)|signature.*not valid'),
 ('ffmpeg-filter-unavailable', r'No such filter|Filter not found'),
 ('ffmpeg-encoder-unavailable', r'Unknown encoder|Encoder .* not found'),
 ('abort-trap', r'Abort trap|SIGABRT'),
]
lines=tail(os.path.join(root,'.gor-selftest-build.log'))
print('bounded-build-tail: %d lines inspected (max 64KiB / 400 lines)' % len(lines))
for name,pattern in classes:
    n=sum(bool(re.search(pattern,l,re.I)) for l in lines)
    if n: print('diagnostic %s count=%d' % (name,n))
# Only project test PASS/FAIL ids and integer timings; no arbitrary reasons.
res=tail(os.path.join(root,'.gor-selftest-last.txt'))
for l in res[-40:]:
    m=re.match(r'^(PASS|FAIL) ([a-z0-9-]+)(?:\s+\((\d+)s\))?',l)
    if m: print('test %s %s%s' % (m[1],m[2],(' seconds='+m[3]) if m[3] else ''))
# Event markers only, selected from the latest bounded quit tail. Integer pid/
# signal/rc and booleans permitted; raw phase text, user data and paths omitted.
qlines=tail(quitlog)
markers = ['killOwnedChildren completed','killOwnedChildren join','killOwnedChildren already-done',
 'killOwnedChildren floor','watchdog','pendingRestart old=false new=true',
 'relaunch skipped','relaunch','freeze']
print('bounded-quit-tail: %d lines inspected (max 64KiB / 400 lines)' % len(qlines))
for l in qlines[-100:]:
    hit=next((x for x in markers if x in l),None)
    if hit:
        fields=[]
        for key in ['reason','outcome']:
            m=re.search(r'\b'+key+r'=([A-Za-z-]+)',l)
            if m and m[1] in ['watchdog','willTerminate','approvedChain','completed','timeout']:
                fields.append(key+'='+m[1])
        print('quit-event '+hit+(' '+' '.join(fields) if fields else ''))
PY
)
msg="gor-diagnostic $(date +%y%m%d-%H%M%S)
against: $head_sha ($branch)
Read-only bounded existing-log categories; no build or launch.
Historical bounded tails, not a claim that every event belongs to the latest run.
$detail"
git -C "$sidecar" -c user.name=gor-update -c user.email=gor-update@localhost commit --allow-empty -qm "$msg"
echo 'diagnostic: empty result commit recorded; gated push follows'
"$sidecar/sync.sh" push
