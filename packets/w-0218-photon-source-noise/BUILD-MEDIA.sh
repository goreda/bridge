#!/bin/sh
set -eu
u=https://svs.gsfc.nasa.gov/vis/a010000/a012000/a012034/Ice_Edge_UHD_YouTube.mp4
ffmpeg -ss 10 -i "$u" -t 10 -map 0:v:0 -an -c:v copy source-4k-excerpt.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -vf scale=854:480 -c:v libx264 -preset fast -crf 20 -threads 2 media/480p.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -vf scale=1920:1080 -c:v libx264 -preset fast -crf 20 -threads 2 media/1080p.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -c:v libx264 -preset fast -crf 26 -threads 2 media/2160p.mp4
