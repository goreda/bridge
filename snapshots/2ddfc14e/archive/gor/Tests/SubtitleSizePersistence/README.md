# Durable subtitle size, PiP default, and runtime diagnosis

Confirmed missing persistence: mpv.conf explicitly removes sub-scale from watch-later; no app preference existed. The accepted owner's session had sub-scale0.65. A fresh process starts1, so identical normal/PiP formula inputs except scale produce1/0.65=1.538x size. This explains a restart growth path; no current screenshot/receipt yet proves it is the only contributor to the report. The last013044 capture was451s stale.

Only size is now saved: launch argument restores before mpv starts, canonical menu and keyboard property readbacks save it, reset saves1. First upgrade recovers last app-authored gor-subtitle-state.json sub-scale if no preference exists. Bad/missing receipt falls back to default1; no magic0.65 constant is introduced. Delay and audio delay remain session-only. Font formula, axes and renderer transforms are unchanged.

PiP window default is bottom-left. A valid user-snapped frame is saved and wins on later entry/launch; current content aspect is applied to it. Invalid/off-screen saved frames fall back to the default. Normal window placement is untouched.

Existing subtitle-state receipt now includes PiP flag, legacy userScale, canonical size scale, target/rendered/resolved point size, canvas dimensions and wrap width to distinguish geometry/zoom/property state from font rendering.

`SWIFTC=/path/swiftc python3 Tests/SubtitleSizePersistence/run.py`: compiled actual preference and PiP geometry, migration0.65->restart0.65, changed choice/reset, no delay persistence, bottom-left default and moved top-right retained on two display origins. `Tests/PiPNormalIsolation/run.py`:600 same-input production output rows byte-identical to b7318c79; font writer/mode setter/font resolution source unchanged. Linux boundary/policy tests do not certify native AppKit/CoreText appearance; owner follow-up remains required.
