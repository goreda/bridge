#!/bin/sh
# P-A1 fixture generation. Run from Tests/BridgeDemuxTests/Fixtures/.
# Requires ffmpeg/ffprobe (developed against 4.4.2-0ubuntu0.22.04.1) and python3.
set -eu
export LC_ALL=C
FFMPEG="ffmpeg -hide_banner -loglevel error -y"

$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 0 -pix_fmt yuv420p a1-v24.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -pix_fmt yuv420p -c:a aac a1-av24.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 2 -g 24 -pix_fmt yuv420p a1-bframes.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 0 -pix_fmt yuv420p a1-v24.mkv
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=25 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -pix_fmt yuv420p -c:a pcm_s16le a1-av25.mkv
$FFMPEG -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:a pcm_s16le a1-audio.mkv

for f in a1-v24.mp4 a1-av24.mp4 a1-bframes.mp4 a1-v24.mkv a1-av25.mkv a1-audio.mkv; do
    ffprobe -v error -show_streams -show_packets -of json "$f" > "$f.ffprobe.json"
    ffprobe -v error -show_packets -show_data -of json "$f" | python3 ../../../tools/make_payload_oracle.py "$f" > "$f.payloads.json"
done
