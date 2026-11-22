#!/bin/sh
# wt_pause_command_run.sh - extract wtPauseCommand from the product file and
# run wt_pause_command_test.swift against it with swiftc.
# Usage: wt_pause_command_run.sh /path/to/PPController.swift
# Exit 1 (RED) when the seam is absent (pre-fix base) or any case fails.
set -u
SRC="${1:?usage: wt_pause_command_run.sh /path/to/PPController.swift}"
DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Extract the function: from its declaration line to the line whose brace
# depth returns to zero. The seam lives inside the product type, so the raw
# lines are indented and carry `static`; both are illegal at Swift file top
# level. Dedent one level and drop `static` while extracting (same wrapper
# as engine_death_watchdog_run.sh). Brace counting keeps the comment lines
# out and the two branches intact.
awk '
    /^    static func wtPauseCommand\(isPlaying: Bool, playbackEnded: Bool\) -> String\? \{/ { capture=1; depth=0 }
    capture {
        n = gsub(/\{/, "{"); depth += n
        m = gsub(/\}/, "}"); depth -= m
        sub(/^    /, "")
        sub(/^static func/, "func")
        print
        if (depth == 0) { capture=0 }
    }
' "$SRC" > "$WORK/extracted.swift"

if [ ! -s "$WORK/extracted.swift" ]; then
    echo "RED: wtPauseCommand seam absent in $SRC (pre-fix base: resume is gated by the latch)"
    exit 1
fi
# The extraction must be a top-level free function or swiftc rejects it.
if ! head -1 "$WORK/extracted.swift" | grep -q '^func wtPauseCommand('; then
    echo "RED: extraction wrapper broken (first line is not a top-level func)"
    cat "$WORK/extracted.swift"
    exit 1
fi

cat "$WORK/extracted.swift" "$DIR/wt_pause_command_test.swift" > "$WORK/main.swift"
if ! swiftc -o "$WORK/wttest" "$WORK/main.swift" 2> "$WORK/compile.log"; then
    echo "RED: swiftc failed"
    cat "$WORK/compile.log"
    exit 1
fi
"$WORK/wttest"
