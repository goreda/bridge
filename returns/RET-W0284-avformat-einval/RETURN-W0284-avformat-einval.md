# RETURN W-0284 avformat EINVAL: root-caused + pinned 7.1 rerun evidence

state: return
solver lab: 1nstinct (W-0284 author)
writer: gdb integrator
id: RET-W0284-avformat-einval

```packet-json
{
 "packet_id": "RET-W0284-avformat-einval",
 "writer": "gdb",
 "code_owner": "gdb integrator",
 "kind": "return-with-evidence",
 "product_repo": "goreda/gorav",
 "product_sha": "0388b972f6b48729c47610adc86bc471000479ef",
 "touched_files": [{"path": "hlsctl.c", "excerpt_block": "source1"}],
 "subject": "avformat driver EINVAL observation from integration; pin-drift rerun (8.0.1 -> pinned 7.1) for the W-0284 driver",
 "carrier_files": [
  {"path": "hlsctl.c", "role": "exact carrier pin of the lab driver (pkg3/avformat_driver/hlsctl.c)"},
  {"path": "server.py", "role": "exact carrier pin of the synthetic origin"},
  {"path": "media/", "role": "generated media fixtures (28 files, synthetic lavfi testsrc2/sine)"},
  {"path": "BUILD_CONTRACT.txt", "role": "exact build contract used for both builds (source pins, configure command, component list)"},
  {"path": "check.py", "role": "the executable verify"}
 ],
 "interface": {
  "signatures": "hlsctl URL bw_bps max_height live_start_index max_packets [switch_after switch_bw] -> exit code 0|1|2|3 with stdout protocol (variant/choice/GAP_SEEN/DISCONTINUITY_SEEN/END lines)",
  "types": "bandwidth Int64 bps; height Int px; packet/segment counts Int; error surface via av_err2str strings ('Connection refused' typed vs 'Invalid argument' for URI/argument failures)",
  "ownership_lifetime": "driver owns its AVFormatContext per run; no state crosses runs; origin is a local synthetic fixture, no external lifetime",
  "caller": "the consuming HLS integration seam on the product branch (future kit)",
  "callee": "the W-0284 lab driver behind avformat (hlsctl.c carrier pin)"
 },
 "test": {
  "command": "python3 check.py --prefix /path/to/exact-7.1-build --aux-prefix /path/to/8.0.1-build",
  "expected": "exit 0; probes avformat+avcodec+avutil runtime AND header equality on both prefixes; core gated to exact 61.7.100/61.19.100/59.39.100, aux gated to exact 62.3.100/62.11.100/60.8.100 (measured on the pinned 894da5ca build); aux==core is REJECTED (exit 1); A/B/C run against BOTH builds and normalized outcomes must be EQUAL ('core==aux: dual-version outcomes EQUAL'); drift -> exit 3 with DRIFT lines",
  "fixture_block": "fixtures1"
 },
 "five_gates": "no credentials, no keys, no user data, no licensed bytes (synthetic generated media only), no private endpoints (loopback only)",
 "target": {"branch": "ohal/gorav", "paths": ["kits/"], "return_form": "full-files"}
}
```

## what was asked
arch-196q item 2: the avformat EINVAL gets one reproducer packet to the owning
lab with the 7.1 build command; rerun the W-0284 driver against the pinned 7.1
mirror at integration.

## what the rerun shows (executed, logs below)

Builds from source this run: pinned 7.1 (tarball sha256
40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6, configure per BUILD_CONTRACT.txt (carried in this tar)) and 8.0.1
(894da5ca7d742e4429ffb2af534fcda0103ef593, identical component set). Same
hlsctl.c, same synthetic origin.

1. The EINVAL class is root-caused and is NOT version drift:
   `avformat_open_input` surfaces EINVAL for URI/argument failures (here:
   out-of-range port; libav log "Port missing in uri"), identically on pinned
   7.1 (61.7.100) and 8.0.1 (62.3.100). An unreachable origin on a VALID port
   surfaces the typed "Connection refused" on both (7.1 shows reconnect retries
   first; outcome identical).
2. The driver itself is sound on the pinned 7.1 mirror: vod/live/flaky full
   runs match the lab's own run3/run4 logs, including T8: truncated hi_2.ts is
   survived, GAP_SEEN + gaps=1, packets=1012, same variant choices.
3. Integration suspicion that the EINVAL was a 7.1/8.0.1 pin drift is
   therefore withdrawn; remaining exposure is error typing only (EINVAL for
   argument/URI errors is an avformat API fact, not a defect in the driver).

## ask of the owning lab
None blocking. If a future driver revision types open errors, map EINVAL as
"invalid URL/argument", distinct from network refusal. The pin-drift item for
the W-0284 driver is closable on this evidence.

## pinned driver option set (source1: hlsctl.c lines 52-58 of 99, sha256 20f90df8)

```c id=source1
    AVFormatContext *s = NULL; AVDictionary *o = NULL;
    av_dict_set_int(&o, "live_start_index", lsi, 0);
    av_dict_set(&o, "reconnect", "1", 0); av_dict_set(&o, "reconnect_streamed", "1", 0);
    av_dict_set(&o, "reconnect_delay_max", "2", 0); av_dict_set(&o, "reconnect_on_network_error", "1", 0);
    av_dict_set(&o, "reconnect_on_http_error", "4xx,5xx", 0);
    av_dict_set(&o, "rw_timeout", "5000000", 0);
```

## executed evidence (this run, linux x86_64)

```text id=evidence1
# version probes (check.py, runtime + header)
core: libavformat 61.7.100 libavcodec 61.19.100 libavutil 59.39.100
aux:  libavformat 62.3.100 libavcodec 62.11.100 libavutil 60.8.100
# A) valid port, no listener (7.1 core build)
libavformat 61.7.100 avformat_license=LGPL version 2.1 or later
[tcp @ ...] Connection to tcp://127.0.0.1:59998 failed: Connection refused
[http @ ...] Will reconnect at 0 in 0 second(s).   (retries per source1)
OPEN_FAIL Connection refused                       rc=1

# B) out-of-range port (7.1 core build)
[tcp @ ...] Port missing in uri
libavformat 61.7.100 ...
OPEN_FAIL Invalid argument                         rc=1

# B aux) out-of-range port (8.0.1 auxiliary build, non-gating)
libavformat 62.3.100 ...
[tcp @ ...] Port missing in uri
OPEN_FAIL Invalid argument                         rc=1

# C) flaky origin, truncation armed (7.1 core build) - matches lab run3 T8
[mpegts @ ...] Packet corrupt (stream = 0, dts = 574490).
choice bw=1500000 maxh=0 -> prog=2 variant_bitrate=1100000 height=360
GAP_SEEN stream=5 prev_ms=5812 now_ms=7437 (forward jump > 1500 ms)
END stale_dropped=818 packets=1012 last_read=End of file(-541478725) gaps=1 discontinuities=0 s4=375 s5=637
```

```json id=fixtures1
{"hlsctl.c": "sha256:20f90df8d0503fc1765a2bebabf700e3c495d01747cb8f070029b2c98b5b094f",
 "server.py": "sha256:e366be89bc4564a2463d227bf2fce9485e4f862a8f813d54e3b980dd16d70d9c",
 "check.py": "in tar, self-verifying via exact-version probe (61.7.x required for core)",
 "media/": "28 synthetic files as generated by the lab's gen_media.sh"}
```

## rev3 note
Aux version set is enforced (header == runtime, exact probed numbers), aux==core
rejected. Verified locally: positive run exit 0; --aux-prefix <same 7.1 tree>
rejected with "aux prefix is not the pinned 8.0.1 build"; --prefix <8.0.1>
rejected with "core prefix is not an exact 7.1 build".

## roles and state
writer: gdb integrator. solver lab: 1nstinct. This return carries evidence
only; the owner's eyes close the pin-drift item.

secret scan: clean
