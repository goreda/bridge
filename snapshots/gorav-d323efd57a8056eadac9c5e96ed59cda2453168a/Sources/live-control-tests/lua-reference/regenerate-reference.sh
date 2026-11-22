#!/bin/sh
# Regenerate live-control-lua-reference.json: verify the pinned script hash,
# then run the reference runner under LuaJIT. executedLua is only true in the
# output when this script actually executed Lua; if LuaJIT is unavailable,
# leave the previous reference untouched and mark executedLua NOT_RUN in the
# witness output instead of fabricating a reference.
set -e
cd "$(dirname "$0")"
LUAJIT="${LUAJIT:-luajit}"
PIN=4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76
echo "$PIN  vendor/photon-live-control.lua" | sha256sum -c -
"$LUAJIT" run-live-control.lua ../live-control-vectors.json vendor/photon-live-control.lua \
  > live-control-lua-reference.json
echo "wrote live-control-lua-reference.json"
