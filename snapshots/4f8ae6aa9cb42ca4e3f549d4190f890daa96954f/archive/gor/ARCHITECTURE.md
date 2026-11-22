# GOR architecture - 190f v3

Current: one macOS executable target `gor`, 40 production Swift files. All other
packages/targets below are planned, not compiler isolation or test coverage.
Destination: app shell -> UI/adapters -> pure features -> shared GorCore.
GorCore and GorAV come from one pinned gorav revision; no gorav -> gor edge.

## Compiler dependency table

| Target/layer | Allowed project dependencies |
| --- | --- |
| GorCore | none |
| GorPlaybackModel | GorCore |
| pure features | GorCore; GorPlaybackModel when needed |
| GorSubtitlesUI / GorStereoUI | own feature; GorCore; system UI frameworks |
| GorUI | features; feature UI; GorCore; GorPlaybackModel |
| GorPlatformMac | GorCore; GorPlaybackModel; system frameworks |
| GorMPVBackend | GorCore; GorPlaybackModel |
| GorAVBackend | GorCore; GorPlaybackModel; GorAV facade only |
| gor | all above; composition root |

No feature-to-feature/adapter edge. No AppKit/Metal/CoreAudio in GorKit.
Only GorMPVBackend knows mpv; only GorAVBackend imports GorAV. No internal
engine imports. The compiler is primary; regex checks only supplement it.

## Packages, targets and reviewers

| Package/target | Layer | Responsibility | Public API | Reviewer |
| --- | --- | --- | --- | --- |
| gor/Package.swift | app package | macOS composition | Executable | gdb |
| Packages/GorKit | pure package | Linux models | Library products | unassigned |
| GorCore (gorav repo) | core | shared values/cue model, logging, clock | Values/protocols | goreda |
| GorPlaybackModel | core | backend contract and state | PlayerBackend/actions/events | unassigned |
| GorSubtitles | feature | styling/layout/preferences/live captions | State/Action/client | unassigned |
| GorStereo | feature | packing/recognition/pose | Pure values | unassigned |
| GorFit | feature | fit/crop/zoom | Pure plans | unassigned |
| GorSources | feature | resolution/admission | State/client | unassigned |
| GorEffectsModel | feature | effect parameters | State/client | unassigned |
| GorCaptureModel | feature | capture/PCM tap | State/client | unassigned |
| GorSubtitlesUI | feature-ui | draw text cues | MainActor views | unassigned |
| GorStereoUI | feature-ui | stereo view glue | MainActor views | unassigned |
| GorPlatformMac | adapter | windows/keys/capture/log sink | Platform clients | unassigned |
| GorMPVBackend | adapter | mpv IPC/Lua/resources | PlayerBackend | unassigned |
| GorAVBackend | adapter | GorAV facade mapping | PlayerBackend | unassigned |
| GorUI | ui | spine/sidebar/HUD | MainActor views | unassigned |
| gor | app | lifecycle/composition | Executable | gdb |
| tooling | tooling | build.sh/tools/scripts | Stable command | gdb |
| delivery | delivery | stage/install/rollback | Recovery contract | gdb |

## Inventory and gates

`architecture/policy.tsv` is reviewed by people and never written by --emit.
Product files have explicit rows; historical evidence has bulk directory rules.
Generated columns are path/kind/current-target/lines, never approval.
`architecture/manifest.tsv` is generated with `tools/arch-check.sh --emit`,
reviewed, then checked with `--verify`. Rows record current and planned target,
kind, responsibility, line count, and explicit exceptions. Historical evidence
is generated/archive material; vendor stays frozen and has VENDOR.md entries.
The installed overlay uses its declared manifest, never inventories private logs.

`architecture/arch-baseline.tsv` ratchets known debt by path/rule/count/queue and
removal condition. New violations and unrecorded growth fail lane CI; recorded hub glue fixes
carry +lines/commit/reason/removal step and prioritize the split. Finishing a
queue item expires its debt. Owner update uses `--report` and logs findings,
never refusing build/launch for a missing/broken architecture asset.

## Conventions

ADRs0001-0010 record 190f v3 A0-A11/D1-D5/G1-G6. Internal by default; public only
for cross-package APIs, package for same-package plumbing. State/Action/reducer
and injected clients; MainActor UI; Swift6 strict checking per migrated target.
Real-time callbacks: no blocking/allocation/actor hops, written thread ownership.
One cue model in GorCore. GorSubtitles styles/layouts; gorav parses/bitmap-renders.
New non-seam files need >=80 lines or allowed-small reason; ~150 is guidance.
800-line ceiling applies to Swift/scripts; v3 permits recorded hub fixes.
Prefer extract-to-destination; hub glue only when extraction is not practical. Fixes extend the owning responsibility.
Characterize first, move-only then behavior-neutral; no mixed concurrency moves.
One newly migrated target per owner update; native t1+l1-l4+selftest unchanged.

## Delivery and remaining gates

D2 characterization precedes build.sh decomposition. Entry stays ./build.sh.
D3 requires exact staged bytes/modes, backed-up install, retained working updater,
rollback without fetching main, no deletion from overlay omissions. D4 reports
warnings to owner logs and enforces only in lane CI. Q1 toolchain ratchet waits
for a real owner-mac version line; Q2 gates M2/M8; Q3 package roots now have an empty fixture and Linux recovery matrix;
M2a waits for one owner update showing Packages installed. M2b waits for G1.
M3 includes GorStereo then GorFit, one target per owner update (190g).
GorFit.swift exists1323lines (c42/branch measured); M6 re-check stays.
Linux gates close logic/scripts only, never native launch/a-v/adapter evidence.
Every report includes unmapped/new edges/debt current-baseline/tests ran-skipped,
actual file/target counts, top5 Swift/script line deltas, map/manifest/ADR diffs.

## Measurements / v3 corrections

Public surface currently belongs to one gor executable (not a library API).
Current text count: gor public types0 / public declarations2 (commands below).
Count types and declarations separately with:
`rg '^public |^    public ' Sources --glob '*.swift'` (declarations), then
`rg '^public (struct|class|enum|protocol|actor) ' Sources --glob '*.swift'` (types).
These are textual counts, not ABI; per-target counts accompany each migration.
Gorav Q4 remains measured by its owner, never inherited as a gor count.
SwiftUI is not approved by the AppKit edge; needs its own ADR. Lab bridges package.
G6 provider-lock OPEN: before pin bumps, write and name the FFmpeg provider
lock in each repository; same-lock is not a verified fact.
Gorav integration namespace is G1-G6; ladder E1 seam trigger is unchanged.
Advisory findings never block owner build/launch; integrity mismatch never
replaces working release bytes and exits before build/network launch effects.

190g approves temporary-D2-bridge2765lines (+53), removed by D2; no extra growth.

J2 bulk rows pin count and sorted path/content/executable-bit SHA256. New
extensionless/JSON files change the pin and fail until reviewed. Product roots
require per-file policies. Longest matching path wins; emit cannot write policy.

J3: build.sh blobs differ faa9d2ab(be668413) -> c42ad640(80f4e736).
Capture130258:rc0, t1-build-launchPASS, SELFTEST3/3. Per190j this is native
update/reexec evidence for that revision, not proof of current M1 native success.

J1 lock copied from gorav exact source revision; gate compares Git blob and
future dependency pin. No GorAV dependency currently exists; M2b/pin bumps
remain gated until lock revision is the intended verified landing. mpv FFmpeg
version is not measured. Shared lock is not proof of mpv binary provenance.

Provider pin state is explicitly ABSENT today: only lock-byte provenance is
checked. Pin bump/M2b stays blocked until a declared exact pin matches source.

Wait-step progress: every blocking update step prints its operation, elapsed time, measured-history estimate or an explicit enforced bound, and maximum remaining time in English. Record durations locally with tools/gor_step.py and include sanitized STEP_HISTORY records in update captures. Never print an unknown ETA or present a policy bound as a measurement.

## 195w S2.2a relocation receipt

Six bounded helpers are folded byte-for-byte into their existing owner files. SourcePixelCrop.swift owns CropHTTPReader and FFmpegAnalysisThreads; Diag.swift owns SharedDiagnosticRecord, SessionLogPaths and BoundedDiskWriter; Subtitles/SubtitlePreferences.swift owns BoundedSubtitleDownload. Every destination stays under 800 lines. The app target has 155 Swift files (was 162 at the 195o freeze, 161 before this step); no module migration is claimed. Camera, engine, PPController and Features files are unchanged. Characterization tests extract the exact relocated sections for Linux compilation; a stale pre-549 readerArgs locator in analysis_threads_test.py is corrected to the actual two-stage reader pipeline.

## arch-198y S2 GorAVBackend placement

Seven root GorAV source files moved with identical blobs. Folder counts: .=45, Camera=8, GorAVBackend=7, Stereo=2, Subtitles=2, Viewport=2. Total=66. Compiler targets remain one; no module migration is claimed. PreparedShotPlayback.swift is absent from this delivery tree, so the historical S1 row has no file to move.

## arch-198y S2 GorSources placement

11 source blobs moved unchanged. Folder counts: .=34, Camera=8, GorAVBackend=7, GorSources=11, Stereo=2, Subtitles=2, Viewport=2. Total=66. One executable target remains.

## arch-198y S2 GorUI placement

7 source blobs moved unchanged. Folder counts: .=27, Camera=8, GorAVBackend=7, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=66. One executable target remains.

## arch-198y S2 GorPlatformMac placement

7 source blobs moved unchanged. Folder counts: .=20, Camera=8, GorAVBackend=7, GorPlatformMac=6, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

PreviewGuard is preserved byte-for-byte inside QuitChildKiller (741 lines including section markers), removing one standalone file. The added 0f39402 baseline edge row is removed, not broadened.

## arch-198y S2 GorMPVBackend placement

1 source blobs moved unchanged. Folder counts: .=19, Camera=8, GorAVBackend=7, GorMPVBackend=1, GorPlatformMac=6, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorCore placement

3 source blobs moved unchanged. Folder counts: .=16, Camera=8, GorAVBackend=7, GorCore=3, GorMPVBackend=1, GorPlatformMac=6, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorPlaybackModel placement

1 source blobs moved unchanged. Folder counts: .=15, Camera=8, GorAVBackend=7, GorCore=3, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorEffectsModel placement

4 source blobs moved unchanged. Folder counts: .=11, Camera=8, GorAVBackend=7, GorCore=3, GorEffectsModel=4, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorCaptureModel placement

1 source blobs moved unchanged. Folder counts: .=10, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorFit placement

1 source blobs moved unchanged. Folder counts: .=9, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorFit=1, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorStereoUI placement

1 source blobs moved unchanged. Folder counts: .=8, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorFit=1, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorStereoUI=1, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorSubtitles placement

2 source blobs moved unchanged. Folder counts: .=6, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorFit=1, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorStereoUI=1, GorSubtitles=2, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 GorSubtitlesUI placement

1 source blobs moved unchanged. Folder counts: .=5, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorFit=1, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorStereoUI=1, GorSubtitles=2, GorSubtitlesUI=1, GorUI=7, Stereo=2, Subtitles=2, Viewport=2. Total=65. One executable target remains.

## arch-198y S2 gor placement

3 source blobs moved unchanged. Folder counts: .=2, Camera=8, GorAVBackend=7, GorCaptureModel=1, GorCore=3, GorEffectsModel=4, GorFit=1, GorMPVBackend=1, GorPlatformMac=6, GorPlaybackModel=1, GorSources=11, GorStereoUI=1, GorSubtitles=2, GorSubtitlesUI=1, GorUI=7, Stereo=2, Subtitles=2, Viewport=2, gor=3. Total=65. One executable target remains.
