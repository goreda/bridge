#ifndef GORAV_AUDIO_CLOCK_H
#define GORAV_AUDIO_CLOCK_H

/* GorAVAudioClock - GP-47 audio master clock core (design: audio-selected
   mixed-media design v2r2, sections 2.1-2.2, 8.2, 8.5).
 *
 * Contract points implemented here:
 *  - G-A3: the audio master is the ONLY presentation clock domain in an
 *    audio-selected session. Correlation between the audio sample position
 *    and the host clock is an explicit, proven anchor - never assumed.
 *  - No clock substitution (2.2): with no proven anchor every query fails
 *    with GVAC_ST_NO_MASTER. There is NO fallback to a system clock.
 *  - G-A4 / AU-16: latency is a declared model value; unknown stays
 *    unknown (GVAC_ST_LATENCY_UNKNOWN) and is never silently zero.
 *  - G-A11: drift thresholds are caller-fixed inputs to every check; this
 *    module carries no tuned constants.
 *  - 8.5 / AU-12: a timeline-changing route reset is a NEW generation.
 *    Re-anchor within a generation only with proof (prediction inside a
 *    caller-fixed tolerance); stale-generation anchors are fenced.
 *  - Buffer-stage honesty (8.2): sample positions are device-consumed
 *    positions supplied by the sink owner; a submitted-but-unheard buffer
 *    is never counted as consumed by this module (caller duty; the API
 *    only accepts the sink's consumed counter).
 */

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GVAC_ST_OK = 0,
    GVAC_ST_NO_MASTER = 1,        /* no proven anchor: failure/new-session path, never substitution */
    GVAC_ST_STALE_GENERATION = 2, /* anchor generation is fenced: rejected */
    GVAC_ST_INCONSISTENT = 3,     /* same-generation re-anchor outside caller tolerance: no proof */
    GVAC_ST_RATE_CHANGE = 4,      /* same-generation sample-rate change: that is a timeline reset, use a new generation */
    GVAC_ST_LATENCY_UNKNOWN = 5,  /* caller passed unknown latency: reported, never substituted */
    GVAC_ST_INVALID_ARGUMENT = 6,
    GVAC_ST_INSUFFICIENT_ANCHORS = 7 /* drift needs >= 2 same-generation anchors; NOT a lost master */
} gvac_status;

typedef enum {
    GVAC_SYNC_SHOW = 0,      /* frame is due now or inside the early window */
    GVAC_SYNC_WAIT = 1,      /* frame is early: wait until out_wait_until_host */
    GVAC_SYNC_DROP_LATE = 2  /* frame is later than the caller-fixed late threshold */
} gvac_sync_decision;

typedef struct gvac_audio_clock gvac_audio_clock;

/* host_clock: monotonic seconds, supplied by the owner (shared origin clock).
   This module never calls a system clock by itself. */
gvac_audio_clock *gvac_create(double (*host_clock)(void *ctx), void *ctx);
void gvac_destroy(gvac_audio_clock *c);

/* Establish or re-anchor the correlation for a generation.
   - First anchor of a NEW generation (gen > last fenced gen) is accepted.
   - Same-generation re-anchor must predict sample_pos within
     consistency_tol_s of media time, and must keep the same sample rate;
     otherwise it is rejected (INCONSISTENT / RATE_CHANGE) and the previous
     anchor stays in force.
   - A fenced or older generation is rejected (STALE_GENERATION).
   consumed_samples: sink-owned device-consumed sample counter at host_time. */
gvac_status gvac_anchor(gvac_audio_clock *c, uint64_t generation,
                        int64_t consumed_samples, uint32_t sample_rate,
                        double host_time, double consistency_tol_s);

/* Fence all anchors up to and including `generation` (teardown / K3-style
   reset). After fencing, queries fail with NO_MASTER until a new anchor. */
void gvac_fence(gvac_audio_clock *c, uint64_t generation);

/* Media time (seconds on the audio timeline) at a host time. */
gvac_status gvac_media_time(const gvac_audio_clock *c, double host_time, double *out_media_time);

/* Expected device-consumed sample position at a host time (starvation /
   underrun observation only; an underrun never substitutes the clock). */
gvac_status gvac_expected_samples(const gvac_audio_clock *c, double host_time, int64_t *out_samples);

/* Host deadline at which a frame with pts (media seconds) should be shown.
   latency_s is the sink-declared end-to-end latency; pass GVAC_LATENCY_UNKNOWN
   when the sink has no proven value: the call then fails with
   GVAC_ST_LATENCY_UNKNOWN and out_host_deadline is untouched. */
#define GVAC_LATENCY_UNKNOWN (-1.0)
gvac_status gvac_host_deadline(const gvac_audio_clock *c, double pts,
                               double latency_s, double *out_host_deadline);

/* Classify a frame for presentation against the audio master.
   early_window_s / late_threshold_s are caller-fixed policy values; both
   must be finite and >= 0 (a negative late threshold would silently drop
   every frame, a negative early window silently disables waiting).
   On GVAC_SYNC_WAIT, out_wait_until_host receives the host deadline. */
gvac_status gvac_classify_frame(const gvac_audio_clock *c, double pts,
                                double now_host, double latency_s,
                                double early_window_s, double late_threshold_s,
                                gvac_sync_decision *out_decision,
                                double *out_wait_until_host);

/* Measured drift between the two most recent same-generation anchors, in
   ppm (positive: device runs faster than host). Requires >= 2 anchors in
   the current generation. Drift THRESHOLDS are the caller's (G-A11); this
   only reports the measurement. */
gvac_status gvac_drift_ppm(const gvac_audio_clock *c, double *out_ppm);

uint64_t gvac_current_generation(const gvac_audio_clock *c);
bool gvac_has_master(const gvac_audio_clock *c);

#ifdef __cplusplus
}
#endif
#endif

