#!/bin/sh
# gen_fixtures.sh - W-0274 fixture generator (generated media only, no owner media).
# Uses system ffmpeg 4.4.2 CLI; deterministic lavfi sources (testsrc2, sine).
set -e
cd "$(dirname "$0")/fixtures"
FF="ffmpeg -hide_banner -loglevel error -y"

# f_shortgop.mp4: 25 fps, GOP 12, 2 B-frames, 44.1 kHz AAC, 6 s
$FF -f lavfi -i testsrc2=size=320x240:rate=25:duration=6 \
    -f lavfi -i sine=frequency=440:sample_rate=44100:duration=6 \
    -c:v libx264 -preset veryfast -g 12 -bf 2 -pix_fmt yuv420p \
    -c:a aac -b:a 64k f_shortgop.mp4

# f_longgop.mp4: 25 fps, GOP 250 (10 s), 3 B-frames -> red-evidence fixture
$FF -f lavfi -i testsrc2=size=320x240:rate=25:duration=10 \
    -f lavfi -i sine=frequency=440:sample_rate=44100:duration=10 \
    -c:v libx264 -preset veryfast -g 250 -bf 3 -pix_fmt yuv420p \
    -c:a aac -b:a 64k f_longgop.mp4

# f_unequal_tb.mp4: 30000/1001 fps, video timescale 30000, 48 kHz audio
$FF -f lavfi -i testsrc2=size=320x240:rate=30000/1001:duration=8 \
    -f lavfi -i sine=frequency=330:sample_rate=48000:duration=8 \
    -c:v libx264 -preset veryfast -g 60 -bf 2 -pix_fmt yuv420p \
    -video_track_timescale 30000 \
    -c:a aac -b:a 64k f_unequal_tb.mp4

# f_negstart.mkv: video at 0, audio shifted 1 s early; mkv keeps a negative
# audio start_time (AAC priming lands before 0). -avoid_negative_ts disabled.
$FF -itsoffset -1.0 -f lavfi -i sine=frequency=550:sample_rate=44100:duration=7 \
    -f lavfi -i testsrc2=size=320x240:rate=25:duration=6 \
    -map 0:a -map 1:v \
    -c:v libx264 -preset veryfast -g 25 -bf 2 -pix_fmt yuv420p \
    -c:a aac -b:a 64k -avoid_negative_ts disabled \
    -f matroska f_negstart.mkv

sha256sum f_shortgop.mp4 f_longgop.mp4 f_unequal_tb.mp4 f_negstart.mkv | tee fixtures.sha256
