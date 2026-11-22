#!/bin/sh
# Entry point for the gor PlayerBackend hook. Exit 77 means UNRUN, never PASS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ROOT=${GORAV_ENGINE_ROOT:-$HERE}
if [ ! -f "$ROOT/Package.swift" ] || [ ! -f "$ROOT/Tests/presenter/run-native.sh" ]; then
  echo 'GORAV_E1 UNRUN: engine root lacks Package.swift or native presenter regression' >&2
  exit 77
fi
if [ "$(uname -s)" != Darwin ]; then
  echo 'GORAV_E1 UNRUN: requires macOS and actual host embed/playback venue' >&2
  exit 77
fi
cd "$ROOT"
printf 'GORAV_E1 engine-root: %s\n' "$ROOT"
git rev-parse HEAD
# These are the native geometry prerequisite, not playback acceptance.
Tests/presenter/run-native.sh
echo 'GORAV_E1 geometry prerequisite: PASS' >&2
# Landed venue legs: the E1Headless pipeline executable, built with the real
# audio-out and host-embed legs enabled. Its own asserts produce the leg
# evidence; this hook adds no placeholder PASS. A BAD leg exits nonzero
# under set -e with the typed failure line.
BIN=.build/debug/e1-headless-tests
if [ ! -x "$BIN" ]; then
  swift build --product e1-headless-tests -Xswiftc -DE1_WITH_AUDIO_OUT -Xswiftc -DE1_WITH_EMBED || {
    echo 'GORAV_E1 UNRUN: e1-headless-tests venue build failed' >&2
    exit 77
  }
fi
if [ ! -x "$BIN" ]; then
  BIN=$(find .build -type f -name e1-headless-tests -path '*debug*' 2>/dev/null | head -1 || true)
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo 'GORAV_E1 UNRUN: e1-headless-tests executable not found after build' >&2
  exit 77
fi
if [ ! -f fixtures/e1-h264-aac-10s.mp4 ]; then
  echo 'GORAV_E1 UNRUN: e1-h264-aac-10s.mp4 fixture not landed' >&2
  exit 77
fi
"$BIN" fixtures/e1-h264-aac-10s.mp4
echo 'GORAV_E1 embed+frame+audio venue legs: PASS (E1-HEADLESS evidence above)' >&2
# Session venue leg: the PlayerBackend seam call sequence (open / pause /
# resume / seek / stop+single-use) against GorAVEmbeddedSession's public
# surface. rc 2/77 stay typed UNRUN; a BAD line is a real failure.
VBIN=.build/debug/session-venue-tests
if [ ! -x "$VBIN" ]; then
  swift build --product session-venue-tests || {
    echo 'GORAV_E1 UNRUN: session-venue-tests build failed' >&2
    exit 77
  }
fi
if [ ! -x "$VBIN" ]; then
  VBIN=$(find .build -type f -name session-venue-tests -path '*debug*' 2>/dev/null | head -1 || true)
fi
if [ -z "$VBIN" ] || [ ! -x "$VBIN" ]; then
  echo 'GORAV_E1 UNRUN: session-venue-tests executable not found after build' >&2
  exit 77
fi
if "$VBIN" fixtures/e1-h264-aac-10s.mp4; then
  echo 'GORAV_E1 session venue legs: PASS (SESSION-VENUE evidence above)' >&2
else
  vrc=$?
  if [ "$vrc" -eq 2 ] || [ "$vrc" -eq 77 ]; then
    echo "GORAV_E1 UNRUN: session venue typed rc=$vrc (see line above)" >&2
    exit 77
  fi
  echo "GORAV_E1 FAIL: session venue rc=$vrc" >&2
  exit 1
fi
# No placeholder PASS: rollback acceptance executable still not wired into
# this venue (it lands via lane/189k-merged-engine).
echo 'GORAV_E1 UNRUN: rollback acceptance executable is not landed in this venue' >&2
exit 77
