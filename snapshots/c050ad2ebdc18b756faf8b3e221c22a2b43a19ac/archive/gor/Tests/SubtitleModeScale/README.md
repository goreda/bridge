# Effective mode owns subtitle scale

Two coupled root causes: `pictureInPictureActive` is remembered windowed intent (`pipRestoreFrame != nil`), which stays true while fullscreen. The subtitle renderer used it as display mode, so fullscreen canvas height entered the PiP height*0.08 font formula. Canonical sub-scale and its preference were also shared, so changing PiP scale changed normal size on exit and saved the PiP choice into normal preference.

Controller now owns independent normal/PiP scale state. Fullscreen entry selects normal presentation before animation; settled fullscreen exit selects remembered windowed mode. PiP entry/exit similarly select scale. Mode switch writes canonical mpv property and immediately updates custom renderer; late polls with old-mode values cannot overwrite new state. Menu/keyboard readbacks save only the active mode's preference. Existing normal key/value and normal font formula remain unchanged. PiP font reset no longer resets normal legacy userScale. Delay/AV policy unchanged.

Actual typography probe logs on every effective-mode transition (`[subtitle-mode]`): both scale values, PiP flag, target/rendered/resolved size, canvas/wrap dimensions. Native entry/exit timing and pixels remain unverified.

`SWIFTC=/path/swiftc python3 Tests/SubtitleModeScale/run.py`: production mode policy and font writer exercise normal0.65 ->PiP1 ->change0.5 ->fullscreen normal0.65 ->PiP0.5 ->exit normal0.65; normal preference untouched. Point sizes19.5/21.6/10.8/19.5/10.8/19.5, not fullscreen-height PiP sizing. Other tests cover original normal byte-equivalence, canonical menu commands and persistence.
