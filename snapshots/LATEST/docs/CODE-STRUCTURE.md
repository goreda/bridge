# Code structure (gor + gorav). Owner-approved rules; change only with owner words.

## Stations
gor: Sources/gor/<Station>/*.swift, flat, one level. Stations and roles live in STATIONS.tsv
(name | one-line responsibility | may import). Current: App, Player, Engine, Media, Picture,
Stereo, Camera, Subtitles, UI, Modes, Session, Platform.
gorav: Sources/GorAV<Station>/ product modules only; every test/probe target lives under Tests/.

## Placement
S1 A file lives in the station that owns its responsibility, not the station of its caller.
S2 Only Engine talks to an engine: mpv IPC/MPVCommand and any GorAV* import appear in Engine only.
   Other stations call PlayerBackend (PLAN P14/P24).
S3 gorav owns media work (demux, decode, clock, pixels, audio). gor stations own UI, policy, input.
S4 Unwired code does not enter Sources. It stays on a lane until it is called by product code.

## Files
F1 File name = its primary type (UpperCamelCase). Extensions: Type+Topic.swift.
F2 Forbidden in names: block or row ids (192d, 199bh), version tags (V2, R3, New, Old), Stub, Temp, Test.
F3 One concept per file. Merge when two files hold one concept or one only wraps the other.
   Split by concept, never by mechanism. Soft size 60-800 lines; outside that, justify or fix.
F4 No duplicate mechanism across stations: one implementation in the owning station or Platform.

## Header (every Swift file, exactly this, nothing else above imports)
// <Station>/<File>.swift
// <One sentence: what this file owns.>
// Uses: <stations or modules it depends on, or "none">
// Engine: mpv | gorav | both | none
No block ids, dates, owner quotes, agent names, receipts or history: git holds history.
Type-level /// doc comments describe behaviour and invariants only.

## Adding a station
A1 Only when >= 5 files of one responsibility fit no existing station, or a new owner-visible
   capability starts (example: Audio when gor's first audio Swift type lands).
A2 Add a STATIONS.tsv row (name, responsibility, may import) in the same commit as the files.
A3 The architect approves it in a block. No station has fewer than 2 files; > 25 files means split.

## Enforcement
tools/check-structure.sh checks S2, S4 (header tag), F1, F2, header form, STATIONS.tsv membership,
Tests/ placement in gorav. Runs: before every lane push (all Instincts), in assembly before landing,
in every Codemagic batch. build.sh runs it in warn-only mode: it never blocks the owner's update.
A lab return that fails the check is returned to the lab with the failing lines.

ARCHITECT 199ci — finalize code structure: CODE-STRUCTURE.md, headers, station audit, enforcement (to gdb; RELAY verbatim to goreda via i2i, labs via bridge)
owner: 00:27 "dosya yapısı konusunu finalize edelim. header production ready. yönerge oluşturulsun, tüm istasyonlarda uyulsun, kaçak açık istemiyorum. istasyon ekleme kuralı. gorav dökümanları geldiğinde nasıl olacak."
pulse: owner Mac tree (261123-002216) = repo route tree: 12 stations, 86 Swift. Session holds one close-log pipeline split in 5 files; PipeDrain header says "not a production hook"; headers mixed (block ids, agent notes, none). Engine 8 GorAV* files, no PlayerBackend (P14). gorav Sources mixes ~18 product modules with ~80 test targets.
code read: route archive/gor/Sources/gor/{Session/*: FileTransport 206, NativeSink 199, PipeDrain 113, BarrierAdapter 76, DrainPlan 66, TorrentEndpoint 59}, tree listings of Engine, Player, Stereo, Camera; goreda/gorav main Sources listing.
items:
1 Commit docs/CODE-STRUCTURE.md (text owner-pasted 199ci, verbatim) to goreda/instinct and goreda/gorav; STATIONS.tsv with the 12 rows.
2 tools/check-structure.sh per the Enforcement section; wire into lane pre-push, assembly, Codemagic batch; build.sh warn-only.
3 Station audit, one lane, one commit per station, byte-preserving moves/merges, swift build + tests green each:
  Session -> SessionContext, SessionResources, SessionDiagnostics, SessionLogTransport, SessionLogSink (NativeSink+PipeDrain), SessionCloseBarrier (DrainPlan+BarrierAdapter); PlayerTorrentEndpoint -> Media (with TorrentManager).
  Engine -> PlayerBackend (new, P14), MPVBackend, GoravBackend, EngineSelection, EngineObservation (from Player).
  Player -> PlayerController(+Menu, +RefusalHUD), PlayerView (from PlayerViewStub), Input.
  Camera, Stereo, Modes, Media candidates from 199ci chat; writer reads each file, applies S1-F4, merges only true one-concept pairs.
  Every file gets the 4-line header. Unwired code (S4) leaves Sources to a lane; deleting is an owner gate.
4 gorav: move all test/probe targets to Tests/; product modules keep GorAV<Station> names; gor reaches gorav only from Engine.
5 Ship: audit lanes go to the daily native batch; green = one owner update; nothing removed from the product.
RELAY goreda (verbatim): CODE-STRUCTURE.md is law for every file you touch from now: header, placement, names. Keep all workers on P30; apply the rules to your own lanes.
RELAY 1nstinct + in2tinct (verbatim): Every diff you return must pass tools/check-structure.sh (in snapshots/LATEST). New Swift files carry the 4-line header and sit in the owning station; failing diffs come back to you with the lines.
effect: one written structure for gor and gorav, enforced on every push; Session and Engine become readable now; new code (gorav included) cannot reopen the drift.