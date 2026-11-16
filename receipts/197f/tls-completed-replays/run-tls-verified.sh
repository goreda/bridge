#!/usr/bin/env bash
# Invoke: bash run-tls-inventory.sh CHECKOUT FF_PREFIX
# CHECKOUT must be a clean a34e2cd checkout. FF_PREFIX is the provider used
# by the product build, not a system ffmpeg. Runs in a disposable archive.
set -u -o pipefail
repo=$(realpath "$1"); ff=$(realpath "$2"); here=$(cd "$(dirname "$0")" && pwd)
want=a34e2cd96b6825932a196424a17cc62962e910a7
[ "$(git -C "$repo" rev-parse HEAD)" = "$want" ] || exit 2
[ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ] || exit 2
work=$(mktemp -d)
trap 'rm -f "$work/key.pem" "$work/cert.pem" "$work/wrong-key.pem" "$work/wrong-cert.pem"' EXIT
printf 'RETAINED_TREE=%s\n' "$work/tree"
mkdir "$work/tree"
git -C "$repo" archive HEAD | tar -x -C "$work/tree"
printf 'product_sha=%s\nprovider_prefix=%s\n' "$want" "$ff"
export PKG_CONFIG_PATH="$ff/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$ff/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
pkg-config --modversion libavformat libavcodec libavutil libswresample
cc "$here/protocol-inventory.c" -I"$ff/include" -L"$ff/lib" -Wl,-rpath,"$ff/lib" $(pkg-config --static --cflags --libs libavformat libavcodec libavutil) -o "$work/protocol-inventory" || exit 2
ldd "$work/protocol-inventory"
"$work/protocol-inventory"; inventory_rc=$?
# Ephemeral fixture key: never print, attach or retain it.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 1 -subj /CN=fixture.invalid -addext 'subjectAltName=IP:127.0.0.1' > /dev/null 2>&1 || exit 2
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/wrong-key.pem" -out "$work/wrong-cert.pem" -days 1 -subj /CN=wrong.invalid -addext 'subjectAltName=DNS:wrong.invalid' > /dev/null 2>&1 || exit 2
export M2_TLS_WRONG_CERT="$work/wrong-cert.pem" M2_TLS_WRONG_KEY="$work/wrong-key.pem"
export M2_TLS_CERT="$work/cert.pem" M2_TLS_KEY="$work/key.pem"
cp "$here/tls-verified-main.swift" "$work/tree/Sources/remote-source-tests/main.swift"
python3 "$here/patch-tls-close-order.py" "$work/tree" || exit 2
python3 "$here/patch-tls-verified.py" "$work/tree" || exit 2
cd "$work/tree"
swiftc --version
# Preserve actual red status. No expected failure is converted to product PASS.
# Existing Package.swift/provider layout must already be configured by the lane.
# Link explicitly to the measured candidate provider, including static deps.
mapfile -t ff_link < <(pkg-config --static --libs libavformat libavcodec libavutil libswscale libswresample | python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.stdin.read())))')
swift_args=(-Xcc "-I$ff/include")
for flag in "${ff_link[@]}"; do swift_args+=(-Xlinker "$flag"); done
timeout 300 swift run "${swift_args[@]}" remote-source-tests; product_rc=$?
printf 'M2_TLS_VERIFIED_PCM_RESULT inventory_exit=%s product_open_exit=%s\n' "$inventory_rc" "$product_rc"
[ "$inventory_rc" -eq 0 ] && [ "$product_rc" -eq 0 ]
