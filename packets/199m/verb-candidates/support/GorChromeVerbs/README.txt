GorChromeVerbs: typed operation interface, Linux test and Darwin fixture for transport-speed, audio-boost, capture-screenshot.
Pins: gor 55e11d70ee6bad7d7d7373a275eeebd0a5157eee, gorav cf3e3f1772033dbc8465b19689e93f53c60006ce.
Status: CANDIDATE. No host wiring, no engine change. New files only; no production file is edited.
Executed here: python3 Tests/guard/guard_test.py (GOR_ROOT=<archive/gor of the 55e11d70 tree>): fixed GREEN, 17 mutants RED.
NOT_RUN (no Swift toolchain here): Sources/GorChromeVerbModel.swift compile, Tests/linux/main.swift, Tests/darwin/main.swift.
Run on a Swift toolchain:
  swiftc -o t Sources/GorChromeVerbModel.swift Tests/GorChromeVerbCases.swift Tests/linux/main.swift && ./t
  swiftc -o t Sources/GorChromeVerbModel.swift Tests/GorChromeVerbCases.swift Tests/darwin/main.swift && ./t
Owner decisions still open (proposed values, not measurements): speed bounds 0.01...100; boost interface ceiling 200 percent;
screenshot destination policy (the call sites carry none, so a nil destination is refused); screenshot subtitles/window modes need engine capabilities that do not exist at cf3e3f1.
Engine capabilities are inputs: GorEngineRateCapability, GorEngineGainCapability, GorScreenshotCapabilities. At cf3e3f1 no rate control, no gain above unity API and no screenshot session method exist (see packets).
Flagged for goreda to confirm: the self-mapped verbs audio-filters, subtitle-owner-sid, subtitle-typography are NOT in this package.
