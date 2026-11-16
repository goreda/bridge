#!/usr/bin/env bash
# Controlled fixture only. Invoke: bash run-coordinator-process.sh CLEAN_A34_CHECKOUT FF_PREFIX
set -eu -o pipefail
repo=$(realpath "$1");ff=$(realpath "$2");here=$(cd "$(dirname "$0")" && pwd)
want=a34e2cd96b6825932a196424a17cc62962e910a7
[ "$(git -C "$repo" rev-parse HEAD)" = "$want" ] || exit 2
[ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ] || exit 2
work=$(mktemp -d);trap 'rm -rf "$work"' EXIT
mkdir "$work/tree";git -C "$repo" archive HEAD | tar -x -C "$work/tree"
export PKG_CONFIG_PATH="$ff/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$ff/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
printf 'product_sha=%s\nprovider_prefix=%s\n' "$want" "$ff"
node --version;swiftc --version
pkg-config --modversion libavformat libavcodec libavutil libswresample
cp "$here/coordinator-pcm-main.swift" "$work/tree/Sources/remote-source-tests/main.swift"
cp "$here/NodeSourcePreparation.swift" "$work/tree/Sources/GorAVPlaybackCore/NodeSourcePreparation.swift"
cp "$here/OpenURLRouter.swift" "$work/tree/Sources/GorAVCore/OpenURLRouter.swift"
mkdir "$work/cache"
export M2_NODE="$(command -v node)" M2_SOURCE_SCRIPT="$here/fixture-prepare-source.mjs" M2_SOURCE_CACHE="$work/cache"
node "$here/transfer-api-fixture.mjs" "$work/fixture" > "$work/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; rm -rf "$work"' EXIT
for _ in $(seq 1 100);do [ -f "$work/fixture/gateway" ] && break;sleep .02;done
[ -f "$work/fixture/gateway" ] || { cat "$work/server.log";exit 2; }
export M2_SOURCE_GATEWAY="$(cat "$work/fixture/gateway")" M2_SOURCE_ANCHOR="$work/fixture/anchor.pcm"

node --check "$here/prepare-source.mjs"
python3 "$here/../patch-tls-close-order.py" "$work/tree"
sha256sum "$here/NodeSourcePreparation.swift" "$here/OpenURLRouter.swift" "$here/coordinator-pcm-main.swift" "$here/fake-prepare-source.mjs"
mapfile -t ff_link < <(pkg-config --static --libs libavformat libavcodec libavutil libswscale libswresample | python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.stdin.read())))')
swift_args=(-Xcc "-I$ff/include")
for flag in "${ff_link[@]}";do swift_args+=(-Xlinker "$flag");done
cd "$work/tree"
set +e
timeout 300 swift run "${swift_args[@]}" remote-source-tests
rc=$?
printf 'M2_COORDINATOR_PCM_RESULT product_decode_exit=%s\n' "$rc"
exit "$rc"
