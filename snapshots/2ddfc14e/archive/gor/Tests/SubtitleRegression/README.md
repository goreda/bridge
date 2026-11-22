# Subtitle regression qualification

`run.py` executes production native-owner selection and the actual SubtitleView compositor hide/unhide method with a layer boundary spy. It covers the real mpv default: secondary visibility true but no selected secondary track. Visibility options alone must not hide custom captions.

`mpv-render.py OUTPUT_DIR` loads a real SRT track into real mpv, captures IPC state with native subtitles OFF and empty secondary, and feeds that JSON to compiled production Swift ownership. It then enables native subtitles and compares real window screenshots to prove that the SRT paints visible pixels. Set GOR_TEST_MPV, FFMPEG, SWIFTC and DISPLAY as needed. This does not substitute mpv's renderer for gor's custom renderer.

Qualification performed on Linux software GL, mpv 0.34.1: OFF screenshot black; ON screenshot visibly reads SUBTITLE VISIBILITY QUALIFICATION; 9276 changed color channels. Both actual pixels inspected. The same exact empty-secondary state was separately reported by UI writer on mpv 0.41. Native AppKit/CoreText custom subtitle bitmap and the owner's installed application remain unverified here.

Code history: `0bacc5a86` introduced the option-only nativeReported OR and compositor suppression, before e75b9ad6. SubtitleView.swift and polling ownership were unchanged across the later suspected chain. No source proof implicates 35bf776e's transaction changes; those remain untouched.
