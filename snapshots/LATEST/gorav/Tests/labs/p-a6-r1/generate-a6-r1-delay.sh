#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")"
python3 tools/make_a6_delay.py
ffprobe -v error -show_streams -show_packets -of json Tests/BridgeDemuxTests/Fixtures/a6-hevc-eac3-delay.mkv > Tests/BridgeDemuxTests/Fixtures/a6-hevc-eac3-delay.mkv.ffprobe.json
python3 tools/inspect_a6_mkv.py a6-hevc-eac3-delay.mkv > A6R1Evidence/mkv-codec-delay.json
