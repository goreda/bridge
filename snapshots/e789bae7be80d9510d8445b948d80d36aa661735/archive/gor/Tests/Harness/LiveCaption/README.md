# Live captions current-tree harness

Run `bash gor/Tests/Harness/LiveCaption/run.sh` from any directory. Requires Python 3 only. Reads the current gor/Sources/gor/LiveCaptionController.swift directly; missing current source fails. No historical fixture fallback.

Ten source guards and 28 model cases cover old pipe/process/partial/final callbacks after replacement in every order, stopped state, live callbacks, one failure notification and partial-line buffer clearing. Three removed current-source guard anchors are rejected. Matching tokens do not establish semantic parity after code changes; review the model when source changes.

This executes a Python lifecycle port, not Swift subprocesses, FileHandle callbacks, PCM threading, captions or UI pixels. Native ordering and renderer validation remain open. No production source changes. The prior portable scaffold was internal; this cell is its current-tree adaptation, not new native coverage.
