"""197i: cadence-aware double-blink detection - measurement model.

Root cause this models (measured, 196v commit a06b8f88 record): under thermal
pressure the helper admits the blink landmark pass on every 5th gated frame
(~2 Hz at the 10 fps thermal floor; head cadence untouched). The shipped
EyeGestureCommands gates are fixed at a 30 fps assumption: a frame gap over
maxFrameGap 0.300 s cancels the state machine and a frame older than 0.300 s
is not fresh, so at 2 Hz the detector resets on literally every sample and
the double-blink seek can never fire, at any blink speed.

Policy layers measured here:
  P0 shipped gates (baseline).
  P1 cadence-derived gates: gap/freshness/episode limits scale with the
     measured sample interval (median of recent gaps), floors unchanged, so
     30/10 fps behaviour is byte-identical to P0.
  P2 P1 + escalation: a closure edge or a completed first blink requests a
     boost window; during boost the helper admits every frame (10 fps at the
     floor), so the episode that matters resolves at full cadence. Extra
     Vision passes are counted per double-blink (heat cost).
  P3 P2 + low-cadence episode bound: at cadence > blinkMax/2 a one-sample
     closure's observed duration is the sample interval, so the duration
     ceiling scales with cadence instead of rejecting everything above
     blinkMax.

Blink physiology (literature range already pinned in Swift): spontaneous
blink 0.10-0.40 s. Generators sweep closure durations and inter-blink gaps
("he tried many speeds") with randomized phase against the sample grid.
Negatives: single blinks, long holds, partial squints, landmark dropouts.
"""
import math
import random
import statistics

# ---- shipped constants (pinned to Sources/gor/Camera/HeadPose.swift EyeGestureCommands) ----
SERIES_WINDOW = 1.200
BLINK_MIN = 0.025
BLINK_MAX = 0.600
MAX_FRAME_GAP = 0.300
CLOSE_BELOW = 0.50
OPEN_ABOVE = 0.65
OPEN_DWELL = 0.030
TOLERATED_MISSES = 2
VISION_MS = 0.047          # 196v measured average blink landmark pass
BOOST_EXTRA_CAP_S = 1.5    # hard ceiling on one boost window


class GestureP0:
    """Line-for-line port of shipped EyeGestureCommands (robust defaults)."""
    def __init__(self):
        self.bl, self.br = [], []
        self.start = self.lastT = self.openSince = self.lastAt = None
        self.misses = 0
        self.boost_until = None

    def cancel(self):
        self.start = self.lastAt = self.openSince = None

    @staticmethod
    def _med(v):
        return sorted(v)[len(v) // 2]

    def feed(self, t, l, r, reliable=True, age=0.0):
        prev, self.lastT = self.lastT, t
        fresh = 0 <= age <= MAX_FRAME_GAP
        if not (reliable and fresh and l is not None and r is not None):
            self.misses += 1
            if not (fresh and self.misses <= TOLERATED_MISSES):
                self.cancel()
            return None
        self.misses = 0
        if prev is not None and (t - prev > MAX_FRAME_GAP or t <= prev):
            self.cancel()
            return None
        if len(self.bl) < 12:
            if l > 0 and r > 0:
                self.bl.append(l); self.br.append(r)
            return None
        lr, rr = l / max(self._med(self.bl), 1e-9), r / max(self._med(self.br), 1e-9)
        closed = lr < CLOSE_BELOW and rr < CLOSE_BELOW
        opened = lr > OPEN_ABOVE and rr > OPEN_ABOVE
        if self.lastAt is not None and t - self.lastAt > SERIES_WINDOW:
            self.lastAt = None
        if opened:
            if self.openSince is None:
                self.openSince = t
            self.bl.append(l); self.br.append(r)
            if len(self.bl) > 121:
                self.bl.pop(0); self.br.pop(0)
            if self.start is not None:
                st, self.start = self.start, None
                if not (BLINK_MIN <= t - st <= BLINK_MAX):
                    self.lastAt = None
                    return None
                if self.lastAt is not None:
                    self.lastAt = None
                    return 60
                self.lastAt = t
            return None
        if not closed:
            if self.start is not None and t - self.start <= BLINK_MAX:
                return None
            self.start = None
            return None
        if self.start is None:
            if self.openSince is None or t - self.openSince < OPEN_DWELL:
                return None
            self.start = t
            self.openSince = None
        return None


class GestureP3(GestureP0):
    """Cadence-derived gates + boost signal + low-cadence episode bound.

    Same state machine as P0; every fixed second constant that encodes a
    30 fps sampling assumption is replaced by max(shipped, k * cadence)
    with cadence = median of the last 7 usable sample intervals. At 30 fps
    (0.033 s) and at the 10 fps thermal floor (0.1 s) every max() selects
    the shipped constant, so behaviour there is byte-identical to P0; only
    the throttled 2 Hz regime changes. k values measured by the replay test.
    """
    GAP_K = 1.25        # one missing sample never cancels; a true stall still does
    FRESH_K = 0.75      # the freshest frame at 2 Hz is ~0.5 s old and still current
    EPISODE_K = 1.25    # one-sample closure bound at low cadence
    SERIES_FLOOR = 0.1  # extension starts above the 10 fps thermal-floor cadence
    SERIES_K = 1.0      # beyond that the window extends by the extra interval
    SOFT_BELOW = 0.80   # weak closure edge: lid falling but above closeBelow

    def __init__(self):
        super().__init__()
        self.gaps = []
        self.soft_armed = True

    def _cadence(self):
        usable = self.gaps[-7:]
        if len(usable) < 3:
            return None
        return statistics.median(usable)

    def _limits(self):
        c = self._cadence() or 0.0
        return (max(MAX_FRAME_GAP, self.GAP_K * c),
                max(MAX_FRAME_GAP, self.FRESH_K * c),
                max(BLINK_MAX, self.EPISODE_K * c),
                SERIES_WINDOW + self.SERIES_K * max(0.0, c - self.SERIES_FLOOR))

    def cancel(self):
        super().cancel()
        self.boost_until = None

    def feed(self, t, l, r, reliable=True, age=0.0):
        gap_limit, fresh_limit, blink_max, series = self._limits()
        prev, self.lastT = self.lastT, t
        fresh = 0 <= age <= fresh_limit
        if not (reliable and fresh and l is not None and r is not None):
            self.misses += 1
            if not (fresh and self.misses <= TOLERATED_MISSES):
                self.cancel()
            return None
        self.misses = 0
        if prev is not None:
            gap = t - prev
            # Bootstrap: with fewer than 3 measured intervals there is no
            # cadence estimate, so a slow stream must not cancel yet (the
            # shipped gate cancels every sample at 2 Hz and the 12-sample
            # baseline never fills - measured: baseline stuck at 1 sample).
            if len(self.gaps) >= 3 and (gap > gap_limit or t <= prev):
                self.cancel()
                return None
            self.gaps.append(min(gap, 1.0))  # clamp: a stall must not inflate the estimate
            if len(self.gaps) > 21:
                self.gaps.pop(0)
        if len(self.bl) < 12:
            if l > 0 and r > 0:
                self.bl.append(l); self.br.append(r)
            return None
        lr, rr = l / max(self._med(self.bl), 1e-9), r / max(self._med(self.br), 1e-9)
        closed = lr < CLOSE_BELOW and rr < CLOSE_BELOW
        opened = lr > OPEN_ABOVE and rr > OPEN_ABOVE
        if self.lastAt is not None and t - self.lastAt > series:
            self.lastAt = None
            if self.boost_until is not None and self.start is None:
                self.boost_until = None
        if opened:
            if self.openSince is None:
                self.openSince = t
            if t - self.openSince >= OPEN_DWELL:
                self.soft_armed = True
            self.bl.append(l); self.br.append(r)
            if len(self.bl) > 121:
                self.bl.pop(0); self.br.pop(0)
            if self.start is not None:
                st, self.start = self.start, None
                if not (BLINK_MIN <= t - st <= blink_max):
                    self.lastAt = None
                    return None
                if self.lastAt is not None:
                    self.lastAt = None
                    self.boost_until = None
                    return 60
                self.lastAt = t
                # A completed first blink: hold full cadence for the series window
                self.boost_until = t + series
            elif self.boost_until is not None and self.start is None and self.lastAt is None:
                self.boost_until = None   # episode resolved, eyes open
            return None
        if not closed:
            if self.start is not None and t - self.start <= blink_max:
                return None
            self.start = None
            # Weak edge: lid clearly falling but not yet below closeBelow.
            # At 2 Hz a 0.2 s closure is sampled only ~1/3 of the time
            # (measured), so boost on the falling edge too; re-arms only
            # after a clean open sample, so a held squint boosts once.
            if self.soft_armed and self.openSince is not None and min(lr, rr) < self.SOFT_BELOW:
                self.soft_armed = False
                self.boost_until = t + max(0.4, 2.0 * (self._cadence() or 0.0))
            return None
        if self.start is None:
            if self.openSince is None or t - self.openSince < OPEN_DWELL:
                return None
            self.start = t
            self.openSince = None
            # Closure edge: hold full cadence until the episode resolves
            self.boost_until = t + blink_max + 2 * (self._cadence() or 0.0)
        return None


# ---- sampling pipeline simulator ----
def pipeline_samples(duration, base_fps, pressure, detector=None, truth=None,
                     stride=5, seed=0, lag_s=VISION_MS):
    """Yield the (t_sample, age) pairs the detector receives.

    base_fps: capture grid (30 cool, 10 at the thermal floor per the 196v record).
    pressure: 1-in-5 blink admission when no boost is active (196v stride).
    truth(t) -> (l, r, reliable): ground-truth lid ratios at time t.
    Boost: when the detector sets boost_until, following frames are all admitted
    until that time (helper behaviour wired by the blink-boost command).
    Returns (samples, admitted_count, base_count) for the heat-cost metric.
    """
    rnd = random.Random(seed)
    samples = []
    admitted = 0
    n = int(duration * base_fps)
    for k in range(n + 1):
        t = k / base_fps
        boosted = detector is not None and detector.boost_until is not None and t <= detector.boost_until
        if pressure and k % stride != 0 and not boosted:
            continue
        admitted += 1
        l, r, reliable = truth(t)
        # feed immediately so the detector's boost decision affects the next frame
        if detector is not None:
            detector.feed(t + lag_s, l, r, reliable, age=lag_s)
        samples.append((t + lag_s, l, r, reliable))
    return samples, admitted, n + 1


def make_truth(blinks, open_ratio=1.0, closed_ratio=0.15, ramp_s=0.03,
               ear_sigma=0.02, dropouts=(), seed=0):
    """blinks: list of (t_close, t_reopen). dropouts: iterable of (t0, t1) unreliable spans."""
    rnd = random.Random(seed)

    def truth(t):
        ratio = open_ratio
        for (c, o) in blinks:
            if c <= t < o:
                if t - c < ramp_s:
                    ratio = open_ratio - (open_ratio - closed_ratio) * (t - c) / ramp_s
                elif o - t < ramp_s:
                    ratio = closed_ratio + (open_ratio - closed_ratio) * (o - t) / ramp_s
                else:
                    ratio = closed_ratio
                break
        l = max(0.0, ratio + rnd.gauss(0, ear_sigma))
        r = max(0.0, ratio + rnd.gauss(0, ear_sigma))
        reliable = not any(a <= t < b for a, b in dropouts)
        return l, r, reliable
    return truth


def run_case(policy, base_fps, pressure, blinks, duration=8.0, seed=0, dropouts=()):
    det = policy()
    truth = make_truth(blinks, dropouts=dropouts, seed=seed)
    events = []
    n = int(duration * base_fps)
    admitted = 0
    for k in range(n + 1):
        t = k / base_fps
        boosted = det.boost_until is not None and t <= det.boost_until
        if pressure and k % 5 != 0 and not boosted:
            continue
        admitted += 1
        l, r, reliable = truth(t)
        ev = det.feed(t + VISION_MS, l, r, reliable, age=VISION_MS)
        if ev is not None:
            events.append((t, ev))
    return events, admitted, n + 1


def phase_sweep(policy, base_fps, pressure, blinks_fn, trials=40, **kw):
    """blinks_fn(phase) -> blink list; returns (catch_rate, avg_extra_passes)."""
    caught = 0
    extra = 0
    for i in range(trials):
        phase = i / trials / base_fps
        blinks = blinks_fn(phase)
        events, admitted, total = run_case(policy, base_fps, pressure, blinks, seed=i, **kw)
        if any(v == 60 for _, v in events):
            caught += 1
        extra += (admitted - (total // 5 if pressure else total))
    return caught / trials, extra / trials
