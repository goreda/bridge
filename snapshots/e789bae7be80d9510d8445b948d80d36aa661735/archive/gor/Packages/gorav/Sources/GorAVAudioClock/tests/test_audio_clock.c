#include "gorav_audio_clock.h"
#include <stdio.h>
#include <math.h>

static double fake_now;
static double fake_clock(void *ctx) { (void)ctx; return fake_now; }

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main(void) {
    /* 1. no master: every query refuses, no system-clock substitution */
    fake_now = 100.0;
    gvac_audio_clock *c = gvac_create(fake_clock, NULL);
    CHECK(c != NULL);
    double out_d = 0.0; int64_t out_i = 0;
    CHECK(gvac_media_time(c, 100.0, &out_d) == GVAC_ST_NO_MASTER);
    CHECK(gvac_expected_samples(c, 100.0, &out_i) == GVAC_ST_NO_MASTER);
    gvac_sync_decision dec; double wait_until = 0.0;
    CHECK(gvac_classify_frame(c, 5.0, 100.0, 0.02, 0.005, 0.040, &dec, &wait_until) == GVAC_ST_NO_MASTER);

    /* 2. anchor + exact media/host mapping */
    CHECK(gvac_anchor(c, 1, 48000, 48000, 100.0, 0.002) == GVAC_ST_OK); /* 1.0 s of audio at t=100 */
    CHECK(gvac_has_master(c));
    CHECK(gvac_media_time(c, 101.0, &out_d) == GVAC_ST_OK);
    CHECK(fabs(out_d - 2.0) < 1e-9);
    CHECK(gvac_expected_samples(c, 101.5, &out_i) == GVAC_ST_OK);
    CHECK(out_i == 120000);

    /* 3. stale generation rejected */
    CHECK(gvac_anchor(c, 1, 48000, 48000, 90.0, 0.002) == GVAC_ST_INCONSISTENT); /* same gen, earlier host time: no proof */
    gvac_fence(c, 1);
    CHECK(gvac_anchor(c, 1, 0, 48000, 102.0, 0.002) == GVAC_ST_STALE_GENERATION);
    CHECK(!gvac_has_master(c));
    CHECK(gvac_media_time(c, 102.0, &out_d) == GVAC_ST_NO_MASTER);

    /* 4. same-generation re-anchor: consistent accepted, inconsistent rejected */
    gvac_destroy(c);
    c = gvac_create(fake_clock, NULL);
    CHECK(gvac_anchor(c, 2, 0, 48000, 200.0, 0.002) == GVAC_ST_OK);
    /* at t=201 prediction is 48000 samples; 48096 is +2ms: outside 2ms? equal edge */
    CHECK(gvac_anchor(c, 2, 48096, 48000, 201.0, 0.002) == GVAC_ST_OK);      /* exactly at tol */
    CHECK(gvac_anchor(c, 2, 97000, 48000, 202.0, 0.002) == GVAC_ST_INCONSISTENT); /* +208ms off */
    /* clock still anchored on the consistent value */
    CHECK(gvac_media_time(c, 202.0, &out_d) == GVAC_ST_OK);
    CHECK(fabs(out_d - 2.002) < 1e-9);

    /* 5. same-generation rate change is a timeline reset: rejected; new gen ok */
    CHECK(gvac_anchor(c, 2, 96000, 44100, 202.0, 0.002) == GVAC_ST_RATE_CHANGE);
    CHECK(gvac_anchor(c, 3, 0, 44100, 202.0, 0.002) == GVAC_ST_OK);
    CHECK(gvac_current_generation(c) == 3);
    CHECK(gvac_media_time(c, 203.0, &out_d) == GVAC_ST_OK);
    CHECK(fabs(out_d - 1.0) < 1e-9);

    /* 6. latency: unknown stays unknown; known shifts the deadline */
    CHECK(gvac_host_deadline(c, 5.0, GVAC_LATENCY_UNKNOWN, &out_d) == GVAC_ST_LATENCY_UNKNOWN);
    CHECK(gvac_host_deadline(c, 5.0, 0.050, &out_d) == GVAC_ST_OK);
    /* media anchor: 0 samples at t=202 => media 0 at host 202; pts 5 -> 207 - 0.05 */
    CHECK(fabs(out_d - 206.95) < 1e-9);

    /* 7. drift measurement from two same-generation anchors */
    gvac_destroy(c);
    c = gvac_create(fake_clock, NULL);
    CHECK(gvac_anchor(c, 4, 0, 48000, 300.0, 0.01) == GVAC_ST_OK);
    /* device reports 48192 samples after 1.0 s host: +0.4% = +4000 ppm, inside tol 1s? no:
       re-anchor tolerance is on prediction error: (48192-48000)/48000 = 4ms > 10ms? 4ms <= 10ms ok */
    CHECK(gvac_anchor(c, 4, 48192, 48000, 301.0, 0.010) == GVAC_ST_OK);
    CHECK(gvac_drift_ppm(c, &out_d) == GVAC_ST_OK);
    CHECK(fabs(out_d - 4000.0) < 1.0);
    /* drift with a single anchor: insufficient anchors, NOT a lost master */
    { gvac_audio_clock *c2 = gvac_create(fake_clock, NULL);
      CHECK(gvac_anchor(c2, 1, 0, 48000, 300.0, 0.002) == GVAC_ST_OK);
      CHECK(gvac_drift_ppm(c2, &out_d) == GVAC_ST_INSUFFICIENT_ANCHORS);
      gvac_destroy(c2); }

    /* 8. classify: WAIT early, SHOW in window, DROP_LATE past threshold */
    gvac_destroy(c);
    c = gvac_create(fake_clock, NULL);
    CHECK(gvac_anchor(c, 5, 0, 48000, 400.0, 0.002) == GVAC_ST_OK); /* media 0 @ host 400 */
    /* frame pts 1.0s, now 400: deadline 401 (no latency); early by 1s -> WAIT */
    CHECK(gvac_classify_frame(c, 1.0, 400.0, 0.0, 0.005, 0.040, &dec, &wait_until) == GVAC_ST_OK);
    CHECK(dec == GVAC_SYNC_WAIT && fabs(wait_until - 401.0) < 1e-9);
    /* now 400.999: inside 5ms early window -> SHOW */
    CHECK(gvac_classify_frame(c, 1.0, 400.999, 0.0, 0.005, 0.040, &dec, &wait_until) == GVAC_ST_OK);
    CHECK(dec == GVAC_SYNC_SHOW);
    /* now 401.100: media 1.1 > pts+0.040 -> DROP_LATE */
    CHECK(gvac_classify_frame(c, 1.0, 401.100, 0.0, 0.005, 0.040, &dec, &wait_until) == GVAC_ST_OK);
    CHECK(dec == GVAC_SYNC_DROP_LATE);
    /* latency shifts the deadline later */
    CHECK(gvac_classify_frame(c, 1.0, 400.950, 0.100, 0.005, 0.040, &dec, &wait_until) == GVAC_ST_OK);
    CHECK(dec == GVAC_SYNC_SHOW && fabs(wait_until - 400.9) < 1e-9);

    /* 8b. classify rejects invalid policy thresholds */
    CHECK(gvac_classify_frame(c, 1.0, 400.0, 0.0, -0.001, 0.040, &dec, &wait_until) == GVAC_ST_INVALID_ARGUMENT);
    CHECK(gvac_classify_frame(c, 1.0, 400.0, 0.0, 0.005, -0.040, &dec, &wait_until) == GVAC_ST_INVALID_ARGUMENT);
    CHECK(gvac_classify_frame(c, 1.0, 400.0, 0.0, NAN, 0.040, &dec, &wait_until) == GVAC_ST_INVALID_ARGUMENT);

    /* 9. invalid arguments */
    CHECK(gvac_anchor(c, 6, 0, 0, 500.0, 0.002) == GVAC_ST_INVALID_ARGUMENT);
    CHECK(gvac_anchor(c, 6, -5, 48000, 500.0, 0.002) == GVAC_ST_INVALID_ARGUMENT);
    CHECK(gvac_media_time(c, NAN, &out_d) == GVAC_ST_INVALID_ARGUMENT);

    /* 10. fence current generation: master lost until re-anchor (8.5 K3 path) */
    gvac_fence(c, 5);
    CHECK(gvac_media_time(c, 500.0, &out_d) == GVAC_ST_NO_MASTER);
    CHECK(gvac_anchor(c, 6, 0, 48000, 500.0, 0.002) == GVAC_ST_OK);
    CHECK(gvac_media_time(c, 500.0, &out_d) == GVAC_ST_OK);

    gvac_destroy(c);
    if (failures == 0) { printf("AUDIO_CLOCK_ALL_PASS\n"); return 0; }
    printf("AUDIO_CLOCK_FAILURES=%d\n", failures);
    return 1;
}

