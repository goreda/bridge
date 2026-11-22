#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources" "$work/Tests"
for module in GorAVCAtomics GorAVCore GorAVNativeProbeKit; do
  cp -R "$repo/Sources/$module" "$work/Sources/$module"
done
mkdir "$work/Sources/GorAVPlaybackCore"
for f in PlayArguments CoreSeekDriver PlayerControlPlane DecodeHeartbeat ShellSeekBridge SPSC Lane0Contract TimingLedger LifetimeRegistry PlaybackCore PreparedShotSession PreparedVideoFrameSource PreparedAdoption; do
  cp "$repo/Sources/GorAVPlaybackCore/$f.swift" "$work/Sources/GorAVPlaybackCore/"
done
cp -R "$repo/Sources/prepared-shot-tests" "$work/Sources/"
cp -R "$repo/Tests/PreparedVideoSwapTests" "$work/Tests/"
cat > "$work/Package.swift" <<'MANIFEST'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PreparedVideoSwapHarness", targets: [
.target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
.target(name: "GorAVCore", dependencies: ["GorAVCAtomics"]),
.target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"]),
.target(name: "GorAVPlaybackCore", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVCAtomics"]),
.testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"]),
.executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"])
])
MANIFEST
cd "$work"
swift --version
swift test --filter PreparedVideoSwapTests
swift run prepared-shot-tests
