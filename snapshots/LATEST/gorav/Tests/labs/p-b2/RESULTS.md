# P-B2 RESULTS

## Toolchain

```
Swift version 6.0.3 (swift-6.0.3-RELEASE)
Target: x86_64-unknown-linux-gnu
ffmpeg version 4.4.2-0ubuntu0.22.04.1 (fixture generation only)
```

## Test run: swift test (full output, unedited)

```
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--765BFAE554EA7E2B.txt
Build complete! (0.21s)
Test Suite 'All tests' started at 2026-11-06 20:57:46.337
Test Suite 'debug.xctest' started at 2026-11-06 20:57:46.356
Test Suite 'ParityRunnerTests' started at 2026-11-06 20:57:46.356
Test Case 'ParityRunnerTests.testDifferentStubsStayVisible' started at 2026-11-06 20:57:46.356
Test Case 'ParityRunnerTests.testDifferentStubsStayVisible' passed (0.002 seconds)
Test Case 'ParityRunnerTests.testEqualStubsPassAndRoundTrip' started at 2026-11-06 20:57:46.358
Test Case 'ParityRunnerTests.testEqualStubsPassAndRoundTrip' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testErrorIsExplicitAndPeerUnavailable' started at 2026-11-06 20:57:46.358
Test Case 'ParityRunnerTests.testErrorIsExplicitAndPeerUnavailable' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testEscapingKeepsRowsIntact' started at 2026-11-06 20:57:46.358
Test Case 'ParityRunnerTests.testEscapingKeepsRowsIntact' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testHeaderAndRowShape' started at 2026-11-06 20:57:46.358
Test Case 'ParityRunnerTests.testHeaderAndRowShape' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testMissingValuesBecomeNAAndUnavailable' started at 2026-11-06 20:57:46.359
Test Case 'ParityRunnerTests.testMissingValuesBecomeNAAndUnavailable' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testNonFiniteSeekTargetThrows' started at 2026-11-06 20:57:46.359
Test Case 'ParityRunnerTests.testNonFiniteSeekTargetThrows' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testNumberFormattingRoundTrips' started at 2026-11-06 20:57:46.359
Test Case 'ParityRunnerTests.testNumberFormattingRoundTrips' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testSanitizeTable' started at 2026-11-06 20:57:46.359
Test Case 'ParityRunnerTests.testSanitizeTable' passed (0.0 seconds)
Test Case 'ParityRunnerTests.testStubFixtureValidation' started at 2026-11-06 20:57:46.359
Test Case 'ParityRunnerTests.testStubFixtureValidation' passed (0.001 seconds)
Test Suite 'ParityRunnerTests' passed at 2026-11-06 20:57:46.360
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'debug.xctest' passed at 2026-11-06 20:57:46.360
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'All tests' passed at 2026-11-06 20:57:46.360
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
◇ Test run started.
↳ Testing Library Version: 6.0.3 (18c42c19cac3faf)
✔ Test run with 0 tests passed after 0.001 seconds.
```

Summary: 10 tests, 10 passed, 0 failures.

## Test-to-assert mapping

| packet exact assert | XCTest |
| --- | --- |
| TSV columns exact, one row per backend | testHeaderAndRowShape |
| known stub values round-trip numerically | testEqualStubsPassAndRoundTrip, testNumberFormattingRoundTrips |
| injected differences remain visible; two different stubs catch hardcoded equal values | testDifferentStubsStayVisible |
| missing values become NA with non-pass status | testMissingValuesBecomeNAAndUnavailable |
| errors are explicit | testErrorIsExplicitAndPeerUnavailable, testStubFixtureValidation |
| stable locale/escaping prevents tabs/newlines corrupting rows | testEscapingKeepsRowsIntact, testSanitizeTable |
| invalid runner input rejected | testNonFiniteSeekTargetThrows |

## Sample measured TSV (stub adapters; NOT native parity)

Commands: `.build/debug/parity-runner --stubs fixtures/<STUB>.json --fixture parity-a24.mp4 --seek 1.0`

### parity-stub-equal
```
fixture	backend	frames	duration_s	seek_target_s	seek_landing_s	av_offset_s	status
parity-a24.mp4	stub-a	48	2.0	1.0	1.0416666666666667	0.002	pass
parity-a24.mp4	stub-b	48	2.0	1.0	1.0416666666666667	0.002	pass
```

### parity-stub-different
```
fixture	backend	frames	duration_s	seek_target_s	seek_landing_s	av_offset_s	status
parity-a24.mp4	stub-a	48	2.0	1.0	1.0416666666666667	0.002	different
parity-a24.mp4	stub-b	47	2.0	1.0	1.0833333333333333	-0.017	different
```

### parity-missing
```
fixture	backend	frames	duration_s	seek_target_s	seek_landing_s	av_offset_s	status
parity-a24.mp4	stub-a	NA	2.0	1.0	NA	NA	unavailable
parity-a24.mp4	stub-b	48	NA	1.0	1.0416666666666667	NA	unavailable
```

