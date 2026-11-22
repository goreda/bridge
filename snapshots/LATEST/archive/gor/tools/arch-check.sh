#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/tools/structure-freeze.py" --root "$root"
if [ "${1:-}" = --freeze-only ]; then exit 0; fi
exec python3 "$root/tools/architecture.py" --root "$root" "$@"
