Harness assertion for W-0219 (run against the W-0218 packet harness + media):

1. For each film (480p -> ~1280 out, 1080p, 2160p -> ~1100 out) record: source height, output height, m = out/source, delivered PHOTON_SHARP_AMOUNT (HUD/observer), and whether sharp is enabled.
2. PASS requires: amount(480p) >= 1.5 * amount(2160p); m > 1 films produce a higher amount than the m = 1 baseline; m < 1 films produce a lower amount; no run shows amount 0 or sharpening silently off while enabled.
3. Record the backend (GPU or llvmpipe) and exact mpv/libplacebo versions per run; a llvmpipe-only result is not a real-GPU verdict.
