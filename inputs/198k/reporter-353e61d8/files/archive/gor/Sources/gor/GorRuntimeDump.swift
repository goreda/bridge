// ================================================================
//  GorRuntimeDump.swift - arch-198k in-app reporter, AppKit adapter
//  Owns: --gor-dump-runtime=<path> collection: NSApp.mainMenu walk,
//  panel inventory, mpv IPC reads (script messages / bindings /
//  glsl-shaders / script-opts), executable SHA256, photon shader
//  warn/error capture (arch-198l: per-shader buckets, grain separate
//  from sharp). Pure assembly lives in GorRuntimeDumpCore.swift.
//  Contract: active only with the flag; normal launch is untouched.
//  macOS-only (AppKit); Mac not verified in this lane.
// ================================================================
#if canImport(AppKit)
import AppKit
import CryptoKit

final class GorRuntimeDump {
    static let outputPath = GorRuntimeDumpCore.outputPath(arguments: CommandLine.arguments)
    static let requested = outputPath != nil

    private static let lock = NSLock()
    /// Raw mpv stderr lines (pre-classification; classified at dump time so
    /// the bucket set can include every generated photon shader name).
    private static var mpvLines: [String] = []
    private static let mpvLinesCap = 2000
    private static var didRun = false

    /// Called from AppDelegate's mpv stderr line handler. Cheap when the
    /// flag is absent.
    static func recordMpvLine(_ line: String) {
        guard requested else { return }
        lock.lock()
        if mpvLines.count < mpvLinesCap { mpvLines.append(line) }
        lock.unlock()
    }

    /// Install after mpv launch. Polls until the player answers IPC and the
    /// photon scripts have written their load-time shaders, then dumps once.
    /// On timeout it dumps anyway with partial=true.
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
            collect(ipcPath: ipcPath, configDir: configDir, partial: !ready)
        }
    }

    private static func collect(ipcPath: String, configDir: String, partial: Bool) {
        lock.lock()
        if didRun { lock.unlock(); return }
        didRun = true
        let lines = mpvLines
        lock.unlock()

        let client = IPCClient(path: ipcPath)
        func ipcGet(_ property: String) -> Any? {
            let payload = "{\"command\":[\"get_property\",\"" + property + "\"],\"request_id\":1}\n"
            let replies = client.queryBatch(payload, timeout: 0.8)
            guard let first = replies.first,
                  let obj = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return nil }
            return obj["data"]
        }

        // ── IPC reads ──
        let glslShaders = (ipcGet("glsl-shaders") as? [Any])?.compactMap { $0 as? String } ?? []
        let shaderNames = glslShaders.map { ($0 as NSString).lastPathComponent }
        let generatedShaders = ((try? FileManager.default.contentsOfDirectory(atPath: configDir + "/shader")) ?? [])
            .filter { $0.hasPrefix("photon") && $0.hasSuffix(".glsl") }.sorted()
        let allShaderNames = Array(Set(shaderNames + generatedShaders)).sorted()
        let scriptOptions = ipcGet("script-opts") as? [String: Any] ?? [:]
        let inputBindings: [Any] = {
            if let native = ipcGet("input-bindings") as? [Any], !native.isEmpty { return native }
            let confPath = configDir + "/input.conf"
            guard let text = try? String(contentsOfFile: confPath, encoding: .utf8) else { return [] }
            return GorRuntimeDumpCore.parseInputConf(text).map { $0 as [String: Any] }
        }()

        // ── Script messages: the running scripts' registered names (the
        // scripts directory holds byte-exact what mpv loaded) plus the
        // script-message-to targets named by input bindings. mpv exposes no
        // registered-message enumeration over IPC; provenance is recorded.
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
        let scriptMessages: [String: Any] = [
            "registered": registered.sorted(),
            "invoked_in_bindings": invoked.sorted(),
            "source": "scripts-dir-scan+input.conf (mpv exposes no registered-message enumeration over IPC)",
        ]

        // ── arch-198l: per-shader warn/error buckets (grain vs sharp) ──
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

        // ── Menus + panels on the main thread ──
        DispatchQueue.main.sync {
            let menus = dumpMenuTree(NSApp.mainMenu)
            let panels = dumpPanels()
            let object = GorRuntimeDumpCore.assemble(
                executableSha256: executableSha,
                menus: menus,
                panels: panels,
                scriptMessages: scriptMessages,
                inputBindings: inputBindings,
                shaderNames: allShaderNames,
                scriptOptions: scriptOptions,
                photonShaderLog: photonShaderLog,
                partial: partial)
            write(object)
        }
    }

    private static func dumpMenuTree(_ menu: NSMenu?) -> [Any] {
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

    /// Panels: the live NSPanel instances plus the static inventory of the
    /// app's panel features (the app keeps no runtime panel registry; the
    /// catalog names the panel classes and their owners).
    private static func dumpPanels() -> [String: Any] {
        let live = NSApp.windows.filter { $0 is NSPanel }.map { panel -> [String: Any] in
            [
                "class": String(describing: type(of: panel)),
                "title": panel.title,
                "level": panel.level.rawValue,
                "visible": panel.isVisible,
            ]
        }
        return [
            "live": live,
            "available": [
                "URLPanel", "FileBrowserPanel", "MusicPanel", "IPTVPanel",
                "ArchiveBrowserPanel", "MagnetResultsPanel", "MagnetBrowserController",
                "SpineUI dropdown/HUD panels",
            ],
            "note": "no runtime panel registry exists; 'available' is the static class inventory, 'live' the open NSPanel instances at dump time",
        ]
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
