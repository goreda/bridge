#!/usr/bin/env bash
set -euo pipefail
cell="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for test in test_audio.py test_cache_fanout.py test_listeners.py; do
    printf '\n%s\n' "$test"
    python3 "$cell/$test"
done
