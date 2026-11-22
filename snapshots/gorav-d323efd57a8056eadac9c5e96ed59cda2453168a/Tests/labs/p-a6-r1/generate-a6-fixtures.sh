#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")"
mkdir -p Tests/BridgeDemuxTests/Fixtures A6Evidence
ffmpeg -version > A6Evidence/ffmpeg-version.txt
ffprobe -version > A6Evidence/ffprobe-version.txt
cd Tests/BridgeDemuxTests/Fixtures
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx265 -pix_fmt yuv420p -c:a eac3 a6-hevc-eac3.mkv
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -pix_fmt yuv420p -c:a aac a6-h264-aac.mp4
for f in a6-hevc-eac3.mkv a6-h264-aac.mp4; do
    ffprobe -v error -show_streams -show_packets -of json "$f" > "$f.ffprobe.json"
done
