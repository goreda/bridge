#!/bin/bash
# arch-198k runtime-dump core witness: compile core+suite, expect FAILS 0
# (same GorFit harness pattern as Tests/Harness/HDRHandoff).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d /tmp/gor-runtime-dump-witness.XXXXXX)"
swiftc -O "$HERE/../../../Sources/gor/GorRuntimeDumpCore.swift" "$HERE/suite/main.swift" \
  -o "$WORK/runtime-dump-witness" 2>"$WORK/build.log"
if [ $? -ne 0 ]; then
  echo "BUILD FAIL"; cat "$WORK/build.log"; exit 1
fi
"$WORK/runtime-dump-witness" | tee "$WORK/run.log"
grep -q '^FAILS 0$' "$WORK/run.log"
RC=$?
if [ $RC -eq 0 ]; then
  echo "PASS: runtime dump core witness; logs retained at $WORK"
else
  echo "FAIL: runtime dump core witness; logs retained at $WORK"
fi
exit $RC
