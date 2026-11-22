"""191a C2: One Euro + Z hysteresis pose filtering. Python reference the Swift/Lua
pose path mirrors (existing Swift: ScreenCaptureEngine HeadTracker.OneEuro,
Casiez et al. 2012 with raw-sample speed; this module is the same math plus the
Z hysteresis the 191a lean-in/fov channel needs).

One Euro: cutoff = min_cutoff + beta*|speed|, speed low-passed at d_cutoff,
speed from RAW samples (not filtered - avoids counting the filter's own lag).
alpha(dt, c) = 1 / (1 + (1/(2*pi*c))/dt).

Z hysteresis (two-state schmitt): LOCKED, the committed Z holds (zero fov
jitter) until the filtered Z moves at least Z_ENTER_MM away; TRACKING, the
output IS the One Euro Z (no added lag, no steady-state offset) until the
filtered Z's speed stays under Z_SETTLE_MM_PER_S for Z_SETTLE_FRAMES
consecutive frames, then it re-locks on the settled value. A still head's Z
noise (sub-10 mm) can never open the gate; a real lean (tens of mm) passes
with One Euro's own lag only.

Constants below are MEASURED on the committed synthetic still/lean-in clip
(synth_pose_clip.py, seed 191): still-phase filtered Z jitter 0.000 mm (raw
sigma 8 mm), still yaw jitter 0.0040 rad around the true drift (raw sigma
0.02 rad), lean-in added lag 0.83 s past the true signal's own 90% time,
zero still-phase Z reversals, settles within 0.1 mm of the true 400 mm
(Tests/HeadPose/test_pose_filter.py reruns the measurement). SYNTHETIC,
provisional: re-measure against a real recorded Mac pose trace
(PoseTraceRing jsonl) when one exists - no real trace was committed at the
time of writing.

197i hold lock (HoldLock below), measured on synth_tilt_hold_clip.py across
seeds 197/5/42/7 x sigma .01/.02/.05 x 30/10 fps (24 configs,
Tests/HeadPose/test_hold_lock.py reruns): hold-phase jitter 0.000 rad at
low noise vs 0.001-0.008 unlocked (worst case equals the unlocked chain,
never worse); fast 0.5 rad tilt added latency +0.000 s (worst +0.100 s,
one 10 fps frame, extreme noise); slow 0.1 rad/s pan cost <= the band
(0.010 rad floor at low noise, 0.050 rad cap at high noise); post-move
offset <= the cap. The adaptive band tracks the measured noise (3x the
0.5 s wander via the AR factor 2.6-2.8, hence K = 8.1); the movement gate
keeps a slow pan from inflating it (mutant ungated: pan cost jumps to the
cap at every noise level).
"""
import math

STILL_CUTOFF_HZ = 0.35      # existing Swift constant (synthetic study, ScreenCaptureEngine)
TURN_CUTOFF_HZ = 2.0        # existing Swift constant
SPEED_FILTER_CUTOFF_HZ = 0.3
ANGLE_REF_SPEED = 1.0       # rad/s
BOX_REF_SPEED = 0.25        # box units/s
Z_MIN_CUTOFF_HZ = 1.0 / (2.0 * math.pi * 0.8)   # fovTauSeconds 0.8 (existing Swift)
Z_ENTER_MM = 15.0           # measured on the synthetic clip: still z_euro jitter
                            # ~1.5 mm, so 15 mm is ~10 sigma; never opens while still
Z_SETTLE_MM_PER_S = 5.0     # re-lock once the filtered Z is this calm...
Z_SETTLE_FRAMES = 10        # ...for this many frames (0.33 s at 30 fps)


def _alpha(dt, cutoff):
    tau = 1.0 / (2.0 * math.pi * cutoff)
    return 1.0 / (1.0 + tau / dt)


class OneEuro:
    """Exact mirror of ScreenCaptureEngine.swift HeadTracker.OneEuro."""

    def __init__(self, min_cutoff, beta, d_cutoff=SPEED_FILTER_CUTOFF_HZ):
        self.min_cutoff, self.beta, self.d_cutoff = min_cutoff, beta, d_cutoff
        self._has = False

    def reset(self):
        self._has = False

    def filter(self, x, t):
        if not self._has:
            self._has = True
            self._x_prev = self._x_raw_prev = x
            self._dx_prev = 0.0
            self._t_prev = t
            return x
        dt = min(max(t - self._t_prev, 1.0 / 240.0), 0.2)
        self._t_prev = t
        dx = (x - self._x_raw_prev) / dt
        self._x_raw_prev = x
        self._dx_prev += _alpha(dt, self.d_cutoff) * (dx - self._dx_prev)
        cutoff = self.min_cutoff + self.beta * abs(self._dx_prev)
        self._x_prev += _alpha(dt, cutoff) * (x - self._x_prev)
        return self._x_prev


class ZHysteresis:
    """Two-state schmitt on the filtered Z. LOCKED: hold the committed value
    (zero output jitter) until the input moves at least enter_mm away.
    TRACKING: pass the input through (no added lag or steady-state offset)
    until its speed stays under settle_mm_per_s for settle_frames frames."""

    def __init__(self, enter_mm=Z_ENTER_MM, settle_mm_per_s=Z_SETTLE_MM_PER_S,
                 settle_frames=Z_SETTLE_FRAMES):
        if not enter_mm > 0 or not settle_mm_per_s > 0 or settle_frames < 1:
            raise ValueError("need enter_mm > 0, settle_mm_per_s > 0, settle_frames >= 1")
        self.enter, self.settle, self.settle_frames = enter_mm, settle_mm_per_s, settle_frames
        self.reset()

    def reset(self):
        self._committed = None
        self._tracking = False

    def filter(self, z_filtered, t):
        if self._committed is None:
            self._committed = z_filtered
            self._prev, self._t_prev = z_filtered, t
            self._calm = 0
            return z_filtered
        dt = max(t - self._t_prev, 1e-6)
        self._t_prev = t
        speed = abs(z_filtered - self._prev) / dt
        self._prev = z_filtered
        if self._tracking:
            self._committed = z_filtered
            self._calm = self._calm + 1 if speed < self.settle else 0
            if self._calm >= self.settle_frames:
                self._tracking = False
                self._calm = 0
        elif abs(z_filtered - self._committed) >= self.enter:
            self._tracking = True
            self._calm = 0
            self._committed = z_filtered
        return self._committed


class PoseFilter:
    """Six-channel pose filter: One Euro on yaw/pitch/roll/x/y, One Euro +
    hysteresis on z (mm). Channel order matches HeadPose: yaw, pitch, roll,
    x, y, z_mm."""

    def __init__(self):
        self._ang = [OneEuro(STILL_CUTOFF_HZ,
                             (TURN_CUTOFF_HZ - STILL_CUTOFF_HZ) / ANGLE_REF_SPEED)
                     for _ in range(3)]
        self._box = [OneEuro(STILL_CUTOFF_HZ,
                             (TURN_CUTOFF_HZ - STILL_CUTOFF_HZ) / BOX_REF_SPEED)
                     for _ in range(2)]
        self._z_euro = OneEuro(Z_MIN_CUTOFF_HZ, 0.0)
        self._z_hyst = ZHysteresis()

    def reset(self):
        for f in self._ang + self._box:
            f.reset()
        self._z_euro.reset()
        self._z_hyst.reset()

    def filter(self, yaw, pitch, roll, x, y, z_mm, t):
        a = [f.filter(v, t) for f, v in zip(self._ang, (yaw, pitch, roll))]
        b = [f.filter(v, t) for f, v in zip(self._box, (x, y))]
        z = self._z_hyst.filter(self._z_euro.filter(z_mm, t), t)
        return a[0], a[1], a[2], b[0], b[1], z


# ---- 197i: output-side hold lock (gimbal) ----
# Measured on synth_tilt_hold_clip.py (constants pinned by
# Tests/HeadPose/test_hold_lock.py; see module docstring numbers there).
HOLD_ENTER_K = 8.1              # band = K * EMA|per-sample delta| * sqrt(settle_s/dt).
                                # Measured on the committed clip: the 0.5 s wander of the
                                # one-euro output is 2.6-2.8x mean|delta| * sqrt(0.5/dt)
                                # across 30/10 fps and sigma .01/.02/.05 (AR-scaling), and
                                # 3x wander keeps the lock closed under noise: 3*2.7 = 8.1.
HOLD_ENTER_FLOOR_RAD = 0.010    # clean-signal floor (~0.6 deg)
HOLD_ENTER_FLOOR_BOX = 0.005
HOLD_SETTLE_S = 0.50            # re-lock after the output stays within half the band this long
HOLD_NOISE_TAU_S = 0.6          # EMA time constant for the online |delta| estimate
                                # (time-based: 0.05/sample at 30 fps, cadence-robust)
HOLD_BAND_CAP_RAD = 0.05        # never freeze more than ~2.9 deg of travel
HOLD_BAND_CAP_BOX = 0.025
HOLD_MAD_GATE = 3.0             # noise EMA accepts deltas < 3x the estimate


class HoldLock:
    """Output-side hold lock, final stage after the existing chain. Two-state
    Schmitt per channel, the house pattern of the proven 191a Z hysteresis:
    LOCKED holds the committed value (zero output jitter); TRACKING passes
    the chain output through untouched (zero added lag, zero steady-state
    offset). Release on the FIRST sample at least `band` from the committed
    value, so a real movement pays no latency; the only cost is the sub-band
    displacement eaten at movement start. The band is adaptive:
    max(floor, ENTER_K * sigma_hat), capped, where sigma_hat is an online
    EMA of the upstream one-euro residual |raw - smoothed| - the exact
    quantity the committed synthetic study measures (residual 0.49-0.59x
    input sigma), so a noisy headset opens the band and a clean one
    tightens it, without any constant invented for a specific noise level.
    """

    def __init__(self, floor, k, settle_s, band_cap,
                 noise_tau=HOLD_NOISE_TAU_S):
        if not floor > 0 or not k > 0 or not settle_s > 0 or not band_cap >= floor \
                or not noise_tau > 0:
            raise ValueError("need floor>0, k>0, settle_s>0, cap>=floor, noise_tau>0")
        self.floor, self.k, self.settle_s = floor, k, settle_s
        self.cap, self.noise_tau = band_cap, noise_tau
        self.reset()

    def reset(self):
        self._committed = None
        self._tracking = True
        self._mad = None
        self._prev = None
        self._t_prev = None
        self._win_val = None
        self._win_t = None
        self.band = self.floor

    def filter(self, chain_out, t):
        if self._committed is None:
            self._committed = chain_out
            self._prev = chain_out
            self._t_prev = t
            self._win_val, self._win_t = chain_out, t
            return chain_out
        dt = min(max(t - self._t_prev, 1.0 / 240.0), 0.5)
        self._t_prev = t
        d = abs(chain_out - self._prev)
        self._prev = chain_out
        # Noise estimate: EMA of the per-sample |delta| of the chain output,
        # updated only from samples whose delta fits the current band.
        # Per-sample deltas are noise-dominated even during a slow pan
        # (measured: at 30 fps a 0.1 rad/s pan moves 0.003 rad/sample vs
        # ~0.005 rad/sample noise at sigma 0.02), unlike a windowed
        # residual which movement inflates ~10x. The band scales the
        # estimate to a 3x settle-window wander via the measured AR
        # cadence factor sqrt(settle_s/dt), so 30 fps and 10 fps both land
        # on 3x the actual wander (single K fits neither: 32 vs 17).
        if self._mad is None or d < HOLD_MAD_GATE * self._mad:
            # Gate against the noise estimate itself, not the band: a slow
            # pan's per-sample delta fits inside the noise-scaled band and
            # would otherwise inflate the band up to the cap (measured:
            # pan eat 0.048 ~= cap instead of the 0.023 the noise level
            # implies). 3x is ~3 sigma of the delta distribution; a
            # 0.1 rad/s pan at 30 fps is ~4.6x, so it is excluded.
            alpha = 1.0 - math.exp(-dt / self.noise_tau)
            self._mad = d if self._mad is None else \
                self._mad + alpha * (d - self._mad)
        if self._mad is not None:
            self.band = min(self.cap, max(
                self.floor, self.k * self._mad * math.sqrt(self.settle_s / dt)))
        if self._tracking:
            self._committed = chain_out
            # Re-lock on displacement stability: the chain output staying
            # within half the band of the window anchor for settle_s. A
            # per-sample speed test cannot separate high noise from a slow
            # pan (measured: 30 fps noise speed ~0.4 rad/s > pan 0.1 rad/s);
            # over settle_s the noise wanders < band/2 while a 0.1 rad/s
            # pan crosses it.
            if self._win_val is None or abs(chain_out - self._win_val) >= 0.5 * self.band:
                self._win_val, self._win_t = chain_out, t
            elif t - self._win_t >= self.settle_s:
                self._tracking = False
                self._committed = chain_out
        elif abs(chain_out - self._committed) >= self.band:
            self._tracking = True
            self._win_val, self._win_t = chain_out, t
            self._committed = chain_out
        return self._committed
