#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import CoreGraphics
import Foundation
import GorAVMacShell

// Gorav r15b isolated sink verification: real-sink playback entry point.
// Uses GorAVMacShellApp: NSWindow display sink + AudioUnit
// audio sink (never NullSink). The kit's unpacked copy carries disclosed
// telemetry counters (display upload count, audio render-callback real
// consumption). Actor isolation and nil-image skip are semantic changes.
// Only this isolated copy changes; original sources remain untouched.
// Native compilation and runtime were not performed before authoring:
// any compile error here is reported by the kit into the result file.
// Explicit NSApp.run() runloop on the main thread; async playback on a Task.
@main
struct SinkCheckMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: gorav-sink-check <videoPath> [audioPath|-] [holdSeconds]\n".utf8))
            Foundation.exit(2)
        }
        let video = args[1]
        let audio: String? = (args.count >= 3 && args[2] != "-") ? args[2] : nil
        let hold: Double = (args.count >= 4 ? Double(args[3]) : nil) ?? 5.0
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let summary: GorAVMacShellApp.ShellSummary
            do {
                summary = try await GorAVMacShellApp.run(videoPath: video, audioPath: audio)
            } catch {
                FileHandle.standardError.write(Data("GORAV_SINK_CHECK_ERROR: \(error)\n".utf8))
                Foundation.exit(1)
            }
            // AppKit isVisible and positive windowNumber during uploads only.
            // No system window-list lookup or pixel capture is performed.
            let onScreen = summary.visibleUploads > 0
            print("gorav sink check: windowOnScreen=\(onScreen ? 1 : 0)")
            print("gorav sink check telemetry: displayUploaded=\(summary.uploads) displayNoPixel=\(summary.noPixels) audioCallbackRealBytes=\(summary.audioConsumedBytes)")
            if hold > 0 {
                print("gorav sink check: playback finished, holding window \(Int(hold))s")
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            }
            Foundation.exit(0)
        }
        app.run()
    }
}
#else
import Foundation
@main
struct SinkCheckUnsupportedMain {
    static func main() {
        print("gorav-sink-check: real display/audio sinks require macOS (AppKit/CoreAudio); unsupported on this host")
        Foundation.exit(3)
    }
}
#endif
