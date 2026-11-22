# PiP font-aware reflow

PiP inherited a fixed normal half-window subtitle column. CoreText also received each authored single newline as a hard paragraph, so reducing font size could not combine those rows. Paint, height measurement and face-avoidance placement each repeated the old width expression.

Only PiP now uses the full PiP canvas minus a symmetric inset max(8px,0.75*renderedFont.pointSize). Font point size is the already-scaled resolved font, not a new glyph/canvas transform. The same width is used for painting, incoming-cue height and candidate placement. PiP single soft rows join before CoreText line breaking; blank paragraphs and dialogue rows beginning '-' or an en dash stay separate. Normal mode retains its exact original text, half-window width and margins. Every font write already atomically rebuilds ink, so size +/- reflows while paused too.

`SWIFTC=/path/swiftc python3 Tests/PiPWrapping/run.py`: actual production Swift policy + real Exposure FreeType glyph advances.240/360/480/720px PiP canvases tested at10.8/21.6/32.4pt; first-line word counts increase strictly as font size decreases. Test PNG visually inspected. These are Linux pixels/policy tests, not native CoreText/AppKit acceptance. Owner b7318c798 size-control success is the native starting point; wrap appearance awaits next update.
