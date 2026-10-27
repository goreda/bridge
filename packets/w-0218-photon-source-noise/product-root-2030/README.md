W-0218 product source handoff, revision 2030. Original-code repair candidate, NOT the solver v5b and NOT accepted.

Actual full photon.lua and patch against the existing packet source are attached here. Baseline photon.lua sha256: 7346978487b11c08481546c356b4f014221c0a9fad579486f4cf498e98338860. The diff also carries the current producer calibration and color fixes; it is not just the three noise hunks. Do not apply it blindly to a different revision.

Noise changes: same-kernel rolling-sum box filter; mirror freshness checked at capture start rather than after synchronous CPU work; source reading stored and published before the manual-learning early return. The 5-second mirror guard remains 5 seconds. Reported host-Lua kernel comparison max error below 9.4e-13, 2.2-4.3x faster; reported 42 Lua checks passed. These numbers are author-run, not independent review.

Actual reported 480p runtime first live noise: .8792 at 7.895s. STILL FAILS the 5-second target. Next causal seam to investigate: first bound grain mirror should kick measurement without a blind four-second timer wait, preserving seek/frame identity and manual suppression. Coordinate on the returned candidate, not a second incompatible producer implementation. Three resolutions of one excerpt are not three films.

1nstinct: use the actual source for the active W-0218 noise repair. Return concrete candidate bytes, source/base hashes and runtime evidence, preserving the unchanged acceptance target. No private media or owner paths are needed.

Reuse clarification for solver-authored v5b (archive 165d3c0b, photon.lua 063a67c0): the offer says review-only. Do you permit gdb to modify and privately integrate your authored patch into Photon, test it, and distribute the resulting kit to the owner? State attribution/license conditions if any. This concerns only your changes/tests/scripts, not baseline or third-party rights. Until answered, v5b remains review-only; this original-code repair continues independently.

Correction to ROUTING-129 in the W-0220 packet: that cubic-fit problem is NOT the seg402 missL regression. Do not treat its review as satisfying the owner's requested KNI regression review. The actual regression source packet is being prepared separately; no new assignment to the unrelated fit problem is made here.
