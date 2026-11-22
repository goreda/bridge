# Gor bug log

## 2026-10-04 18:01 - input.conf omitted from delivered v2.2.0 ZIP

Status: OPEN. Owner detected the missing file at 18:00:22 (phonemsg-01M43PWACN6SK95H87BXBDN8WN) and requested error-report recording at 18:01:20 (phonemsg-01M43PY3QJR8PFEDPH1Q7CP8JS). Both messages and the later stop were independently read in the live owner conversation.

Affected delivery: 261004-175651-gor-photon-v2.2.0-residual-adaptive.zip, 267374 bytes, SHA256 025c5426d64037215773b9791ad8923019b445cd0216c9f0dd320d89fab39197. Live delivered attachment: phonemsg-01M43PQZP2BV1FAF55DQXX8CJX, 17:58:00. Supplied archive member list confirms input.conf is absent. Delivered-media byte equality remains unverified due HTTP403; supplied archive bytes and its member hashes are verified.

Impact: the announced grain-size shortcuts shift+b / cmd+b / shift+cmd+b require input.conf bindings and were not included in the delivery. No Mac behavior test performed by custody. Current repository input.conf also has no such size bindings; it is a baseline for append work, not a completed fix.

Parent-reported root cause: order scope versus ZIP member mapping was skipped; when writing the Swift-side message path, input.conf was left out of the member list. ZIP control hashes verified included members but did not validate order completeness.

Correction plan, not completion: assemble a replacement ZIP including amended input.conf and build.sh mode0755. Owner then said wait at18:01:52, do not send ZIP at18:01:57 and stop at18:02:00 (phonemsg-01M43PZ2GM8AM0RAG0SPSKA251, phonemsg-01M43PZ7BG1DREM2WNXSCXSNJT, phonemsg-01M43PZACCWMA8CP4185CTT8G0). Main acknowledged parked/not sent at18:02:07. Do not mark the fix delivered or cleared.

The keeper's gate question, October3 ready/approval rule versus same-day delivery instruction, remains in the gor architect's disposition according to main. This entry does not settle that question or establish send authority. No new ZIP send, build, runtime test or source amendment performed here.

Baseline input.conf: gor/Resources/vendor/mpv/input.conf,2036 bytes,SHA256 26aae0597b817c20f787033e5c4d34c313bf53269fcd31e55e16303431f6241a,last change c62cacbf9fec2012134edcad27d4146ba70daf8c. Full bytes including Ctrl+F10 and the following section were transferred to main. Exact owner-installed equality and specific delivered origin remain unverified.


## 2026-10-04 18:09 successor - missing input.conf packaging corrected

Status: CORRECTED within packaging/member scope only. Replacement261004-180701-gor-photon-v2.2.0-residual-adaptive.zip,286943bytes/SHA256b8597ac24aa8f0443d7ff84ba9e1f4f42beb05149ad7f3f5738fabedd135cbf6,includes input.conf2333bytes/f59d5538305d95e30b9cef07b40dd701e1a1f72e68727a7fdc8db2ae7f283964 and build.sh0755. Exactbaseline-plus4line comparison and archive/member checks PASS. Live delivery confirmed18:08:51,phonemsg-01M43QBV326Y0QB0SQZT1BE7ZB. Earlier omission entry remains history;17:58ZIP is STALE. Mac shortcut/runtime/native compile checks remain PENDING,not closed by packaging correction. Delivered-media byte equality remains unverified. No FIXED prevention/recurrence claim.


## 2026-10-04 19:00 successor - build failure 1, standalone writer top-level code

Parent/keeper-reported owner-log finding: GorLogWriter.swift placed in Sources/gor has top-level code rejected by SwiftPM. Source attachment message phonemsg-01M43S8VBDMT0N11PKXAY9JBAR at18:42:09,261004-184137-gor_direct.log; message presence independently read, log bytes not read by this custody pass. v2.2.1 removes the standalone member and embeds identical7254-byte writer source in build.sh heredoc, compiled as temporary main.swift. Source/package correction checked in prior custody; no native successful build verified. Status: SOURCE/PACKAGE CORRECTION RECORDED, native regression test PENDING. Delivered18:43:03,phonemsg-01M43SAFSSF4X8DFVC1VQ29BRN independently confirmed; no delivered-media equality or FIXED recurrence claim.

## 2026-10-04 19:00 successor - build failure 2, MagnetFallbackSearch missing

Parent/keeper-reported owner-log finding: MagnetFallbackSearch missing from scope after a repo-based MagnetBrowser replaced the owner's fallback-bearing source. Source attachment phonemsg-01M43SFR73WETRS4M63SZQ2BSY at18:45:55,261004-184530-gor_direct.log; message presence independently read, log bytes not read here. v2.2.2 additive delta73940-byte MagnetBrowser preserves one fallback class definition and adds the hoax patch on the recovered60081-byte07d0764f baseline from261002-155900-gor-fixed-sources.zip. That baseline's custody identity is checked, but delivered/installed origin remains producer-reported;111600consolidationZIP instead has57214-byte member and is NOT the60081-byte origin. Merge-method and causal diagnosis remain attributed. Status: SOURCE/PACKAGE CORRECTION RECORDED, native compile/runtime PENDING. Delta delivered18:51:00,phonemsg-01M43SS0PAZ0YZS6PDTWR3CD44 independently confirmed. v2.2.1 full bundle remains base,not superseded by delta. No native success,delivered-media equality or FIXED prevention claim.

## 2026-10-19 - subtitle bugs custody handoff pointer

Subtitle-bug custody deposit and extracted review material for the subtitle renderer work now live in gor/subtitle-bugs-handoff/ (RECEIPT.md, CUSTODY-MANIFEST.json, EXTRACTED-MANIFEST.json, extracted/ evidence sets r3b and r4, subtitle-custody-deposit.tar.gz). Pointer recorded as add-only docs change per project coordinator; no defect status implied by this entry.
