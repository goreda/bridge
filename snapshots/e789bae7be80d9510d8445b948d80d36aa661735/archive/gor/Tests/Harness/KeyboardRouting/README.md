# Keyboard ownership and config contract

Run `bash gor/Tests/Harness/KeyboardRouting/run.sh`. Python 3 only, current PPController_Features.swift and input.conf required. No snapshot fallback, key injection, NSEvent, Swift, mpv or UI execution.

Six controls cover source/config arrow contract, Shift subtitle/VR/IPD actions, local monitor Cmd ownership and Cmd+Option clips, mode/panel bypass, modifier/key names and volume clamp. Three source/config mutations fail. Current comments mentioning Shift-digit speeds differ from implementation's subtitle placement; tests follow actual code, not that historical comment.

Characterizations: direct view-keyDown lacks the monitor Cmd gate and forwarder omits Cmd/Meta; Ctrl/Alt arrows still use plain Swift volume/seek; synthetic control characters can defeat quote/backslash-only JSON escaping. Native responder chain, reachable character inputs and intended modifiers are not established. Do not label these confirmed shortcut bugs or silently redefine shortcuts. PASS is source/port consistency, not native keyboard correctness. No production edit included.
