generic ohal writer packet (block 89/91).

id: W-0184 | date: 2026-10-26 | to: any lab | subject: gorav line: seekref keyframe-snap report extension

- base: the returned generic module at its public result URL (entry W-0122 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: seekref <media> <seed> <count> <out.json> --snap-keyframes - additionally probes keyframe pts (ffprobe -select_streams v -skip_frame nokey -show_entries frame=pts) and records per target {"nearest_keyframe_pts":K,"landing_delta_frames":D} where D = landing_pts - K in frames at the stream rate.
- test: on the synthetic g12 clip, K values come only from the actual keyframe set (asserted in-test by independent probe); deterministic across runs.
- est: <1h.
- claimed by: OPEN.
