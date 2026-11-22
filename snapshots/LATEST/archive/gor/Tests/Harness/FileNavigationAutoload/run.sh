#!/usr/bin/env bash
set -euo pipefail
cell="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$cell/test_navigation.py"
python3 "$cell/test_resource_guards.py"
python3 "$cell/test_autoload.py"
