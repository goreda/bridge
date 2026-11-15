# W-gdb-006 FFmpeg http/tcp configure-diff kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-006

```packet-json
{
  "packet_id": "W-gdb-006",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": ".github/workflows/engine-macos.yml",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "check.py <transcripts-dir> -> per-transcript PASS/FAIL receipt + machine-readable receipt",
    "types": "capability receipt { required: [protocols], perTranscript: PASS | 'FAIL missing: [...]' }",
    "ownership_lifetime": "python3 stdlib + shell only; no FFmpeg build; no network",
    "caller": "CI step consuming the receipt (engine-macos.yml lane)",
    "callee": "configure-diff kit: recorded configure line + protocol list vs required capability set -> typed PASS/FAIL receipt"
  },
  "test": {
    "command": "python3 kits/ffmpeg-configure-diff/check.py kits/ffmpeg-configure-diff/transcripts/",
    "expected": "exit 0; stdout per transcript 'PASS file+http+tcp' / 'FAIL file-only missing: http,tcp'; negative control (dropped flag) printed in the returned log",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/ffmpeg-configure-diff/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/ffmpeg-configure-diff/README.md",
        "block": "rf1"
      },
      {
        "path": "kits/ffmpeg-configure-diff/check.py",
        "block": "rf2"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/comma-form.txt",
        "block": "rf3"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/comment-lines.txt",
        "block": "rf4"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/disable-everything-ordering.txt",
        "block": "rf5"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/enable-all-unverifiable.txt",
        "block": "rf6"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/extra-protocols.txt",
        "block": "rf7"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/file+http+tcp.txt",
        "block": "rf8"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/file-only.txt",
        "block": "rf9"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/flags-and-list-agree.txt",
        "block": "rf10"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/flags-vs-list-mismatch.txt",
        "block": "rf11"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/raw-output-agree.txt",
        "block": "rf12"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/raw-output-mismatch.txt",
        "block": "rf13"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/reordered.txt",
        "block": "rf14"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/unknown-flag.txt",
        "block": "rf15"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/unterminated-quote.txt",
        "block": "rf16"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/workflow-pinned.txt",
        "block": "rf17"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/ffmpeg-configure-diff/check.py kits/ffmpeg-configure-diff/transcripts/",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:05:10.281399+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "PASS file+http+tcp",
    "inline_files": [
      {
        "path": "kits/ffmpeg-configure-diff/README.md",
        "block": "rf1",
        "sha256": "fa9a6412c8c76291e646cf5ed379b752ff86516b8250908cd417479551ff76cd"
      },
      {
        "path": "kits/ffmpeg-configure-diff/check.py",
        "block": "rf2",
        "sha256": "1aedededaf9799d7d5dd74c87410b75c2c1ec12312b67735eda2365f49207aa7"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/comma-form.txt",
        "block": "rf3",
        "sha256": "eb1a7dc853a95f655a412393e300231d158eda5b85c71f97c98513e315714836"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/comment-lines.txt",
        "block": "rf4",
        "sha256": "5dc743c8fe48577fa3570bc0bf9ed5385f19aed5414cd71710fedcf8635f697c"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/disable-everything-ordering.txt",
        "block": "rf5",
        "sha256": "3c2cb8cb19ce7e9939edaef634cde949a414d5abcb33f8eb5041351651a9674e"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/enable-all-unverifiable.txt",
        "block": "rf6",
        "sha256": "1973780d886f39c7b191ea90e332757b8012ea81746ed9752219810f27656351"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/extra-protocols.txt",
        "block": "rf7",
        "sha256": "3fac45a6ccb3c4d3e76e0a74d4d991405f5bed5c35e0d58c8c78f01ea585f592"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/file+http+tcp.txt",
        "block": "rf8",
        "sha256": "c7f45ad362e9c6a993aea5e554095ee5fa1fd5d59c6bdeb07e92dd4493f7ae73"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/file-only.txt",
        "block": "rf9",
        "sha256": "14e7fd42a0a3d955d1a5f8801d9db4873b08305ef7e63fe60cac89eb99bac591"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/flags-and-list-agree.txt",
        "block": "rf10",
        "sha256": "01d99a6b6fd58b659bc4ba172ce850e08b9352847bcfe998ceac62d93566db39"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/flags-vs-list-mismatch.txt",
        "block": "rf11",
        "sha256": "412300af2a1c53010dec7c8d9089f5f0902096a3b9b7161c9ff0134fa7bbc7fc"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/raw-output-agree.txt",
        "block": "rf12",
        "sha256": "3feab1c7fce24227818e92dd20314a3154104e3832dfe55cd1cd0399069b252a"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/raw-output-mismatch.txt",
        "block": "rf13",
        "sha256": "30698e5db6e70e29aa76e011b6f6a9c54b63ac2fe50bad4679468c02ecb079a7"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/reordered.txt",
        "block": "rf14",
        "sha256": "25deda4ea4c52db0df06a96bdec0f3a02651eec8063b243d87f63fcdf6f0fef9"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/unknown-flag.txt",
        "block": "rf15",
        "sha256": "2e19da278722f7b221f94e120580c116dadbbd9625050449ca886ef40bc620c8"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/unterminated-quote.txt",
        "block": "rf16",
        "sha256": "bc9c2a30527b8c44fa0b288d915be7c635333a44822aa6c7cad35a198a163014"
      },
      {
        "path": "kits/ffmpeg-configure-diff/transcripts/workflow-pinned.txt",
        "block": "rf17",
        "sha256": "dc4426e499377017d88ed82a292c27e1db4797352616d472923fc3663cffad82"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "fcc9bad4641e5d9e436d1b1ebd708a4326044cee4f617510b7c325231e31e760",
    "last_5_lines": [
      "    \"file\",",
      "    \"http\",",
      "    \"tcp\"",
      "  ]",
      "}"
    ],
    "receipt_sha256": "c30ba04dc8a64d1ce908a34d627ac64a3a32214e50d71b75cc4cea22999b98c1"
  }
}
```

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
```yaml id=source1
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

```json id=fixtures1
{"required":["file","http","tcp"],"transcripts":{"file+http+tcp":"--enable-protocol=file --enable-protocol=http --enable-protocol=tcp","file-only":"--enable-protocol=file"},"expect":{"file+http+tcp":"PASS","file-only":"FAIL missing: http,tcp"}}
```

```text id=rf1
# ffmpeg-configure-diff

Typed capability receipt for recorded FFmpeg configure lines. Stdlib Python 3 +
shell only; no FFmpeg build; no network. Bridges W-gdb-006.

## usage

    python3 kits/ffmpeg-configure-diff/check.py kits/ffmpeg-configure-diff/transcripts/
    python3 kits/ffmpeg-configure-diff/check.py DIR [--required file,http,tcp]
                                                     [--receipt receipt.json]
                                                     [--strict]

Each file in DIR is one transcript. A transcript holds configure flags plus,
optionally, a recorded protocol list. Rules:

- protocol flags: --enable-protocol=NAME[,NAME...] / --disable-protocol=NAME[,NAME...]
  (comma forms are split), --enable-protocols / --disable-protocols, in order.
- optional recorded protocol list. Preferred normalized form, one line:
  `protocols: file,http,tcp` (comma or space separated). Raw
  'Supported file protocols:' Input:/Output: blocks (ffmpeg -protocols style)
  are also parsed: required coverage is checked against the Input: set and
  flag/list agreement against Input+Output. Either way, disagreement with the
  flags FAILs as mismatch / list-missing.
- '#' starts a shell-style comment (full-line or inline); comments are never
  scored as flags.
- text shlex cannot tokenize (e.g. an unmatched quote) is a parse error and
  typed-FAILs; bad shell text never becomes a PASS.

A bare --enable-protocols / --enable-everything can never PASS unless a later
--disable-protocols / --disable-everything narrows it: extras cannot be
enumerated, so it FAILs as typed-unverifiable. Flags apply in order
(configure's sequential semantics), so '--enable-protocols
--disable-everything --enable-protocol=file,http,tcp' resolves to the explicit
list and PASSes. Non-protocol flags, including unknown ones, are ignored:
real configure lines carry dozens of them.

## output

One typed line per transcript, then a machine-readable JSON receipt:

    PASS file+http+tcp
    FAIL file-only missing: http,tcp
    {"required": ["file","http","tcp"], "perTranscript": {"file+http+tcp": "PASS", ...}}

receipt values follow the packet schema: PASS | 'FAIL missing: [...]',
extended with typed reasons: ' extra: [...]' (unexpected protocols, honouring
the packet's "nothing else unexpected" clause), ' unverifiable: [enable-all]',
' list-missing: [...]', ' mismatch: [...]', ' parse-error: [...]'. The
receipt document also carries an evidence block: configureFlags CHECKED,
compiledProtocolList NOT_RUN - the kit attests the requested configuration
only; full compiled capability proof is out of scope.

Exit status: 0 whenever receipts were produced (even with per-transcript
FAILs - the CI step consumes the typed receipt, not the exit code); 2 on
usage/IO errors; 1 under --strict when any transcript FAILs.

## transcripts shipped

- file+http+tcp.txt      exact match (packet fixture)            -> PASS
- file-only.txt          missing http,tcp (packet fixture)       -> FAIL missing: http,tcp
- workflow-pinned.txt    verbatim configure line from
                         .github/workflows/engine-macos.yml      -> FAIL missing: http,tcp
- reordered.txt          same set, different flag order          -> PASS
- extra-protocols.txt    adds https                              -> FAIL extra: https
- unknown-flag.txt       bogus non-protocol flag present         -> PASS (ignored)
- comma-form.txt         --enable-protocol=file,http,tcp          -> PASS
- comment-lines.txt      '# --enable-protocol=https' comment      -> PASS (comment ignored)
- flags-and-list-agree.txt  flags + matching recorded list        -> PASS
- enable-all-unverifiable.txt  bare --enable-protocols            -> FAIL unverifiable: enable-all
- flags-vs-list-mismatch.txt flags enable http,tcp; list=file only -> FAIL list-missing + mismatch
- raw-output-mismatch.txt flags file,http,tcp + raw Input/Output=file -> FAIL list-missing + mismatch
- raw-output-agree.txt   flags + raw block carrying file,http,tcp     -> PASS
- unterminated-quote.txt trailing unmatched quote                    -> FAIL parse-error
- disable-everything-ordering.txt enable-all then disable-everything -> PASS (sequential semantics)

```

```text id=rf2
#!/usr/bin/env python3
"""ffmpeg-configure-diff: typed capability receipt for recorded configure lines.

Reads a directory of transcripts and diffs each transcript's protocol evidence
against a required capability set (default: file,http,tcp). Prints one typed
receipt line per transcript plus a machine-readable JSON receipt.
python3 stdlib + shell only; no FFmpeg build; no network.

Transcript format (one file per transcript):
  - configure flags: any non-comment tokens; the kit extracts
    --enable-protocol=NAME[,NAME...] / --disable-protocol=NAME[,NAME...]
    (comma forms are split), --enable-protocols / --disable-protocols,
    --enable-everything / --disable-everything. Flags apply in order;
    --disable-everything clears earlier protocol state (configure's own
    sequential semantics), so '--enable-protocols --disable-everything
    --enable-protocol=...' resolves to the explicit list.
  - optional recorded protocol list, preferred normalized form, one line:
        protocols: file,http,tcp      (comma or space separated)
  - optional raw 'ffmpeg -protocols' style block:
        Supported file protocols:
        Input:
         file
         http
        Output:
         file
    Required coverage for the raw form is checked against the Input: set
    (read capability); the flag/list agreement check uses Input+Output.
  A recorded list, in either form, is cross-checked against the configure
  flags; disagreement FAILs.
  - '#' starts a shell-style comment (full-line or inline); comment text is
    never scored as flags.
  - text shlex cannot tokenize (e.g. an unmatched quote) is a parse error and
    typed-FAILs; bad shell text never becomes a PASS.

Receipt semantics (per transcript):
  PASS
  FAIL missing: a,b              required protocols absent from the flags
  FAIL extra: x                  enabled protocols beyond the required set
  FAIL unverifiable: enable-all  bare --enable-protocols / --enable-everything
                                 with no later bulk disable; extras cannot be
                                 enumerated, so PASS is impossible
  FAIL list-missing: a,b         required protocols absent from the recorded
                                 protocol list (Input: set for raw blocks)
  FAIL mismatch: ...             configure flags and recorded list disagree
  FAIL parse-error: msg          transcript could not be tokenized
Non-protocol flags (decoders, demuxers, --cc, unknown switches) are ignored:
the kit diffs protocol evidence only.

Evidence scope: receipts attest configure-flag configuration, cross-checked
against recorded protocol lists where supplied (normalized 'protocols:' lines
preferred; raw 'Supported file protocols:' blocks parsed). Full compiled
capability proof is NOT_RUN.

Exit status: 0 whenever transcripts were read and receipts produced, even on
per-transcript FAIL (the typed receipt is the contract; a CI step consumes it).
2 on usage/IO errors. --strict flips any-FAIL to exit 1 if a caller prefers it.
"""

import argparse
import json
import os
import re
import shlex
import sys

DEFAULT_REQUIRED = ["file", "http", "tcp"]
RAW_HEADER_RE = re.compile(r"^supported\s+.*protocols:$", re.IGNORECASE)


def split_names(value):
    return [n.strip().lower() for n in value.split(",") if n.strip()]


def parse_raw_protocols_block(lines, i):
    """Parse a 'Supported file protocols:' block starting after the header.
    Returns (raw_list, next_i): raw_list = {"input": [...], "output": [...]};
    sections are indented name lines under Input: / Output: headers."""
    inp, out = [], []
    section = None
    i += 1  # past header
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        low = s.lower().rstrip(":")
        if not s:
            break
        if low == "input":
            section = "input"
        elif low == "output":
            section = "output"
        elif section and line[:1] in (" ", "\t"):
            target = inp if section == "input" else out
            target.extend(n.lower() for n in s.split() if n)
        else:
            break  # unindented non-section line ends the block
        i += 1
    return {"input": sorted(set(inp)), "output": sorted(set(out))}, i


def parse_transcript(text):
    """Split a transcript into (tokens, protocol_list, raw_list, parse_errors).

    tokens        configure-flag tokens (comments stripped)
    protocol_list normalized 'protocols:' line, or None
    raw_list      parsed 'Supported file protocols:' block, or None
    parse_errors  shlex failures; any entry forces a typed FAIL
    """
    tokens = []
    protocol_list = None
    raw_list = None
    parse_errors = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        if RAW_HEADER_RE.match(raw.strip()):
            raw_list, i = parse_raw_protocols_block(lines, i)
            continue
        try:
            toks = shlex.split(raw, comments=True)
        except ValueError as e:
            parse_errors.append(str(e))
            i += 1
            continue
        if toks:
            head = toks[0].lower()
            if head in ("protocols:", "protocols"):
                names = []
                for t in toks[1:]:
                    names.extend(split_names(t))
                protocol_list = names
            else:
                tokens.extend(toks)
        i += 1
    return tokens, protocol_list, raw_list, parse_errors


def enabled_protocols(tokens):
    """Effective enabled-protocol set from configure flags, in order.
    Returns (set, enable_all). --enable-protocols / --enable-everything set
    enable_all; --disable-protocols / --disable-everything clear both the set
    and enable_all (sequential configure semantics)."""
    enabled = set()
    enable_all = False
    for tok in tokens:
        if tok in ("--enable-protocols", "--enable-everything"):
            enable_all = True
        elif tok in ("--disable-protocols", "--disable-everything"):
            enabled.clear()
            enable_all = False
        elif tok.startswith("--enable-protocol="):
            enabled.update(split_names(tok.split("=", 1)[1]))
        elif tok.startswith("--disable-protocol="):
            for name in split_names(tok.split("=", 1)[1]):
                enabled.discard(name)
    return enabled, enable_all


def cross_check_list(required, found, listed, reasons, receipt_parts):
    """Diff a recorded protocol list against the required set and the flags."""
    req = set(required)
    plist = set(listed)
    list_missing = sorted(req - plist)
    flags_not_in_list = sorted(found - plist)
    list_not_in_flags = sorted(plist - found)
    if list_missing:
        reasons.append("list-missing: " + ",".join(list_missing))
        receipt_parts.append("list-missing: [" + ",".join(list_missing) + "]")
    if flags_not_in_list or list_not_in_flags:
        frag = []
        if flags_not_in_list:
            frag.append("flags-not-in-list: " + ",".join(flags_not_in_list))
        if list_not_in_flags:
            frag.append("list-not-in-flags: " + ",".join(list_not_in_flags))
        reasons.append("mismatch: " + " ".join(frag))
        receipt_parts.append("mismatch: [" + " ".join(frag) + "]")


def check_transcript(tokens, protocol_list, raw_list, parse_errors, required):
    """Return (status, detail, receipt). receipt follows the packet schema
    PASS | 'FAIL missing: [...]', extended with the typed FAIL reasons above."""
    if parse_errors:
        msg = "; ".join(parse_errors)
        return ("FAIL", f"parse-error: {msg}", f"FAIL parse-error: [{msg}]")

    req = set(required)
    found, enable_all = enabled_protocols(tokens)

    if enable_all:
        return ("FAIL",
                "unverifiable: enable-all (extras cannot be enumerated)",
                "FAIL unverifiable: [enable-all]")

    reasons = []
    receipt_parts = []

    missing = sorted(req - found)
    extra = sorted(found - req)
    if missing:
        reasons.append("missing: " + ",".join(missing))
        receipt_parts.append("missing: [" + ",".join(missing) + "]")
    if extra:
        reasons.append("extra: " + ",".join(extra))
        receipt_parts.append("extra: [" + ",".join(extra) + "]")

    if protocol_list is not None:
        cross_check_list(required, found, protocol_list, reasons, receipt_parts)
    if raw_list is not None:
        # required coverage is read capability: the Input: set
        in_missing = sorted(req - set(raw_list["input"]))
        if in_missing:
            reasons.append("list-missing: " + ",".join(in_missing))
            receipt_parts.append("list-missing: [" + ",".join(in_missing) + "]")
        # flag/list agreement is checked against the full supported set
        union = set(raw_list["input"]) | set(raw_list["output"])
        flags_not_in_list = sorted(found - union)
        list_not_in_flags = sorted(union - found)
        if flags_not_in_list or list_not_in_flags:
            frag = []
            if flags_not_in_list:
                frag.append("flags-not-in-list: " + ",".join(flags_not_in_list))
            if list_not_in_flags:
                frag.append("list-not-in-flags: " + ",".join(list_not_in_flags))
            reasons.append("mismatch: " + " ".join(frag))
            receipt_parts.append("mismatch: [" + " ".join(frag) + "]")

    if not reasons:
        return "PASS", "", "PASS"
    return "FAIL", " ".join(reasons), "FAIL " + " ".join(receipt_parts)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("transcripts_dir", help="directory of transcripts")
    p.add_argument("--required", default=",".join(DEFAULT_REQUIRED),
                   help="comma-separated required protocol set (default: file,http,tcp)")
    p.add_argument("--receipt", metavar="PATH",
                   help="also write the machine-readable JSON receipt to PATH")
    p.add_argument("--strict", action="store_true",
                   help="exit 1 if any transcript FAILs (default: always 0 on success)")
    args = p.parse_args(argv)

    required = [s.strip().lower() for s in args.required.split(",") if s.strip()]
    if not required:
        print("error: empty required set", file=sys.stderr)
        return 2

    try:
        names = sorted(os.listdir(args.transcripts_dir))
    except OSError as e:
        print(f"error: cannot read transcripts dir: {e}", file=sys.stderr)
        return 2
    files = [n for n in names
             if os.path.isfile(os.path.join(args.transcripts_dir, n)) and n != "receipt.json"]
    if not files:
        print(f"error: no transcripts in {args.transcripts_dir}", file=sys.stderr)
        return 2

    per_transcript = {}
    details = {}
    any_fail = False
    for fname in files:
        path = os.path.join(args.transcripts_dir, fname)
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        name = os.path.splitext(fname)[0]
        tokens, protocol_list, raw_list, parse_errors = parse_transcript(text)
        status, detail, receipt = check_transcript(
            tokens, protocol_list, raw_list, parse_errors, required)
        if status != "PASS":
            any_fail = True
        per_transcript[name] = receipt

        evidence = "configure-flags"
        if parse_errors:
            evidence = "parse-error"
        elif protocol_list is not None:
            evidence = "configure-flags+recorded-protocol-list"
        elif raw_list is not None:
            evidence = "configure-flags+ffmpeg-protocols-output"
        found, enable_all = enabled_protocols(tokens) if not parse_errors else (None, False)
        details[name] = {
            "configureFlags": ("enable-all" if enable_all else sorted(found))
                              if found is not None else None,
            "protocolList": sorted(set(protocol_list)) if protocol_list is not None else None,
            "rawProtocols": raw_list,
            "parseErrors": parse_errors or None,
            "evidence": evidence,
        }
        print(f"{status} {name}" + (f" {detail}" if detail else ""))

    receipt_doc = {
        "required": required,
        "perTranscript": per_transcript,
        "evidence": {
            "scope": "configure-flag configuration; recorded protocol lists "
                     "cross-checked where supplied (normalized 'protocols:' "
                     "lines preferred, raw 'Supported file protocols:' "
                     "Input/Output blocks parsed)",
            "configureFlags": "CHECKED",
            "compiledProtocolList": "NOT_RUN",
        },
        "details": details,
    }
    print(json.dumps(receipt_doc, indent=2, sort_keys=True))
    if args.receipt:
        with open(args.receipt, "w", encoding="utf-8") as f:
            json.dump(receipt_doc, f, indent=2, sort_keys=True)
            f.write("\n")

    return 1 if (args.strict and any_fail) else 0


if __name__ == "__main__":
    sys.exit(main())

```

```text id=rf3
--enable-protocol=file,http,tcp

```

```text id=rf4
# recorded configure line; the https line below was tried and reverted
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp
# --enable-protocol=https

```

```text id=rf5
--enable-protocols --disable-everything --enable-protocol=file --enable-protocol=http --enable-protocol=tcp

```

```text id=rf6
--enable-protocols --enable-protocol=file --enable-protocol=http --enable-protocol=tcp

```

```text id=rf7
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp --enable-protocol=https

```

```text id=rf8
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp

```

```text id=rf9
--enable-protocol=file

```

```text id=rf10
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp
protocols: file,http,tcp

```

```text id=rf11
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp
protocols: file

```

```text id=rf12
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp
Supported file protocols:
Input:
 file
 http
 tcp
Output:
 file
 http

```

```text id=rf13
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp
Supported file protocols:
Input:
 file
Output:
 file

```

```text id=rf14
--enable-protocol=tcp --enable-protocol=file --enable-protocol=http

```

```text id=rf15
--disable-programs --enable-protocol=file --enable-frobnicate --enable-protocol=http --cc=clang --enable-protocol=tcp

```

```text id=rf16
--enable-protocol=file --enable-protocol=http --enable-protocol=tcp --cc='clang

```

```text id=rf17
./configure --disable-programs --disable-doc --disable-everything --disable-avfilter --disable-avdevice --disable-x86asm --disable-asm --disable-debug --disable-bzlib --disable-lzma --disable-iconv --disable-securetransport --disable-audiotoolbox --disable-coreimage --disable-appkit --disable-avfoundation --disable-metal --enable-zlib --enable-protocol=file --enable-demuxer=mov --enable-demuxer=matroska --enable-demuxer=wav --enable-demuxer=image_ppm_pipe --enable-decoder=mpeg4 --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac --enable-decoder=pcm_s16le --enable-decoder=ppm --enable-parser=h264 --enable-parser=hevc --enable-parser=aac --enable-parser=mpeg4video --enable-hwaccel=h264_videotoolbox --enable-hwaccel=hevc_videotoolbox --cc=clang

```

```text id=actual_run_log
PASS comma-form
PASS comment-lines
PASS disable-everything-ordering
FAIL enable-all-unverifiable unverifiable: enable-all (extras cannot be enumerated)
FAIL extra-protocols extra: https
PASS file+http+tcp
FAIL file-only missing: http,tcp
PASS flags-and-list-agree
FAIL flags-vs-list-mismatch list-missing: http,tcp mismatch: flags-not-in-list: http,tcp
PASS raw-output-agree
FAIL raw-output-mismatch list-missing: http,tcp mismatch: flags-not-in-list: http,tcp
PASS reordered
PASS unknown-flag
FAIL unterminated-quote parse-error: No closing quotation
FAIL workflow-pinned missing: http,tcp
{
  "details": {
    "comma-form": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "comment-lines": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "disable-everything-ordering": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "enable-all-unverifiable": {
      "configureFlags": "enable-all",
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "extra-protocols": {
      "configureFlags": [
        "file",
        "http",
        "https",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "file+http+tcp": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "file-only": {
      "configureFlags": [
        "file"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "flags-and-list-agree": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags+recorded-protocol-list",
      "parseErrors": null,
      "protocolList": [
        "file",
        "http",
        "tcp"
      ],
      "rawProtocols": null
    },
    "flags-vs-list-mismatch": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags+recorded-protocol-list",
      "parseErrors": null,
      "protocolList": [
        "file"
      ],
      "rawProtocols": null
    },
    "raw-output-agree": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags+ffmpeg-protocols-output",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": {
        "input": [
          "file",
          "http",
          "tcp"
        ],
        "output": [
          "file",
          "http"
        ]
      }
    },
    "raw-output-mismatch": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags+ffmpeg-protocols-output",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": {
        "input": [
          "file"
        ],
        "output": [
          "file"
        ]
      }
    },
    "reordered": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "unknown-flag": {
      "configureFlags": [
        "file",
        "http",
        "tcp"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    },
    "unterminated-quote": {
      "configureFlags": null,
      "evidence": "parse-error",
      "parseErrors": [
        "No closing quotation"
      ],
      "protocolList": null,
      "rawProtocols": null
    },
    "workflow-pinned": {
      "configureFlags": [
        "file"
      ],
      "evidence": "configure-flags",
      "parseErrors": null,
      "protocolList": null,
      "rawProtocols": null
    }
  },
  "evidence": {
    "compiledProtocolList": "NOT_RUN",
    "configureFlags": "CHECKED",
    "scope": "configure-flag configuration; recorded protocol lists cross-checked where supplied (normalized 'protocols:' lines preferred, raw 'Supported file protocols:' Input/Output blocks parsed)"
  },
  "perTranscript": {
    "comma-form": "PASS",
    "comment-lines": "PASS",
    "disable-everything-ordering": "PASS",
    "enable-all-unverifiable": "FAIL unverifiable: [enable-all]",
    "extra-protocols": "FAIL extra: [https]",
    "file+http+tcp": "PASS",
    "file-only": "FAIL missing: [http,tcp]",
    "flags-and-list-agree": "PASS",
    "flags-vs-list-mismatch": "FAIL list-missing: [http,tcp] mismatch: [flags-not-in-list: http,tcp]",
    "raw-output-agree": "PASS",
    "raw-output-mismatch": "FAIL list-missing: [http,tcp] mismatch: [flags-not-in-list: http,tcp]",
    "reordered": "PASS",
    "unknown-flag": "PASS",
    "unterminated-quote": "FAIL parse-error: [No closing quotation]",
    "workflow-pinned": "FAIL missing: [http,tcp]"
  },
  "required": [
    "file",
    "http",
    "tcp"
  ]
}
```
