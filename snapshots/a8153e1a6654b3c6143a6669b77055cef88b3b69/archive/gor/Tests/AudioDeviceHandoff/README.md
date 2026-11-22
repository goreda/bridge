# Audio device Stage A test seam

Run `SWIFTC=/path/to/swiftc python3 Tests/AudioDeviceHandoff/run.py` at the gor root.

Green transaction suites compile the actual production AudioOutputDeviceTransaction.swift directly. The adapter extractor reads current production AudioUnitSink.swift afresh, extracts select/review/DeviceHandoff methods, and compiles those unchanged control-flow bodies against recording HAL, registry, callback admission and pacing doubles. The test seam is not native callback or CoreAudio evidence. Inventory raw-C/CF calls, actual registry ownership, real callback timing and actual clock values remain native obligations.

No session/host/menu activation is in Stage A. Default sink construction is unchanged. The new unit is opt-in HALOutput only. Current actual readback is mandatory. A failed pre-stop preparation does not disturb old output. A failed replacement activation/readback rolls back through checked stop/dispose/old start/old readback. Failed quiesce/rollback/disposal is terminal and fault-retained, never accepted.

Run the added XCTest AudioOutputDeviceNativeTests on macOS for compile/inventory/unit wiring. Hardware execution requires GORAV_AUDIO_DEVICE_TEST=1 and GORAV_AUDIO_DEVICE_UID set to a real output UID. It changes only the test sink output, not the system default. No PCM is sent. The fixture restores the old explicit UID, not the original DefaultOutput component type. Actual audible output, timed hot unplug, callback race stress and device format compatibility require separate hardware tests.

Terminal device faults intentionally retain provider handles/context roots, do not reuse or dispose uncertain handles, and make later stop report failed. Process registry ceilings apply to every replacement registration. A late callback after provider disposal is fenced by that provider's retired admission context, not by an assumption that disposal stopped all callback invocations. Two registries/context roots during a handoff do not authorize two PCM consumers; all callbacks are paused while switching and old admission is retired plus drained before resuming new consumption.

The portability tests check semantic call order and injected status failures. They cannot prove system APIs honor quiescence, that a device emits sound, sample-rate conversion, CoreAudio listener lifetime semantics, or deadline behavior on hardware. Linux syntax parsing is not Apple API typechecking. Keep Darwin/hardware NOT_RUN until their receipts exist.
