# Crop and aspect format regressions

`SWIFTC=/path/to/swiftc python3 Tests/VideoFormats/run.py` compiles the production catalog and verifies its shared format list, exact ratios, manual parser and source-pixel crop plans. Set `MPV` to a current mpv executable to run actual IPC tests against generated video at 1920x1080, 1440x1080 and anamorphic 720x576. These assert every format forward/reverse, every crop paired with every AR override, 162 resets, post-crop output dimensions and unchanged decoder dimensions. The file bytes are never edited.

`SWIFTC=/path/to/swiftc python3 Tests/VideoFormats/reset_routes.py` executes the production two reset methods and reset transition with boundary spies, all27 formats, PiP on/off. `Tests/PiPCropAspect/run.py` exercises the production PiP geometry refit for all27 formats. `Tests/AspectReset/run.py` covers aspect override/reset and independent crop state.

Linux evidence only. Native AppKit menu clicks, screenshot layout, actual PiP window rendering and the owner's Seinfeld file remain unverified. Production manual crops now use decoder w/h/par and mpv video-crop, matching the automatic crop owner instead of a second vf crop. Both reset methods cancel and hold automatic detection, clear video-crop/owned vf, and explicitly refit even when vf was idle. Detect or a new file releases that hold.
