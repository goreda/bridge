# Subtitle menu controls (189h)

Root causes: menu actions changed mpv properties while the custom renderer did not consume sub-scale/sub-pos/sub-delay; independent external cues ignored delay; mpv text availability shifts with delay but its cue timestamps do not. Unicode-arrow menu shortcuts were not AppKit function-key equivalents. Explicit delay actions had no transient OSD.

The menu now mutates then reads back the canonical property, updates the custom renderer immediately, and uses the existing transient OSD for1.5s. Polling also handles keyboard property changes. Size multiplies the existing complete proximity envelope; font family/variation axes and canvas transforms are preserved. PiP base is max(12,windowHeight*0.08),21.6pt at270px height; sub-scale applies afterward. Position polling does not undo dragging. Explicit resets force the same property position even if unchanged. Full reset sets scale1/delay0/position100. Audio delay has no automatic writer.

Run `SWIFTC=/path/swiftc python3 Tests/SubtitleMenuControls/run.py`.
Real mpv replay: `MPV=/path/mpv SWIFTC=/path/swiftc python3 Tests/SubtitleMenuControls/mpv_timing.py` (ffmpeg required).
Actual Exposure font cap-height raster: `SWIFTC=/path/swiftc python3 Tests/SubtitleMenuControls/pixels.py` (Pillow/FreeType);0.5/1/1.5 ratios within5% in normal/PiP. The saved PNG is Linux raster evidence, not native CoreText.

Owner capture261107-010115 tested prior b00eef38 only; APP_STATE was stale and cannot certify these controls. Native AppKit menu clicks, installed CoreText cap heights, PiP resize appearance, OSD timing and t1+l1-l4 remain owner-Mac acceptance. Linux production-method/boundary tests and real mpv are not that gate.
