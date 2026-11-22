# P29-LIVE-CONTROL authoritative Lua reference (DR-0021, lane c)

`live-control-vectors.json` (one level up) is a MODEL-ONLY Python replay of
photon-live-control.lua semantics: a cross-check, never the authority. The
authoritative reference is `live-control-lua-reference.json`: raw outputs
captured by executing the EXACT pinned script
(`vendor/photon-live-control.lua`, M.VERSION=1, SHA256
4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76 - the
driver verifies the hash before running) under real LuaJIT, replaying the
same ops. `run-live-control.lua` is a runner only; it re-implements nothing
of the pinned script. Harness config closures (classify_cut, settled,
target, velocity, feed, and the scalar config) are test fixtures, injected
into the pinned script exactly as its host would inject them, and mirrored
one-for-one in the Python replay and the Swift witness.

Regenerate (needs a LuaJIT binary; LuaJIT 2.1 branch v2.1 built from
github.com/LuaJIT/LuaJIT was used):

    LUAJIT=/path/to/luajit ./regenerate-reference.sh

The reference JSON carries `executedLua: true` and the runtime string. If
LuaJIT is unavailable, do NOT regenerate from Python and do NOT edit the
reference by hand: leave it and let the witness report executedLua NOT_RUN.

Only one authoritative Lua execution should exist across lanes (Ops review
of 38811041): goreda's twin parity-checks against this runner and output.
