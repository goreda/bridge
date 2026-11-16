// ================================================================
//  GorRuntimeDumpCore.swift - arch-198k in-app reporter, pure core
//  Owns: output-path parse, photon shader warn/error bucketing
//  (arch-198l + Ops 198k review: keep every shader-related warn/error
//  line, bucketed per shader when attributable, else "unattributed"),
//  checker-compatible features string arrays (schema
//  bridge inputs/198k/feature-runtime.schema.json: every features.*
//  value is a string array; the rich records move to
//  features_provenance), and JSON assembly. Foundation-only; the
//  AppKit adapter lives in GorRuntimeDump.swift. Linux-tested via
//  Tests/Harness/RuntimeDump.
// ================================================================
import Foundation

enum GorRuntimeDumpCore {

    static func outputPath(arguments: [String]) -> String? {
        for arg in arguments where arg.hasPrefix("--gor-dump-runtime=") {
            let path = String(arg.dropFirst("--gor-dump-runtime=".count))
            return path.isEmpty ? nil : path
        }
        return nil
    }

    // MARK: - photon shader log bucketing (arch-198l, Ops review (c))

    /// A warn/error line counts when it is shader-related, with or without
    /// a filename: parse failures like "Failed to parse user shader" and
    /// generic libplacebo/glsl errors must not be dropped.
    static func isShaderLogLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let isWarnOrError = lower.contains("error") || lower.contains("warn") || lower.contains("failed")
        guard isWarnOrError else { return false }
        return lower.contains("shader") || lower.contains("libplacebo") || lower.contains("glsl")
            || lower.contains("hook") || lower.contains("[gpu")
    }

    static func shaderLogBucket(_ line: String, shaderNames: [String]) -> String {
        for name in shaderNames where line.contains(name) { return name }
        return "unattributed"
    }

    /// Buckets every shader-related warn/error line. Unattributable lines
    /// land in "unattributed", never silently dropped (Ops 198k review (c)).
    static func appendShaderLogLine(_ buckets: inout [String: [String]], line: String, shaderNames: [String]) {
        guard isShaderLogLine(line) else { return }
        buckets[shaderLogBucket(line, shaderNames: shaderNames), default: []].append(line)
    }

    // MARK: - script message source scan (provenance only)

    /// Names registered via mp.register_script_message("name", ...) in a Lua
    /// source. The scanned file is the byte-exact script mpv loaded.
    static func registeredScriptMessages(in luaSource: String) -> [String] {
        var out: [String] = []
        for line in luaSource.split(separator: "\n") {
            // Lua line comments never register anything.
            if line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("--") { continue }
            var rest = Substring(line)
            while let range = rest.range(of: "register_script_message(\"") {
                let after = rest[range.upperBound...]
                if let end = after.firstIndex(of: "\"") {
                    out.append(String(after[..<end]))
                }
                rest = after
            }
        }
        return out
    }

    /// input.conf parse (IPC input-bindings fallback): key + full command,
    /// comment and empty lines skipped.
    static func parseInputConf(_ text: String) -> [[String: String]] {
        var out: [[String: String]] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let key = parts.first else { continue }
            let command = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            out.append(["key": String(key), "command": command])
        }
        return out
    }

    static func bindingMessageTargets(in inputConf: String) -> [String] {
        var out: [String] = []
        for line in inputConf.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var rest = Substring(trimmed)
            while let range = rest.range(of: "script-message-to ") {
                var after = rest[range.upperBound...]
                if after.hasPrefix("\"") { after = after.dropFirst() }
                let target = after.split(whereSeparator: { $0 == " " || $0 == "\"" }).first.map(String.init)
                if let target { out.append(target) }
                rest = after
            }
        }
        return out
    }

    // MARK: - features string arrays (checker-compatible)

    /// Nested menu records -> "menuTitle/itemTitle" strings (one per item,
    /// submenu paths joined with "/"). Separators are omitted.
    static func menuStrings(_ items: [[String: Any]], prefix: String = "") -> [String] {
        var out: [String] = []
        for item in items {
            guard let title = item["title"] as? String, !title.isEmpty else { continue }
            let path = prefix.isEmpty ? title : prefix + "/" + title
            if let submenu = item["submenu"] as? [[String: Any]], !submenu.isEmpty {
                out.append(contentsOf: menuStrings(submenu, prefix: path))
            } else if (item["separator"] as? Bool) != true {
                out.append(path)
            }
        }
        return out
    }

    /// Raw input binding records -> "key: full command" strings.
    static func inputBindingStrings(_ bindings: [Any]) -> [String] {
        bindings.compactMap { raw -> String? in
            guard let b = raw as? [String: Any] else { return nil }
            let key = (b["key"] as? String) ?? "?"
            let cmd = (b["cmd"] as? String) ?? (b["command"] as? String) ?? ""
            return key + ": " + cmd
        }
    }

    /// script-opts dictionary -> "name=value" strings.
    static func scriptOptionStrings(_ options: [String: Any]) -> [String] {
        options.map { name, value in name + "=" + String(describing: value) }.sorted()
    }

    // MARK: - probe records

    /// One runtime script-message probe outcome (Ops 198k review (1)).
    /// result: ATTESTED (flip + restore observed over IPC), FAILED (probe
    /// ran, effect not observed), UNPROBED (no safe probe exists).
    static func probeRecord(message: String, method: String, result: String, detail: String) -> [String: Any] {
        ["message": message, "method": method, "result": result, "detail": detail]
    }

    /// Unprobed classification for a registered message that has no safe
    /// IPC-observable probe. Reasons are data, not authority.
    static func unprobedReason(_ message: String) -> String {
        if message.hasSuffix("-hud-state") || message == "photon-scene-feed"
            || message == "photon-grain-measure-status" || message == "photon-grain-size-evidence"
            || message == "photon-grain-size-trim-state" || message == "photon-adaptive-program-state" {
            return "payload ingress (subscriber publishes nothing IPC-readable back); no safe read-only probe"
        }
        if message == "photon-hud-toggle-fold" || message == "photon-hud-force-redraw"
            || message == "photon-grain-doc" || message == "photon-grain-debug-visualize" {
            return "effect is OSD/VM-internal only; no IPC-visible witness"
        }
        if message == "set-user-enabled" || message == "set-chrome-user-enabled"
            || message == "set-negativ-user-enabled" || message == "set-live"
            || message == "photon-adaptive-program-toggle" {
            return "synchronizes an internal flag; no IPC-visible effect to round-trip"
        }
        if message == "photon-chrome-filter-toggle" || message == "photon-chrome-set-mono-grain"
            || message.hasPrefix("photon-chrome-set-target") {
            return "effect is conditional on chrome being enabled; probing it changes playback state"
        }
        if message == "photon-look-reset" {
            return "mutates user tuning state with no reversible observable"
        }
        return "requires argument payload that mutates tuning state; no safe read-only probe"
    }

    // MARK: - photon_v4_replacement (NOT_RUN placeholders per Ops (d))

    static func photonV4ReplacementSection(executableSha256: String) -> [String: Any] {
        [
            "executable_sha256": executableSha256,
            "result": "NOT_RUN",
            "lua_swift_twin_byte_equal": "NOT_RUN",
            "v7_invariants": "NOT_RUN",
            "manual_recall_sequence": "NOT_RUN",
            "implemented": [
                "V1": "NOT_RUN", "V2": "NOT_RUN", "V3": "NOT_RUN", "V4": "NOT_RUN",
                "V5": "NOT_RUN", "V6": "NOT_RUN", "V7": "NOT_RUN",
            ],
            "note": "checker-side placeholders; the in-app reporter does not execute the v4 replacement suites",
        ]
    }

    // MARK: - assembly

    static func assemble(
        executableSha256: String,
        menuTree: [[String: Any]],
        livePanels: [[String: Any]],
        staticPanelCatalog: [String],
        attestedMessages: [String],
        unprobedMessages: [String],
        registeredScan: [String],
        invokedScan: [String],
        probes: [[String: Any]],
        inputBindingsRaw: [Any],
        activeShaderPaths: [String],
        generatedShaderInventory: [String],
        scriptOptionsRaw: [String: Any],
        photonShaderLog: [String: [String]],
        partial: Bool
    ) -> [String: Any] {
        let activeShaderNames = activeShaderPaths.map { ($0 as NSString).lastPathComponent }.sorted()
        let features: [String: Any] = [
            // Checker contract (bridge inputs/198k/feature-runtime.schema.json):
            // every features.* value is a flat string array; the checker set()s
            // it. Rich records live in features_provenance.
            "menus": menuStrings(menuTree).sorted(),
            "panels": livePanels.compactMap { $0["class"] as? String }.sorted(),
            "script_messages": attestedMessages.sorted(),
            "input_bindings": inputBindingStrings(inputBindingsRaw).sorted(),
            "shader_names": activeShaderNames,
            "script_options": scriptOptionStrings(scriptOptionsRaw),
        ]
        let featuresProvenance: [String: Any] = [
            "menus": ["format": "menuTitle/itemTitle path strings", "tree": menuTree],
            "panels": [
                "live": livePanels,
                "static_catalog": staticPanelCatalog,
                "note": "live = open NSPanel instances at dump time (runtime); static_catalog = source inventory of panel classes (not runtime availability); the two are never merged (Ops 198k review (2))",
            ],
            "script_messages": [
                "attested_runtime": attestedMessages.sorted(),
                "unprobed": unprobedMessages.sorted(),
                "registered_source_scan": registeredScan,
                "invoked_in_bindings_source_scan": invokedScan,
                "note": "features.script_messages contains ONLY runtime-ATTESTED handlers; source scans are provenance, never merged into the runtime list (Ops 198k review (1))",
            ],
            "input_bindings": ["raw": inputBindingsRaw],
            "shader_names": [
                "active_glsl_shaders": activeShaderPaths.sorted(),
                "generated_inventory": generatedShaderInventory,
                "note": "features.shader_names = the ACTIVE glsl-shaders list only; the generated file inventory is kept separate (Ops 198k review (b))",
            ],
            "script_options": ["raw": scriptOptionsRaw],
        ]
        return [
            "executable_sha256": executableSha256,
            "features": features,
            "features_provenance": featuresProvenance,
            "script_message_probes": probes,
            "probe_coverage_note": "probes cover only the six toggle handlers with a safe IPC round-trip witness; every other registered handler is UNPROBED. This is not a full feature baseline and ATTESTED applies per handler, never to the feature set as a whole.",
            "photon_shader_log": photonShaderLog,
            "photon_v4_replacement": photonV4ReplacementSection(executableSha256: executableSha256),
            "partial": partial,
        ]
    }

    static func jsonData(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        data.append(0x0A)
        return data
    }
}
