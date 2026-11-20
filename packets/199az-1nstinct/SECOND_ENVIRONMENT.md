# 199az - SECOND_ENVIRONMENT validation request for 1nstinct

State: request only, not accepted or started. This independent validation supplements, and does not replace, the primary Ops validation. No owner Mac/runtime access is available in this environment.

## CROP v9

**Candidate chain**
- Parent: `644b9e088813ab101cb41abdc1efd60043c55514`
- `d12fba48f8f100906123e5488ad48526382f5d65` is an initial patch, not final: same-commit emits are missing.
- `f7142464afcd8ae647bed350b313262dd6e453fa` is intermediate, not final: same-commit emit was added, but `Source.current_sha256` needs repinning and `update_integrity` is RED.
- Do not accept either intermediate. Require the exact final candidate SHA and parent before testing.

**Acceptance gates**
1. Verify exact final patch SHA and parent.
2. Run `manifest_tree` and production `update_integrity` checks first.
3. Run full `Tests/CropDetect/run_all.py` discovery with the exact compiler; retain full results.
4. Compile the actual changed Swift scheduling policy, or the full Darwin target if available. A Python mirror is not native proof.
5. Reproduce the reported base-versus-candidate architecture-emission result separately. The candidate reportedly has 209 baseline-count failures; do not waive failing gates.
6. Verify retry timing at 2, 5, 10, and 30 seconds, with no give-up after 60 seconds.
7. Verify immediate scan restart on seek, track switch, dimension/aspect change, and magnet-buffer growth past the scanned range.
8. Confirm the full picture remains visible until consistent agreement; widening-only behavior, manual-crop ownership, and black-threshold behavior remain unchanged.

**Semantic risks to resolve**
- The seek path clears a pending retry record but does not cancel/reset the detector's last-file latch.
- The initial patch has no track-switch handler for immediate restart.
- A retry timer armed before pause may fire after pause; the retry callback does not check `isPlaying`.
- `lastSeekableEnd` is not reset for a new file and may carry across files.

## BLINK normal playback

**Candidate**
- Branch: `blink/b4-normal-playback`
- Parent: `644b9e088813ab101cb41abdc1efd60043c55514`
- Candidate: `3f82344838cf6f582eaa049ab1061e3cb4160df5`
- Five-path patch with targeted delivery emit.

**Acceptance gates**
1. Inspect the removal of the VR requirement from `blinkShouldRun`, while preserving `blinkOn`, `loadedVideoActive`, and `cameraAllowed` checks.
2. Confirm `VR180Controller` and `pp-split-manifest` are unchanged and exactly reconstructed.
3. Run `Tests/BlinkEntryRouting/normal-playback.py`; report the pristine-base RED and patched result. A prior report claimed pristine RED and 17 patched PASS under Swift 6.0.3 on Linux; independently reproduce it.
4. Compare `Tests/BlinkRoute/current_route.py` on base and candidate; classify whether the six base compiler errors are pre-existing or new.
5. Confirm projection OFF does not suppress independent blink behavior.
6. Native camera, permissions, and recognizer behavior remains NOT_RUN unless directly evidenced.

## Report back

Include the exact tested candidate SHA and parent, commands, compiler/toolchain, exit codes, raw logs and hashes, and new-versus-base RED classification. Clearly label all unrun native checks. This is a validation request only; do not merge or deliver product changes.
