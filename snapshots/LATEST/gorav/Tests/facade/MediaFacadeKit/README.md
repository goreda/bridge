# MediaFacadeKit - P-B1 clean-room facade skeleton (in2tinct, lab-b)

Contract source: goreda/bridge GROUP-INBOX.md / INBOX-IN2TINCT.md, packet P-B1,
pinned commits d37421b04b06d7c07eef36daf3ac8c0e6569cfb4 (packet publication) and
d9f0c368983d2c11713dca8413c6d76dcb63c513 (delivery to the in2tinct lab inbox).
Lab assignment: in2tinct = lab-b, from the owner's message in the in2tinct group
(2026-11-06 23:55 +03, relayed via the architect). Scope per the owner's 23:58 +03
steering: P-B1 only; P-B2/P-B3 stay with 1nstinct and are not duplicated here.

## Status: ROW SUITE DELIVERED on the approved E1 rows

The approved E1 row set landed at bridge commit 0fe957bed27c486a58b19f5515cce7d662cabae5
(INBOX-IN2TINCT.md, "P-B1 E1 rows", sources: mpv.io manual sections; preamble:
"command-result-or-error preserves errors. property-mutate rows use the facade get/set
contract."). The posted TSV is vendored verbatim at
Tests/MediaFacadeKitTests/Fixtures/facade-rows.tsv (22 rows: 3 command, 4 property-get,
4 property-set, 6 property-mutate, 5 property-observe; sha256
eb1532026534af085b3a00388405e5a26a0c31cd1a12e0b2942eb1e5205ab8e7). One named XCTest per
row (testRow01..testRow22); the mapping is ROW-MAP.tsv.

Schema notes (posted bytes govern): the posted header spells the last column "e_step"
(lowercase; the packet prose said E_step), kinds are command / property-get / property-set /
property-mutate / property-observe, access values execute / read / write / read-write /
observe (kind/access pairing validated), argument_types holds ';'-separated name:type /
name?:type specs ("none" = empty; property-observe rows carry the bare descriptive token
"callback(value)"). value_type forms: command-result-or-error, boolean,
number(...)[-or-unavailable], integer|string(...), array(object)-or-unavailable.

Binding decisions (the packet leaves these open; chosen minimally and labeled):
- Command arguments bind positionally in the row's declared order: all required specs
  present, optionals may be appended in order, nothing beyond - no holes: a later
  optional cannot be supplied while an earlier one is skipped (loadfile's index
  without flags binds positionally to flags:string and fails the type check); types
  checked per spec (string/number/integer/boolean/object onto MediaValue cases).
- property-observe "token:uint64" binds through the observe(token:) API as a real
  UInt64, never through MediaValue; there is no uint64 argument-type branch.
- Command results pass through unchecked ("command-result-or-error": any result value;
  engine errors travel as thrown errors, verified preserved).
- set/mutate values bind against the row's single typed "value:" argument spec; the
  type token carries the posted domain and the facade enforces it with the existing
  named error invalidValueType (no invented error signature):
  - "number(0.01..100)" (speed): explicit bounds - enforced (0.01 and 100 accepted,
    0.005 / 100.5 / 0 rejected).
  - "number(percent)" (volume): "percent" is a unit annotation with no posted bounds -
    the facade enforces the numeric type only and does NOT invent a 0..100 range.
  - "integer|string(auto|no)" (sid, audio, sub): finite integral .number, or .text
    exactly "auto"/"no" - enforced ("bogus", "AUTO", .bool, and .number(1.5)/NaN/
    infinity rejected; rejected values never reach the engine).
  - "integer" (loadfile index?:): finite integral only - 1.5/NaN/infinity rejected.
  - Finiteness of unconstrained "number" tokens (seek target) is UNSPECIFIED in the
    posted contract: labeled, not assumed - the facade is type-only there (NaN/infinity
    pass; engine-level policy), while ranged tokens reject non-finite implicitly.
  - "boolean" (pause, mute): .bool only.
  Anything beyond the posted token (clamping, engine-side range policy) is engine-level
  policy, not facade typing, and is not invented here. The value_type column is the
  property's looser result type, kept for get/observe shape reference.
- "-or-unavailable" in a value_type cell admits .none.
- Observation requires a property-observe row for that name. Read-only observables
  (time-pos, duration) change via engine-originated changes (FakeEngine.simulateChange),
  not client sets; facade.set is rejected for them.
- unobserve is ungated; unknown tokens are a recorded no-op.

## P-B1-R1 strengthening (integrator note at a0bdf13, published 2026-11-06T21:33:56Z)

Four additive proofs in Tests/MediaFacadeKitTests/FacadeR1Tests.swift:
- Kind-separated dispatch for rows sharing names: a synthetic table gives one name
  divergent set/mutate domains and proves set() is governed by the property-set row
  only (the mutate row's domain never leaks in), mutate-only names fall back to the
  mutate row, get-only names reject set; the real fixture's shared names
  (pause/speed/volume) and single-row names (sid set-only; mute/audio/sub
  mutate-only) all dispatch and forward.
- Exact observer tokens: observe/unobserve with UInt64.max and 2^53+1 register,
  fire and remove precisely (the tests first prove a Double round-trip cannot
  represent these tokens).
- Removal proof via a valid typed mutation: after unobserve, facade.set volume 50
  really reaches the engine (snapshot asserted) yet the removed observer stays silent.
- Exact engine API tokens in the call log: RecordedCall carries the observe/unobserve
  token as UInt64 (previously Double-converted - that conversion silently corrupted
  UInt64.max and 2^53+1; fixed, not just documented).

Provenance: the integrator reports their own Mac CI run of r6 as 52/0/0 with the
vendored TSV independently byte-identical (H-0548 note) - that is their reported
execution, not ours; our author run is the one in TEST-RUN.txt. r7 is additive on
top of r6: all 52 r6 tests unchanged and green, plus 4 R1 tests.

## P-B1 E2 rows (posted at 4ae5c0d, published 2026-11-06T21:53:19Z)

12 public rows, e_step E2, same posted schema as E1. Vendored verbatim at
Tests/MediaFacadeKitTests/Fixtures/facade-rows-e2.tsv (sha256
ce6e3ab8bac7050ac041e6da3f2e821de8e950155c4339c44b52f3fdf1384354, byte-identical to
the posted block). Installs additively beside the E1 table (34 rows combined, no
kind/name key conflicts; E1 rows and the E1 audio/sub alias rows unchanged). One
named XCTest per row (testE2Row01..testE2Row12); mapping is ROW-MAP-E2.tsv.

Rows: commands cycle / add / frame-step / frame-back-step; property-set time-pos and
vid; property-mutate vid; property-get volume / aid / sid / vid; property-observe
track-list. Posted semantics honored:
- cycle/add are the generic property commands: the facade enforces the argument spec
  only (name:string;value?:string / value?:number) - whether a (cycle|add, name) pair
  is meaningful is engine-level policy, and the fake's documented policy rejects an
  unknown target name with unsupportedProperty at the engine level (proven by test).
- aid/sid/vid are the canonical track-selector names; E1 audio/sub mutate rows stay
  the alias rows, unchanged.
- time-pos gains a set row (E1 had get/observe only): number(seconds) is a unit
  annotation - type-only, no invented bounds, same rule as percent.
- sid gains a get row beside its E1 set row; dispatch stays kind-separated.

## Public contract (verbatim from the packet, do not extend silently)

MediaValue (none/bool/number/text/list/object), MediaEngine (command/get/set/
observe/unobserve), MediaFacade: MediaEngine. Any required change to this surface
gets reported instead of inventing members. The Codable conformance on MediaValue is
additive test-fixture support and does not alter the contract.

## What the tests prove (70 tests, 0 failures, 0 skips - swift-5.10.1-RELEASE, x86_64-unknown-linux-gnu)

- 22 named row tests (ROW-MAP.tsv): exact forwarding of name/typed arguments/return
  or preserved error for every approved row; observer registration/callback/removal
  per observe row; unavailable (.none) delivered as .none, never fabricated
- mechanics: exact command/get/set forwarding, observer register/notify/unobserve,
  scripted engine error surfaces unchanged, generated fake-engine-events.json
  (empty/load/playback/error) replays
- domains: posted typed domains enforced as above, out-of-domain values rejected and never forwarded
- gating: unapproved names throw (unsupportedCommand/unsupportedProperty), rejected
  calls never reach the engine, value types enforced per row, observe limited to
  property-observe rows
- schema: exact posted header, 6 tab columns, kind/access pairing, argument-spec
  shapes, CRLF == LF parsing (regression: "\r\n" is one Character in Swift -
  reproduced on this toolchain before the fix), duplicate (kind,name) rejected
- 0 skips: the rows-pending skip from the skeleton is resolved by the landed rows

## Layout

- Sources/MediaFacadeKit/MediaValue.swift - contract enum (+ additive Codable)
- Sources/MediaFacadeKit/MediaEngine.swift - contract protocols
- Sources/MediaFacadeKit/MediaError.swift - named error type
- Sources/MediaFacadeKit/RowTable.swift - public E1 TSV schema parser (schema only)
- Sources/MediaFacadeKit/Facade.swift - forwarding facade with row-table validation
- Sources/MediaFacadeKit/FakeEngine.swift - recording fake engine (candidate
  vocabulary loadfile/seek/stop + pause,time-pos,duration,speed,volume,mute,aid,sid,
  track-list; candidate only, not the approved row set)
- Tests/MediaFacadeKitTests/Fixtures/fake-engine-events.json - generated sequence
- Tests/MediaFacadeKitTests/*.swift - the suite described above

## Run

swift test (verified with the public swift-5.10.1-RELEASE ubuntu22.04 toolchain;
tools-version 5.9, Swift 5 default language mode, Foundation only)

Clean-room: public/generated fixtures only; no private source, identifiers, paths,
licensed media or credentials.
