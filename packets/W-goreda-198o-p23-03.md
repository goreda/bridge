# W-goreda-198o-p23-03: one-family Swift/Lua emitter twin

Status: startable source/emitter task, not accepted parity. Consuming integrator: goreda; native integration remains outside this packet. Uses only already-shared bridge input, no private repository/Mac access. Family: translucid mode only; all ng_bake_common constants and exact %.4f substitutions.

## Exact inputs

Bridge ref `14c53ca`, path `inputs/198k/mpv/scripts/photon-negativ.lua`, git blob `fa540b521c2b32e225ecb0c5dcc8b5e039ee784c`, SHA256 `971f4c189c3e1a54bd556446f110787d6d98c60c449d92d0cd28371463cebb80`, 60714bytes. Verify these bytes before work; fail visibly on mismatch. Shared helper, if needed: same ref `inputs/198k/mpv/scripts/photon-common.lua`, blob `762a731a930a0bb76b029b7c33ca782ce85bf47b`, SHA256 `827d96e2cc7ab0c56861383d8e8fe0a7834bd545e99c934e9ec5f03acb57b4f7`.

The existing published file is the entire source of the template, constants and substitutions. Do not fetch/copy any private source or invent a replacement template. Do not read or supply TEX_BLUENOISE, media, fonts or user state. This packet does not need grain or any texture resource.

## Interface

Implement a pure Swift emitter taking the family bake constants as a typed value and returning the exact UTF-8 emitted GLSL bytes. Extract the exact constant names/defaults/types from the pinned file and list them in the return before code. Use `GOR_NEGATIV_SOURCE_TRANSLUCID` and the bake operations actually called by `ng_n_write_shader`. Preserve Lua long-string leading-newline semantics, Unicode bytes, spaces, comments, final LF and format precision. Do not use a retyped GLSL template or a different shader family. Parameters that the source pushes at runtime are not baked emitter inputs.

Reference: execute the actual pinned Lua bake path with Lua5.1 or LuaJIT, in an isolated temporary directory and C numeric locale, capturing writes rather than running mpv. Either isolate the named template/constants/bake function verbatim with source-span hashes, or provide minimal mp/require/file stubs so the named write path executes. Report which method and every source span used; do not replace Lua formatting with a claimed equivalent Python oracle. Include all stubs in the return and assert that no unexpected file/process/network action occurred. Do not duplicate the separately owned live-control reference runner.

## Failure-first tests and acceptance

Before implementing Swift, make the comparator fail for one changed template byte, one wrong baked constant, one missing final LF and one altered precision. Then compare Lua versus Swift for pinned defaults, zero and positive/negative finite values where a particular constant's actual source domain allows them, and decimal-rounding boundary values at its actual precision. Record the admitted input domains from source, not model guesses; unsupported nonfinite/out-of-domain input must be reported separately rather than widening the original contract. For the sharp packet, explicitly assert that spatial output has no appended COMPUTE block. For other packets, check only invariants actually present in the pinned selected family.

Acceptance: each accepted vector has equal byte count, equal SHA256 and zero byte diff against the executed Lua path. Numeric/image similarity is insufficient. Include at least five vectors and a default expected-output hash produced by the executed reference. Report bytes even if shader parsing is unavailable; do not claim pixels, GPU execution, delivered parity or owner acceptance. No delivery feature is disabled or removed.

## Reproducer, dependencies and return

Required tools: Python3 stdlib for orchestration, Lua5.1 or LuaJIT for the reference, Swift compiler for the twin. Return a `run.py` entry point accepting `--lua PATH --swiftc PATH --input PATH --out DIR`; it verifies the pinned input digest, constructs isolated references, builds Swift, runs vectors and negative controls, then exits0 only when all expected comparisons hold. Exact intended invocation from bridge root:

```sh
python3 run.py --lua /path/to/lua --swiftc /path/to/swiftc --input inputs/198k/mpv/scripts/photon-negativ.lua --out /tmp/W-goreda-198o-p23-03
```

Discover local executables and report their versions. If absent, return complete source and exact missing dependency; no invented execution. This dependency report is not parity acceptance.

Target branch: `lab/W-goreda-198o-p23-03`. Return complete Swift emitter, actual Lua reference/stubs, run.py, fixtures, source-span manifest, commands/versions/exits, raw logs, output SHA256/byte-diff table and intentional-mutant failures. Do not execute a private app, touch delivery refs or modify the pinned input. Done when the consuming integrator can rerun the same named command and inspect exact equality, or has a precise reproducible failure.
