# Results of the reference derivation (geometric classes) on the fixture set (REPS=200 per cell, integer-rounded outlines)

Rates are fractions of fixture instances. "declared_true" = noise sigma supplied equal to the true sigma; "measured" =
sigma measured from the outline by measure_noise.

| metric | sigma 0 | 0.5 | 1 | 2 | 4 | (declared_true) |
|---|---|---|---|---|---|---|
| corner class correct | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | |
| extremum class correct | 1.000 | 0.995 | 0.994 | 0.994 | 0.990 | |
| seam class correct | 1.000 | 0.981 | 0.984 | 0.982 | 0.987 | |
| interior extremum found | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | |
| interior extremum false | 0 | 0 | 0 | 0 | 0 | |
| inflection found / false | 1.0 / 0 | 1.0 / 0 | 1.0 / 0 | 1.0 / 0 | 1.0 / 0 | |
| flat edge found | 1.000 | 0.999 | 0.998 | 0.996 | 0.998 | |
| flat edge false (per outline) | 0 | 0 | 0.017 | 0.057 | 0.137 | |

Corner detection by true turn angle (declared_true): turn 1 deg detected 1.00 / 0.89 / 0.28 / 0.06 / 0.02 at sigma 0 / 0.5 / 1 / 2 / 4;
2 deg: 1.00 / 1.00 / 0.92 / 0.39 / 0.07; 3 deg: 1.00 / 1.00 / 1.00 / 0.74 / 0.14; 5 deg: ... / 1.00 / 1.00 / 1.00 / 0.56;
8 deg: 0.95 at sigma 4; 12 deg and above: 1.00 everywhere. The limit is physical (a turn smaller than the noise-derived tolerance cannot be told from noise).
Closure (declared_true): a true gap of 0 is declared closed in 100% of cases; a true gap of 2 units is declared closed 0.00 / 0.77 / 0.99 / 1.00 / 1.00 at sigma 0 / 0.5 / 1 / 2 / 4;
a gap of 5: 0.00 / 0.00 / 0.27 / 0.94 / 1.00; a gap of 10: 0.00 / 0.00 / 0.00 / 0.21 / 0.94.

## Failure found with measured noise (same fixtures)
With measured noise the results degrade: extremum correct 1.00 / 0.90 / 0.81 / 0.71 / 0.61 and seam correct 1.00 / 0.82 / 0.62 / 0.39 / 0.28 at sigma 0 .. 4;
flat edge false rate about 0.05 at every sigma; the 1 degree wedge is missed (corner correct 0.917 at sigma 0).
Causes: (1) measure_noise accepts any line within about 1 degree of an axis as "axis-aligned", so a real 1 degree edge is read as noise (circular);
(2) noise from axis-aligned lines is under-estimated for sigma >= 0.5 (mean absolute error of the sigma estimate 0.15 / 0.42 / 0.54 / 0.88 / 1.86 at sigma 0 / 0.5 / 1 / 2 / 4);
(3) outlines without axis-aligned lines (ellipse, S curve) cannot be measured, noise_measurable is 0.895 at sigma 0 and 0.73 at sigma 4.
Conclusion: for a vector font the noise record should come from the font's coordinate grid or a declared value with its derivation, not from this line-mismatch estimate.
