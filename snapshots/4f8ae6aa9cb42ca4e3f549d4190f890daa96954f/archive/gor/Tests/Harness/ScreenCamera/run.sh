#!/usr/bin/env bash
set -euo pipefail
cell="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$cell/test_sampling.py"
python3 "$cell/test_camera.py"
