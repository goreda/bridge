# PHOTON-ADAPTIVE-V4 candidate interface v1

This is a draft calibration contract, not owner-verified appearance or rendered acceptance. Output RGB is in the caller's documented working signal domain. HDR and transfer metadata must be explicit; no inference from pixel max>=1. Measurement is decoded/pre-sharp/pre-grain, not a post-render screenshot.

A frame invocation provides:

- input texture: immutable decoded picture, RGBA32F test harness; production stage may supply separate luma planes.
- pictureRect: x/y/width/height in output pixels, excluding bars. Pixels outside this rect are passed through; pixels inside use no flat-area variance gate.
- sourcePictureHeight and pictureOutputHeight: positive finite values, picture only, never window size with bars.
- sourceCellPixels and measurementConfidence: source-matched if source estimate is valid/confident, else lookFraction of picture height. Source-matched output=max(0.6, sourceCellPixels*pictureOutputHeight/sourcePictureHeight); look output=max(0.6,lookFraction*pictureOutputHeight). No resolution class rails.
- enabled, ownerAmount, ownerStrength and sizeTrim: explicit zero disables only when owner sets it. Negative/nonfinite input is rejected; not silently defaulted.
- targetSigmaKnots[8] and sourceSigmaKnots[8], lumaKnots[8]: piecewise-linear sigma in normalized luma signal units, finite nonnegative. Repeated/decreasing knot positions refuse. source sigma was measured in same domain as target.
- minimumAddedFraction: default0.35. Added sigma=max(sqrt(max(targetSigma^2-sourceSigma^2,0)),minimumAddedFraction*targetSigma), before owner positive scales. Metadata compressionFactor >=1 multiplies target exactly once, not source subtraction. Grain enabled+positive owner scales require positive target curve; zero target is refused unless explicitly disabled.
- transfer: SDR/PQ/HLG enum supplied by stream metadata; exposure/tonemap conversion belongs to stage owner and cannot be guessed here.
- seed and frameBucket: integer deterministic keys. Identical texture/rect/parameters/seed/bucket give identical output. No wall clock.
- mono: bit-identical RGB field for B&W; otherwise declared correlation, no hidden scene factor.

GPU stage order proposal: decoded signal -> PhotonSourceMeasurement -> existing color/HDR handling per agreed domain -> sharp -> grain -> output. The grain measurement input never contains sharp or grain. P22 receives measurement luma-bin sigma, sourceCellPixels, confidence and source binding; stale binding refuses.

The first runnable EGL harness will use an extracted/generated fragment body with exactly these named scalar/vector uniforms and RGBA32F offscreen output; both Lua and Swift generator emit the same source bytes. Do not wire this draft into shipping P22 by guessed offsets. Layout packing is versioned separately after lane-c approval.
