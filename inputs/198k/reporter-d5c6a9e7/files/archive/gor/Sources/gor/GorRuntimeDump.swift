// ================================================================
//  GorRuntimeDump.swift - arch-198k in-app reporter, AppKit adapter
//  Owns: --gor-dump-runtime=<path> collection: NSApp.mainMenu walk,
//  live-panel inventory, mpv IPC reads (bindings / glsl-shaders /
//  script-opts), executable SHA256, photon shader warn/error capture
//  (arch-198l + Ops 198k review (c)), and runtime script-message
//  round-trip probes (Ops 198k review (1)): each probe sends a
//  harmless toggle over IPC and watches an IPC-visible witness
//  (user-data property flip or mpv log line), then restores the
//  original state. Handlers with no safe probe are reported UNPROBED
//  and stay out of features.script_messages. Pure assembly lives in
//  GorRuntimeDumpCore.swift. Contract: active only with the flag;
//  normal launch is untouched. macOS-only; Mac not verified here.
// ================================================================
#if canImport(AppKit)
import AppKit
import CryptoKit

final class GorRuntimeDump {
    static let outputPath = GorRuntimeDumpCore.outputPath(arguments: CommandLine.arguments)
    static let requested = outputPath != nil

    private static let lock = NSLock()
    /// Raw mpv stderr lines (pre-classification; classified at dump time).
    private static var mpvLines: [String] = []
    private static let mpvLinesCap = 4000
    private static var didRun = false

    static func recordMpvLine(_ line: String) {
        guard requested else { return }
        lock.lock()
        if mpvLines.count < mpvLinesCap { mpvLines.append(line) }
        lock.unlock()
    }

    private static func lineSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return mpvLines.count
    }

    private static func linesSince(_ mark: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard mpvLines.count > mark else { return [] }
        return Array(mpvLines[mark...])
    }

    static func install(ipcPath: String, configDir: String) {
        guard requested, !didRun else { return }
        DispatchQueue.global(qos: .utility).async {
            let shaderDir = configDir + "/shader"
            let markers = ["photon-chrome.glsl", "photon-grain.glsl"]
            var ready = false
            for _ in 0..<60 {
                let ipcUp = !IPCClient(path: ipcPath).queryBatch(#"{"command":["get_property","mpv-version"],"request_id":1}"# + "\n", timeout: 0.5).isEmpty
                let scriptsUp = markers.allSatisfy { FileManager.default.fileExists(atPath: shaderDir + "/" + $0) }
                if ipcUp && scriptsUp { ready = true; break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            if ready { Thread.sleep(forTimeInterval: 1.0) }  // settle: first PARAM pushes land
            let client = IPCClient(path: ipcPath)
            let probes = ready ? runProbes(client: client) : []
            collect(ipcPath: ipcPath, configDir: configDir, partial: !ready, probes: probes)
        }
    }

    // MARK: - runtime script-message probes (Ops 198k review (1))

    /// Probe witness kinds. propertyFlip: a user-data property's rendered
    /// value flips to a new non-nil value and later returns to the exact
    /// original. logMarkers: the mpv log gains the explicit enabled/on line
    /// on one leg and the explicit disabled/off line on the other (never
    /// "any marker twice"). stateSnapshot: target-peak, gamma or the
    /// glsl-shaders list changes, then returns to the exact original.
    private enum Witness {
        case propertyFlip(String)
        case logMarkers(on: String, off: String)
        case stateSnapshot
    }

    private struct ProbeSpec {
        let message: String
        let scriptTarget: String
        let witness: Witness
        /// Minimum seconds between the trigger and its restore message
        /// (photon-toggle has a 1.5s storm guard that ignores fast repeats).
        let restoreSpacing: Double
        let method: String
    }

    private static let probeSpecs: [ProbeSpec] = [
        ProbeSpec(message: "photon-chrome-toggle", scriptTarget: "photon_chrome",
                  witness: .propertyFlip("user-data/gor/chrome"), restoreSpacing: 0.3,
                  method: "toggle round-trip; witness user-data/gor/chrome string flip (handler writes it on every toggle)"),
        ProbeSpec(message: "photon-negativ-toggle", scriptTarget: "photon_negativ",
                  witness: .propertyFlip("user-data/gor/negativ"), restoreSpacing: 0.3,
                  method: "toggle round-trip; witness user-data/gor/negativ string flip (handler writes it on every toggle)"),
        ProbeSpec(message: "photon-bright-toggle", scriptTarget: "photon",
                  witness: .propertyFlip("user-data/adaptive-brightness-enabled"), restoreSpacing: 0.3,
                  method: "toggle round-trip; witness user-data/adaptive-brightness-enabled bool flip (handler set_property_native on every toggle)"),
        ProbeSpec(message: "photon-grain-toggle", scriptTarget: "photon_grain",
                  witness: .logMarkers(on: "photon-grain: enabled", off: "photon-grain: disabled"), restoreSpacing: 0.3,
                  method: "toggle round-trip; witness mp.msg.info 'photon-grain: enabled|disabled' in the mpv log stream"),
        ProbeSpec(message: "photon-sharp-toggle", scriptTarget: "photon_sharp",
                  witness: .logMarkers(on: "photon-sharp: on", off: "photon-sharp: off"), restoreSpacing: 0.3,
                  method: "toggle round-trip; witness mp.msg.info 'photon-sharp: on|off' in the mpv log stream"),
        ProbeSpec(message: "photon-toggle", scriptTarget: "photon",
                  witness: .stateSnapshot, restoreSpacing: 1.6,
                  method: "toggle round-trip; witness change in target-peak / gamma / glsl-shaders over IPC (handler body sets these; storm guard needs 1.6s spacing)"),
    ]

    private static func ipcGetAny(_ client: IPCClient, _ property: String) -> Any? {
        let payload = "{\"command\":[\"get_property\",\"" + property + "\"],\"request_id\":1}\n"
        guard let first = client.queryBatch(payload, timeout: 0.8).first,
              let obj = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return nil }
        return obj["data"]
    }

    private static func sendScriptMessage(_ client: IPCClient, target: String, message: String) {
        let payload = "{\"command\":[\"script-message-to\",\"" + target + "\",\"" + message + "\"],\"request_id\":1}\n"
        _ = client.queryBatch(payload, timeout: 0.8)
    }

    private static func stateSnapshotString(_ client: IPCClient) -> String {
        let peak = ipcGetAny(client, "target-peak").map { String(describing: $0) } ?? "nil"
        let gamma = ipcGetAny(client, "gamma").map { String(describing: $0) } ?? "nil"
        let shaders = (ipcGetAny(client, "glsl-shaders") as? [Any])?.compactMap { $0 as? String }.joined(separator: ",") ?? "nil"
        return peak + "|" + gamma + "|" + shaders
    }

    /// The value a witness leg must reach: the flipped state (any non-nil
    /// value different from the original) or the exact original on restore.
    private enum LegExpectation {
        case flippedFrom(String)
        case original(String)
        case logOn
        case logOff
    }

    /// Polls up to `seconds` for the witness to reach the expected state.
    /// Marks are captured BEFORE the send, so a synchronous effect is seen.
    private static func waitForWitness(_ client: IPCClient, witness: Witness, expect: LegExpectation, logMark: Int, seconds: Double) -> Bool {
        var waited = 0.0
        while waited < seconds {
            Thread.sleep(forTimeInterval: 0.25)
            waited += 0.25
            switch (witness, expect) {
            case (.propertyFlip(let property), .flippedFrom(let original)):
                guard let raw = ipcGetAny(client, property) else { continue }  // error-free reply required
                let now = String(describing: raw)
                if now != "nil", now != original { return true }
            case (.propertyFlip(let property), .original(let original)):
                guard let raw = ipcGetAny(client, property) else { continue }
                if String(describing: raw) == original { return true }
            case (.stateSnapshot, .flippedFrom(let original)):
                if stateSnapshotString(client) != original { return true }
            case (.stateSnapshot, .original(let original)):
                if stateSnapshotString(client) == original { return true }
            case (.logMarkers(let on, _), .logOn):
                if linesSince(logMark).contains(where: { $0.contains(on) }) { return true }
            case (.logMarkers(_, let off), .logOff):
                if linesSince(logMark).contains(where: { $0.contains(off) }) { return true }
            default:
                return false
            }
        }
        return false
    }

    private static func runProbes(client: IPCClient) -> [[String: Any]] {
        var results: [[String: Any]] = []
        for spec in probeSpecs {
            // Capture the witness BEFORE the send so a synchronous effect
            // cannot be missed (Ops review of 8cabab72).
            let mark1 = lineSnapshot()
            let original: String
            switch spec.witness {
            case .propertyFlip(let property):
                original = ipcGetAny(client, property).map { String(describing: $0) } ?? "nil"
            case .logMarkers:
                original = ""
            case .stateSnapshot:
                original = stateSnapshotString(client)
            }
            sendScriptMessage(client, target: spec.scriptTarget, message: spec.message)
            var flipped = false
            var wentOn = true  // which direction the flip leg took (log witnesses)
            switch spec.witness {
            case .propertyFlip, .stateSnapshot:
                flipped = waitForWitness(client, witness: spec.witness, expect: .flippedFrom(original), logMark: mark1, seconds: 3.0)
            case .logMarkers(let on, _):
                flipped = waitForWitness(client, witness: spec.witness, expect: .logOn, logMark: mark1, seconds: 3.0)
                if !flipped {
                    // The handler may have started enabled: look for the
                    // explicit disabled/off line in the same window.
                    flipped = waitForWitness(client, witness: spec.witness, expect: .logOff, logMark: mark1, seconds: 0.25)
                    wentOn = false
                }
                _ = on
            }
            Thread.sleep(forTimeInterval: spec.restoreSpacing)
            let mark2 = lineSnapshot()  // before the restore send
            sendScriptMessage(client, target: spec.scriptTarget, message: spec.message)
            let restored: Bool
            switch spec.witness {
            case .propertyFlip, .stateSnapshot:
                restored = waitForWitness(client, witness: spec.witness, expect: .original(original), logMark: mark2, seconds: 3.0)
            case .logMarkers:
                restored = waitForWitness(client, witness: spec.witness, expect: wentOn ? .logOff : .logOn, logMark: mark2, seconds: 3.0)
            }
            let result: String
            let detail: String
            if flipped && restored {
                result = "ATTESTED"
                detail = "handler fired on send and restore; witness reached the flipped state, then the exact original"
            } else if flipped {
                result = "FAILED"
                detail = "handler fired but the witness did not return to the original value"
            } else {
                result = "FAILED"
                detail = "no witness change within 3s of send"
            }
            results.append(GorRuntimeDumpCore.probeRecord(message: spec.message, method: spec.method, result: result, detail: detail))
        }
        return results
    }

    // MARK: - collection

    private static func collect(ipcPath: String, configDir: String, partial: Bool, probes: [[String: Any]]) {
        lock.lock()
        if didRun { lock.unlock(); return }
        didRun = true
        let lines = mpvLines
        lock.unlock()

        let client = IPCClient(path: ipcPath)
        func ipcGet(_ property: String) -> Any? { ipcGetAny(client, property) }

        // ── IPC reads ──
        let glslShaders = (ipcGet("glsl-shaders") as? [Any])?.compactMap { $0 as? String } ?? []
        let activeShaderNames = glslShaders.map { ($0 as NSString).lastPathComponent }
        let generatedShaders = ((try? FileManager.default.contentsOfDirectory(atPath: configDir + "/shader")) ?? [])
            .filter { $0.hasPrefix("photon") && $0.hasSuffix(".glsl") }.sorted()
        let allShaderNames = Array(Set(activeShaderNames + generatedShaders)).sorted()
        let scriptOptions = ipcGet("script-opts") as? [String: Any] ?? [:]
        let inputBindings: [Any] = {
            if let native = ipcGet("input-bindings") as? [Any], !native.isEmpty { return native }
            let confPath = configDir + "/input.conf"
            guard let text = try? String(contentsOfFile: confPath, encoding: .utf8) else { return [] }
            return GorRuntimeDumpCore.parseInputConf(text).map { $0 as [String: Any] }
        }()

        // ── Script messages: source scan is PROVENANCE ONLY (Ops 198k
        // review (1)): registered handlers enter features.script_messages
        // only via a runtime probe result of ATTESTED.
        let scriptsDir = configDir + "/scripts"
        var registered: Set<String> = []
        if let files = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir) {
            for file in files where file.hasSuffix(".lua") {
                if let source = try? String(contentsOfFile: scriptsDir + "/" + file, encoding: .utf8) {
                    registered.formUnion(GorRuntimeDumpCore.registeredScriptMessages(in: source))
                }
            }
        }
        var invoked: Set<String> = []
        if let text = try? String(contentsOfFile: configDir + "/input.conf", encoding: .utf8) {
            invoked.formUnion(GorRuntimeDumpCore.bindingMessageTargets(in: text))
        }
        let attested = probes.filter { ($0["result"] as? String) == "ATTESTED" }
            .compactMap { $0["message"] as? String }
        let probedNames = Set(probes.compactMap { $0["message"] as? String })
        var allProbes = probes
        for name in registered.sorted() where !probedNames.contains(name) {
            allProbes.append(GorRuntimeDumpCore.probeRecord(
                message: name, method: "none",
                result: "UNPROBED", detail: GorRuntimeDumpCore.unprobedReason(name)))
        }
        let unprobed = allProbes.filter { ($0["result"] as? String) == "UNPROBED" }
            .compactMap { $0["message"] as? String }

        // ── arch-198l + Ops (c): every shader-related warn/error line,
        // bucketed per shader when attributable, else "unattributed" ──
        var buckets: [String: [String]] = [:]
        for name in allShaderNames { buckets[name] = [] }
        for line in lines {
            GorRuntimeDumpCore.appendShaderLogLine(&buckets, line: line, shaderNames: allShaderNames)
        }
        let photonShaderLog = buckets.filter { !$0.value.isEmpty }

        // ── Executable identity ──
        var executableSha = "unavailable"
        if let exe = Bundle.main.executableURL, let bytes = try? Data(contentsOf: exe) {
            executableSha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }

        // ── Menus + live panels on the main thread ──
        DispatchQueue.main.sync {
            let menus = dumpMenuTree(NSApp.mainMenu)
            let livePanels = NSApp.windows.filter { $0 is NSPanel }.map { panel -> [String: Any] in
                [
                    "class": String(describing: type(of: panel)),
                    "title": panel.title,
                    "level": panel.level.rawValue,
                    "visible": panel.isVisible,
                ]
            }
            // Static panel class inventory: provenance only, never merged
            // with the live list (Ops 198k review (2)).
            let staticCatalog = [
                "URLPanel", "FileBrowserPanel", "MusicPanel", "IPTVPanel",
                "ArchiveBrowserPanel", "MagnetResultsPanel", "MagnetBrowserController",
                "SpineUI dropdown/HUD panels",
            ]
            let object = GorRuntimeDumpCore.assemble(
                executableSha256: executableSha,
                menuTree: menus,
                livePanels: livePanels,
                staticPanelCatalog: staticCatalog,
                attestedMessages: attested,
                unprobedMessages: unprobed,
                registeredScan: registered.sorted(),
                invokedScan: invoked.sorted(),
                probes: allProbes,
                inputBindingsRaw: inputBindings,
                activeShaderPaths: glslShaders,
                generatedShaderInventory: generatedShaders,
                scriptOptionsRaw: scriptOptions,
                photonShaderLog: photonShaderLog,
                partial: partial)
            write(object)
        }
    }

    private static func dumpMenuTree(_ menu: NSMenu?) -> [[String: Any]] {
        guard let menu else { return [] }
        return menu.items.map { item -> [String: Any] in
            var record: [String: Any] = [
                "title": item.title,
                "enabled": item.isEnabled,
                "separator": item.isSeparatorItem,
                "key_equivalent": item.keyEquivalent,
                "key_equivalent_modifier_mask": item.keyEquivalentModifierMask.rawValue,
                "tag": item.tag,
            ]
            if let action = item.action { record["action"] = NSStringFromSelector(action) }
            if let submenu = item.submenu { record["submenu"] = dumpMenuTree(submenu) }
            return record
        }
    }

    private static func write(_ object: [String: Any]) {
        guard let path = outputPath, let data = GorRuntimeDumpCore.jsonData(object) else {
            NSLog("[gor] runtime dump: assembly failed")
            return
        }
        let url = URL(fileURLWithPath: path)
        let tmp = url.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try data.write(to: tmp)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
            NSLog("[gor] runtime dump written: %@", path)
        } catch {
            NSLog("[gor] runtime dump write failed: %@", "\(error)")
        }
    }
}
#endif
