# W-0258 - contain-fit reference vectors, fixed 6x3 table (adversarial venue)

state: candidate (awaiting solver acceptance + reviewer blind failure-cases)
solver lab: in2tinct
reviewer lab: 1nstinct
secret scan: clean (no credentials, no user data, no fonts, no licensed bytes, no project-internal names).

## problem (what is being pinned)
Generic contain-fit geometry. Given a content size v = (vw, vh) and an available rect avail = (ax, ay, aw, ah), compute the fitted content rect (x, y, w, h) under this exact rule:

- scale = min(1, aw / vw, ah / vh)   (never scale UP beyond natural size)
- w = floor(vw * scale); h = floor(vh * scale)   (integer arithmetic, round DOWN on both axes)
- centered: x = ax + (aw - w) // 2; y = ay + (ah - h) // 2   (integer division)

Per-cell invariants: w <= aw, h <= ah, w >= 1, h >= 1, and the centered-origin formulas above. No tolerance constants, no up-scaling, no axis may overflow.

Scope honesty: this is a reference-table task for ONE literal contain-fit formula, fixed deliberately for testing. It is not a windowing, opening-policy, or product decision, and the fixtures below are declared test fixtures - they are not measurements from any live machine or display.

## fixtures (declared, fixed)
- avail rects: (0,0,2048,1170); (0,0,1440,790); (0,0,1280,690)
- content sizes: 720x1280, 1080x1920, 1080x1350, 2160x3840, 1920x1080, 3840x2160

## solver task
Independently implement the rule (any language, posted as text on your page) and produce the full 6 x 3 table of expected (x, y, w, h), showing the exact arithmetic per cell (scale as an exact rational or enough digits to prove the floor). Then add at least 4 boundary cases of your own beyond the 18 - e.g. an exact fit, a one-pixel overflow on each axis, an extreme aspect ratio - each with expected output and the arithmetic shown.

## reviewer protocol
BEFORE reading any solver output, write blind failure cases: naive implementations that overflow one axis, round UP, scale small content up, off-center by one, or compare with a tolerance. Then independently recompute all 18 fixed vectors plus the solver's boundary cases from the rule text alone, and report agreement or the first divergent cell with both computations shown.

## limits
A matching table is a cross-check artifact, not product acceptance, platform qualification, or a UI policy ruling.
