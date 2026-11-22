# build.sh characterization (190f v2 D2 / Q3)

The shipped shell remains the entry. M1 performs no decomposition. Goldens run
actual extracted dispatch/parser functions in fake HOME/app trees, with native
functions replaced by recording stubs. They prove routing and refusal output,
not macOS launch, codesign, TCC, rendering, a/v or complete end-to-end selftests.

| Entry/flag | Files / side effects | Recovery invariant / golden |
| --- | --- | --- |
| default; --no-launch | .build, .gor-stage, gor.app, logs, mirror/backups | stage before app swap; parser flags |
| --update | sidecar fetch, capture queue, source overlay, backup, reexec | ff-only; old updater retained; update routing |
| --update-project PATH | existing project identity; snapshot target | invalid project rejected before mutation |
| --update-build | source assets, fixtures, build/selftest/capture | asset gate warning never strands build |
| --selftest | .gor-selftest-last.txt, build log, scratch apps | child locks; no recursion; lifetime routing |
| --selftest-full | same plus full feature/native tests | full routing; not a Linux native proof |
| --install-runner | local credential, runner launch agent, owned runner dir | pre-log/pre-lock route; no secret argv/log |
| --remove-runner | owned runner files and launch agent | pre-log route; ownership guard |
| --rollback [ID] | backup changes.txt, source, undo backup | no mutable fetch; additions moved aside |
| --rollback verified | local tag archive plus normal backup | local git required; not no-git recovery route |
| --verified; --unverified | sidecar local tag / one-line log | local only; no network push |
| --push | source-sync helper existence check only | push disabled; no lock/build/launch |
| --no-build | source operations only | exits before compilation and app paths |
| --clean; --dmg | .build reset; DMG packaging | existing explicit flags; parse golden |
| --no-sign; --warnings; --whisper | signing/diagnostics/whisper build toggles | parse golden; native work not simulated |
| --log MODE | direct/off/filter/stream/broad/full, writer temp/cache, quit logs | reject missing/unknown mode; logging routes |
| --[no-]log-timestamp; --[no-]log-cpu-info | log formatting/cached sensor data | parse golden |
| unknown flag | stderr, rc2 | no app mutation before parser failure |

## Delivery and recovery characterization

`gor_install_tree` enumerates delivered roots, backs changed bytes and records
added/changed/deleted kinds before per-file temporary-copy/readback. Overlay
omissions never imply deletion. Existing explicit source-retirement rules remain
unchanged, not newly authorized by this document. It is not a single atomic tree
swap: interruption recovery uses the completed backup changes.txt. Rollback
reads local backups, not main, and moves added overlays aside instead of deleting.
The prior working build.sh is copied to .gor-last-working-build.sh before install
and retained (not removed by M1). A failing/missing advisory architecture gate warns; release-byte integrity
failure exits before installing or launching and never replaces the working app;
normal build failure leaves the prior installed app untouched.

D3 fixture battery exercises real shipped installer/bootstrap/rollback code with
fake HOME and project/app roots. Linux substitutes copy-on-write `cp -c` with
`cp`; native clonefile/filesystem/launch evidence remains owner update only.
Gate assets stage with exact declared digest/mode verification; missing/broken
assets are warnings at owner runtime, hard failures only in lane CI.

## Q3: two-package delivery answer (M2 gate)

**R4 roots added in M1; native receipt still required.** `Packages/GorKit` was absent from gor_tree_files operands, embedded
mirror-diff TRACKED, installer roots and selftest rollback scratch copy. M1 adds
all these roots plus source-snapshot hashing and an empty Packages/.keep fixture. A by-path
app dependency could therefore compile against stale/missing model bytes, and
rollback could restore the app Package.swift without its matching GorKit.
M2 must verify the preceding owner update installed Packages, preserve
manifest paths and executable modes, then test old->new, repeat, interruption and
local rollback with no git. It must also audit source-snapshot hashing (currently
Package.swift/build.sh + Sources/gor only), sync capture allowlists and lock scope.
M1 creates no package; M2 remains gated on owner-update receipt. Tools-version ratchet still
waits on a real owner-Mac swift version capture (Q1), not Linux's toolchain.

## Proposed later move-only phases

fetch/stage; verify; compile/package; install/rollback; selftest; runner; logs.
Each goes under tools/build/lib in its own move-only commit after golden/native
evidence, then behavior-neutral cleanup. Never coupled to a Swift M step or
engine change. This characterization is the prerequisite, not the decomposition.

R3 bridge measured2765lines (+53 vs2712) includes required R4/R5 roots and passive Q1
version capture. temporary-D2-bridge growth is recorded in arch-baseline.tsv;190g approves
ceiling2765, removed by D2. Further hub growth follows R3.
R1 GorFit.swift exists1323lines at c42ad64 and current source branch; no deletion.

## Replay commands and evidence boundary

With Swift installed: `PATH=/path/to/swift/bin:$PATH python3 Tests/Architecture/run.py`
and `python3 Tests/Architecture/install.py`. Without Swift, fixtures select
`Tests/Architecture/swift-fixture.py` via ARCH_SWIFT and explicitly print
SUPPLEMENTARY / compile NOT_RUN. `package-gor.json` is Swift6.0.3 dump-package
for the current app, not compiled model evidence. Direct --verify without Swift
fails clearly; --report returns0 with swift unavailable; --integrity-only never
invokes Swift. `prior-installer.sh` is exact extracted281910e8 installer code.
Old->new fixture executes that prior installer then candidate bootstrap, checks
added-path roots and retained prior updater. It is not a complete native --update
process re-exec: fetch/capture/launch boundaries are separately mocked goldens.

## Permission portability regression

Release bytes remain exact SHA256. Mode verification follows Git's executable
bit, not all Unix0777 permission bits: a100644 checkout can be0444/0644/0664
under a different umask/read-only workflow. The three owner-reported vendor
paths have an explicit fixture proving this, plus rejection of changed bytes,
missing files and executable-bit flips. Diagnostics split these failure classes.
The Mac failure did not capture actual modes, so permission cause is reproduced
but the precise Mac permission value is not claimed measured.

## Required fixture bootstrap regression

The architecture overlay must carry selftest-fixtures because the shared tree
installer always calls gor_install_selftest_fixtures. Both required shaders are
committed; the prior bootstrap omitted their directory, not their source files.
Recovery tests now execute the actual fixture helper, never a no-op substitute,
and audit its entire literal required list against delivered bytes/readback.

## J3 existing native snapshot transition evidence

Exact Git blobs: faa9d2ab369fbc179e1298639d0005a3101a852e build.sh
be668413b0731248cb4d66e527536cd47cf2cb6a; c42ad64073bfaa2c77849622b4d72a35129f649f
80f4e73656503dc077b9ccffa9edb3d3e9e61fc7. They differ. Committed capture
captures/261107-130258.txt on gor-capture-mac reports rc=0 against c42ad640,
PASS t1-build-launch (0s), SELFTEST PASS3/3 4s. Per190j's conditional branch,
this records native update/reexec evidence then; no new build.sh capture glue.
It does not close current M1 native validation after later updater changes.

## J1/J2 lock and classifier

ffmpeg-provider.lock ships through the same backup/install/bootstrap/mirror roots.
Its first494 bytes exactly match the gorav source blob; only gorav_lock_source is
appended. No claim about mpv's bundled FFmpeg version is made. Bulk classification
recipe is documented at tools/architecture.py:140: bytewise UTF8 path order,
JSON-line records with escaped path, regular/symlink kind, raw-byte SHA256 and Git
executable flag. Symlinks hash link-target bytes without following. Empty listing
is SHA256(empty). Reviewed per-file overrides are excluded from bulk membership.

## Installed overlay versus repository inventory

The repository manifest includes historical archives which are not copied to the
owner project. Installed report verifies only updater roots and explicitly says
repository-only bulk/archive checks NOT_APPLICABLE. delivery.tsv likewise lists
only actual installable roots, not root dev scripts, private MEMORY.md or the
locally maintained whisper-cpp-src tree. Lane CI still checks the whole repo.
The exact code-only overlay regression asserts0unmapped/no stale archive lines
and retains required delivered-file integrity failures.

## Feature verdict prerequisites

Normal --update deliberately calls gor_selftest with lifetime mode; it passes
GOR_LIFETIME_FULL=0 to gor-selftest.sh. Thus the feature rows are INCONCLUSIVE
by design, not executed failures. --selftest-full selects1 and runs native app,
mpv IPC/geometry/render tests using vendor ffmpeg-generated media and fixtures.
A real feature verdict needs the particular trace/property/pixel observations;
missing trace, no actual zoom excursion or insufficient samples stay inconclusive.
Camera and native display calibration still need real-device observations and
are not proven by synthetic distance fixtures. Full mode is not automatically
added to normal updates and old historical failures are not silently erased.
