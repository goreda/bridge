// Core station: source units below retain their complete non-lifted bytes.
import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import CoreImage
import CryptoKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import QuartzCore

// MARK: - GORResources.swift
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
//  Native-test staging (block 190m font repair): under XCTest ONLY, a
//  staged copy of the intended layout named by testResourceRootOverride
//  (default: GOR_TEST_RESOURCE_ROOT) is consulted AFTER the real
//  directories miss. The app process never loads XCTest, so production
//  resolution is unchanged; the native test host's Bundle.main is the
//  toolchain runner, never the app bundle, so without this hook the
//  intended layout is unresolvable there (run9/run10).
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

    /// Native-test harness override (block 190m font repair): honored
    /// ONLY when XCTest is loaded in the process - never in the app -
    /// and only after the real layouts miss. The harness stages the
    /// repo's actual Resources/fonts under this root; tests may re-point
    /// it directly for the deliberate-missing case.
    static var testResourceRootOverride: String? = ProcessInfo.processInfo.environment["GOR_TEST_RESOURCE_ROOT"]

    private static var isTestProcess: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    private static func testStagedDir(_ name: String) -> URL? {
        guard isTestProcess, let root = testResourceRootOverride,
              root.hasPrefix("/"), !root.contains("..") else { return nil }
        return realDirectory(URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true))
    }

    /// fonts/: bundle-internal real dir -> sibling external real dir.
    /// Miss: one explicit log per launch; PhotonFont falls back as before.
    static func fonts() -> URL? {
        if let r = releaseDir(fontsName) { return r }
        if let b = bundledDir(fontsName) { return b }
        if let e = externalDir(fontsName) { return e }
        if let t = testStagedDir(fontsName) { return t }
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
// MARK: - BuildID.swift

/// K8(b): build identity shown in About and written to the synced log at launch.
/// Source: <bundle>/Contents/Resources/build-id.txt, written by build.sh.
/// The legacy key is commit=, but its value is the SHA256 of the compiled
/// source manifest, not a Git commit. Keep the format backward compatible.
/// A missing, unreadable or malformed file never crashes the app: the value is
/// "unknown" and the log line is still written on every launch (no skipping).
enum BuildID {
    static let resourceName = "build-id"
    static let resourceExtension = "txt"
    static let unknown = "unknown"

    /// Pure parser (no I/O). Returns the source identity value, or nil when the text has
    /// no usable `commit=` line (empty value or value containing whitespace).
    static func parseCommit(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("commit=") else { continue }
            let value = String(line.dropFirst("commit=".count)).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return nil }
            return value
        }
        return nil
    }

    /// Value for display and log: the source identity, or "unknown".
    static func value(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let commit = parseCommit(text) else { return unknown }
        return commit
    }

    /// Pure parser (no I/O). Returns the delivered archive/gor tree sha, or nil when the
    /// text has no usable `tree=` line (must be exactly 40 lowercase hex chars).
    static func parseTree(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("tree=") else { continue }
            let value = String(line.dropFirst("tree=".count)).trimmingCharacters(in: .whitespaces)
            guard value.count == 40, value.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }) else { return nil }
            return value
        }
        return nil
    }

    /// Delivered archive/gor tree sha, or "unknown". Same never-crash contract as value().
    static func tree(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let tree = parseTree(text) else { return unknown }
        return tree
    }

    /// UTC launch timestamp for the launch line (ISO 8601, seconds precision).
    static func launchTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Exact launch log line: installed BuildID sha, archive/gor tree sha, launch time.
    /// One bounded ASCII line per launch; gor-periodic-capture carries it to the repo.
    static func launchLine(value: String, tree: String, at: Date = Date()) -> String {
        let safeValue = (value.isEmpty || value.contains(where: { $0.isWhitespace })) ? unknown : value
        let safeTree = (tree.isEmpty || tree.contains(where: { $0.isWhitespace })) ? unknown : tree
        return "[GOR] build-id \(safeValue) tree=\(safeTree) launch=\(launchTimestamp(at))"
    }

    /// Short form for the About label (7 chars of the source identity, else as-is).
    static func shortValue(_ value: String) -> String {
        value == unknown ? unknown : String(value.prefix(7))
    }
}
// MARK: - StableCacheKey.swift
// ================================================================
//  StableCacheKey.swift - shared stable SHA-1 hex cache key
//  Owns: sha1(_:)
//  Answers: I45
// ================================================================

enum StableCacheKey {
    // I45: stable SHA-1 of the key, never Swift hashValue
    static func sha1(_ string: String) -> String {
        Insecure.SHA1.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
// MARK: - SeededRandomNumberGenerator.swift
// ================================================================
//  SeededRandomNumberGenerator - deterministic random source
// ================================================================
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed = seed &* 0x9e3779b97f4a7c15 &+ 0xbf58476d1ce4e5b9
        return seed
    }
}
