# P23 runnable packet materials (lane a, 2026-11-16 ~22:52 +03)

Pin: goreda/instinct @ 56181f7699d792a3a3e095caf2e807a551be46f9
(archive/gor/Resources/vendor/mpv/scripts/). Target rev: gorav main
31ffba3ae35a13d316b92a16ee78ce17b57d8741. Public/license-free sources only
(own vendored mpv scripts); no credentials, user data or licensed assets.

## Contents
- lua/vr180-look.lua     sha256 c455d945818a23ed7ddcb77a22002d12873430e53198b0ef253a673d7ccbeffc
- lua/photon-sharp.lua   sha256 f9aeedb4265d281ec87d9bdea6b45168d9af6431ce353a554202d44b2f7c46d1
- lua/photon-grain.lua   sha256 cfa29f39a332615718c3844ded69bc680cb3816732a690dee5b5a48e97f82999
- swift/LookShaderGenerator.swift @ goreda/gorav lane/gdb-m3-render 47f8a39c7941e483d99b95f7ea4fac94eae56a84
                         sha256 3156f40f6a3ebe78523537e508c590bc8891cded23b377f3737e54661301406c
- harness/mp_stub_capture.py  (rebuilt arch-196z e01ee437 capture harness:
  lupa + mp-stub; run: `python3 mp_stub_capture.py <vr180-look.lua> <outdir>`;
  needs python3 + lupa 2.8, Linux, no mpv/GPU)
- expected/vr180-look-{base,extended,legacy,pack}.glsl - fresh capture
  output of that harness against the pinned Lua.

## Capture result (fresh run, this workspace)
All four route dumps BYTE-MATCH the byte-lock fixtures committed in
LookShaderGenerator.swift's header on lane/gdb-m3-render:
- base     1bace86d9c4f44e49bcb30599c6afa31991e1d772aab3333347d6e36495c8601
- extended cbeb9f593cf1b5ab654a82293ec99fdfb5b22b9d312c9b51ecf54b762fa39cc7
- legacy   04f432983f8d166e486d739e7602e08bfb8fca44208bd18a861b481572f893a4
- pack     287bd5a07ad751aea77405fa4cd6e16ad29495fade3da9ae11dc0b7b4cfed9c1

Harness instrumentation disclosure: the route sources are chunk-scope
locals in the Lua and the base global is overwritten with the legacy text
at load end, so the harness (a) snapshots the base global just before the
extended-source definition, (b) appends a `return` of the three route
locals to the chunk. Capture-only; no semantic change to the script.

## Notes
- The Swift file needs its branch context to compile (LookParameterBlock.swift,
  ControlBus.swift -> GorAVPlaybackCore on lane/gdb-m3-render). Standalone
  compile was not forced here; the Swift-side run evidence is the branch's
  recorded suites: look-shader-tests 19/19 (incl. D1-D4 MSL drift guards),
  look-param-tests 23/23, stage-list 13/13 (commits e01ee437, 64c7d847).
- photon-sharp / photon-grain: sources delivered; no Swift twin exists yet
  (see Ops packet W-gdb-ops-p23-001 inputs note).
