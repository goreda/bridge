#!/usr/bin/env python3
"""Item: scrolling the magnet results list or the IPTV list counts as
idle-hide activity, like mouse movement.

Structural checks plus a replicated idle-timer model of the owner report:
with no scroll wake the 2.5s timer fades the panel mid-scroll; with the
scroll view waking PPController.wakeUI() it stays visible.

Linux: RUN. Mac/AppKit: NOT_RUN.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MB = os.path.join(HERE, "Sources", "gor", "MagnetBrowser.swift")
IPTV = os.path.join(HERE, "Sources", "gor", "IPTV.swift")
PP = os.path.join(HERE, "Sources", "gor", "PPController.swift")

fails = []
def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" - " + detail if detail else ""))
    if not ok:
        fails.append(name)

mb = open(MB, encoding="utf-8").read()
iptv = open(IPTV, encoding="utf-8").read()
pp = open(PP, encoding="utf-8").read()

check("GORActivityScrollView defined", "final class GORActivityScrollView: NSScrollView" in mb)
cls = mb[mb.index("final class GORActivityScrollView"):]
body = cls[:cls.index("\n}")]
wake = body.index("(NSApp.delegate as? AppDelegate)?.controller?.wakeUI()")
sup = body.index("super.scrollWheel(with: event)")
check("activity scroll view wakes before scrolling", wake < sup)
check("magnet panel uses the activity scroll view",
      "private let scroll = GORActivityScrollView()" in mb)
check("no plain NSScrollView left on the magnet panel",
      "private let scroll = NSScrollView()" not in mb)
start = iptv.index("final class IPTVRowStepScrollView")
seg = iptv[start:iptv.index("override func layout()", start)]
check("IPTV step scroll view wakes the idle path on scroll",
      "(NSApp.delegate as? AppDelegate)?.controller?.wakeUI()" in seg)
check("idle fade of the magnet panel unchanged",
      "magnetBrowser?.panel.setChromeAlpha(0.0, animated: true)" in pp)
check("app-wide idle monitor mask unchanged",
      "matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .scrollWheel]" in pp)

def final_alpha(events, wake_on_event, hide_delay=2.5):
    # Port of the idle rule: every activity resets the 2.5s timer; when the
    # timer fires the panel alpha goes to 0 and only activity restores it.
    last = 0.0
    alpha = 1.0
    for t in events:
        if t - last >= hide_delay:
            alpha = 0.0
        if wake_on_event:
            last = t
            alpha = 1.0
    if events[-1] + hide_delay < events[-1]:
        pass
    return alpha

scroll = [i * 0.1 for i in range(1, 100)]  # 10s of continuous scrolling
check("no scroll wake: panel fades mid-scroll (owner report)",
      final_alpha(scroll, False) == 0.0)
check("scroll wake: panel stays visible for the whole scroll",
      final_alpha(scroll, True) == 1.0)

print(("%d check(s) failed" % len(fails)) if fails else "all checks passed")
sys.exit(1 if fails else 0)
