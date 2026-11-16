// arch-198k/198l runtime-dump core witness (GorFit harness pattern:
// swiftc -O core+suite, expect FAILS 0). Pins the pure behavior of
// GorRuntimeDumpCore: flag parsing, mpv line classification with per-shader
// buckets (grain separate from sharp), Lua message extraction, input.conf
// parsing, deterministic assembly.
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

// ── mpv line classification + per-shader buckets (arch-198l) ──
let shaders = ["photon-grain.glsl", "photon-sharp.glsl", "photon-chrome.glsl"]
check(GorRuntimeDumpCore.isPhotonShaderLogLine("[shader] warn: photon-grain.glsl: some warning", shaderNames: shaders), "grain warn kept")
check(GorRuntimeDumpCore.isPhotonShaderLogLine("[shader] error: failed to compile photon-sharp.glsl", shaderNames: shaders), "sharp error kept")
check(!GorRuntimeDumpCore.isPhotonShaderLogLine("[shader] info: loaded photon-grain.glsl", shaderNames: shaders), "info dropped")
check(!GorRuntimeDumpCore.isPhotonShaderLogLine("[ffmpeg] error: decode failed", shaderNames: shaders), "non-shader error dropped")
check(GorRuntimeDumpCore.shaderLogBucket("[shader] warn: photon-grain.glsl: x", shaderNames: shaders) == "photon-grain.glsl", "grain bucketed as grain")
check(GorRuntimeDumpCore.shaderLogBucket("[shader] error: photon-sharp.glsl failed", shaderNames: shaders) == "photon-sharp.glsl", "sharp bucketed as sharp")
check(GorRuntimeDumpCore.shaderLogBucket("[shader] warn: generic", shaderNames: shaders) == "unattributed", "unnamed line unattributed")

var buckets: [String: [String]] = [:]
for s in shaders { buckets[s] = [] }
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] warn: photon-grain.glsl: g1", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] error: photon-sharp.glsl: s1", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] warn: photon-grain.glsl: g2", shaderNames: shaders)
GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: "[shader] info: noise", shaderNames: shaders)
check(buckets["photon-grain.glsl"]?.count == 2, "grain bucket has 2, order kept")
check(buckets["photon-grain.glsl"]?[0].hasSuffix("g1") == true && buckets["photon-grain.glsl"]?[1].hasSuffix("g2") == true, "grain bucket order")
check(buckets["photon-sharp.glsl"]?.count == 1, "sharp bucket separate from grain")
check(buckets["photon-chrome.glsl"]?.isEmpty == true, "chrome bucket empty")

// ── Lua registered-message extraction ──
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

// ── deterministic assembly ──
let object = GorRuntimeDumpCore.assemble(
    executableSha256: "deadbeef",
    menus: [["title": "app", "enabled": true]],
    panels: ["live": [Any](), "available": ["URLPanel"]],
    scriptMessages: ["registered": ["a", "b"], "invoked_in_bindings": ["a"], "source": "test"],
    inputBindings: [["key": "c", "command": "script-message-to photon_chrome photon-chrome-toggle"]],
    shaderNames: shaders,
    scriptOptions: ["photon-scriptdir": "/x"],
    photonShaderLog: ["photon-grain.glsl": ["[shader] warn: g1"]],
    partial: false)
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
check(s1.contains("\"V7\" : false"), "implemented.V1-V7 shape")

print("FAILS \(fails)")
exit(fails == 0 ? 0 : 1)
