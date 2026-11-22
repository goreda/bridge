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

# --- P-A1-FMP4 addendum fixtures (fragmented MP4) ---
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 0 -pix_fmt yuv420p -movflags frag_keyframe+empty_moov f1-v24.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -pix_fmt yuv420p -c:a aac -movflags frag_keyframe+empty_moov f1-av24.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 2 -g 24 -pix_fmt yuv420p -movflags frag_keyframe+empty_moov f1-bframes.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -pix_fmt yuv420p -c:a aac -movflags frag_keyframe+empty_moov+default_base_moof f1-av24-bm.mp4
$FFMPEG -f lavfi -i testsrc2=size=64x64:rate=24 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -c:v libx264 -bf 0 -g 12 -pix_fmt yuv420p -c:a aac -movflags frag_keyframe+empty_moov f1-av24-g12.mp4
for f in f1-v24.mp4 f1-av24.mp4 f1-bframes.mp4 f1-av24-bm.mp4 f1-av24-g12.mp4; do
    ffprobe -v error -show_streams -show_packets -of json "$f" > "$f.ffprobe.json"
    ffprobe -v error -show_packets -show_data -of json "$f" | python3 ../../../tools/make_payload_oracle.py "$f" > "$f.payloads.json"
done
