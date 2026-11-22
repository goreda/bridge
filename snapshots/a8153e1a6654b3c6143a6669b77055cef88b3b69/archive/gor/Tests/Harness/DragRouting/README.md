# Drag gesture and file routing harness

Run `bash gor/Tests/Harness/DragRouting/run.sh`. Python 3 only; reads current PPController_Features.swift and paired PPController.swift. No source snapshot fallback, AppKit events, actual file/font/torrent operations or UI output. Seven controls and three negative-source mutations cover gesture/screen admission and font/subtitle/torrent/image/ordinary media dispatch.

Source/model characterizations: identical URL list is suppressed across later deliberate gestures; subtitle-only drop calls stopTorrent before sub-add; image/torrent do not consume isFirst, so a following ordinary media file replaces; global monitor tokens are not retained/removed and repeated start would add more. Native consequences and repeated-start reachability are not established. Mixed-file intended routing remains an owner/product decision, not a guessed fix. Paired openMediaFile is media-level profile/reset/loadfile, not itself a font/subtitle classifier.

Priority: validate subtitle-only torrent continuity and same-file re-drop on native events, then constrain dedupe to one gesture and preserve media append behavior. Monitor teardown requires caller lifetime evidence. PASS retains expected counterexamples, not routing correctness clearance. No production patch, real UI inspection, engine or provider proof included.
