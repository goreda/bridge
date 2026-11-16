#!/usr/bin/env bash
# Controlled fixture only. Invoke: bash run-transfer-pcm.sh CLEAN_A34_CHECKOUT FF_PREFIX
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
cp "$here/transfer-pcm-main.swift" "$work/tree/Sources/remote-source-tests/main.swift"
python3 "$here/../patch-tls-close-order.py" "$work/tree"
node "$here/test-transfer-download.mjs" "$work/tree/fixtures"
sha256sum "$work/tree/fixtures/transfer-downloaded.wav" "$work/tree/fixtures/transfer-anchor.pcm"
mapfile -t ff_link < <(pkg-config --static --libs libavformat libavcodec libavutil libswscale libswresample | python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.stdin.read())))')
swift_args=(-Xcc "-I$ff/include")
for flag in "${ff_link[@]}";do swift_args+=(-Xlinker "$flag");done
cd "$work/tree"
set +e
timeout 300 swift run "${swift_args[@]}" remote-source-tests
rc=$?
printf 'M2_TRANSFER_PCM_RESULT product_decode_exit=%s\n' "$rc"
exit "$rc"
