// Photon native check: compiles the CURRENT embedded projection MSL on the
// real device with the production compile options (fast math disabled), then
// instantiates the actual pass so lane-layout assertions run too. This is the
// current-source shader proof for the isolated Photon candidate; earlier
// diagnostic payloads are not reused as evidence.
#if canImport(Metal)
import Foundation
import Darwin
import Metal
import GorAVMetalPresenter

@main
struct StereoShaderCheckMain {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("NOT_RUN no Metal device on this host")
            exit(77)
        }
        print("device=\(device.name)")
        do {
            let options = MTLCompileOptions(); options.fastMathEnabled = false
            let library = try device.makeLibrary(source: StereoProjectionShader.source, options: options)
            let names = library.functionNames.sorted()
            print("PASS makeLibrary functions=\(names.joined(separator: ","))")
        } catch {
            let ns = error as NSError
            print("FAIL makeLibrary domain=\(ns.domain) code=\(ns.code): \(ns.localizedDescription)")
            exit(1)
        }
        do {
            _ = try StereoProjectionPass(device: device)
            print("PASS StereoProjectionPass init (lane layout assertions)")
        } catch {
            print("FAIL StereoProjectionPass init: \(error)")
            exit(1)
        }
    }
}
#else
@main
struct StereoShaderCheckMain {
    static func main() { print("NOT_RUN Metal unavailable (non-Darwin host)") }
}
#endif
