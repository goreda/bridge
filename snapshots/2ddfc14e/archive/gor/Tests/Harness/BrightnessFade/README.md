# Brightness fade ownership harness

Run `bash gor/Tests/Harness/BrightnessFade/run.sh`. Python 3 only, current PPController.swift required. No snapshot fallback, hardware writes/reads, actual timer, Swift or UI execution. Separate from ContentDimming scene target/cut calculation.

Five controls preserve 36-step monotonic easing endpoints, normal replacement generation, teardown cancellation, immediate near-target completion and configured durations (arithmetic only). Three source mutations fail. Counterexample: near-target early return precedes generation invalidation, so a replacement can complete while older scheduled fade remains active and later writes its old endpoint. Quit restore can take the same branch. Native shutdown/Dispatch/Float/hardware ordering is unverified, not an observed display incident.

Priority handoff: retire old generation before near-target completion while preserving normal endpoints/completion, user override and quit behavior. No production patch included. DisplayServices/display identity, read failures, monitor integration and actual timing remain open. PASS is source/port consistency with retained counterexamples, not hardware correctness.
