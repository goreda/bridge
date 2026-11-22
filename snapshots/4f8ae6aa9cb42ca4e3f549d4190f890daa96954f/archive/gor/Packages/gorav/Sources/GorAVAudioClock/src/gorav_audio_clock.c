#include "gorav_audio_clock.h"
#include <stdlib.h>
#include <math.h>

typedef struct {
    uint64_t generation;
    int64_t consumed_samples;
    uint32_t sample_rate;
    double host_time;
} gvac_anchor_t;

struct gvac_audio_clock {
    double (*host_clock)(void *ctx);
    void *ctx;
    gvac_anchor_t cur;
    gvac_anchor_t prev;          /* previous same-generation anchor (drift) */
    bool has_cur;
    bool has_prev;
    uint64_t fenced_generation;  /* anchors <= this are stale */
    bool has_fence;
};

gvac_audio_clock *gvac_create(double (*host_clock)(void *ctx), void *ctx) {
    if (!host_clock) return NULL;
    gvac_audio_clock *c = (gvac_audio_clock *)calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->host_clock = host_clock;
    c->ctx = ctx;
    return c;
}

void gvac_destroy(gvac_audio_clock *c) { free(c); }

uint64_t gvac_current_generation(const gvac_audio_clock *c) {
    return (c && c->has_cur) ? c->cur.generation : 0;
}

bool gvac_has_master(const gvac_audio_clock *c) { return c && c->has_cur; }

void gvac_fence(gvac_audio_clock *c, uint64_t generation) {
    if (!c) return;
    if (!c->has_fence || generation > c->fenced_generation)
        c->fenced_generation = generation;
    c->has_fence = true;
    if (c->has_cur && c->cur.generation <= generation) {
        c->has_cur = false;
        c->has_prev = false;
    }
}

gvac_status gvac_anchor(gvac_audio_clock *c, uint64_t generation,
                        int64_t consumed_samples, uint32_t sample_rate,
                        double host_time, double consistency_tol_s) {
    if (!c || sample_rate == 0 || !isfinite(host_time) || consumed_samples < 0
        || !isfinite(consistency_tol_s) || consistency_tol_s < 0.0)
        return GVAC_ST_INVALID_ARGUMENT;
    if (c->has_fence && generation <= c->fenced_generation)
        return GVAC_ST_STALE_GENERATION;
    if (c->has_cur) {
        if (generation < c->cur.generation)
            return GVAC_ST_STALE_GENERATION;
        if (generation == c->cur.generation) {
            /* 8.5: a rate change is timeline-changing; it must arrive as a
               new generation, not a silent same-generation re-anchor. */
            if (sample_rate != c->cur.sample_rate)
                return GVAC_ST_RATE_CHANGE;
            /* Proof of a same-generation re-anchor: the prediction from the
               existing anchor must land within the caller-fixed tolerance. */
            double dt = host_time - c->cur.host_time;
            if (dt < 0.0) return GVAC_ST_INCONSISTENT;
            double predicted = (double)c->cur.consumed_samples + dt * (double)c->cur.sample_rate;
            double err_s = fabs((double)consumed_samples - predicted) / (double)sample_rate;
            if (err_s > consistency_tol_s)
                return GVAC_ST_INCONSISTENT;
            c->prev = c->cur;
            c->has_prev = true;
        }
        /* generation > cur.generation: timeline reset, new anchor chain */
        if (generation > c->cur.generation)
            c->has_prev = false;
    }
    c->cur.generation = generation;
    c->cur.consumed_samples = consumed_samples;
    c->cur.sample_rate = sample_rate;
    c->cur.host_time = host_time;
    c->has_cur = true;
    return GVAC_ST_OK;
}

gvac_status gvac_media_time(const gvac_audio_clock *c, double host_time, double *out_media_time) {
    if (!c || !out_media_time || !isfinite(host_time))
        return GVAC_ST_INVALID_ARGUMENT;
    if (!c->has_cur)
        return GVAC_ST_NO_MASTER;
    double dt = host_time - c->cur.host_time;
    *out_media_time = ((double)c->cur.consumed_samples + dt * (double)c->cur.sample_rate)
                      / (double)c->cur.sample_rate;
    return GVAC_ST_OK;
}

gvac_status gvac_expected_samples(const gvac_audio_clock *c, double host_time, int64_t *out_samples) {
    if (!c || !out_samples || !isfinite(host_time))
        return GVAC_ST_INVALID_ARGUMENT;
    if (!c->has_cur)
        return GVAC_ST_NO_MASTER;
    double dt = host_time - c->cur.host_time;
    double v = (double)c->cur.consumed_samples + dt * (double)c->cur.sample_rate;
    *out_samples = (int64_t)(v >= 0.0 ? v + 0.5 : v - 0.5);
    return GVAC_ST_OK;
}

gvac_status gvac_host_deadline(const gvac_audio_clock *c, double pts,
                               double latency_s, double *out_host_deadline) {
    if (!c || !out_host_deadline || !isfinite(pts))
        return GVAC_ST_INVALID_ARGUMENT;
    if (!c->has_cur)
        return GVAC_ST_NO_MASTER;
    if (latency_s == GVAC_LATENCY_UNKNOWN)
        return GVAC_ST_LATENCY_UNKNOWN;
    if (!isfinite(latency_s) || latency_s < 0.0)
        return GVAC_ST_INVALID_ARGUMENT;
    /* host(pts) = anchor_host + (pts*rate - consumed)/rate, minus latency */
    double anchor_media = (double)c->cur.consumed_samples / (double)c->cur.sample_rate;
    *out_host_deadline = c->cur.host_time + (pts - anchor_media) - latency_s;
    return GVAC_ST_OK;
}

gvac_status gvac_classify_frame(const gvac_audio_clock *c, double pts,
                                double now_host, double latency_s,
                                double early_window_s, double late_threshold_s,
                                gvac_sync_decision *out_decision,
                                double *out_wait_until_host) {
    if (!c || !out_decision || !out_wait_until_host || !isfinite(now_host)
        || !isfinite(early_window_s) || early_window_s < 0.0
        || !isfinite(late_threshold_s) || late_threshold_s < 0.0)
        return GVAC_ST_INVALID_ARGUMENT;
    double deadline = 0.0;
    gvac_status st = gvac_host_deadline(c, pts, latency_s, &deadline);
    if (st != GVAC_ST_OK)
        return st;
    double media_now = 0.0;
    st = gvac_media_time(c, now_host, &media_now);
    if (st != GVAC_ST_OK)
        return st;
    if (media_now > pts + late_threshold_s) {
        *out_decision = GVAC_SYNC_DROP_LATE;
        *out_wait_until_host = deadline;
        return GVAC_ST_OK;
    }
    if (deadline - now_host > early_window_s) {
        *out_decision = GVAC_SYNC_WAIT;
        *out_wait_until_host = deadline;
        return GVAC_ST_OK;
    }
    *out_decision = GVAC_SYNC_SHOW;
    *out_wait_until_host = deadline;
    return GVAC_ST_OK;
}

gvac_status gvac_drift_ppm(const gvac_audio_clock *c, double *out_ppm) {
    if (!c || !out_ppm)
        return GVAC_ST_INVALID_ARGUMENT;
    if (!c->has_cur)
        return GVAC_ST_NO_MASTER;
    if (!c->has_prev)
        return GVAC_ST_INSUFFICIENT_ANCHORS;
    double host_dt = c->cur.host_time - c->prev.host_time;
    double sample_dt = (double)(c->cur.consumed_samples - c->prev.consumed_samples);
    if (host_dt <= 0.0 || sample_dt <= 0.0)
        return GVAC_ST_INCONSISTENT;
    double expected = host_dt * (double)c->cur.sample_rate;
    *out_ppm = (sample_dt - expected) / expected * 1.0e6;
    return GVAC_ST_OK;
}

