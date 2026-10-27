# Photon sharp upscale curve (118g) - problem packet v1

Delivery id: photon-sharp-curve-118g-v1. One W id is retained through every round. State: candidate; the delivered fix claim is NOT independently verified, not accepted.

Problem (what fails, for the user): owner block 118 addendum item 118g, on the owner log 2026-10-27 14:24:49-14:32:17 UTC (pre-fix code): sharp was "attenuation only" - the 480p film upscaled 2.7x got amount 0.78 while the 4k film downscaled got 0.88; "the 480p film upscaled 2.7x gets less sharp, not more. the difference is invisible." Owner requirement: remove "attenuation only". Upscale raises the amount, downscale lowers it. Harness assertion: the amount for 480p shown at about 1280 must be at least 1.5 times the amount for 4k shown at about 1100.

Current candidate claim (to be challenged, not trusted): the private 118 candidate source carries a ps_refresh_adaptive change (photon-sharp.lua) computing m = output height / source height, multiplier = clamp(r^0.5, 0.5, 2.0) applied to AMOUNT only, m = 1 -> 1.0 at native size. A single 2026-10-27 19:20 llvmpipe harness run reported per-film amounts 480p 3.0601 / 1080p 0.8591 / 2160p 0.5566 (ratio ~5.5). That is a one-backend self-report on software rendering, not independent verification; real-GPU behavior, failure coverage and the owner's visual acceptance are open.

Reproducer (real source at a named commit): source/photon-sharp.lua sha256 fc460715970776cbc691ecac0b3f61dcfbfaacf8aa21a0e5f6a07cf28c93a647 and source/photon-common.lua sha256 220fa27b886187d69d839a3c67ed3b32d9836bcc748a6535db1a956004082ce6 (R40 supplied file, unchanged), anchored at goreda/instinct branch photon-118-candidate-20261027 commit bdeb4611ff8ddabcfbf89e33e1f1b9e21ff6d6c6, projects/photon/118-candidate-source/. Fixtures and base harness are the already-published W-0218 public media (480p sha256 74fcb562..., 1080p f2d9f7ea..., 2160p c3fbe3fe...) and harness at packets/w-0218-photon-source-noise/{media,harness}. Run: MPV=/absolute/path/to/mpv sh harness/run.sh from the W-0218 packet, then read the per-film sharp amount and m from the observer/HUD rows.

Expected behaviour: upscale raises the sharp amount, downscale lowers it, 1:1 keeps the delivered look; the harness assertion amount(480p@~1280) >= 1.5 x amount(4k@~1100) holds on every run; no zero or silent-off sharpening while sharp is enabled.

Exact call site and interface: ps_refresh_adaptive in photon-sharp.lua (geometric multiplier, fed by common.adaptive_rasters source/output heights); application point photon_sharp_push_params -> PHOTON_SHARP_AMOUNT = photon_sharp_strength_rendered * ps_multiplier. FACTOR stays geometry-free (no double-scaling).

Behaviour that must not change: saved look at 1:1; manual floor/ceiling shortcut values stay manual-only and must not feed adaptive measurement; the 118c visual range; grain behavior (the noise feed is W-0218, do not touch it here); the fine/coarse character tier; no new owner-visible gates or thresholds without the owner's own words.

Acceptance test from the product side: the numeric harness assertion above plus reviewer failure cases written blind BEFORE reading any solver fix: 1:1 native size, extreme upscale (>2.7x), extreme downscale, window resize mid-playback, anamorphic SAR != 1, manual floor/ceiling override interplay, scene cut / seek stability, sharp disabled/enabled toggle. Neither lab approval is product acceptance; acceptance remains the owner's eyes.

Roles (123d, swapped from W-0218): solver lab in2tinct writes the verification/fix + regression test; reviewer lab 1nstinct writes the failure cases first, then reviews. state: candidate.

secret scan: clean
