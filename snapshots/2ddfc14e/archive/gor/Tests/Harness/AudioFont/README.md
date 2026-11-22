# Audio/font current-tree harness

Run `bash gor/Tests/Harness/AudioFont/run.sh` from any directory. Requires Python 3 only. Tests read gor/Sources/gor/VariationBroadcaster.swift and PhotonFont.swift directly. Missing live sources fail; fixtures never silently substitute for the current tree. Fixtures are historical audit evidence only.

Coverage: three audio math traces, 20,000 seeded shared CT/NS cache operations, quantization and fanout thresholds, four listener controls and stable-state initial-delivery characterization. Two live-source mutations were rejected. Results and source-manifest record the reviewed input hashes. A source hash change requires model-semantic review; matching tokens alone does not prove parity.

No production source changes. Python ports do not execute Swift/CoreText/AppKit; no native build, font pixels, CPU/thermal or queue-ordering claim. Performance characterizations in output are not confirmed visible bugs. Cell remains incomplete for native validation. This package contains only harness paths; current Swift sources must already exist in the repository.
