#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p results
for h in 480 1080 2160; do python3 harness/run.py "$h" on; done
python3 harness/check_noise_feed.py
