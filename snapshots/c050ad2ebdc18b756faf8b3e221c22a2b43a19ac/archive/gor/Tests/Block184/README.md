# Block184 available-source tests

Run `sh Tests/Block184/run.sh` with Swift and vendor ffmpeg. The update's automatic tests remain lifecycle-only; `--selftest-full` runs these legs and the actual projection/recognition cases.

Actual pure production functions: index-free PCA EAR, per-session timing detector, disparity sign/swap/1degree comfort bound, outlier and150ms reacquire, exact original decoded pixel bounds/outward/SBS union. Generated lossless original-media fixtures test letterbox removal and a SINGLE bright bar pixel. Native cropdetect alone misses that pixel because it tests line averages; the exact luma safety union prevents loss. Crop has40 spread sample attempts, no renderer/shader input. Content confined to unsampled frames may still be cut, as explicitly accepted in184. Unreadable/unavailable frames do not count as samples.

The subtitle ownership/replica-axis leg is STATIC SOURCE inspection, not a native rendering assertion. No Mac/AppKit/camera/physical fusion PASS is implied. Synthetic Linux mpv0.41 video-crop and its actual rendered screenshot were separately checked. The full app and camera require the owner's normal native update run; no extra owner diagnostics step is requested.

Blink pilot source: owner Nov6 15:28-15:29 chooses measured-eye video closure, double closure -> relative120s, NO HUD and NO artificial post-event animation. Index-free detector dispatches double-only seek; a continuous measured aperture drives the video closure. Real camera throughput/30fps, eye acceptance and appearance remain unqualified until actual use.

Pose ring is private in-memory last5min during head tracking, no camera frames or media identifiers. Quit writes a unique0600 JSONL file under Application Support/gor/pose-traces; existing files are not overwritten or deleted. Reacquire/outlier flags allow later attribution. No owner session trace has been received yet, so jump-source analysis is pending real data.

Progressive-input correction: continuous pose IPC uses one replaceable pending value and at most one drain; each drain yields behind discrete commands. Main-queue eye/pose/ambient updates likewise retain latest only. Discrete blink/keyboard actions are not coalesced. Quit closes the pose slot, rejecting later offers. The production slot and actual IPCClient (platform shim only) were stress-tested with an owned slow Unix socket; no owner Mac performance claim. Numeric input queue/send timing is bounded to9000rows and private0600 onquit; AV numeric sampling is1Hz/300rows, no media identifiers.

ExplicitDYNAMIC shader-parameter experiment was WITHDRAWN. Software gpu-next A/B showed plain149sends89drops/meanabsAV58.5ms versus DYNAMIC149sends109drops/86.4ms. Both overloaded, no audio hardware. Negative evidence retained; shader restored byte-for-byte. Neither coalescing nor diagnostics establishes the owner's AV root cause or that audio drift is fixed. Native normal-session evidence is still needed and will be collected automatically.
