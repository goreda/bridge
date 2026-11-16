// arch-198k/198l runtime-dump core witness (GorFit harness pattern:
// swiftc -O core+suite, expect FAILS 0). Pins the pure behavior of
// GorRuntimeDumpCore, now extended per Ops 198k review: flag parsing,
// shader-related warn/error capture with per-shader buckets plus
// "unattributed" (review (c)), checker-compatible features string arrays
// with rich records in features_provenance (review (a)), active-only
// shader_names (review (b)), live/static panel separation (review (2)),
// probe records with ATTESTED/UNPROBED discipline (review (1)),
// Lua message extraction, input.conf parsing, deterministic assembly.
import Foundation

var fails = 0
func check(_ cond: Bool, _ label: String) {
    if !cond { fails += 1; print("FAIL: \(label)") }
}

// ── flag parsing ──
check(GorRuntimeDumpCore.outputPath(arguments: ["gor", "--gor-dump-runtime=/tmp/out.json"]) == "/tmp/out.json", "flag path")
check(GorRuntimeDumpCore.outputPath(arguments: ["gor", "--other"]) == nil, "flag absent")
check(GorRuntimeDumpCore.outputPath(arguments: ["gor", "--gor-dump-runtime="]) == nil, "empty path rejected")
check(GorRuntimeDumpCore.outputPath(arguments: ["gor"]) == nil, "normal launch untouched")

// ── shader log capture + buckets (arch-198l + Ops review (c)) ──
let shaders = ["photon-grain.glsl", "photon-sharp.glsl", "photon-chrome.glsl"]
check(GorRuntimeDumpCore.isShaderLogLine("[shader] warn: photon-grain.glsl: some warning"), "grain warn kept")
check(GorRuntimeDumpCore.isShaderLogLine("[shader] error: failed to compile photon-sharp.glsl"), "sharp error kept")
check(!GorRuntimeDumpCore.isShaderLogLine("[shader] info: loaded photon-grain.glsl"), "info dropped")
check(!GorRuntimeDumpCore.isShaderLogLine("[ffmpeg] error: decode failed"), "non-shader error dropped")
// Ops review (c): generic lines with no filename or "[shader" prefix stay.
check(GorRuntimeDumpCore.isShaderLogLine("Failed to parse user shader"), "bare parse failure kept")
check(GorRuntimeDumpCore.isShaderLogLine("[libplacebo] error: shader link failed"), "libplacebo error kept")
check(!GorRuntimeDumpCore.isShaderLogLine("[libplacebo] info: shader linked"), "libplacebo info dropped")
check(GorRuntimeDumpCore.shaderLogBucket("[shader] warn: photon-grain.glsl: x", shaderNames: shaders) == "photon-grain.glsl", "grain bucketed as grain")
check(GorRuntimeDumpCore.shaderLogBucket("[shader] error: photon-sharp.glsl failed", shaderNames: shaders) == "photon-sharp.glsl", "sharp bucketed as sharp")
check(GorRuntimeDumpCore.shaderLogBucket("Failed to parse user shader", shaderNames: shaders) == "unattributed", "unnamed line unattributed")

var buckets: [String: [String]] = [:]
for s in shaders { buckets[s] = [] }
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] warn: photon-grain.glsl: g1", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] error: photon-sharp.glsl: s1", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] warn: photon-grain.glsl: g2", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] info: noise", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "Failed to parse user shader", shaderNames: shaders)
check(buckets["photon-grain.glsl"]?.count == 2, "grain bucket has 2, order kept")
check(buckets["photon-grain.glsl"]?[0].hasSuffix("g1") == true && buckets["photon-grain.glsl"]?[1].hasSuffix("g2") == true, "grain bucket order")
check(buckets["photon-sharp.glsl"]?.count == 1, "sharp bucket separate from grain")
check(buckets["photon-chrome.glsl"]?.isEmpty == true, "chrome bucket empty")
check(buckets["unattributed"]?.count == 1, "unattributed bucket holds bare failure")

// ── Lua registered-message extraction (source scan = provenance only) ──
let lua = """
mp.register_script_message("photon-scene-feed", function(payload)
mp.register_script_message("photon-chrome-toggle", function()
-- mp.register_script_message("commented-out", handler)
"""
let msgs = GorRuntimeDumpCore.registeredScriptMessages(in: lua)
check(msgs == ["photon-scene-feed", "photon-chrome-toggle"], "registered messages extracted, got \(msgs)")

// ── input.conf parsing ──
let conf = """
# comment
c script-message-to photon_chrome photon-chrome-toggle
C script-message-to photon_chrome photon-chrome-filter-toggle

F9 script-message-to photon toggle
"""
let bindings = GorRuntimeDumpCore.parseInputConf(conf)
check(bindings.count == 3, "3 bindings parsed, got \(bindings.count)")
check(bindings[0]["key"] == "c" && bindings[0]["command"] == "script-message-to photon_chrome photon-chrome-toggle", "binding 0")
let targets = GorRuntimeDumpCore.bindingMessageTargets(in: conf)
check(targets == ["photon_chrome", "photon_chrome", "photon"], "binding targets, got \(targets)")

// ── features string arrays (checker-compatible, Ops review (a)) ──
let menuTree: [[String: Any]] = [
    ["title": "File", "enabled": true, "submenu": [
        ["title": "Open", "enabled": true],
        ["title": "", "separator": true],
        ["title": "Recent", "enabled": true, "submenu": [["title": "clip.mkv", "enabled": true]]],
    ]],
]
let menuStrings = GorRuntimeDumpCore.menuStrings(menuTree)
check(menuStrings.contains("File/Open"), "menu path flattened")
check(menuStrings.contains("File/Recent/clip.mkv"), "nested menu path flattened")
check(!menuStrings.contains { $0.contains("separator") || $0.hasSuffix("/") }, "separators omitted")
let bindingStrings = GorRuntimeDumpCore.inputBindingStrings(bindings)
check(bindingStrings.first == "c: script-message-to photon_chrome photon-chrome-toggle", "binding string format, got \(bindingStrings)")
let optionStrings = GorRuntimeDumpCore.scriptOptionStrings(["photon-scriptdir": "/x", "photon-grain_floor_480p": 12])
check(optionStrings == ["photon-grain_floor_480p=12", "photon-scriptdir=/x"], "option strings sorted, got \(optionStrings)")

// ── probe discipline (Ops review (1)) ──
let att = GorRuntimeDumpCore.probeRecord(message: "photon-chrome-toggle", method: "m", result: "ATTESTED", detail: "d")
check(att["result"] as? String == "ATTESTED", "probe record shape")
check(GorRuntimeDumpCore.unprobedReason("photon-scene-feed").contains("ingress"), "feed classed as payload ingress")
check(GorRuntimeDumpCore.unprobedReason("photon-hud-toggle-fold").contains("OSD"), "fold classed as OSD-only")
check(GorRuntimeDumpCore.unprobedReason("set-user-enabled").contains("internal flag"), "user-enabled classed as internal sync")
check(GorRuntimeDumpCore.unprobedReason("photon-grain-set-amount").contains("payload"), "set-* classed as tuning mutation")

// ── deterministic assembly with the checker shape ──
let object = GorRuntimeDumpCore.assemble(
    executableSha256: "deadbeef",
    menuTree: menuTree,
    livePanels: [["class": "URLPanel", "title": "Open URL"]],
    staticPanelCatalog: ["URLPanel", "MusicPanel"],
    attestedMessages: ["photon-chrome-toggle"],
    unprobedMessages: ["photon-scene-feed"],
    registeredScan: ["photon-chrome-toggle", "photon-scene-feed"],
    invokedScan: ["photon_chrome"],
    probes: [att],
    inputBindingsRaw: bindings.map { $0 as [String: Any] },
    activeShaderPaths: ["/cfg/shader/photon-grain.glsl"],
    generatedShaderInventory: ["photon-chrome.glsl", "photon-grain.glsl"],
    scriptOptionsRaw: ["photon-scriptdir": "/x"],
    photonShaderLog: ["photon-grain.glsl": ["[shader] warn: g1"], "unattributed": ["Failed to parse user shader"]],
    partial: false)
guard let features = object["features"] as? [String: Any] else {
    fails += 1; print("FAIL: features missing"); print("FAILS \(fails)"); exit(1)
}
check(features["menus"] is [String], "features.menus is a string array")
check(features["panels"] is [String], "features.panels is a string array")
check(features["script_messages"] is [String], "features.script_messages is a string array")
check(features["input_bindings"] is [String], "features.input_bindings is a string array")
check(features["shader_names"] is [String], "features.shader_names is a string array")
check(features["script_options"] is [String], "features.script_options is a string array")
check((features["panels"] as? [String]) == ["URLPanel"], "features.panels = live panels only")
check((features["script_messages"] as? [String]) == ["photon-chrome-toggle"], "features.script_messages = ATTESTED only")
check((features["shader_names"] as? [String]) == ["photon-grain.glsl"], "features.shader_names = active list only")
let prov = object["features_provenance"] as? [String: Any]
let provPanels = prov?["panels"] as? [String: Any]
check((provPanels?["static_catalog"] as? [String]) == ["URLPanel", "MusicPanel"], "static catalog kept separate")
let provMsgs = prov?["script_messages"] as? [String: Any]
check((provMsgs?["registered_source_scan"] as? [String])?.count == 2, "scan kept as provenance")
check((provMsgs?["unprobed"] as? [String]) == ["photon-scene-feed"], "unprobed listed in provenance")
let provShaders = prov?["shader_names"] as? [String: Any]
var genInvCount = -1
if let ps = provShaders, let gi = ps["generated_inventory"] as? [String] { genInvCount = gi.count }
check(genInvCount == 2, "generated inventory kept separate")
var probeListCount = -1
if let pl = object["script_message_probes"] as? [[String: Any]] { probeListCount = pl.count }
check(probeListCount == 1, "probe list assembled")

guard let d1 = GorRuntimeDumpCore.jsonData(object), let d2 = GorRuntimeDumpCore.jsonData(object),
      let s1 = String(data: d1, encoding: .utf8) else {
    fails += 1; print("FAIL: jsonData nil")
    print("FAILS \(fails)")
    exit(1)
}
check(d1 == d2, "assembly deterministic")
check(s1.hasSuffix("}\n"), "trailing newline")
check(s1.contains("\"executable_sha256\" : \"deadbeef\""), "executable sha present")
check(s1.contains("\"photon_v4_replacement\""), "v4 section present")
check(s1.contains("\"photon_shader_log\""), "per-shader log section present")
check(s1.contains("\"result\" : \"NOT_RUN\""), "v4 placeholder NOT_RUN")
check(s1.contains("\"V7\" : \"NOT_RUN\""), "implemented.V1-V7 NOT_RUN placeholders")
check(s1.contains("probe_coverage_note"), "coverage honesty note present")

print("FAILS \(fails)")
exit(fails == 0 ? 0 : 1)
