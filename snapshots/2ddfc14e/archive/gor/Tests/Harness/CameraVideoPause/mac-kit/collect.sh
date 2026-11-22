#!/bin/bash
# Local evidence collection only. Does not launch, quit, restart or alter playback.
set -euo pipefail
if [ "$#" -ne 1 ]; then printf 'Usage: bash collect.sh /path/to/gor/source-tree\n' >&2; exit 2; fi
root="$1"
[ -d "$root/Sources/gor" ] || { printf 'Missing Sources/gor\n' >&2; exit 2; }
out="$HOME/Desktop/gor-backlog-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$out/collected-at.txt"
sw_vers > "$out/os-version.txt"
for f in AppDelegate.swift PPController.swift PPController_Features.swift VRStereoControlInput.swift GeomTrace.swift SeededRandomNumberGenerator.swift BrightnessController.swift MusicRowLabel.swift PlayerViewStub.swift BrightnessReadCache.swift DragDropHandler.swift MusicModeController.swift IPTVModeController.swift BlinkCommandRoute.swift CaptureConsumerRules.swift VR180Controller.swift InputController.swift ContentAdaptiveDimming.swift SpineUI.swift ScreenCaptureEngine.swift; do
  for d in Sources/gor Sources/gor/gor; do
    [ -f "$root/$d/$f" ] && shasum -a 256 "$root/$d/$f" >> "$out/source-sha256.txt"
  done
done
for f in gor_direct.log wt_full.log gor_diag.log; do
  [ -f "/tmp/$f" ] && cp "/tmp/$f" "$out/$f"
done
for f in "$root/gor-build-manifest.json" "$root/Resources/vendor/mpv/scripts/gor-build-manifest.json" "$HOME/Library/Logs/gor/quit-debug.log"; do
  [ -f "$f" ] && cp "$f" "$out/$(basename "$f")"
done
ps -axo pid,ppid,lstart,command | grep -E '[/ ](gor|mpv)( |$)|gor.app/Contents/MacOS/gor' | grep -v grep > "$out/processes.txt" || true
printf 'Evidence saved to: %s\nNo tests were run. Keep the folder private; logs and paths may contain personal data.\n' "$out"
