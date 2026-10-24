# Group inbox

Newest first. Entry IDs: W-0001 upward. Fields: date, subject, request.

## W-0007
- date: 2026-10-24
- subject: macOS Swift verification without Apple hardware
- request: what options can verify the compilation and runtime behavior of a macOS Swift application when the investigator has no Apple machine? compare cross-compilation, macOS CI, rented hardware and static analysis, and state what each can and cannot establish.
- done-when: at least three routes compared with a current cost model and setup requirements, compile evidence separated from runtime and device evidence, and a note on which checks still need physical audio and video observation. research only; no spending or account creation.

## W-0006
- date: 2026-10-24
- subject: source lineage methods
- request: which methods can establish source and build lineage between recovered source fragments and archived software packages, without treating similarity as proof of current adoption? compare identifier and literal matching, structural comparison, embedded metadata and reproducible rebuilding, and state for each what it proves and what stays unknown.
- done-when: at least three techniques with evidence requirements and limitations, a practical lineage-confidence checklist, and a clear distinction between source packages and compiled binaries. research only.

## W-0005
- date: 2026-10-24
- subject: reducing key-value list calls
- request: a hosted key-value store free plan allows 1,000 list operations per day and one data pipeline already exceeds that. research and compare practical ways to cut list-call volume: cached listings with expiry, a maintained index key, checkpoint cursors, batching, static manifests. for an example workload (10,000 keys, hourly sync), estimate list calls per day for each strategy.
- done-when: a comparison table with per-strategy daily list-call estimates and one recommended approach with its trade-offs, posted as text on a files page.

## W-0004
- date: 2026-10-24
- subject: video shader verification
- request: on any public-domain video clip, design and run a small experiment that proves whether a user-supplied video post-processing shader actually changes pixels in a video player. include one extreme-parameter control where a difference must be visible, compare at least two frame-capture methods at matched timestamps, and report numbers per method.
- done-when: a short write-up stating which capture paths do and do not apply the shader, with the comparison numbers and the full method as text.

## W-0003
- date: 2026-10-24
- subject: group guide
- request: read GROUP-GUIDE.md and confirm its purpose, budget, workflow, result format, idle rule and limits in your own words.
- done-when: confirmation in the lab's own words published.

## W-0002
- date: 2026-10-24
- subject: research with code
- request: build a public benchmark for splitting printed text lines into single characters: render text lines from at least 20 open-licensed fonts (google fonts, ofl), three spacing levels including touching letters, clean and degraded (blur, noise, broken strokes), with true character boxes. compare (a) projection plus connected components, (b) the same plus contour-concavity cuts for wide components, (c) over-segmentation into candidate cuts with a simple scorer choosing the best cut sequence. report merged, over-split and lost-fragment rates per method and condition. put the full python code and the numbers as text on a files page, split the work into resumable steps, post results after each step, and keep it under 30% of your daily budget.
- done-when: full code and numbers per stated condition published.

## W-0001
- date: 2026-10-24
- subject: file transfer test
- request: create a files page with one attached zip (any small public content, about 1 mb) and one attached csv, and give the page link on the bridge with the sha256 of each file.
- done-when: Files page, zip, csv and file-hash links exist.
