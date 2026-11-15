#!/usr/bin/env python3
"""check.py - W-gdb-055 bounded executable gate, rev3.

Core failing verify = the lab's own STRICT command built against an EXACT
FFmpeg 7.1 build supplied by the runner:

    python3 check.py --prefix /path/to/ffinstall        (or FFMPEG_PREFIX=...)

Checks:
1. carrier integrity (CARRIER.sha256)
2. fixture pin: f_negstart.mkv must match fixtures/fixtures.sha256
3. STRICT 7.1 verify (requires --prefix):
   a. exact-version probe: the build must be FFmpeg 7.1.x, i.e.
      libavformat 61.7.x, libavcodec 61.19.x, libavutil 59.39.x
      (per SEVEN_ONE_BUILD.txt); any other version FAILs this check.
   b. seek_ref_v4.c built against that prefix, then the lab's STRICT
      command: `verify -1023 -500 -5000 500` (STRICT expects MATCH at all
      targets, exit 0).
      PASS = STRICT fails with the documented signature: exit 3, audio
      MISMATCH at -1023/-500/-5000, audio MATCH at +500, video MATCH
      everywhere (the returned failing test reproduces).
      FAIL = STRICT exits 0 (not reproduced) or fails differently.
4. AUXILIARY 8.0.1 log (non-gating, only if the integrator's 8.0.1 static
   tree exists at $HOME/ffbuild/FFmpeg-894da5ca...): same verify, labeled
   8.0.1; it never substitutes for the 7.1 leg.

Exit codes: 0 = checks 1-3 PASS (check 4 informational); 77 = --prefix not
given, strict 7.1 leg NOT RUN (checks 1,2,4 only); 1 = a check failed.
"""
import hashlib
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
FF801 = pathlib.Path.home() / "ffbuild" / "FFmpeg-894da5ca7d742e4429ffb2af534fcda0103ef593"

VERSION_PROBE = r"""
#include <stdio.h>
#include <libavformat/version.h>
#include <libavcodec/version.h>
#include <libavutil/version.h>
int main(void) {
    printf("header libavformat %d.%d.%d libavcodec %d.%d.%d libavutil %d.%d.%d\n",
           LIBAVFORMAT_VERSION_MAJOR, LIBAVFORMAT_VERSION_MINOR, LIBAVFORMAT_VERSION_MICRO,
           LIBAVCODEC_VERSION_MAJOR, LIBAVCODEC_VERSION_MINOR, LIBAVCODEC_VERSION_MICRO,
           LIBAVUTIL_VERSION_MAJOR, LIBAVUTIL_VERSION_MINOR, LIBAVUTIL_VERSION_MICRO);
    /* exact FFmpeg 7.1.x per SEVEN_ONE_BUILD.txt */
    if (LIBAVFORMAT_VERSION_MAJOR == 61 && LIBAVFORMAT_VERSION_MINOR == 7
        && LIBAVCODEC_VERSION_MAJOR == 61 && LIBAVCODEC_VERSION_MINOR == 19
        && LIBAVUTIL_VERSION_MAJOR == 59 && LIBAVUTIL_VERSION_MINOR == 39)
        return 0;
    return 2;
}
"""

STRICT_ARGS = ["verify", "-1023", "-500", "-5000", "500"]


def run(cmd, timeout):
    return subprocess.run(cmd, cwd=ROOT, timeout=timeout, capture_output=True, text=True)


def check_carrier():
    ok = True
    for line in (ROOT / "CARRIER.sha256").read_text().splitlines():
        want, rel = line.split(None, 1)
        got = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        if got != want:
            print(f"FAIL carrier mismatch: {rel}")
            ok = False
    if ok:
        print("PASS carrier-integrity")
    return ok


def check_fixture_pin():
    want = None
    for line in (ROOT / "fixtures" / "fixtures.sha256").read_text().splitlines():
        h, name = line.split(None, 1)
        if name.strip() == "f_negstart.mkv":
            want = h
    got = hashlib.sha256((ROOT / "fixtures" / "f_negstart.mkv").read_bytes()).hexdigest()
    if want and got == want:
        print("PASS fixture-pin (f_negstart.mkv sha256 matches)")
        return True
    print(f"FAIL fixture-pin: want {want} got {got}")
    return False


def build_against_prefix(prefix, out_name, src):
    prefix = pathlib.Path(prefix)
    rpath = ["-Wl,-rpath," + str(prefix / "lib")]
    cmd = (["gcc", "-std=gnu11", "-O2", "-Wall", "-Wextra",
            "-I" + str(prefix / "include"), "-o", str(ROOT / out_name), src,
            "-L" + str(prefix / "lib"), "-lavformat", "-lavcodec", "-lavutil",
            "-lm", "-lpthread", "-lz"] + rpath)
    return run(cmd, timeout=300)


def parse_verify_output(out):
    audio = dict(re.findall(r"=== target (-?\d+) ms.*?\n(?:.*\n)*?\[audio\] seek-vs-seqref: (MATCH|MISMATCH)", out))
    video_bad = re.search(r"\[video\] seek-vs-seqref: MISMATCH", out)
    return audio, (video_bad is None)


def signature_matches(rc, out):
    audio, video_ok = parse_verify_output(out)
    expect = {"-1023": "MISMATCH", "-500": "MISMATCH", "-5000": "MISMATCH", "500": "MATCH"}
    return rc == 3 and audio == expect and video_ok


def check_strict_71(prefix):
    if prefix is None:
        print("SKIP strict-7.1: no --prefix/FFMPEG_PREFIX given; strict leg NOT RUN (exit 77 overall)")
        return None
    probe_src = ROOT / ".version_probe.c"
    probe_src.write_text(VERSION_PROBE)
    b = build_against_prefix(prefix, ".version_probe", str(probe_src))
    if b.returncode != 0:
        print("FAIL strict-7.1: version probe build failed:", b.stderr[-400:])
        return False
    v = run([str(ROOT / ".version_probe")], timeout=30)
    print("version probe:", v.stdout.strip() or v.stderr.strip())
    if v.returncode != 0:
        print("FAIL strict-7.1: prefix is not an exact FFmpeg 7.1 build "
              "(need libavformat 61.7.x / libavcodec 61.19.x / libavutil 59.39.x)")
        return False
    b = build_against_prefix(prefix, "seek_ref_71", "seek_ref_v4.c")
    if b.returncode != 0:
        print("FAIL strict-7.1: seek_ref_v4.c build against 7.1 failed:", b.stderr[-400:])
        return False
    r = run([str(ROOT / "seek_ref_71"), "fixtures/f_negstart.mkv"] + STRICT_ARGS, timeout=120)
    print("--- lab STRICT command output (7.1) ---")
    print(r.stdout.strip())
    print("--- rc:", r.returncode, "---")
    if signature_matches(r.returncode, r.stdout):
        print("PASS strict-7.1: lab STRICT command FAILS on 7.1 with the documented signature "
              "(exit 3; audio MISMATCH -1023/-500/-5000, MATCH +500, video MATCH) - failing test reproduced")
        return True
    if r.returncode == 0:
        print("FAIL strict-7.1: STRICT exited 0 on 7.1 - documented failure NOT reproduced")
        return False
    print(f"FAIL strict-7.1: STRICT failed with a DIFFERENT signature (rc={r.returncode})")
    return False


def check_aux_801():
    if not FF801.is_dir():
        print("AUX 8.0.1: integrator static tree absent here; auxiliary leg not run (non-gating)")
        return True
    b = run(["gcc", "-std=gnu11", "-O2", "-Wall", "-Wextra", "-I" + str(FF801),
             "-o", str(ROOT / "seek_ref_801"), "seek_ref_v4.c",
             str(FF801 / "libavformat" / "libavformat.a"),
             str(FF801 / "libavcodec" / "libavcodec.a"),
             str(FF801 / "libavutil" / "libavutil.a"),
             "-lm", "-lpthread", "-lz"], timeout=300)
    if b.returncode != 0:
        print("AUX 8.0.1: build failed (non-gating):", b.stderr[-400:])
        return True
    r = run([str(ROOT / "seek_ref_801"), "fixtures/f_negstart.mkv"] + STRICT_ARGS, timeout=120)
    print("--- AUXILIARY 8.0.1 log (NOT the 7.1 measurement, non-gating) ---")
    print(r.stdout.strip())
    print("--- aux rc:", r.returncode, "; signature match:", signature_matches(r.returncode, r.stdout), "---")
    return True


def check_71_command():
    txt = (ROOT / "SEVEN_ONE_BUILD.txt").read_text()
    if ("ffmpeg-7.1.tar.xz" in txt
            and "40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6" in txt
            and "--enable-demuxer=matroska" in txt):
        print("PASS 7.1-build-command-pinned (SEVEN_ONE_BUILD.txt)")
        return True
    print("FAIL 7.1-build-command-pinned")
    return False


def main():
    prefix = None
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--prefix" and i + 1 < len(args):
            prefix = args[i + 1]
        elif a.startswith("--prefix="):
            prefix = a.split("=", 1)[1]
    prefix = prefix or os.environ.get("FFMPEG_PREFIX")

    results = [check_carrier(), check_fixture_pin(), check_71_command(), check_aux_801()]
    strict = check_strict_71(prefix)
    if strict is None:
        print("n03-negstart-mismatch rev3: strict 7.1 leg NOT RUN (rerun with --prefix <7.1 install>); base checks", 
              "PASS" if all(results) else "FAIL")
        return 77
    results.append(strict)
    passed = sum(results)
    print(f"n03-negstart-mismatch rev3: {passed}/5 checks PASS")
    return 0 if passed == 5 else 1


if __name__ == "__main__":
    sys.exit(main())
