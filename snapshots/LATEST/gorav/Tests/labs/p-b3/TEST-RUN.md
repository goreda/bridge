# P-B3 TEST RUN

## Swift XCTest suite: EXECUTED AND PASS (real toolchain)

Toolchain: Swift 5.10.1 RELEASE, official swift.org Ubuntu 22.04 x86_64 build
(swift-5.10.1-RELEASE-ubuntu22.04.tar.gz). Command: `swift test` from the
package root. Result:

```
Test Suite 'All tests' passed
         Executed 8 tests, with 0 failures (0 unexpected) in 0.004 seconds
```

All 8 tests passed: testBlackMapsBlack, testErrorCases, testGrayRampFixture,
testOutputRange, testPPMConsistency, testPQRoundTripDense,
testPQRoundTripKnownSamples, testPrimaryPatchesFixture.

The fixture oracle tests (testGrayRampFixture, testPrimaryPatchesFixture)
recompute every CSV row with the Swift Double implementation and compare
against the Python-generated saved oracle within 1e-9: cross-language
agreement of the two independent implementations is therefore verified, not
assumed. testPPMConsistency verifies the reference PPMs are the 8-bit
quantization of the oracle.

Two compile defects in the first delivered test file were found by this run
and fixed (an import nested in function scope; tuple equality in
XCTAssertEqual). No source/algorithm changes.

## Metal execution: UNRUN (as the packet's conditional allows)

Linux has no Metal. The Metal parity test is behind #if canImport(Metal) and
was not compiled into this run; on macOS it compiles, and XCTSkips when no
Metal device exists, which the suite reports as UNRUN, not pass. The 1e-4
CPU/GPU parity assert must not be claimed until executed on macOS.

## Generator numeric asserts: EXECUTED AND PASS (independent second check)

`python3 tools/generate_fixtures.py` (Python 3.10.12, stdlib only,
deterministic; rerun regenerates byte-identical fixtures):

```
M_2020_TO_709 (derived from published primaries):
  1.6604910021084338  -0.58764113878854973  -0.072849863319884856
  -0.12455047452159063  1.1328998971259601  -0.0083494226043694872
  -0.018150763354905213  -0.10057889800800743  1.1187296613629127
  row0 sum = 0.99999999999999933
  row1 sum = 1
  row2 sum = 1
A1 PQ round-trip max relative error (1008 samples): 1.707e-13
A2 neutral max channel spread: 3.331e-16, finite=True, monotonic=True
A3 black -> (0.0, 0.0, 0.0)
A4 all fixture outputs in [0,1]: True
ALL NUMERIC ASSERTS PASS (A1-A4)
```

Fixture sha256:

```
2830274dd73ed3bfc792a7a7825b8677114d698fd18dca1ac027a78e80057d90  fixtures/pq-gray-ramp.csv
d4f8078e0d3800fd518e7bffe0b168c1ec77532ea7078f557d933c7e47b1d60b  fixtures/hdr-primary-patches.csv
d436e5dfaca0398e848472d4d65e7ff096a8cc31c59707dc758f3393aa252653  fixtures/gray-ramp-reference.ppm
4806fa7738bd7547ad7001220a41f5bbbfb13578b5bc42150701f9a162bb1c22  fixtures/color-patches-reference.ppm
```
