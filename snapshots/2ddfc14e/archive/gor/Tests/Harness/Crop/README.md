# Crop current-tree arithmetic and golden corpus harness

Install requirements.txt in an isolated Python environment, then run `bash gor/Tests/Harness/Crop/run.sh`. No package installation or network request is performed by the runner. Reads current gor/Sources/gor/PPController.swift directly, with no old-source fallback. Includes 21 synthetic scenario families and 112 previously visually inspected, unchanged PNGs, with hashes.

Current source anchors cover 960px raster limit, black occupancy/signatures, WT budgets, axis quorum and symmetric margins. Python ports use 960px fixtures without resizing, so no CoreGraphics interpolation equivalence is claimed. All observed frames are analyzed after modeled first lock for characterization; this is not what the production accumulation loop does after finish.

PASS means normal controls and expected known-red counterexamples reproduced. It does NOT mean crop correctness: moving title-card false crop, four-vote aspect-change early lock and narrow-subtitle 567 removed bright pixels remain red. Assertions intentionally keep those failures visible; do not erase them to make a cosmetic green run. Source changes require semantic port review, not merely token agreement. Two mutated current-source anchors were rejected.

No production edit or ready track-2 redesign. Native CGImage pixels/colorspace/scaling, screenshot/mPV path, actual UI crop, real media, manual mode and timing remain open. Historical PNGs are fixtures, not current-source evidence. No new visual asset was produced; fixtures were reused unchanged.
