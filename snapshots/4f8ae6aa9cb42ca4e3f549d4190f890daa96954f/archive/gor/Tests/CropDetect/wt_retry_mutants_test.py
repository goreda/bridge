#!/usr/bin/env python3
"""Behavior-level check of the crop retry table with source mutants, ported to the 199az persistent
search (no give-up count, +2/+5/+10/30s cadence, 3-tuple with scannedEnd, isPlaying at scheduling).
The model's parameters are PARSED from the Swift (cadence, table size, eviction rule, guards), so a
changed number or rule changes model behaviour instead of only breaking an exact-string pin. Each
mutant of the Swift text must turn at least one scenario red. Scope: the scheduling line, the whole
onResult closure and every use of the table in the file. Still a model: the Swift is not executed.
EXPLICIT LIMIT (C7): a timer that calls an EXISTING caller function (one that already reaches the
needsRedetect site) adds no new starter name and is not detectable by name pinning. C8 is covered by
the cropDetector.detect( census below; that census is LEXICAL only."""
import pathlib, re, sys
PC = (pathlib.Path(__file__).resolve().parents[2] / 'Sources/gor/Player/PPController.swift').read_text()

def params(text):
    line = next(l for l in text.splitlines() if "if CropDetector.isWTPlayback(self.currentFilePath)" in l and "let n" in l)
    p = {}
    m = re.search(r"if n < (\d+)", line); p["cap"] = int(m.group(1)) if m else None
    m = re.search(r"count >= (\d+)", line); p["size"] = int(m.group(1)) if m else None
    p["evict_new_only"] = "self.wtCropRetry.index(forKey: self.currentFilePath) == nil" in line
    p["oldest"] = ".min(by: { $0.value.t < $1.value.t })" in line
    p["clear_all"] = "removeAll" in line
    p["incr"] = int(re.search(r"= \(n \+ (\d+),", line).group(1))
    p["playing_gate"] = "self.isPlaying" in line
    p["crop_gate"] = "(!manual || self.cropRect == nil)" in line
    p["sched_uses_cadence"] = "let delay = Self.wtCropRetryDelay(attempt: n + 1)" in line and ".now() + delay)" in line
    m = re.search(r"wtCropRetryDelay\(attempt n: Int\) -> Double \{ n <= 1 \? (\d+) : n == 2 \? (\d+) : n == 3 \? (\d+) : (\d+) \}", text)
    p["delays"] = tuple(map(int, m.groups())) if m else None
    p["scanned_recorded"] = "self.wtCropRetry[self.currentFilePath] = (n + 1, ProcessInfo.processInfo.systemUptime, self.lastSeekableEnd)" in line
    reg = text.split("cropDetector.onResult = {", 1)[1].split("cropDetector.onStatus = {", 1)[0]
    uses = [l for l in text.splitlines() if re.search(r"\bwtCropRetry\b", l) and "wtCropRetryDelay" not in l]
    allowed = ("private var wtCropRetry", "wtCropRetry[self.currentFilePath] = nil", "wtCropRetry[currentFilePath] = nil",
               "if CropDetector.isWTPlayback", "wtCropRetry[currentFilePath] != nil", "wtCropRetry[self.currentFilePath] != nil",
               "if let pending = wtCropRetry[currentFilePath]", "restartPendingWTCropSearch")
    p["stray_use"] = any(not any(a in l for a in allowed) for l in uses)
    p["nil_writes"] = len(re.findall(r"wtCropRetry\[[^\]]*\]\s*=\s*nil", text))
    p["tuple_writes"] = len(re.findall(r"wtCropRetry\[[^\]]*\]\s*=\s*\(", text))
    p["nil_in_decisive"] = len(re.findall(r"if decisive && !early \{ self\.wtCropRetry\[self\.currentFilePath\] = nil \}", text))
    p["clear_calls"] = len(re.findall(r"wtCropRetry\.(?:removeAll|removeValue)", text)) - 1
    p["decisive_clear"] = len(re.findall(r"if decisive && !early \{ self\.wtCropRetry\[self\.currentFilePath\] = nil \}", reg)) == 1
    norm = re.sub(r"\s+", "", text).replace("self.wtCropRetry", "wtCropRetry")
    forms = [
        ("decl", r"wtCropRetry:\[String:\(n:Int,t:TimeInterval,scannedEnd:Double\)\]=\[:\]"),
        ("read", r"wtCropRetry\[self\.currentFilePath\]\?\.n\?\?0"),
        ("index", r"wtCropRetry\.index\(forKey:self\.currentFilePath\)==nil"),
        ("count", r"wtCropRetry\.count>=\d+"),
        ("oldest", r"wtCropRetry\.min\(by:\{\$0\.value\.t<\$1\.value\.t\}\)\?\.key"),
        ("evict", r"wtCropRetry\.removeValue\(forKey:old\)"),
        ("write3", r"wtCropRetry\[self\.currentFilePath\]=\(n\+1,ProcessInfo\.processInfo\.systemUptime,self\.lastSeekableEnd\)"),
        ("guard_read", r"wtCropRetry\[currentFilePath\]!=nil"),
        ("seek_cond", r"wtCropRetry\[self\.currentFilePath\]!=nil\|\|"),
        ("nil_bare", r"wtCropRetry\[currentFilePath\]=nil"),
        ("nil_self", r"wtCropRetry\[self\.currentFilePath\]=nil"),
        ("cache_read", r"wtCropRetry\[currentFilePath\],cropRect==nil,end>pending\.scannedEnd\+2\{"),
    ]
    kinds = []
    for m in re.finditer(r"wtCropRetry(?!Delay)", norm):
        tail = norm[m.start():m.start() + 120]; head = norm[max(0, m.start() - 26):m.start()]
        k = next((name for name, rx in forms if re.match(rx, tail)), "UNKNOWN:" + tail[:40])
        if k == "nil_self" and head.endswith("ifdecisive&&!early{"): k = "decisive_nil"
        kinds.append(k)
    want = sorted(["decl","read","index","count","oldest","evict","write3","decisive_nil",
                   "guard_read","guard_read","seek_cond","nil_bare","nil_bare","nil_self","cache_read"])
    p["structure_ok"] = sorted(kinds) == want
    p["flag_decl"] = line.count("var willRetry = false; if CropDetector.isWTPlayback") == 1
    p["flag_set"] = len(re.findall(r"willRetry = true", text)) == 1 and "systemUptime, self.lastSeekableEnd); willRetry = true; let scheduled" in line
    p["osd_flag"] = '(willRetry ? "crop detect: not enough of the stream downloaded yet, retrying by itself" : "crop detect: not enough of the stream downloaded yet, try again")' in text and len(re.findall(r"retrying by itself", text)) == 1
    p["sched_tokens"] = len(re.findall(r"asyncAfter|DispatchQueue|Timer\b|perform\(|Task\s*\{|OperationQueue|\.async\b|\.sync\b|NotificationCenter", reg))
    p["sched_on_line"] = len(re.findall(r"asyncAfter|DispatchQueue|Timer\b|perform\(|Task\s*\{|OperationQueue|\.async\b|\.sync\b|NotificationCenter", line))
    p["scan_calls_reg"] = len(re.findall(r"startAutomaticCropDetection\(", reg))
    sk = [re.sub(r"\s+", "", m) for m in re.findall(r"startAutomaticCropDetection\([^)]*\)", text)]
    p["scan_calls_file"] = sorted(sk) == sorted(["startAutomaticCropDetection(needsRedetect:Bool=false)", *(["startAutomaticCropDetection(needsRedetect:true)"]*7), "startAutomaticCropDetection(needsRedetect:needsRedetect)", "startAutomaticCropDetection()", "startAutomaticCropDetection()", "startAutomaticCropDetection()"])
    import pathlib as _pl
    srcs = sorted((_pl.Path(__file__).resolve().parents[2] / "Sources").rglob("*.swift"))
    allsrc = "\n".join(f.read_text() for f in srcs) if text is PC else text
    names = [re.sub(r"\s+", "", allsrc[m.start():m.start() + 60]) for m in re.finditer(r"startAutomaticCropDetection", allsrc)]
    known = ["startAutomaticCropDetection(needsRedetect:Bool=false)", *(["startAutomaticCropDetection(needsRedetect:true)"]*7), "startAutomaticCropDetection(needsRedetect:needsRedetect)", "startAutomaticCropDetection()", "startAutomaticCropDetection()", "startAutomaticCropDetection()"]
    p["bare_census"] = len(names) == 12 and sorted(re.match(r"startAutomaticCropDetection(\([^)]*\))", n).group(0) if re.match(r"startAutomaticCropDetection\([^)]*\)", n) else "BARE:" + n[:40] for n in names) == sorted(known)
    p["detect_census"] = sorted(re.sub(r"\s+", "", m) for m in re.findall(r"cropDetector\s*\.\s*detect\s*\(", allsrc)) == ["cropDetector.detect(", "cropDetector.detect("] and len(re.findall(r"\bdetect\s*\(\s*filePath", allsrc)) == 4
    p["identity_guard"] = "self.currentFilePath == scheduled" in line
    helper = text.split("private func fireWTCropRetry(_ scheduled: String,token:Int) {", 1)[1].split("\n    }", 1)[0]
    p["fire_pause_recheck"] = "if !isPlaying" in helper and "retry re-armed: playback paused, no scan" in helper
    p["fire_thermal"] = "if HeatTelemetry.thermalPressure" in helper and ".now() + 30" in helper
    return p

def scenarios(P):
    """Returns list of (name, ok) from a model driven only by P."""
    tbl = {}; clock = [0]
    def bump(f):
        n = tbl[f][0] if f in tbl else 0
        if P["cap"] is not None and n >= P["cap"]: return False
        full = P["size"] is not None and len(tbl) >= P["size"]
        if full and (not P["evict_new_only"] or f not in tbl):
            if P["clear_all"]: tbl.clear()
            elif tbl:
                key = min(tbl, key=lambda k: tbl[k][1]) if P["oldest"] else max(tbl, key=lambda k: tbl[k][1])
                tbl.pop(key)
        clock[0] += 1; tbl[f] = (n + P["incr"], clock[0]); return True
    out = []
    out.append(("no give-up cap: a crop is searched until found", P["cap"] is None))
    out.append(("cadence parsed from the source is +2/+5/+10 then every 30s", P["delays"] == (2, 5, 10, 30)))
    out.append(("the schedule delay comes from the cadence function, never a literal", P["sched_uses_cadence"]))
    out.append(("scheduling requires isPlaying", P["playing_gate"]))
    out.append(("each schedule records the scanned range end", P["scanned_recorded"]))
    out.append(("fire-time guards: paused re-arm and thermal defer both present", P["fire_pause_recheck"] and P["fire_thermal"]))
    for i in range(63): bump("f%d" % i)
    out.append(("63 entries keep all", len(tbl) == 63))
    bump("f63"); out.append(("64th new file keeps all 64", len(tbl) == 64 and "f0" in tbl))
    before = set(tbl); bump("f5"); out.append(("existing-key update at 64 evicts nothing", set(tbl) == before and tbl["f5"][0] == 2))
    bump("n65"); out.append(("65th new file evicts only the oldest", len(tbl) == 64 and "f0" not in tbl and "f1" in tbl and "n65" in tbl))
    for _ in range(15): bump("f1")
    out.append(("attempt 16 still schedules (no exhaustion)", tbl["f1"][0] == 16))
    out.append(("retry increment is exactly 1", P["incr"] == 1))
    out.append(("no stray table use or extra clear/removeAll anywhere in the file", not P["stray_use"] and P["clear_calls"] == 0))
    out.append(("structure: whitespace-stripped, every mention of the table is one of the 15 known forms (no reassign, updateValue, inout, removeAll)", P["structure_ok"]))
    out.append(("file-wide: exactly 4 nil writes (decisive, restart helper, dims, seek) and exactly 1 counter write", P["nil_writes"] == 4 and P["nil_in_decisive"] == 1 and P["tuple_writes"] == 1))
    out.append(("decisive result clears only the current file (once, inside the onResult closure)", P["decisive_clear"]))
    def manual_click(n, has_crop, playing=True):
        scheduled = playing and (P["cap"] is None or n < P["cap"]) and (not P["crop_gate"] or not has_crop) if P["flag_decl"] and P["flag_set"] else True
        osd_retry = scheduled if P["osd_flag"] else True
        return scheduled, osd_retry
    out.append(("manual click is never budget-refused (n=12 still schedules, OSD promises the retry)", manual_click(12, False) == (True, True)))
    out.append(("manual click with an existing crop: nothing scheduled, OSD does not promise a retry", manual_click(0, True) == (False, False)))
    out.append(("manual click while paused: nothing scheduled", manual_click(0, False, playing=False) == (False, False)))
    out.append(("flag wiring: declared once, set only where the retry is scheduled, retry text only under the flag, crop gate present", P["crop_gate"] and P["flag_decl"] and P["flag_set"] and P["osd_flag"]))
    out.append(("no other scheduling in onResult: exactly one DispatchQueue/asyncAfter/Timer/perform/Task/async token, and it is on the retry line", P["sched_tokens"] == 2 and P["sched_on_line"] == 2 and P["scan_calls_reg"] == 0))
    out.append(("scan starter is called file-wide only from the known sites including the restart helper and explicit output ON/OFF restoration", P["scan_calls_file"]))
    out.append(("bare-name census over all Sources: 12 mentions of the scan starter, each a known call form (no alias, method reference, or selector string)", P["bare_census"]))
    out.append(("census: cropDetector.detect( is called from exactly 2 sites (startAutomaticCropDetection and the manual path), no third direct call", P["detect_census"]))
    out.append(("fire-time file identity guard present", P["identity_guard"]))
    return out

def green(text):
    try: return all(ok for _, ok in scenarios(params(text)))
    except Exception: return False

base = scenarios(params(PC))
for n, ok in base: print(("ok   " if ok else "FAIL ") + n)
fails = [n for n, ok in base if not ok]
line = next(l for l in PC.splitlines() if "if CropDetector.isWTPlayback(self.currentFilePath)" in l and "let n" in l)
cadh = "static func wtCropRetryDelay(attempt n: Int) -> Double { n <= 1 ? 2 : n == 2 ? 5 : n == 3 ? 10 : 30 }"
full_mutants = {
    "removeAll inserted before the decisive guard (outside the pinned line)": ("            guard decisive else {", "            self.wtCropRetry.removeAll()\n            guard decisive else {"),
    "decisive branch clears everything instead of one file": ("if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }", "if decisive && !early { self.wtCropRetry.removeAll() }"),
    "decisive clear removed": ("if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }", ""),
    "decisive clears twice": ("if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }", "if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }; if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }"),
    "X1: budget=nil inside the scheduled closure before the rescan": ("self.startAutomaticCropDetection(needsRedetect:true)\n    }", "self.wtCropRetry[self.currentFilePath] = nil; self.startAutomaticCropDetection(needsRedetect:true)\n    }"),
    "X2: budget=nil appended inside startAutomaticCropDetection": ('print("[cropdetect] dimensions ready', 'self.wtCropRetry[self.currentFilePath] = nil; print("[cropdetect] dimensions ready'),
    "nil write for another file key": ("if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }", "if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil; self.wtCropRetry[\"\"] = nil }"),
    "A1: whitespace before bracket nil write": ("let scheduled = self.currentFilePath;", "self.wtCropRetry [self.currentFilePath]=nil; let scheduled = self.currentFilePath;"),
    "A2: updateValue((0, uptime), forKey:)": ("let scheduled = self.currentFilePath;", "self.wtCropRetry.updateValue((0, 0), forKey: self.currentFilePath); let scheduled = self.currentFilePath;"),
    "A3: whitespace before dot removeValue": ("let scheduled = self.currentFilePath;", "self.wtCropRetry .removeValue(forKey: self.currentFilePath); let scheduled = self.currentFilePath;"),
    "A4: wipe by reassignment [:]": ("let scheduled = self.currentFilePath;", "self.wtCropRetry=[:]; let scheduled = self.currentFilePath;"),
    "A5: whitespace before bracket tuple write": ("let scheduled = self.currentFilePath;", "self.wtCropRetry [self.currentFilePath] = (0, 0); let scheduled = self.currentFilePath;"),
    "A6: inout helper declared and called on the line": ("let scheduled = self.currentFilePath;", "func wipe(_ d: inout [String: (n: Int, t: TimeInterval, scannedEnd: Double)]) { d.removeAll() }; wipe(&self.wtCropRetry); let scheduled = self.currentFilePath;"),
    "OSD promises retry unconditionally": ('(willRetry ? "crop detect: not enough of the stream downloaded yet, retrying by itself" : "crop detect: not enough of the stream downloaded yet, try again")', '"crop detect: not enough of the stream downloaded yet, retrying by itself"'),
    "OSD flag inverted": ('(willRetry ? "crop detect: not enough of the stream downloaded yet, retrying by itself" : "crop detect: not enough of the stream downloaded yet, try again")', '(!willRetry ? "crop detect: not enough of the stream downloaded yet, retrying by itself" : "crop detect: not enough of the stream downloaded yet, try again")'),
    "P7: extra asyncAfter on the OSD line, no table named": ('                if manual { self.showCropDetectOSD(', '                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startAutomaticCropDetection() }\n                if manual { self.showCropDetectOSD('),
    "P7b: extra Timer in onResult": ('            guard decisive else {', '            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }\n            guard decisive else {'),
    "P7c: extra scan call in onResult": ('            guard decisive else {', '            self.startAutomaticCropDetection()\n            guard decisive else {'),
    "P7d: extra perform(selector) on the OSD line": ('                if manual { self.showCropDetectOSD(', '                self.perform(#selector(NSObject.description), with: nil, afterDelay: 1)\n                if manual { self.showCropDetectOSD('),
    "T5: alias + Timer elsewhere": ('    private func startAutomaticCropDetection(needsRedetect', '    private lazy var scanAlias = self.startAutomaticCropDetection\n    private func startAutomaticCropDetection(needsRedetect'),
    "T5b: method reference as value elsewhere": ('print("[cropdetect] dimensions ready', 'let f = self.startAutomaticCropDetection; Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in f(false) }; print("[cropdetect] dimensions ready'),
    "T6: selector string perform elsewhere": ('print("[cropdetect] dimensions ready', 'perform(NSSelectorFromString("startAutomaticCropDetection"), with: nil, afterDelay: 1); print("[cropdetect] dimensions ready'),
    "C8: Timer calls cropDetector.detect directly": ('print("[cropdetect] dimensions ready', 'Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in self.cropDetector.detect(filePath: "", videoW: 1, videoH: 1, fallbackDuration: 1) }; print("[cropdetect] dimensions ready'),
    "C8b: detect via spaced call": ('print("[cropdetect] dimensions ready', 'self.cropDetector .detect (filePath: "", videoW: 1, videoH: 1, fallbackDuration: 1); print("[cropdetect] dimensions ready'),
    "extra removeValue elsewhere": ("            guard decisive else {", "            self.wtCropRetry.removeValue(forKey: self.currentFilePath)\n            guard decisive else {"),
    "cap reintroduced at 12": ("if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying,", "if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, n < 12,"),
    "isPlaying scheduling gate dropped": ("if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying,", "if CropDetector.isWTPlayback(self.currentFilePath),"),
    "scannedEnd no longer recorded": ("(n + 1, ProcessInfo.processInfo.systemUptime, self.lastSeekableEnd)", "(n + 1, ProcessInfo.processInfo.systemUptime)"),
    "cadence 30 -> 45": (cadh, cadh.replace(": 30 }", ": 45 }")),
    "cadence +2 -> +1": (cadh, cadh.replace("n <= 1 ? 2", "n <= 1 ? 1")),
    "schedule delay hard-coded 45": (".now() + delay)", ".now() + 45)"),
    "paused fire scans instead of re-arming": ('if !isPlaying { print("[cropdetect] retry re-armed: playback paused, no scan");', 'if false { print("[cropdetect] retry re-armed: playback paused, no scan");'),
}
mutants = {
    "increment n+1 -> n+2": line.replace("(n + 1, ProcessInfo", "(n + 2, ProcessInfo"),
    "table 64 -> 65": line.replace("count >= 64", "count >= 65"),
    "table 64 -> 63": line.replace("count >= 64", "count >= 63"),
    "crop gate removed": line.replace(", (!manual || self.cropRect == nil)", ""),
    "gate OR flipped to AND": line.replace("(!manual || self.cropRect == nil)", "(!manual && self.cropRect == nil)"),
    "gate forgets manual (automatic path halted by existing crop)": line.replace("(!manual || self.cropRect == nil)", "self.cropRect == nil"),
    "flag set before the budget check": line.replace("var willRetry = false; ", "var willRetry = true; "),
    "flag set twice": line.replace("willRetry = true; let scheduled", "willRetry = true; willRetry = true; let scheduled"),
    "evict newest instead of oldest": line.replace(".min(by:", ".max(by:"),
    "evict on existing-key update too": line.replace("self.wtCropRetry.index(forKey: self.currentFilePath) == nil, ", ""),
    "reset-all instead of one eviction": line.replace("self.wtCropRetry.removeValue(forKey: old)", "self.wtCropRetry.removeAll()"),
    "drop file-identity guard": line.replace("guard let self, self.currentFilePath == scheduled else { return }; ", "guard let self else { return }; "),
}
red = 0
for name, ml in mutants.items():
    assert ml != line, name
    is_red = not green(PC.replace(line, ml)); red += is_red
    print(("ok   mutant caught: " if is_red else "FAIL mutant SURVIVED: ") + name)
    if not is_red: fails.append("survivor " + name)
for name, (a, b) in full_mutants.items():
    assert a in PC, name
    is_red = not green(PC.replace(a, b, 1)); red += is_red
    print(("ok   mutant caught: " if is_red else "FAIL mutant SURVIVED: ") + name)
    if not is_red: fails.append("survivor " + name)
total = len(base) + len(mutants) + len(full_mutants)
print("total %d checks: %d green, %d red (mutants caught %d/%d)" % (total, total - len(fails), len(fails), red, len(mutants) + len(full_mutants)))
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
