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
 *   discard (deliberately wrong: returns pre-target frames).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <inttypes.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>

static const AVRational MS = {1, 1000};

typedef __int128 i128;

static void print_i128(i128 v) {
    if (v == 0) { putchar('0'); return; }
    if (v < 0) { putchar('-'); v = -v; }
    char buf[48]; int n = 0;
    while (v) { buf[n++] = '0' + (int)(v % 10); v /= 10; }
    while (n) putchar(buf[--n]);
}

typedef struct { AVFormatContext *fmt; int idx; AVCodecContext *cc; } Stream;

/* 0 = opened, 1 = stream absent, -1 = real error */
static int open_stream(AVFormatContext *fmt, enum AVMediaType type, Stream *s) {
    const AVCodec *dec = NULL;
    int idx = av_find_best_stream(fmt, type, -1, -1, &dec, 0);
    s->fmt = fmt; s->idx = -1; s->cc = NULL;
    if (idx == AVERROR_STREAM_NOT_FOUND) return 1;
    if (idx < 0) { fprintf(stderr, "find_best_stream error %d\n", idx); return -1; }
    s->idx = idx;
    s->cc = avcodec_alloc_context3(dec);
    if (!s->cc) return -1;
    if (avcodec_parameters_to_context(s->cc, fmt->streams[idx]->codecpar) < 0) return -1;
    if (avcodec_open2(s->cc, dec, NULL) < 0) { fprintf(stderr, "decoder open failed\n"); return -1; }
    return 0;
}

static void print_stream_info(AVFormatContext *fmt) {
    printf("container start=%" PRId64 " us duration=%" PRId64 " us\n",
           fmt->start_time == AV_NOPTS_VALUE ? -1 : fmt->start_time,
           fmt->duration == AV_NOPTS_VALUE ? -1 : fmt->duration);
    for (unsigned i = 0; i < fmt->nb_streams; i++) {
        AVStream *st = fmt->streams[i];
        const char *t = av_get_media_type_string(st->codecpar->codec_type);
        printf("stream #%u %s codec=%s timebase=%d/%d start_ticks=%" PRId64 " duration_ticks=%" PRId64 "\n",
               i, t ? t : "?", avcodec_get_name(st->codecpar->codec_id),
               st->time_base.num, st->time_base.den,
               st->start_time == AV_NOPTS_VALUE ? -1 : st->start_time,
               st->duration == AV_NOPTS_VALUE ? -1 : st->duration);
    }
}

typedef struct {
    int err, eof, got_raw, discarded, found;
    int64_t raw_pts;
    int64_t sel_pts;
    int64_t sel_off;
    int sel_rate, sel_ns;
    i128 sel_num, sel_den;   /* exact selected first-sample time, seconds */
} PassRes;

/* exact: does frame span target (end > target_ms/1000)? checked __int128 */
static int spans_target(int64_t pts, AVRational tb, int ns, int rate, int64_t target_ms) {
    i128 lhs = ((i128)pts * tb.num * rate + (i128)ns * tb.den) * 1000;
    i128 rhs = (i128)target_ms * tb.den * rate;
    return lhs > rhs;
}

/* exact retained offset: smallest i >= 0 with pts + i/rate >= target (checked).
   Caller guarantees pts < target, so the numerator is positive. */
static i128 retained_offset(int64_t pts, AVRational tb, int rate, int64_t target_ms) {
    i128 num = ((i128)target_ms * tb.den - (i128)pts * 1000 * tb.num) * rate;
    i128 den = (i128)1000 * tb.den;
    return (num + den - 1) / den;
}

/* do_seek: BACKWARD seek to (clamped) target; else NO seek at all (seqref:
   caller passes a freshly opened context at its initial demux position). */
static PassRes run_pass(Stream *s, int64_t target_ms, int naive, int do_seek, const char *name) {
    PassRes R; memset(&R, 0, sizeof R);
    R.raw_pts = R.sel_pts = AV_NOPTS_VALUE; R.sel_off = -1;
    AVStream *st = s->fmt->streams[s->idx];
    AVRational tb = st->time_base;
    int is_audio = st->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;

    int64_t origin_ticks = st->start_time == AV_NOPTS_VALUE ? 0 : st->start_time;
    int64_t eff_ticks = av_rescale_q(target_ms, MS, tb);
    int clamped = 0;
    if (av_compare_ts(target_ms, MS, origin_ticks, tb) < 0) {
        eff_ticks = origin_ticks; clamped = 1;
    }
    printf("[%s] target_ms=%" PRId64 " origin_ticks=%" PRId64 "(tb=%d/%d)%s mode=%s\n",
           name, target_ms, origin_ticks, tb.num, tb.den,
           clamped ? " CLAMPED-TO-ORIGIN" : "", do_seek ? "seek" : "seqref-noseek");

    if (do_seek) {
        int sret = av_seek_frame(s->fmt, s->idx, eff_ticks, AVSEEK_FLAG_BACKWARD);
        if (sret < 0) { printf("[%s] SEEK-ERROR %d\n", name, sret); R.err = 1; return R; }
        if (!naive)
            avcodec_flush_buffers(s->cc);   /* flush state between seeks */
    }

    AVPacket *pkt = av_packet_alloc();
    AVFrame *fr = av_frame_alloc();
    int done = 0, sent_eof = 0;

    while (!done && !R.err) {
        if (!sent_eof) {
            int r = av_read_frame(s->fmt, pkt);
            if (r == AVERROR_EOF) {
                sent_eof = 1; R.eof = 1;
                if (avcodec_send_packet(s->cc, NULL) < 0) { printf("[%s] SEND-ERROR on drain\n", name); R.err = 1; }
            } else if (r < 0) {
                printf("[%s] READ-ERROR %d (not EOF)\n", name, r); R.err = 1;
            } else if (pkt->stream_index != s->idx) {
                av_packet_unref(pkt);
                continue;
            } else {
                int sr = avcodec_send_packet(s->cc, pkt);
                av_packet_unref(pkt);
                if (sr < 0) { printf("[%s] SEND-ERROR %d\n", name, sr); R.err = 1; }
            }
            if (R.err) break;
        }
        while (!done && !R.err) {
            int rr = avcodec_receive_frame(s->cc, fr);
            if (rr == AVERROR(EAGAIN)) break;
            if (rr == AVERROR_EOF) { done = 1; break; }
            if (rr < 0) { printf("[%s] DECODE-ERROR %d\n", name, rr); R.err = 1; break; }
            int64_t pts = fr->pts;
            if (!R.got_raw) { R.raw_pts = pts; R.got_raw = 1; }
            if (naive) { done = 1; }
            else if (pts == AV_NOPTS_VALUE) {
                printf("[%s] WARN frame without PTS skipped\n", name);
            } else if (av_compare_ts(pts, tb, target_ms, MS) >= 0) {
                R.sel_pts = pts; R.sel_rate = fr->sample_rate; R.sel_ns = fr->nb_samples;
                R.sel_off = 0; R.found = 1;
                R.sel_num = (i128)pts * tb.num * fr->sample_rate;
                R.sel_den = (i128)tb.den * fr->sample_rate;
                done = 1;
            } else if (is_audio && fr->nb_samples > 0 &&
                       spans_target(pts, tb, fr->nb_samples, fr->sample_rate, target_ms)) {
                i128 i = retained_offset(pts, tb, fr->sample_rate, target_ms);
                if (i >= 0 && i < fr->nb_samples) {   /* required 0 <= i < nb_samples */
                    R.sel_pts = pts; R.sel_off = (int64_t)i; R.sel_rate = fr->sample_rate;
                    R.sel_ns = fr->nb_samples; R.found = 1;
                    R.sel_num = (i128)pts * tb.num * fr->sample_rate + i * tb.den;
                    R.sel_den = (i128)tb.den * fr->sample_rate;
                    done = 1;
                } else {
                    printf("[%s] NOTE spanning frame but offset outside [0,%d), discarding: ", name, fr->nb_samples);
                    print_i128(i); printf("\n");
                    R.discarded++;
                }
            } else R.discarded++;
            av_frame_unref(fr);
        }
        if (sent_eof && !done && !R.err) done = 1;
    }

    printf("[%s] raw_first_decoded_pts=", name);
    if (!R.got_raw) printf("NONE");
    else if (R.raw_pts == AV_NOPTS_VALUE) printf("NOPTS");
    else printf("%" PRId64 " ticks (~%.6f ms)", R.raw_pts, 1000.0 * R.raw_pts * tb.num / tb.den);
    printf("\n");
    if (naive) {
        if (R.got_raw && R.raw_pts != AV_NOPTS_VALUE)
            printf("[%s] naive returns first decoded frame; oracle verdict: %s\n",
                   name, av_compare_ts(R.raw_pts, tb, target_ms, MS) < 0 ? "REJECT (pre-target)" : "ACCEPT");
    } else {
        printf("[%s] preroll_discarded=%d\n", name, R.discarded);
        if (R.found) {
            if (is_audio) {
                printf("[%s] selected_audio_frame_pts=%" PRId64 " ticks (~%.6f ms) nb_samples=%d rate=%d retained_offset_samples=%" PRId64 "\n",
                       name, R.sel_pts, 1000.0 * R.sel_pts * tb.num / tb.den, R.sel_ns, R.sel_rate, R.sel_off);
                printf("[%s] selected_first_sample_time=", name);
                print_i128(R.sel_num); putchar('/'); print_i128(R.sel_den);
                printf(" s (exact rational; ~%.6f ms)\n", 1000.0 * (double)R.sel_num / (double)R.sel_den);
            } else {
                printf("[%s] selected_first_pts=%" PRId64 " ticks (~%.6f ms) = first video frame at/after target (exact-compare)\n",
                       name, R.sel_pts, 1000.0 * R.sel_pts * tb.num / tb.den);
            }
        } else if (R.eof && !R.err) {
            printf("[%s] selected=NONE (clean EOF: no frame at/after target)\n", name);
        } else {
            printf("[%s] selected=NONE (ABORTED on error, not EOF)\n", name);
        }
    }
    av_packet_free(&pkt);
    av_frame_free(&fr);
    return R;
}

static int same_sel(const PassRes *a, const PassRes *b) {
    if (a->found != b->found) return 0;
    if (!a->found) return 1;
    if (a->sel_pts != b->sel_pts || a->sel_off != b->sel_off) return 0;
    return a->sel_num * b->sel_den == b->sel_num * a->sel_den; /* checked __int128 */
}

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
