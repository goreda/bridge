# W-gdb-006 FFmpeg http/tcp configure-diff kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-006

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
the pinned FFmpeg mirror is configured file-protocol-only, so four native harness rows (54/61/62/64) cannot run - remote-source behavior has no honest native witness. the protocol add is approved, but there is no kit proving a given build actually carries the required protocols (and nothing else unexpected).

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: .github/workflows/engine-macos.yml (sha256 5a16a065, 2269B) - the pinned configure line; scripts/ci/native-harness-map-195b.md (same pin) - the gap note "blocks 54/61/62/64 natively".
- real test command: the kit runs standalone (python3 stdlib + shell); no FFmpeg build required.

## expected behaviour
a kit that reads a build's recorded configure line and protocol list and diffs them against a required capability set (case in scope: file-only baseline vs file+http+tcp target), printing typed PASS/FAIL per capability plus a machine-readable receipt; synthetic transcripts cover exact match, missing protocol, extra protocols, reordered flags, unknown flag.

## exact call site and interface
the workflow's configure block (pinned file) is the baseline input; the kit's receipt schema is the deliverable interface the CI step adopts.

## behaviour that must not change
the pinned FFmpeg revision and the shipped provider pin; no network access in the kit; no built binaries or license text shipped.

## acceptance test (from the product repo)
kit PASSes a file+http+tcp transcript and FAILs the file-only one with the missing capabilities named; negative control (dropped flag) shown in the returned log.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### .github/workflows/engine-macos.yml (sha256 5a16a065, lines 1-42 of 42)
```yaml
name: GorAV engine macOS baseline
run-name: GorAV full-package and G3 native tests
on:
  push:
    branches: [gorav/engine, lane/goreda-g3]
    paths: ['Sources/**', 'Tests/**', 'Package.swift', '.github/workflows/engine-macos.yml']
permissions:
  contents: read
concurrency:
  group: gorav-engine-macos
  cancel-in-progress: false
jobs:
  native-baseline:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Record exact trunk and toolchain
        run: |
          git rev-parse HEAD
          swift --version
          sw_vers
      - name: G3 actual AppKit view regression
        run: Tests/presenter/run-native.sh
      - name: Configure and build bundled FFmpeg
        shell: bash
        run: |
          set -euo pipefail
          tar -xf ffmpeg-894da5ca-refetch.tar.xz -C "$RUNNER_TEMP"
          FF="$RUNNER_TEMP/FFmpeg-894da5ca7d742e4429ffb2af534fcda0103ef593"
          cd "$FF"
          ./configure --disable-programs --disable-doc --disable-everything --disable-avfilter --disable-avdevice --disable-x86asm --disable-asm --disable-debug --disable-bzlib --disable-lzma --disable-iconv --disable-securetransport --disable-audiotoolbox --disable-coreimage --disable-appkit --disable-avfoundation --disable-metal --enable-zlib --enable-protocol=file --enable-demuxer=mov --enable-demuxer=matroska --enable-demuxer=wav --enable-demuxer=image_ppm_pipe --enable-decoder=mpeg4 --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac --enable-decoder=pcm_s16le --enable-decoder=ppm --enable-parser=h264 --enable-parser=hevc --enable-parser=aac --enable-parser=mpeg4video --enable-hwaccel=h264_videotoolbox --enable-hwaccel=hevc_videotoolbox --cc=clang
          make -j3
          echo "FF=$FF" >> "$GITHUB_ENV"
      - name: Native embedded presenter build and bounded core tests
        shell: bash
        run: |
          set -euo pipefail
          FLAGS=(-Xcc "-I$FF" -Xlinker "-L$FF/libavformat" -Xlinker "-L$FF/libavcodec" -Xlinker "-L$FF/libavutil" -Xlinker "-L$FF/libswscale" -Xlinker "-L$FF/libswresample" -Xlinker -framework -Xlinker VideoToolbox)
          swift build --build-tests "${FLAGS[@]}"
          swift test "${FLAGS[@]}"
          swift run "${FLAGS[@]}" subtitle-srt-tests
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
