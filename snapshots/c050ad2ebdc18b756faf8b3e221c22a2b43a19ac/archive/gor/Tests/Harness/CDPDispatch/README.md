# CDP command dispatch bookkeeping

Run `bash gor/Tests/Harness/CDPDispatch/run.sh`. Python 3 only, current CDPSession.swift required. Four controls cover monotonic IDs/reverse correlation/duplicate once, unknown replies, event shape and error response completion. Three source mutations fail. No snapshot fallback, browser/CDP/WebSocket/provider/Swift execution or production edit.

Send-path failure characterizations: pending is installed before serialization and retained if serialization fails, transport is nil or send fails. Outer capture deadlines and transport retirement may compensate, so this does not claim capture is permanently hung or regress the fixed capture tests. Native queues/reentrancy, per-command lifetime, outer legacy listing deadlines and teardown callback policy remain open. PASS is bookkeeping-port consistency, not browser reliability. No production patch included.
