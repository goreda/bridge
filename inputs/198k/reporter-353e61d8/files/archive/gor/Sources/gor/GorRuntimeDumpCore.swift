// ================================================================
//  GorRuntimeDumpCore.swift - arch-198k in-app reporter, pure core
//  Owns: flag parsing, mpv line classification, payload extraction,
//        feature-runtime.json assembly (Foundation only; compiles on
//        Linux so the witness harness can pin behavior). The AppKit
//        adapter lives in GorRuntimeDump.swift.
//  Contract: runs only under --gor-dump-runtime=<path>; normal launch
//  is untouched. Output is deterministic (sorted keys, stable order).
// ================================================================
import Foundation

enum GorRuntimeDumpCore {
    static let flagPrefix = "--gor-dump-runtime="

    /// The dump output path, or nil when the flag is absent (normal launch).
    static func outputPath(arguments: [String]) -> String? {
        for arg in arguments where arg.hasPrefix(flagPrefix) {
            let path = String(arg.dropFirst(flagPrefix.count))
            if !path.isEmpty { return path }
        }
        return nil
    }

    /// mpv stderr line classifier: keep warn/error lines that concern any
    /// photon shader (the shader module's own [shader] lines, or any line
    /// naming a photon shader file). msg-level shader=v is set at launch.
    static func isPhotonShaderLogLine(_ line: String, shaderNames: [String]) -> Bool {
        let lowered = line.lowercased()
        guard lowered.contains("warn") || lowered.contains("error") || lowered.contains("failed") else { return false }
        if lowered.contains("[shader") { return true }
        return shaderNames.contains { line.contains($0) }
    }

    /// arch-198l: bucket one kept line by the shader it names (grain and
    /// sharp must be separable - the "sometimes no grain" cause is not
    /// established). Lines naming no shader land in "unattributed".
    static func shaderLogBucket(_ line: String, shaderNames: [String]) -> String {
        for name in shaderNames where line.contains(name) { return name }
        return "unattributed"
    }

    /// Append a line to per-shader buckets (one bucket per known shader name
    /// plus "unattributed"), preserving arrival order per bucket.
    static func appendShaderLogLine(_ buckets: inout [String: [String]], line: String, shaderNames: [String]) {
        guard isPhotonShaderLogLine(line, shaderNames: shaderNames) else { return }
        let bucket = shaderLogBucket(line, shaderNames: shaderNames)
        buckets[bucket, default: []].append(line)
    }

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

    /// script-message-to <target> names appearing in input.conf text.
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

    /// input.conf parse (IPC input-bindings fallback): key + full command,
    /// comments and blank lines skipped, inline order preserved.
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

    /// The photon_v4_replacement section: checker-side comparison fields are
    /// emitted in schema shape with NOT_RUN placeholders (arch-198k; the
    /// reporter records the build, the bridge checker compares it).
    static func photonV4ReplacementSection(executableSha256: String) -> [String: Any] {
        return [
            "executable_sha256": executableSha256,
            "result": "NOT_RUN",
            "lua_swift_twin_byte_equal": NSNull(),
            "v7_invariants": [String](),
            "manual_recall_sequence": "NOT_RUN",
            "implemented": [
                "V1": false, "V2": false, "V3": false, "V4": false,
                "V5": false, "V6": false, "V7": false,
            ],
            "note": "checker-side fields emitted in schema shape only (arch-198k); filled by the bridge checker",
        ]
    }

    /// Assemble the full feature-runtime object. Every collection is passed
    /// in by the adapter so the assembly is platform-free and testable.
    static func assemble(
        executableSha256: String,
        menus: [Any],
        panels: [String: Any],
        scriptMessages: [String: Any],
        inputBindings: [Any],
        shaderNames: [String],
        scriptOptions: [String: Any],
        photonShaderLog: [String: [String]],
        partial: Bool
    ) -> [String: Any] {
        return [
            "schema": "feature-runtime/1 (arch-198k)",
            "partial": partial,
            "executable_sha256": executableSha256,
            "features": [
                "menus": menus,
                "panels": panels,
                "script_messages": scriptMessages,
                "input_bindings": inputBindings,
                "shader_names": shaderNames,
                "script_options": scriptOptions,
            ],
            "photon_shader_log": photonShaderLog,
            "photon_v4_replacement": photonV4ReplacementSection(executableSha256: executableSha256),
        ]
    }

    /// Deterministic JSON: sorted keys, pretty printed, trailing newline.
    static func jsonData(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        data.append(0x0A)
        return data
    }
}
