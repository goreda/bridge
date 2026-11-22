import Foundation
// S2 (A-D parity plan): CoreML-vs-torch per-package parity driver for the iw3-nunif-coreml kit.
// usage: nunif-parity <kitDir> <dumpDir>; <dumpDir> holds one <stem>.json manifest + <stem>/<name>.f32
// raw little-endian float32 (C order) per array, written by nunif_coreml_parity_test.py from the kit's
// *_fixture.npz. Prints one line per output: "<package> <output> maxabs <v> psnr <v>" (the S2 table).
// fp16 packages are expected to deviate; this driver posts numbers, it claims no pass threshold.
#if canImport(CoreML)
struct ParityArr: Decodable { var shape: [Int]?; var file: String }
struct ParityManifest: Decodable { var package: String; var inputs: [String: ParityArr]; var refs: [String: ParityArr] }
func loadF32(_ url: URL) -> [Float] { let d = try! Data(contentsOf: url); precondition(d.count % 4 == 0, "bad f32 \(url.lastPathComponent)"); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
let kitDir = URL(fileURLWithPath: CommandLine.arguments[1])
let dumpDir = URL(fileURLWithPath: CommandLine.arguments[2])
let runner = NunifCoreMLRunner(kitDir: kitDir)
for stem in try FileManager.default.contentsOfDirectory(atPath: dumpDir.path).filter({ $0.hasSuffix(".json") }).sorted() {
    let m = try JSONDecoder().decode(ParityManifest.self, from: Data(contentsOf: dumpDir.appendingPathComponent(stem)))
    let sub = dumpDir.appendingPathComponent(String(stem.dropLast(5)))
    var inputs: [String: (shape: [Int], values: [Float])] = [:]
    for (k, v) in m.inputs { let a = loadF32(sub.appendingPathComponent(v.file)); inputs[k] = (v.shape ?? [], a) }
    var refs: [String: [Float]] = [:]
    for (k, v) in m.refs { refs[k] = loadF32(sub.appendingPathComponent(v.file)) }
    guard let rows = runner.parity(package: m.package, inputs: inputs, refs: refs) else { print("\(m.package) RUN_FAIL"); continue }
    for r in rows { print("\(m.package) \(r.output) maxabs \(r.maxAbs) psnr \(r.psnr)") }
}
#else
print("NOT_RUN coreml-unavailable")
#endif
