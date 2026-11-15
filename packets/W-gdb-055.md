# W-gdb-055 return-to-lab: W-0274/N03 negative-start Matroska audio seek MISMATCH (in2tinct) [rev 3]
state: candidate
solver lab: in2tinct
reviewer lab: gdb integrator (gorav lane)
id: W-gdb-055

```packet-json
{
 "packet_id": "W-gdb-055",
 "writer": "gdb",
 "code_owner": "in2tinct (owning lab, demux/seek/timing allocation)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {"path": "kits/n03-negstart-mismatch/seek_ref_v4.c", "excerpt_block": "source1"},
  {"path": "kits/n03-negstart-mismatch/seek_ref_v4.c", "excerpt_block": "source2"},
  {"path": "kits/n03-negstart-mismatch/gen_fixtures.sh", "excerpt_block": "source3"}
 ],
 "interface": {
  "signatures": "seek_ref FILE info|naive|oracle|verify [target_ms...] (source1 header contract; source2 main/verify dispatch); verify exits 3 on any MISMATCH",
  "types": "verify = seek pass on one context vs an INDEPENDENT fresh-open no-seek sequential reference, compared on the common ms timeline (stream ticks -> ms via stream timebase num/den)",
  "ownership_lifetime": "fixture bytes are generated media only (no owner media), carried in the kit with the pinned sha256",
  "caller": "gorav lane ingest gate (kits/n03-negstart-mismatch/check.py)",
  "callee": "in2tinct seek-landing reference (W-0274/N03)"
 },
 "test": {
  "command": "cd kits/n03-negstart-mismatch && python3 check.py --prefix /path/to/ffinstall  (or FFMPEG_PREFIX=...)",
  "expected": "exit 0; stdout 'n03-negstart-mismatch rev3: 5/5 checks PASS' (carrier integrity, fixture sha256 pin, pinned 7.1 build contract present, AUXILIARY 8.0.1 log non-gating, STRICT 7.1: exact-version probe libavformat 61.7.x/libavcodec 61.19.x/libavutil 59.39.x then the lab's own STRICT command failing with the documented signature exit 3, audio MISMATCH -1023/-500/-5000, MATCH +500, video MATCH). Without --prefix the strict leg is NOT RUN and check.py exits 77.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": ["kits/n03-negstart-mismatch/"],
  "return_form": "patch"
 }
}
```

## problem (what fails)
W-0274/N03 seek-landing reference (1nstinct G0735 v6) shows a MEASURED Matroska seek-granularity MISMATCH in the negative-start region on f_negstart.mkv. This packet returns the kit WITH the executable failing test (verify exits 3), the fixture bytes, and the exact 7.1 build contract.

## provenance and version labeling (per gate ruling)
- 7.1 MEASURED evidence (lab): the lab's own captured log (kit: lab-71-evidence-excerpt.txt, verbatim from G0735 out/test_run.txt lines 275-360): audio seek-vs-seqref MISMATCH at -1023/-500/-5000 ms, MATCH at +500; video MATCH at every target; v6 true counts 17 MATCH + 3 MISMATCH of 20.
- 7.1 MEASURED evidence (integrator, rev3): the integrator built the exact pinned FFmpeg 7.1 per SEVEN_ONE_BUILD.txt (tarball sha256 verified 40973d44...7abe6; header probe libavformat 61.7.100 / libavcodec 61.19.100 / libavutil 59.39.100) and ran the lab's STRICT command: exit 3, audio MISMATCH at -1023/-500/-5000, MATCH at +500, video MATCH everywhere. The failure reproduces on the real pinned 7.1 build; check.py rev3 runs this leg against any runner-supplied --prefix and enforces the exact version.
- 8.0.1 INTEGRATOR REPRODUCTION (auxiliary log only, non-gating, never conflated): check.py builds seek_ref_v4.c against the integrator's FFmpeg 8.0.1 static libs (tree 894da5ca7d742e4429ffb2af534fcda0103ef593) when that tree exists and gets the same signature. It never substitutes for the 7.1 leg.
- fixture pin: fixtures/f_negstart.mkv sha256 7fbf6e5f90641fd019859519dc6419f4095ba20d8763487747fb436bf3785dbf (matches fixtures/fixtures.sha256); gen_fixtures.sh carries the deterministic-source generator for provenance.

## closure (original MATCH gate, NOT loosened)
the return closes only when `seek_ref fixtures/f_negstart.mkv verify -1023 -500 -5000 500` exits 0 (all four targets MATCH) on the pinned 7.1 build. A named ms granularity bound would LOOSEN the original MATCH gate and is NOT accepted as closure without a separately approved expectation. Any rerun uses the exact pinned 7.1 build in SEVEN_ONE_BUILD.txt (tarball sha256 40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6), never 8.0.1.

## acceptance test (executable, bounded)
cd kits/n03-negstart-mismatch && python3 check.py --prefix <7.1 install> exits 0 with '5/5 checks PASS': carrier integrity, fixture sha256 pin, pinned 7.1 build contract present, the auxiliary 8.0.1 log (non-gating), and the STRICT 7.1 leg - exact-version probe (build bounded 300s), then the lab's own STRICT command on that 7.1 build (bounded 120s) failing with the documented signature. Without --prefix the strict leg does not run and check.py exits 77.

## pinned excerpts
### kits/n03-negstart-mismatch/seek_ref_v4.c (carrier, lines 1-29: mode contract header)
```c id=source1
/* seek_ref.c - W-0274 / 195a-N03: seek-landing avformat/avcodec reference, v4.
 *
 * Modes:
 *   seek_ref FILE info
 *   seek_ref FILE naive  <target_ms>
 *   seek_ref FILE oracle <target_ms> [target_ms ...]
 *   seek_ref FILE verify <target_ms> [target_ms ...]
 *
 * Exactness: all selection decisions and the reported first-sample time are
 * exact rational arithmetic. Cross products use checked __int128, so the
 * supported input range is: any int64 stream ticks/PTS and any int64
 * target_ms with timebase num/den and sample rate each < 2^31 (worst-case
 * product pts*num*rate*1000 < 2^127); inputs beyond that are not supported.
 * av_compare_ts / av_rescale_q use FFmpeg's own overflow-checked paths.
 * Nothing is rounded for a decision. Values after "~" are display rounding.
 *
 * oracle: av_seek_frame(BACKWARD) -> avcodec_flush_buffers -> decode ->
 *   video: first frame with pts >= target (exact) is selected.
 *   audio: a frame at/after target is selected whole (offset 0); a frame that
 *     starts before target is kept only if it strictly spans target (exact)
 *     and the retained offset i = ceil((target - pts) * rate) (exact)
 *     satisfies 0 <= i < nb_samples; otherwise it is preroll, discarded.
 *   Real EOF vs read/send/decode errors distinguished; any error exits 1,
 *   usage errors exit 2. Exit 0 = all passes completed cleanly.
 * verify: seek pass on one context vs an INDEPENDENT sequential reference:
 *   a second avformat_open_input with fresh decoders, reading from the
 *   initial demux position with NO seek call of any kind. Prints
 *   MATCH/MISMATCH; exit 3 on any mismatch (documented finding, not a pass).
 * naive : seek backward, return first decoded frame, no flush, no preroll
```
### kits/n03-negstart-mismatch/seek_ref_v4.c (carrier, lines 233-300: main + verify dispatch; exit 3 on MISMATCH)
```c id=source2
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: seek_ref FILE info|naive|oracle|verify [target_ms...]\n"); return 2; }
    const char *path = argv[1], *mode = argv[2];
    int is_verify = !strcmp(mode, "verify");
    if (strcmp(mode, "info") && strcmp(mode, "naive") && strcmp(mode, "oracle") && !is_verify) {
        fprintf(stderr, "bad mode\n"); return 2;
    }
    if (strcmp(mode, "info") && argc < 4) { fprintf(stderr, "no target_ms given\n"); return 2; }

    /* validate all targets before any I/O side effects */
    int64_t targets[64]; int nt = 0;
    for (int i = 3; i < argc && nt < 64; i++) {
        char *end = NULL; errno = 0;
        long long t = strtoll(argv[i], &end, 10);
        if (errno || !end || *end) { fprintf(stderr, "invalid target_ms '%s'\n", argv[i]); return 2; }
        targets[nt++] = t;
    }

    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path, NULL, NULL) < 0) { fprintf(stderr, "open failed\n"); return 1; }
    if (avformat_find_stream_info(fmt, NULL) < 0) { fprintf(stderr, "stream info failed\n"); return 1; }
    if (!strcmp(mode, "info")) { print_stream_info(fmt); return 0; }

    Stream v = {0}, a = {0};
    int rv = open_stream(fmt, AVMEDIA_TYPE_VIDEO, &v);
    int ra = open_stream(fmt, AVMEDIA_TYPE_AUDIO, &a);
    if (rv < 0 || ra < 0) { fprintf(stderr, "stream open error\n"); return 1; }
    if (rv == 1 && ra == 1) { fprintf(stderr, "no usable streams\n"); return 1; }
    printf("opened: video=%s audio=%s\n", rv == 0 ? "yes" : "no", ra == 0 ? "yes" : "no");

    int rc = 0, mismatches = 0;
    for (int i = 0; i < nt; i++) {
        int64_t t = targets[i];
        printf("=== target %" PRId64 " ms (%s mode) ===\n", t, mode);
        if (!is_verify) {
            if (rv == 0 && run_pass(&v, t, !strcmp(mode, "naive"), 1, "video").err) rc = 1;
            if (!strcmp(mode, "oracle") && ra == 0 && run_pass(&a, t, 0, 1, "audio").err) rc = 1;
        } else {
            /* seqref: per stream per target, a FRESH avformat_open_input with
               a fresh decoder, read from the initial demux position, no seek
               and no avformat_find_stream_info on the seqref context. */
            static const struct { int type; const char *name; } chans[2] = {
                { AVMEDIA_TYPE_VIDEO, "video" }, { AVMEDIA_TYPE_AUDIO, "audio" }
            };
            Stream *sv[2] = { &v, &a }; int have[2] = { rv == 0, ra == 0 };
            for (int c = 0; c < 2; c++) {
                if (!have[c]) continue;
                PassRes s1 = run_pass(sv[c], t, 0, 1, c ? "audio/seek" : "video/seek");
                AVFormatContext *f2 = NULL; Stream s2s = {0};
                if (avformat_open_input(&f2, path, NULL, NULL) < 0 ||
                    avformat_find_stream_info(f2, NULL) < 0 ||
                    open_stream(f2, chans[c].type, &s2s) != 0) {
                    fprintf(stderr, "seqref open failed\n"); rc = 1;
                    if (f2) avformat_close_input(&f2);
                    continue;
                }
                PassRes s2 = run_pass(&s2s, t, 0, 0, c ? "audio/seqref" : "video/seqref");
                avcodec_free_context(&s2s.cc);
                avformat_close_input(&f2);
                if (s1.err || s2.err) rc = 1;
                else { int m = same_sel(&s1, &s2); printf("[%s] seek-vs-seqref: %s\n", chans[c].name, m ? "MATCH" : "MISMATCH"); if (!m) mismatches++; }
            }
        }
    }
    if (rc) return 1;
    if (mismatches) return 3;
    return 0;
}
```
### kits/n03-negstart-mismatch/gen_fixtures.sh (carrier, f_negstart.mkv generator section)
```sh id=source3
# audio start_time (AAC priming lands before 0). -avoid_negative_ts disabled.
$FF -itsoffset -1.0 -f lavfi -i sine=frequency=550:sample_rate=44100:duration=7 \
    -f lavfi -i testsrc2=size=320x240:rate=25:duration=6 \
    -map 0:a -map 1:v \
    -c:v libx264 -preset veryfast -g 25 -bf 2 -pix_fmt yuv420p \
    -c:a aac -b:a 64k -avoid_negative_ts disabled \
    -f matroska f_negstart.mkv

sha256sum f_shortgop.mp4 f_longgop.mp4 f_unequal_tb.mp4 f_negstart.mkv | tee fixtures.sha256
```


## roles and state
solver lab: in2tinct. reviewer lab: gdb integrator. Returned with the failing test per arch-196q item 3.

secret scan: clean

```json id=fixtures1
[{"check": "strict-7.1", "expect": "exact-version probe 61.7.x/61.19.x/59.39.x, then lab STRICT command verify -1023 -500 -5000 500 on the --prefix 7.1 build FAILS with the documented signature: exit 3, audio MISMATCH -1023/-500/-5000, MATCH +500, video MATCH everywhere"}, {"check": "aux-8.0.1", "expect": "same signature, non-gating, labeled 8.0.1"}, {"check": "fixture pin", "expect": "f_negstart.mkv sha256 7fbf6e5f90641fd019859519dc6419f4095ba20d8763487747fb436bf3785dbf"}, {"check": "7.1 contract", "expect": "SEVEN_ONE_BUILD.txt carries the exact pinned 7.1 source sha256 + configure + build command"}]
```
