#!/usr/bin/env python3
"""block 190m font repair source-contract test (portable, no Swift).

Pins the repair seams in the patched 374c sources:
  GORResources test-staging hook (XCTest-gated, real-dir, last precedence)
  PhotonFont bounded-fallback latch + registration counter
  photon-native-check.py staging, env export, step order, qualification gates
  PhotonFontResourceTests expectations

Usage: font_repair_contract_test.py <gor_root>
Exit 0 = PASS, 1 = FAIL.
"""
import re
import sys

def main():
    root = sys.argv[1]
    build = open(f"{root}/Sources/gor/App/Build.swift", encoding="utf-8").read()
    font = open(f"{root}/Sources/gor/UI/PhotonFont.swift", encoding="utf-8").read()
    harness = open(f"{root}/Tests/Photon/photon-native-check.py", encoding="utf-8").read()
    tests = open(f"{root}/Tests/gorTests/PhotonFontResourceTests.swift", encoding="utf-8").read()
    failures = []

    def check(name, cond):
        if not cond:
            failures.append(name)

    # 1. GORResources hook: XCTest-gated, real-dir only, consulted LAST.
    check("override defaults from GOR_TEST_RESOURCE_ROOT",
          'testResourceRootOverride: String? = ProcessInfo.processInfo.environment["GOR_TEST_RESOURCE_ROOT"]' in build)
    check("gated on XCTest presence (never the app)",
          'NSClassFromString("XCTestCase") != nil' in build)
    check("staged dir must be a REAL directory", "realDirectory(" in build)
    fonts = build[build.index("static func fonts()"):]
    fonts = fonts[:fonts.index("\n    }")]
    check("override consulted after real layouts, before miss log",
          fonts.index("externalDir(fontsName)") < fonts.index("testStagedDir(fontsName)")
          < fonts.index("didLogFontsMiss"))

    # 2. PhotonFont latch (a SET, so random reselection cannot alternate
    #    bad fonts forever) + counter + test-only state helpers.
    check("latch is a per-URL set", "private static var _failedLoadURLs: Set<URL> = []" in font)
    check("counter declared", "static var registrationAttemptCount = 0" in font)
    fn = font[font.index("static var fontName"):]
    fn = fn[:fn.index("\n    }")]
    check("latch guards the default load",
          "if !_failedLoadURLs.contains(url) {" in fn and "_failedLoadURLs.insert(url)" in fn)
    check("counter incremented before registration",
          font.index("registrationAttemptCount += 1")
          < font.index("CTFontManagerRegisterFontsForURL(loadURL as CFURL, .process, &error)"))
    check("success clears the latch",
          font.index("_registeredFontURL = loadURL")
          < font.index("_failedLoadURLs = []", font.index("_registeredFontURL = loadURL")))
    inv = font[font.index("static func invalidateCache()"):]
    check("invalidateCache re-arms", "_failedLoadURLs = []" in inv[:300])
    # r3: one XCTest-gated reset, no partial snapshot/restore pretense.
    check("single XCTest-gated reset helper", "static func resetFontLoadStateForTest()" in font)
    reset = font[font.index("static func resetFontLoadStateForTest()"):]
    reset = reset[:reset.index("\n    }")]
    check("reset is XCTest-gated (inert in the app)",
          'guard NSClassFromString("XCTestCase") != nil else { return }' in reset)
    check("reset unregisters the real CoreText font",
          "CTFontManagerUnregisterFontsForURL" in reset)
    check("reset clears identity + registration + latch + axis/mapping state",
          all(s in reset for s in ("_fontName = nil", "_registeredFontURL = nil",
                                   "_failedLoadURLs = []", "_axisRanges = [:]",
                                   "clearAxisMapping()", "reversedAxes = []",
                                   "invalidateCache()")))
    check("no partial snapshot/restore helpers remain",
          "snapshotFontLoadStateForTest" not in font
          and "restoreFontLoadStateForTest" not in font)

    # 3. Harness: staging, env export, order, gates.
    check("staging copies the REAL committed layout",
          "src = ROOT / 'Resources' / 'fonts'" in harness)
    check("byte-for-byte staged verification", "hashlib.sha256(q.read_bytes())" in harness)
    check("unique task-owned staging root (no fixed-path deletion)",
          "tempfile.mkdtemp(prefix='photon-test-resources-')" in harness
          and "shutil.rmtree(stage)" not in harness)
    check("env exported before suites",
          harness.index("os.environ['GOR_TEST_RESOURCE_ROOT'] = str(stage)")
          < harness.index("steps = ["))
    check("font-resource gate before feature suites",
          harness.index("'font-resource'") < harness.index("'close-lifecycle'"))
    check("startup test is actually selected as a strict step",
          "'font-startup'" in harness
          and "PhotonFontResourceTests/testAutomaticStartupSelectsStagedFont" in harness
          and harness.index("'font-resource'") < harness.index("'font-startup'")
          < harness.index("'close-lifecycle'")
          and "'font-startup': FONT_STRICT" in harness)
    check("deliberate-missing suite runs last",
          harness.index("'font-fallback-bounded'") > harness.index("'native-owner-evaluation'"))
    check("strict gate turns green-suite font errors into FAIL",
          "unexpected font resolution/registration failure with staged resources" in harness)
    check("bounded gate caps deliberate-missing at one error",
          "text.count('[PhotonFont] Registration error') > 1" in harness)

    # 4. XCTest expectations.
    check("staged test fails when unstaged (no skip)",
          "harness must stage the intended Resources layout" in tests)
    check("all committed eligible candidates named (incl. woff2)",
          "sixa/Exposure-VAR.ttf" in tests and "sixa/Milling-TriplexVAR.ttf" in tests
          and "DMTLLVIPWeb-Regular-6a47c86c.woff2" in tests)
    check("fallback must not serve when staged",
          'XCTAssertNotEqual(PhotonFont.fontName, "Menlo-Regular"' in tests)
    check("startup proof is strict first-access, not a 20-retry loop",
          "accesses < 20" not in tests
          and "XCTAssertEqual(PhotonFont.registrationAttemptCount - before, 1,\n                       \"first automatic load is exactly one registration call\")" in tests)
    check("override restored after deliberate-missing",
          "GORResources.testResourceRootOverride = savedRoot" in tests)
    check("tests reset font state at start and end (process isolation)",
          tests.count("PhotonFont.resetFontLoadStateForTest()") == 2)
    check("file closes its canImport(AppKit) guard (r2 compile blocker)",
          tests.rstrip().endswith("#endif"))
    check("no String/URL confusion on the temp path (v1 compile defect)",
          "FileManager.default.temporaryDirectory" in tests
          and "NSTemporaryDirectory().appendingPathComponent" not in tests)
    check("deliberate-missing uses an ABSENT layout, not an empty real dir",
          ".appendingPathComponent(\"fonts\")" not in tests.split("testMissingResourceFallsBackBounded")[1])
    check("exactly one controlled attempt (not <=1 vacuity)",
          "XCTAssertEqual(PhotonFont.registrationAttemptCount - before, 1" in tests)
    check("automatic startup route exercised (not only explicit loads)",
          "testAutomaticStartupSelectsStagedFont" in tests)
    check("deterministic resolved-root assertion",
          "fonts.path.hasPrefix(root)" in tests)

    if failures:
        print("FAIL")
        for f in failures:
            print(" -", f)
        return 1
    print("PASS: XCTest-gated staging hook (last precedence, real-dir), "
          "bounded-fallback latch with re-arm, registration counter, harness "
          "staging/order/gates and both test expectations pinned")
    return 0

if __name__ == "__main__":
    sys.exit(main())
