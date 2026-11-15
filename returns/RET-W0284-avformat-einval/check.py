#!/usr/bin/env python3
"""W-0284 avformat driver: pinned-7.1 integration rerun + EINVAL root-cause verify,
with dual-version equality asserted in code (7.1 core vs 8.0.1 aux).

Checks (CORE prefix must be an EXACT FFmpeg 7.1 build - all three libraries
probed at runtime AND compile time: avformat 61.7.x, avcodec 61.19.x,
avutil 59.39.x; build contract in BUILD_CONTRACT.txt):
  A) hlsctl (carrier, sha256 in fixtures1) vs unreachable origin on a VALID
     port -> "OPEN_FAIL Connection refused" (typed).
  B) hlsctl vs an out-of-range port URI (>65535) -> "OPEN_FAIL Invalid argument"
     with libav log "Port missing in uri": the observed EINVAL class is a URI
     parse failure, NOT a 7.1/8.0.1 drift.
  C) live control: driver vs carrier server.py (flaky profile, truncation
     armed) -> exit 0, "choice bw=1500000", "gaps=1" (truncation survived via
     reconnect path, matching the lab's run3 T8).
With --aux-prefix (8.0.1 build): the SAME A/B/C suite runs against the aux
binary and the normalized outcomes must EQUAL the core outcomes, or exit 3.

Usage: python3 check.py --prefix /path/to/ff71 --aux-prefix /path/to/ff801
  prefixes accept an install prefix (include/, lib/) or an in-tree build dir.
Exit: 0 all checks behaved as pinned; 1 setup error; 3 behavior drift.
"""
import argparse
import os
import socket
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HLSCTL = os.path.join(HERE, "hlsctl.c")
SERVER = os.path.join(HERE, "server.py")

PROBE_C = r'''
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <stdio.h>
#define PV(name, rt, maj, min, mic) printf("%s %d.%d.%d (headers %d.%d.%d)\n", name, \
    AV_VERSION_MAJOR(rt), AV_VERSION_MINOR(rt), AV_VERSION_MICRO(rt), maj, min, mic)
int main(void) {
    PV("libavformat", avformat_version(), LIBAVFORMAT_VERSION_MAJOR, LIBAVFORMAT_VERSION_MINOR, LIBAVFORMAT_VERSION_MICRO);
    PV("libavcodec", avcodec_version(), LIBAVCODEC_VERSION_MAJOR, LIBAVCODEC_VERSION_MINOR, LIBAVCODEC_VERSION_MICRO);
    PV("libavutil", avutil_version(), LIBAVUTIL_VERSION_MAJOR, LIBAVUTIL_VERSION_MINOR, LIBAVUTIL_VERSION_MICRO);
    return 0;
}
'''

EXPECT_CORE = {"libavformat": (61, 7, 100), "libavcodec": (61, 19, 100), "libavutil": (59, 39, 100)}
# measured on the pinned 894da5ca7d742e4429ffb2af534fcda0103ef593 build
EXPECT_AUX = {"libavformat": (62, 3, 100), "libavcodec": (62, 11, 100), "libavutil": (60, 8, 100)}


def dirs(prefix):
    if os.path.isdir(os.path.join(prefix, "include")):
        return ["-I" + os.path.join(prefix, "include")], ["-L" + os.path.join(prefix, "lib")]
    if os.path.isdir(os.path.join(prefix, "libavformat")):
        return (["-I" + prefix],
                ["-L" + os.path.join(prefix, d) for d in
                 ("libavformat", "libavcodec", "libswresample", "libavutil")])
    raise SystemExit("prefix has neither include/ nor libavformat/: " + prefix)


def build(src, out, prefix):
    inc, libs = dirs(prefix)
    subprocess.run(["gcc", "-o", out] + inc + [src] + libs +
                   ["-lavformat", "-lavcodec", "-lswresample", "-lavutil",
                    "-lm", "-lpthread", "-lz"], check=True)


def probe_versions(prefix, tmp):
    src = os.path.join(tmp, "vprobe.c")
    open(src, "w").write(PROBE_C)
    out = os.path.join(tmp, "vprobe")
    build(src, out, prefix)
    res = {}
    for line in subprocess.run([out], capture_output=True, text=True, check=True).stdout.splitlines():
        # 'libavformat 61.7.100 (headers 61.7.100)'
        parts = line.replace("(", "").replace(")", "").split()
        runtime = tuple(int(x) for x in parts[1].split("."))
        headers = tuple(int(x) for x in parts[3].split("."))
        if runtime != headers:
            raise SystemExit("header/runtime version mismatch for %s: %s vs %s"
                             % (parts[0], headers, runtime))
        res[parts[0]] = runtime
    return res


def run(binary, url, pkts="50", timeout=90):
    p = subprocess.run([binary, url, "1500000", "0", "-3", pkts],
                       capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout + p.stderr


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def suite(binary, tag):
    """Returns normalized outcomes for A/B/C; raises SystemExit on setup errors."""
    out = {}
    port = free_port()
    rcA, outA = run(binary, f"http://127.0.0.1:{port}/vod/master.m3u8", pkts="1", timeout=60)
    out["A"] = (rcA, "OPEN_FAIL Connection refused" in outA)
    print("%s A (valid refused): rc=%d typed-refusal=%s" % (tag, rcA, out["A"][1]))
    rcB, outB = run(binary, "http://127.0.0.1:70000/vod/master.m3u8", pkts="1", timeout=60)
    out["B"] = (rcB, "OPEN_FAIL Invalid argument" in outB, "Port missing in uri" in outB)
    print("%s B (port>65535): rc=%d einval=%s port-missing-log=%s" % ((tag,) + out["B"]))
    port2 = free_port()
    srv = subprocess.Popen([sys.executable, SERVER, str(port2)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        import time; time.sleep(0.8)
        rcC, outC = run(binary, f"http://127.0.0.1:{port2}/flaky/master.m3u8", pkts="5000")
        tail = [l for l in outC.splitlines() if l.startswith(("choice", "END"))]
        out["C"] = (rcC,
                    any(l.startswith("choice bw=1500000") for l in tail),
                    any("gaps=1" in l for l in tail))
        print("%s C (flaky origin): rc=%d choice=%s gap-survived=%s" % ((tag,) + out["C"]))
    finally:
        srv.kill()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--aux-prefix")
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="einval-repro-")

    vers = probe_versions(a.prefix, tmp)
    print("core versions:", vers)
    for lib, want in EXPECT_CORE.items():
        if vers.get(lib) != want:
            raise SystemExit("core prefix is not an exact 7.1 build: %s is %s, want %s"
                             % (lib, vers.get(lib), want))

    orig = os.path.join(tmp, "hlsctl")
    build(HLSCTL, orig, a.prefix)
    core = suite(orig, "[7.1]")

    expect = {"A": (1, True), "B": (1, True, True), "C": (0, True, True)}
    fails = ["core %s: got %s want %s" % (k, core[k], expect[k]) for k in expect if core[k] != expect[k]]

    if a.aux_prefix:
        avers = probe_versions(a.aux_prefix, tmp)
        print("aux versions:", avers)
        for lib, want in EXPECT_AUX.items():
            if avers.get(lib) != want:
                raise SystemExit("aux prefix is not the pinned 8.0.1 build: %s is %s, want %s"
                                 % (lib, avers.get(lib), want))
        if avers == vers:
            raise SystemExit("aux prefix equals core prefix (same 7.1 tree): aux must be 8.0.1 - REJECTED")
        aux = os.path.join(tmp, "hlsctl_aux")
        build(HLSCTL, aux, a.aux_prefix)
        auxr = suite(aux, "[aux]")
        for k in expect:
            if auxr[k] != expect[k]:
                fails.append("aux %s: got %s want %s" % (k, auxr[k], expect[k]))
        if auxr != core:
            fails.append("core/aux outcome mismatch: %s vs %s" % (core, auxr))
        else:
            print("core==aux: dual-version outcomes EQUAL")

    if fails:
        for f in fails:
            print("DRIFT:", f)
        return 3
    print("w0284-rerun: A typed-refusal + B EINVAL-root-caused + C flaky-control ALL AS PINNED"
          + (" (7.1 core == 8.0.1 aux)" if a.aux_prefix else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
