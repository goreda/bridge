// ================================================================
//  main.swift - NSApp entry
//  Owns: activation policy (.accessory), AppDelegate handoff
// ================================================================
import AppKit

// 190l V1.1: no-UI boot check for the auto-update stager. dyld has already loaded every linked
// library to reach this line; exit before NSApplication exists. Not a selftest, starts no app instance.
if CommandLine.arguments.contains("--bootcheck") { exit(0) }
// X1 (190x): headless 3D self-test for the first-Mac kit; same exit-before-NSApplication shape as --bootcheck.
if let code = PrepareWorker.cli(arguments: CommandLine.arguments) { exit(code) }
if let code = KitCompiledCache.probeCLI(arguments: CommandLine.arguments) { exit(code) }
// arch-195z Z3 / arch-196b C6: same-executable camera helper; runs the
// capture session as a child process so a hung Apple stop can always be
// SIGKILLed by the parent (2 s stop deadline in CameraHelperClient).
if let code = CameraVisionWorkerCLI.cli(arguments: CommandLine.arguments) { exit(code) }
if let code = CameraHelperCLI.cli(arguments: CommandLine.arguments) { exit(code) }
if ThreeDSelfTestCLI.requested(arguments: CommandLine.arguments) { exit(ThreeDSelfTestCLI.run()) }

if let exe=Bundle.main.executableURL { PrepareProcessLifetime.reapOrphanedHelpers(executable:exe) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Explicit CI-only runtime mode. Normal launch remains unchanged.
// Top-level code is nonisolated; the gate delegate is MainActor-isolated.
// main.swift runs on the main thread before app.run(), so the assumption holds.
let delegate: NSApplicationDelegate = CommandLine.arguments.contains("--gorav-native-gate")
    ? MainActor.assumeIsolated { GorAVNativeGate() } : AppDelegate()
app.delegate = delegate
// native104 D-stage: --gorav-app-gate keeps the NORMAL AppDelegate (the C
// stage's NOT_RUN scope) and only installs its observation/control driver.
if CommandLine.arguments.contains("--gorav-app-gate"), let d = delegate as? AppDelegate {
    MainActor.assumeIsolated { GorAVAppGate.install(appDelegate: d) }
}
PermissionStateLog.logLaunch()  // 190l V1.3: passive, non-prompting permission states
app.run()
