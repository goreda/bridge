#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
B=${PHOTON_BUILD:-/tmp/photon-v4-model}; mkdir -p "$B"
python3 photon-v4/tests/generate-twins.py --check
printf '%s\n' 'io.write(dofile("photon-v4/lua/photon-v4-shader.lua"))' > "$B/twin.lua"
"$B/lua51" "$B/twin.lua" > "$B/lua.frag"
printf '%s\n' 'print(PhotonV4Shader.fragment,terminator: "")' > "$B/main.swift"
${SWIFTC:-/home/sandbox/swift/usr/bin/swiftc} photon-v4/swift/PhotonV4Shader.swift "$B/main.swift" -o "$B/twin"
"$B/twin" > "$B/swift.frag"
cmp "$B/lua.frag" "$B/swift.frag"
cmp "$B/lua.frag" photon-v4/shaders/grain.frag
sha256sum "$B/lua.frag" "$B/swift.frag"
