#!/usr/bin/env bash
set -euo pipefail
cell="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "$cell/test_abort.mjs"
