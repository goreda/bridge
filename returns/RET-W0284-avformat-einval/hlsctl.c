/* W-0284 B5: variant choice / live edge / discontinuity / reconnect driven through the REAL avformat HLS demuxer.
 * Variant control = AVProgram/AVStream discard (avformat hls.c honours it, recheck_discard_flags).
 * Usage: hlsctl URL bw_bps max_height live_start_index max_packets [switch_after switch_bw]
 * Not a decoder: demux only. Admission (program listed) != decode support. */
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
typedef struct { int prog; int64_t bw; int h; } Var;
static int program_height(AVFormatContext *s, AVProgram *p) {
    int h = 0;
    for (unsigned i = 0; i < p->nb_stream_indexes; i++) {
        AVCodecParameters *c = s->streams[p->stream_index[i]]->codecpar;
        if (c->codec_type == AVMEDIA_TYPE_VIDEO && c->height > h) h = c->height;
    } return h;
}
static int has_codec_id(AVFormatContext *s, AVProgram *p, enum AVCodecID id) {
    for (unsigned i = 0; i < p->nb_stream_indexes; i++)
        if (s->streams[p->stream_index[i]]->codecpar->codec_id == id) return 1;
    return 0;
}
/* Same policy as hlslive.choose_variant: highest bw <= 0.8*measured, height cap, lowest as fallback; -1 if none admitted */
/* AUTHORITATIVE POLICY = hlslive.POLICY: probed height is truth, cap rejects unknown height, 0.8 budget, lowest fallback, 1.25 up-switch hysteresis (cur>=0). */
static int choose(AVFormatContext *s, Var *v, int n, int64_t bw, int maxh, int cur) {
    int best = -1, low = -1;
    for (int i = 0; i < n; i++) {
        if (maxh && (!v[i].h || v[i].h > maxh)) continue; /* strict: unknown height rejected when capped */
        if (!has_codec_id(s, s->programs[v[i].prog], AV_CODEC_ID_H264)) continue; /* policy: only h264 admitted */
        if (low < 0 || v[i].bw < v[low].bw) low = i;
        if (v[i].bw <= bw * 0.8 && (best < 0 || v[i].bw > v[best].bw)) best = i;
    }
    int pick = best >= 0 ? best : low;
    if (pick >= 0 && cur >= 0 && cur < n && v[pick].bw > v[cur].bw && bw * 0.8 < v[pick].bw * 1.25 &&
        has_codec_id(s, s->programs[v[cur].prog], AV_CODEC_ID_H264) && !(maxh && (!v[cur].h || v[cur].h > maxh))) pick = cur;
    return pick;
}
static void select_prog(AVFormatContext *s, int pi) {
    for (unsigned p = 0; p < s->nb_programs; p++) {
        enum AVDiscard d = (int)p == pi ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
        s->programs[p]->discard = d;
        for (unsigned i = 0; i < s->programs[p]->nb_stream_indexes; i++)
            s->streams[s->programs[p]->stream_index[i]]->discard = d;
    }
}
int main(int argc, char **argv) {
    if (argc < 6) return 2;
    const char *url = argv[1]; int64_t bw = atoll(argv[2]); int maxh = atoi(argv[3]);
    int lsi = atoi(argv[4]), maxpk = atoi(argv[5]);
    int sw_after = argc > 7 ? atoi(argv[6]) : -1; int64_t sw_bw = argc > 7 ? atoll(argv[7]) : 0;
    printf("libavformat %u.%u.%u avformat_license=%s\n", LIBAVFORMAT_VERSION_MAJOR, LIBAVFORMAT_VERSION_MINOR, LIBAVFORMAT_VERSION_MICRO, avformat_license());
    AVFormatContext *s = NULL; AVDictionary *o = NULL;
    av_dict_set_int(&o, "live_start_index", lsi, 0);
    av_dict_set(&o, "reconnect", "1", 0); av_dict_set(&o, "reconnect_streamed", "1", 0);
    av_dict_set(&o, "reconnect_delay_max", "2", 0); av_dict_set(&o, "reconnect_on_network_error", "1", 0);
    av_dict_set(&o, "reconnect_on_http_error", "4xx,5xx", 0);
    av_dict_set(&o, "rw_timeout", "5000000", 0);
    av_log_set_level(AV_LOG_WARNING);
    int r = avformat_open_input(&s, url, NULL, &o);
    if (r < 0) { printf("OPEN_FAIL %s\n", av_err2str(r)); return 1; }
    /* NOTE: discarding programs BEFORE find_stream_info was tried and rejected: probing of discarded programs
     * is skipped, so their height/codec stay unknown (measured, run1b). Probe all, then select. */
    if ((r = avformat_find_stream_info(s, NULL)) < 0) { printf("INFO_FAIL %s\n", av_err2str(r)); return 1; }
    printf("format=%s programs=%u streams=%u ctx_unseekable=%d duration_us=%" PRId64 " pb_seekable=%d\n", s->iformat->name, s->nb_programs, s->nb_streams,
           !!(s->ctx_flags & AVFMTCTX_UNSEEKABLE), s->duration == AV_NOPTS_VALUE ? -1 : s->duration, s->pb ? s->pb->seekable : -1);
    Var *v = calloc(s->nb_programs, sizeof *v); int n = 0;
    for (unsigned p = 0; p < s->nb_programs; p++) {
        AVDictionaryEntry *e = av_dict_get(s->programs[p]->metadata, "variant_bitrate", NULL, 0);
        v[n].prog = p; v[n].bw = e ? atoll(e->value) : 0; v[n].h = program_height(s, s->programs[p]);
        printf("variant prog=%d variant_bitrate=%" PRId64 " height=%d nstreams=%u\n", p, v[n].bw, v[n].h, s->programs[p]->nb_stream_indexes); n++;
    }
    int pick = n ? choose(s, v, n, bw, maxh, -1) : -1;
    if (pick < 0) { printf("NO_ADMITTED_VARIANT (bw=%" PRId64 " maxh=%d)\n", bw, maxh); return 3; }
    printf("choice bw=%" PRId64 " maxh=%d -> prog=%d variant_bitrate=%" PRId64 " height=%d\n", bw, maxh, v[pick].prog, v[pick].bw, v[pick].h);
    select_prog(s, v[pick].prog);
    AVPacket *pkt = av_packet_alloc(); int np = 0, errs = 0; int64_t last_ms[64]; for (int i = 0; i < 64; i++) last_ms[i] = INT64_MIN;
    int regress = 0, ret = 0, stale = 0, gaps = 0; int64_t per_stream[64] = {0};
    while (np < maxpk && (ret = av_read_frame(s, pkt)) >= 0) {
        AVStream *st = s->streams[pkt->stream_index];
        if (st->discard == AVDISCARD_ALL) { stale++; av_packet_unref(pkt); continue; } /* packets buffered during probe / before a switch */
        int64_t ts = pkt->pts != AV_NOPTS_VALUE ? pkt->pts : pkt->dts;
        int64_t ms = ts == AV_NOPTS_VALUE ? INT64_MIN : av_rescale_q(ts, st->time_base, (AVRational){1, 1000});
        if (pkt->stream_index < 64) {
            if (ms != INT64_MIN && last_ms[pkt->stream_index] != INT64_MIN && ms < last_ms[pkt->stream_index] - 500) {
                printf("DISCONTINUITY_SEEN stream=%d prev_ms=%" PRId64 " now_ms=%" PRId64 " (backward timestamp jump after packet %d)\n", pkt->stream_index, last_ms[pkt->stream_index], ms, np); regress++; }
            if (ms != INT64_MIN && last_ms[pkt->stream_index] != INT64_MIN && ms > last_ms[pkt->stream_index] + 1500) {
                printf("GAP_SEEN stream=%d prev_ms=%" PRId64 " now_ms=%" PRId64 " (forward jump > 1500 ms: lost data / skipped segment)\n", pkt->stream_index, last_ms[pkt->stream_index], ms); gaps++; }
            if (ms != INT64_MIN) { last_ms[pkt->stream_index] = ms; }
            per_stream[pkt->stream_index]++;
        }
        if (np < 3 || np % 40 == 0) printf("pkt %d stream=%d type=%s ms=%" PRId64 " size=%d key=%d\n", np, pkt->stream_index, av_get_media_type_string(st->codecpar->codec_type), ms, pkt->size, !!(pkt->flags & AV_PKT_FLAG_KEY));
        av_packet_unref(pkt); np++;
        if (np == sw_after) {
            int p2 = choose(s, v, n, sw_bw, maxh, pick);
            if (p2 < 0 || p2 >= n) { printf("SWITCH_NO_ADMITTED_VARIANT keep current\n"); continue; }
            printf("SWITCH at packet %d bw=%" PRId64 " -> prog=%d variant_bitrate=%" PRId64 "\n", np, sw_bw, v[p2].prog, v[p2].bw);
            select_prog(s, v[p2].prog); pick = p2;
        }
    }
    printf("END stale_dropped=%d packets=%d last_read=%s(%d) gaps=%d discontinuities=%d", stale, np, ret < 0 ? av_err2str(ret) : "limit", ret, gaps, regress);
    for (int i = 0; i < (int)s->nb_streams && i < 64; i++) if (per_stream[i]) printf(" s%d=%" PRId64, i, per_stream[i]);
    printf("\n"); (void)errs;
    av_packet_free(&pkt); avformat_close_input(&s); free(v); return 0;
}
