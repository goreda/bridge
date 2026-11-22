# Content-adaptive dimming control harness

Run `bash gor/Tests/Harness/ContentDimming/run.sh`. Python 3 only, current PPController_Features.swift required. No snapshot fallback, luminance capture, screenshots, timer/hardware brightness writes, Swift or UI execution. No production edit or CPU/heat benefit claim.

Controls preserve current intended policy: 404 normalized content/ambient target combinations bounded in [0.75,1], content/ambient monotonicity, cut-threshold clamps, two-candidate confirmation, steady no-cut, endpoint/monotonic micro steps, stale-generation suppression, external-fade arbitration and adaptive cut-duration floor/saturation at 60/120/240Hz. Three source mutations fail.

Characterizations: disabling runtime during an existing micro-step does not invalidate its generation/timer and the callback checks generation/fade, not runtimeEnabled; failed captures reuse prior luma without an age limit; calm capture cadence widens to four scene ticks (designed bounded policy, not a defect). Native disable ordering/visible effect and correct fallback duration remain unverified. No speculative replacement of intended dimming for lower work.

Priority handoff: validate runtime-disable brightness ownership and clear/invalidate only the old micro-step while preserving fade arbitration, target range and cut behavior. Stale cached capture policy needs a product/native evidence decision. PASS means arithmetic/state controls and characterizations reproduced, not display, timing, image or thermal correctness clearance.
