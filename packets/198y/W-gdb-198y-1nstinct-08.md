# W-gdb-198y-1nstinct-08
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/GORResources.swift -> GorPlatformMac. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-08",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GORResources.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/GORResources.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: GORResources, realDirectory, releaseDir, bundledDir, externalDir, conventionalDir, vendor, fonts, vendorRootPath, vendorPath, fontsPath, StagedPathPolicy",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py",
    "callee": "archive/gor/Sources/gor/GORResources.swift owning station GorPlatformMac"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.340156+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GORResources.swift",
        "block": "source1",
        "sha256": "d94c3244ba7adc4ef87d85e94d9de573950d770c2885073d978b17c6a19484ac"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-08.py",
        "block": "fixtures1",
        "sha256": "098ee841282de6ba781ccfea8cf2563c6359a8f9e98b5f0ddcf54f71a01e77e9"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "6c21928abb4056fc5582257ef2b67502b7c38a5ce5c90aa7368fbaf72e5093a3",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "ab63e2464cadd12fc0bccac44d97b291e919ec5492c1d541cf4cda950fcfa206"
  }
}
```

```swift id=source1
// ================================================================
//  GORResources - external asset resolution (block 174)
//  Owns: ONE lookup path for vendor/ and fonts/ across the two
//  supported layouts. Read-only; nothing here mutates state.
//
//  Layouts:
//   - daily build: gor.app sits at the project root; vendor/ and fonts/
//     live in <project root>/Resources/, the app bundle parent's sibling.
//   - DMG: vendor/ and fonts/ are real directories inside
//     Contents/Resources (copied in at DMG creation).
//  Real-directory checks only (lstat): a symlink is never accepted as the
//  layout - strict codesigning rejects out-of-bundle links, so the runtime
//  must not reintroduce them (owner-machine diagnostic, block 174 t1a).
//  Precedence vendor: bundle-internal real dir -> sibling external real
//  dir. The dev override (AppDelegate.devVendorRoot) is NOT applied here;
//  the sites that historically honored it keep calling it themselves.
//  Precedence fonts: bundle-internal real dir -> sibling external real
//  dir (fonts never derive from the dev override).
//  .gor-stage is not a runtime location: build.sh opens only the
//  installed app (r3 L1374, post-swap). gor.app.previous and
//  gor.app.instinct-* sit at the project root, so they resolve the same
//  sibling Resources/ as the installed app. The staged app and
//  .gor-stage/gor.app.last (r3 L417-420, L475-480) have .gor-stage/ as
//  their parent: no Resources sibling exists there, so a manual launch
//  from either resolves no assets and every consumer degrades with an
//  explicit log line (statically reviewed failure paths; no runtime
//  claim). .gor-stage/gor.app.last is a restore source only - the build
//  moves it back into place, it never opens it.
// ================================================================

import Foundation
import AVFoundation
import ApplicationServices
import CoreGraphics

enum GORResources {

    static let vendorName = "vendor"
    static let fontsName  = "fonts"

    /// The directory only when the final component is a REAL directory.
    /// A symlink as the layout itself is rejected; symlinked PARENTS
    /// (e.g. /tmp -> /private/tmp) are fine.
    private static func realDirectory(_ url: URL) -> URL? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return url
    }

    /// Auto-update release set (190l V1.4): staging writes one line into Contents/Resources/gor-resource-root
    /// before signing. It names <project>/.gor-autoupdate/releases/<sha40>. Only that exact shape is accepted;
    /// absent file = manual-update layout, unchanged.
    static func releaseDir(_ name: String) -> URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let marker = res.appendingPathComponent("gor-resource-root")
        var st = stat()
        guard lstat(marker.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let root = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = root.split(separator: "/", omittingEmptySubsequences: true)
        guard root.hasPrefix("/"), !root.contains(".."), comps.count >= 3,
              comps[comps.count - 2] == "releases", comps[comps.count - 3] == ".gor-autoupdate",
              comps[comps.count - 1].count == 40,
              comps[comps.count - 1].allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return realDirectory(URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(name, isDirectory: true))
    }

    /// Bundle-internal real directory (DMG layout).
    static func bundledDir(_ name: String) -> URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        return realDirectory(res.appendingPathComponent(name, isDirectory: true))
    }

    /// Sibling external directory: <bundle parent>/Resources/<name> (daily
    /// layout). The installed gor.app lives at the project root, so its
    /// parent is the project root.
    static func externalDir(_ name: String) -> URL? {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        return realDirectory(parent
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true))
    }

    /// The conventional daily-layout location, existence NOT guaranteed.
    /// Used to compose error paths / env values when resolution failed
    /// (the miss itself is already logged by vendor()/fonts()).
    static func conventionalDir(_ name: String) -> URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static var didLogVendorMiss = false
    private static var didLogFontsMiss  = false

    /// vendor/: release set (auto-update) -> bundle-internal real dir -> sibling external real dir.
    /// Miss: one explicit log per launch; callers degrade per feature.
    static func vendor() -> URL? {
        if let r = releaseDir(vendorName) { return r }
        if let b = bundledDir(vendorName) { return b }
        if let e = externalDir(vendorName) { return e }
        if !didLogVendorMiss {
            didLogVendorMiss = true
            NSLog("[GORResources] vendor unavailable: no real bundled or sibling Resources/vendor")
        }
        return nil
    }

    /// fonts/: bundle-internal real dir -> sibling external real dir.
    /// Miss: one explicit log per launch; PhotonFont falls back as before.
    static func fonts() -> URL? {
        if let r = releaseDir(fontsName) { return r }
        if let b = bundledDir(fontsName) { return b }
        if let e = externalDir(fontsName) { return e }
        if !didLogFontsMiss {
            didLogFontsMiss = true
            NSLog("[GORResources] fonts unavailable: no real bundled or sibling Resources/fonts")
        }
        return nil
    }

    /// Resolved vendor root path, or the conventional location when
    /// unresolved (callers keep their existing missing-file handling).
    static func vendorRootPath() -> String {
        (vendor() ?? conventionalDir(vendorName)).path
    }

    /// Resolved path for a file under vendor/, or its conventional
    /// location when vendor/ is unresolved.
    static func vendorPath(_ relative: String) -> String {
        (vendor() ?? conventionalDir(vendorName)).appendingPathComponent(relative).path
    }

    /// Resolved path for a file under fonts/, or its conventional
    /// location when fonts/ is unresolved.
    static func fontsPath(_ relative: String) -> String {
        (fonts() ?? conventionalDir(fontsName)).appendingPathComponent(relative).path
    }
}

// Staged selftest boundaries. The production id ignores every staging override.
struct StagedPathPolicy {
    let active: Bool
    let prefix: String?
    init(bundleID: String?, environment: [String: String]) {
        active = bundleID == "com.gokcebalkan.gor.staging"
        let raw = environment["GOR_STAGED_PATH_PREFIX"] ?? ""
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        prefix = active && raw.hasPrefix("/") && !raw.contains("..") &&
            raw.contains("/.gor-autoupdate/staging/") && url.resolvingSymlinksInPath().path == url.path ? url.path : nil
    }
    var valid: Bool { !active || prefix != nil }
    func temp(_ original: String) -> String {
        guard active else { return original }
        guard let prefix, original.hasPrefix("/tmp/") else { return "/dev/null" }
        return prefix + original
    }
    func home(_ original: URL) -> URL {
        guard active else { return original }
        return URL(fileURLWithPath: (prefix ?? "/dev/null") + "/home", isDirectory: true)
    }
}
enum StagedRunPaths {
    static let policy = StagedPathPolicy(bundleID: Bundle.main.bundleIdentifier, environment: ProcessInfo.processInfo.environment)
    static var active: Bool { policy.active }
    static var valid: Bool { policy.valid }
    static func tmp(_ original: String) -> String { active ? policy.temp(original) : SessionLogPaths.path(original) }
    static func home(_ original: URL) -> URL { policy.home(original) }
    static func support(_ original: URL) -> URL { active ? home(original).appendingPathComponent("Library/Application Support", isDirectory: true) : original }
    static func prepare() -> Bool {
        guard active else { return true }
        guard valid, let prefix = policy.prefix else { return false }
        for part in ["/tmp", "/home/Library/Logs/gor", "/home/Library/Application Support/gor", "/home/Downloads/gor-bbu", "/home/Downloads/gor-repo-sync", "/home/captures"] {
            do { try FileManager.default.createDirectory(atPath: prefix + part, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { return false }
        }
        return true
    }
}

/// 190l V1.3: one passive launch log line per permission gor really uses. Non-prompting reads only:
/// CGPreflightScreenCaptureAccess, AVCaptureDevice.authorizationStatus, AXIsProcessTrusted() without the prompt option.
/// Uses: Screen Recording/SCK + audio tap (ScreenCaptureEngine.swift:801-1324), camera (ScreenCaptureEngine.swift:2798,
/// Info.plist NSCameraUsageDescription build.sh:2454), CGEvent tap on keyDown (AppDelegate.swift:523, Accessibility/Input Monitoring).
/// The system-audio tap has no public preflight (ScreenCaptureEngine.swift:801-805), so it is logged as unavailable, not guessed.
enum PermissionStateLog {
    static func states() -> [(String, String)] {
        let camera: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = "granted"
        case .notDetermined: camera = "not-determined"
        case .denied: camera = "denied"
        case .restricted: camera = "restricted"
        @unknown default: camera = "unknown"
        }
        return [("screen_recording", CGPreflightScreenCaptureAccess() ? "granted" : "not-granted"),
                ("camera", camera),
                ("accessibility", AXIsProcessTrusted() ? "granted" : "not-granted"),
                ("system_audio_tap", "unavailable-no-public-preflight")]
    }
    static func logLaunch() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let mac = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        for (name, state) in states() {
            NSLog("[GORPermission] permission=%@ state=%@ macos=%@", name, state, mac)
        }
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/GORResources.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='d94c3244ba7adc4ef87d85e94d9de573950d770c2885073d978b17c6a19484ac', 'pinned source changed: rebase and review, never bless silently'
for token in ['GORResources', 'realDirectory', 'releaseDir', 'bundledDir', 'externalDir', 'conventionalDir', 'vendor', 'fonts', 'vendorRootPath', 'vendorPath', 'fontsPath', 'StagedPathPolicy']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='d94c3244ba7adc4ef87d85e94d9de573950d770c2885073d978b17c6a19484ac'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
