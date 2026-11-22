# Tests/BlinkRoute

`run.sh` runs the current store-applier blink lifecycle with verbatim production
methods extracted by `current_route.py`, in normal, no-camera and simulated-head
modes. It checks callback installation, separate head/blink consumer ownership,
projection OFF independence, idempotence, diagnostic-log failures, file close and
reopen, explicit OFF, lids/seek IPC, and dispatch from the public entry to the store.
It then runs the labeled Python gesture replay and the actual Swift recognizer.
Set SWIFTC to choose the compiler.

The historical `main.swift` asserts the retired pre-store VR-entry/defaults path.
It is retained as history, not compiled as current acceptance. The old extraction
failed on deleted `blinkControlDefaultsKey` before reaching a runtime assertion.

Boundary spies model only HeadTracker consumer counts/callbacks, logging, store
dispatch and IPC recording. Store action reduction, UI events, real camera frames,
permissions and GPU response are outside this extracted lifecycle test. Other
store and rendered-pixel tests cover their own scopes. The diagnostic callback
runs inline here, not on the native queue. No native acceptance is claimed.

The current Lua lid path only draws the measured lids. A bilateral hold must not
change playback pause. `Tests/Block185/hold-lua.py` and `render-mpv.py` check that
contract separately from Swift gesture recognition.

Control-held single completed bilateral blink toggles play/pause, using the same
fresh-frame reliability gates and existing robustness thresholds. This does not
enable the camera or change settings. Control must stay held from before the
closure until command delivery. Changing Control mid-gesture cancels the series.
Control blinks never build a seek series. A Control-held double blink therefore
toggles twice; ordinary double blink keeps +60s and Cmd-double blink keeps -60s.
The extracted production EyeGestureCommands fixture covers both robustness modes,
winks, long holds, dropped/stale frames, modifier changes and seek isolation.
